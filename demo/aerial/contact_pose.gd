extends SkeletonModifier3D

# Uncharted 4's animation/contact layering, using Godot's native two-bone solve.
# ponytail: visual feet over one physical capsule; articulated suspension would
# require a separate gameplay physics change, not forces hidden inside this rig.
const RigProfile = preload("res://aerial/mech_rig_profile.gd")
const Servo = preload("res://aerial/pose_servo.gd")
enum Support { AIRBORNE, GROUNDED }
var profile: RigProfile
var body: RigidBody3D
var state := Support.AIRBORNE
var initialized := false
var unsupported_time := 0.0
var previous_velocity := Vector3.ZERO
var had_contact := false
var impact := 0.0
var touchdown_count := 0
var preparation := 0.0
var probe_count := 0
var pelvis := Servo.new()
var weights: Array = []
var planted := [false,false]
var plants := [Vector3.ZERO,Vector3.ZERO]
var normals := [Vector3.UP,Vector3.UP]
var last_world_plants := [Vector3.ZERO,Vector3.ZERO]
var last_world_normals := [Vector3.UP,Vector3.UP]
var platforms: Array = [null,null]
var hits: Array = [{},{}]
var targets: Array[Marker3D] = []
var poles: Array[Marker3D] = []
var solvers: Array[TwoBoneIK3D] = []
var alignment: SkeletonModifier3D

class Alignment extends SkeletonModifier3D:
	var owner_pose
	func _process_modification() -> void: owner_pose.align_soles()

func configure(mech: RigidBody3D, rig_profile: RigProfile) -> void:
	body = mech
	profile = rig_profile
	var sk := get_skeleton()
	for side in 2:
		weights.append(Servo.new())
		for markers in [targets,poles]:
			var marker := Marker3D.new()
			add_child(marker)
			markers.append(marker)
		var solver := TwoBoneIK3D.new()
		solver.name = "FootIK" + str(side)
		sk.add_child(solver)
		solver.set_setting_count(1)
		solver.set_root_bone_name(0,profile.thigh_bones[side])
		solver.set_middle_bone_name(0,profile.knee_bones[side])
		solver.set_end_bone_name(0,profile.foot_bones[side])
		solver.set_target_node(0,solver.get_path_to(targets[side]))
		solver.set_pole_node(0,solver.get_path_to(poles[side]))
		solver.set_pole_direction(0,SkeletonModifier3D.SECONDARY_DIRECTION_CUSTOM)
		solver.set_pole_direction_vector(0,Vector3(0,0,1))
		solvers.append(solver)
	alignment = Alignment.new()
	alignment.name = "SoleAlignmentAndPoseComplete"
	alignment.owner_pose = self
	sk.add_child(alignment)
	reset()

func reset() -> void:
	state = Support.AIRBORNE
	initialized = false
	unsupported_time = 0
	previous_velocity = Vector3.ZERO
	had_contact = false
	impact = 0
	touchdown_count = 0
	preparation = 0
	pelvis.reset()
	for side in 2:
		planted[side] = false
		platforms[side] = null
		weights[side].reset()
		solvers[side].influence = 0

func update(delta: float, controller) -> void:
	if delta <= 0: return
	var sk := get_skeleton()
	var upright := body.global_basis.y.dot(Vector3.UP) > 0.65
	var walking: bool = not body.flying
	var lifting: bool = controller.leg_force.length() > 1 or controller.velocity.y > 0.6
	probe_count = 0
	var near_ground: bool = upright and (walking or controller.grounded or (controller.time_to_impact < profile.landing_lead and controller.velocity.y < -0.5))
	for side in 2:
		hits[side] = {}
		if not near_ground: continue
		var index := sk.find_bone(profile.foot_bones[side])
		var foot: Transform3D = body.bone_poses.get(index,sk.get_bone_global_rest(index))
		var sole: Vector3 = sk.global_transform * (foot * profile.sole_offset)
		var ray := PhysicsRayQueryParameters3D.create(sole+Vector3.UP*body.display_scale*0.45,sole+Vector3.DOWN*body.display_scale*0.75,2)
		ray.exclude = [body.get_rid()]
		var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
		probe_count += 1
		if not hit.is_empty() and hit.normal.dot(Vector3.UP) > 0.65: hits[side] = hit
	# Ray hits alone can never claim support in flight. The walk demo is an
	# explicitly frozen preview; its feet may use the validated floor samples.
	var support: bool = upright and not lifting and (body.native_support or walking) and (not hits[0].is_empty() or not hits[1].is_empty())
	unsupported_time = 0.0 if support else unsupported_time+delta
	var next: int = Support.GROUNDED if support or (state == Support.GROUNDED and unsupported_time < 0.05 and not lifting) else Support.AIRBORNE
	if initialized and body.collided and not had_contact:
		impact = maxf(impact,clampf(-previous_velocity.y/18.0,0,1))
	if initialized and next == Support.GROUNDED and state == Support.AIRBORNE: touchdown_count += 1
	state = next
	initialized = true
	had_contact = body.collided
	previous_velocity = controller.velocity
	impact *= exp(-delta/0.24)
	preparation = (1.0-smoothstep(0.10,profile.landing_lead,controller.time_to_impact)) if near_ground and not support and (not hits[0].is_empty() or not hits[1].is_empty()) else 0.0
	if state == Support.GROUNDED: preparation = 1.0
	var phase := 0.0
	if walking:
		var player: AnimationPlayer = body.actor.animation_player
		phase = fposmod(player.current_animation_position/maxf(player.current_animation_length,0.001),1.0)
	for side in 2:
		var stance: bool = not walking or fposmod(phase+side*0.5,1.0) < profile.walk_stance_fraction
		var desired: bool = support and stance and not hits[side].is_empty()
		if desired and not planted[side]: _plant(side,hits[side])
		if not desired: planted[side] = false
		weights[side].step(Vector3(float(desired),0,0),delta,0.055 if lifting else profile.foot_response)
		var weight: float = weights[side].value.x
		solvers[side].influence = weight
		solvers[side].active = weight > 0.001
	var supported: float = maxf(weights[0].value.x,weights[1].value.x)
	pelvis.step(Vector3(0,-profile.ground_sink*supported-profile.impact_sink*impact,0),delta,0.14,1.5)

func _plant(side: int, hit: Dictionary) -> void:
	planted[side] = true
	var collider = hit.collider
	platforms[side] = weakref(collider) if collider is Node3D else null
	last_world_plants[side] = hit.position
	last_world_normals[side] = hit.normal
	plants[side] = collider.to_local(hit.position) if collider is Node3D else hit.position
	normals[side] = collider.global_basis.orthonormalized().inverse()*hit.normal if collider is Node3D else hit.normal

func plant_position(side: int) -> Vector3:
	var platform = platforms[side].get_ref() if platforms[side] != null else null
	if is_instance_valid(platform): last_world_plants[side] = platform.to_global(plants[side])
	return last_world_plants[side]

func plant_normal(side: int) -> Vector3:
	var platform = platforms[side].get_ref() if platforms[side] != null else null
	if is_instance_valid(platform): last_world_normals[side] = (platform.global_basis.orthonormalized()*normals[side]).normalized()
	return last_world_normals[side]

func foot_basis(side: int) -> Basis:
	var normal := plant_normal(side)
	var angle := acos(clampf(normal.dot(Vector3.UP),-1,1))
	if angle>profile.sole_tilt_limit: normal = Vector3.UP.slerp(normal,profile.sole_tilt_limit/angle)
	var forward := (-body.global_basis.z).slide(normal).normalized()
	if forward.is_zero_approx(): forward = Vector3.FORWARD.slide(normal).normalized()
	return Basis(forward.cross(normal).normalized(),forward,normal)

func _process_modification() -> void:
	var sk := get_skeleton()
	for side in 2:
		if not solvers[side].active: continue
		var target: Vector3 = plant_position(side)+plant_normal(side)*0.04-foot_basis(side)*profile.sole_offset*sk.global_basis.get_scale().x
		var local := sk.to_local(target)
		var hip := sk.get_bone_global_pose(sk.find_bone(profile.thigh_bones[side])).origin
		var a := sk.get_bone_global_rest(sk.find_bone(profile.thigh_bones[side])).origin
		var b := sk.get_bone_global_rest(sk.find_bone(profile.knee_bones[side])).origin
		var c := sk.get_bone_global_rest(sk.find_bone(profile.foot_bones[side])).origin
		var upper := a.distance_to(b)
		var lower := b.distance_to(c)
		var reach := (upper+lower)*0.985
		var minimum := sqrt(upper*upper+lower*lower+2*upper*lower*cos(profile.joint_max[1].x))
		var distance := clampf(hip.distance_to(local),minimum,reach)
		targets[side].position = hip+(local-hip).normalized()*distance
		poles[side].position = hip+Vector3(0,-2,5)

func align_soles() -> void:
	var sk := get_skeleton()
	for side in 2:
		var weight: float = weights[side].value.x
		if weight < 0.001: continue
		var index := sk.find_bone(profile.foot_bones[side])
		var parent := sk.get_bone_global_pose(sk.get_bone_parent(index)).basis
		var desired := sk.global_basis.orthonormalized().inverse()*foot_basis(side)
		var rotation := (parent.inverse()*desired).get_rotation_quaternion().normalized()
		sk.set_bone_pose_rotation(index,sk.get_bone_pose_rotation(index).slerp(rotation,weight))
