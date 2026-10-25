extends SceneTree

var capture_statistics := {}
var completed := false

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	create_timer(30.0).timeout.connect(_capture_timeout)
	if DisplayServer.get_name() == "headless":
		push_error("Visual capture requires a rendering display driver")
		quit(1)
		return
	var arguments := OS.get_cmdline_user_args()
	var output := arguments[0] if not arguments.is_empty() else "/tmp/godot-dmc-captures"
	if not output.is_absolute_path() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Capture output must be a writable absolute directory: "+output)
		quit(1)
		return
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	scene.hud.visible = false
	# Dummy/headless rendering does not retain MultiMesh transform readbacks.
	# Verify the actual GPU instance placement against the weather transforms here.
	for bank in scene.clouds.bank_transforms.size():
		var batch: MultiMeshInstance3D = scene.clouds.batches[bank%scene.clouds.SHAPE_COUNT]
		assert(batch.multimesh.get_instance_transform(bank/scene.clouds.SHAPE_COUNT).is_equal_approx(scene.clouds.bank_transforms[bank]),"Visible cloud transform differs from its weather volume")
	var trail: MultiMeshInstance3D = scene.trails[0]
	var first := trail.multimesh.get_instance_transform(0)
	var second := trail.multimesh.get_instance_transform(1)
	var direction := (second.origin-first.origin).normalized()
	assert(absf(second.basis.z.normalized().dot(direction)) > 0.999,"Trail puffs do not follow their trajectory")
	assert(second.basis.z.length() > second.basis.x.length()*1.4,"Trail puffs lost their overlapping elongated shape")
	scene.post_material.set_shader_parameter("post_strength",0.0)
	await _save_frame(output.path_join("sunset-no-post.png"))
	scene.post_material.set_shader_parameter("post_strength",1.0)
	await _save_frame(output.path_join("sunset.png"))
	scene.set_palette(true)
	await _save_frame(output.path_join("daylight.png"))
	var initial_camera: Transform3D = scene.camera.transform
	scene.camera.position = scene.hero.global_position+Vector3(-120,65,80)
	scene.camera.look_at(scene.hero.global_position)
	await _save_frame(output.path_join("aircraft-top.png"))
	scene.camera.position = scene.hero.global_position+Vector3(-90,-55,100)
	scene.camera.look_at(scene.hero.global_position)
	await _save_frame(output.path_join("aircraft-underside.png"))
	scene.camera.transform = initial_camera
	scene.trigger_explosion()
	scene.explosion.set_process(false)
	scene.explosion.set_time(0.7)
	await _save_frame(output.path_join("explosion.png"))
	for time in [0.2,1.8,3.4]:
		scene.explosion.set_time(time)
		await _save_frame(output.path_join("explosion-"+str(time)+".png"))
	scene.explosion.set_time(0.7)
	var outside: Vector3 = scene.camera.position
	var bank: Vector4 = scene.clouds.banks[0]
	scene.camera.position = scene.clouds.to_global(Vector3(bank.x,bank.y,bank.z))
	await _save_frame(output.path_join("inside-cloud.png"))
	scene.storm = true
	scene.set_palette(true)
	await _save_frame(output.path_join("storm-rain.png"))
	scene.camera.position = outside
	scene._process(0.0)
	scene.set_process(false)
	scene.post_material.set_shader_parameter("rain_strength",0.0)
	await _save_frame(output.path_join("storm-clear.png"))
	scene.post_material.set_shader_parameter("rain_strength",1.0)
	scene.post_material.set_shader_parameter("weather_time",2.3)
	await _save_frame(output.path_join("rain-on-geometry.png"))
	var dry := Image.load_from_file(output.path_join("storm-clear.png"))
	var wet := Image.load_from_file(output.path_join("rain-on-geometry.png"))
	assert(dry.get_data() != wet.get_data(),"Rain produced no visible change on scene geometry")
	var before := Image.load_from_file(output.path_join("sunset-no-post.png"))
	var after := Image.load_from_file(output.path_join("sunset.png"))
	assert(before.get_data() != after.get_data(),"Post processing did not change the captured frame")
	var statistics := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"captures": capture_statistics,
		"note": "Desktop capture counters; not a mobile device benchmark."
	}
	var report := FileAccess.open(output.path_join("render-stats.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(statistics,"  "))
	scene.queue_free()
	await process_frame
	completed = true
	print("Aerial comparison captures: ",output)
	quit()

func _save_frame(path: String) -> void:
	print("Capturing ",path.get_file())
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(not image.is_empty(),"Renderer returned an empty frame")
	assert(image.save_png(path) == OK,"Could not save comparison frame")
	capture_statistics[path.get_file()] = {
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	}

func _capture_timeout() -> void:
	if not completed:
		push_error("Aerial capture timed out waiting for rendered frames. Keep the capture window visible.")
		quit(1)
