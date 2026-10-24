@tool
extends "res://scripts/controls.gd"

@export_range(0.01, 1.0, 0.001) var visual_scale: float = 0.3
@export var player_controlled: bool = false
@export var texture_override: Texture2D
@export var animation_names: Dictionary = {}
@export var root_motion_bone: StringName = &""

const MECH_SHADER: Shader = preload("res://shaders/cel-shader-base.gdshader")
const WALK_SPEED_THRESHOLD := 0.1
const VISUAL_TURN_SPEED := 4.5
const LOCOMOTION_BLEND_TIME := 0.6
const NON_JUMP_ANIMATION_RATE_SCALE := 0.7
const ROBOT_ALBEDO_SCALE := 1.0

@onready var visual_root: Node3D = $VisualRoot
@onready var actor_camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var animation_player: AnimationPlayer
var current_animation: StringName
var locomotion_stride_distances: Dictionary = {}
var jump_landing_cue_time := 0.0
var _was_grounded := false


func _ready() -> void:
	# Risk of Rain 2 keeps locomotion on the physics body and skeletal clips on its visual child.
	set_physics_process(player_controlled and not Engine.is_editor_hint())
	set_process_input(player_controlled and not Engine.is_editor_hint())
	movement_input_enabled = player_controlled
	visual_root.scale = Vector3.ONE * visual_scale
	# The mech pack's eye meshes face +Z; the controller and camera face -Z.
	visual_root.rotation.y = PI
	if visual_root.get_child_count() == 0:
		push_error("Add an imported mech scene under VisualRoot.")
		return

	var model := visual_root.get_child(0)
	_apply_robot_materials(model)
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		push_error("The mech model scene must contain an AnimationPlayer.")
		return
	_prepare_animation_library()

	actor_camera.current = player_controlled and not Engine.is_editor_hint()
	if Engine.is_editor_hint():
		return
	if player_controlled:
		super._ready()
	_play_animation("Idle")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_locomotion_animation(delta)


func _input(event: InputEvent) -> void:
	if player_controlled:
		super._input(event)


func set_player_controlled(enabled: bool) -> void:
	# GTA V-style switching: one input owner and camera; both bodies keep simulating.
	player_controlled = enabled
	movement_input_enabled = enabled
	set_physics_process(not Engine.is_editor_hint())
	set_process_input(enabled and not Engine.is_editor_hint())
	if enabled:
		actor_camera.make_current()


func _prepare_animation_library() -> void:
	var source_library := animation_player.get_animation_library(&"")
	if source_library == null:
		return
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
			locomotion_stride_distances[animation_name] = _measure_stride_distance(
				local_library.get_animation(animation_name)
			)
	if local_library.has_animation(&"Jump"):
		jump_landing_cue_time = _measure_jump_landing_cue_time(
			local_library.get_animation(&"Jump")
		)
	if not root_motion_bone.is_empty():
		var rest_position := Vector3.ZERO
		var idle := local_library.get_animation(&"Idle")
		var root_track := _find_position_track(idle, root_motion_bone)
		if root_track >= 0:
			rest_position = idle.track_get_key_value(root_track, 0)
		for animation_name in [&"Idle", &"Walk", &"Run", &"Jump", &"Fall", &"Land"]:
			if not local_library.has_animation(animation_name):
				continue
			var animation := local_library.get_animation(animation_name)
			root_track = _find_position_track(animation, root_motion_bone)
			if root_track >= 0:
				for key_index in animation.track_get_key_count(root_track):
					animation.track_set_key_value(root_track, key_index, rest_position)
			if animation_name in [&"Idle", &"Jump", &"Land"]:
				animation.loop_mode = Animation.LOOP_NONE
	animation_player.remove_animation_library(&"")
	animation_player.add_animation_library(&"", local_library)


func _apply_robot_materials(node: Node) -> void:
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
			var robot_color := Color(
					source_color.r * ROBOT_ALBEDO_SCALE,
					source_color.g * ROBOT_ALBEDO_SCALE,
					source_color.b * ROBOT_ALBEDO_SCALE,
					source_color.a
			)
			var material := ShaderMaterial.new()
			material.shader = MECH_SHADER
			if source_texture != null:
				material.set_shader_parameter("base_texture", source_texture)
			material.set_shader_parameter("color", robot_color)
			material.set_shader_parameter("color_saturation", 0.35)
			material.set_shader_parameter("paint_variation", 0.06)
			material.set_shader_parameter("diffuse_ramp_mode", 0)
			material.set_shader_parameter("specular", Color(0.0, 0.0, 0.0, 0.0))
			material.set_shader_parameter("specular_strength", 0.0)
			mesh_instance.set_surface_override_material(surface, material)

	for child in node.get_children():
		_apply_robot_materials(child)


func _update_locomotion_animation(delta: float = 1.0 / 60.0) -> void:
	if animation_player == null:
		return
	var grounded := is_on_floor()
	var just_took_off := _was_grounded and not grounded
	var planar_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var planar_speed := planar_velocity.length()
	_update_visual_facing(planar_velocity, planar_speed, delta)
	if animation_player.has_animation(&"Fall") and animation_player.has_animation(&"Land"):
		var desired := _get_separate_air_animation(planar_speed, grounded, just_took_off)
		animation_player.speed_scale = _get_locomotion_playback_speed(desired, planar_speed) * (
			1.0 if desired == &"Jump" else NON_JUMP_ANIMATION_RATE_SCALE
		)
		_play_animation(desired, just_took_off or (grounded and not _was_grounded))
		_was_grounded = grounded
		return
	var jump_recovery_active := (
		current_animation == &"Jump"
		and animation_player.is_playing()
		and grounded
		and not just_took_off
	)
	var desired_animation := _get_locomotion_animation(
		planar_speed, grounded, jump_recovery_active, is_running
	)
	var animation_rate_scale := (
		1.0 if desired_animation == &"Jump" else NON_JUMP_ANIMATION_RATE_SCALE
	)
	animation_player.speed_scale = (
		_get_locomotion_playback_speed(desired_animation, planar_speed) * animation_rate_scale
	)
	_play_animation(desired_animation, just_took_off)
	_was_grounded = grounded


func _get_locomotion_animation(
	planar_speed: float, grounded: bool, jump_recovery_active := false, run_requested := false
) -> StringName:
	if not grounded or jump_recovery_active:
		return &"Jump"
	if planar_speed <= WALK_SPEED_THRESHOLD:
		return &"Idle"
	return &"Run" if run_requested and running_enabled else &"Walk"


func _get_separate_air_animation(planar_speed: float, grounded: bool, just_took_off: bool) -> StringName:
	if not grounded:
		return &"Jump" if velocity.y > 0.0 and (just_took_off or current_animation == &"Jump") else &"Fall"
	if not _was_grounded:
		return &"Land"
	if current_animation == &"Land" and animation_player.is_playing():
		return &"Land"
	return &"Walk" if planar_speed > WALK_SPEED_THRESHOLD else &"Idle"


func _find_position_track(animation: Animation, bone: StringName) -> int:
	for index in animation.get_track_count():
		if animation.track_get_type(index) == Animation.TYPE_POSITION_3D and str(animation.track_get_path(index)).ends_with(":" + str(bone)):
			return index
	return -1


func _measure_stride_distance(animation: Animation) -> float:
	if not root_motion_bone.is_empty():
		var root_track := _find_position_track(animation, root_motion_bone)
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


func _measure_jump_landing_cue_time(animation: Animation) -> float:
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


func _get_locomotion_playback_speed(animation_name: StringName, planar_speed: float) -> float:
	var animation := animation_player.get_animation(animation_name)
	if animation_name == &"Jump":
		if not root_motion_bone.is_empty() and animation_player.has_animation(&"Fall"):
			var ascent_time := jump_power / gravity if gravity > 0.0 else 0.0
			return animation.length / ascent_time if ascent_time > 0.0 else 1.0
		# Risk of Rain 2-style body animation stays on the visual child. This aligns its
		# landing compression cue with a same-height ballistic jump's predicted airtime.
		var predicted_airtime := 2.0 * jump_power / gravity if gravity > 0.0 else 0.0
		if jump_landing_cue_time > 0.0 and predicted_airtime > 0.0:
			return jump_landing_cue_time / predicted_airtime
		return 1.0
	var stride_distance := float(locomotion_stride_distances.get(animation_name, 0.0)) * visual_scale
	if animation == null or stride_distance <= 0.0 or planar_speed <= 0.0:
		return 1.0
	return animation.length * planar_speed / stride_distance


func _update_visual_facing(
	planar_velocity: Vector3, planar_speed: float, delta: float = 1.0 / 60.0
) -> void:
	if planar_speed <= WALK_SPEED_THRESHOLD:
		return
	var local_direction := global_transform.basis.inverse() * planar_velocity.normalized()
	var target_rotation := atan2(local_direction.x, local_direction.z)
	visual_root.rotation.y = lerp_angle(
		visual_root.rotation.y, target_rotation, 1.0 - exp(-VISUAL_TURN_SPEED * delta)
	)


func _play_animation(animation_name: StringName, restart := false) -> void:
	if animation_player == null or not animation_player.has_animation(animation_name):
		return
	if current_animation == animation_name:
		if not restart:
			return
		animation_player.seek(0.0, true)
	else:
		current_animation = animation_name
	animation_player.play(animation_name, LOCOMOTION_BLEND_TIME)
