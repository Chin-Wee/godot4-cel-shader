extends RigidBody3D

# The existing MechAsset capsule provides the reference mass properties.
const Mech = preload("res://aerial/aerial_mech.gd")
const Flight = preload("res://aerial/flight_controller.gd")
const Allocator = preload("res://aerial/thruster_allocator.gd")
const Valve = preload("res://aerial/thruster_valve.gd")
const Servo = preload("res://aerial/pose_servo.gd")
const Poses = preload("res://aerial/poses/articulation_poses.gd")
const Profile = preload("res://aerial/mech_rig_profile.tres")
const BODY_MASS := 10000.0
const INERTIA_SI := Vector3(80833.34,26666.67,80833.34)
const UNITS := Flight.WORLD_UNITS_PER_METER
const LENGTH := 5.0
const WEIGHT := BODY_MASS*Flight.GRAVITY
const FIT_WEIGHTS := Vector2(250.0,80.0) # Moderate tracking weights for the constrained six-outlet fixture.
const MAIN_MOUNT_ORDER := [0,2,4,1,3,5] # Left backpack/calf/sole, then right.

var skeleton: Skeleton3D
var bone_ids := PackedInt32Array()
var bone_rest: Array[Quaternion] = []
var bone_axes: Array[Basis] = []
var valve_bases: Array[Basis] = []
var joints: Array = []
var valves: Array = []
var key := "Neutral_Flight"
var intensity := 1.0
var override_angles := PackedVector3Array()
var power := 1.0
var side_power := Vector2.ONE
var steer := Vector3.ZERO # Pilot pitch / yaw / roll.
var move := Vector3.ZERO # Chassis lateral / up / forward.
var brake := false
var requested_force := Vector3.ZERO
var requested_moment := Vector3.ZERO
var force := Vector3.ZERO
var moment := Vector3.ZERO
var outputs := PackedFloat32Array()
var side_output := Vector2.ZERO
var saturated := false
var ports: Array = []
var stress := 0.0
var correction_count := 0
var travel := Vector3.ZERO
var last_steer := Vector3.ZERO
var correction := PackedVector3Array()
var correction_left := 0.0

func configure(sk: Skeleton3D) -> void:
	skeleton = sk
	mass = BODY_MASS
	inertia = INERTIA_SI*UNITS*UNITS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	gravity_scale = Flight.GRAVITY*UNITS/float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	can_sleep = false
	collision_layer = 0
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 20
	capsule.height = 90
	shape.shape = capsule
	add_child(shape)
	for side in 2:
		for name in [Profile.thigh_bones[side],Profile.knee_bones[side],Profile.foot_bones[side]]:
			var id := sk.find_bone(name)
			bone_ids.append(id)
			bone_rest.append(sk.get_bone_rest(id).basis.get_rotation_quaternion())
			bone_axes.append(sk.get_bone_global_rest(id).basis.orthonormalized())
			joints.append(Servo.new())
	assert(MAIN_MOUNT_ORDER.size()==Profile.main_booster_max_thrust.size())
	for mount_index in MAIN_MOUNT_ORDER:
		var exhaust: Vector3 = Mech.MOUNTS[mount_index][3].normalized()
		assert(skeleton.find_bone(Mech.MOUNTS[mount_index][1])>=0,"Missing main outlet bone")
		valve_bases.append(Basis.looking_at(-exhaust,Vector3.UP))
		valves.append(Valve.new(Flight.HOT_IGNITION,Flight.HOT_RESTART,Flight.HOT_RESPONSE,Flight.HOT_RESPONSE,Flight.HOT_MINIMUM_ON))
		outputs.append(0.0)
	correction.resize(joints.size())
	reset_lab()

func reset_lab() -> void:
	transform = Transform3D.IDENTITY
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for valve in valves: valve.reset()
	outputs.fill(0.0)
	side_output = Vector2.ZERO
	correction.fill(Vector3.ZERO)
	travel = Vector3.ZERO
	last_steer = Vector3.ZERO
	force = Vector3.ZERO
	moment = Vector3.ZERO
	stress = 0.0
	correction_left = 0.0
	correction_count = 0
	set_pose(targets())

func targets() -> PackedVector3Array:
	if not override_angles.is_empty(): return override_angles
	if key!="Pilot_Blend":
		return Poses.blend(Poses.angles("Neutral_Flight"),Poses.angles(key),intensity,pow(intensity,2))
	var axis := requested_force.normalized()
	var local_travel := global_basis.inverse()*travel
	var reverse := brake and local_travel.length()>0.8
	var alignment := axis.dot(local_travel.normalized()) if not axis.is_zero_approx() else 1.0
	var reversing := 1.0 if reverse else maxf(0.0,-alignment)*smoothstep(0.08,0.5,force.length()/WEIGHT)
	return Poses.select(steer*intensity,move*intensity,maxf(power,side_output.length()/WEIGHT),reversing*intensity)

func set_pose(angles: PackedVector3Array) -> void:
	for i in joints.size(): joints[i].reset(Profile.limit_joint(angles[i],i/3,i%3))
	_apply_angles()
	ports = outlet_geometry()

func _apply_angles() -> void:
	# Same chassis-to-rest-bone rotation convention as FlightPose._rotate.
	for i in joints.size():
		var rest := bone_axes[i]
		var offset := rest.inverse()*Basis.from_euler(joints[i].value)*rest
		skeleton.set_bone_pose_rotation(bone_ids[i],(bone_rest[i]*offset.get_rotation_quaternion()).normalized())

func outlet_geometry() -> Array:
	var relative := global_transform.affine_inverse()*skeleton.global_transform
	var result := []
	for i in MAIN_MOUNT_ORDER.size():
		var mount_index: int = MAIN_MOUNT_ORDER[i]
		var mount: Array = Mech.MOUNTS[mount_index]
		var bone := skeleton.find_bone(mount[1])
		var segment := relative*skeleton.get_bone_global_pose(bone)
		var rating := Profile.main_booster_max_thrust[mount_index]
		result.append({"basis":(segment.basis*valve_bases[i]).orthonormalized(),
			"lever":segment*mount[2]/(UNITS*LENGTH), "cap":rating/WEIGHT})
	return result

func wrench_plan(geometry: Array, wanted_force: Vector3, wanted_moment: Vector3, cone := 0.0, dt := 0.0) -> Array[Vector3]:
	var available := []
	var seed := []
	for i in geometry.size():
		var cap: float = geometry[i].cap
		var cap_request := side_power[i/3] if power>0 else 0.0
		var off: float = valves[i].preview(0.0,dt)*cap if dt>0.0 else 0.0
		var minimum_request := minf(cap_request,Flight.HOT_IDLE_FLOW)
		var minimum: float = valves[i].preview(minimum_request,dt)*cap if dt>0.0 else minimum_request*cap
		var maximum: float = valves[i].preview(cap_request,dt)*cap if dt>0.0 else cap*cap_request
		available.append(geometry[i].merged({"cone":cone,"center":Vector3.ZERO,"gain":1.0,
			"minimum":minf(minimum,maximum),"maximum":maximum,"off":minimum if cap_request>0 else off,"fuel":0.0},true))
		seed.append(-geometry[i].basis.z*outputs[i]/WEIGHT)
	return Allocator.solve(available,wanted_force/WEIGHT,wanted_moment/(WEIGHT*LENGTH),Vector3.ZERO,seed,[],Allocator.SWEEPS,FIT_WEIGHTS)

func measure(plan: Array[Vector3], geometry: Array) -> Array[Vector3]:
	var total := Vector3.ZERO
	var torque := Vector3.ZERO
	for i in plan.size():
		total += plan[i]*WEIGHT
		torque += geometry[i].lever.cross(plan[i])*WEIGHT*LENGTH
	return [total,torque]

func tick(delta: float, authoring := false) -> void:
	var local_speed := global_basis.inverse()*linear_velocity/UNITS
	if local_speed.length()>0.8: travel = linear_velocity/UNITS
	var armed_motion := Vector3.UP+move
	if brake and travel.length()>0.8: armed_motion = -(global_basis.inverse()*travel).normalized()
	requested_force = armed_motion.limit_length(1.0+move.length())*WEIGHT*power
	# Same pilot axes, reference inertia and bounded angular acceleration as the flight controller.
	var wanted_rates := Flight.PILOT_AXES*(steer*Flight.MAX_RATE)
	var rate_error := wanted_rates-global_basis.inverse()*angular_velocity
	var angular_accel := (rate_error*Flight.RATE_GAIN).limit_length(Flight.MAX_ANGULAR_ACCELERATION)
	requested_moment = INERTIA_SI*angular_accel if power>0 else Vector3.ZERO
	var previous_residual := (requested_moment-moment)/(LENGTH*WEIGHT)
	var load := smoothstep(1.0,3.0,force.length()/WEIGHT)
	var air := smoothstep(18.0,70.0,local_speed.length())
	var reversal := maxf(0.0,-last_steer.dot(steer))
	var force_error := (requested_force-force).length()/WEIGHT
	var triggered := maxf(maxf(previous_residual.length(),0.4*force_error),reversal)
	stress = move_toward(stress,clampf(maxf(load,air*0.4)+triggered,0,1),delta*3.0)
	last_steer = steer
	var target := targets()
	if authoring: set_pose(target)
	else: _step_pose(target,delta)
	var steady := wrench_plan(ports,requested_force,requested_moment)
	var reachable := wrench_plan(ports,requested_force,requested_moment,0.0,delta)
	var actual: Array[Vector3] = []
	side_output = Vector2.ZERO
	for i in ports.size():
		var cap: float = ports[i].cap
		var cap_request := side_power[i/3] if power>0 else 0.0
		var command: float = valves[i].command_for(reachable[i].length()/cap,delta)
		# Prepare a useful valve during ignition even though its current reachable output is zero.
		if not valves[i].running and steady[i].length()>0.001: command = steady[i].length()/cap
		var input := clampf(command,minf(Flight.HOT_IDLE_FLOW,cap_request),cap_request)
		outputs[i] = valves[i].step(input,delta)*cap*WEIGHT
		side_output[i/3] += outputs[i]
		actual.append(-ports[i].basis.z*outputs[i]/WEIGHT)
	var measured := measure(actual,ports)
	force = measured[0]
	moment = measured[1]
	saturated = (force-requested_force).length()>WEIGHT*0.05 or (moment-requested_moment).length()>WEIGHT*LENGTH*0.015

func _step_pose(target: PackedVector3Array, delta: float) -> void:
	correction_left -= delta
	if key=="Pilot_Blend" and power>0 and stress>0.35 and correction_left<=0:
		_try_counterstroke()
		correction_left = lerpf(0.65,0.22,stress)
	elif key!="Pilot_Blend" or power<=0 or stress<0.25:
		correction.fill(Vector3.ZERO)
	for i in joints.size():
		var goal := Profile.limit_joint(target[i]+correction[i],i/3,i%3)
		joints[i].step(goal,delta,Profile.leg_response[i%3],Profile.joint_speed[i%3])
		joints[i].value = Profile.limit_joint(joints[i].value,i/3,i%3)
	_apply_angles()
	ports = outlet_geometry()

func _try_counterstroke() -> void:
	# Try a bounded ankle adjustment on the less-loaded foot. Keep it only
	# when the fixed-axis allocator predicts a lower wrench error.
	correction.fill(Vector3.ZERO)
	var ankle := 2 if side_output.x<side_output.y else 5
	var saved: Vector3 = joints[ankle].value
	var best := _wrench_error(ports)
	for axis in [Vector3.RIGHT,Vector3.LEFT,Vector3.BACK,Vector3.FORWARD]:
		joints[ankle].value = Profile.limit_joint(saved+axis*0.07*stress,ankle/3,2)
		_apply_angles()
		var error := _wrench_error(outlet_geometry())
		if error<best-0.001:
			best = error
			correction[ankle] = joints[ankle].value-saved
	if not correction[ankle].is_zero_approx(): correction_count += 1
	joints[ankle].value = saved

func _wrench_error(geometry: Array) -> float:
	var predicted := measure(wrench_plan(geometry,requested_force,requested_moment),geometry)
	return predicted[0].distance_to(requested_force)/WEIGHT+predicted[1].distance_to(requested_moment)/(WEIGHT*LENGTH)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if freeze or ports.is_empty(): return
	var basis := state.transform.basis.orthonormalized()
	for i in ports.size():
		var thrust: Vector3 = -ports[i].basis.z*outputs[i]
		state.apply_force(basis*thrust*UNITS,basis*ports[i].lever*(LENGTH*UNITS))
