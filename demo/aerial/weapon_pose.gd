extends SkeletonModifier3D

# Titanfall 2 pilot intent / Gears 5 low-ready and braced weapon presentation.
# This modifier places targets. Native arm IK solves next; Alignment finishes
# wrists and publishes the actual muzzle after that solve.
const RigProfile = preload("res://aerial/mech_rig_profile.gd")
const Servo = preload("res://aerial/pose_servo.gd")
const Controller = preload("res://aerial/flight_controller.gd")
var profile: RigProfile
var readiness := Servo.new()
var support := Servo.new()
var recoil := Servo.new()
var hands: Array = []
var poles: Array = []
var hand_targets: Array[Marker3D] = []
var pole_targets: Array[Marker3D] = []
var finger_poses := {}
var ik: TwoBoneIK3D
var alignment: SkeletonModifier3D
var smoothed_aim := Vector3.FORWARD
var aim_up := Vector3.UP
var muzzle := Transform3D.IDENTITY
var barrel_direction := Vector3.FORWARD
var barrel_axis := Vector3.UP
var muzzle_local := Vector3.ZERO
var top_axis := Vector3.BACK
var support_offset := Vector3.ZERO
var support_rotation := Basis.IDENTITY
var support_weight := 0.0

class Alignment extends SkeletonModifier3D:
	var owner_pose
	func _process_modification() -> void: owner_pose.finish_pose()

func configure(player: AnimationPlayer, rig_profile: RigProfile) -> void:
	profile = rig_profile
	var sk := get_skeleton()
	player.play(&"GunPose")
	player.advance(0.0)
	var right := sk.get_bone_global_pose(sk.find_bone(profile.arm_ends[1]))
	var left := sk.get_bone_global_pose(sk.find_bone(profile.arm_ends[0]))
	support_rotation = right.basis.inverse() * left.basis
	for index in sk.get_bone_count():
		var bone := sk.get_bone_name(index)
		if "Finger" in bone or "Thumb" in bone: finger_poses[index] = sk.get_bone_pose_rotation(index)
	player.stop()
	sk.reset_bone_poses()
	ik = TwoBoneIK3D.new()
	ik.name = "ArmIK"
	sk.add_child(ik)
	ik.set_setting_count(2)
	for side in 2:
		hands.append(Servo.new())
		poles.append(Servo.new())
		for targets in [hand_targets,pole_targets]:
			var marker := Marker3D.new()
			add_child(marker)
			targets.append(marker)
		ik.set_root_bone_name(side,profile.arm_roots[side])
		ik.set_middle_bone_name(side,profile.arm_middles[side])
		ik.set_end_bone_name(side,profile.arm_ends[side])
		ik.set_target_node(side,ik.get_path_to(hand_targets[side]))
		ik.set_pole_node(side,ik.get_path_to(pole_targets[side]))
		ik.set_pole_direction(side,SkeletonModifier3D.SECONDARY_DIRECTION_CUSTOM)
		ik.set_pole_direction_vector(side,Vector3(0,0,-1))
	alignment = Alignment.new()
	alignment.name = "WeaponAlignment"
	alignment.owner_pose = self
	sk.add_child(alignment)
	var gun: MeshInstance3D = sk.find_child("GUN",false,false)
	for bind in gun.skin.get_bind_count():
		if gun.skin.get_bind_name(bind) == &"Hands.R":
			var transform := gun.skin.get_bind_pose(bind)
			barrel_axis = (transform.basis * Vector3.DOWN).normalized()
			top_axis = (transform.basis * Vector3.BACK).normalized()
			support_offset = transform * profile.receiver_point
			muzzle_local = transform * profile.muzzle_point
	reset()

func reset() -> void:
	for spring in [readiness,support,recoil]: spring.reset()
	for side in 2:
		hands[side].reset(profile.hand_guard if side == 0 else profile.rifle_low_ready)
		poles[side].reset(Vector3(4.5,-1.1,1.5) if side == 0 else Vector3(-4.7,-1.4,-2.1))
	support_weight = 0.0

func set_weight(weight: float) -> void:
	for modifier in [self,ik,alignment]:
		modifier.active = weight > 0.0001
		modifier.influence = weight

func update(delta: float, frame: Dictionary) -> void:
	var ready := readiness.step(Vector3(float(frame.aiming),0,0),delta,0.18).x
	var kickback := recoil.step(Vector3.ZERO,delta,0.10).x
	var sk := get_skeleton()
	var aim: Vector3 = sk.global_basis.inverse() * frame.aim
	var yaw := atan2(aim.x,aim.z)
	var flow: Vector3 = frame.flow * frame.pressure
	for side in 2:
		var guard := profile.hand_guard.lerp(profile.free_hand_spread,frame.spread) + flow * Vector3(0.35,0.2,0.4) + Vector3(-frame.side_load*0.35,frame.compression*0.2,0)
		var raised := profile.rifle_raised + aim.normalized() * (0.4-kickback)
		var low_ready := profile.rifle_low_ready.lerp(profile.rifle_stream_ready,frame.stream)
		var target := guard if side == 0 else low_ready.lerp(raised,ready)
		hands[side].step(target,delta,0.20 if side == 0 else profile.weapon_response,12.0)
		var pole := Vector3(4.5,-1.1,1.5) if side == 0 else Vector3(-4.7,-1.4,-2.1)
		poles[side].step(pole+flow*0.15,delta,0.20,10.0)
	var demand := ready * (1.0-smoothstep(deg_to_rad(30),deg_to_rad(65),absf(yaw)))
	support.step(Vector3(demand,0,0),delta,0.15)
	var wrist: Vector3 = sk.global_transform * sk.get_bone_global_rest(sk.find_bone("Torso")) * hands[1].value
	# Project before parallax correction so an exactly rearward look cannot swap
	# between the equally close left/right limits because of wrist displacement.
	var target: Vector3 = frame.position + frame.aim * frame.position.distance_to(frame.gaze_target)
	var direction := Controller.limit_aim_in_frame((target-wrist).normalized(),frame.aim_basis)
	var low: Vector3 = frame.aim_basis * Vector3(0,-0.7,-1).normalized()
	var desired := low.lerp(direction,ready).normalized()
	var rotation := Quaternion(smoothed_aim.normalized(),desired)
	var angle := rotation.get_angle()
	var amount := minf(1.0-exp(-delta/profile.weapon_response),3.0*delta/maxf(angle,0.0001))
	smoothed_aim = (Quaternion.IDENTITY.slerp(rotation,amount)*smoothed_aim).normalized()
	aim_up = frame.aim_basis * Vector3.UP

func kick() -> void: recoil.velocity.x += 12.0

func hand_basis() -> Basis:
	var sk := get_skeleton()
	var desired := (sk.global_basis.inverse()*smoothed_aim).normalized()
	var up := (sk.global_basis.inverse()*aim_up).normalized()
	if absf(desired.dot(up)) > 0.98: up = desired.cross(Vector3.RIGHT if absf(desired.x)<0.9 else Vector3.FORWARD).normalized()
	return Basis.looking_at(-desired,up)*Basis.looking_at(-barrel_axis,top_axis).inverse()

func _process_modification() -> void:
	var sk := get_skeleton()
	for suffix in [".L",".R"]:
		for bone in ["UpperArm"+suffix+".001","LowerArm"+suffix]:
			var index := sk.find_bone(bone)
			sk.set_bone_pose_rotation(index,sk.get_bone_rest(index).basis.get_rotation_quaternion())
	for index in finger_poses:
		var weight := 1.0 if ".R" in sk.get_bone_name(index) else support.value.x
		sk.set_bone_pose_rotation(index,sk.get_bone_pose_rotation(index).slerp(finger_poses[index],weight))
	var torso := sk.get_bone_global_pose(sk.find_bone("Torso"))
	for side in 2:
		var target: Vector3 = torso * hands[side].value
		var shoulder := sk.get_bone_global_pose(ik.get_root_bone(side)).origin
		var middle := sk.get_bone_global_pose(ik.get_middle_bone(side)).origin
		var end := sk.get_bone_global_pose(ik.get_end_bone(side)).origin
		var reach := (shoulder.distance_to(middle)+middle.distance_to(end))*0.985
		var distance := shoulder.distance_to(target)
		var cushion := reach*0.15
		if distance > reach-cushion: distance = reach-cushion+cushion*(1.0-exp(-(distance-reach+cushion)/cushion))
		hand_targets[side].position = shoulder+(target-shoulder).normalized()*distance
		pole_targets[side].position = torso*poles[side].value
	var contact := Transform3D(hand_basis(),hand_targets[1].position)*support_offset
	var shoulder := sk.get_bone_global_pose(ik.get_root_bone(0)).origin
	var a := sk.get_bone_global_rest(ik.get_root_bone(0)).origin
	var b := sk.get_bone_global_rest(ik.get_middle_bone(0)).origin
	var c := sk.get_bone_global_rest(ik.get_end_bone(0)).origin
	var reach := a.distance_to(b)+b.distance_to(c)
	support_weight = support.value.x*(1.0-smoothstep(reach*0.90,reach*0.985,shoulder.distance_to(contact)))
	hand_targets[0].position = hand_targets[0].position.lerp(contact,support_weight)

func finish_pose() -> void:
	var sk := get_skeleton()
	var index := sk.find_bone(profile.arm_ends[1])
	var hand := sk.get_bone_global_pose(index)
	hand.basis = hand_basis()
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(index)).basis
	sk.set_bone_pose_rotation(index,(parent.inverse()*hand.basis).get_rotation_quaternion().normalized())
	muzzle = sk.global_transform*Transform3D(hand.basis,hand.origin+hand.basis*muzzle_local)
	barrel_direction = (sk.global_basis*hand.basis*barrel_axis).normalized()
	var offhand := sk.find_bone(profile.arm_ends[0])
	var off_parent := sk.get_bone_global_pose(sk.get_bone_parent(offhand)).basis
	var desired := (off_parent.inverse()*hand.basis*support_rotation).get_rotation_quaternion().normalized()
	sk.set_bone_pose_rotation(offhand,sk.get_bone_pose_rotation(offhand).slerp(desired,support_weight))
