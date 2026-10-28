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
	var lag := Vector3(omega.x*0.11+alpha.x*0.01,omega.y*0.07,omega.z*0.11+alpha.z*0.01)
	lag += Vector3(acceleration.z*0.004,-acceleration.x*0.002,-acceleration.x*0.005)
	hips.step(lag*0.35,delta,0.09)

	root_angles = hips.value*Vector3(-1,1,1)
	com.step(Vector3(-acceleration.x*0.004,-clampf(controller.g_load-1,-1,3)*0.025,acceleration.z*0.004).limit_length(0.16),delta,0.1)
	var bounded_aim: Vector3 = controller.limit_aim_direction(controller.aim_direction)
	var aim: Vector3 = get_skeleton().global_basis.inverse()*bounded_aim
	var yaw := atan2(aim.x,aim.z)
	var pitch := atan2(-aim.y,Vector2(aim.x,aim.z).length())
	# Head/shoulder/torso articulation only; aim never steers the chassis.
	var torso_aim := Vector3(signf(pitch)*clampf(absf(pitch)-deg_to_rad(20),0,deg_to_rad(35)),signf(yaw)*clampf(absf(yaw)-deg_to_rad(30),0,deg_to_rad(35)),0)
	chest.step(lag+torso_aim,delta,0.12)
	head.step(Vector3(clampf(pitch-torso_aim.x,-1.2,1.2),clampf(yaw-torso_aim.y,-deg_to_rad(30),deg_to_rad(30)),-chest.value.z*0.6),delta,0.10)
	var load := clampf((controller.g_load-1.0)/3.0,0,1.2)
	var kick := clampf(alpha.length()*0.08,0,1)
	var burst: Vector3 = Basis(controller.attitude).inverse()*controller.burst_direction*controller.boost_amount
	var demand: Vector3 = controller.translation_input
	var side_load := clampf(acceleration.x/22.0,-1,1)
	var compression := clampf(load*0.75+kick*0.35+controller.boost_amount*0.65+absf(demand.y)*0.25,0,1.3)
	var trail_pitch := atan2(flow.z,maxf(0.35,-flow.y))
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var tau := (0.14 if controller.boost_amount > 0.1 else 0.24)+side*0.035
		var brace := clampf(sx*(side_load+burst.x*0.8)+omega.z*0.25,-1,1)
		var hover_sway := sin(clock*1.7+side*2.1)*0.045*(1.0-cruise)
		# Load-driven tuck, opposed burst kicks and slower ankle follow-through.
		# The weapon remains stabilized while the free limbs absorb the maneuver.
		var thigh := Vector3(-0.25*(1.0-cruise)-0.65*spread-compression*0.32+trail_pitch*0.38+brace*0.22+hover_sway,-flow.x*0.22+omega.y*0.12,sx*(0.12+0.32*spread+compression*0.10)-flow.x*0.28-side_load*0.12)
		var knee := 0.42*(1.0-cruise)+0.12*cruise+0.85*compression+0.65*spread+brace*0.28-hover_sway
		legs[side*3].step(thigh.clamp(Vector3(-1.15,-0.5,-0.65),Vector3(0.65,0.5,0.65)),delta,tau)
		legs[side*3+1].step(Vector3(clampf(knee,0.1,1.65),0,0),delta,tau+0.04)
		legs[side*3+2].step(Vector3(clampf(0.32*cruise-0.24*spread-compression*0.30-brace*0.15,-0.65,0.5),-flow.x*0.12,0),delta,tau+0.08)
		var hand := Vector3(sx*(3.2+0.9*spread),-2.3+0.8*spread,0.3)+flow*Vector3(1.3,0.8,1.8)+Vector3(-side_load*0.45,compression*0.2,omega.x*0.35)
		if side == 1:
			# Rifle arm resists airflow. The native IK positions the wrist; a final
			# modifier points the skinned rifle using the solved wrist transform.
			hand = Vector3(-2.7,0.6,0.0)+aim.normalized()*3.5+flow*0.12
		hands[side].step(hand,delta,0.15 if side == 1 else 0.18)
		poles[side].step(Vector3(sx*5.4,-0.3,-2.8)+flow*0.25,delta,0.15+side*0.02)
	force = force_spring.step(controller.required_force,delta,0.10)
	for index in 6: shares[index] = 1.0/6.0
	var wrist: Vector3 = get_skeleton().global_transform*get_skeleton().get_bone_global_rest(bones["Torso"])*hands[1].value
	# Project once before parallax correction. An exactly rearward look has two
	# equally close yaw limits; the wrist offset must not choose the opposite one.
	var target: Vector3 = controller.position+bounded_aim*controller.position.distance_to(controller.gaze_target)
	var rifle_aim: Vector3 = controller.limit_aim_direction((target-wrist).normalized())
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
