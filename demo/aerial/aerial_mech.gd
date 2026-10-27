extends Node3D

# Armored Core VI is the production reference for walking/boost poses with body-mounted exhaust.
# Reuse the roster actor's cloned animation library, root cleanup and matte color conversion.
const Actor = preload("res://actors/mechs/mech_asset.tscn")
const Geometry = preload("res://aerial/geometry.gd")
const FLIGHT_POSES := [&"Boost_Forward", &"Boost_Left", &"Boost_Right", &"Boost_Backward"]
var actor: CharacterBody3D
var flames: Array[MeshInstance3D] = []
var sockets: Array[BoneAttachment3D] = []
var palette_materials: Array[ShaderMaterial] = []
var flying := true
var flight_pose := 0
var walk_speed := 0.0

func build(surface: ShaderMaterial, exhaust: ShaderMaterial) -> void:
	actor = Actor.instantiate()
	add_child(actor)
	actor.position.y = -0.9
	actor.set_physics_process(false)
	actor.get_node("CameraPivot").process_mode = Node.PROCESS_MODE_DISABLED
	actor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.animation_player.speed_scale = actor.NON_JUMP_ANIMATION_RATE_SCALE
	walk_speed = actor.locomotion_stride_distances[&"Walk"] * actor.visual_scale / actor.animation_player.get_animation(&"Walk").length * actor.NON_JUMP_ANIMATION_RATE_SCALE
	var colors := {}
	for mesh in actor.find_children("*", "MeshInstance3D", true, false):
		for index in mesh.mesh.get_surface_count():
			var converted: ShaderMaterial = mesh.get_active_material(index)
			var color: Color = converted.get_shader_parameter("color")
			if not colors.has(color):
				var material := surface.duplicate() as ShaderMaterial
				var gray := color.get_luminance()
				material.set_shader_parameter("body_color", Color(gray,gray,gray).lerp(color,0.35))
				colors[color] = material
				palette_materials.append(material)
			mesh.set_surface_override_material(index, colors[color])
	# The supplied boost clips are one-frame poses. Hold them for native crossfades.
	var rest: Vector3 = actor.animation_player.get_animation(&"Idle").track_get_key_value(actor._find_position_track(actor.animation_player.get_animation(&"Idle"), &"Root"), 0)
	for name in FLIGHT_POSES:
		var clip: Animation = actor.animation_player.get_animation(name)
		clip.length = 1.0
		clip.loop_mode = Animation.LOOP_LINEAR
		var track: int = actor._find_position_track(clip, &"Root")
		for key in clip.track_get_key_count(track): clip.track_set_key_value(track,key,rest)
	var skeleton: Skeleton3D = actor.find_child("Skeleton3D",true,false)
	var nozzle_material := surface.duplicate() as ShaderMaterial
	nozzle_material.set_shader_parameter("body_color",Color(0.065,0.075,0.085))
	palette_materials.append(nozzle_material)
	for side in [-1.0,1.0]:
		var socket := BoneAttachment3D.new()
		socket.name = "BackThruster" + str(side)
		socket.bone_name = &"Torso"
		skeleton.add_child(socket)
		sockets.append(socket)
		# Source faces +Z; the actor's VisualRoot already corrects facing to -Z.
		var nozzle := CylinderMesh.new()
		nozzle.top_radius = 0.65
		nozzle.bottom_radius = 0.8
		nozzle.height = 0.9
		nozzle.radial_segments = 8
		var housing := Geometry.add_mesh(socket,nozzle,nozzle_material)
		housing.position = Vector3(side*1.35,-0.3,-1.5)
		housing.rotation.x = PI/2.0
		var flame := Geometry.add_mesh(socket,Geometry.afterburner_mesh(),exhaust)
		flame.name = "EngineFlame" + str(side)
		flame.position = housing.position + Vector3(0,0,-0.45)
		flame.rotation.y = PI
		flame.custom_aabb = flame.mesh.get_aabb().grow(0.2)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.set_instance_shader_parameter("phase_offset",(side+1.0)*0.31)
		flames.append(flame)
	update_animation(1.0,1.0)

func update_animation(delta: float, throttle: float) -> void:
	var clip: StringName = FLIGHT_POSES[flight_pose] if flying and throttle > 0.5 else (&"Fall" if flying else &"Walk")
	actor._play_animation(clip)
	actor.animation_player.advance(delta)

func update_exhaust(throttle: float, phase: float) -> void:
	for flame in flames:
		flame.visible = flying and throttle > 0.001
		var beat := (phase+float(flame.get_instance_shader_parameter("phase_offset")))*TAU
		flame.scale = Vector3(0.65*(1.0+sin(beat*2.0)*0.07),0.65*(1.0+cos(beat*3.0)*0.05),lerpf(1.5,7.0,throttle)*(1.0+sin(beat*4.0)*0.12))
