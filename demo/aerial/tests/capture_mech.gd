extends SceneTree

var completed := false
var viewport: SubViewport
var scene
var held := []

func _initialize() -> void:
	call_deferred("_capture")

func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func _keys(keys: Array) -> void:
	for code in held:
		if not code in keys: _event(code, false)
	for code in keys:
		if not code in held: _event(code, true)
	held = keys.duplicate()
	Input.flush_buffered_events()

func _event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	# SubViewport has no container: route native events into its input pipeline.
	Input.parse_input_event(event)
	viewport.push_input(event)

func _save(path: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	var frame := viewport.get_texture().get_image()
	assert(not frame.is_empty() and frame.get_size() == viewport.size)
	assert(frame.save_png(path) == OK)

func _capture() -> void:
	create_timer(240).timeout.connect(func():
		if not completed: push_error("Native rigid flight replay did not finish"); quit(1))
	assert(DisplayServer.get_name() != "headless", "Use the native renderer for visual validation")
	var arguments := OS.get_cmdline_user_args()
	var output: String = arguments[0] if not arguments.is_empty() else "/tmp/rigid-flight-visual"
	assert(output.is_absolute_path() and DirAccess.make_dir_recursive_absolute(output) == OK)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,800)
	viewport.own_world_3d = true
	viewport.msaa_3d = root.msaa_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	viewport.add_child(scene)
	root.title = "Godot rigid flight validation"
	root.mode = Window.MODE_MINIMIZED
	scene.follow_camera = false
	scene.animate = false
	scene.hero.reset_flight(Vector3(175,1600,340))
	scene.animate = true
	await _ticks(60)
	var records := []
	var saw_brake := false
	var saw_zero := false
	var saw_rotation := false
	# This replay is uninterrupted. Every control arrives through native events.
	for frame in 108:
		match frame:
			0: _keys([])
			8: _keys([KEY_SPACE,KEY_W])
			9: _keys([KEY_W])
			28: _keys([])
			38: _keys([KEY_C])
			39: _keys([])
			40: _keys([KEY_C])
			41: _keys([])
			42: _keys([KEY_C])
			43: _keys([KEY_D,KEY_E])
			62: _keys([KEY_SHIFT,KEY_D,KEY_S])
			76: _keys([])
			80: _keys([KEY_SPACE])
			81: _keys([])
			82: _keys([KEY_SPACE])
			83: _keys([])
			84: _keys([KEY_SPACE,KEY_W])
			85: _keys([KEY_W])
			100: _keys([])
		await _ticks(3)
		var mech = scene.hero
		var fc = mech.controller
		var expected := {8:2.0,38:1.0,40:0.5,42:0.0,80:0.5,82:1.0,84:2.0}
		if expected.has(frame): assert(fc.DETENTS[fc.detent] == expected[frame], "Native key press changed more than one detent")
		scene.camera.position = mech.position + Vector3(165,55,115)
		scene.camera.look_at(mech.position)
		scene._update_flight_stats()
		await _save(output.path_join("flight-%03d.png" % frame))
		assert(mech.scale.is_equal_approx(Vector3.ONE), "Physics root was scaled")
		assert(mech.position.is_finite() and fc.velocity.is_finite())
		assert(not mech.actor.animation_player.is_playing())
		_check_mounts(mech)
		saw_brake = saw_brake or fc.brake_amount > 0.9
		saw_zero = saw_zero or (frame > 45 and fc.delivered_thrust == 0)
		saw_rotation = saw_rotation or (frame > 45 and frame < 60 and fc.rotation_command.length() > 0.9)
		records.append({"frame":frame,"detent":fc.DETENTS[fc.detent],"engine":fc.engine_level,
			"hover":fc.hover_assist,"aero":fc.aero_authority,"velocity":str(fc.velocity),
			"rotation":str(fc.rotation_command),"main_force":str(fc.main_force),
			"aero_force":str(fc.aero_force),"rcs_torque":str(fc.rcs_torque),
			"brake":fc.brake_amount,"torque_saturated":fc.torque_saturated})
	assert(saw_brake and saw_zero and saw_rotation, "Replay missed braking, main cutoff or free rotation")
	_keys([])
	scene.hero.debug_forces = true
	scene.hero.update_force_debug()
	await _save(output.path_join("forces.png"))
	scene.animate = false
	var frozen: Transform3D = scene.hero.global_transform
	await _ticks(6)
	assert(scene.hero.global_transform.is_equal_approx(frozen), "Native replay did not pause")
	var data := FileAccess.open(output.path_join("telemetry.json"),FileAccess.WRITE)
	data.store_string(JSON.stringify(records,"  "))
	data.close()
	# Supplied poses remain in the Animation dock; authored flight stays stopped.
	assert(scene.hero.actor.animation_player.has_animation(&"GunPose"))
	scene.queue_free()
	await process_frame
	completed = true
	print("Native rigid flight checks passed: real Space/C detents, Shift braking, continuous six-axis flight, main cutoff, free rotation, gimbal limits, mounted boosters, force diagnostics and pause.")
	quit()

func _check_mounts(mech) -> void:
	for index in 10:
		var pivot: Node3D = (mech.gimbals + mech.gas_gimbals)[index]
		var socket: BoneAttachment3D = (mech.sockets + mech.gas_sockets)[index]
		var relative: Basis = mech.neutral_bases[index].inverse() * pivot.basis
		assert(relative.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) <= mech.VECTOR_LIMIT + 0.001)
		var bone: int = mech.skeleton.find_bone(socket.bone_name)
		assert(socket.global_transform.is_equal_approx(mech.skeleton.global_transform * mech.bone_poses[bone]), "Booster left its animated inlay")
