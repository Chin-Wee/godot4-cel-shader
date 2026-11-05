extends "res://aerial/tests/capture_aerial.gd"

var lighting_metrics := {}

func _capture() -> void:
	create_timer(90.0).timeout.connect(_capture_timeout)
	if DisplayServer.get_name() == "headless":
		push_error("Lighting validation requires a native rendering display")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var output := args[0] if not args.is_empty() else "/tmp/dmc-lighting"
	assert(output.is_absolute_path() and DirAccess.make_dir_recursive_absolute(output) == OK)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	assert(scene.lighting.post_material.get_shader_parameter("sun_visible") == 0.0,"Optics opened before the first depth mask")
	assert(scene.lighting.post_material.get_shader_parameter("solar_visibility_texture") == null,"Uninitialized GPU mask was bound to the Canvas shader")
	scene.animate = false
	scene.hud.visible = false
	await _save_frame(output.path_join("full.png"))
	assert(scene.lighting.volume_effect.get_status().ready,"Atmospheric compositor did not initialize")
	assert(scene.lighting.post_material.get_shader_parameter("use_depth_occlusion"),"Optics still use luminance occlusion")
	var full := Image.load_from_file(output.path_join("full.png"))
	for component in ["glare_strength","corona_strength","starburst_strength","streak_strength","ring_strength","flare_strength","veil_strength"]:
		var saved = scene.lighting.post_material.get_shader_parameter(component)
		scene.lighting.post_material.set_shader_parameter(component,0.0)
		await _save_frame(output.path_join(component+"-off.png"))
		_record_difference(full,output.path_join(component+"-off.png"),component)
		scene.lighting.post_material.set_shader_parameter(component,saved)
	for component in ["cloud_scattering_strength","cloud_bank_glow_strength","cloud_edge_strength"]:
		var saved = scene.lighting.cloud_material.get_shader_parameter(component)
		scene.lighting.cloud_material.set_shader_parameter(component,0.0)
		await _save_frame(output.path_join(component+"-off.png"))
		_record_difference(full,output.path_join(component+"-off.png"),component)
		scene.lighting.cloud_material.set_shader_parameter(component,saved)
	for component in ["haze_sun_strength","sky_fill_strength"]:
		var saved := []
		for material in scene.lighting.palette_materials:
			saved.append(material.get_shader_parameter(component))
			material.set_shader_parameter(component,0.0)
		await _save_frame(output.path_join(component+"-off.png"))
		_record_difference(full,output.path_join(component+"-off.png"),component)
		for index in saved.size(): scene.lighting.palette_materials[index].set_shader_parameter(component,saved[index])
	scene.lighting.atmosphere_shadow_strength = 0.0
	await _save_frame(output.path_join("volume-shadows-off.png"))
	_record_difference(full,output.path_join("volume-shadows-off.png"),"volumetric_cloud_shadows")
	scene.lighting.atmosphere_shadow_strength = 1.0
	scene.lighting.atmosphere_strength = 0.0
	await _save_frame(output.path_join("volume-off.png"))
	_record_difference(full,output.path_join("volume-off.png"),"volumetric_scattering")
	scene.lighting.atmosphere_strength = 1.0
	scene.lighting.environment.glow_enabled = false
	await _save_frame(output.path_join("native-glow-off.png"))
	_record_difference(full,output.path_join("native-glow-off.png"),"native_glow")
	scene.lighting.environment.glow_enabled = true
	await _check_occlusion(scene,output)
	await _check_veil(scene,output)
	await _check_optics_gates(scene,output)
	var saved_size := root.size
	var saved_msaa := root.msaa_3d
	root.msaa_3d = Viewport.MSAA_DISABLED
	await _save_frame(output.path_join("msaa-off.png"))
	assert(scene.lighting.volume_effect.get_status().native_depth_samples == 0,"Volume did not select single-sample depth")
	root.msaa_3d = Viewport.MSAA_2X
	await _save_frame(output.path_join("msaa-2x.png"))
	assert(scene.lighting.volume_effect.get_status().native_depth_samples == 1,"Volume did not select multisample depth")
	root.size = Vector2i(1000,600)
	await _save_frame(output.path_join("resized.png"))
	assert(scene.lighting.volume_effect.get_status().quarter_size == Vector2i(ceili(root.size.x/4.0),ceili(root.size.y/4.0)))
	root.size = saved_size
	root.msaa_3d = saved_msaa
	await _save_frame(output.path_join("final.png"))
	var allocation_count: int = scene.lighting.volume_effect.get_status().texture_allocations
	var bake_count: int = scene.lighting.volume_effect.get_status().shadow_bakes
	for frame in 12: await process_frame
	assert(scene.lighting.volume_effect.get_status().texture_allocations == allocation_count,"Volume allocated textures during steady rendering")
	scene.clouds.position.x += 50.0
	await _save_frame(output.path_join("cloud-drift.png"))
	assert(scene.lighting.volume_effect.get_status().shadow_bakes == bake_count,"Rigid cloud drift rebaked the shadow field")
	scene.clouds.set_coverage(0.4)
	await _save_frame(output.path_join("partial-cover.png"))
	assert(scene.lighting.volume_effect.get_status().shadow_bakes > bake_count,"Coverage left stale cloud shadows")
	lighting_metrics["volume_status"] = scene.lighting.volume_effect.get_status()
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	lighting_metrics["gpu_ms_desktop"] = gpu_ms if gpu_ms > 0.0 else null
	lighting_metrics["gpu_timing_available"] = gpu_ms > 0.0
	lighting_metrics["captures"] = capture_statistics
	lighting_metrics["note"] = "Native desktop validation; not a phone performance benchmark."
	var report := FileAccess.open(output.path_join("lighting-metrics.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(lighting_metrics,"  "))
	scene.queue_free()
	for frame in 8: await process_frame
	# Reopen after render-thread resource retirement, rather than only testing process exit.
	var reloaded = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(reloaded)
	reloaded.animate = false
	reloaded.hud.visible = false
	await _save_frame(output.path_join("reloaded.png"))
	assert(reloaded.lighting.volume_effect.get_status().ready,"Atmosphere failed after scene reload")
	reloaded.queue_free()
	for frame in 8: await process_frame
	completed = true
	print("Lighting validation passed: isolated layers, depth occlusion, veil contrast, MSAA, resize and cloud invalidation. ",output)
	quit()

func _record_difference(full: Image, path: String, label: String) -> void:
	var delta := _mean_difference(full,Image.load_from_file(path))
	lighting_metrics[label] = delta
	assert(delta > 0.000001,"Lighting component produced no visible contribution: "+label)

func _mean_difference(a: Image, b: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0,a.get_height(),8):
		for x in range(0,a.get_width(),8):
			var first := a.get_pixel(x,y)
			var second := b.get_pixel(x,y)
			total += Vector3(first.r-second.r,first.g-second.g,first.b-second.b).length()
			count += 1
	return total/maxi(count,1)

func _check_occlusion(scene: Node3D, output: String) -> void:
	var blocker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 18.0
	sphere.height = 36.0
	blocker.mesh = sphere
	blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blocker.material_override = material
	scene.add_child(blocker)
	blocker.global_position = scene.camera.global_position+scene.lighting.sun_direction*150.0
	for sample in [[Color.BLACK,"black"],[Color.WHITE,"white"]]:
		material.albedo_color = sample[0]
		scene.lighting.post_material.set_shader_parameter("post_strength",1.0)
		await _save_frame(output.path_join("occluded-"+sample[1]+".png"))
		assert(scene.lighting.volume_effect.solar_visibility_texture.get_image().get_pixel(0,0).r < 0.01,"Sun optics leaked through "+sample[1]+" geometry")
		scene.lighting.post_material.set_shader_parameter("post_strength",0.0)
		await _save_frame(output.path_join("occluded-"+sample[1]+"-raw.png"))
		var delta := _mean_difference(Image.load_from_file(output.path_join("occluded-"+sample[1]+".png")),Image.load_from_file(output.path_join("occluded-"+sample[1]+"-raw.png")))
		assert(delta < 0.0001,"Optical layers survived source occlusion")
	blocker.queue_free()
	scene.lighting.post_material.set_shader_parameter("post_strength",1.0)
	await process_frame

func _check_veil(scene: Node3D, output: String) -> void:
	var components := ["glare_strength","corona_strength","starburst_strength","streak_strength","ring_strength","flare_strength","veil_strength"]
	var saved := {}
	for component in components:
		saved[component] = scene.lighting.post_material.get_shader_parameter(component)
		scene.lighting.post_material.set_shader_parameter(component,0.0)
	var layer := CanvasLayer.new()
	layer.layer = 0
	scene.add_child(layer)
	var sun_uv: Vector2 = scene.lighting.post_material.get_shader_parameter("sun_uv")
	var points := [sun_uv+Vector2(-0.07,0.035),sun_uv+Vector2(0.07,0.035)]
	for index in 2:
		var patch := ColorRect.new()
		patch.color = Color(0.15,0.15,0.15) if index == 0 else Color(0.45,0.45,0.45)
		patch.position = points[index]*Vector2(root.size)-Vector2(12,12)
		patch.size = Vector2(24,24)
		layer.add_child(patch)
	await _save_frame(output.path_join("veil-probe-off.png"))
	var raw := Image.load_from_file(output.path_join("veil-probe-off.png"))
	scene.lighting.post_material.set_shader_parameter("veil_strength",0.8)
	await _save_frame(output.path_join("veil-probe-on.png"))
	var veiled := Image.load_from_file(output.path_join("veil-probe-on.png"))
	var raw_contrast := absf(_luma(raw,points[0])-_luma(raw,points[1]))
	var veiled_contrast := absf(_luma(veiled,points[0])-_luma(veiled,points[1]))
	assert(veiled_contrast < raw_contrast*0.99,"Veiling glare did not reduce local contrast")
	lighting_metrics["veil_contrast_ratio"] = veiled_contrast/raw_contrast
	layer.queue_free()
	for component in saved: scene.lighting.post_material.set_shader_parameter(component,saved[component])
	await process_frame

func _luma(picture: Image, uv: Vector2) -> float:
	var color := picture.get_pixelv(Vector2i(uv*Vector2(picture.get_size())))
	return color.r*0.2126+color.g*0.7152+color.b*0.0722

func _check_optics_gates(scene: Node3D, output: String) -> void:
	var initial: Transform3D = scene.camera.transform
	for sample in [[-scene.lighting.sun_direction,"behind"],[Vector3(0.4,0.0,-1.0),"offscreen"]]:
		scene.camera.look_at(scene.camera.global_position+sample[0]*1000.0)
		await _assert_optics_hidden(scene,output,sample[1])
	scene.camera.transform = initial
	scene.lighting.storm = true
	scene.set_palette(false)
	await _assert_optics_hidden(scene,output,"storm")
	scene.lighting.storm = false
	scene.set_palette(false)
	scene.camera.global_position = scene.clouds.to_global(scene.clouds.bank_transforms[0].origin)
	assert(scene.clouds.density_at(scene.camera.global_position) > 0.99,"Cloud-entry gate probe missed the bank")
	await _assert_optics_hidden(scene,output,"cloud-interior")
	scene.camera.transform = initial
	await process_frame

func _assert_optics_hidden(scene: Node3D, output: String, label: String) -> void:
	scene.lighting.post_material.set_shader_parameter("post_strength",1.0)
	await _save_frame(output.path_join(label+"-post.png"))
	scene.lighting.post_material.set_shader_parameter("post_strength",0.0)
	await _save_frame(output.path_join(label+"-raw.png"))
	var difference := _mean_difference(Image.load_from_file(output.path_join(label+"-post.png")),Image.load_from_file(output.path_join(label+"-raw.png")))
	assert(difference < 0.0001,"Solar optics survived the "+label+" visibility gate")
	lighting_metrics[label+"_optics_delta"] = difference
	scene.lighting.post_material.set_shader_parameter("post_strength",1.0)
