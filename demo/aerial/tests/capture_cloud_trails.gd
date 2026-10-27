extends "res://aerial/tests/capture_aerial.gd"

const Trail = preload("res://aerial/position_trail.gd")
var metrics := {}

func _capture() -> void:
	create_timer(120.0).timeout.connect(_capture_timeout)
	if DisplayServer.get_name() == "headless":
		push_error("Cloud/trail acceptance requires native rendering")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var output := args[0] if not args.is_empty() else "/tmp/dmc-cloud-trails"
	assert(output.is_absolute_path() and DirAccess.make_dir_recursive_absolute(output) == OK)
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	scene.hud.visible = false
	await _save_frame(output.path_join("sunset.png"))
	scene.set_palette(true)
	await _save_frame(output.path_join("daylight.png"))
	for node in [scene.hero,scene.wingman,scene.missile,scene.get_node("Terrain"),scene.get_node("River")]: node.visible = false
	for trail in scene.trails: trail.visible = false
	for batch in scene.clouds.batches: batch.visible = false
	scene.atmosphere_strength = 0.0
	scene.post_material.set_shader_parameter("post_strength",0.0)
	var preview := MeshInstance3D.new()
	preview.material_override = scene.cloud_material
	preview.position = Vector3(0,1800,0)
	preview.scale = Vector3(170,100,170)
	scene.add_child(preview)
	for variant in scene.clouds.SHAPE_COUNT:
		preview.mesh = scene.clouds.batches[variant].multimesh.mesh
		scene.camera.position = preview.position+Vector3(420,120,460)
		scene.camera.look_at(preview.position+Vector3(0,10,0))
		await _save_frame(output.path_join("cloud-%d-side.png"%variant))
		scene.camera.position = preview.position+Vector3(300,-230,330)
		scene.camera.look_at(preview.position)
		await _save_frame(output.path_join("cloud-%d-underside.png"%variant))
	preview.mesh = scene.clouds.batches[0].multimesh.mesh
	scene.camera.position = preview.position+Vector3(120,430,420)
	scene.camera.look_at(preview.position)
	await _save_frame(output.path_join("cloud-top.png"))
	scene.cloud_material.set_shader_parameter("cloud_edge_strength",0.0)
	await _save_frame(output.path_join("cloud-no-rim.png"))
	_delta(output,"cloud-top.png","cloud-no-rim.png","cloud_rim")
	scene.cloud_material.set_shader_parameter("cloud_edge_strength",1.0)
	scene.cloud_material.set_shader_parameter("cloud_shade_noise_strength",0.0)
	await _save_frame(output.path_join("cloud-no-paint.png"))
	_delta(output,"cloud-top.png","cloud-no-paint.png","cloud_threshold_noise")
	scene.cloud_material.set_shader_parameter("cloud_shade_noise_strength",0.18)
	preview.visible = false
	for style in [Trail.SMOKE,Trail.THIN,Trail.MISSILE]:
		var trail := Trail.new()
		trail.spacing = 6.0
		trail.width = 3.0
		trail.lifetime = 8.0
		scene.add_child(trail)
		var material = scene._vfx_material(PackedColorArray([Color(0.9,0.94,1.0),Color(0.4,0.52,0.65)]))
		trail.configure(material,style)
		for layer_material in trail.palette_materials():
			scene._set_surface_palette(layer_material)
			layer_material.set_shader_parameter("haze_start",100000.0)
			layer_material.set_shader_parameter("wind_velocity",Vector3.ZERO)
			layer_material.set_shader_parameter("wind_curl",0.0)
		for index in 81:
			trail.set_time(16.0+float(index)*0.05)
			trail.sample_position(Vector3(-150+float(index)*3.75,1800+sin(float(index)*0.07)*20,0))
		trail.set_time(20.0)
		trail.set_process(false)
		scene.camera.fov = 40.0
		scene.camera.position = Vector3(0,1830,300)
		scene.camera.look_at(Vector3(0,1800,0))
		var label: String = ["smoke","thin","missile"][style]
		await _save_frame(output.path_join(label+"-layers.png"))
		if style == Trail.SMOKE:
			var roll_speed: float = trail.material_override.get_shader_parameter("trail_roll_speed")
			trail.vapor.visible = false
			await _save_frame(output.path_join("smoke-core-only.png"))
			_delta(output,"smoke-layers.png","smoke-core-only.png","vapor_layer")
			trail.vapor.visible = true
			trail.material_override.set_shader_parameter("trail_opacity",0.0)
			await _save_frame(output.path_join("smoke-vapor-only.png"))
			_delta(output,"smoke-layers.png","smoke-vapor-only.png","geometric_core")
			trail.material_override.set_shader_parameter("trail_opacity",1.0)
			trail.vapor.visible = false
			for layer_material in trail.palette_materials(): layer_material.set_shader_parameter("expansion",0.0)
			trail.material_override.set_shader_parameter("trail_roll_speed",0.0)
			await _save_frame(output.path_join("smoke-no-spin.png"))
			trail.material_override.set_shader_parameter("trail_roll_speed",roll_speed)
			await _save_frame(output.path_join("smoke-spin.png"))
			_delta(output,"smoke-no-spin.png","smoke-spin.png","age_spin")
			trail.material_override.set_shader_parameter("trail_roll_speed",0.0)
			trail.material_override.set_shader_parameter("expansion",3.0)
			await _save_frame(output.path_join("smoke-expanded.png"))
			_delta(output,"smoke-no-spin.png","smoke-expanded.png","age_expansion")
			for layer_material in trail.palette_materials(): layer_material.set_shader_parameter("sun_direction",-scene.sun_direction)
			await _save_frame(output.path_join("smoke-opposite-sun.png"))
			_delta(output,"smoke-expanded.png","smoke-opposite-sun.png","directional_smoke")
		if style == Trail.THIN:
			trail.material_override.set_shader_parameter("haze_start",0.0)
			trail.material_override.set_shader_parameter("haze_distance",100.0)
			await _save_frame(output.path_join("thin-distance-faded.png"))
			trail.visible = false
			await _save_frame(output.path_join("thin-distance-hidden.png"))
			assert(Image.load_from_file(output.path_join("thin-distance-faded.png")).get_data() == Image.load_from_file(output.path_join("thin-distance-hidden.png")).get_data(),"Distant trail retained an opaque silhouette")
			trail.visible = true
			trail.material_override.set_shader_parameter("haze_start",100000.0)
			trail.material_override.set_shader_parameter("haze_distance",6500.0)
		if style == Trail.MISSILE:
			scene.environment.glow_enabled = false
			await _save_frame(output.path_join("missile-no-bloom.png"))
			_delta(output,"missile-layers.png","missile-no-bloom.png","missile_bloom")
			scene.environment.glow_enabled = true
			trail.emissive_core.visible = false
			await _save_frame(output.path_join("missile-smoke-only.png"))
			_delta(output,"missile-layers.png","missile-smoke-only.png","missile_emissive_core")
		trail.set_time(30.0)
		await _save_frame(output.path_join(label+"-expired.png"))
		trail.visible = false
		await _save_frame(output.path_join(label+"-hidden.png"))
		assert(Image.load_from_file(output.path_join(label+"-expired.png")).get_data() == Image.load_from_file(output.path_join(label+"-hidden.png")).get_data(),"Expired trail layer remained visible: "+label)
		trail.queue_free()
		await process_frame
	metrics["captures"] = capture_statistics
	var report := FileAccess.open(output.path_join("cloud-trail-metrics.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(metrics,"  "))
	scene.queue_free()
	await process_frame
	completed = true
	print("Cloud/trail native acceptance passed: mesh views, painted bands, layer isolation, age spin/expansion, directional smoke, missile bloom and full expiry. ",output)
	quit()

func _delta(output: String, first: String, second: String, label: String) -> void:
	var a := Image.load_from_file(output.path_join(first))
	var b := Image.load_from_file(output.path_join(second))
	var delta := 0.0
	var count := 0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			delta += Vector3(ca.r-cb.r,ca.g-cb.g,ca.b-cb.b).length()
			count += 1
	delta /= maxi(count,1)
	metrics[label] = delta
	if delta <= 0.000001:
		push_error("A/B contribution was invisible: "+label)
		quit(1)
