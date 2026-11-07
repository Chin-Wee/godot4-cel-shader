extends RigidBody3D

# DCS / Elite Dangerous behavior references; continuous body-lift flight.
# Reuse the roster actor's cloned animation library, root cleanup and matte color conversion.
const Actor = preload("res://actors/mechs/mech_asset.tscn")
const Geometry = preload("res://aerial/geometry.gd")
const FlightPose = preload("res://aerial/flight_pose.gd")
const FlightController = preload("res://aerial/flight_controller.gd")
const FlightInput = preload("res://aerial/flight_input.gd")
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
var controller: FlightController = FlightController.new()
var motor_springs: Array = []
var neutral_bases: Array[Basis] = []
var display_scale := 50.0
var controls := {}
var ground_motion: RefCounted
var player_controlled := false
var paused_linear_velocity := Vector3.ZERO
var paused_angular_velocity := Vector3.ZERO
var simulation_enabled := true:
	set(value):
		if value == simulation_enabled: return
		simulation_enabled = value
		if not value:
			paused_linear_velocity = linear_velocity
			paused_angular_velocity = angular_velocity
			freeze = true
			# Commit the displayed pose, including when a physics sync is pending.
			PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		else:
			freeze = false
			linear_velocity = paused_linear_velocity
			angular_velocity = paused_angular_velocity
var debug_forces := false
var force_lines: MeshInstance3D
var hull: CollisionShape3D
var leg_reachable := false
var prediction_clock := 0.0
var collided := false
var native_support := false
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
 ["ToeLInner",&"Feet.L",Vector3(-0.375359,0.8,0.15),Vector3(-0.2,0.05,-0.978)],
 ["ToeLOuter",&"Feet.L",Vector3(0.374634,0.8,0.15),Vector3(0.2,0.05,-0.978)],
 ["ToeRInner",&"Feet.R",Vector3(0.375374,0.8,0.15),Vector3(0.2,0.05,-0.978)],
 ["ToeROuter",&"Feet.R",Vector3(-0.374634,0.8,0.15),Vector3(-0.2,0.05,-0.978)],
]
# Fixed opposed triads, seated on inspected torso/backpack armor triangles. The
# upper/lower separation supplies pitch; lateral separation supplies yaw/roll.
# Shared rigid torso axes keep opposed jets balanced while the legs articulate.
const COLD_MOUNTS := [
 ["UpperLSide",&"Torso",Vector3(1.596664,1.112213,0.25),Vector3.RIGHT],
 ["UpperLFore",&"Torso",Vector3(0.822496,1.353148,1.307773),Vector3.BACK],
 ["UpperLAft",&"Torso",Vector3(1.077153,1.250922,-3.557281),Vector3.FORWARD],
 ["UpperRSide",&"Torso",Vector3(-1.596657,1.112215,0.25),Vector3.LEFT],
 ["UpperRFore",&"Torso",Vector3(-0.822495,1.353148,1.307774),Vector3.BACK],
 ["UpperRAft",&"Torso",Vector3(-1.077152,1.250921,-3.557281),Vector3.FORWARD],
 ["LowerLSide",&"Torso",Vector3(1.246701,-2.183311,-3.406221),Vector3.RIGHT],
 ["LowerLFore",&"Torso",Vector3(0.734726,0.163116,1.28089),Vector3.BACK],
 ["LowerLAft",&"Torso",Vector3(1.335068,-2.64238,-4.471244),Vector3.FORWARD],
 ["LowerRSide",&"Torso",Vector3(-1.246699,-2.183311,-3.406221),Vector3.LEFT],
 ["LowerRFore",&"Torso",Vector3(-0.734725,0.163116,1.280891),Vector3.BACK],
 ["LowerRAft",&"Torso",Vector3(-1.335067,-2.642381,-4.471244),Vector3.FORWARD],
]
var palette_materials: Array[ShaderMaterial] = []

func build(surface: ShaderMaterial, exhaust: ShaderMaterial) -> void:
	actor = Actor.instantiate()
	add_child(actor)
	actor.scale = Vector3.ONE * display_scale
	actor.position.y = -0.9 * display_scale
	actor.collision_mask = 0
	actor.get_node("CollisionShape3D").disabled = true
	mass = 10000.0
	gravity_scale = FlightController.GRAVITY * FlightController.WORLD_UNITS_PER_METER / float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	collision_layer = 8
	collision_mask = 6
	hull = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4 * display_scale
	capsule.height = 1.8 * display_scale
	hull.shape = capsule
	add_child(hull)
	rig = FlightPose.new()
	assert(MOUNTS.size()==rig.profile.main_booster_max_thrust.size())
	assert(COLD_MOUNTS.size()==rig.profile.cold_booster_max_thrust.size())
	controller.configure(self, display_scale, rig.profile)
	actor.set_physics_process(false)
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.get_node("CameraPivot").process_mode = Node.PROCESS_MODE_DISABLED
	actor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
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
	# Flight starts from the skeleton rest pose.
	actor.animation_player.stop()
	actor.current_animation = &""
	skeleton = actor.find_child("Skeleton3D",true,false)
	# Flight animation pass: the supplied gun remains available in asset preview.
	# Mesh inspection: both are weapon geometry weighted solely to Hands.R;
	# Cube is the Torso-weighted backpack and must remain visible.
	for name in ["GUN","Cube_001"]: skeleton.find_child(name,false,false).visible = false
	rig.name = "SpringFlightPose"
	skeleton.add_child(rig)
	rig.configure(actor.animation_player,self)
	# Seed the first physics tick; subsequent hardpoints come from the final modifier.
	for index in skeleton.get_bone_count(): bone_poses[index] = skeleton.get_bone_global_pose(index)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
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
		var radius := 0.085 if cold else 0.18
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
	controller.reset()
	update_animation(0.0)

# Physics consumes one previous-tick pose for hardpoints. The new pose is then
# advanced on this same fixed clock; rendering never runs the motor simulation.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if freeze or not simulation_enabled or sockets.is_empty(): return
	if absf(state.inverse_inertia_tensor.determinant()) < 1e-30: return
	var outlets := _thruster_outlets(sockets,MOUNTS,0)
	var cold_outlets := _thruster_outlets(gas_sockets,COLD_MOUNTS,MOUNTS.size())
	collided = state.get_contact_count() > 0
	native_support = false
	for index in state.get_contact_count():
		# Godot labels the body side "local", but returns this vector in world axes.
		if state.get_contact_local_normal(index).dot(Vector3.UP)>0.65: native_support = true
	if ground_motion:
		ground_motion.prepare(state, controls)
		controller.step_ground(state,outlets,cold_outlets,aerodynamic_surfaces(),
			ground_motion.supported,ground_motion.jet_force,ground_motion.jet_moment,ground_motion.hot_enabled)
		ground_motion.apply_traction(state,controller.main_force+controller.cold_force+controller.aero_force)
	else:
		var contact := _ground_probe(state)
		controller.step(state, FlightInput.read_input() if player_controlled else controls, outlets, cold_outlets, contact.grounded, contact.reachable, aerodynamic_surfaces(), rig.arms.brake_spread())
	prediction_clock -= state.step
	if prediction_clock <= 0:
		controller.time_to_impact = predict_impact()
		prediction_clock = 0.1
	update_animation(state.step)

func aerodynamic_surfaces() -> Array:
	var surfaces := []
	var profile = rig.profile
	for index in profile.aero_bones.size():
		var bone := skeleton.find_bone(profile.aero_bones[index])
		var pose: Transform3D = bone_poses[bone]
		var rotation := skeleton.global_basis.orthonormalized()*pose.basis.orthonormalized()*skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse()*Basis(Vector3.RIGHT,-profile.aero_incidence[index])
		var offset: Vector3 = skeleton.global_transform*pose.origin-global_position
		# Torso panel represents the whole trunk/pelvis, below its upper bone pivot.
		if index==0: offset -= global_basis.y*2.0*display_scale/50.0*FlightController.WORLD_UNITS_PER_METER
		surfaces.append({"position":offset,"normal":rotation*Vector3.FORWARD,"forward":rotation*Vector3.UP,"fraction":profile.aero_fractions[index]})
	return surfaces

func _thruster_outlets(attachments: Array, mounts: Array, offset: int) -> Array:
	var outlets := []
	for index in attachments.size():
		var bone := skeleton.find_bone(attachments[index].bone_name)
		var transform: Transform3D = skeleton.global_transform*bone_poses[bone]
		outlets.append({"position":transform*mounts[index][2]-global_position,
			"basis":(transform.basis*neutral_bases[index+offset]).orthonormalized()})
	return outlets

func _ground_probe(state: PhysicsDirectBodyState3D) -> Dictionary:
	var reach := 0.9 * display_scale
	var ray := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * (reach + 8.0), 2)
	ray.exclude = [get_rid()]
	var hit := state.get_space_state().intersect_ray(ray)
	var suitable: bool = not hit.is_empty() and hit.normal.dot(Vector3.UP) > 0.65 and global_basis.y.dot(Vector3.UP) > 0.65
	var distance: float = global_position.distance_to(hit.position) if suitable else INF
	leg_reachable = suitable and distance <= reach + 8.0
	return {"grounded":suitable and distance <= reach + 0.6, "reachable":leg_reachable}

# Explicit fixture/preview reset only. Ordinary flight never writes these states.
func reset_flight(origin: Vector3, orientation := Quaternion.IDENTITY, speed := Vector3.ZERO) -> void:
	global_transform = Transform3D(Basis(orientation), origin)
	linear_velocity = speed * FlightController.WORLD_UNITS_PER_METER
	angular_velocity = Vector3.ZERO
	controller.reset()
	rig.reset()
	native_support = false
	collided = false
	prediction_clock = 0.0
	update_animation(0.0)
	reset_physics_interpolation()

func predict_impact() -> float:
	if controller.velocity.length() < 0.5: return INF
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull.shape
	query.transform = global_transform
	query.collision_mask = 2
	query.exclude = [get_rid()]
	var previous_point := Vector3.ZERO
	for segment in 3:
		var time := float(segment + 1)
		var point: Vector3 = (controller.velocity * time + controller.acceleration * time * time * 0.5) * FlightController.WORLD_UNITS_PER_METER
		query.motion = point - previous_point
		var fractions := get_world_3d().direct_space_state.cast_motion(query)
		if fractions[0] < 1.0: return float(segment) + fractions[0]
		query.transform.origin += query.motion
		previous_point = point
	return INF

func update_animation(delta: float) -> void:
	rig.update(delta,controller)
	actor.animation_player.stop()
	actor.current_animation = &""
	skeleton.reset_bone_poses()
	actor.rotation = rig.root_angles
	actor.position = (-(Basis.from_euler(actor.rotation)*Vector3(0,0.9,0))+rig.com.value+rig.contacts.pelvis.value) * display_scale
	skeleton.advance(delta)

func capture_pose() -> void:
	# Called inside the final native modifier, while the completed pose exists.
	# No chain of modifier-completion signals and no restored-rest pose reads.
	for index in skeleton.get_bone_count(): bone_poses[index] = skeleton.get_bone_global_pose(index)
	rig.arms.sample_completed(skeleton,bone_poses)
	for index in MOUNTS.size(): motor_springs[index].value = controller.motor_angles[index]
	for index in gas_gimbals.size(): motor_springs[index+MOUNTS.size()].value = controller.cold_angles[index]
	_refresh_exhaust()

func update_force_debug() -> void:
	if not is_instance_valid(force_lines):
		if not debug_forces: return
		force_lines = MeshInstance3D.new()
		force_lines.top_level = true
		force_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		force_lines.material_override = material
		add_child(force_lines)
	force_lines.visible = debug_forces
	if not debug_forces: return
	force_lines.global_position = global_position
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var vectors := [controller.main_force / mass, controller.cold_force / mass, controller.aero_force / mass, controller.rcs_torque / (mass * 2.0), Vector3.DOWN * FlightController.GRAVITY]
	var colors := [Color.ORANGE, Color.SKY_BLUE, Color.CYAN, Color.MAGENTA, Color.WHITE]
	for index in vectors.size():
		var tip: Vector3 = vectors[index].limit_length(50.0) * 3.0
		if tip.length() < 0.01: tip = Vector3.UP * 0.01
		lines.surface_set_color(colors[index])
		lines.surface_add_vertex(Vector3.ZERO)
		lines.surface_add_vertex(tip)
	lines.surface_end()
	force_lines.mesh = lines

func update_exhaust(phase: float) -> void:
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
		var output: float = controller.motor_forces[index].length()
		var throttle: float = clampf(output/maxf(controller.hot_max_thrust(index),0.000001),0,1)
		var load := throttle
		flame.visible = output>0.00001
		flame.set_instance_shader_parameter("thrust_load",load)
		flame.set_instance_shader_parameter("engine_throttle",throttle)
		var beat := (exhaust_phase+float(flame.get_instance_shader_parameter("phase_offset")))*TAU
		flame.scale = Vector3(0.18*(1.0+sin(beat*2.0)*0.07),0.18*(1.0+cos(beat*3.0)*0.05),lerpf(1.2,5.5,throttle)*load*(1.0+sin(beat*4.0)*0.12))
	gas_material.set_shader_parameter("flow_phase",exhaust_phase)
	for index in gas_jets.size():
		# The same nozzle force drives the native body and its visible exhaust.
		var demand: float = controller.cold_forces[index].length()/maxf(controller.cold_max_thrust(index),0.000001)
		gas_jets[index].visible = demand>0.00001
		gas_jets[index].scale = Vector3(0.09,0.09,0.7+demand*0.7)
		gas_jets[index].set_instance_shader_parameter("thrust_load",demand)
		gas_jets[index].set_instance_shader_parameter("engine_throttle",demand)
