extends SceneTree

const Mech = preload("res://aerial/aerial_mech.gd")
const Flight = preload("res://aerial/flight_controller.gd")
const Poses = preload("res://aerial/poses/articulation_poses.gd")
const HEAD_FIRST := Quaternion(Vector3.RIGHT,-PI/2)

var mech: Mech
var failures: Array[String] = []
var maximum_visible_error := 0.0
var relaxed_digits := {}

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	create_timer(20).timeout.connect(func(): push_error("Authored flight checks timed out"); quit(1))
	mech = Mech.new()
	mech.controller.articulated_flight = true
	root.add_child(mech)
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://shaders/aerial/aircraft.gdshader")
	var plume := ShaderMaterial.new()
	plume.shader = preload("res://shaders/aerial/afterburner.gdshader")
	mech.build(surface,plume)
	_check_thruster_layout()
	assert(Poses.AUTHORED.size()+Poses.TORSO.size()+Poses.ARMS.size()+Poses.HANDS.size()==42)
	assert(Poses.MIRRORED.size()+Poses.TORSO_MIRRORED.size()+Poses.ARMS_MIRRORED.size()==9)
	assert(mech.rig.arms.digits.size()==28)
	await _hover_and_gaze()
	await _powered_inputs()
	await _cutoff_and_landing()
	await _compare_clocks()
	if not failures.is_empty():
		for failure in failures: push_error(failure)
		quit(1)
		return
	print("Authored flight checks passed. Peak exhaust lag %.2f degrees."%rad_to_deg(maximum_visible_error))
	quit()

func _check_thruster_layout() -> void:
	var expected_hot := ["BackpackL","BackpackR","CalfL","CalfR","FootSoleL","FootSoleR"]
	assert(mech.MOUNTS.size()==6 and mech.sockets.size()==6,"Expected six Gundam-style main outlets")
	for index in expected_hot.size():
		assert(String(mech.MOUNTS[index][0])==expected_hot[index],"Unexpected main outlet order")
		assert(mech.skeleton.find_bone(mech.MOUNTS[index][1])>=0,"Main outlet bone is missing")
	assert(mech.COLD_MOUNTS.size()==12 and mech.gas_sockets.size()==12,"Expected twelve cold-gas verniers")
	var cold_bones := {}
	for mount in mech.COLD_MOUNTS:
		assert(mech.skeleton.find_bone(mount[1])>=0,"Cold outlet bone is missing: "+String(mount[1]))
		cold_bones[mount[1]] = true
	for bone in [&"Shoulder.L",&"Shoulder.R",&"Thigh.L",&"Thigh.R",&"Torso"]:
		assert(cold_bones.has(bone),"Cold-gas layout is missing "+String(bone))

func _expect(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)

func _reset(attitude := Quaternion.IDENTITY, speed := Vector3.ZERO, power := 2, altitude := 5000.0) -> void:
	mech.controls = {}
	mech.reset_flight(Vector3(0,altitude,0),attitude,speed)
	mech.controller.detent = power

func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
		if not mech.controller.articulated_flight: continue
		var fc := mech.controller
		for index in fc.motor_forces.size():
			var force := fc.motor_forces[index]
			_expect(fc.motor_angles[index].is_zero_approx(),"Independent hot nozzle rotation")
			_expect(force.length()<=fc.hot_max_thrust(index)+1.0,"Hot outlet exceeds capacity")
			if force.length()>100.0:
				var visible := -mech.gimbals[index].global_basis.z.normalized()
				maximum_visible_error = maxf(maximum_visible_error,visible.angle_to(force.normalized()))
				_expect(visible.dot(force.normalized())>cos(deg_to_rad(9)),"Displayed exhaust disagrees with force")
		for index in fc.cold_forces.size():
			_expect(fc.cold_forces[index].length()<=fc.cold_thrust_limit(index)+100.0,"Cold outlet exceeds capacity")

func _rest_rotation(bone: String) -> Quaternion:
	var sk := mech.skeleton
	var index := sk.find_bone(bone)
	var parent: Transform3D = mech.bone_poses[sk.get_bone_parent(index)]
	var local: Transform3D = parent.affine_inverse()*mech.bone_poses[index]
	return local.basis.get_rotation_quaternion()

func _hover_and_gaze() -> void:
	var fc := mech.controller
	_reset()
	await _ticks(90)
	_expect(fc.velocity.length()<0.6 and fc.angular_velocity.length()<0.08,"Fixed-axis hover drifts")
	_expect(mech.rig.legs[1].value.x<0.16 and mech.rig.arms.elbows[0].value.x> -0.55,"Routine hover misses the extended pose")
	for index in mech.rig.arms.digits:
		var name := mech.skeleton.get_bone_name(index)
		relaxed_digits[name] = _rest_rotation(name)
	var finger := _rest_rotation("Finger5.L")
	var finger_motion := 0.0
	for i in 8:
		await _ticks(15)
		finger_motion = maxf(finger_motion,finger.angle_to(_rest_rotation("Finger5.L")))
	print("Relaxed middle finger moved %.2f degrees."%rad_to_deg(finger_motion))
	_expect(finger_motion>deg_to_rad(0.65),"Relaxed finger track is frozen")
	var current_head: Vector3 = mech.rig.head.value
	fc.gaze_direction = mech.actor.global_basis*(Vector3(0.6,0.1,1).normalized())
	await _ticks(19)
	_expect(mech.rig.head.value.distance_to(current_head)>0.06,"Independent gaze does not move the head")
	_expect(fc.angular_velocity.length()<0.08,"Head pose drives chassis attitude")

func _powered_inputs() -> void:
	var fc := mech.controller
	var vertical_rates: Array[float] = []
	for key in ["forward","back"]:
		_reset(HEAD_FIRST,Vector3(0,0,-55),3)
		await _ticks(10)
		mech.controls = {key:true}
		await _ticks(60)
		vertical_rates.append(fc.velocity.y)
		if key=="back":
			_expect(mech.rig.legs[1].value.x>1.04,"Hard pull-up never gathers the knees")
			for name in relaxed_digits:
				var relaxed: Quaternion = relaxed_digits[name]
				_expect(relaxed.angle_to(_rest_rotation(name))>0.025,"Loaded hand does not articulate "+name)
		else: _expect(mech.rig.legs[1].value.x<0.25,"Hard pitch-down loses its extended knees")
	_expect(vertical_rates[1]>vertical_rates[0]+3.0,"W and S bend the trajectory in the same direction")
	_reset(HEAD_FIRST,Vector3(0,0,-65),3)
	await _ticks(30)
	var cruise := _rest_rotation("Finger8.R")
	var low_stress: float = mech.rig.motion.stress
	mech.controls = {"left":true}
	await _ticks(46)
	var bank_rate := (fc.pilot_frame().inverse()*mech.angular_velocity).z
	_expect(bank_rate>0.9 and mech.rig.gesture_count>=1,"Full rig cannot drive the documented roll")
	_expect(mech.rig.motion.stress>low_stress or mech.rig.gesture_count>1,"Held bank lacks active correction")
	_expect(cruise.angle_to(_rest_rotation("Finger8.R"))>0.02,"High load never changes the fingers")
	mech.controls = {}
	await _ticks(55)
	_expect(absf((fc.pilot_frame().inverse()*mech.angular_velocity).z)<0.16,"Roll does not arrest")
	_reset()
	await _ticks(70)
	mech.controls = {"right":true,"yaw_left":true}
	await _ticks(15)
	_expect(fc.velocity.x>0.05 and (fc.pilot_frame().inverse()*mech.angular_velocity).y>0.04,"Combined lateral boost and yaw misses authority")
	mech.controls = {"left":true,"yaw_right":true}
	await _ticks(36)
	_expect((fc.pilot_frame().inverse()*mech.angular_velocity).y< -0.35,"Yaw reversal stalls")
	print("Fixed flight W/S vertical speeds %.2f / %.2f m/s, hard roll %.2f rad/s."%[vertical_rates[0],vertical_rates[1],bank_rate])

func _cutoff_and_landing() -> void:
	var fc := mech.controller
	var inverted := Quaternion(Vector3.FORWARD,PI)*Quaternion(Vector3.RIGHT,-PI/2-deg_to_rad(10))
	_reset(inverted,Vector3(0,0,-80),0)
	fc.reset(0.0)
	fc.detent = 0
	await _ticks(3)
	_expect(fc.aero_force.y>1000.0,"Inverted negative-AoA coast produces no upward lift")
	_reset(HEAD_FIRST,Vector3(0,0,-42),3)
	await _ticks(40)
	var speed := fc.velocity
	fc.detent = 0
	await _ticks(1)
	_expect(fc.delivered_thrust>0.0 and fc.velocity.distance_to(speed)<5.0,"Cutoff skips its shutdown impulse")
	await _ticks(24)
	_expect(fc.delivered_thrust<1.0,"Main outlets fail to close in coast")
	fc.detent = 3
	await _ticks(35)
	_expect(fc.delivered_thrust>mech.mass*Flight.GRAVITY*0.8,"Fixed outlets fail to relight")
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000,10,1000)
	shape.shape = box
	floor_body.add_child(shape)
	root.add_child(floor_body)
	floor_body.position.y = -5
	_reset(Quaternion.IDENTITY,Vector3(0,-5,0),0,85.0)
	await _ticks(75)
	_expect(mech.native_support and mech.rig.contacts.touchdown_count>=1,"Landing contact was lost in authored flight")
	floor_body.queue_free()

func _compare_clocks() -> void:
	var previous := Engine.physics_ticks_per_second
	var rates: Array[float] = []
	for hz in [30,60,120]:
		Engine.physics_ticks_per_second = hz
		_reset(HEAD_FIRST,Vector3(0,0,-55),3)
		await _ticks(int(hz*0.3))
		mech.controls = {"left":true}
		await _ticks(int(hz*0.8))
		rates.append((mech.controller.pilot_frame().inverse()*mech.angular_velocity).z)
	Engine.physics_ticks_per_second = previous
	_expect(rates.max()-rates.min()<0.23,"Fixed-axis roll is timestep-dependent")
	print("Matched hard roll at 30/60/120 Hz: ",rates)
	mech.controller.articulated_flight = false
	_reset(HEAD_FIRST,Vector3(0,0,-55),3)
	await _ticks(18)
	mech.controls = {"left":true}
	await _ticks(48)
	var baseline := (mech.controller.pilot_frame().inverse()*mech.angular_velocity).z
	print("Gimballed comparison at 60 Hz: %.3f rad/s."%baseline)
	_expect(absf(baseline-rates[1])<0.25,"Fixed-axis full rig lost substantial hard-roll authority")
