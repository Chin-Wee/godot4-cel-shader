extends SceneTree
func _initialize(): call_deferred("probe")
func probe():
	if DisplayServer.get_name() == "headless":
		push_error("Soft-depth capture requires a rendering display driver")
		quit(1)
		return
	create_timer(20.0).timeout.connect(func(): quit(1))
	var stage:=Node3D.new()
	root.add_child(stage)
	var world:=WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color(0.09,0.11,0.16)
	stage.add_child(world)
	var plane:=MeshInstance3D.new()
	plane.mesh=PlaneMesh.new()
	plane.mesh.size=Vector2(20,20)
	var floor_material:=StandardMaterial3D.new()
	floor_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.albedo_color=Color(0.12,0.28,0.24)
	plane.material_override=floor_material
	stage.add_child(plane)
	for index in 2:
		var sphere:=MeshInstance3D.new()
		sphere.mesh=SphereMesh.new()
		sphere.mesh.radius=1.0
		sphere.mesh.height=2.0
		var gradient:=Gradient.new()
		gradient.colors=PackedColorArray([Color(0.9,0.7,0.3),Color(0.9,0.7,0.3)])
		var ramp:=GradientTexture1D.new()
		ramp.gradient=gradient
		var material:=ShaderMaterial.new()
		material.shader=load("res://shaders/aerial/mesh-vfx.gdshader")
		material.set_shader_parameter("color_ramp",ramp)
		material.set_shader_parameter("normalized_age",0.25)
		material.set_shader_parameter("soft_intersection",2.0 if index==1 else 0.0)
		sphere.material_override=material
		sphere.position=Vector3(-1.7 if index==0 else 1.7,0.35,0)
		stage.add_child(sphere)
	var camera:=Camera3D.new()
	camera.position=Vector3(0,3,8)
	stage.add_child(camera)
	camera.look_at(Vector3(0,0.5,0))
	camera.current=true
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_png("/tmp/dmc-soft-depth-probe.png") == OK)
	var left := camera.unproject_position(Vector3(-1.7,0.35,0))
	var right := camera.unproject_position(Vector3(1.7,0.35,0))
	var radius := absf(camera.unproject_position(Vector3(-0.7,0.35,0)).x-left.x)
	var opaque_pixels := _gold_pixels(image,left,radius)
	var soft_pixels := _gold_pixels(image,right,radius)
	assert(soft_pixels < opaque_pixels*0.9 and soft_pixels > opaque_pixels*0.25,"Soft intersection must fade the contact area without removing the whole mesh")
	print("Depth probe captured: left=opaque, right=soft enabled.")
	quit()

func _gold_pixels(image: Image, center: Vector2, radius: float) -> int:
	var count := 0
	for y in range(int(center.y),int(center.y+radius*0.9)):
		for x in range(int(center.x-radius),int(center.x+radius)):
			var color := image.get_pixel(x,y)
			if color.r > color.g*1.05: count += 1
	return count
