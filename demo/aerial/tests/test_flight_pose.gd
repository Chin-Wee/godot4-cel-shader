extends SceneTree

const Controller = preload("res://aerial/flight_controller.gd")
var scene
var mech
var completed := false

func _initialize() -> void:
	call_deferred("_run")

func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func _fixture(origin := Vector3(175, 2200, 340), orientation := Quaternion.IDENTITY, speed := Vector3.ZERO, level := 2) -> void:
	mech.freeze = true
	await _ticks(1)
	mech.reset_flight(origin, orientation, speed)
	mech.controller.detent = level
	mech.controller.engine_level = Controller.DETENTS[level]
	mech.controller.air_density = 1.225
	mech.controls = {}
	mech.freeze = false
	await _ticks(2)

func _key(code: Key, pressed := true, echo := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	mech.controller.handle_input(event)

func _run() -> void:
	create_timer(80).timeout.connect(func():
		if not completed: push_error("Rigid flight checks did not finish"); quit(1))
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.animate = true
	mech = scene.hero
	mech.player_controlled = false
	await _ticks(2)
	assert(mech is RigidBody3D and mech.scale.is_equal_approx(Vector3.ONE))
	assert(mech.actor.get_node("CollisionShape3D").disabled)
	assert(mech.flames.size() == 6 and mech.gas_jets.size() == 4)
	assert(_check_mount_surfaces(mech))
	_check_inputs()
	await _fixture()
	await _ticks(180)
	assert(mech.controller.velocity.length() < 1.0, "Hover did not settle")
	assert(mech.basis.y.dot(Vector3.UP) > 0.99, "Hover did not remain upright")
	assert(_check_limbs(mech) and _check_motors(mech))
	await _ticks(420)
	assert(mech.controller.velocity.length() < 0.3, "Long hover develops persistent drift")
	# A new hover press translates first, including precision input. Its same
	# held direction gradually starts tilt after the three-second interval.
	mech.controls = {"forward":true,"precision":true}
	await _ticks(30)
	assert(absf(mech.angular_velocity.x)<0.02 and mech.controller.hover_translation.z< -0.3)
	await _ticks(180)
	assert(mech.angular_velocity.x< -0.02 and mech.controller.released_axes.x<1)
	# Same six rotation commands at upright/prone/inverted/vertical-flight poses.
	for orientation in [Quaternion.IDENTITY, Quaternion(Vector3.RIGHT,-PI/2), Quaternion(Vector3.FORWARD,PI)*Quaternion(Vector3.RIGHT,-PI/2), Quaternion(Vector3.RIGHT,PI)]:
		for key in ["forward","back","left","right","yaw_left","yaw_right"]:
			await _fixture(Vector3(175,2400,340), orientation, Vector3.ZERO, 0)
			mech.controller.air_density = 0.0
			mech.controls = {key:true}
			await _ticks(24)
			assert(mech.controller.rotation_command.length() > 0.9, "Rotation input was gated")
			assert(mech.controller.attitude.angle_to(orientation) > 0.08, "A rotation axis cannot move")
			assert(absf(mech.controller.pilot_frame().determinant()-1.0) < 0.001)
			assert(_check_motors(mech) and _check_limbs(mech))
	# In vacuum, balanced attitude torque cannot change horizontal momentum.
	await _fixture(Vector3(175,2600,340), Quaternion.IDENTITY, Vector3(45,0,-30), 0)
	mech.controller.air_density = 0.0
	await _ticks(2) # Drain the preceding atmospheric step before measuring vacuum.
	mech.controls = {"right":true,"back":true}
	var before: Vector3 = mech.controller.velocity
	await _ticks(120)
	assert(absf(mech.controller.velocity.x-before.x) < 0.01 and absf(mech.controller.velocity.z-before.z) < 0.01, "Rotation rewrote momentum")
	assert(mech.controller.main_force.is_zero_approx() and mech.controller.leg_force.is_zero_approx() and mech.controller.hover_assist == 0)
	mech.controls = {}
	await _ticks(90)
	assert(mech.angular_velocity.length() < 0.03, "Cold-gas counter-torque did not stop rotation")
	# Existing momentum survives thrust directed across it.
	await _fixture(Vector3(175,2600,340), Quaternion(Vector3.RIGHT,-PI/2), Vector3(40,0,0), 3)
	mech.controller.air_density = 0.0
	await _ticks(45)
	assert(mech.controller.velocity.x > 35 and mech.controller.velocity.z < -5, "Sideways thrust replaced the previous trajectory")
	assert(mech.controller.hover_assist < 0.01)
	# Maximum detent reaches the old 4× level with equal, capacity-limited engines.
	await _fixture(Vector3(175,2600,340), Quaternion(Vector3.RIGHT,-PI/2), Vector3(0,0,-70), 4)
	await _ticks(60)
	assert(is_equal_approx(mech.controller.engine_level,4.0) and _check_motors(mech))
	for share in mech.controller.engine_shares: assert(absf(share-1.0/6.0) < 0.0001)
	# High-speed departure must never enable hover correction or disable controls.
	await _fixture(Vector3(175,2600,340), Quaternion.IDENTITY, Vector3(0,0,-80))
	mech.controls = {"back":true,"brake":true}
	await _ticks(12)
	assert(mech.controller.hover_assist < 0.01, "Fast departure engaged hover correction")
	assert(mech.controller.rotation_command.x > 0.7, "Pitch stopped during departure")
	assert(mech.controller.brake_amount > 0.3 and mech.controller.brake_amount < 0.7, "Brake spread should build gradually")
	# Airflow generates lift with engines off; Shift adds real deceleration.
	var cruise := Quaternion(Vector3.RIGHT,-PI/2)
	await _fixture(Vector3(175,2600,340), cruise, Vector3(0,0,-80), 0)
	await _ticks(30)
	var coast_speed: float = mech.controller.velocity.length()
	assert(mech.controller.aero_force.length() > 1000, "Unpowered flight lost aerodynamics")
	var inverted := Quaternion(Vector3.FORWARD,PI) * Quaternion(Vector3.RIGHT,-PI/2-deg_to_rad(10))
	await _fixture(Vector3(175,2600,340), inverted, Vector3(0,0,-80), 0)
	assert(mech.controller.aero_force.y > 0, "Inverted negative-AoA flight cannot generate upward lift")
	await _fixture(Vector3(175,2600,340), cruise, Vector3(0,0,-80), 0)
	mech.controls = {"brake":true,"left":true}
	await _ticks(30)
	assert(mech.controller.velocity.length() < coast_speed-5, "Shift did not brake")
	assert(mech.controller.rotation_command.z > 0.9, "Shift stole roll input")
	# A broadside spread fall decelerates differently from a compact fall.
	await _fixture(Vector3(175,2600,340), cruise, Vector3(0,-50,0), 0)
	await _ticks(60)
	var compact_fall: float = mech.controller.velocity.y
	await _fixture(Vector3(175,2600,340), cruise, Vector3(0,-50,0), 0)
	mech.controls = {"brake":true}
	await _ticks(60)
	assert(mech.controller.velocity.y > compact_fall+8, "Skydiver area does not affect descent")
	# A ground-contact leg push launches without changing the thrust detent.
	var ground: float = scene.ground_height(Vector3(175,0,340))
	await _fixture(Vector3(175,ground+45.2,340), Quaternion.IDENTITY, Vector3.ZERO, 0)
	await _ticks(90)
	assert(mech.controller.grounded, "Native ground probe failed")
	var launch_height: float = mech.position.y
	_key(KEY_R)
	await _ticks(12)
	assert(mech.position.y > launch_height+2 and mech.controller.velocity.y > 1, "Leg push did not launch")
	assert(mech.controller.detent == 0 and mech.controller.delivered_thrust == 0, "Jump changed the main thrust setting")
	await _ticks(180)
	assert(mech.controller.grounded and mech.position.y >= ground+44, "Native capsule tunneled through the ground")
	# One uninterrupted transition: grounded hover -> takeoff -> pitch -> cutoff
	# -> free rotation -> re-ignite/brake -> settle. No pose or velocity resets.
	_key(KEY_SPACE); _key(KEY_SPACE); _key(KEY_SPACE)
	await _ticks(60)
	mech.controls = {"forward":true}
	await _ticks(65)
	mech.controls = {}
	await _ticks(60)
	_key(KEY_C); _key(KEY_C); _key(KEY_C)
	await _ticks(45) # 2× -> 0 takes 2/3 s at the calibrated spool rate.
	assert(mech.controller.delivered_thrust == 0)
	mech.controls = {"right":true,"back":true}
	await _ticks(45)
	_key(KEY_SPACE); _key(KEY_SPACE); _key(KEY_SPACE)
	mech.controls = {"brake":true,"forward":true}
	await _ticks(30)
	assert(mech.controller.velocity.is_finite() and mech.position.is_finite())
	assert(_check_motors(mech) and _check_limbs(mech))
	# Free arms, independent camera look, pause and retained walk preview.
	var paused_velocity: Vector3 = mech.linear_velocity
	scene.animate = false
	var frozen: Transform3D = mech.global_transform
	var time: float = mech.controller.clock
	await _ticks(8)
	assert(mech.global_transform.is_equal_approx(frozen) and mech.controller.clock == time, "Pause did not freeze physics")
	scene.animate = true
	assert(mech.linear_velocity.is_equal_approx(paused_velocity), "Resume erased momentum")
	await _fixture()
	await _ticks(60)
	scene.animate = false
	for frame in 90: mech.update_animation(1.0/60.0)
	await _ticks(2)
	assert(_check_limbs(mech))
	assert(not mech.skeleton.find_child("GUN",false,false).visible)
	assert(not scene.has_method("fire_weapon"),"Gun aiming/firing still owns the flight arms")

	scene.set_walk_mode(true)
	mech.update_animation(0.3)
	assert(mech.actor.animation_player.is_playing() and mech.freeze)
	scene.set_walk_mode(false)
	mech.update_animation(0.3)
	assert(not mech.actor.animation_player.is_playing())
	completed = true
	print("Rigid flight checks passed: detents, six-axis rotation, hover, unpowered momentum, redirected thrust, brake, lift, skydiving, jump/contact, continuous transitions, IK, thrusters and pause.")
	scene.queue_free()
	await process_frame
	quit()

func _check_inputs() -> void:
	mech.controller.detent = 0
	for expected in [1,2,3,4,4]:
		_key(KEY_SPACE)
		assert(mech.controller.detent == expected)
		_key(KEY_SPACE,true,true)
		assert(mech.controller.detent == expected, "Holding Space repeats a detent")
		_key(KEY_SPACE,false)
	for expected in [3,2,1,0,0]:
		_key(KEY_C)
		assert(mech.controller.detent == expected)
	assert(InputMap.action_has_event("flight_brake", _event(KEY_SHIFT)))
	assert(not InputMap.has_action("flight_burst"))
	var before: int = mech.controller.detent
	_key(KEY_X); _key(KEY_F)
	assert(mech.controller.detent == before)

func _event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

func _check_motors(mech: Node3D) -> bool:
	var pivots: Array = mech.gimbals+mech.gas_gimbals
	for index in pivots.size():
		var relative: Basis = mech.neutral_bases[index].inverse()*pivots[index].basis
		if relative.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) > mech.VECTOR_LIMIT+0.001: return false
	var total := 0.0
	for force in mech.controller.motor_forces:
		if force.length() > mech.mass * Controller.GRAVITY * 4.0 / 6.0 + 1.0: return false
		total += force.length()
	if absf(total-mech.controller.delivered_thrust) > 2.0: return false
	return true

func _check_limbs(mech: Node3D) -> bool:
	for side in 2:
		var suffix := ".L" if side == 0 else ".R"
		var hand: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Hands"+suffix)]
		var shoulder: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Shoulder"+suffix)]
		if not hand.origin.is_finite() or not hand.basis.is_finite(): return false
		if hand.origin.distance_to(shoulder.origin)>5.5: return false
	return true

func _check_mount_surfaces(mech: Node3D) -> bool:
	# Test against source triangles, excluding the collars we add ourselves. Bone
	# attachment alone cannot prove that a booster is seated against the armor.
	var sk: Skeleton3D = mech.skeleton
	for mount in mech.MOUNTS+mech.COLD_MOUNTS:
		var nearest := INF
		for child in sk.get_children():
			var candidates := []
			var transform := Transform3D.IDENTITY
			if child is BoneAttachment3D and child.bone_name == mount[1] and not str(child.name).begins_with("Thruster"):
				candidates = child.get_children()
			elif child is MeshInstance3D and child.name == &"Cube" and mount[1] == &"Torso":
				candidates = [child]
				transform = sk.get_bone_global_rest(sk.find_bone("Torso")).affine_inverse()
			for mesh in candidates:
				if not mesh is MeshInstance3D: continue
				var to_bone: Transform3D = transform*mesh.transform
				var faces: PackedVector3Array = mesh.mesh.get_faces()
				for index in range(0,faces.size(),3):
					nearest = minf(nearest,_triangle_distance(mount[2],to_bone*faces[index],to_bone*faces[index+1],to_bone*faces[index+2]))
		if nearest >= 0.02:
			push_error("Booster floats away from source armor: %s (%s source units)"%[mount[0],nearest])
			return false
	return true

func _triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b-a).cross(c-a).normalized()
	var hit = Geometry3D.segment_intersects_triangle(point+normal*100,point-normal*100,a,b,c)
	if hit != null: return point.distance_to(hit)
	return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point,a,b)),minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point,b,c)),point.distance_to(Geometry3D.get_closest_point_to_segment(point,c,a))))
