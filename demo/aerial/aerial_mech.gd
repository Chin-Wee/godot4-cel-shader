extends Node3D

# Marvel's Iron Man VR is the flight reference: upright hover, then body-led acceleration.
# Reuse the roster actor's cloned animation library, root cleanup and matte color conversion.
const Actor = preload("res://actors/mechs/mech_asset.tscn")
const Geometry = preload("res://aerial/geometry.gd")
const FlightPose = preload("res://aerial/flight_pose.gd")
const FLIGHT_POSES := [&"Boost_Forward", &"Boost_Left", &"Boost_Right", &"Boost_Backward"]
var actor: CharacterBody3D
var flames: Array[MeshInstance3D] = []
var sockets: Array[BoneAttachment3D] = []
var gimbals: Array[Node3D] = []
var vector_angles: Array[Vector2] = []
var vector_targets: Array[Vector2] = []
var skeleton: Skeleton3D
var rig: SkeletonModifier3D
var gas_material: ShaderMaterial
var gas_jets: Array[MeshInstance3D] = []
var gas_sockets: Array[BoneAttachment3D] = []
var gas_gimbals: Array[Node3D] = []
var bone_poses := {}
var motion_ready := false
var previous_position := Vector3.ZERO
var previous_velocity := Vector3.ZERO
var previous_yaw := 0.0
var local_velocity := Vector3.ZERO
var local_acceleration := Vector3.ZERO
var yaw_rate := 0.0
var exhaust_throttle := 0.35
var exhaust_phase := 0.0
const VECTOR_LIMIT := PI/6.0
const NEUTRAL_EXHAUST := Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN)
var flight_amount := 0.0
# Measured centers of the actual barrel ends / recessed ports, in source bone space.
# The paired lower backpack barrels are angled down and aft; use their inset caps.
const MOUNTS := [
 ["BackpackL",&"Torso",Vector3(0.9018,-2.9555,-4.4456)],
 ["BackpackR",&"Torso",Vector3(-0.9018,-2.9555,-4.4456)],
 ["CalfL",&"Shin.L",Vector3(0,1.90103,-0.76695)],
 ["CalfR",&"Shin.R",Vector3(0,1.90103,-0.76695)],
 ["HeelL",&"Feet.L",Vector3(0,-0.297,-0.009)],
 ["HeelR",&"Feet.R",Vector3(0,-0.297,-0.009)],
]
const COLD_MOUNTS := [
 ["ShoulderL",&"Shoulder.L",Vector3(-0.63559,0.002,-0.047)],
 ["ShoulderR",&"Shoulder.R",Vector3(0.63559,0.002,-0.047)],
 ["ThighL",&"Thigh.L",Vector3(-0.47860,2.339,-0.187)],
 ["ThighR",&"Thigh.R",Vector3(0.47860,2.339,-0.187)],
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
	# The source idle has relaxed arms and straight legs. Keep authored boost/fall
	# clips for preview, but use this held stance for hover and streamlined flight.
	var airborne := actor.animation_player.get_animation(&"Idle").duplicate(true) as Animation
	airborne.length = 1.0
	airborne.loop_mode = Animation.LOOP_LINEAR
	actor.animation_player.get_animation_library(&"").add_animation(&"Airborne",airborne)
	skeleton = actor.find_child("Skeleton3D",true,false)
	rig = FlightPose.new()
	rig.name = "SpringFlightPose"
	skeleton.add_child(rig)
	rig.configure()
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	rig.ik.modification_processed.connect(_on_pose_modified)
	var nozzle_material := surface.duplicate() as ShaderMaterial
	nozzle_material.set_shader_parameter("body_color",Color(0.065,0.075,0.085))
	palette_materials.append(nozzle_material)
	var vapor := exhaust.duplicate() as ShaderMaterial
	vapor.set_shader_parameter("core_color",Color(0.85,0.95,1.0))
	vapor.set_shader_parameter("plume_color",Color(0.42,0.65,0.78))
	vapor.set_shader_parameter("hot_color",Color(0.7,0.86,0.92))
	vapor.set_shader_parameter("rim_color",Color(0.3,0.5,0.65))
	vapor.set_shader_parameter("emission_strength",0.15)
	palette_materials.append(vapor)
	gas_material = vapor
	for mount in MOUNTS+COLD_MOUNTS:
		var cold: bool = mount in COLD_MOUNTS
		var socket := BoneAttachment3D.new()
		socket.name = "Thruster"+mount[0]
		socket.bone_name = mount[1]
		skeleton.add_child(socket)
		var gimbal := Node3D.new()
		gimbal.name = "VectoringPivot"
		socket.add_child(gimbal)
		gimbal.position = mount[2]
		var radius := (0.10 if str(mount[0]).begins_with("Shoulder") else 0.065) if cold else 0.18
		# A seated ball joint connects the vectoring bell to its modeled recess.
		var collar := SphereMesh.new()
		collar.radius = radius
		collar.height = radius*2.0
		collar.radial_segments = 8
		collar.rings = 4
		Geometry.add_mesh(gimbal,collar,nozzle_material).name = "SeatedJoint"
		var nozzle := CylinderMesh.new()
		nozzle.top_radius = radius*0.78
		nozzle.bottom_radius = radius
		nozzle.height = radius*1.3
		nozzle.radial_segments = 8
		nozzle.cap_top = false
		nozzle.cap_bottom = false
		var housing := Geometry.add_mesh(gimbal,nozzle,nozzle_material)
		housing.name = "Nozzle"
		housing.position.z = radius*0.6
		housing.rotation.x = PI/2.0
		var flame := Geometry.add_mesh(gimbal,Geometry.afterburner_mesh(),vapor if cold else exhaust)
		flame.name = ("ColdGas" if cold else "EngineFlame")+mount[0]
		flame.position.z = radius*1.25
		flame.custom_aabb = flame.mesh.get_aabb().grow(0.2)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.set_instance_shader_parameter("phase_offset",float(flames.size()+gas_jets.size())*0.173)
		if cold:
			gas_sockets.append(socket)
			gas_gimbals.append(gimbal)
			gas_jets.append(flame)
		else:
			sockets.append(socket)
			gimbals.append(gimbal)
			vector_angles.append(Vector2.ZERO)
			vector_targets.append(Vector2.ZERO)
			flames.append(flame)
	update_animation(0.0,0.35)

func reset_motion() -> void:
	motion_ready = false
	previous_velocity = Vector3.ZERO
	local_velocity = Vector3.ZERO
	local_acceleration = Vector3.ZERO
	yaw_rate = 0.0

func update_animation(delta: float, throttle: float) -> void:
	if delta > 0.0 and motion_ready:
		var velocity := (global_position-previous_position)/delta
		var axes := global_basis.orthonormalized().inverse()
		var size := maxf(absf(global_basis.get_scale().x),0.001)
		local_velocity = axes*velocity/size
		local_acceleration = (axes*(velocity-previous_velocity)/delta/size).limit_length(8.0)
		yaw_rate = clampf(angle_difference(previous_yaw,global_rotation.y)/delta,-3.0,3.0)
		previous_velocity = velocity
	previous_position = global_position
	previous_yaw = global_rotation.y
	motion_ready = true
	rig.update(delta,flight_amount if flying else 0.0,flight_pose,local_velocity,local_acceleration,yaw_rate)
	var mix: float = rig.blend.step(Vector3(1 if flying else 0,0,0),delta,0.16).x
	actor._play_animation(&"Airborne" if flying else &"Walk")
	actor.animation_player.advance(delta)
	rig.active = mix > 0.0001
	rig.ik.active = rig.active
	rig.influence = mix
	rig.ik.influence = mix
	actor.rotation = rig.root_angles*mix
	actor.position = -(actor.basis*Vector3(0,0.9,0))
	actor.position += rig.com.value*mix
	# Force demand steers the six main bells; individual preview offsets remain additive.
	# Calf recesses face down/aft. A 15-degree aft neutral clears the lower armor lip.
	var force_direction: Vector3 = actor.basis.inverse()*rig.force.normalized()
	var command := Vector2(-atan2(force_direction.x,force_direction.y),atan2(force_direction.z,force_direction.y))
	for index in gimbals.size():
		var clearance := Vector2(0,-0.26) if index in [2,3] else Vector2.ZERO
		var target: Vector2 = (command+clearance+vector_targets[index]).clamp(Vector2(-VECTOR_LIMIT,-VECTOR_LIMIT),Vector2(VECTOR_LIMIT,VECTOR_LIMIT))
		vector_angles[index] = vector_angles[index].lerp(target,1.0-exp(-8.0*delta))
	exhaust_throttle = throttle
	skeleton.advance(delta)

func _on_pose_modified() -> void:
	for index in skeleton.get_bone_count():
		bone_poses[index] = skeleton.get_bone_global_pose(index)
	_refresh_exhaust()

func update_exhaust(throttle: float, phase: float) -> void:
	exhaust_throttle = throttle
	exhaust_phase = phase
	_refresh_exhaust()

func _refresh_exhaust() -> void:
	var body_basis := skeleton.global_basis.inverse()*actor.global_basis.orthonormalized()
	var nozzle_scale := Basis.from_scale(skeleton.global_basis.get_scale())
	for index in flames.size():
		var bone := skeleton.find_bone(sockets[index].bone_name)
		var pose: Transform3D = bone_poses.get(bone,skeleton.get_bone_global_pose(bone)) if rig.active else skeleton.get_bone_global_pose(bone)
		var angles := vector_angles[index]
		var desired := body_basis*NEUTRAL_EXHAUST*Basis.from_euler(Vector3(angles.y,angles.x,0))*nozzle_scale
		gimbals[index].basis = pose.basis.inverse()*desired
		var flame := flames[index]
		flame.visible = flying and exhaust_throttle > 0.001
		var load := clampf(rig.shares[index]*6.0*sqrt(rig.force.length()/9.81),0.6,1.5)
		flame.set_instance_shader_parameter("thrust_load",load)
		var beat := (exhaust_phase+float(flame.get_instance_shader_parameter("phase_offset")))*TAU
		flame.scale = Vector3(0.18*(1.0+sin(beat*2.0)*0.07),0.18*(1.0+cos(beat*3.0)*0.05),lerpf(1.2,5.5,exhaust_throttle)*load*(1.0+sin(beat*4.0)*0.12))
	gas_material.set_shader_parameter("flow_phase",exhaust_phase)
	for index in gas_jets.size():
		var sx := 1.0 if index%2 == 0 else -1.0
		var bone := skeleton.find_bone(gas_sockets[index].bone_name)
		var pose: Transform3D = bone_poses.get(bone,skeleton.get_bone_global_pose(bone)) if rig.active else skeleton.get_bone_global_pose(bone)
		var direction := Vector3(-sx,clampf(-local_acceleration.y*0.1,-0.3,0.3),clampf(local_acceleration.z*0.15,-0.45,0.45)).normalized()
		var desired := body_basis*Basis.looking_at(-direction,Vector3.UP)*nozzle_scale
		gas_gimbals[index].basis = pose.basis.inverse()*desired
		var lever := 1.0 if index < 2 else -1.0
		# Opposed shoulder/thigh pulses produce a control couple, freeing the hands.
		var demand := clampf(maxf(0.0,-sx*lever*rig.turn.value.x)*0.8+absf(local_acceleration.z)*0.15+absf(yaw_rate)*0.3,0.0,0.85)
		var pulse := fposmod(rig.clock*6.0+index*0.27,1.0)
		gas_jets[index].visible = flying and exhaust_throttle > 0.001 and demand > 0.02 and pulse < demand
		gas_jets[index].scale = Vector3(0.09,0.09,0.7+demand*0.7)
		gas_jets[index].set_instance_shader_parameter("thrust_load",0.6)

func set_thrust_vector(index: int, yaw_pitch: Vector2) -> void:
	assert(index >= 0 and index < gimbals.size())
	vector_targets[index] = yaw_pitch.clamp(Vector2(-VECTOR_LIMIT,-VECTOR_LIMIT),Vector2(VECTOR_LIMIT,VECTOR_LIMIT))
