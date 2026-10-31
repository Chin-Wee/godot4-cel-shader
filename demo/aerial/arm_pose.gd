extends SkeletonModifier3D

# Uncharted 4's intent/secondary-motion layering, with skydiver body-flight
# shapes and deliberate start-coast-stop shoulder/elbow strokes.
const RigProfile = preload("res://aerial/mech_rig_profile.gd")
const Servo = preload("res://aerial/pose_servo.gd")
var profile: RigProfile
var hands: Array = []
var poles: Array = []
var wrists: Array = []
var hand_targets: Array[Marker3D] = []
var pole_targets: Array[Marker3D] = []
var finger_poses := {}
var finger_curl := 0.35
var ik: TwoBoneIK3D
var palms: SkeletonModifier3D

# Same post-IK modifier pattern as contact_pose.Alignment. Rotating the end
# joint articulates the wrist without disturbing the solved hand position.
class PalmPose extends SkeletonModifier3D:
	var owner_pose
	func _process_modification() -> void:
		var sk := get_skeleton()
		for side in 2:
			var index: int = owner_pose.ik.get_end_bone(side)
			var offset := Basis.from_euler(owner_pose.wrists[side].value).get_rotation_quaternion()
			sk.set_bone_pose_rotation(index,(sk.get_bone_pose_rotation(index)*offset).normalized())

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
		wrists.append(Servo.new())
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
		# Preserve the imported elbow hinge/twist. A generic pole axis and lateral
		# pole rolled the shoulder armor outward even with a lowered hand target.
		var root := sk.get_bone_global_rest(ik.get_root_bone(side)).origin
		var middle := sk.get_bone_global_rest(ik.get_middle_bone(side))
		var end := sk.get_bone_global_rest(ik.get_end_bone(side)).origin
		var bend := (middle.origin-root).slide((end-root).normalized())
		bend = bend.slide((end-middle.origin).normalized()).normalized()
		ik.set_pole_direction_vector(side,middle.basis.inverse()*bend)
	palms = PalmPose.new()
	palms.name = "FreeWristArticulation"
	palms.owner_pose = self
	sk.add_child(palms)
	reset()

func reset() -> void:
	for side in 2:
		var sx := 1.0 if side==0 else -1.0
		hands[side].reset(profile.arm_hover*Vector3(sx,1,1))
		poles[side].reset(profile.arm_elbow_pole*Vector3(sx,1,1))
		wrists[side].reset()

func set_weight(weight: float) -> void:
	for modifier in [self,ik,palms]:
		modifier.active = weight>0.0001
		modifier.influence = weight

func update(delta: float, frame: Dictionary) -> void:
	finger_curl = clampf(0.25-frame.box*0.15-frame.brake*0.10+frame.retro*0.45+absf(frame.roll)*0.15,0.1,0.85)
	for side in 2:
		var sx := 1.0 if side==0 else -1.0
		var base: Vector3 = profile.arm_hover*frame.hover+profile.arm_stream*frame.fighter+profile.arm_coast*(frame.coast+frame.fall+frame.land)
		base = base.lerp(profile.arm_stream,frame.track)
		base = base.lerp(profile.arm_box,frame.box)
		base = base.lerp(profile.arm_brake,frame.brake)
		base = base.lerp(profile.arm_retro,frame.retro)
		base = base.lerp(profile.arm_land,frame.land)
		var hand := base*Vector3(sx,1,1)
		var style: Vector3 = profile.hover_stroke*frame.hover+profile.fighter_stroke*frame.fighter+profile.coast_stroke*frame.coast+profile.fall_stroke*frame.fall
		var steer: Vector3 = frame.steer*style
		var inside := maxf(sx*steer.z,0.0)
		var outside := maxf(-sx*steer.z,0.0)
		# Deliberate body flight: roll gathers one arm and opens the other; yaw
		# presses one shoulder/forearm into the air; pitch reaches or tucks both.
		# Commanded strokes work before any airflow, load or rotation appears.
		hand += Vector3(sx*(-1.1*inside+0.8*outside)+steer.y*0.35,
			inside*1.1-outside*0.8+steer.x*1.25,
			sx*steer.y*1.35+steer.x*0.65+sx*steer.z*0.85+frame.brake_rate*0.15)
		hand += Vector3(0,sx*absf(frame.roll)*frame.up.z*0.45,sx*absf(frame.roll)*frame.up.x*0.55)
		hand += frame.flow*frame.pressure*Vector3(0.20,0.15,0.35)
		var gather: float = frame.coast*minf(frame.steer.length(),1)
		hand += Vector3(-sx*0.35,0.6,0.35)*gather
		hand += Vector3(sx*frame.gyro.z*0.25,-frame.gyro.x*0.2,sx*frame.gyro.y*0.35)*frame.hover
		hand += Vector3(sx*0.25,0.45,0.3)*frame.launch
		# Body -Z forward becomes source +Z forward. Arms trail changes in
		# momentum, then the existing spring catches and recovers them. Freefall
		# has no supported load to throw the arms up against gravity.
		var source_acceleration: Vector3 = frame.acceleration*Vector3(-1,1,-1)
		var source_alpha: Vector3 = frame.alpha*Vector3(-1,1,-1)
		var balance := -source_acceleration*profile.arm_balance_gain*clampf(frame.g_load,0,1)
		balance -= source_alpha.cross(Vector3(sx*0.65,-0.4,0.2))*0.18
		balance = balance.limit_length(0.75)
		hand += balance+Vector3(sx*absf(balance.x)*0.3,absf(balance.x)*0.5+absf(balance.z)*0.2,0)
		hand += Vector3(sx*frame.trim.x,frame.trim.y*(0.65+side*0.25),frame.trim.z*sx)*profile.hover_arm_motion*frame.hover
		# Comfortable hand workspace prevents load response crossing the chest.
		hand.x = sx*clampf(sx*hand.x,1.8,5.8)
		if absf(hand.x)<2.6: hand.z = maxf(hand.z,1.4) # Gather in front of the chest armor.
		hand.y = clampf(hand.y,-3.2,4.0)
		hand.z = clampf(hand.z,-1.8,3.8)
		hands[side].follow(hand,delta,profile.arm_frequency+side*0.08,profile.arm_damping,profile.arm_speed)
		# Relaxed elbows stay near the ribs. Body flight widens them into a box,
		# while steering presses the same calibrated hinge without a plane flip.
		var pole := profile.arm_elbow_pole*Vector3(sx,1,1)
		pole = pole.lerp(profile.arm_box_pole*Vector3(sx,1,1),frame.box)
		pole += Vector3(sx*(frame.brake*0.8+outside*0.3),inside*0.2,frame.retro*0.5)
		pole += Vector3(sx*(-inside*0.25+outside*0.55),steer.x*0.3,sx*steer.y*1.15+sx*steer.z*0.5)
		poles[side].step(pole,delta,0.12,12.0)
		var wrist := Vector3(-frame.box*0.20-frame.brake*0.12+steer.x*0.12,0,sx*(steer.y*0.18+steer.z*0.12))
		wrists[side].step(wrist.clamp(Vector3(-0.35,-0.2,-0.25),Vector3(0.35,0.2,0.25)),delta,0.14,2.0)

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
