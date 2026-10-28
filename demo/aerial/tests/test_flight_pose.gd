extends SceneTree

const Controller = preload("res://aerial/flight_controller.gd")
const Pose = preload("res://aerial/flight_pose.gd")
var completed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(20).timeout.connect(func():
		if not completed: push_error("Procedural flight checks did not complete"); quit(1))
	# An analytic spring must give the same result at different frame rates and
	# retain velocity across reversals instead of restarting a tween each frame.
	var previous := Vector3.ZERO
	for fps in [30,60,120]:
		var spring := Pose.Spring.new()
		for frame in fps: spring.step(Vector3.ONE,1.0/fps,0.35)
		if fps > 30: assert(spring.value.distance_to(previous) < 0.00001,"Spring depends on frame rate")
		previous = spring.value
		var velocity := spring.velocity
		spring.step(Vector3.ZERO,0.001,0.35)
		assert(spring.velocity.distance_to(velocity) < 0.1,"Target reversal discarded spring momentum")
	assert(_check_controller(),"Flight controller differs from the supplied controls/inertia")
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	scene.follow_camera = false
	var mech = scene.hero
	await process_frame
	assert(mech.flames.size() == 6 and mech.gas_jets.size() == 4)
	assert(_check_mount_surfaces(mech),"A booster is not seated against its armor")
	assert(not mech.actor.animation_player.has_animation(&"Airborne"),"Static flight hold remains")
	for mode in Controller.MODES:
		mech.controller.set_mode(mode)
		for frame in 180: mech.step_flight(1.0/60.0,{},0.0)
		await process_frame
		await process_frame
		assert(not mech.actor.animation_player.is_playing() and mech.actor.current_animation.is_empty(),"Flight plays a static/authored clip")
		assert(_check_ik(mech),"Native arm IK missed its target")
		assert(_check_motors(mech),"A motor exceeded its local mechanical cone")
		var total := 0.0
		for share in mech.rig.shares: total += share
		assert(is_equal_approx(total,1.0),"Thrust load is not normalized")
	mech.controller.set_mode(&"boost")
	for frame in 180: mech.step_flight(1.0/60.0,{},0.0)
	await process_frame
	await process_frame
	var away_from_down := 0
	for flame in mech.flames:
		if flame.global_basis.z.normalized().dot(Vector3.DOWN) < 0.8: away_from_down += 1
	assert(away_from_down > 0,"Articulated boosters still lock to world down")
	mech.controller.set_mode(&"manual")
	mech.controller.reset(mech.position,0.0)
	for frame in 120: mech.step_flight(1.0/60.0,{"turn":1.0},0.0)
	await process_frame
	assert(mech.actor.rotation.z > 0.1,"A banks away from the requested left turn")
	assert(_check_motors(mech))
	mech.controller.reset(mech.position,0.0)
	for frame in 120: mech.step_flight(1.0/60.0,{},PI/2.0)
	assert(mech.rig.head.value.y > 0.15,"Camera orbit does not lead head gaze")
	scene.set_walk_mode(true)
	for frame in 90: mech.update_animation(1.0/60.0)
	await process_frame
	assert(not mech.rig.active and not mech.rig.ik.active)
	assert(mech.actor.current_animation == &"Walk")
	scene.set_walk_mode(false)
	var position: Vector3 = mech.position
	var clock: float = mech.controller.mode_time
	var posture: Transform3D = mech.actor.transform
	scene._process(0.2)
	assert(mech.position == position and mech.controller.mode_time == clock and mech.actor.transform == posture,"Pause advances flight")
	# Buttons and orbit events use the same public paths as the native HUD.
	scene.mode_buttons[3].pressed.emit()
	assert(mech.controller.mode == &"boost" and scene.mode_buttons[3].button_pressed)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	scene._unhandled_input(mouse)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20,10)
	var yaw: float = scene.camera_yaw
	scene._unhandled_input(motion)
	assert(scene.camera_yaw < yaw)
	scene.queue_free()
	await process_frame
	completed = true
	print("Flight checks passed: reference keys and inertia, all eight modes, procedural rest-pose IK, camera gaze, local motor limits, model seating, walk and pause.")
	quit()

func _check_controller() -> bool:
	Controller.install_input_actions()
	for pair in [[KEY_W,"forward",1.0],[KEY_S,"forward",-1.0],[KEY_A,"turn",1.0],[KEY_D,"turn",-1.0],[KEY_Q,"strafe",1.0],[KEY_E,"strafe",-1.0],[KEY_SPACE,"vertical",1.0],[KEY_C,"vertical",-1.0],[KEY_CTRL,"vertical",-1.0],[KEY_SHIFT,"boost",1.0],[KEY_X,"brake",1.0]]:
		var key := InputEventKey.new()
		key.physical_keycode = pair[0]
		key.pressed = true
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		if Controller.read_input()[pair[1]] != pair[2]: return false
		key = key.duplicate()
		key.pressed = false
		Input.parse_input_event(key)
		Input.flush_buffered_events()
	var previous := Vector3.ZERO
	for fps in [30,60,120]:
		var fc = Controller.new()
		fc.reset(Vector3(0,600,0))
		for frame in fps*3: fc.advance(1.0/fps,{"forward":1.0,"turn":0.2,"boost":1.0},0.0)
		if fps > 30 and fc.position.distance_to(previous) > 0.001: return false
		previous = fc.position
	var cruise = Controller.new()
	var boosted = Controller.new()
	for frame in 360:
		cruise.advance(1.0/60.0,{"forward":1.0},0.0)
		boosted.advance(1.0/60.0,{"forward":1.0,"boost":1.0},0.0)
	if boosted.velocity.length() < cruise.velocity.length()*1.5: return false
	var coast = Controller.new()
	var braking = Controller.new()
	coast.velocity = Vector3(0,0,-25)
	braking.velocity = coast.velocity
	for frame in 60:
		coast.advance(1.0/60.0,{},0.0)
		braking.advance(1.0/60.0,{"brake":1.0},0.0)
	if braking.velocity.length() >= coast.velocity.length()*0.5: return false
	for controls in [{"strafe":1.0},{"vertical":1.0},{"vertical":-1.0},{"forward":-1.0}]:
		var fc = Controller.new()
		for frame in 120: fc.advance(1.0/60.0,controls,0.0)
		if controls.has("strafe") and fc.position.x >= 0.0: return false
		if controls.has("vertical") and fc.position.y*controls.vertical <= 0.0: return false
		if controls.has("forward") and fc.position.z <= 0.0: return false
	var floor_test = Controller.new()
	floor_test.reset(Vector3(0,100,0))
	for frame in 300: floor_test.advance(1.0/60.0,{"vertical":-1.0},0.0,20.0)
	if floor_test.position.y < 42.0: return false
	return true

func _check_motors(mech: Node3D) -> bool:
	var pivots: Array = mech.gimbals+mech.gas_gimbals
	for index in pivots.size():
		var relative: Basis = mech.neutral_bases[index].inverse()*pivots[index].basis
		if relative.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) > mech.VECTOR_LIMIT+0.001: return false
	return true

func _check_ik(mech: Node3D) -> bool:
	for side in 2:
		var suffix := ".L" if side == 0 else ".R"
		var hand: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Hands"+suffix)]
		var target: Vector3 = mech.rig.hand_targets[side].position
		if not hand.origin.is_finite() or not hand.basis.is_finite() or hand.origin.distance_to(target) >= 0.05: return false
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
