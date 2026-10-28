extends SkeletonModifier3D

# Marvel's Iron Man VR is the production flight reference. The supplied procedural
# rig contributes spring timing, chest-local arm targets and overlapping leg motion.
# The velocity controller owns movement; flight is generated from rest, never a held clip.
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
var boost_weight := Spring.new()
var lateral := Spring.new()
var force_spring := Spring.new()
var loads: Array[Spring] = []
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
	force_spring.value = Vector3.UP*9.81
	for index in 6:
		var load := Spring.new()
		load.value.x = 1.0/6.0
		loads.append(load)
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

func update(delta: float, controller) -> void:
	clock = controller.mode_time
	var velocity: Vector3 = controller.local_velocity
	var acceleration: Vector3 = controller.local_acceleration
	var yaw_rate: float = controller.yaw_rate
	var active_brake := clampf((-acceleration.z-5.5)/22.0,0.0,1.0) if velocity.z > 3.5 else 0.0
	var raw_brake := maxf(active_brake,controller.brake_amount)
	var raw_boost: float = controller.boost_amount*(1.0-raw_brake)
	var raw_cruise := smoothstep(2.0,15.0,velocity.z)*(1.0-0.65*raw_boost)*(1.0-raw_brake)
	var w := weights.step(Vector3(1.0-smoothstep(1.2,15.0,velocity.length()),raw_cruise,raw_brake),delta,0.28)
	var boosted := boost_weight.step(Vector3(raw_boost,0,0),delta,0.28).x
	var bank := turn.step(Vector3(clampf(yaw_rate*0.52+acceleration.x*0.032,-1,1),0,0),delta,0.28).x
	var drift := lateral.step(Vector3(clampf(velocity.x/14.0,-1,1),clampf(velocity.y/12.0,-1,1),0),delta,0.30)
	var pitch := clampf(acceleration.z*0.02+clampf(velocity.z/52.0,-0.25,1.0)*1.12+boosted*0.26-w.z*0.62,deg_to_rad(-30),deg_to_rad(82))
	pitch += sin(clock*1.9)*0.022*w.x
	var roll := clampf(acceleration.x*0.026+yaw_rate*0.38+cos(clock*1.1)*0.035*w.x,-1.08,1.08)
	chest.step(Vector3(pitch,clampf(-yaw_rate*0.08-velocity.x*0.01,-0.28,0.28),roll),delta,0.35)
	hips.step(Vector3(pitch*0.78-w.z*0.18,clampf(-yaw_rate*0.24-velocity.x*0.028,-0.52,0.52),roll*0.74),delta,0.50)
	# Godot's actor faces -Z. The imported skeleton faces +Z, so pitch/roll
	# offsets must be converted rather than copying the prototype's Euler signs.
	root_angles = hips.value*Vector3(-0.68,1,0.68)
	var gaze_offset: Vector3 = controller.gaze_target-controller.position-Vector3.UP*controller.model_scale*0.5
	var gaze_pitch := -atan2(gaze_offset.y,Vector2(gaze_offset.x,gaze_offset.z).length())
	head.step(Vector3(clampf(gaze_pitch-chest.value.x,-0.7,0.6),clampf(angle_difference(controller.heading_yaw,controller.gaze_yaw)-chest.value.y,-1,1),clampf(chest.value.z,-0.4,0.4)),delta,0.24)
	var dip := clampf(-acceleration.y*0.012-w.z*0.14-absf(bank)*0.06,-0.22,0.15)
	com.step(Vector3(-sin(clock*1.1)*0.045*w.x+bank*0.09,(sin(clock*1.7)*0.055+cos(clock*0.85)*0.025)*w.x+dip,clampf(acceleration.z*0.008,-0.12,0.12)),delta,0.38)
	# Normalize target offsets so reverse/sideways flight retains relaxed limbs
	# instead of collapsing targets when the prototype's forward weight is zero.
	var h := maxf(w.x,1.0-w.y-boosted-w.z)
	var total := maxf(h+w.y+boosted+w.z,0.001)
	var c := w.y/total
	var b := boosted/total
	var brake_pose := w.z/total
	h /= total
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var into_turn := maxf(0.0,sx*bank)
		var sway := sin(clock*(1.35+side*0.1)+side*1.5)*0.04*h
		var tau := 0.58+side*0.06
		legs[side*3].step(Vector3(-0.22*h+0.08*c+0.12*b-0.60*brake_pose-0.16*into_turn+sway,bank*0.12,sx*(0.13*h+0.03*c+0.015*b+0.22*brake_pose)-drift.x*0.08),delta,tau)
		legs[side*3+1].step(Vector3((0.44-side*0.06)*h+0.12*c+0.05*b+(0.78-side*0.04)*brake_pose+0.22*into_turn-sway*0.6,0,0),delta,tau+0.04)
		legs[side*3+2].step(Vector3(-0.13*h+0.44*c+0.66*b-0.34*brake_pose,0,0),delta,tau+0.08)
		# Hands balance the suit; shoulder/thigh jets replace hand repulsors.
		var hand := Vector3(sx*(3.5*h+3.1*c+2.8*b+3.8*brake_pose),-2.6*h-2.8*c-2.9*b-1.4*brake_pose,0.5*h-1.2*c-1.6*b+1.8*brake_pose)
		hand += Vector3(sx*sin(clock*1.8)*0.06,cos(clock*1.6+side)*0.08,0)*h
		hand.z += maxf(0.0,-sx*bank)*0.5
		hands[side].step(hand,delta,0.18)
		poles[side].step(Vector3(sx*(5.5*h+4.8*c+4.3*b+5.6*brake_pose),-0.3*h-0.6*c-0.8*b-0.1*brake_pose,-3.0*h-3.1*c-3.3*b-2.0*brake_pose),delta,0.22)
	force = force_spring.step(controller.required_force,delta,0.24)
	# As in the reference, load is allocated from requested force, not a rigid-body
	# simulation. The independent velocity controller still owns translation.
	total = 0.0
	for index in 6:
		var sx := 1.0 if index%2 == 0 else -1.0
		var group := index/2
		var raw := (0.19+0.08*b-0.02*brake_pose) if group == 0 else ((0.16+0.04*c+0.04*brake_pose) if group == 1 else (0.15+0.08*b-0.04*brake_pose))
		raw += sx*(bank*0.035+sin(clock*1.35)*0.012*h)
		shares[index] = loads[index].step(Vector3(raw,0,0),delta,0.24).x
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
		_rotate(part[0],delta*Vector3(1,1,-1)*part[1])
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
