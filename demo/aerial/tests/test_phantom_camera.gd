extends SceneTree

# Run at each rate: godot --headless --fixed-fps 144 --path demo --script res://aerial/tests/test_phantom_camera.gd -- 144
# Real native body motion at 60 Hz, sampled at mismatched render rates.
var completed := false
var scene

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(45).timeout.connect(func():
		if not completed: push_error("Phantom Camera checks did not finish"); quit(1))
	root.size = Vector2i(1280,720)
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_unhandled_input(false)
	scene.animate = false
	scene.hero.custom_integrator = true
	await process_frame
	await process_frame
	assert(scene.camera.camera_host.get_active_pcam() == scene.camera.phantom_camera)
	assert(scene.camera.camera_host.process_mode == Node.PROCESS_MODE_DISABLED)
	assert(not scene.camera.is_physics_interpolated_and_enabled(),"Camera is being interpolated twice")
	assert(scene.hero.is_physics_interpolated_and_enabled())
	assert(scene.camera.fov == 65 and scene.camera.far == 7000)
	var args := OS.get_cmdline_user_args()
	Engine.max_fps = 144 if args.is_empty() else int(args[0])
	assert(await _fast_motion(Vector3(900,700,-1100)))
	# Live mouse input must not teleport to the velocity lead on every event.
	scene.animate = true
	var live_camera: Transform3D = scene.camera.global_transform
	scene.camera.orbit(Vector2(130,-50))
	assert(scene.camera.global_transform == live_camera,"Mouse input snapped the moving camera")
	scene.camera.update_view(1.0/Engine.max_fps)
	assert(scene.camera.global_position.distance_to(live_camera.origin)<50)
	scene.animate = false
	# Orbit, zoom and focus remain usable while paused; no zero-delta NaNs.
	scene.hero.freeze = true
	scene.camera.orbit(Vector2(130,-50))
	assert(scene.camera.global_transform.is_finite())
	assert(scene.camera.global_basis.y.dot(Vector3.UP)>0.9,"Orbit rolled the horizon")
	var before: Vector3 = scene.camera.global_position
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	scene._unhandled_input(wheel)
	assert(scene.camera.global_position.distance_to(before)>1,"Zoom stopped working")
	scene.camera.focus_next()
	scene.camera.update_view(0.0)
	var aim: Vector3 = (scene.wingman.get_global_transform_interpolated().origin-scene.camera.global_position).normalized()
	assert((-scene.camera.global_basis.z).dot(aim)>0.9999,"Focus did not aim at the rendered target")
	scene.camera.orbit(Vector2.ZERO)
	assert(scene.camera.focus_target == null)
	# Teleports must cut immediately, without dragging history across the world.
	scene.hero.reset_flight(Vector3(0,15000,0))
	await process_frame # Godot refreshes its rendered-transform cache each frame.
	scene.camera.update_view(1.0/144)
	assert(scene.hero.get_global_transform_interpolated().origin.distance_to(scene.hero.global_position)<0.01)
	assert(scene.camera.global_position.distance_to(scene.hero.global_position)<500)
	scene.camera.follow_enabled = false
	var frozen: Transform3D = scene.camera.global_transform
	scene.camera.update_view(1.0/144)
	assert(scene.camera.global_transform == frozen,"Camera overwrote a fixed capture view")
	scene.queue_free()
	await process_frame
	completed = true
	print("Phantom Camera checks passed: fast follow, sub-tick sampling, focus, orbit, zoom, reset, teleport and fixed capture views.")
	quit()

func _fast_motion(speed: Vector3) -> bool:
	scene.hero.freeze = true
	scene.hero.reset_flight(Vector3(175,9000,340))
	scene.hero.linear_velocity = speed
	scene.hero.freeze = false
	scene.camera.reset_view()
	var time := 0.0
	var min_uv := Vector2(INF,INF)
	var max_uv := Vector2(-INF,-INF)
	var sub_tick_frames := 0
	var previous_tick := -1
	var previous_target := Vector3.ZERO
	while time<2.2:
		await process_frame
		var dt: float = root.get_process_delta_time()
		time += dt
		scene.camera.update_view(dt)
		var rendered: Vector3 = scene.hero.get_global_transform_interpolated().origin
		assert(scene.camera.camera_target.global_position.distance_to(rendered+Vector3.UP*17.5)<0.01,"Camera sampled a raw physics transform")
		var tick := Engine.get_physics_frames()
		if tick==previous_tick and rendered.distance_to(previous_target)>0.01: sub_tick_frames += 1
		previous_tick = tick
		previous_target = rendered
		if time<1.2: continue # Let native follow damping settle.
		var uv: Vector2 = scene.camera.unproject_position(rendered)/Vector2(root.size)
		assert(not scene.camera.is_position_behind(rendered) and Rect2(0.1,0.1,0.8,0.8).has_point(uv),"Fast flight escaped the frame")
		min_uv = min_uv.min(uv)
		max_uv = max_uv.max(uv)
	print("%d FPS: screen drift %s, %d moving sub-tick frames"%[Engine.max_fps,max_uv-min_uv,sub_tick_frames])
	assert((max_uv-min_uv).length()<0.006,"Steady fast flight jitters by more than 0.6% of the viewport")
	if Engine.max_fps>60: assert(sub_tick_frames>20,"High-FPS test never sampled between physics ticks")
	return true
