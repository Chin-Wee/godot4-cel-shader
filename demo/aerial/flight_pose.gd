extends SkeletonModifier3D

# Airflow-driven overlapping motion, using native SkeletonModifier3D/TwoBoneIK3D.
# Flight behavior references: DCS Su-27, Elite Dangerous and Armored Core VI.
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
var turn := Spring.new()
var force_spring := Spring.new()
var legs: Array[Spring] = []
var hands: Array[Spring] = []
var poles: Array[Spring] = []
var hand_targets: Array[Marker3D] = []
var pole_targets: Array[Marker3D] = []
var weapon: WeaponAim
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
	force_spring.value = Vector3.UP*9.81
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
	weapon = WeaponAim.new()
	weapon.name = "FlightWeaponAim"
	sk.add_child(weapon)
	var gun: MeshInstance3D = sk.find_child("GUN",false,false)
	for bind in gun.skin.get_bind_count():
		if gun.skin.get_bind_name(bind) == &"Hands.R":
			# Skin bind can differ from inverse skeleton rest. Use the actual asset.
			var transform := gun.skin.get_bind_pose(bind)
			weapon.barrel_axis = (transform.basis*Vector3.DOWN).normalized()
			weapon.muzzle_local = transform*Vector3(-2.412204,-0.004719,0.436474)

class WeaponAim:
	extends SkeletonModifier3D
	var smoothed_aim := Vector3.FORWARD
	var muzzle := Transform3D.IDENTITY
	var barrel_direction := Vector3.FORWARD
	var barrel_axis := Vector3.UP
	var muzzle_local := Vector3.ZERO
	func _process_modification() -> void:
		var sk := get_skeleton()
		var index := sk.find_bone("Hands.R")
		var hand := sk.get_bone_global_pose(index)
		var desired := (sk.global_basis.inverse()*smoothed_aim).normalized()
		var rotation := Quaternion((hand.basis*barrel_axis).normalized(),desired)
		hand.basis = Basis(rotation)*hand.basis
		var parent := sk.get_bone_global_pose(sk.get_bone_parent(index)).basis
		sk.set_bone_pose_rotation(index,(parent.inverse()*hand.basis).get_rotation_quaternion().normalized())
		# Measured center of the lowest-Y rifle end, transformed to Hands.R space.
		muzzle = sk.global_transform*Transform3D(hand.basis,hand.origin+hand.basis*muzzle_local)
		barrel_direction = (sk.global_basis*hand.basis*barrel_axis).normalized()

func update(delta: float, controller) -> void:
	clock = controller.clock
	var acceleration: Vector3 = controller.local_acceleration
	var omega: Vector3 = Basis(controller.attitude).inverse()*controller.angular_velocity
	var alpha: Vector3 = Basis(controller.attitude).inverse()*controller.angular_acceleration
	var flow: Vector3 = controller.local_airflow.limit_length(70.0)/70.0
	# Convert Godot -Z forward to the imported skeleton's +Z forward frame.
	flow *= Vector3(-1,1,-1)
	var spread: float = clampf(controller.departure+controller.brake_amount,0,1)
	var cruise: float = controller.aero_authority
	turn.step(Vector3(omega.y,0,0),delta,0.12)
	# Chassis attitude is physical. These small secondary offsets trail its rates
	# and loads: pelvis first, torso 30ms later, arms another 30ms behind.
	var lag := Vector3(omega.x*0.07+alpha.x*0.006,omega.y*0.045,omega.z*0.07+alpha.z*0.006)
	lag += Vector3(acceleration.z*0.004,-acceleration.x*0.002,-acceleration.x*0.005)
	hips.step(lag*0.35,delta,0.09)

	root_angles = hips.value*Vector3(-1,1,1)
	com.step(Vector3(-acceleration.x*0.004,-clampf(controller.g_load-1,-1,3)*0.025,acceleration.z*0.004).limit_length(0.16),delta,0.1)
	var aim: Vector3 = get_skeleton().global_basis.inverse()*controller.aim_direction
	var yaw := atan2(aim.x,aim.z)
	var pitch := atan2(-aim.y,Vector2(aim.x,aim.z).length())
	# ±30/20 head zone, then shoulder/torso articulation, then controller chassis.
	var torso_aim := Vector3(signf(pitch)*clampf(absf(pitch)-deg_to_rad(20),0,deg_to_rad(35)),signf(yaw)*clampf(absf(yaw)-deg_to_rad(30),0,deg_to_rad(35)),0)
	chest.step(lag+torso_aim,delta,0.12)
	head.step(Vector3(clampf(pitch-torso_aim.x,-1.2,1.2),clampf(yaw-torso_aim.y,-deg_to_rad(30),deg_to_rad(30)),-chest.value.z*0.6),delta,0.10)
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var tau := 0.16+side*0.025
		# Broadside airflow opens limbs; aligned flow streamlines them. No flight clips.
		legs[side*3].step(Vector3(-0.12-0.48*spread+flow.z*0.24,flow.x*0.16,sx*(0.08+0.28*spread)-flow.x*0.2),delta,tau)
		legs[side*3+1].step(Vector3(0.24+0.64*spread+absf(flow.x)*0.18,0,0),delta,tau+0.03)
		legs[side*3+2].step(Vector3(0.24*cruise-0.20*spread,0,0),delta,tau+0.06)
		var hand := Vector3(sx*(3.2+0.9*spread),-2.3+0.8*spread,0.3)+flow*Vector3(1.1,0.6,1.4)
		if side == 1:
			# Rifle arm resists airflow. The native IK positions the wrist; a final
			# modifier points the skinned rifle using the solved wrist transform.
			hand = Vector3(-2.7,0.6,0.0)+aim.normalized()*3.5+flow*0.12
		hands[side].step(hand,delta,0.15 if side == 1 else 0.18)
		poles[side].step(Vector3(sx*5.4,-0.3,-2.8)+flow*0.25,delta,0.15+side*0.02)
	force = force_spring.step(controller.required_force,delta,0.10)
	for index in 6: shares[index] = 1.0/6.0
	var wrist: Vector3 = get_skeleton().global_transform*get_skeleton().get_bone_global_rest(bones["Torso"])*hands[1].value
	var rifle_aim: Vector3 = (controller.gaze_target-wrist).normalized()
	var aim_rotation := Quaternion(weapon.smoothed_aim.normalized(),rifle_aim)
	weapon.smoothed_aim = (Quaternion.IDENTITY.slerp(aim_rotation,1.0-exp(-delta/0.12))*weapon.smoothed_aim).normalized()

func _rotate(bone: String, angles: Vector3) -> void:
	var sk := get_skeleton()
	var index: int = bones[bone]
	var rest := sk.get_bone_global_rest(index).basis.orthonormalized()
	var offset := rest.inverse()*Basis.from_euler(angles)*rest
	sk.set_bone_pose_rotation(index,(sk.get_bone_pose_rotation(index)*offset.get_rotation_quaternion()).normalized())

func _process_modification() -> void:
	var delta := chest.value-hips.value
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
