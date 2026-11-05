extends Node3D

# DELIVERY MUST COMPLETE reference: one lighting/weather palette for surfaces and VFX.
const AtmosphereVolume = preload("res://aerial/atmosphere_volume.gd")
var environment: Environment
var sun: DirectionalLight3D
var palette_materials: Array[ShaderMaterial] = []
var sky_material: ShaderMaterial
var cloud_material: ShaderMaterial
var storm := false
var daylight_palette := false
var sun_direction := Vector3(-0.660,0.232,-0.715).normalized()
var post_material: ShaderMaterial
var current_haze := Color(0.30,0.27,0.40)
var current_haze_sun_color := Color(0.88,0.43,0.27)
var current_haze_sun_strength := 0.8
var current_sky_fill := Color(0.14,0.22,0.38)
var current_sky_fill_strength := 0.3
@export_range(0.0,3.0,0.05) var atmosphere_strength := 1.0
@export_range(0.0,1.0,0.05) var atmosphere_shadow_strength := 1.0
var volume_effect: AtmosphereVolume

func _ready() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_strength = 0.85
	environment.glow_hdr_threshold = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.14,0.17,0.25)
	environment.ambient_light_energy = 0.25
	environment.fog_light_color = Color(0.45,0.48,0.57)
	environment.fog_density = 0.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	sky_material = create_material("sky")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1600.0
	add_child(sun)
	cloud_material = create_material("cloud")
	_make_post()

func create_material(shader_name: String, persistent := true) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/aerial/"+shader_name+".gdshader")
	if shader_name != "sky":
		apply_surface_palette(material)
		if persistent: palette_materials.append(material)
	return material

func apply_surface_palette(material: ShaderMaterial) -> void:
	material.set_shader_parameter("haze_color",current_haze)
	material.set_shader_parameter("haze_sun_color",current_haze_sun_color)
	material.set_shader_parameter("haze_sun_strength",current_haze_sun_strength)
	material.set_shader_parameter("sky_fill_color",current_sky_fill)
	material.set_shader_parameter("sky_fill_strength",current_sky_fill_strength)
	material.set_shader_parameter("sun_direction",sun_direction)

func set_palette(daylight: bool) -> void:
	daylight_palette = daylight
	var haze := Color(0.30,0.27,0.40) if not daylight else Color(0.37,0.67,0.76)
	if storm: haze = haze.lerp(Color(0.17,0.20,0.26),0.65)
	current_haze = haze
	current_haze_sun_color = Color(0.88,0.43,0.27) if not daylight else Color(0.78,0.86,0.84)
	current_haze_sun_strength = 0.8 if not daylight else 0.3
	current_sky_fill = Color(0.14,0.22,0.38) if not daylight else Color(0.22,0.35,0.43)
	current_sky_fill_strength = 0.3 if not daylight else 0.24
	if storm:
		current_haze_sun_color = current_haze_sun_color.lerp(Color(0.24,0.27,0.34),0.8)
		current_haze_sun_strength = 0.08
		current_sky_fill = Color(0.11,0.16,0.24)
		current_sky_fill_strength = 0.12
	var direction := Vector3(-0.660,0.232,-0.715).normalized() if not daylight else Vector3(-0.4,0.65,-0.64).normalized()
	sun_direction = direction
	for material in palette_materials:
		apply_surface_palette(material)
	sky_material.set_shader_parameter("zenith_color",Color(0.18,0.11,0.25) if not daylight else Color(0.035,0.27,0.4))
	sky_material.set_shader_parameter("horizon_color",haze if daylight or storm else Color(0.43,0.28,0.37))
	sky_material.set_shader_parameter("sun_color",Color(1.0,0.78,0.48) if not daylight else Color(1.0,0.95,0.84))
	sky_material.set_shader_parameter("halo_strength",0.15 if storm else (0.35 if daylight else 1.0))
	sky_material.set_shader_parameter("horizon_scatter_strength",0.0 if storm else (0.10 if daylight else 0.35))
	sky_material.set_shader_parameter("solar_core_energy",0.0 if storm else 18.0)
	sky_material.set_shader_parameter("sun_direction",direction)
	sun.look_at_from_position(Vector3.ZERO,-direction)
	sun.light_color = Color(1.0,0.73,0.47) if not daylight else Color(1.0,0.96,0.86)
	sun.light_energy = 0.65 if storm else 1.5
	environment.ambient_light_color = current_sky_fill
	environment.ambient_light_energy = current_sky_fill_strength
	cloud_material.set_shader_parameter("cloud_light",Color(1.0,0.66,0.30) if not daylight else Color(0.91,0.94,0.86))
	cloud_material.set_shader_parameter("cloud_shadow",Color(0.22,0.14,0.29) if not daylight else Color(0.11,0.36,0.47))
	cloud_material.set_shader_parameter("cloud_transmission",Color(1.0,0.48,0.10) if not daylight else Color(0.69,0.83,0.88))
	cloud_material.set_shader_parameter("cloud_bank_glow_strength",0.7 if not daylight else 0.12)
	cloud_material.set_shader_parameter("cloud_lining",Color(1.0,0.91,0.66) if not daylight else Color(0.97,0.99,1.0))
	cloud_material.set_shader_parameter("storm",float(storm))
	if storm:
		sky_material.set_shader_parameter("zenith_color",Color(0.075,0.09,0.14))
	environment.fog_light_color = Color(0.22,0.24,0.31) if storm else haze.lerp(Color(0.8,0.78,0.75),0.35)

func create_vfx_material(colors: PackedColorArray, emission := 0.0, persistent := true) -> ShaderMaterial:
	var material := create_material("mesh-vfx",persistent)
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

func _update_atmosphere(sun_uv: Vector2, clouds: Node3D) -> void:
	volume_effect.configure(clouds,sun_direction,{
		"strength":atmosphere_strength,"shadow_strength":atmosphere_shadow_strength,
		"density":0.000085,"height_scale":600.0,"max_distance":4500.0,
		"sun_strength":1.5 if daylight_palette else 4.5,
		"light_color":sun.light_color,"ambient_color":current_sky_fill,
		"sun_enabled":not storm,"sun_uv":sun_uv,
	})
	# The Texture2DRD has no RID before the first compositor callback.
	if volume_effect.get_status().ready:
		post_material.set_shader_parameter("solar_visibility_texture",volume_effect.solar_visibility_texture)
		post_material.set_shader_parameter("use_depth_occlusion",true)
	else:
		post_material.set_shader_parameter("sun_visible",0.0)

func update_weather(camera: Camera3D, clouds: Node3D, elapsed: float) -> void:
	var density: float = clouds.density_at(camera.global_position)
	environment.fog_enabled = density > 0.001
	environment.fog_density = density * (0.035 if storm else 0.025)
	var sun_point := camera.global_position + sun_direction*4000.0
	var uv := camera.unproject_position(sun_point)/camera.get_viewport().get_visible_rect().size
	post_material.set_shader_parameter("sun_uv",uv)
	post_material.set_shader_parameter("sun_visible",0.0 if camera.is_position_behind(sun_point) or storm or uv.x < -0.25 or uv.x > 1.25 or uv.y < -0.25 or uv.y > 1.25 else 1.0-density)
	post_material.set_shader_parameter("rain_strength",density*float(storm))
	post_material.set_shader_parameter("weather_time",elapsed)
	if is_instance_valid(volume_effect): _update_atmosphere(uv,clouds)

func attach_camera(camera: Camera3D) -> void:
	volume_effect = AtmosphereVolume.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [volume_effect]
	camera.compositor = compositor

func apply_materials(materials: Array[ShaderMaterial]) -> void:
	for material in materials: apply_surface_palette(material)
