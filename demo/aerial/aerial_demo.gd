extends Node3D

const Geometry = preload("res://aerial/geometry.gd")
const PositionTrail = preload("res://aerial/position_trail.gd")
const Explosion = preload("res://aerial/graphic_explosion.gd")
const CloudBanks = preload("res://aerial/cloud_banks.gd")
const AerialMech = preload("res://aerial/aerial_mech.gd")
const FlightInput = preload("res://aerial/flight_input.gd")
const FlightCamera = preload("res://aerial/flight_camera.gd")
const AerialLighting = preload("res://aerial/aerial_lighting.gd")
const FlightHUD = preload("res://aerial/flight_hud.gd")
const FlightAudio = preload("res://aerial/flight_audio.gd")
@onready var lighting: AerialLighting = $Lighting
@onready var camera: FlightCamera = $FlightCamera
@onready var hud: FlightHUD = $FlightHUD
var clouds: CloudBanks
var hero: AerialMech
var wingman: AerialMech
var missile: Node3D
var animate := true:
	set(value):
		animate = value
		if is_instance_valid(hero): hero.simulation_enabled = value
		if is_instance_valid(camera): camera.input_paused = not value
var elapsed := 0.0
var trails: Array[MultiMeshInstance3D] = []
var engine_trails: Array[PositionTrail] = []
var thrust_wash: Array[GPUParticles3D] = []
var explosion: Explosion
var explosion_clock := 0.0
@export var authored_flight := true
@export_range(0.0,1.0,0.01) var afterburner_throttle := 0.35
var afterburner_material: ShaderMaterial
var afterburner_flow_phase := 0.0
var automatic_exhaust := true

func _ready() -> void:
	# Only the physics-driven mechs interpolate; scenery/VFX use the render clock.
	get_tree().physics_interpolation = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	FlightInput.install_input_actions()
	var terrain_material := lighting.create_material("terrain")
	terrain_material.set_shader_parameter("diffuse_ramp_mode",1)
	terrain_material.set_shader_parameter("diffuse_ramp_threshold",0.28)
	Geometry.add_mesh(self,Geometry.terrain(),terrain_material).name = "Terrain"
	var river_material := lighting.create_material("aircraft")
	river_material.set_shader_parameter("body_color",Color(0.055,0.24,0.21))
	river_material.set_shader_parameter("orientation_bias",0.0)
	river_material.set_shader_parameter("panel_strength",0.0)
	river_material.set_shader_parameter("rim_strength",0.05)
	Geometry.add_mesh(self,Geometry.river(),river_material).name = "River"
	clouds = CloudBanks.new()
	add_child(clouds)
	clouds.build(lighting.cloud_material)
	var body := lighting.create_material("aircraft")
	body.set_shader_parameter("orientation_bias",0.0)
	body.set_shader_parameter("panel_strength",0.0)
	body.set_shader_parameter("rim_color",Color(0.85,0.9,1.0))
	body.set_shader_parameter("rim_strength",0.18)
	body.set_shader_parameter("highlight_mask",0.0)
	body.set_shader_parameter("shadow_fill",0.28)
	body.set_shader_parameter("diffuse_ramp_mode",1)
	body.set_shader_parameter("diffuse_ramp_threshold",0.18)
	var canopy := lighting.create_material("aircraft")
	canopy.set_shader_parameter("body_color",Color(0.03,0.12,0.13))
	canopy.set_shader_parameter("underside_color",Color(0.01,0.04,0.06))
	canopy.set_shader_parameter("highlight_mask",1.0)
	canopy.set_shader_parameter("orientation_bias",0.0)
	canopy.set_shader_parameter("panel_strength",0.0)
	canopy.set_shader_parameter("rim_strength",0.35)
	afterburner_material = lighting.create_material("afterburner")
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
	hero.display_scale = 50.0
	hero.player_controlled = true
	hero.controller.articulated_flight = authored_flight
	hero.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(hero)
	hero.build(body,afterburner_material)
	var flight_audio := FlightAudio.new()
	flight_audio.subject = hero
	hero.add_child(flight_audio)
	lighting.palette_materials.append_array(hero.palette_materials)
	hero.position = Vector3(175,600,340)
	wingman = AerialMech.new()
	wingman.name = "WingmanMech"
	wingman.display_scale = 35.0
	wingman.controller.articulated_flight = authored_flight
	wingman.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(wingman)
	wingman.build(body,afterburner_material)
	lighting.palette_materials.append_array(wingman.palette_materials)
	wingman.position = Vector3(-400,580,-700)
	camera.subject = hero
	camera.input_paused = not animate
	missile = Node3D.new()
	missile.position = missile_position(0.0)
	add_child(missile)
	camera.focus_targets = [wingman,missile,null]
	Geometry.add_mesh(missile,Geometry.icosphere(),canopy).scale = Vector3(1,1,4)
	var missile_fire := lighting.create_vfx_material(PackedColorArray([Color(1,0.55,0.05),Color(1,0.15,0.01)]),3.0)
	var flame := Geometry.add_mesh(missile,Geometry.icosphere(),missile_fire)
	flame.position.z = 5.0
	flame.scale = Vector3(0.8,0.8,3.0)
	_add_trails()
	set_palette(false)
	for mech in [hero,wingman]:
		mech.controller.reset()
		mech.update_animation(0.0)
		mech.reset_physics_interpolation()
	wingman.collision_layer = 4
	wingman.simulation_enabled = false
	_make_ground()
	_add_thrust_wash()
	camera.reset_view()
	_update_afterburners()
	for trail in trails.slice(0,2): trail.visible = false
	lighting.attach_camera(camera)
	lighting.update_weather(camera,clouds,elapsed)
	hud.update_status(hero)

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
	for mech in [hero,wingman]: mech.update_exhaust(afterburner_flow_phase)

func set_palette(daylight: bool) -> void:
	lighting.set_palette(daylight)
	if is_instance_valid(explosion): lighting.apply_materials(explosion.materials)

func _flight_throttle(mech: Node3D) -> float:
	return clampf(mech.controller.thrust_level / 4.0, 0.0, 1.0) if mech.simulation_enabled else 0.0

func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = get_node("Terrain").mesh.create_trimesh_shape()
	ground.add_child(shape)
	add_child(ground)

func ground_height(point: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x,4000,point.z),Vector3(point.x,-1000,point.z),2)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return float(hit.position.y) if not hit.is_empty() else 0.0

func missile_position(time: float) -> Vector3:
	return Vector3(175.0-sin(time*0.065)*940.0,600.0+sin(time*0.35)*35.0,-600.0+cos(time*0.065)*940.0)+Vector3(-120.0+cos(time*0.6)*80.0,50.0+sin(time*0.6)*50.0,-200.0-sin(time*0.6)*100.0)

func _add_trails() -> void:
	var material := lighting.create_vfx_material(PackedColorArray([Color(0.9,0.83,0.7),Color(0.53,0.49,0.5)]))
	for index in hero.flames.size():
		var flame: MeshInstance3D = hero.flames[index]
		var emitter := Marker3D.new()
		emitter.name = "EngineTrailEmitter_%d" % index
		flame.get_parent().add_child(emitter)
		emitter.position = flame.position
		var trail := PositionTrail.new()
		trail.emitter = emitter
		trail.lifetime = 12.0
		trail.width = 0.42
		trail.spacing = 4.5
		add_child(trail)
		trail.configure(material,PositionTrail.THIN)
		engine_trails.append(trail)
		lighting.palette_materials.append_array(trail.palette_materials())

	var distant_trail := PositionTrail.new()
	distant_trail.emitter = wingman
	distant_trail.lifetime = 26.0
	distant_trail.width = 0.7
	distant_trail.spacing = 6.0
	add_child(distant_trail)
	distant_trail.configure(material,PositionTrail.THIN)
	trails.append(distant_trail)
	lighting.palette_materials.append_array(distant_trail.palette_materials())

	var smoke := lighting.create_vfx_material(PackedColorArray([Color(0.9,0.85,0.72),Color(0.18,0.23,0.28)]))
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
	lighting.palette_materials.append_array(missile_trail.palette_materials())

func _add_thrust_wash() -> void:
	for index in hero.flames.size():
		var particles := GPUParticles3D.new()
		particles.name = "ThrustWash_%d" % index
		particles.amount = 72
		particles.lifetime = 1.4
		particles.local_coords = false
		particles.emitting = false
		particles.amount_ratio = 0.0
		particles.visibility_aabb = AABB(Vector3(-120,-80,-120),Vector3(240,160,240))
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 2.5
		process.direction = Vector3.UP
		process.spread = 78.0
		process.initial_velocity_min = 3.0
		process.initial_velocity_max = 16.0
		process.gravity = Vector3(0,3,0)
		process.damping_min = 2.0
		process.damping_max = 6.0
		process.scale_min = 0.5
		process.scale_max = 1.5
		process.color = Color(0.55,0.48,0.39,0.28)
		particles.process_material = process
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.albedo_color = Color(0.58,0.51,0.42,0.24)
		quad.material = material
		particles.draw_pass_1 = quad
		add_child(particles)
		thrust_wash.append(particles)

func _update_thrust_wash() -> void:
	if not is_instance_valid(hero) or not hero.simulation_enabled:
		for emitter in thrust_wash: emitter.emitting = false
		return
	var space := get_world_3d().direct_space_state
	for index in mini(thrust_wash.size(),hero.flames.size()):
		var emitter: GPUParticles3D = thrust_wash[index]
		var force: Vector3 = hero.controller.motor_forces[index]
		var rating: float = maxf(hero.controller.hot_max_thrust(index),1.0)
		var ratio := clampf(force.length()/rating,0.0,1.0)
		if ratio<0.04:
			emitter.emitting = false
			emitter.amount_ratio = 0.0
			continue
		var exhaust_direction := -force.normalized()
		if exhaust_direction.y>-0.20:
			emitter.emitting = false
			emitter.amount_ratio = 0.0
			continue
		var origin: Vector3 = hero.flames[index].global_position
		var query := PhysicsRayQueryParameters3D.create(origin,origin+exhaust_direction*1200.0,2)
		query.exclude = [hero.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			emitter.emitting = false
			emitter.amount_ratio = 0.0
			continue
		var distance: float = origin.distance_to(hit.position)
		var influence := ratio*(1.0-smoothstep(120.0,850.0,distance))
		emitter.amount_ratio = influence
		emitter.global_position = hit.position+hit.normal*0.8
		emitter.scale = Vector3.ONE*lerpf(0.65,1.8,influence)
		emitter.emitting = influence>0.04

func trigger_explosion(seed_value := -1) -> void:
	if is_instance_valid(explosion): explosion.queue_free()
	var fire := lighting.create_vfx_material(PackedColorArray([Color(1,0.95,0.22),Color(1,0.42,0.015),Color(0.65,0.06,0.01),Color(0.03,0.025,0.07)]),0.85,false)
	var smoke := lighting.create_vfx_material(PackedColorArray([Color(0.28,0.31,0.38),Color(0.24,0.27,0.34),Color(0.18,0.20,0.26)]),0.0,false)
	var accent := lighting.create_vfx_material(PackedColorArray([Color(1,1,0.45),Color(1,0.8,0.1),Color(1,0.35,0.01)]),0.85,false)
	explosion = Explosion.new()
	explosion.position = hero.position + Vector3(-180,30,-110)
	explosion.scale = Vector3.ONE*1.8
	add_child(explosion)
	explosion.build(fire,smoke,accent,seed_value)

func _physics_process(delta: float) -> void:
	# Vision is sampled on the fixed pose clock. Head movement never feeds back
	# into the independent camera or the chassis rotation controller.
	if is_instance_valid(hero) and hero.player_controlled and animate:
		var following := is_instance_valid(camera.focus_target) or camera.manual_gaze_time>0.0
		hero.controller.gaze_direction = camera.look_direction() if following or not authored_flight else Vector3.ZERO
		camera.manual_gaze_time = maxf(0.0,camera.manual_gaze_time-delta)

func _process(delta: float) -> void:
	if not is_instance_valid(camera): return
	if animate:
		elapsed += delta
		hero.update_force_debug()
		_update_afterburners(delta)
		camera.update_view(delta)
		_update_thrust_wash()
		hud.update_status(hero)
		missile.position = missile_position(elapsed)
		missile.look_at(missile_position(elapsed+0.1))
		explosion_clock += delta
		if explosion_clock > 8.0:
			explosion_clock = 0.0
			trigger_explosion()
		clouds.position.x = sin(elapsed*0.015)*50.0
	for trail in trails: trail.set_process(animate)
	if trails.size()>0: trails[0].visible = wingman.controller.velocity.length()>1.5
	if trails.size()>1: trails[1].visible = true
	if not animate:
		for emitter in thrust_wash: emitter.emitting = false
	for index in engine_trails.size():
		var active: bool = animate and hero.controller.motor_forces[index].length()>hero.controller.hot_max_thrust(index)*0.02
		engine_trails[index].visible = active
		engine_trails[index].set_process(active)
	if is_instance_valid(explosion): explosion.set_process(animate)
	lighting.update_weather(camera,clouds,elapsed)

func _unhandled_input(event: InputEvent) -> void:
	if animate: FlightInput.handle_input(event,hero.controller)
	camera.handle_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: set_palette(false)
			KEY_2: set_palette(true)
			KEY_3:
				lighting.storm = not lighting.storm
				set_palette(lighting.daylight_palette)
			KEY_4: clouds.set_coverage(0.4 if clouds.coverage > 0.5 else 1.0)
			KEY_P: animate = not animate
			KEY_F8: trigger_explosion()
			KEY_F9: hero.debug_forces = not hero.debug_forces; hero.update_force_debug()
