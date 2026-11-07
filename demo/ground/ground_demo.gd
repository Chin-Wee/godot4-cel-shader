extends Node3D

const Mech = preload("res://aerial/aerial_mech.gd")
const Motion = preload("res://ground/ground_motion.gd")
const U := Motion.U
const KEYS := {
	"left": KEY_A, "right": KEY_D, "forward": KEY_W, "back": KEY_S,
	"turn_left": KEY_Q, "turn_right": KEY_E, "hop": KEY_R, "run": KEY_ALT, "brake": KEY_SHIFT, "guard": KEY_CTRL,
}

@onready var lighting = $Lighting
@onready var camera = $Chase
@onready var witness: Camera3D = $Witness
@onready var label: Label = $HUD/Label
var mech: Mech
var motion: Motion
var player_controlled := true
var daylight := false
var phase := 0.0
var lamps: Array[OmniLight3D] = []
var jet_light: OmniLight3D
var dust: GPUParticles3D
var skid_dust: GPUParticles3D
var last_touchdown := 0
var exhaust: ShaderMaterial

func _ready() -> void:
	get_tree().physics_interpolation = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for key in KEYS:
		var action: String = "ground_"+key
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = KEYS[key]
		InputMap.action_add_event(action,event)
	_build_street()
	var armor: ShaderMaterial = _paint(Color(0.75,0.77,0.79))
	exhaust = lighting.create_material("afterburner")
	exhaust.set_shader_parameter("core_color",Color(1.0,0.96,0.87))
	exhaust.set_shader_parameter("plume_color",Color(1.0,0.55,0.16))
	exhaust.set_shader_parameter("hot_color",Color(1.0,0.79,0.43))
	exhaust.set_shader_parameter("rim_color",Color(0.82,0.36,0.13))
	var noise := FastNoiseLite.new()
	noise.seed = 431
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	exhaust.set_shader_parameter("flow_noise",texture)
	mech = Mech.new()
	mech.name = "GroundMech"
	mech.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(mech)
	mech.build(armor,exhaust)
	var friction := PhysicsMaterial.new()
	friction.friction = 0.0
	mech.physics_material_override = friction
	# Fixed support pads give the capsule a bounded footprint. Normal load and
	# its centre of pressure remain native even while an animated boot swings.
	for side in [-1,1]:
		var pad := CollisionShape3D.new()
		var sole := BoxShape3D.new()
		sole.size = Vector3(0.64,0.22,2.8)*U
		pad.shape = sole
		mech.add_child(pad)
		pad.position = Vector3(side*Motion.WIDTH,-mech.hull.shape.height*0.5+sole.size.y*0.5,0)
	lighting.palette_materials.append_array(mech.palette_materials)
	camera.subject = mech
	jet_light = _light(Vector3.ZERO,Color(1.0,0.62,0.34),0.0,9.0)
	dust = _dust(true)
	skid_dust = _dust(false)
	reset_trial()
	set_daylight(false)
	witness.position = Vector3(-8.8,1.7,19.0)*U
	witness.look_at(Vector3(-0.5,4.9,7.2)*U)

func reset_trial(position_m := Vector3(0,4.49,10), direction := Quaternion.IDENTITY, speed := Vector3.ZERO) -> void:
	mech.reset_flight(position_m*U,direction,speed)
	mech.controller.reset(0.0)
	mech.controls = {}
	motion = Motion.new(mech)
	mech.ground_motion = motion
	last_touchdown = 0
	camera.reset_view()

func _paint(color: Color) -> ShaderMaterial:
	var material: ShaderMaterial = lighting.create_material("aircraft")
	material.set_shader_parameter("body_color",color)
	material.set_shader_parameter("orientation_bias",0.0)
	material.set_shader_parameter("panel_strength",0.0)
	material.set_shader_parameter("highlight_mask",0.0)
	return material

func _box(label_text: String, position_m: Vector3, size_m: Vector3, material: Material,
		layer := 0, tilt := 0.0) -> Node3D:
	var piece: Node3D = StaticBody3D.new() if layer>0 else Node3D.new()
	piece.name = label_text
	add_child(piece)
	piece.position = position_m*U
	piece.rotation.x = tilt
	var geometry := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_m*U
	geometry.mesh = mesh
	geometry.material_override = material
	piece.add_child(geometry)
	if piece is StaticBody3D:
		piece.collision_layer = layer
		piece.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		collision.shape = shape
		piece.add_child(collision)
	return piece

func _build_street() -> void:
	var asphalt := _paint(Color(0.23,0.24,0.28))
	var concrete := _paint(Color(0.39,0.40,0.44))
	var dark := _paint(Color(0.13,0.17,0.22))
	var chalk := _paint(Color(0.63,0.57,0.40))
	var truck := _paint(Color(0.40,0.24,0.17))
	_box("Floor",Vector3(0,-0.28,0),Vector3(20,0.5,40),concrete,2)
	_box("Street",Vector3(0,-0.255,0),Vector3(12,0.5,40),asphalt)
	for side in [-1,1]:
		_box("Sidewalk",Vector3(side*8,-0.25,0),Vector3(4,0.5,40),concrete)
		_box("Building",Vector3(side*14,4,-3),Vector3(8,8,30),dark,4)
		for z in [-12,-6,0,6,12]:
			_box("FacadePier",Vector3(side*9.94,4,z),Vector3(0.18,8.0,0.27),concrete)
			for y in [3.1,5.9]:
				_box("Window",Vector3(side*9.90,y,z+1.4),Vector3(0.12,0.85,1.45),asphalt)
				_box("Sill",Vector3(side*9.81,y-0.48,z+1.4),Vector3(0.28,0.12,1.6),concrete)
		_box("Door",Vector3(side*9.94,1.04,7.0),Vector3(0.09,2.08,1.05),concrete)
		for z in [-11,3,12]:
			_box("Lamp",Vector3(side*7.4,1.65,z),Vector3(0.11,3.3,0.11),dark)
			_box("LampShade",Vector3(side*7.15,3.3,z),Vector3(0.60,0.14,0.25),chalk)
			lamps.append(_light(Vector3(side*7.15,3.13,z),Color(1.0,0.65,0.34),2.6,9.0))
	for z in range(-18,19,5):
		_box("LaneMark",Vector3(0,0.003,z),Vector3(0.15,0.013,2.4),chalk)
	_box("Ramp",Vector3(0,0.58,-13.0),Vector3(9,0.24,7.0),concrete,2,deg_to_rad(8.0))
	_box("RampDeck",Vector3(0,0.55,-18.1),Vector3(9,1.26,3.2),concrete,2)
	_box("StopWall",Vector3(0,2.2,-20.1),Vector3(12,4.4,0.8),concrete,4)
	_box("Cover",Vector3(5.4,1.45,0.0),Vector3(1.5,2.9,4.0),concrete,4)
	_box("TruckBed",Vector3(-7.5,0.65,9.7),Vector3(1.85,0.8,3.4),truck,4)
	_box("TruckCab",Vector3(-7.5,1.27,10.9),Vector3(1.80,1.25,1.2),truck,4)
	_box("Windscreen",Vector3(-7.5,1.62,11.52),Vector3(1.55,0.48,0.04),dark)
	for x in [-8.33,-6.67]:
		for z in [8.65,10.9]:
			_box("TruckTire",Vector3(x,0.37,z),Vector3(0.32,0.70,0.64),dark)

func _light(at: Vector3, color: Color, energy: float, range_m: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	add_child(light)
	light.position = at*U
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m*U
	return light

func _dust(once: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	add_child(particles)
	particles.emitting = false
	particles.one_shot = once
	particles.amount = 22 if once else 18
	particles.lifetime = 0.75
	particles.explosiveness = 0.85 if once else 0.0
	var motion_material := ParticleProcessMaterial.new()
	motion_material.direction = Vector3.UP
	motion_material.spread = 78.0
	motion_material.initial_velocity_min = 5.0
	motion_material.initial_velocity_max = 19.0
	motion_material.gravity = Vector3.DOWN*U*2.2
	motion_material.scale_min = 0.3
	motion_material.scale_max = 1.0
	particles.process_material = motion_material
	var pebble := SphereMesh.new()
	pebble.radius = 1.3
	pebble.height = 1.9
	pebble.radial_segments = 5
	pebble.rings = 3
	pebble.material = _paint(Color(0.44,0.38,0.34))
	particles.draw_pass_1 = pebble
	return particles

func set_daylight(value: bool) -> void:
	daylight = value
	lighting.set_palette(value)
	lighting.post_material.set_shader_parameter("sun_visible",0.0)
	lighting.environment.fog_enabled = not value
	lighting.environment.fog_density = 0.0012
	for lamp in lamps: lamp.visible = not value
	if not value:
		lighting.sun.light_color = Color(0.61,0.69,0.92)
		lighting.sun.light_energy = 0.46
		lighting.environment.ambient_light_energy = 0.28
		lighting.environment.fog_light_color = Color(0.12,0.16,0.23)
		lighting.current_haze = Color(0.14,0.18,0.27)
		lighting.current_haze_sun_strength = 0.18
		lighting.apply_materials(lighting.palette_materials)
		lighting.sky_material.set_shader_parameter("zenith_color",Color(0.07,0.10,0.19))
		lighting.sky_material.set_shader_parameter("horizon_color",Color(0.18,0.21,0.31))
		lighting.sky_material.set_shader_parameter("solar_core_energy",0.0)

func _pressed(key: String) -> bool:
	var action: String = "ground_"+key
	return Input.is_action_pressed(action) or Input.is_action_just_pressed(action)

func _physics_process(_dt: float) -> void:
	if not player_controlled or not mech.simulation_enabled: return
	mech.controls = {
		"move": Vector2(float(_pressed("right"))-float(_pressed("left")),float(_pressed("forward"))-float(_pressed("back"))),
		"turn": int(_pressed("turn_left"))-int(_pressed("turn_right")),
		"hop": _pressed("hop"), "run": _pressed("run"), "brake": _pressed("brake"), "guard": _pressed("guard"),
	}

func _process(dt: float) -> void:
	if not mech.simulation_enabled: return
	camera.update_view(dt)
	phase = fposmod(phase+dt,100.0)
	exhaust.set_shader_parameter("flow_phase",phase)
	mech.update_exhaust(phase)
	var power: float = mech.controller.delivered_thrust/(mech.mass*Motion.G)
	var p := mech.get_global_transform_interpolated().origin
	jet_light.global_position = p-Vector3.UP*2.5*U
	jet_light.light_energy = clampf(power*2.0,0.0,6.0)
	if motion.touchdowns>last_touchdown:
		dust.global_position = motion.feet[0]+Vector3.UP
		dust.restart()
		dust.emitting = true
	last_touchdown = motion.touchdowns
	skid_dust.global_position = motion.feet[0]+Vector3.UP
	skid_dust.emitting = motion.slip>0.4
	var mode := "Airborne" if not motion.supported else "Skid" if motion.slip>0.25 else "Guard" if motion.guard else "Run" if motion.step_running or motion.running else "Support"
	label.text = "GROUND TRIAL    %s    %.1f m/s\nWASD walk   Alt run   Ctrl crouch   Q/E pivot   R hop   Shift brake\nP pause   F6 light   F7 witness   Backspace reset" % [mode,mech.controller.velocity.length()]

func _unhandled_input(event: InputEvent) -> void:
	camera.handle_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P:
				mech.simulation_enabled = not mech.simulation_enabled
				camera.input_paused = not mech.simulation_enabled
				dust.speed_scale = float(mech.simulation_enabled)
				skid_dust.speed_scale = dust.speed_scale
			KEY_F6: set_daylight(not daylight)
			KEY_F7:
				if witness.current: camera.make_current()
				else: witness.make_current()
			KEY_BACKSPACE: reset_trial()
