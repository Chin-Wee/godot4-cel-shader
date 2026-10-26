extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(15.0).timeout.connect(func(): quit(1))
	for name in ["atmosphere.gdshaderinc","aircraft.gdshader","terrain.gdshader","cloud.gdshader","post.gdshader","sky.gdshader","mesh-vfx.gdshader","afterburner.gdshader","atmosphere-volume.glsl","atmosphere-composite.glsl"]:
		var canonical := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../src/aerial/"+name))
		assert(not canonical.is_empty(),"Canonical surface shader is missing: "+name)
		assert(canonical == FileAccess.get_file_as_string("res://shaders/aerial/"+name),"Runtime surface shader drifted: "+name)
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	await process_frame
	scene.set_palette(false)
	assert(scene.current_haze.b > scene.current_haze.r,"Sunset away-side haze lost its cool separation")
	assert(scene.current_haze_sun_color.r > scene.current_haze_sun_color.b,"Sun-facing haze lost its warm palette")
	assert(scene.current_sky_fill.b > scene.current_sky_fill.r,"Ambient fill must remain cooler than direct sunlight")
	var sunset_scattering: float = scene.current_haze_sun_strength
	var sunset_fill: float = scene.current_sky_fill_strength
	_check_materials(scene)
	scene.trigger_explosion()
	scene.explosion.set_process(false)
	scene.set_palette(true)
	_check_materials(scene)
	scene._vfx_material(PackedColorArray([Color.WHITE,Color.BLACK]))
	_check_materials(scene)
	scene.storm = true
	scene.set_palette(true)
	assert(scene.current_haze_sun_strength < sunset_scattering,"Storm retained clear-sunset directional scattering")
	assert(scene.current_sky_fill_strength < sunset_fill,"Storm retained clear-sunset ambient intensity")
	_check_materials(scene)
	scene.storm = false
	scene.set_palette(false)
	_check_materials(scene)
	scene.queue_free()
	await process_frame
	print("Surface lighting checks passed: source copies, warm/cool palette and persistent/new/live effect transitions.")
	quit()

func _check_materials(scene: Node3D) -> void:
	var expected := {
		"haze_color": scene.current_haze,
		"haze_sun_color": scene.current_haze_sun_color,
		"haze_sun_strength": scene.current_haze_sun_strength,
		"sky_fill_color": scene.current_sky_fill,
		"sky_fill_strength": scene.current_sky_fill_strength,
		"sun_direction": scene.sun_direction,
	}
	var materials: Array = scene.palette_materials.duplicate()
	if is_instance_valid(scene.explosion):
		for node in scene.explosion.get_children():
			if node is MeshInstance3D and node.material_override is ShaderMaterial:
				materials.append(node.material_override)
	for material in materials:
		for parameter in expected:
			assert(material.get_shader_parameter(parameter) == expected[parameter],"Material missed surface palette transition: "+parameter)
