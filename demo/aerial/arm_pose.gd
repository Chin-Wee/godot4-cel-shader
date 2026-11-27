extends RefCounted

# Overgrowth reference: authored joint poses with directional corrections.
# Data for the single flight modifier, not another modifier/IK pass.
const Poses = preload("res://aerial/poses/articulation_poses.gd")
const Servo = preload("res://aerial/pose_servo.gd")
var profile
var upper: Array = []
var elbows: Array = []
var wrists: Array = []
var finger_poses := {}
var digits := {}
var authored_hands := false
var grip_noise := FastNoiseLite.new()
var finger_curl := PackedFloat32Array([0.25,0.25])
# Completed, displayed geometry in torso space; never unsolved hand targets.
var hands := PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
var shoulders := PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
var elbow_positions := PackedVector3Array([Vector3.ZERO,Vector3.ZERO])

func configure(sk: Skeleton3D, player: AnimationPlayer, rig_profile) -> void:
	profile = rig_profile
	grip_noise.seed = 407
	grip_noise.frequency = 0.54
	grip_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	player.play(&"GunPose")
	player.advance(0.0)
	for index in sk.get_bone_count():
		var name := sk.get_bone_name(index)
		var finger := name.begins_with("Finger")
		if not finger and not name.begins_with("Thumb"): continue
		finger_poses[index] = sk.get_bone_pose_rotation(index)
		var number := name.get_slice(".",0).trim_prefix("Finger").trim_prefix("Thumb").to_int()-1
		var side := int(name.ends_with(".R"))
		var joint := number%3
		var digit := number/3
		var scale: float = (0.80+0.12*digit)*[1.08,1.0,0.67][joint] if finger else 0.59
		var spread := Vector3.ZERO
		if finger and joint==0:
			var palm := sk.get_bone_global_rest(sk.find_bone(profile.arm_ends[side])).basis
			var knuckle := sk.get_bone_global_rest(index).basis
			spread = (knuckle.inverse()*palm.x).normalized()*(1.0-2.0*digit/3.0)
		digits[index] = {"side":side,"delay":0.015+0.007*(digit+joint),"scale":scale,
			"spread":spread,"fan":0.0,"curl":0.25,"phase":float(digit)*2.7+float(side)*17.3}
	player.stop()
	sk.reset_bone_poses()
	for side in 2:
		upper.append(Servo.new())
		elbows.append(Servo.new())
		wrists.append(Servo.new())
	reset()

func reset(authored := false) -> void:
	hands = PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
	shoulders = PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
	elbow_positions = PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
	for side in 2:
		var sx := 1.0 if side==0 else -1.0
		var pose := Poses.arm_key("Neutral_Straight",side) if authored else Vector4(profile.arm_hover.x,0,profile.arm_hover.y,profile.arm_hover.z)
		upper[side].reset(Vector3(pose.x,pose.y*sx,pose.z*sx))
		elbows[side].reset(Vector3(-pose.w,0,0))
		wrists[side].reset()
		finger_curl[side] = 0.25
	for digit in digits.values():
		digit.curl = 0.25
		digit.fan = 0.0
	authored_hands = false

func update(delta: float, frame: Dictionary) -> void:
	authored_hands = frame.get("authored",false)
	if authored_hands:
		_update_articulation(delta,frame)
		return
	var structural_arms: PackedVector4Array = frame.get("mechanical_arms",PackedVector4Array())
	var structural_wrists: PackedVector3Array = frame.get("mechanical_wrists",PackedVector3Array())
	var structural_grip: float = float(frame.get("mechanical_grip",0.0))
	var pose: Vector3 = profile.arm_hover*frame.hover+profile.arm_coast*(frame.coast+frame.fall+frame.land)+profile.arm_stream*frame.fighter
	pose = pose.lerp(profile.arm_stream,frame.track)
	pose = pose.lerp(profile.arm_box,frame.get("belly",frame.box))
	pose = pose.lerp(profile.arm_back,frame.get("back",0.0))
	pose = pose.lerp(profile.arm_drive,frame.get("drive",0.0))
	pose = pose.lerp(profile.arm_prepare,frame.get("prepare",0.0)*0.70)
	pose = pose.lerp(profile.arm_retro,frame.retro)
	# One full-body flare wins over the reverse brace instead of being starved
	# of blend weight. Steering is applied afterward, including during freefall.
	pose = pose.lerp(profile.arm_brake,frame.get("flare",frame.brake))
	pose = pose.lerp(profile.arm_land,frame.land)
	var ground_run: float = frame.get("ground_run",0.0)
	var ground_guard: float = frame.get("ground_guard",0.0)
	pose = pose.lerp(Vector3(0.28,0.22,0.95),ground_run)
	pose = pose.lerp(Vector3(0.18,0.42,1.25),ground_guard)
	# Forearm pressure opposes the desired rotation at the moving side: the
	# resulting air force supplies the turn, rather than flaring against it.
	var steer: Vector3 = frame.steer*Vector3(1,-1,-1)
	var clean: float = frame.fighter*(1.0-frame.get("flare",frame.brake))*(1.0-maxf(frame.get("drive",0.0),frame.retro))
	var turn: Vector3 = frame.get("brake_turn",Vector3.ZERO)*Vector3(1,-1,-1)
	var slip: Vector3 = frame.get("slip",Vector3.ZERO)
	var flare: float = frame.get("flare",frame.brake)
	var balance: Vector3 = frame.acceleration*Vector3(-1,1,-1)*clampf(frame.g_load,0,1)
	var move: Vector3 = frame.get("reach",Vector3.ZERO)
	for side in 2:
		var sx := 1.0 if side==0 else -1.0
		var bias: float = sx*frame.get("lead",1.0)*(0.06+frame.get("asymmetry",0.0)*0.18)*(1-frame.land)
		var swing: float = pose.x+(sx*steer.y*0.52-steer.x*0.28+slip.x*sx*0.12)*lerpf(1.0,0.25,clean)
		var spread: float = pose.y-sx*steer.z*lerpf(0.36,0.08,clean)+bias*(1.0-clean*0.7)
		var flex: float = pose.z+(sx*steer.y*0.34+sx*steer.z*0.45-bias)*lerpf(1.0,0.3,clean)
		swing += ground_guard*(-0.52 if side==0 else 0.16)
		flex += ground_guard*(0.32 if side==0 else 0.14)
		var ground_swing: int = int(frame.get("ground_swing",0))
		var run_role := 1.0 if side != ground_swing else -1.0
		swing += ground_run*run_role*sin(float(frame.get("ground_phase",0.0))*PI)*0.16
		# Armored Core VI directional combat-turn silhouette: the outside armor
		# catches wind while the inside arm gathers. Pitch presents both panels.
		swing += turn.x*0.55+sx*turn.y*0.40
		spread += sx*turn.z*0.50-sx*turn.y*0.50-sx*steer.y*0.10*clean
		flex += -turn.x*0.35-sx*turn.z*0.45-sx*turn.y*0.35
		# AC VI-style directional slides: arms trail forward thrust, catch reverse
		# thrust and take different inside/outside roles during lateral movement.
		swing += move.z*0.42+sx*move.x*0.26
		spread += absf(move.z)*0.14+sx*move.x*0.26
		flex += absf(move.z)*0.22+sx*move.x*0.22
		var acro: Vector2 = frame.get("acro",Vector2.ZERO)
		var signs: Vector2 = frame.get("acro_sign",Vector2.ZERO)
		var flip: Vector3 = frame.get("flip_shape",Vector3.ZERO)
		var roll: Vector3 = frame.get("roll_shape",Vector3.ZERO)
		var front: float = maxf(-signs.x,0.0)
		var back: float = maxf(signs.x,0.0)
		# Backward reach becomes a row toward the ribs; forward flip sweeps aft,
		# folds tightly and reaches out. Independent hands preserve lead roles.
		var flip_swing: float = (front*0.75-back*0.70)*flip.x-0.12*flip.y-0.45*flip.z
		var flip_spread: float = 0.65*flip.x+0.24*flip.y+1.10*flip.z
		var flip_flex: float = 0.35*flip.x+1.50*flip.y+0.65*flip.z
		var layout: float = frame.get("layout",0.0)
		flip_spread = lerpf(flip_spread,0.85+0.25*flip.z,layout)
		flip_flex = lerpf(flip_flex,0.30+0.35*flip.z,layout)
		var bank: float = sx*frame.get("bank_gesture",0.0)
		swing += bank*0.16
		spread += bank*0.12
		flex += bank*0.20
		var roll_side: float = sx*signs.y
		var pitch_weight: float = acro.x*lerpf(1.0,0.65,flare)
		swing = swing*(1.0-pitch_weight)+flip_swing*pitch_weight
		spread = spread*(1.0-pitch_weight)+flip_spread*pitch_weight
		flex = flex*(1.0-pitch_weight)+flip_flex*pitch_weight
		swing += acro.y*(roll_side*0.35*roll.x-roll_side*0.25*roll.y-roll_side*0.20*roll.z)
		spread += acro.y*(-0.22*roll.y+roll_side*0.30*roll.x+0.45*roll.z)
		flex += acro.y*(0.65*roll.y+roll_side*0.25*(roll.x-roll.z))
		swing -= steer.x*0.28*acro.x # Keep active air-control pressure through flips.
		swing += acro.x*sx*frame.get("lead",1.0)*0.10*(flip.x+flip.z)
		flex += acro.x*sx*frame.get("lead",1.0)*0.12*flip.x
		if structural_arms.size()==2:
			var mechanical_arm: Vector4 = structural_arms[side]
			swing += mechanical_arm.x
			twist += mechanical_arm.y
			spread += mechanical_arm.z
			flex += mechanical_arm.w
		swing += clampf(balance.z*0.006,-0.08,0.08)+frame.trim.y*frame.hover*0.06
		spread += clampf(-sx*balance.x*0.006,-0.08,0.08)+sx*frame.trim.x*frame.hover*0.07
		flex += sx*frame.trim.z*frame.hover*0.06
		# External rotation bends the forearms toward the head. Raising the whole
		# arm instead creates a straight scarecrow silhouette with forward hands.
		var twist: float = (-sx*profile.arm_box_twist+steer.y*0.18+steer.z*0.10)*frame.get("belly",frame.box)-sx*profile.arm_back_twist*frame.get("back",0.0)
		spread = lerpf(spread,minf(spread,0.28),clean)
		upper[side].step(Vector3(clampf(swing,-0.8,1.1),twist,sx*clampf(spread,0.18,2.15)),delta,0.30,profile.arm_speed)
		elbows[side].step(Vector3(-clampf(flex,0.12,1.6),0,0),delta,0.34,profile.arm_speed)
		var wrist_load := structural_wrists[side] if structural_wrists.size()==2 else Vector3.ZERO
		wrists[side].step(Vector3(-frame.box*0.18-flare*0.18+acro.x*(-0.12*flip.x+0.08*flip.y-0.16*flip.z),0,sx*(steer.y*0.15+steer.z*0.10))+wrist_load,delta,0.24,1.0)
		var curl: float = clampf(0.25-flare*0.15-frame.box*0.10+frame.retro*(0.35+bias)+frame.get("drive",0.0)*0.1+structural_grip,0.05,0.90)
		curl = lerpf(curl,0.15+0.45*flip.y,acro.x)
		curl = lerpf(curl,0.20+0.35*roll.y,acro.y)
		finger_curl[side] = move_toward(finger_curl[side],curl,delta*2.0)

func _update_articulation(delta: float, frame: Dictionary) -> void:
	var time: float = frame.hand_time
	var phase: float = frame.stroke_phase
	var structural_arms: PackedVector4Array = frame.get("mechanical_arms",PackedVector4Array())
	var structural_wrists: PackedVector3Array = frame.get("mechanical_wrists",PackedVector3Array())
	var structural_grip: float = float(frame.get("mechanical_grip",0.0))
	var strength: float = frame.stress
	var direction: Vector3 = frame.stroke_direction
	var goals := [Vector2.ZERO,Vector2.ZERO]
	for side in 2:
		var sx := 1.0 if side==0 else -1.0
		var target := Poses.arm_target(frame,side)
		var age := maxf(0.0,phase-float(side)*0.11)
		var envelope := smoothstep(0,0.25,age)*(1.0-smoothstep(0.53,1.0,age))
		var weight: float = envelope*strength*(0.7+sx*frame.differential*0.15)*(1.0-frame.land)
		var opposition := sx*(direction.y+direction.z)*0.50
		var recoil := smoothstep(0.24,0.45,age)*(1.0-smoothstep(0.48,0.72,age))
		target += Vector4(direction.x*0.48+opposition*0.33,opposition*0.30,
			absf(opposition)*0.47+0.18,opposition*0.36+recoil*0.46)*weight
		if structural_arms.size()==2: target += structural_arms[side]
		var flip: Vector3 = frame.flip_shape
		var acro: Vector2 = frame.acro
		var tuck := Vector4(0.08,-0.22,0.35,1.22)
		var opening := Poses.arm_key("Forward_Brace",side)
		target = target.lerp(tuck,acro.x*flip.y)
		target = target.lerp(opening,acro.x*flip.z)
		var hand_texture := grip_noise.get_noise_2d(time,side*19.3)
		var settling: float = frame.pressure*strength*hand_texture*(1.0-envelope)*(1.0-frame.land)
		target += Vector4(settling*0.065,0,settling*0.06,settling*0.09)
		goals[side] = Poses.hand_target(frame,side,hand_texture)
		var curl: float = goals[side].x
		var rate := 6.0 if curl>finger_curl[side] else 2.6
		finger_curl[side] = move_toward(finger_curl[side],curl,delta*rate)
		upper[side].step(Vector3(clampf(target.x,-0.8,1.05),target.y*sx,clampf(target.z,0.10,2.12)*sx),
			delta,0.27,profile.arm_speed)
		elbows[side].step(Vector3(-clampf(target.w,0.12,1.65),0,0),delta,0.31,profile.arm_speed)
		wrists[side].step(Vector3(-frame.flare*0.18+direction.x*weight*0.10+hand_texture*0.035,0,opposition*weight*0.15*sx),delta,0.23,1.0)
	for digit in digits.values():
		var hand: Vector2 = goals[digit.side]
		var value := grip_noise.get_noise_2d(time,digit.phase)
		var variation := lerpf(0.06,0.115,smoothstep(0.06,0.26,hand.x))
		variation = lerpf(variation,0.022,smoothstep(0.44,0.80,hand.x))
		var curl := clampf(hand.x+value*variation,0.0,0.90)
		var tau: float = (0.08 if curl>digit.curl else 0.20)+digit.delay
		var amount := 1.0-exp(-delta/tau)
		digit.curl = lerpf(digit.curl,curl,amount)
		digit.fan = lerpf(digit.fan,hand.y,amount)

func apply(sk: Skeleton3D, rotate: Callable) -> void:
	for side in 2:
		var angles: Vector3 = upper[side].value
		rotate.call(profile.arm_roots[side],Vector3(angles.x,0,angles.z))
		# Twist about the actual humerus, after positioning the upper arm. A
		# skeleton-space yaw would move the elbow instead of changing its hinge.
		var shoulder: int = sk.find_bone(profile.arm_roots[side])
		sk.set_bone_pose_rotation(shoulder,(sk.get_bone_pose_rotation(shoulder)*Quaternion(Vector3.UP,angles.y)).normalized())
		rotate.call(profile.arm_middles[side],elbows[side].value)
		rotate.call(profile.arm_ends[side],wrists[side].value)
	for index in finger_poses:
		var digit: Dictionary = digits[index]
		var curl: float = minf(digit.curl*digit.scale,0.91) if authored_hands else finger_curl[digit.side]
		var open := sk.get_bone_rest(index).basis.get_rotation_quaternion() if authored_hands else sk.get_bone_pose_rotation(index)
		var rotation := open.slerp(finger_poses[index],curl)
		var spread: Vector3 = digit.spread
		if authored_hands and not spread.is_zero_approx():
			rotation *= Quaternion(spread.normalized(),spread.length()*digit.fan)
		sk.set_bone_pose_rotation(index,rotation)

func sample_completed(sk: Skeleton3D, completed: Dictionary) -> void:
	var torso: Transform3D = completed[sk.find_bone("Torso")].affine_inverse()
	for side in 2:
		hands[side] = torso*completed[sk.find_bone(profile.arm_ends[side])].origin
		shoulders[side] = torso*completed[sk.find_bone(profile.arm_roots[side])].origin
		elbow_positions[side] = torso*completed[sk.find_bone(profile.arm_middles[side])].origin

func brake_spread() -> float:
	# ponytail: completed limb projection is a calibrated armor-area proxy;
	# replace it with measured projected areas if wind-tunnel data becomes available.
	var projected := 0.0
	var reach := 0.0
	for side in 2:
		projected += absf(elbow_positions[side].x-shoulders[side].x)+absf(hands[side].x-elbow_positions[side].x)
		reach += elbow_positions[side].distance_to(shoulders[side])+hands[side].distance_to(elbow_positions[side])
	if reach<0.001: return 0.0
	return smoothstep(profile.brake_projection.x,profile.brake_projection.y,projected/reach)
