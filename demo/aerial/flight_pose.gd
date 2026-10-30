extends SkeletonModifier3D

# Hathaway / skydiver silhouettes and Titanfall 2 pilot intent. Architecture:
# Uncharted 4's authored intent + controlled secondary motion + contact layers.
const RigProfile = preload("res://aerial/mech_rig_profile.gd")
const Spring = preload("res://aerial/pose_servo.gd")
const ArmPose = preload("res://aerial/arm_pose.gd")
const ContactPose = preload("res://aerial/contact_pose.gd")
@export var profile: RigProfile = preload("res://aerial/mech_rig_profile.tres")
var blend := Spring.new()
var chest := Spring.new()
var hips := Spring.new()
var head := Spring.new()
var com := Spring.new()
var legs: Array = []
var arms: SkeletonModifier3D
var contacts: SkeletonModifier3D
var bones := {}
var clock := 0.0
var root_angles := Vector3.ZERO
# hover, streamlined, spread, coast, landing; normalized, never flight modes.
var posture_weights := PackedFloat32Array([1,0,0,0,0])
var motion := {}
var last_brake := 0.0

func configure(player: AnimationPlayer, mech: RigidBody3D) -> void:
	var sk := get_skeleton()
	for bone in Array(profile.torso_bones)+Array(profile.thigh_bones)+Array(profile.knee_bones)+Array(profile.foot_bones)+["Neck","ShoulderJoint.L","ShoulderJoint.R"]:
		var index := sk.find_bone(bone)
		assert(index >= 0,"Missing procedural mech bone: "+str(bone))
		bones[bone] = index
	for joint in 6: legs.append(Spring.new())
	arms = ArmPose.new()
	arms.name = "ManeuverArmTargets"
	sk.add_child(arms)
	arms.configure(player,profile)
	contacts = ContactPose.new()
	contacts.name = "FootTargets"
	sk.add_child(contacts)
	contacts.configure(mech,profile)
	reset()

func reset() -> void:
	for spring in [chest,hips,head,com]: spring.reset()
	blend.reset(Vector3(1,0,0))
	root_angles = Vector3.ZERO
	for side in 2:
		for joint in 3: legs[side*3+joint].reset(profile.leg_target(PackedFloat32Array([1,0,0,0,0]),side,joint))
	arms.reset()
	last_brake = 0.0
	contacts.reset()

func set_weight(weight: float) -> void:
	active = weight > 0.0001
	influence = weight
	arms.set_weight(weight)
	# Feet also operate over the retained ground-walk preview. Their final
	# modifier always publishes the completed pose/hardpoints, even at zero IK.

func update(delta: float, controller) -> void:
	clock = controller.clock
	contacts.update(delta,controller)
	motion = _sample_motion(controller,delta)
	_choose_posture(controller)
	motion["spread"] = posture_weights[2]
	motion["stream"] = posture_weights[1]
	motion["hover"] = posture_weights[0]
	motion["coast"] = posture_weights[3]
	motion["brake"] = posture_weights[2]
	motion.make_read_only()
	_update_body(delta)
	_update_legs(delta,controller)
	arms.update(delta,motion)

func _sample_motion(controller, delta: float) -> Dictionary:
	var basis := Basis(controller.attitude)
	var pilot: Basis = controller.pilot_frame()
	var flow: Vector3 = controller.local_airflow*Vector3(-1,1,-1)
	var pressure := clampf(0.5*controller.air_density*flow.length_squared()/3000.0,0,1)
	var omega: Vector3 = basis.inverse()*controller.angular_velocity
	var alpha: Vector3 = basis.inverse()*controller.angular_acceleration
	var pilot_rates: Vector3 = pilot.inverse()*controller.angular_velocity
	var intent: Vector3 = controller.rotation_command
	var body_intent: Vector3 = basis.inverse()*pilot*intent
	var load := clampf((controller.g_load-1.0)/3.0,0,1.2)
	var acceleration: Vector3 = controller.local_acceleration
	var compression := clampf(load*0.75+alpha.length()*0.028+clampf(-acceleration.z/30.0,0,1)*0.25+contacts.impact*0.4,0,1.3)
	var speed: float = controller.velocity.length()
	# Retro means delivered thrust opposing existing travel, not a throttle cut
	# or a velocity rewrite. Gravity and aerodynamic braking stay independent.
	var retro: float = maxf(0,-controller.main_force.normalized().dot(controller.velocity.normalized()))*smoothstep(2,12,speed)*smoothstep(0.1,0.8,controller.engine_level)
	var brake_rate := clampf((controller.brake_amount-last_brake)/delta,-3,3) if delta>0 else 0.0
	last_brake = controller.brake_amount
	var roll_stop := clampf(pilot_rates.z/1.2-intent.z,-1,1)*(1.0-absf(intent.z))
	# Active hover trim is a slow weight-transfer cycle. Opposed thigh/knee
	# offsets keep the lower-leg thrust axes nearly parallel while arms balance.
	var trim := Vector3(sin(clock*0.95)+0.25*sin(clock*1.83),sin(clock*0.73+1.4),sin(clock*0.84+0.8))
	return {"flow":flow.normalized(),"pressure":pressure,"omega":omega,"alpha":alpha,
		"acceleration":acceleration,"compression":compression,"g_load":controller.g_load,
		"side_load":clampf(acceleration.x/22.0,-1,1),"pitch":intent.x,"yaw":intent.y,
		"roll":clampf(intent.z*0.7+pilot_rates.z/1.2*0.3,-1,1),"roll_stop":roll_stop,
		"body_intent":body_intent,"up":basis.inverse()*Vector3.UP,"trim":trim,
		"retro":retro,"brake_rate":brake_rate}

func _choose_posture(controller) -> void:
	var landing: float = contacts.preparation
	var spread: float = maxf(controller.brake_amount,controller.departure*motion.pressure*0.55)*(1.0-landing)
	var remaining := 1.0-landing-spread
	var stream: float = controller.aero_authority*clampf(controller.engine_level,0,1)*remaining
	var hover: float = controller.hover_assist*(remaining-stream)
	posture_weights = PackedFloat32Array([hover,stream,spread,remaining-stream-hover,landing])

func _update_body(delta: float) -> void:
	var omega: Vector3 = motion.omega
	var alpha: Vector3 = motion.alpha
	var acceleration: Vector3 = motion.acceleration
	var intent: Vector3 = motion.body_intent
	var lag := Vector3(omega.x*0.11+alpha.x*0.01,omega.y*0.07,omega.z*0.11+alpha.z*0.01)
	lag += Vector3(acceleration.z*0.004,-acceleration.x*0.002,-acceleration.x*0.005)
	var brace := Vector3(motion.brake*0.12+motion.retro*0.16,0,motion.side_load*0.06)
	var anticipation := intent*Vector3(0.075,0.09,0.11)
	var hover: Vector3 = Vector3(motion.trim.z*0.015,motion.trim.x*0.018,motion.trim.y*0.012)*motion.hover
	hips.step((-anticipation*0.25+lag*0.35+hover).limit_length(0.09),delta,0.14,0.8)
	root_angles = hips.value*Vector3(-1,1,1)
	var displacement := Vector3(-acceleration.x*0.004,-clampf(motion.g_load-1,-1,3)*0.025,acceleration.z*0.004)
	displacement += Vector3(motion.trim.x*0.012,motion.trim.y*0.008,0)*motion.hover
	com.step(displacement.limit_length(0.16),delta,0.16,1.0)
	chest.follow((lag+anticipation+brace-hover*0.5).limit_length(0.24),delta,profile.body_frequency,profile.body_damping,2.0)
	# Head leads the maneuver and counter-rolls slightly; mouse look never
	# imposes a weapon-facing pose on the torso or either arm.
	head.step(Vector3(intent.x*0.10,intent.y*0.18,-chest.value.z*0.55),delta,0.10,3.0)

func _update_legs(delta: float, controller) -> void:
	var flow: Vector3 = motion.flow*motion.pressure
	var omega: Vector3 = motion.omega
	var compression: float = motion.compression
	var jump := clampf(controller.leg_force.length()/maxf(controller.body.mass*9.81*4,1),0,1)
	# Preserve feasible calibrated anchors. When physical vectoring is already
	# at its cone, reduce extra load/airflow articulation rather than bend jets.
	var articulation := lerpf(1.0,0.35,clampf(controller.engine_level,0,1)*float(controller.motor_saturated))
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var brace := clampf(sx*motion.side_load+omega.z*0.25,-1,1)
		var extras := [Vector3(flow.z*profile.leg_airflow_gain-compression*0.32+brace*0.22,-flow.x*0.22+omega.y*0.12,-flow.x*0.28-motion.side_load*0.12+sx*compression*0.10),
			Vector3(0.85*compression+brace*0.28-jump*0.35,0,0),Vector3(-compression*0.30-brace*0.15,-flow.x*0.12,0)]
		var hover_shift: float = sx*motion.trim.x*profile.hover_leg_motion*motion.hover
		var steer: float = sx*(motion.roll*0.18+motion.yaw*0.12)*profile.maneuver_leg_motion/0.22
		extras[0] += Vector3(steer-motion.retro*(0.22+sx*0.10),motion.yaw*sx*0.06,0)
		extras[1] += Vector3(-steer*0.65+motion.retro*(0.34-sx*0.10)+motion.brake_rate*0.04,0,0)
		extras[2] += Vector3(-motion.retro*0.12,0,motion.roll_stop*0.06)
		for joint in 3:
			var target: Vector3 = profile.leg_target(posture_weights,side,joint)+extras[joint]*articulation
			if joint==0: target.x += hover_shift
			if joint==1: target.x -= hover_shift
			target = profile.limit_joint(target,side,joint)
			var servo = legs[side*3+joint]
			servo.step(target,delta,profile.leg_response[joint]+side*0.025,profile.joint_speed[joint])
			servo.value = profile.limit_joint(servo.value,side,joint)

func _rotate(bone: String, angles: Vector3) -> void:
	var sk := get_skeleton()
	var index: int = bones[bone]
	var rest := sk.get_bone_global_rest(index).basis.orthonormalized()
	var offset := rest.inverse()*Basis.from_euler(angles)*rest
	sk.set_bone_pose_rotation(index,(sk.get_bone_pose_rotation(index)*offset.get_rotation_quaternion()).normalized())

func _process_modification() -> void:
	var difference := chest.value-hips.value
	for part in profile.torso_bones.size(): _rotate(profile.torso_bones[part],difference*Vector3(1,1,-1)*profile.torso_weights[part])
	_rotate("Neck",head.value)
	for side in 2:
		_rotate(profile.thigh_bones[side],legs[side*3].value)
		_rotate(profile.knee_bones[side],legs[side*3+1].value)
		_rotate(profile.foot_bones[side],legs[side*3+2].value)
		_rotate("ShoulderJoint.L" if side==0 else "ShoulderJoint.R",Vector3(0,arms.hands[side].value.z*0.025*(1 if side==0 else -1),0))
