extends Node3D

# DCS / Elite Dangerous / AC VI behavior references; continuous body-lift flight.
# Reuse the roster actor's cloned animation library, root cleanup and matte color conversion.
const Actor = preload("res://actors/mechs/mech_asset.tscn")
const Geometry = preload("res://aerial/geometry.gd")
const FlightPose = preload("res://aerial/flight_pose.gd")
const FlightController = preload("res://aerial/flight_controller.gd")
var actor: CharacterBody3D
var flames: Array[MeshInstance3D] = []
var sockets: Array[BoneAttachment3D] = []
var gimbals: Array[Node3D] = []
var skeleton: Skeleton3D
var rig: SkeletonModifier3D
var gas_material: ShaderMaterial
var gas_jets: Array[MeshInstance3D] = []
var gas_sockets: Array[BoneAttachment3D] = []
var gas_gimbals: Array[Node3D] = []
var bone_poses := {}
var controller = FlightController.new()
var motor_springs: Array = []
var neutral_bases: Array[Basis] = []
var motor_delta := 0.0
var prediction_clock := 0.0
var collided := false
var exhaust_throttle := 0.35
var exhaust_phase := 0.0
const VECTOR_LIMIT := PI/6.0
# Measured centers of the actual barrel ends / recessed ports, in source bone space.
# The paired lower backpack barrels are angled down and aft; use their inset caps.
const MOUNTS := [
 ["BackpackL",&"Torso",Vector3(0.9018,-2.9555,-4.4456),Vector3(0,-0.789,-0.615)],
 ["BackpackR",&"Torso",Vector3(-0.9018,-2.9555,-4.4456),Vector3(0,-0.789,-0.615)],
 ["CalfL",&"Shin.L",Vector3(0,1.90103,-0.76695),Vector3(0,0.442,-0.897)],
 ["CalfR",&"Shin.R",Vector3(0,1.90103,-0.76695),Vector3(0,0.442,-0.897)],
 ["HeelL",&"Feet.L",Vector3(0,-0.297,-0.009),Vector3(0,0,-1)],
 ["HeelR",&"Feet.R",Vector3(0,-0.297,-0.009),Vector3(0,0,-1)],
]
const COLD_MOUNTS := [
 ["ShoulderL",&"Shoulder.L",Vector3(-0.63559,0.002,-0.047),Vector3(-1,0,0)],
 ["ShoulderR",&"Shoulder.R",Vector3(0.63559,0.002,-0.047),Vector3(1,0,0)],
 ["ThighL",&"Thigh.L",Vector3(-0.47860,2.339,-0.187),Vector3(-1,0,0)],
 ["ThighR",&"Thigh.R",Vector3(0.47860,2.339,-0.187),Vector3(1,0,0)],
]
var palette_materials: Array[ShaderMaterial] = []
var flying := true
var walk_speed := 0.0

func build(surface: ShaderMaterial, exhaust: ShaderMaterial) -> void:
	actor = Actor.instantiate()
	add_child(actor)
	actor.position.y = -0.9
	actor.set_physics_process(false)
	actor.collision_layer = 0
	actor.collision_mask = 2
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
	# Flight starts from the skeleton rest pose. Imported clips are retained only
	# for asset preview and the dynamic ground-walk option; no idle/boost hold plays.
	actor.animation_player.stop()
	actor.current_animation = &""
	skeleton = actor.find_child("Skeleton3D",true,false)
	rig = FlightPose.new()
	rig.name = "SpringFlightPose"
	skeleton.add_child(rig)
	rig.configure()
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	rig.weapon.modification_processed.connect(_on_pose_modified)
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
		var direction: Vector3 = mount[3].normalized()
		var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.95 else Vector3.UP
		var neutral := Basis.looking_at(-direction,up)
		neutral_bases.append(neutral)
		motor_springs.append(FlightPose.Spring.new())
		gimbal.basis = neutral
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
			flames.append(flame)
	controller.model_scale = global_basis.get_scale().x
	controller.reset(global_position,rotation.y)
	update_animation(0.0)

func step_flight(delta: float, controls: Dictionary, camera_yaw: float) -> void:
	prediction_clock -= delta
	if prediction_clock <= 0.0:
		controller.time_to_impact = predict_impact()
		prediction_clock = 0.1
	var origin := global_position
	controller.advance(delta,controls,camera_yaw)
	quaternion = controller.attitude
	# Sweep the existing native capsule through the complete requested motion.
	# ponytail: chassis capsule only; add limb shapes when limb impacts matter.
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = actor.global_transform
	parameters.motion = controller.position-origin
	parameters.margin = 0.2
	var result := PhysicsTestMotionResult3D.new()
	collided = PhysicsServer3D.body_test_motion(actor.get_rid(),parameters,result)
	if collided:
		controller.position = origin+result.get_travel()
		var normal := result.get_collision_normal()
		if controller.velocity.dot(normal) < 0.0: controller.velocity = controller.velocity.slide(normal)
	global_position = controller.position
	update_animation(delta)

func predict_impact() -> float:
	if controller.velocity.length() < 0.5: return INF
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = actor.global_transform
	parameters.margin = 0.5
	var result := PhysicsTestMotionResult3D.new()
	# Three native swept segments cover the curved, three-second flight path.
	var previous_point := Vector3.ZERO
	for segment in 3:
		var time := float(segment+1)
		var point: Vector3 = (controller.velocity*time+controller.acceleration*time*time*0.5)*controller.distance_scale
		parameters.motion = point-previous_point
		if PhysicsServer3D.body_test_motion(actor.get_rid(),parameters,result):
			return float(segment)+result.get_collision_safe_fraction()
		parameters.from.origin += parameters.motion
		previous_point = point
	return INF

func update_animation(delta: float) -> void:
	rig.update(delta,controller)
	var mix: float = rig.blend.step(Vector3(1 if flying else 0,0,0),delta,0.16).x
	if flying:
		actor.animation_player.stop()
		actor.current_animation = &""
		skeleton.reset_bone_poses()
	else:
		actor._play_animation(&"Walk")
		actor.animation_player.advance(delta)
	rig.active = mix > 0.0001
	rig.ik.active = rig.active
	rig.weapon.active = rig.active
	rig.influence = mix
	rig.ik.influence = mix
	rig.weapon.influence = mix
	actor.rotation = rig.root_angles*mix
	actor.position = -(actor.basis*Vector3(0,0.9,0))+rig.com.value*mix
	motor_delta += delta
	skeleton.advance(delta)

func _on_pose_modified() -> void:
	for index in skeleton.get_bone_count(): bone_poses[index] = skeleton.get_bone_global_pose(index)
	var all_sockets := sockets+gas_sockets
	for index in all_sockets.size():
		var bone := skeleton.find_bone(all_sockets[index].bone_name)
		var neutral_world: Basis = (skeleton.global_basis*bone_poses[bone].basis*neutral_bases[index]).orthonormalized()
		var yaw_demand := clampf(controller.yaw_rate*0.45+controller.yaw_acceleration*0.08,-0.5,0.5)
		var desired: Vector3 = -rig.force.normalized()
		if index < flames.size():
			var anchor: Vector3 = skeleton.global_transform*bone_poses[bone]*MOUNTS[index][2]
			var lever := (anchor-global_position)/maxf(global_basis.get_scale().x,0.001)
			# Tangential exhaust offsets form a yaw couple around the suit center.
			desired = (desired+lever.cross(Vector3.UP)*yaw_demand).normalized()
		if index >= flames.size():
			var sx := 1.0 if (index-flames.size())%2 == 0 else -1.0
			desired = global_basis.orthonormalized()*Vector3(-sx,clampf(-controller.local_acceleration.y*0.015,-0.3,0.3),clampf(-controller.local_acceleration.z*0.02-sx*yaw_demand*0.6,-0.45,0.45)).normalized()
		var local_direction: Vector3 = neutral_world.inverse()*desired
		var angle := minf(acos(clampf(local_direction.z,-1,1)),VECTOR_LIMIT)
		var axis := Vector3.BACK.cross(local_direction).normalized()
		if axis.is_zero_approx(): axis = Vector3.RIGHT
		# The motor state is relative to the physical inlay. Never cancel bone
		# rotation or force a world-down orientation outside its local cone.
		motor_springs[index].step(axis*angle,motor_delta,0.16)
		motor_springs[index].value = motor_springs[index].value.limit_length(VECTOR_LIMIT)
	motor_delta = 0.0
	_refresh_exhaust()

func update_exhaust(throttle: float, phase: float) -> void:
	exhaust_throttle = throttle
	exhaust_phase = phase
	_refresh_exhaust()

func _refresh_exhaust() -> void:
	var all_gimbals := gimbals+gas_gimbals
	for index in all_gimbals.size():
		var angle: Vector3 = motor_springs[index].value
		var rotation_basis := Basis.IDENTITY if angle.is_zero_approx() else Basis(Quaternion(angle.normalized(),angle.length()))
		all_gimbals[index].basis = neutral_bases[index]*rotation_basis
	for index in flames.size():
		var flame := flames[index]
		flame.visible = flying and exhaust_throttle > 0.001
		var load := clampf(rig.shares[index]*6.0*sqrt(rig.force.length()/9.81),0.6,1.5)
		flame.set_instance_shader_parameter("thrust_load",load)
		flame.set_instance_shader_parameter("engine_throttle",exhaust_throttle)
		var beat := (exhaust_phase+float(flame.get_instance_shader_parameter("phase_offset")))*TAU
		flame.scale = Vector3(0.18*(1.0+sin(beat*2.0)*0.07),0.18*(1.0+cos(beat*3.0)*0.05),lerpf(1.2,5.5,exhaust_throttle)*load*(1.0+sin(beat*4.0)*0.12))
	gas_material.set_shader_parameter("flow_phase",exhaust_phase)
	for index in gas_jets.size():
		var sx := 1.0 if index%2 == 0 else -1.0
		var lever := 1.0 if index < 2 else -1.0
		# Opposed shoulder/thigh pulses produce a control couple, freeing the hands.
		var local_burst: Vector3 = global_basis.orthonormalized().inverse()*controller.burst_direction
		var demand := clampf(maxf(0.0,-sx*lever*rig.turn.value.x)*0.8+absf(controller.local_acceleration.z)*0.015+controller.angular_velocity.length()*0.25+maxf(0.0,sx*local_burst.x)*controller.boost_amount,0.0,1.0)
		var pulse := fposmod(rig.clock*6.0+index*0.27,1.0)
		gas_jets[index].visible = flying and demand > 0.02 and pulse < demand
		gas_jets[index].scale = Vector3(0.09,0.09,0.7+demand*0.7)
		gas_jets[index].set_instance_shader_parameter("thrust_load",0.6)
		gas_jets[index].set_instance_shader_parameter("engine_throttle",1.0)
