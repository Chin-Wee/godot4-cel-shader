extends SkeletonModifier3D

# Uncharted 4's controlled secondary-motion layering: free arms anticipate
# steering, catch braking loads and lag/recover from chassis rotation.
const RigProfile = preload("res://aerial/mech_rig_profile.gd")
const Servo = preload("res://aerial/pose_servo.gd")
var profile: RigProfile
var hands: Array = []
var poles: Array = []
var hand_targets: Array[Marker3D] = []
var pole_targets: Array[Marker3D] = []
var finger_poses := {}
var finger_curl := 0.35
var ik: TwoBoneIK3D

func configure(player: AnimationPlayer, rig_profile: RigProfile) -> void:
	profile = rig_profile
	var sk := get_skeleton()
	# Sample only the supplied finger articulation, not its aiming/body pose.
	player.play(&"GunPose")
	player.advance(0.0)
	for index in sk.get_bone_count():
		var bone := sk.get_bone_name(index)
		if "Finger" in bone or "Thumb" in bone: finger_poses[index] = sk.get_bone_pose_rotation(index)
	player.stop()
	sk.reset_bone_poses()
	ik = TwoBoneIK3D.new()
	ik.name = "FreeArmIK"
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
	reset()

func reset() -> void:
	for side in 2:
		var sx := 1.0 if side==0 else -1.0
		hands[side].reset(profile.arm_hover*Vector3(sx,1,1))
		poles[side].reset(Vector3(sx*5.0,-1.0,1.0))

func set_weight(weight: float) -> void:
	for modifier in [self,ik]:
		modifier.active = weight>0.0001
		modifier.influence = weight

func update(delta: float, frame: Dictionary) -> void:
	finger_curl = clampf(0.30+frame.brake*0.25+frame.retro*0.35+absf(frame.roll)*0.15,0.2,0.85)
	for side in 2:
		var sx := 1.0 if side==0 else -1.0
		var base: Vector3 = profile.arm_hover.lerp(profile.arm_coast,frame.coast)
		base = base.lerp(profile.arm_stream,frame.stream)
		base = base.lerp(profile.arm_brake,frame.brake)
		base = base.lerp(profile.arm_retro,frame.retro)
		var hand := base*Vector3(sx,1,1)
		var inside := maxf(sx*frame.roll,0.0)
		var outside := maxf(-sx*frame.roll,0.0)
		# Inside arm gathers; outside arm reaches. Release opens the opposite side
		# to arrest remaining roll instead of instantly returning to neutral.
		hand += Vector3(sx*(-1.2*inside+0.65*outside)+frame.yaw*0.65-frame.roll_stop*0.55,
			inside*0.75-outside*0.25+frame.pitch*0.65,
			sx*frame.yaw*0.90-frame.pitch*0.85+frame.brake_rate*0.15)
		hand += Vector3(0,sx*absf(frame.roll)*frame.up.z*0.45,sx*absf(frame.roll)*frame.up.x*0.55)
		hand += frame.flow*frame.pressure*Vector3(0.30,0.25,0.55)
		hand += Vector3(-frame.acceleration.x*0.025,-frame.acceleration.y*0.012,-frame.acceleration.z*0.025).limit_length(0.8)
		hand += Vector3(sx*frame.trim.x,frame.trim.y*(0.65+side*0.25),frame.trim.z*sx)*profile.hover_arm_motion*frame.hover
		hands[side].follow(hand,delta,profile.arm_frequency+side*0.08,profile.arm_damping,profile.arm_speed)
		var pole := Vector3(sx*(5.0+frame.brake),-1.0+inside*0.5,1.0+frame.retro*1.2)
		poles[side].step(pole+Vector3(frame.yaw*0.3,0,0),delta,0.20,10.0)

func _process_modification() -> void:
	var sk := get_skeleton()
	for suffix in [".L",".R"]:
		for bone in ["UpperArm"+suffix+".001","LowerArm"+suffix]:
			var index := sk.find_bone(bone)
			sk.set_bone_pose_rotation(index,sk.get_bone_rest(index).basis.get_rotation_quaternion())
	for index in finger_poses:
		sk.set_bone_pose_rotation(index,sk.get_bone_pose_rotation(index).slerp(finger_poses[index],finger_curl))
	var torso := sk.get_bone_global_pose(sk.find_bone("Torso"))
	for side in 2:
		var target: Vector3 = torso*hands[side].value
		var shoulder := sk.get_bone_global_pose(ik.get_root_bone(side)).origin
		var middle := sk.get_bone_global_pose(ik.get_middle_bone(side)).origin
		var end := sk.get_bone_global_pose(ik.get_end_bone(side)).origin
		var reach := (shoulder.distance_to(middle)+middle.distance_to(end))*0.985
		var distance := shoulder.distance_to(target)
		var cushion := reach*0.15
		if distance>reach-cushion: distance = reach-cushion+cushion*(1.0-exp(-(distance-reach+cushion)/cushion))
		hand_targets[side].position = shoulder+(target-shoulder).normalized()*distance
		pole_targets[side].position = torso*poles[side].value
