extends RefCounted

# Risk of Rain 2 reference: imported visual resources are local to each actor;
# the native body remains the sole movement owner.
const MECH_SHADER: Shader = preload("res://shaders/cel-shader-base.gdshader")

static func prepare_animations(animation_player: AnimationPlayer, animation_names: Dictionary, root_motion_bone: StringName) -> Dictionary:
	var locomotion_stride_distances := {}
	var jump_landing_cue_time := 0.0
	var source_library := animation_player.get_animation_library(&"")
	if source_library == null:
		return {"stride_distances":locomotion_stride_distances,"landing_cue":jump_landing_cue_time}
	var local_library := source_library.duplicate(true) as AnimationLibrary
	for canonical_name in animation_names:
		var source_name: StringName = animation_names[canonical_name]
		if local_library.has_animation(source_name) and canonical_name != source_name:
			local_library.add_animation(canonical_name, local_library.get_animation(source_name).duplicate(true))
	for animation_name in [&"Idle", &"Walk", &"Run", &"Fall"]:
		if local_library.has_animation(animation_name):
			local_library.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	for animation_name in [&"Walk", &"Run"]:
		if local_library.has_animation(animation_name):
			locomotion_stride_distances[animation_name] = measure_stride_distance(
				local_library.get_animation(animation_name),root_motion_bone
			)
	if local_library.has_animation(&"Jump"):
		jump_landing_cue_time = measure_jump_landing_cue_time(
			local_library.get_animation(&"Jump")
		)
	if not root_motion_bone.is_empty():
		var rest_position := Vector3.ZERO
		var idle := local_library.get_animation(&"Idle")
		var root_track := find_position_track(idle, root_motion_bone)
		if root_track >= 0:
			rest_position = idle.track_get_key_value(root_track, 0)
		for animation_name in [&"Idle", &"Walk", &"Run", &"Jump", &"Fall", &"Land"]:
			if not local_library.has_animation(animation_name):
				continue
			var animation := local_library.get_animation(animation_name)
			root_track = find_position_track(animation, root_motion_bone)
			if root_track >= 0:
				for key_index in animation.track_get_key_count(root_track):
					animation.track_set_key_value(root_track, key_index, rest_position)
			if animation_name in [&"Idle", &"Jump", &"Land"]:
				animation.loop_mode = Animation.LOOP_NONE
	animation_player.remove_animation_library(&"")
	animation_player.add_animation_library(&"", local_library)
	return {"stride_distances":locomotion_stride_distances,"landing_cue":jump_landing_cue_time}

static func prepare_materials(node: Node, texture_override: Texture2D = null) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var imported_material := mesh_instance.get_active_material(surface)
			if imported_material == null and texture_override == null:
				continue
			var source_color := Color.WHITE
			var source_texture := texture_override
			if imported_material is BaseMaterial3D:
				var base_material := imported_material as BaseMaterial3D
				source_color = base_material.albedo_color
				if base_material.emission_enabled and source_color.get_luminance() < 0.01:
					# Keep the imported green lights readable as matte painted accents.
					source_color = base_material.emission.clamp(Color.BLACK, Color.WHITE)
				if source_texture == null:
					source_texture = base_material.albedo_texture
			var material := ShaderMaterial.new()
			material.shader = MECH_SHADER
			if source_texture != null:
				material.set_shader_parameter("base_texture", source_texture)
			material.set_shader_parameter("color", source_color)
			material.set_shader_parameter("color_saturation", 0.35)
			material.set_shader_parameter("paint_variation", 0.06)
			material.set_shader_parameter("diffuse_ramp_mode", 0)
			material.set_shader_parameter("specular", Color(0.0, 0.0, 0.0, 0.0))
			material.set_shader_parameter("specular_strength", 0.0)
			mesh_instance.set_surface_override_material(surface, material)

	for child in node.get_children():
		prepare_materials(child,texture_override)

static func find_position_track(animation: Animation, bone: StringName) -> int:
	for index in animation.get_track_count():
		if animation.track_get_type(index) == Animation.TYPE_POSITION_3D and str(animation.track_get_path(index)).ends_with(":" + str(bone)):
			return index
	return -1

static func measure_stride_distance(animation: Animation, root_motion_bone: StringName) -> float:
	if not root_motion_bone.is_empty():
		var root_track := find_position_track(animation, root_motion_bone)
		if root_track >= 0:
			var start: Vector3 = animation.track_get_key_value(root_track, 0)
			var end: Vector3 = animation.track_get_key_value(root_track, animation.track_get_key_count(root_track) - 1)
			return Vector2(end.x - start.x, end.z - start.z).length()
	for track_index in animation.get_track_count():
		if (
			animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D
			or not str(animation.track_get_path(track_index)).ends_with(":Foot.L")
		):
			continue
		var minimum_z := INF
		var maximum_z := -INF
		for key_index in animation.track_get_key_count(track_index):
			var foot_position: Vector3 = animation.track_get_key_value(track_index, key_index)
			minimum_z = minf(minimum_z, foot_position.z)
			maximum_z = maxf(maximum_z, foot_position.z)
		return maximum_z - minimum_z
	return 0.0

static func measure_jump_landing_cue_time(animation: Animation) -> float:
	var body_track := -1
	for track_index in animation.get_track_count():
		if (
			animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D
			and str(animation.track_get_path(track_index)).ends_with(":Body")
		):
			body_track = track_index
			break
	if body_track < 0:
		return 0.0

	var apex_time := 0.0
	var apex_y := -INF
	for key_index in animation.track_get_key_count(body_track):
		var body_position: Vector3 = animation.track_get_key_value(body_track, key_index)
		if body_position.y > apex_y:
			apex_y = body_position.y
			apex_time = animation.track_get_key_time(body_track, key_index)

	var landing_cue_time := 0.0
	var landing_cue_y := INF
	for key_index in animation.track_get_key_count(body_track):
		var key_time := animation.track_get_key_time(body_track, key_index)
		if key_time <= apex_time:
			continue
		var body_position: Vector3 = animation.track_get_key_value(body_track, key_index)
		if body_position.y < landing_cue_y:
			landing_cue_y = body_position.y
			landing_cue_time = key_time
	return landing_cue_time
