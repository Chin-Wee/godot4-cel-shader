extends Node3D

# Armored Core VI is the production reference for walking/boost poses with body-mounted exhaust.
# Reuse the roster actor's cloned animation library, root cleanup and matte color conversion.
const Actor = preload("res://actors/mechs/mech_asset.tscn")
const Geometry = preload("res://aerial/geometry.gd")
const FLIGHT_POSES := [&"Boost_Forward", &"Boost_Left", &"Boost_Right", &"Boost_Backward"]
var actor: CharacterBody3D
var flames: Array[MeshInstance3D] = []
var sockets: Array[BoneAttachment3D] = []
var gimbals: Array[Node3D] = []
var vector_angles: Array[Vector2] = []
var vector_targets: Array[Vector2] = []
var vector_pose := -1
var skeleton: Skeleton3D
const VECTOR_LIMIT := PI/6.0
# One backpack, one per calf and one per heel. Dimensions are source-model units.
const MOUNTS := [
 ["Backpack",&"Torso",Vector3(0,-0.3,-1.95)],
 ["CalfL",&"Shin.L",Vector3(0,1.937,-0.840)],
 ["CalfR",&"Shin.R",Vector3(0,1.937,-0.840)],
 ["HeelL",&"Feet.L",Vector3(0,-1.20,0.10)],
 ["HeelR",&"Feet.R",Vector3(0,-1.20,0.10)],
]
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
	skeleton = actor.find_child("Skeleton3D",true,false)
	var nozzle_material := surface.duplicate() as ShaderMaterial
	nozzle_material.set_shader_parameter("body_color",Color(0.065,0.075,0.085))
	palette_materials.append(nozzle_material)
	for mount in MOUNTS:
		var socket := BoneAttachment3D.new()
		socket.name = "Thruster"+mount[0]
		socket.bone_name = mount[1]
		skeleton.add_child(socket)
		sockets.append(socket)
		var gimbal := Node3D.new()
		gimbal.name = "VectoringPivot"
		socket.add_child(gimbal)
		gimbal.position = mount[2]
		gimbals.append(gimbal)
		vector_angles.append(Vector2.ZERO)
		vector_targets.append(Vector2.ZERO)
		var nozzle := CylinderMesh.new()
		nozzle.top_radius = 0.30
		nozzle.bottom_radius = 0.36
		nozzle.height = 0.5
		nozzle.radial_segments = 8
		nozzle.cap_top = false
		nozzle.cap_bottom = false
		var housing := Geometry.add_mesh(gimbal,nozzle,nozzle_material)
		housing.name = "Nozzle"
		housing.position.z = -0.25
		housing.rotation.x = PI/2.0
		var flame := Geometry.add_mesh(gimbal,Geometry.afterburner_mesh(),exhaust)
		flame.name = "EngineFlame"+mount[0]
		flame.custom_aabb = flame.mesh.get_aabb().grow(0.2)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.set_instance_shader_parameter("phase_offset",float(flames.size())*0.173)
		flames.append(flame)
	update_animation(1.0,1.0)

func update_animation(delta: float, throttle: float) -> void:
	var clip: StringName = FLIGHT_POSES[flight_pose] if flying and throttle > 0.5 else (&"Fall" if flying else &"Walk")
	var command_pose := flight_pose if flying else -1
	if vector_pose != command_pose:
		vector_pose = command_pose
		var command := Vector2.ZERO
		if flying:
			match flight_pose:
				1: command = Vector2(0.28,0.04)
				2: command = Vector2(-0.28,0.04)
				3: command = Vector2(0.0,-0.22)
		for index in gimbals.size(): set_thrust_vector(index,command)
	for index in gimbals.size():
		vector_angles[index] = vector_angles[index].lerp(vector_targets[index],1.0-exp(-8.0*delta))
	actor._play_animation(clip)
	actor.animation_player.advance(delta)

func update_exhaust(throttle: float, phase: float) -> void:
	var body_basis := (skeleton.global_basis.inverse()*global_basis).orthonormalized()
	for index in flames.size():
		var flame := flames[index]
		# Bone orientations differ (notably Feet). Stabilize the neutral nozzle axes
		# in body space, then apply each motor's yaw/pitch around that shared rear axis.
		var bone := skeleton.find_bone(sockets[index].bone_name)
		var bone_basis := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
		var angles := vector_angles[index]
		var desired := body_basis*Basis.from_euler(Vector3(angles.y,angles.x,0))
		gimbals[index].basis = bone_basis.inverse()*desired
		flame.visible = flying and throttle > 0.001
		var beat := (phase+float(flame.get_instance_shader_parameter("phase_offset")))*TAU
		flame.scale = Vector3(0.30*(1.0+sin(beat*2.0)*0.07),0.30*(1.0+cos(beat*3.0)*0.05),lerpf(1.2,5.5,throttle)*(1.0+sin(beat*4.0)*0.12))

func set_thrust_vector(index: int, yaw_pitch: Vector2) -> void:
	assert(index >= 0 and index < gimbals.size())
	vector_targets[index] = yaw_pitch.clamp(Vector2(-VECTOR_LIMIT,-VECTOR_LIMIT),Vector2(VECTOR_LIMIT,VECTOR_LIMIT))
