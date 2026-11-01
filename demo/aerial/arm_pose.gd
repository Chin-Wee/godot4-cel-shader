extends RefCounted

# Overgrowth reference: authored joint poses with directional corrections.
# Data for the single flight modifier, not another modifier/IK pass.
const Servo = preload("res://aerial/pose_servo.gd")
var profile
var upper: Array = []
var elbows: Array = []
var wrists: Array = []
var finger_poses := {}
var finger_curl := PackedFloat32Array([0.25,0.25])
# Completed, displayed geometry in torso space; never unsolved hand targets.
var hands := PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
var shoulders := PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
var elbow_positions := PackedVector3Array([Vector3.ZERO,Vector3.ZERO])

func configure(sk: Skeleton3D, player: AnimationPlayer, rig_profile) -> void:
	profile = rig_profile
	player.play(&"GunPose")
	player.advance(0.0)
	for index in sk.get_bone_count():
		if "Finger" in sk.get_bone_name(index) or "Thumb" in sk.get_bone_name(index):
			finger_poses[index] = sk.get_bone_pose_rotation(index)
	player.stop()
	sk.reset_bone_poses()
	for side in 2:
		upper.append(Servo.new())
		elbows.append(Servo.new())
		wrists.append(Servo.new())
	reset()

func reset() -> void:
	for side in 2:
		upper[side].reset(Vector3(profile.arm_hover.x,0,(1 if side==0 else -1)*profile.arm_hover.y))
		elbows[side].reset(Vector3(-profile.arm_hover.z,0,0))
		wrists[side].reset()
		finger_curl[side] = 0.25

func update(delta: float, frame: Dictionary) -> void:
	var pose: Vector3 = profile.arm_hover*frame.hover+profile.arm_coast*(frame.coast+frame.fall+frame.land)+profile.arm_stream*frame.fighter
	pose = pose.lerp(profile.arm_stream,frame.track)
	pose = pose.lerp(profile.arm_box,frame.box)
	pose = pose.lerp(profile.arm_drive,frame.get("drive",0.0))
	pose = pose.lerp(profile.arm_prepare,frame.get("prepare",0.0)*0.35)
	pose = pose.lerp(profile.arm_retro,frame.retro)
	# One full-body flare wins over the reverse brace instead of being starved
	# of blend weight. Steering is applied afterward, including during freefall.
	pose = pose.lerp(profile.arm_brake,frame.get("flare",frame.brake))
	pose = pose.lerp(profile.arm_land,frame.land)
	var steer: Vector3 = frame.steer
	var slip: Vector3 = frame.get("slip",Vector3.ZERO)
	var flare: float = frame.get("flare",frame.brake)
	var balance: Vector3 = frame.acceleration*Vector3(-1,1,-1)*clampf(frame.g_load,0,1)
	var move: Vector3 = frame.get("translate",Vector3.ZERO)
	for side in 2:
		var sx := 1.0 if side==0 else -1.0
		var bias: float = sx*frame.get("lead",1.0)*(0.06+frame.get("asymmetry",0.0)*0.18)*(1-frame.land)
		var swing: float = pose.x+sx*steer.y*0.48-steer.x*0.28+slip.x*sx*0.12
		var spread: float = pose.y-sx*steer.z*0.36+bias
		var flex: float = pose.z+sx*steer.y*0.34+sx*steer.z*0.24-bias
		# AC VI-style directional slides: arms trail forward thrust, catch reverse
		# thrust and take different inside/outside roles during lateral movement.
		swing += move.z*0.24+sx*move.x*0.14
		spread += absf(move.z)*0.10+sx*move.x*0.16
		flex += absf(move.z)*0.12+sx*move.x*0.16
		swing += clampf(balance.z*0.006,-0.08,0.08)+frame.trim.y*frame.hover*0.06
		spread += clampf(-sx*balance.x*0.006,-0.08,0.08)+sx*frame.trim.x*frame.hover*0.07
		flex += sx*frame.trim.z*frame.hover*0.06
		# External rotation bends the forearms toward the head. Raising the whole
		# arm instead creates a straight scarecrow silhouette with forward hands.
		var twist: float = (-sx*profile.arm_box_twist+steer.y*0.18+steer.z*0.10)*frame.box
		upper[side].step(Vector3(clampf(swing,-0.8,1.1),twist,sx*clampf(spread,0.18,2.15)),delta,0.30,profile.arm_speed)
		elbows[side].step(Vector3(-clampf(flex,0.12,1.6),0,0),delta,0.34,profile.arm_speed)
		wrists[side].step(Vector3(-frame.box*0.18-flare*0.18,0,sx*(steer.y*0.15+steer.z*0.10)),delta,0.24,1.0)
		var curl: float = clampf(0.25-flare*0.15-frame.box*0.10+frame.retro*(0.35+bias)+frame.get("drive",0.0)*0.1,0.05,0.85)
		finger_curl[side] = move_toward(finger_curl[side],curl,delta*2.0)

func apply(sk: Skeleton3D, rotate: Callable, weight := 1.0) -> void:
	for side in 2:
		var angles: Vector3 = upper[side].value
		rotate.call(profile.arm_roots[side],Vector3(angles.x,0,angles.z))
		# Twist about the actual humerus, after positioning the upper arm. A
		# skeleton-space yaw would move the elbow instead of changing its hinge.
		var shoulder: int = sk.find_bone(profile.arm_roots[side])
		sk.set_bone_pose_rotation(shoulder,(sk.get_bone_pose_rotation(shoulder)*Quaternion(Vector3.UP,angles.y*weight)).normalized())
		rotate.call(profile.arm_middles[side],elbows[side].value)
		rotate.call(profile.arm_ends[side],wrists[side].value)
	for index in finger_poses:
		var side := 1 if ".R" in sk.get_bone_name(index) else 0
		sk.set_bone_pose_rotation(index,sk.get_bone_pose_rotation(index).slerp(finger_poses[index],finger_curl[side]*weight))

func sample_completed(sk: Skeleton3D, completed: Dictionary) -> void:
	var torso: Transform3D = completed[sk.find_bone("Torso")].affine_inverse()
	for side in 2:
		hands[side] = torso*completed[sk.find_bone(profile.arm_ends[side])].origin
		shoulders[side] = torso*completed[sk.find_bone(profile.arm_roots[side])].origin
		elbow_positions[side] = torso*completed[sk.find_bone(profile.arm_middles[side])].origin
