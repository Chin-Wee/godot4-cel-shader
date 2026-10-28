extends SkeletonModifier3D

# Marvel's Iron Man VR is the production flight reference. The supplied procedural
# rig contributes spring timing, chest-local arm targets and overlapping leg motion.
# Movement stays with the showcase route; this layer only reacts to its motion.
class Spring:
	var value := Vector3.ZERO
	var velocity := Vector3.ZERO
	func step(target: Vector3, delta: float, tau: float) -> Vector3:
		var omega := 2.0/tau
		var change := value-target
		var impulse := (velocity+change*omega)*delta
		var decay := exp(-omega*delta)
		value = target+(change+impulse)*decay
		velocity = (velocity-impulse*omega)*decay
		return value

var blend := Spring.new()
var chest := Spring.new()
var hips := Spring.new()
var head := Spring.new()
var com := Spring.new()
var weights := Spring.new() # hover, cruise, brake; always sum to one.
var turn := Spring.new()
var legs: Array[Spring] = []
var hands: Array[Spring] = []
var poles: Array[Spring] = []
var hand_targets: Array[Marker3D] = []
var pole_targets: Array[Marker3D] = []
var ik: TwoBoneIK3D
var bones := {}
var clock := 0.0
var root_angles := Vector3.ZERO
var force := Vector3.UP*9.81
var shares := PackedFloat32Array([1.0/6,1.0/6,1.0/6,1.0/6,1.0/6,1.0/6])

func configure() -> void:
	var sk := get_skeleton()
	for bone in ["PelvisBase","Low_Waist","Torso_WaistConnect","Torso","Neck","ShoulderJoint.L","ShoulderJoint.R","Thigh.L","Thigh.R","Knee.L","Knee.R","Feet.L","Feet.R"]:
		var index := sk.find_bone(bone)
		assert(index >= 0,"Missing procedural flight bone: "+bone)
		bones[bone] = index
	weights.value = Vector3(1,0,0)
	blend.value = Vector3(1,0,0)
	ik = TwoBoneIK3D.new()
	ik.name = "FlightArmIK"
	sk.add_child(ik)
	ik.set_setting_count(2)
	for side in 2:
		var suffix := ".L" if side == 0 else ".R"
		var sign_x := 1.0 if side == 0 else -1.0
		hands.append(Spring.new())
		poles.append(Spring.new())
		hands[side].value = Vector3(sign_x*3.5,-2.6,0.5)
		poles[side].value = Vector3(sign_x*5.5,-0.3,-3.0)
		for targets in [hand_targets,pole_targets]:
			var target := Marker3D.new()
			add_child(target)
			targets.append(target)
		ik.set_root_bone_name(side,"Shoulder"+suffix)
		ik.set_middle_bone_name(side,"ArmJoint"+suffix)
		ik.set_end_bone_name(side,"Hands"+suffix)
		ik.set_target_node(side,ik.get_path_to(hand_targets[side]))
		ik.set_pole_node(side,ik.get_path_to(pole_targets[side]))
		# The model's arm bends in its local Y/Z plane. Preserve its authored twist.
		ik.set_pole_direction(side,SkeletonModifier3D.SECONDARY_DIRECTION_CUSTOM)
		ik.set_pole_direction_vector(side,Vector3(0,0,-1))
		for joint in 3: legs.append(Spring.new())

func update(delta: float, amount: float, command: int, velocity: Vector3, acceleration: Vector3, yaw_rate: float) -> void:
	clock += delta
	var brake := clampf(maxf(0.0,acceleration.z)*0.15,0.0,1.0)
	if command == 3: brake = maxf(brake,amount)
	var w := weights.step(Vector3(1.0-amount,amount,0)*(1.0-brake)+Vector3(0,0,brake),delta,0.24)
	var steering := (1.0 if command == 1 else (-1.0 if command == 2 else 0.0))*amount
	var bank := turn.step(Vector3(clampf(yaw_rate*0.7+acceleration.x*0.07+steering,-1,1),0,0),delta,0.22).x
	var pitch := clampf(amount*1.12-acceleration.z*0.035-w.z*0.7,-0.35,1.35)
	var body := Vector3(pitch,clampf(-yaw_rate*0.08,-0.25,0.25),bank*0.48)
	body.x += sin(clock*1.9)*0.015*w.x
	chest.step(body,delta,0.35)
	hips.step(Vector3(body.x*0.78-w.z*0.12,-yaw_rate*0.24,body.z*0.74),delta,0.50)
	root_angles = hips.value*Vector3(-0.68,1,-0.68)
	head.step(Vector3(clampf(-chest.value.x*0.72,-0.7,0.5),clampf(yaw_rate*0.45-chest.value.y,-0.7,0.7),-chest.value.z*0.65),delta,0.24)
	com.step(Vector3(-bank*0.025,sin(clock*1.7)*0.012*w.x-absf(acceleration.z)*0.002,clampf(acceleration.z*0.003,-0.04,0.04)),delta,0.38)
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var sway := sin(clock*(1.35+side*0.1)+side*1.5)*0.035*w.x
		var tau := 0.58+side*0.06
		legs[side*3].step(Vector3(-0.22*w.x+0.10*w.y-0.55*w.z+sway,bank*0.10,sx*(0.11*w.x+0.025*w.y+0.18*w.z)),delta,tau)
		legs[side*3+1].step(Vector3(0.38*w.x+0.08*w.y+0.70*w.z-sway,0,0),delta,tau+0.04)
		legs[side*3+2].step(Vector3(-0.12*w.x+0.40*w.y-0.30*w.z,0,0),delta,tau+0.08)
		# Hands balance the body; there are no hand repulsors. Keep elbows soft and
		# arms beside the torso, with modest forward reach only during braking.
		var hand := Vector3(sx*(3.5*w.x+3.1*w.y+3.8*w.z),-2.6*w.x-2.8*w.y-1.0*w.z,0.5*w.x-1.2*w.y+2.0*w.z)
		hand += Vector3(sx*sin(clock*1.8)*0.06,cos(clock*1.6+side)*0.08,0)*w.x
		hand.z += maxf(0.0,sx*bank)*0.5
		hands[side].step(hand,delta,0.18)
		poles[side].step(Vector3(sx*5.5,-0.3,-3.0),delta,0.24)
	# ponytail: visual load allocation, not a constrained rigid-body force solver.
	# Replace only when the route showcase becomes force-driven gameplay.
	force = Vector3.UP*9.81+acceleration*4.0+velocity*0.06
	force = force.limit_length(35.0)
	var total := 0.0
	for index in 6:
		var sx := 1.0 if index%2 == 0 else -1.0
		shares[index] = maxf(0.05,1.0/6.0+sx*bank*0.035+(0.025*w.y if index < 2 else -0.0125*w.y))
		total += shares[index]
	for index in 6: shares[index] /= total

func _rotate(bone: String, angles: Vector3) -> void:
	var sk := get_skeleton()
	var index: int = bones[bone]
	var rest := sk.get_bone_global_rest(index).basis.orthonormalized()
	var offset := rest.inverse()*Basis.from_euler(angles)*rest
	sk.set_bone_pose_rotation(index,(sk.get_bone_pose_rotation(index)*offset.get_rotation_quaternion()).normalized())

func _process_modification() -> void:
	var delta := chest.value-hips.value*Vector3(0.68,1,0.68)
	for part in [["PelvisBase",0.14],["Low_Waist",0.24],["Torso_WaistConnect",0.30],["Torso",0.32]]:
		_rotate(part[0],delta*part[1])
	_rotate("Neck",head.value)
	for side in 2:
		var suffix := ".L" if side == 0 else ".R"
		_rotate("Thigh"+suffix,legs[side*3].value)
		_rotate("Knee"+suffix,legs[side*3+1].value)
		_rotate("Feet"+suffix,legs[side*3+2].value)
		_rotate("ShoulderJoint"+suffix,Vector3(0,hands[side].value.z*0.025*(1 if side == 0 else -1),0))
	var sk := get_skeleton()
	# TwoBoneIK treats the nonconsecutive joints as virtual straight bones.
	# Remove authored intermediate bend rotations before the native solve.
	for suffix in [".L",".R"]:
		for name in ["UpperArm"+suffix+".001","LowerArm"+suffix]:
			var index := sk.find_bone(name)
			sk.set_bone_pose_rotation(index,sk.get_bone_rest(index).basis.get_rotation_quaternion())
	var torso := sk.get_bone_global_pose(bones["Torso"])
	for side in 2:
		var target := torso*hands[side].value
		var shoulder := sk.get_bone_global_pose(ik.get_root_bone(side)).origin
		var middle := sk.get_bone_global_pose(ik.get_middle_bone(side)).origin
		var end := sk.get_bone_global_pose(ik.get_end_bone(side)).origin
		var reach := (shoulder.distance_to(middle)+middle.distance_to(end))*0.985
		var distance := shoulder.distance_to(target)
		# Soft reach prevents a straight elbow singularity; the pole stays behind it.
		var cushion := reach*0.15
		if distance > reach-cushion:
			distance = reach-cushion+cushion*(1.0-exp(-(distance-reach+cushion)/cushion))
		hand_targets[side].position = shoulder+(target-shoulder).normalized()*distance
		pole_targets[side].position = torso*poles[side].value
