extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cloud tone validation requires a native renderer")
		quit(1)
		return
	create_timer(20.0).timeout.connect(func(): quit(1))
	assert(FileAccess.get_file_as_string("res://shaders/aerial/cloud.gdshader") == FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../src/aerial/cloud.gdshader")),"Cloud shader copies differ")
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLACK
	stage.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.position = Vector3(0,0,8)
	stage.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/aerial/cloud.gdshader")
	material.set_shader_parameter("cloud_light",Color(0.8,0.8,0.8))
	material.set_shader_parameter("cloud_shadow",Color(0.08,0.08,0.08))
	material.set_shader_parameter("haze_start",100000.0)
	for parameter in ["sky_fill_strength","cloud_scattering_strength","cloud_bank_glow_strength","cloud_edge_strength","cloud_shade_noise_strength","ndotl_dither_strength"]:
		material.set_shader_parameter(parameter,0.0)
	var panels: Array[MeshInstance3D] = []
	for index in 3:
		var panel := MeshInstance3D.new()
		panel.mesh = _panel([-0.4,0.3,0.9][index])
		panel.position.x = (index-1)*2.3
		panel.material_override = material
		stage.add_child(panel)
		panels.append(panel)
	await _frame()
	var bands := root.get_texture().get_image()
	bands.save_png("/tmp/dmc-cloud-three-tones.png")
	var brightness := []
	for panel in panels:
		var uv := camera.unproject_position(panel.global_position)/Vector2(root.size)
		var color := bands.get_pixelv(Vector2i(uv*Vector2(bands.get_size())))
		brightness.append(color.r)
	assert(brightness[1] > brightness[0]+0.05 and brightness[2] > brightness[1]+0.05,"Cloud shader did not produce three distinct directional tones")
	for panel in panels: panel.mesh = _panel(0.05)
	await _frame()
	var plain := root.get_texture().get_image()
	material.set_shader_parameter("cloud_shade_noise_strength",0.3)
	material.set_shader_parameter("cloud_shade_noise_scale",0.9)
	await _frame()
	var painted := root.get_texture().get_image()
	painted.save_png("/tmp/dmc-cloud-painted-threshold.png")
	assert(plain.get_data() != painted.get_data(),"Cloud threshold noise produced no painted breakup")
	await _frame()
	assert(root.get_texture().get_image().get_data() == painted.get_data(),"Cloud threshold noise changes while the world is static")
	print("Cloud tone GPU checks passed: three directional planes, painted threshold breakup, static noise and source-copy parity. ",brightness)
	stage.queue_free()
	quit()

func _panel(shade: float) -> ArrayMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0,2.0)
	var arrays := quad.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	normals.fill(Vector3(sqrt(1.0-shade*shade),0,shade))
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _frame() -> void:
	for index in 4: await process_frame
	RenderingServer.force_draw()
