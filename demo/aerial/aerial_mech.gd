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
var neutral_bases: Array[Basis] = []
var rear_waist_offset := Vector3.ZERO
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
const GROUND_ANIMATION_BLEND := 0.12
const GROUND_WALK_STEPS_PER_CYCLE := 2.0
# Six traditional mobile-suit main outlets: backpack, rear calves and foot soles.
# MechAsset is +Z-forward; each direction is authored in its mounting bone frame.
# Centers are measured against the actual barrel/recess surfaces; foot soles use the outermost downward-facing triangles.
const MOUNTS := [
 ["BackpackL",&"Torso",Vector3(0.9018,-2.9555,-4.4456),Vector3(0,-0.789,-0.615)],
 ["BackpackR",&"Torso",Vector3(-0.9018,-2.9555,-4.4456),Vector3(0,-0.789,-0.615)],
 ["CalfL",&"Shin.L",Vector3(0,1.90103,-0.76695),Vector3(0,0.442,-0.897)],
 ["CalfR",&"Shin.R",Vector3(0,1.90103,-0.76695),Vector3(0,0.442,-0.897)],
 ["FootSoleL",&"Feet.L",Vector3(0,-0.297,-0.193247),Vector3(0,0,-1)],
 ["FootSoleR",&"Feet.R",Vector3(0,-0.297,-0.193246),Vector3(0,0,-1)],
]
# Twelve fixed cold-gas verniers across six paired, mesh-verified locations.
# Static child meshes are attached to their parent bones in the GLB hierarchy.
# Torso and waist positions are measured in their respective parent-bone frames.
const COLD_MOUNTS := [
 ["ShoulderL",&"Shoulder.L",Vector3(-0.63559,0.002,-0.047),Vector3(-1,0,0)],
 ["ChestFrontL",&"Torso",Vector3(0.822496,1.353148,1.307773),Vector3(0,-0.175874,0.984413)],
 ["BackpackUpperL",&"Torso",Vector3(1.077153,1.250922,-3.557281),Vector3(0,0,-1)],
 ["BackpackSideL",&"Torso",Vector3(1.352454,-2.086017,-3.531022),Vector3(-0.831482,0.34158,-0.438133)],
 ["WaistFrontL",&"Low_Waist",Vector3(0.734726,2.449736,1.022654),Vector3(0,0.612551,0.790431)],
 ["WaistRearL",&"Low_Waist",Vector3(1.222387,-0.109595,-1.317057),Vector3(0.919755,-0.380953,-0.094472)],
 ["ShoulderR",&"Shoulder.R",Vector3(0.63559,0.002,-0.047),Vector3(1,0,0)],
 ["ChestFrontR",&"Torso",Vector3(-0.822495,1.353148,1.307774),Vector3(0,-0.175874,0.984413)],
 ["BackpackUpperR",&"Torso",Vector3(-1.077152,1.250921,-3.557281),Vector3(0,0,-1)],
 ["BackpackSideR",&"Torso",Vector3(-1.352453,-2.086016,-3.531022),Vector3(0.831482,0.34158,-0.438133)],
 ["WaistFrontR",&"Low_Waist",Vector3(-0.734725,2.449736,1.022654),Vector3(0,0.612551,0.790431)],
 ["WaistRearR",&"Low_Waist",Vector3(-1.222384,-0.109595,-1.317059),Vector3(-0.919755,-0.380953,-0.094474)],
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
	var skirt := skeleton.find_child("Waist Armor",true,false) as MeshInstance3D
	var skirt_before := skirt.global_position
	rig.profile.fit_waist_armor(skeleton)
	var waist_frame := skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(&"Low_Waist"))
	rear_waist_offset = waist_frame.basis.inverse()*(skirt.global_position-skirt_before)
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
		gimbal.name = "FixedOutlet"
		socket.add_child(gimbal)
		gimbal.position = mount_position(mount)
		var direction: Vector3 = mount[3].normalized()
		var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.95 else Vector3.UP
		var neutral := Basis.looking_at(-direction,up)
		neutral_bases.append(neutral)
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
	var incidence: PackedFloat32Array = profile.authored_aero_incidence if controller.articulated_flight else profile.aero_incidence
	for index in profile.aero_bones.size():
		var bone := skeleton.find_bone(profile.aero_bones[index])
		var pose: Transform3D = bone_poses[bone]
		var rotation := skeleton.global_basis.orthonormalized()*pose.basis.orthonormalized()*skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse()*Basis(Vector3.RIGHT,-incidence[index])
		var offset: Vector3 = skeleton.global_transform*pose.origin-global_position
		# Torso panel represents the whole trunk/pelvis, below its upper bone pivot.
		if index==0: offset -= global_basis.y*2.0*display_scale/50.0*FlightController.WORLD_UNITS_PER_METER
		surfaces.append({"position":offset,"normal":rotation*Vector3.FORWARD,"forward":rotation*Vector3.UP,"fraction":profile.aero_fractions[index]})
	return surfaces

func mount_position(mount: Array) -> Vector3:
	var position: Vector3 = mount[2]
	if String(mount[0]).begins_with("WaistRear"):
		position += rear_waist_offset
	return position

func _thruster_outlets(attachments: Array, mounts: Array, offset: int) -> Array:
	var outlets := []
	for index in attachments.size():
		var bone := skeleton.find_bone(attachments[index].bone_name)
		var transform: Transform3D = skeleton.global_transform*bone_poses[bone]
		outlets.append({"position":transform*mount_position(mounts[index])-global_position,
			"basis":(transform.basis*neutral_bases[index+offset]).orthonormalized()})
	return outlets

func leg_gesture_feasible(primary: PackedVector3Array, gesture: PackedVector3Array) -> bool:
	# Test the next reachable joint geometry against the same fixed-axis
	# allocator. Only the leg chain changes; torso and other mounts use the
	# last completed pose, matching the one-tick actuator pipeline.
	if primary==gesture: return true
	var first := _pose_wrench_error(primary)
	var second := _pose_wrench_error(gesture)
	return second<=first+0.002

func apply_primary_trim(angles: PackedVector3Array, trim: Vector3) -> PackedVector3Array:
	var result := angles.duplicate()
	for side in 2:
		var sign_axis := 1.0 if side==0 else -1.0
		var hip := result[side*3]
		hip.z += trim.z*sign_axis
		result[side*3] = rig.profile.limit_joint(hip,side,0)
		var ankle := result[side*3+2]
		ankle.x += trim.x
		ankle.z += trim.y
		result[side*3+2] = rig.profile.limit_joint(ankle,side,2)
	return result

func calibrate_primary_pose(angles: PackedVector3Array, previous: Vector3, axis: int) -> Vector3:
	var best := previous
	var error := _pose_wrench_error(apply_primary_trim(angles,best),true)+best.length()*0.02
	var limit := Vector3(0.14,0.12,0.12)
	# One bounded coordinate search per interval; do not run a full pose
	# optimizer every tick. Stance trim may widen but never close the key.
	for direction in [-1.0,1.0]:
		var candidate := previous
		candidate[axis] += direction*0.045
		candidate = candidate.clamp(Vector3(-limit.x,-limit.y,0.0),limit)
		var score := _pose_wrench_error(apply_primary_trim(angles,candidate),true)+candidate.length()*0.02
		if score<error-0.0005:
			best = candidate
			error = score
	return best

func _pose_wrench_error(angles: PackedVector3Array, hot_only := false) -> float:
	var length_scale := display_scale/FlightController.WORLD_UNITS_PER_METER
	var weight := mass*FlightController.GRAVITY
	var ports := []
	var seed := []
	var predicted := {}
	for side in 2:
		var profile = rig.profile
		var names := [profile.thigh_bones[side],profile.knee_bones[side],profile.foot_bones[side]]
		var chain := PackedInt32Array()
		var bone := skeleton.find_bone(names[2])
		while bone>=0:
			chain.append(bone)
			if skeleton.get_bone_name(bone)==names[0]: break
			bone = skeleton.get_bone_parent(bone)
		chain.reverse()
		var parent: Transform3D = bone_poses[skeleton.get_bone_parent(chain[0])]
		for index in chain:
			var local := skeleton.get_bone_rest(index)
			var joint := names.find(skeleton.get_bone_name(index))
			if joint>=0:
				var rest := skeleton.get_bone_global_rest(index).basis.orthonormalized()
				var goal: Vector3 = profile.limit_joint(angles[side*3+joint],side,joint)
				var current: Vector3 = rig.legs[side*3+joint].value
				var reachable := current.move_toward(goal,profile.joint_speed[joint]*0.16)
				local.basis *= rest.inverse()*Basis.from_euler(reachable)*rest
			parent *= local
			predicted[index] = parent
	for i in MOUNTS.size()+(0 if hot_only else COLD_MOUNTS.size()):
		var hot := i<MOUNTS.size()
		var index := i if hot else i-MOUNTS.size()
		var mount: Array = MOUNTS[index] if hot else COLD_MOUNTS[index]
		var bone := skeleton.find_bone(mount[1])
		var pose: Transform3D = skeleton.global_transform*predicted.get(bone,bone_poses[bone])
		var capacity := controller.hot_max_thrust(index) if hot else controller.cold_thrust_limit(index)
		var valve = controller.hot_valves[index] if hot else controller.cold_valves[index]
		var can_fire := not hot or controller.detent>0 or controller.jump_remaining>0.0
		var tail: float = valve.preview(0.0,0.16)*capacity/weight
		var available: float = valve.preview(float(can_fire),0.16)*capacity/weight
		ports.append({"basis":(pose.basis*neutral_bases[i]).orthonormalized(),
			"lever":(pose*mount_position(mount)-global_position)/display_scale,"cone":0.0,"center":Vector3.ZERO,
			"gain":1.0,"minimum":tail,"maximum":available,"off":tail,"fuel":0.0})
		seed.append((controller.motor_forces[index] if hot else controller.cold_forces[index])/weight)
	var force := controller.requested_main_force/weight
	var moment := (controller.control_torque-controller.aero_torque)/(weight*length_scale)
	var plan := FlightController.Allocator.solve(ports,force,moment,Vector3.ZERO,seed,[],32,FlightController.FIXED_FIT)
	for i in plan.size():
		force -= plan[i]
		moment -= ports[i].lever.cross(plan[i])
	return force.length()+moment.length()*1.4

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
	var ground_animation := _ground_animation_name()
	rig.ground_animation_active = not ground_animation.is_empty()
	rig.update(delta,controller)
	if not controller.articulated_flight or not ground_animation.is_empty(): skeleton.reset_bone_poses()
	if ground_animation.is_empty():
		actor.animation_player.stop()
		actor.animation_player.speed_scale = 1.0
		actor.current_animation = &""
		if controller.articulated_flight: skeleton.reset_bone_poses()
	else:
		if actor.current_animation != ground_animation or not actor.animation_player.is_playing():
			actor.animation_player.play(ground_animation,GROUND_ANIMATION_BLEND)
			actor.current_animation = ground_animation
		if ground_animation == &"Idle":
			actor.animation_player.speed_scale = 1.0
			actor.animation_player.seek(0.0,true)
		else:
			var animation: Animation = actor.animation_player.get_animation(ground_animation)
			var cycle_duration: float = ground_motion.step_duration*GROUND_WALK_STEPS_PER_CYCLE
			actor.animation_player.speed_scale = animation.length/maxf(cycle_duration,0.01)
			actor.animation_player.advance(delta)
	actor.rotation = rig.root_angles
	actor.position = (-(Basis.from_euler(actor.rotation)*Vector3(0,0.9,0))+rig.com.value+rig.contacts.pelvis.value) * display_scale
	skeleton.advance(delta)


func _ground_animation_name() -> StringName:
	if ground_motion == null or not ground_motion.supported:
		return &""
	if (
		ground_motion.braking or ground_motion.skidding
		or ground_motion.pivot_steps > 0 or ground_motion.hop_load > 0.0
		or ground_motion.catch_time > 0.0 or ground_motion.recovery > 0.0
		or ground_motion.hot_enabled
	):
		return &""
	if not actor.animation_player.has_animation(&"Idle") or not actor.animation_player.has_animation(&"Walk"):
		return &""
	var planar_speed: float = ground_motion.velocity.slide(ground_motion.support_normal).length()
	var moving: bool = ground_motion.step_time >= 0.0 or planar_speed > 0.10
	# Until dedicated clips are imported, the calibrated Walk loop is the base
	# for shoulder running and crouched travel; the full-body modifier adds pose.
	if ground_motion.guard:
		return &"Walk" if moving else &""
	if (ground_motion.step_running or ground_motion.running) and actor.animation_player.has_animation(&"Run"):
		return &"Run"
	return &"Walk" if moving else &"Idle"

func capture_pose() -> void:
	# Called inside the final native modifier, while the completed pose exists.
	# No chain of modifier-completion signals and no restored-rest pose reads.
	for index in skeleton.get_bone_count(): bone_poses[index] = skeleton.get_bone_global_pose(index)
	rig.arms.sample_completed(skeleton,bone_poses)
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
