extends SceneTree

# Native check for the existing Risk of Rain 2 material variants and template.
# godot --path demo --script res://scripts/tests/capture_shader_variants.gd -- /tmp/variants.png
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(15).timeout.connect(func(): push_error("Native shader check timed out"); quit(1))
	assert(DisplayServer.get_name() != "headless","Shader validation requires a native renderer")
	root.size = Vector2i(960,400)
	var stage := Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.08,0.08,0.10)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.4
	stage.add_child(world)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position.z = 10
	camera.fov = 40
	camera.current = true
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	sun.rotation_degrees = Vector3(-30,-30,0)
	var shaders: Array[Shader] = []
	for name in ["base","aniso","transp","translucent"]:
		shaders.append(load("res://shaders/cel-shader-"+name+".gdshader"))
	var source := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../src/cel-shader-base.gdshader"))
	var height_map := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../src/includes/height-map.gdshaderinc"))
	source = source.replace('#include "includes/height-map.gdshaderinc"',height_map)
	# Shared includes are byte-checked against src by tools/check_godot.py.
	source = source.replace('"includes/','"res://shaders/includes/')
	for height in [false,true]:
		# File loading runs Godot's include/define preprocessor; Shader.code does not.
		var path := OS.get_user_data_dir().path_join("shader-check-%d-%s.gdshader"%[OS.get_process_id(),height])
		var file := FileAccess.open(path,FileAccess.WRITE)
		assert(file != null)
		file.store_string(source.replace("#define USE_HEIGHT_MAP 0","#define USE_HEIGHT_MAP 1") if height else source)
		file.close()
		var shader := ResourceLoader.load(path,"Shader",ResourceLoader.CACHE_MODE_IGNORE) as Shader
		DirAccess.remove_absolute(path)
		shaders.append(shader)
	for index in shaders.size():
		assert(shaders[index].get_shader_uniform_list().any(func(uniform): return uniform.name=="color"),"Shader did not compile its material interface")
		var mesh := MeshInstance3D.new()
		mesh.mesh = SphereMesh.new()
		var material := ShaderMaterial.new()
		material.shader = shaders[index]
		material.set_shader_parameter("color",Color(0.3,0.65,0.9,0.65 if index==2 else 1.0))
		var texture := GradientTexture1D.new()
		texture.gradient = Gradient.new()
		material.set_shader_parameter("base_texture",texture)
		mesh.material_override = material
		mesh.position.x = (index-2.5)*1.5
		stage.add_child(mesh)
	for frame in 12: await process_frame
	RenderingServer.force_draw()
	var picture := root.get_texture().get_image()
	assert(not picture.is_empty())
	var args := OS.get_cmdline_user_args()
	assert(picture.save_png(args[0] if not args.is_empty() else "/tmp/shader-variants.png")==OK)
	stage.queue_free()
	await process_frame
	print("Native shader variants rendered: painted, anisotropic, transparent, translucent, distributable and height-mapped.")
	quit()
