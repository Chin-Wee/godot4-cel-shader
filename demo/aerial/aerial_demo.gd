extends Node3D

const Geometry = preload("res://aerial/geometry.gd")
const PositionTrail = preload("res://aerial/position_trail.gd")
const Explosion = preload("res://aerial/graphic_explosion.gd")
const CloudBanks = preload("res://aerial/cloud_banks.gd")
var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var clouds: Node3D
var hero: Node3D
var wingman: Node3D
var missile: Node3D
var palette_materials: Array[ShaderMaterial] = []
var sky_material: ShaderMaterial
var cloud_material: ShaderMaterial
var animate := true
var elapsed := 0.0
var storm := false
var daylight_palette := false
var sun_direction := Vector3(-0.5,0.22,-0.84)
var post_material: ShaderMaterial
var current_haze := Color(0.54,0.34,0.39)
var hud: CanvasLayer
var trails: Array[MultiMeshInstance3D] = []
var explosion: Node3D
var explosion_clock := 0.0

func _ready() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.14,0.17,0.25)
	environment.ambient_light_energy = 0.25
	environment.fog_light_color = Color(0.45,0.48,0.57)
	environment.fog_density = 0.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	sky_material = _material("sky")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1600.0
	add_child(sun)
	var terrain_material := _material("terrain")
	terrain_material.set_shader_parameter("diffuse_ramp_mode",1)
	terrain_material.set_shader_parameter("diffuse_ramp_threshold",0.20)
	Geometry.add_mesh(self,Geometry.terrain(),terrain_material)
	var river_material := _material("aircraft")
	river_material.set_shader_parameter("body_color",Color(0.055,0.24,0.21))
	river_material.set_shader_parameter("orientation_bias",0.0)
	river_material.set_shader_parameter("panel_strength",0.0)
	river_material.set_shader_parameter("rim_strength",0.05)
	Geometry.add_mesh(self,Geometry.river(),river_material)
	cloud_material = _material("cloud")
	cloud_material.set_shader_parameter("diffuse_ramp_mode",2)
	cloud_material.set_shader_parameter("diffuse_ramp_threshold",0.08)
	cloud_material.set_shader_parameter("diffuse_ramp_smoothing",0.12)
	clouds = CloudBanks.new()
	add_child(clouds)
	clouds.build(cloud_material)
	var body := _material("aircraft")
	body.set_shader_parameter("body_color",Color(0.78,0.29,0.06))
	body.set_shader_parameter("underside_color",Color(0.24,0.10,0.065))
	body.set_shader_parameter("rim_color",Color(1.0,0.90,0.75))
	body.set_shader_parameter("rim_strength",1.25)
	body.set_shader_parameter("highlight_mask",0.08)
	body.set_shader_parameter("diffuse_ramp_mode",1)
	body.set_shader_parameter("diffuse_ramp_threshold",0.12)
	var canopy := _material("aircraft")
	canopy.set_shader_parameter("body_color",Color(0.03,0.12,0.13))
	canopy.set_shader_parameter("underside_color",Color(0.01,0.04,0.06))
	canopy.set_shader_parameter("highlight_mask",1.0)
	canopy.set_shader_parameter("orientation_bias",0.0)
	canopy.set_shader_parameter("panel_strength",0.0)
	canopy.set_shader_parameter("rim_strength",0.35)
	var exhaust := _vfx_material(PackedColorArray([Color(1,0.05,0.22),Color(1,0.2,0.02)]),3.0)
	hero = Geometry.aircraft(body,canopy,exhaust)
	hero.name = "HeroAircraft"
	hero.position = flight_position(0.0)
	hero.rotation = Vector3(0.05,1.4,0.6)
	hero.scale = Vector3.ONE * 1.6
	add_child(hero)
	_update_hero_pose(0.0)
	var wing_body := body.duplicate() as ShaderMaterial
	palette_materials.append(wing_body)
	wing_body.set_shader_parameter("body_color",Color(0.34,0.38,0.29))
	wing_body.set_shader_parameter("underside_color",Color(0.035,0.065,0.07))
	wing_body.set_shader_parameter("panel_color",Color(0.48,0.51,0.34))
	wingman = Geometry.aircraft(wing_body,canopy,exhaust)
	wingman.position = wingman_position(0.0)
	wingman.rotation = Vector3(0.1,0.5,-0.3)
	wingman.scale = Vector3.ONE*0.8
	add_child(wingman)
	camera = Camera3D.new()
	camera.position = Vector3(140,610,540)
	camera.fov = 65
	camera.far = 7000
	add_child(camera)
	camera.look_at(Vector3(-160,550,-800))
	camera.current = true
	missile = Node3D.new()
	missile.position = missile_position(0.0)
	add_child(missile)
	Geometry.add_mesh(missile,Geometry.icosphere(),canopy).scale = Vector3(1,1,4)
	var missile_fire := _vfx_material(PackedColorArray([Color(1,0.55,0.05),Color(1,0.15,0.01)]),3.0)
	var flame := Geometry.add_mesh(missile,Geometry.icosphere(),missile_fire)
	flame.position.z = 5.0
	flame.scale = Vector3(0.8,0.8,3.0)
	_add_trails()
	_make_post()
	_make_hud()
	set_palette(false)

func _material(shader_name: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/aerial/"+shader_name+".gdshader")
	if shader_name != "sky":
		material.set_shader_parameter("haze_color",current_haze)
		palette_materials.append(material)
	return material

func set_palette(daylight: bool) -> void:
	daylight_palette = daylight
	var haze := Color(0.48,0.30,0.36) if not daylight else Color(0.37,0.67,0.76)
	if storm: haze = haze.lerp(Color(0.17,0.20,0.26),0.65)
	current_haze = haze
	for material in palette_materials:
		material.set_shader_parameter("haze_color",haze)
	sky_material.set_shader_parameter("zenith_color",Color(0.27,0.19,0.32) if not daylight else Color(0.035,0.27,0.4))
	sky_material.set_shader_parameter("horizon_color",haze if daylight or storm else Color(0.62,0.39,0.42))
	var direction := Vector3(-0.5,0.22,-0.84) if not daylight else Vector3(-0.4,0.65,-0.64)
	sun_direction = direction
	sky_material.set_shader_parameter("sun_direction",direction)
	sun.look_at_from_position(Vector3.ZERO,-direction)
	sun.light_color = Color(1.0,0.78,0.53) if not daylight else Color(1.0,0.94,0.79)
	sun.light_energy = 0.65 if storm else 1.5
	cloud_material.set_shader_parameter("cloud_light",Color(1.0,0.72,0.50) if not daylight else Color(0.91,0.94,0.86))
	cloud_material.set_shader_parameter("cloud_shadow",Color(0.22,0.17,0.29) if not daylight else Color(0.11,0.36,0.47))
	cloud_material.set_shader_parameter("sun_direction",direction)
	cloud_material.set_shader_parameter("storm",float(storm))
	if storm:
		sky_material.set_shader_parameter("zenith_color",Color(0.075,0.09,0.14))
	environment.fog_light_color = Color(0.22,0.24,0.31) if storm else haze.lerp(Color(0.8,0.78,0.75),0.35)
	if is_instance_valid(explosion):
		for node in explosion.get_children():
			if node is MeshInstance3D and node.material_override is ShaderMaterial:
				node.material_override.set_shader_parameter("haze_color",haze)

func _vfx_material(colors: PackedColorArray, emission := 0.0) -> ShaderMaterial:
	var material := _material("mesh-vfx")
	var gradient := Gradient.new()
	gradient.colors = colors
	var offsets := PackedFloat32Array()
	for index in colors.size(): offsets.append(float(index)/float(colors.size()-1))
	gradient.offsets = offsets
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	material.set_shader_parameter("color_ramp",ramp)
	material.set_shader_parameter("emission_strength",emission)
	return material

func _update_hero_pose(time: float) -> void:
	hero.position = flight_position(time)
	hero.look_at(flight_position(time+0.01))
	hero.rotate_object_local(Vector3.FORWARD,-1.05+sin(time*0.3)*0.1)

func flight_position(time: float) -> Vector3:
	return Vector3(175.0-sin(time*0.065)*940.0,600.0+sin(time*0.35)*35.0,-600.0+cos(time*0.065)*940.0)

func wingman_position(time: float) -> Vector3:
	return Vector3(-400+sin(time*0.18)*600,580+cos(time*0.18)*160,-700+cos(time*0.18)*500)

func missile_position(time: float) -> Vector3:
	return flight_position(time)+Vector3(-120.0+cos(time*0.6)*80.0,50.0+sin(time*0.6)*50.0,-200.0-sin(time*0.6)*100.0)

func _add_trails() -> void:
	var material := _vfx_material(PackedColorArray([Color(0.9,0.83,0.7),Color(0.53,0.49,0.5)]))
	for side in [-1.0,1.0]:
		var emitter := Marker3D.new()
		emitter.position = Vector3(side*24,-0.8,12)
		hero.add_child(emitter)
		var trail := PositionTrail.new()
		trail.emitter = emitter
		add_child(trail)
		trail.configure(material)
		for index in 280:
			var time := -14.0+float(index)*0.05
			_update_hero_pose(time)
			trail.emit_at(emitter.global_position,20.0+time)
		_update_hero_pose(0.0)
		trail.material_override.set_shader_parameter("effect_time",trail.elapsed)
		trail.previous_position = emitter.global_position
		trail.has_previous = true
		trails.append(trail)
		palette_materials.append(trail.material_override)

	var distant_trail := PositionTrail.new()
	distant_trail.emitter = wingman
	distant_trail.lifetime = 26.0
	distant_trail.width = 1.5
	add_child(distant_trail)
	distant_trail.configure(material)
	for index in 480:
		var time := -24.0+float(index)*0.05
		distant_trail.emit_at(wingman_position(time),26.0+time)
	distant_trail.elapsed = 26.0
	distant_trail.material_override.set_shader_parameter("effect_time",26.0)
	distant_trail.previous_position = wingman.position
	distant_trail.has_previous = true
	trails.append(distant_trail)
	palette_materials.append(distant_trail.material_override)

	var smoke := _vfx_material(PackedColorArray([Color(0.9,0.85,0.72),Color(0.18,0.23,0.28)]))
	var missile_trail := PositionTrail.new()
	missile_trail.emitter = missile
	missile_trail.lifetime = 6.0
	missile_trail.spacing = 2.0
	missile_trail.width = 1.2
	add_child(missile_trail)
	missile_trail.configure(smoke)
	missile_trail.material_override.set_shader_parameter("wind_velocity",Vector3(0.35,0.2,0.1))
	missile_trail.material_override.set_shader_parameter("wind_curl",0.2)
	for index in 120:
		var time := -6.0+float(index)*0.05
		missile_trail.emit_at(missile_position(time),20.0+time)
	missile_trail.material_override.set_shader_parameter("effect_time",20.0)
	missile_trail.previous_position = missile.position
	missile_trail.has_previous = true
	trails.append(missile_trail)
	palette_materials.append(missile_trail.material_override)

func trigger_explosion() -> void:
	if is_instance_valid(explosion): explosion.queue_free()
	var fire := _vfx_material(PackedColorArray([Color(1,0.95,0.22),Color(1,0.42,0.015),Color(0.65,0.06,0.01),Color(0.03,0.025,0.07)]),0.85)
	var smoke := _vfx_material(PackedColorArray([Color(0.08,0.10,0.17),Color(0.11,0.13,0.22),Color(0.18,0.13,0.20)]))
	var accent := _vfx_material(PackedColorArray([Color(1,1,0.45),Color(1,0.8,0.1),Color(1,0.35,0.01)]),0.85)
	explosion = Explosion.new()
	explosion.position = hero.position + Vector3(-180,30,-110)
	explosion.scale = Vector3.ONE*1.8
	add_child(explosion)
	explosion.build(fire,smoke,accent)
	# Material uniforms are local to the effect; do not retain freed effects in the palette list.
	palette_materials.erase(fire)
	palette_materials.erase(smoke)
	palette_materials.erase(accent)

func _process(delta: float) -> void:
	if not is_instance_valid(camera): return
	if animate:
		elapsed += delta
		var old_position := hero.position
		_update_hero_pose(elapsed)
		for node in hero.get_children():
			if node.name.begins_with("EngineFlame"):
				node.scale.z = 3.6 + sin(elapsed*38.0)*0.35
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			camera.position += hero.position-old_position
		missile.position = missile_position(elapsed)
		missile.look_at(missile_position(elapsed+0.1))
		wingman.position = wingman_position(elapsed)
		wingman.look_at(wingman_position(elapsed+0.1))
		wingman.rotate_object_local(Vector3.FORWARD,0.3)
		explosion_clock += delta
		if explosion_clock > 8.0:
			explosion_clock = 0.0
			trigger_explosion()
		clouds.position.x = sin(elapsed*0.015)*50.0
	for trail in trails: trail.set_process(animate)
	if is_instance_valid(explosion): explosion.set_process(animate)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := Vector3(Input.get_axis("left","right"),float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q)),Input.get_axis("forward","back"))
		camera.position += camera.basis * motion * delta * (420.0 if Input.is_key_pressed(KEY_SHIFT) else 140.0)
	var density: float = clouds.density_at(camera.global_position)
	environment.fog_enabled = density > 0.001
	environment.fog_density = density * (0.035 if storm else 0.025)
	var sun_point := camera.global_position + sun_direction*4000.0
	var uv := camera.unproject_position(sun_point)/get_viewport().get_visible_rect().size
	post_material.set_shader_parameter("sun_uv",uv)
	post_material.set_shader_parameter("sun_visible",0.0 if camera.is_position_behind(sun_point) or storm or uv.x < -0.25 or uv.x > 1.25 or uv.y < -0.25 or uv.y > 1.25 else 1.0)
	post_material.set_shader_parameter("rain_strength",density*float(storm))
	post_material.set_shader_parameter("weather_time",elapsed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera.rotation.y -= event.relative.x*0.002
		camera.rotation.x = clampf(camera.rotation.x-event.relative.y*0.002,-1.5,1.5)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: set_palette(false)
			KEY_2: set_palette(true)
			KEY_3:
				storm = not storm
				set_palette(daylight_palette)
			KEY_4: clouds.set_coverage(0.4 if clouds.coverage > 0.5 else 1.0)
			KEY_P: animate = not animate
			KEY_SPACE: trigger_explosion()
			KEY_ESCAPE: Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _make_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_material = ShaderMaterial.new()
	post_material.shader = load("res://shaders/aerial/post.gdshader")
	rect.material = post_material
	layer.add_child(rect)

func _make_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
	var label := Label.new()
	label.text = "AERIAL RENDER STUDY   ·   DELIVERY MUST COMPLETE\n1 Sunset   2 Daylight   3 Storm   4 Cloud cover   P Pause   Space Explosion\nRight click: fly camera · WASD / Q E · Shift: faster"
	label.position = Vector2(24,22)
	label.add_theme_color_override("font_color",Color(1,0.88,0.73))
	label.add_theme_font_size_override("font_size",16)
	hud.add_child(label)
