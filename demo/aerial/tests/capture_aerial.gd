extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	assert(DisplayServer.get_name() != "headless","Visual capture requires a rendering display driver")
	var arguments := OS.get_cmdline_user_args()
	var output := arguments[0] if not arguments.is_empty() else "/tmp/godot-dmc-captures"
	DirAccess.make_dir_recursive_absolute(output)
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	scene.hud.visible = false
	await _save_frame(output.path_join("sunset.png"))
	scene.set_palette(true)
	await _save_frame(output.path_join("daylight.png"))
	scene.trigger_explosion()
	scene.explosion.set_process(false)
	scene.explosion.set_time(0.7)
	await _save_frame(output.path_join("explosion.png"))
	var bank: Vector4 = scene.clouds.banks[0]
	scene.camera.position = scene.clouds.to_global(Vector3(bank.x,bank.y,bank.z))
	await _save_frame(output.path_join("inside-cloud.png"))
	var statistics := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"note": "Desktop capture counters; not a mobile device benchmark."
	}
	var report := FileAccess.open(output.path_join("render-stats.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(statistics,"  "))
	scene.queue_free()
	await process_frame
	print("Aerial comparison captures: ",output)
	quit()

func _save_frame(path: String) -> void:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(not image.is_empty(),"Renderer returned an empty frame")
	assert(image.save_png(path) == OK,"Could not save comparison frame")
