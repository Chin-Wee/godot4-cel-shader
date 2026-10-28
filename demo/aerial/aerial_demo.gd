extends Node3D

const Geometry = preload("res://aerial/geometry.gd")
const PositionTrail = preload("res://aerial/position_trail.gd")
const Explosion = preload("res://aerial/graphic_explosion.gd")
const CloudBanks = preload("res://aerial/cloud_banks.gd")
const AerialMech = preload("res://aerial/aerial_mech.gd")
const FlightController = preload("res://aerial/flight_controller.gd")
const Spring = preload("res://aerial/flight_pose.gd").Spring
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
var sun_direction := Vector3(-0.660,0.232,-0.715).normalized()
var post_material: ShaderMaterial
var current_haze := Color(0.30,0.27,0.40)
var current_haze_sun_color := Color(0.88,0.43,0.27)
var current_haze_sun_strength := 0.8
var current_sky_fill := Color(0.14,0.22,0.38)
var current_sky_fill_strength := 0.3
var hud: CanvasLayer
var trails: Array[MultiMeshInstance3D] = []
var explosion: Node3D
var explosion_clock := 0.0
@export_range(0.0,1.0,0.01) var afterburner_throttle := 0.35
var afterburner_material: ShaderMaterial
var afterburner_flow_phase := 0.0
@export_range(0.0,3.0,0.05) var atmosphere_strength := 1.0
@export_range(0.0,1.0,0.05) var atmosphere_shadow_strength := 1.0
var walking_time := 0.0
var automatic_exhaust := true
var follow_camera := true
var camera_yaw := 0.45
var camera_pitch := 0.22
var camera_distance := 3.8
var camera_target := Spring.new()
var camera_lag := Spring.new()
var focus_target: Node3D
var focus_index := -1
var fire_cooldown := 0.0
var shots := []
var shot_cursor := 0
var reticle: Label
var hit_time := 0.0
var shots_fired := 0
var flight_stats: Label
var walk_ground: StaticBody3D
var volume_effect

func _ready() -> void:
	FlightController.install_input_actions()
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
	terrain_material.set_shader_parameter("diffuse_ramp_threshold",0.28)
	Geometry.add_mesh(self,Geometry.terrain(),terrain_material).name = "Terrain"
	var river_material := _material("aircraft")
	river_material.set_shader_parameter("body_color",Color(0.055,0.24,0.21))
	river_material.set_shader_parameter("orientation_bias",0.0)
	river_material.set_shader_parameter("panel_strength",0.0)
	river_material.set_shader_parameter("rim_strength",0.05)
	Geometry.add_mesh(self,Geometry.river(),river_material).name = "River"
	cloud_material = _material("cloud")
	clouds = CloudBanks.new()
	add_child(clouds)
	clouds.build(cloud_material)
	var body := _material("aircraft")
	body.set_shader_parameter("orientation_bias",0.0)
	body.set_shader_parameter("panel_strength",0.0)
	body.set_shader_parameter("rim_color",Color(0.85,0.9,1.0))
	body.set_shader_parameter("rim_strength",0.18)
	body.set_shader_parameter("highlight_mask",0.0)
	body.set_shader_parameter("shadow_fill",0.28)
	body.set_shader_parameter("diffuse_ramp_mode",1)
	body.set_shader_parameter("diffuse_ramp_threshold",0.18)
	var canopy := _material("aircraft")
	canopy.set_shader_parameter("body_color",Color(0.03,0.12,0.13))
	canopy.set_shader_parameter("underside_color",Color(0.01,0.04,0.06))
	canopy.set_shader_parameter("highlight_mask",1.0)
	canopy.set_shader_parameter("orientation_bias",0.0)
	canopy.set_shader_parameter("panel_strength",0.0)
	canopy.set_shader_parameter("rim_strength",0.35)
	afterburner_material = _material("afterburner")
	var noise := FastNoiseLite.new()
	noise.seed = 431
	noise.frequency = 0.018
	noise.fractal_octaves = 2
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	afterburner_material.set_shader_parameter("flow_noise",texture)
	hero = AerialMech.new()
	hero.name = "HeroMech"
	hero.scale = Vector3.ONE*50.0
	add_child(hero)
	hero.build(body,afterburner_material)
	palette_materials.append_array(hero.palette_materials)
	hero.position = Vector3(175,600,340)
	wingman = AerialMech.new()
	wingman.name = "WingmanMech"
	wingman.scale = Vector3.ONE*35.0
	add_child(wingman)
	wingman.build(body,afterburner_material)
	palette_materials.append_array(wingman.palette_materials)
	wingman.position = Vector3(-400,580,-700)
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
	for mech in [hero,wingman]:
		mech.controller.reset(mech.position,mech.rotation.y)
		mech.update_animation(0.0)
	wingman.actor.collision_layer = 4
	_make_weapon_preview()
	_make_ground()
	reset_camera()
	_update_afterburners()
	for trail in trails.slice(0,2): trail.visible = false
	volume_effect = load("res://aerial/atmosphere_volume.gd").new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [volume_effect]
	camera.compositor = compositor
	_update_atmosphere(camera.unproject_position(camera.global_position+sun_direction*4000.0)/get_viewport().get_visible_rect().size)
	_update_flight_stats()

func _update_atmosphere(sun_uv: Vector2) -> void:
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

func set_afterburner_throttle(value: float) -> void:
	automatic_exhaust = false
	afterburner_throttle = clampf(value,0.0,1.0)
	_update_afterburners()

func _update_afterburners(delta := 0.0) -> void:
	# KSP2's production pattern: one throttle drives mesh scale, flow and intensity.
	if automatic_exhaust: afterburner_throttle = _flight_throttle(hero)
	var throttle := clampf(afterburner_throttle,0.0,1.0)
	# All texture scroll rates repeat after 100 phase units; keep the GPU clock precise.
	afterburner_flow_phase = fposmod(afterburner_flow_phase+delta*lerpf(0.35,1.8,throttle),100.0)
	afterburner_material.set_shader_parameter("flow_phase",afterburner_flow_phase)
	afterburner_material.set_shader_parameter("throttle",throttle)
	for mech in [hero,wingman]: mech.update_exhaust(_flight_throttle(mech) if automatic_exhaust else throttle,afterburner_flow_phase)

func _material(shader_name: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/aerial/"+shader_name+".gdshader")
	if shader_name != "sky":
		_set_surface_palette(material)
		palette_materials.append(material)
	return material

func _set_surface_palette(material: ShaderMaterial) -> void:
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
		_set_surface_palette(material)
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
	if is_instance_valid(explosion):
		for node in explosion.get_children():
			if node is MeshInstance3D and node.material_override is ShaderMaterial:
				_set_surface_palette(node.material_override)

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

func _flight_throttle(mech: Node3D) -> float:
	return clampf(mech.controller.DETENTS[mech.controller.detent]/4.0+mech.controller.recovery_request*0.35,0.0,1.0)

func _make_ground() -> void:
	walk_ground = StaticBody3D.new()
	walk_ground.collision_layer = 2
	walk_ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = get_node("Terrain").mesh.create_trimesh_shape()
	walk_ground.add_child(shape)
	add_child(walk_ground)

func ground_height(point: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x,4000,point.z),Vector3(point.x,-1000,point.z),2)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return float(hit.position.y) if not hit.is_empty() else 0.0

func _update_walk_pose() -> void:
	var angle: float = walking_time*hero.walk_speed*hero.scale.x/100.0
	hero.position = Vector3(650.0+sin(angle)*100.0,0,120.0+cos(angle)*100.0)
	hero.position.y = ground_height(hero.position)+0.9*hero.scale.y+0.1
	hero.rotation = Vector3(0,-PI/2.0+angle,0)

func set_walk_mode(enabled: bool) -> void:
	hero.flying = not enabled
	if enabled: _update_walk_pose()
	hero.controller.reset(hero.position,hero.rotation.y)
	hero.update_animation(0.0)
	_update_afterburners()
	reset_camera()
	trails[0].visible = not enabled and hero.controller.velocity.length() > 1.5

func reset_camera() -> void:
	camera_yaw = hero.controller.heading_yaw
	camera_pitch = 0.08
	camera_distance = 3.8
	camera_target.value = hero.position+Vector3.UP*hero.scale.y*0.35
	camera_target.velocity = Vector3.ZERO
	camera_lag.value = Vector3.ZERO
	camera_lag.velocity = Vector3.ZERO
	_update_camera(0.0)

func _update_camera(delta: float) -> void:
	if not follow_camera: return
	var center: Vector3 = hero.position+Vector3.UP*hero.scale.y*0.35
	var lag: Vector3 = (-hero.controller.acceleration*0.016*hero.scale.y).limit_length(0.45*hero.scale.y)
	var target: Vector3 = camera_target.step(center,delta,0.14)+camera_lag.step(lag,delta,0.35)
	if is_instance_valid(focus_target):
		var focus_direction := (focus_target.global_position-center).normalized()
		camera_yaw = atan2(-focus_direction.x,-focus_direction.z)
		camera_pitch = -asin(clampf(focus_direction.y,-1,1))
	var offset := Vector3(sin(camera_yaw)*cos(camera_pitch),sin(camera_pitch),cos(camera_yaw)*cos(camera_pitch))*camera_distance*hero.scale.x
	camera.position = target+offset+Basis(Vector3.UP,camera_yaw).x*hero.scale.x*0.4
	camera.look_at(focus_target.global_position if is_instance_valid(focus_target) else hero.position+aim_direction()*4500.0)

func missile_position(time: float) -> Vector3:
	return Vector3(175.0-sin(time*0.065)*940.0,600.0+sin(time*0.35)*35.0,-600.0+cos(time*0.065)*940.0)+Vector3(-120.0+cos(time*0.6)*80.0,50.0+sin(time*0.6)*50.0,-200.0-sin(time*0.6)*100.0)

func _add_trails() -> void:
	var material := _vfx_material(PackedColorArray([Color(0.9,0.83,0.7),Color(0.53,0.49,0.5)]))
	for flame in hero.flames.slice(0,1):
		var emitter := Marker3D.new()
		flame.get_parent().add_child(emitter)
		emitter.position = flame.position
		var trail := PositionTrail.new()
		trail.emitter = emitter
		add_child(trail)
		trail.configure(material)
		trails.append(trail)
		palette_materials.append_array(trail.palette_materials())

	var distant_trail := PositionTrail.new()
	distant_trail.emitter = wingman
	distant_trail.lifetime = 26.0
	distant_trail.width = 0.7
	distant_trail.spacing = 6.0
	add_child(distant_trail)
	distant_trail.configure(material,PositionTrail.THIN)
	trails.append(distant_trail)
	palette_materials.append_array(distant_trail.palette_materials())

	var smoke := _vfx_material(PackedColorArray([Color(0.9,0.85,0.72),Color(0.18,0.23,0.28)]))
	var missile_trail := PositionTrail.new()
	missile_trail.emitter = missile
	missile_trail.lifetime = 6.0
	missile_trail.spacing = 2.0
	missile_trail.width = 1.2
	add_child(missile_trail)
	missile_trail.configure(smoke,PositionTrail.MISSILE)
	for layer_material in missile_trail.palette_materials():
		layer_material.set_shader_parameter("wind_velocity",Vector3(0.35,0.2,0.1))
		layer_material.set_shader_parameter("wind_curl",0.2)
	for index in 241:
		var time := -6.0+float(index)*0.025
		missile_trail.elapsed = 20.0+time
		missile_trail.sample_position(missile_position(time))
	missile_trail.set_time(20.0)
	trails.append(missile_trail)
	palette_materials.append_array(missile_trail.palette_materials())

func trigger_explosion(seed_value := -1) -> void:
	if is_instance_valid(explosion): explosion.queue_free()
	var fire := _vfx_material(PackedColorArray([Color(1,0.95,0.22),Color(1,0.42,0.015),Color(0.65,0.06,0.01),Color(0.03,0.025,0.07)]),0.85)
	var smoke := _vfx_material(PackedColorArray([Color(0.28,0.31,0.38),Color(0.24,0.27,0.34),Color(0.18,0.20,0.26)]))
	var accent := _vfx_material(PackedColorArray([Color(1,1,0.45),Color(1,0.8,0.1),Color(1,0.35,0.01)]),0.85)
	explosion = Explosion.new()
	explosion.position = hero.position + Vector3(-180,30,-110)
	explosion.scale = Vector3.ONE*1.8
	add_child(explosion)
	explosion.build(fire,smoke,accent,seed_value)
	# Material uniforms are local to the effect; do not retain freed effects in the palette list.
	palette_materials.erase(fire)
	palette_materials.erase(smoke)
	palette_materials.erase(accent)

func _process(delta: float) -> void:
	if not is_instance_valid(camera): return
	if animate:
		elapsed += delta
		if hero.flying:
			hero.controller.aim_direction = aim_direction()
			hero.controller.aim_point = focus_target.global_position if is_instance_valid(focus_target) else hero.position+hero.controller.aim_direction*4500.0
			hero.step_flight(delta,FlightController.read_input(),camera_yaw)
		else:
			walking_time += delta
			_update_walk_pose()
			hero.update_animation(delta)
		wingman.step_flight(delta,{},0.0)
		_update_weapon(delta)
		_update_afterburners(delta)
		_update_camera(delta)
		_update_flight_stats()
		missile.position = missile_position(elapsed)
		missile.look_at(missile_position(elapsed+0.1))
		explosion_clock += delta
		if explosion_clock > 8.0:
			explosion_clock = 0.0
			trigger_explosion()
		clouds.position.x = sin(elapsed*0.015)*50.0
	for index in trails.size():
		trails[index].set_process(animate and (hero.flying or index > 0))
		if index < 2: trails[index].visible = (hero if index == 0 else wingman).controller.velocity.length() > 1.5 and (hero.flying or index > 0)
	if is_instance_valid(explosion): explosion.set_process(animate)
	var density: float = clouds.density_at(camera.global_position)
	environment.fog_enabled = density > 0.001
	environment.fog_density = density * (0.035 if storm else 0.025)
	var sun_point := camera.global_position + sun_direction*4000.0
	var uv := camera.unproject_position(sun_point)/get_viewport().get_visible_rect().size
	post_material.set_shader_parameter("sun_uv",uv)
	post_material.set_shader_parameter("sun_visible",0.0 if camera.is_position_behind(sun_point) or storm or uv.x < -0.25 or uv.x > 1.25 or uv.y < -0.25 or uv.y > 1.25 else 1.0-density)
	post_material.set_shader_parameter("rain_strength",density*float(storm))
	post_material.set_shader_parameter("weather_time",elapsed)
	if is_instance_valid(volume_effect): _update_atmosphere(uv)

func aim_direction() -> Vector3:
	if is_instance_valid(focus_target): return (focus_target.global_position-hero.global_position).normalized()
	return -Vector3(sin(camera_yaw)*cos(camera_pitch),sin(camera_pitch),cos(camera_yaw)*cos(camera_pitch))

func focus_next() -> void:
	focus_index = (focus_index+1)%3
	focus_target = [wingman,missile,null][focus_index]

func _update_flight_stats() -> void:
	var fc = hero.controller
	var warning := " · AoA LIMIT" if fc.pull_limit > 0.1 else ""
	if fc.aim_direction.dot(fc.weapon_aim) < cos(deg_to_rad(10)): warning += " · OUTSIDE FIRING ARC"
	if fc.time_to_impact < 2.4: warning = " · TERRAIN %.1fs%s"%[fc.time_to_impact," — RECOVERY CAPPED" if fc.uncaged else " — PULL UP"]
	flight_stats.text = "%s · THRUST %.1f× · %.0f m/s · AERO %.0f%% · %.1f G%s\nW/S: %s · A/D: %s · Focus: %s"%[
		"UNCAGED" if fc.uncaged else "ASSIST",fc.DETENTS[fc.detent],fc.velocity.length(),fc.aero_authority*100,fc.g_load,warning,
		"TRANSLATE" if Input.is_action_pressed("flight_vector") else "PITCH",
		"STRAFE" if Input.is_action_pressed("flight_vector") else "ROLL",
		str(focus_target.name) if is_instance_valid(focus_target) else "free aim"]
	flight_stats.modulate = Color(1,0.4,0.25) if fc.time_to_impact < 2.4 else Color.WHITE
	reticle.text = "×" if hit_time > 0.0 else "+"
	reticle.modulate = Color(1,0.5,0.2) if hit_time > 0.0 else Color(0.8,0.95,1)

func _make_weapon_preview() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1,0.85,0.32)
	material.emission_enabled = true
	material.emission = Color(1,0.55,0.08)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.2,1.2,1)
	for index in 8:
		var tracer := Geometry.add_mesh(self,mesh,material)
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tracer.visible = false
		shots.append({"mesh":tracer,"life":0.0})

func _update_weapon(delta: float) -> void:
	fire_cooldown = maxf(0,fire_cooldown-delta)
	hit_time = maxf(0,hit_time-delta)
	for shot in shots:
		shot.life = maxf(0,shot.life-delta)
		shot.mesh.visible = shot.life > 0
	if hero.flying and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and fire_cooldown <= 0:
		fire_weapon()

func fire_weapon() -> void:
	if not animate or fire_cooldown > 0: return
	if hero.controller.aim_direction.dot(hero.controller.limit_aim_direction(hero.controller.aim_direction)) < cos(deg_to_rad(10)): return
	var start: Vector3 = hero.rig.weapon.muzzle.origin
	var direction: Vector3 = hero.rig.weapon.barrel_direction
	if direction.dot(hero.controller.aim_direction) < cos(deg_to_rad(12)): return
	var finish := start+direction*4500.0
	var ray := PhysicsRayQueryParameters3D.create(start,finish,6)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		finish = hit.position
		if hit.collider == wingman.actor: hit_time = 0.12
	var shot: Dictionary = shots[shot_cursor]
	shot_cursor = (shot_cursor+1)%shots.size()
	shot.life = 0.07
	shot.mesh.visible = true
	shot.mesh.position = (start+finish)*0.5
	shot.mesh.look_at(finish)
	shot.mesh.scale = Vector3(1,1,start.distance_to(finish))
	fire_cooldown = 0.16
	shots_fired += 1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE: focus_next()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera_distance = clampf(camera_distance+(-0.3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.3),1.8,9.5)
			_update_camera(0.0)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: _orbit(event.relative)
	if event is InputEventScreenDrag: _orbit(event.relative)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: set_palette(false)
			KEY_2: set_palette(true)
			KEY_3:
				storm = not storm
				set_palette(daylight_palette)
			KEY_4: clouds.set_coverage(0.4 if clouds.coverage > 0.5 else 1.0)
			KEY_G: set_walk_mode(hero.flying)
			KEY_P: animate = not animate
			KEY_F8: trigger_explosion()
			KEY_HOME: reset_camera()
			KEY_TAB: focus_next()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _orbit(relative: Vector2) -> void:
	# Camera remains gravity-upright even during inverted/body-independent flight.
	focus_target = null
	focus_index = -1
	camera_yaw -= relative.x*0.004
	camera_pitch = clampf(camera_pitch+relative.y*0.004,-1.45,1.45)
	_update_camera(0.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.add_child(panel)
	panel.offset_left = 20
	panel.offset_right = -20
	panel.offset_top = 18
	var label := Label.new()
	label.text = "GUNDAM · CONTINUOUS FLIGHT\nW/S: pitch · A/D: roll · Q/E: yaw · Arrows: pitch / roll\nR/F: vertical thrust · Alt+WASD: always translate · Ctrl: precision\nSpace / C: thrust detent · RMB hold: uncage · Shift+WASD: burst · X: drag\nMouse: aim · LMB: fire · MMB / Tab: focus · Esc: release · Wheel: zoom\nHome: camera reset · P: pause · G: walk · 1/2: palette · 3/4: weather · F8: explosion"
	label.add_theme_color_override("font_color",Color(1,0.93,0.82))
	label.add_theme_font_size_override("font_size",15)
	panel.add_child(label)
	flight_stats = Label.new()
	flight_stats.text = "ASSIST · THRUST 1.0×"
	panel.add_child(flight_stats)
	for text in [label,flight_stats]:
		text.add_theme_constant_override("outline_size",3)
		text.add_theme_color_override("font_outline_color",Color(0.03,0.04,0.06,0.85))

	reticle = Label.new()
	reticle.text = "+"
	reticle.add_theme_font_size_override("font_size",28)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.position -= Vector2(10,18)
	hud.add_child(reticle)
