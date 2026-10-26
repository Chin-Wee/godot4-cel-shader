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
	scene.environment.glow_enabled = false
	await _save_frame(output.path_join("sunset-no-glow.png"))
	scene.environment.glow_enabled = true
	await _save_frame(output.path_join("sunset-no-post.png"))
	assert(Image.load_from_file(output.path_join("sunset-no-glow.png")).get_data() != Image.load_from_file(output.path_join("sunset-no-post.png")).get_data(),"Native HDR glow produced no change in the current renderer")
	scene.post_material.set_shader_parameter("post_strength",1.0)
	await _save_frame(output.path_join("sunset.png"))
	var flare_gain = scene.post_material.get_shader_parameter("flare_strength")
	scene.post_material.set_shader_parameter("flare_strength",0.0)
	await _save_frame(output.path_join("sunset-no-flare.png"))
	scene.post_material.set_shader_parameter("flare_strength",flare_gain)
	var sun_uv: Vector2 = scene.post_material.get_shader_parameter("sun_uv")
	var ghost_uv := sun_uv+(Vector2(0.5,0.5)-sun_uv)*2.4
	var occluder := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 12.0
	sphere.height = 24.0
	occluder.mesh = sphere
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	occluder.material_override = black
	occluder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(occluder)
	occluder.global_position = scene.camera.global_position+scene.sun_direction.normalized()*150.0
	await _save_frame(output.path_join("sun-occluded-post.png"))
	scene.post_material.set_shader_parameter("post_strength",0.0)
	await _save_frame(output.path_join("sun-occluded-raw.png"))
	var visible_delta := _post_difference(Image.load_from_file(output.path_join("sunset-no-flare.png")),Image.load_from_file(output.path_join("sunset.png")),ghost_uv)
	var hidden_delta := _post_difference(Image.load_from_file(output.path_join("sun-occluded-raw.png")),Image.load_from_file(output.path_join("sun-occluded-post.png")),ghost_uv)
	assert(visible_delta > 0.001,"Sun optics produced no visible flare")
	assert(hidden_delta < visible_delta*0.2+0.001,"Sun flare shone through its occluder")
	print("Solar probe: visible ghost delta=",visible_delta," occluded delta=",hidden_delta)
	occluder.queue_free()
	await process_frame
	scene.post_material.set_shader_parameter("post_strength",1.0)
	scene.set_palette(true)
	await _save_frame(output.path_join("daylight.png"))
	var initial_camera: Transform3D = scene.camera.transform
	var aircraft_basis: Basis = scene.hero.global_basis.orthonormalized()
	scene.camera.position = scene.hero.global_position+aircraft_basis*Vector3(-90,65,100)
	scene.camera.look_at(scene.hero.global_position,aircraft_basis.y)
	await _save_frame(output.path_join("aircraft-top.png"))
	scene.camera.position = scene.hero.global_position+aircraft_basis*Vector3(-90,-65,100)
	scene.camera.look_at(scene.hero.global_position,aircraft_basis.y)
	await _save_frame(output.path_join("aircraft-underside.png"))
	scene.camera.position = scene.hero.global_position+aircraft_basis*Vector3(-80,45,-110)
	scene.camera.look_at(scene.hero.global_position,aircraft_basis.y)
	await _save_frame(output.path_join("aircraft-front.png"))
	var nozzle: MeshInstance3D = scene.hero.find_child("EngineFlame*",false,false)
	assert(nozzle != null,"Afterburner inspection target is missing")
	scene.camera.position = nozzle.global_position+aircraft_basis*Vector3(-27,9,10)
	scene.camera.look_at(nozzle.global_position+aircraft_basis*Vector3(0,0,8),aircraft_basis.y)
	for sample in [[0.0,"off"],[0.35,"low"],[1.0,"full"]]:
		scene.set_afterburner_throttle(sample[0])
		await _save_frame(output.path_join("afterburner-"+sample[1]+".png"))
	scene.afterburner_material.set_shader_parameter("flow_phase",100.0)
	await _save_frame(output.path_join("afterburner-wrap.png"))
	assert(_post_difference(Image.load_from_file(output.path_join("afterburner-full.png")),Image.load_from_file(output.path_join("afterburner-wrap.png")),Vector2(0.5,0.5)) < 0.01,"Exhaust texture jumped at the bounded clock wrap")
	scene._update_afterburners(0.4)
	await _save_frame(output.path_join("afterburner-flow.png"))
	assert(Image.load_from_file(output.path_join("afterburner-full.png")).get_data() != Image.load_from_file(output.path_join("afterburner-flow.png")).get_data(),"Exhaust flow did not animate on the GPU")
	var aircraft_scale: Vector3 = scene.hero.scale
	scene.hero.scale *= Vector3(1.4,0.75,1.6)
	scene.camera.position = nozzle.global_position+aircraft_basis*Vector3(-33,9,15)
	scene.camera.look_at(nozzle.global_position+aircraft_basis*Vector3(0,0,12),aircraft_basis.y)
	await _save_frame(output.path_join("afterburner-stretched.png"))
	scene.hero.scale = aircraft_scale
	scene.afterburner_flow_phase = 0.0
	scene._update_afterburners()
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
		"solar_probe": {"visible_ghost_delta": visible_delta,"occluded_post_delta": hidden_delta},
		"note": "Desktop capture counters; not a mobile device benchmark."
	}
	var report := FileAccess.open(output.path_join("render-stats.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(statistics,"  "))
	scene.queue_free()
	await process_frame
	completed = true
	print("Aerial comparison captures: ",output)
	quit()

func _post_difference(before: Image, after: Image, uv: Vector2) -> float:
	var center := Vector2i(uv*Vector2(before.get_size()))
	var difference := 0.0
	var samples := 0
	for y in range(center.y-32,center.y+33,4):
		for x in range(center.x-32,center.x+33,4):
			if x < 0 or y < 0 or x >= before.get_width() or y >= before.get_height(): continue
			var a := before.get_pixel(x,y)
			var b := after.get_pixel(x,y)
			difference += Vector3(b.r-a.r,b.g-a.g,b.b-a.b).length()
			samples += 1
	return difference/maxi(samples,1)

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
		push_error("Aerial capture did not finish; inspect earlier errors or keep a stalled render window visible.")
		quit(1)
