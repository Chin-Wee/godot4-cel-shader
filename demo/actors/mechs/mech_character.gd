@tool
extends "res://scripts/controls.gd"

@export_range(0.2, 0.5, 0.001) var visual_scale: float = 0.3
@export var player_controlled: bool = false
@export var texture_override: Texture2D

const MECH_SHADER: Shader = preload("res://shaders/cel-shader-base.gdshader")
const WALK_SPEED_THRESHOLD := 0.1
const RUN_SPEED_RATIO := 0.7
const ROBOT_ALBEDO_SCALE := 0.85

@onready var visual_root: Node3D = $VisualRoot
@onready var actor_camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var animation_player: AnimationPlayer
var current_animation: StringName
var locomotion_stride_distances: Dictionary = {}


func _ready() -> void:
	# Risk of Rain 2 keeps locomotion on the physics body and skeletal clips on its visual child.
	set_physics_process(player_controlled and not Engine.is_editor_hint())
	set_process_input(player_controlled and not Engine.is_editor_hint())
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
	_update_locomotion_animation()


func _input(event: InputEvent) -> void:
	super._input(event)


func _prepare_animation_library() -> void:
	var source_library := animation_player.get_animation_library(&"")
	if source_library == null:
		return
	var local_library := source_library.duplicate(true) as AnimationLibrary
	for animation_name in [&"Idle", &"Walk", &"Run"]:
		if local_library.has_animation(animation_name):
			local_library.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	for animation_name in [&"Walk", &"Run"]:
		if local_library.has_animation(animation_name):
			locomotion_stride_distances[animation_name] = _measure_stride_distance(
				local_library.get_animation(animation_name)
			)
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
			material.set_shader_parameter("color_saturation", 0.65)
			material.set_shader_parameter("paint_variation", 0.0)
			material.set_shader_parameter("diffuse_ramp_mode", 0)
			material.set_shader_parameter("specular", Color(0.0, 0.0, 0.0, 0.0))
			material.set_shader_parameter("specular_strength", 0.0)
			mesh_instance.set_surface_override_material(surface, material)

	for child in node.get_children():
		_apply_robot_materials(child)


func _update_locomotion_animation() -> void:
	if animation_player == null:
		return
	var planar_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var planar_speed := planar_velocity.length()
	_update_visual_facing(planar_velocity, planar_speed)
	var desired_animation := _get_locomotion_animation(planar_speed, is_on_floor())
	animation_player.speed_scale = _get_locomotion_playback_speed(
		desired_animation, planar_speed
	)
	_play_animation(desired_animation)


func _get_locomotion_animation(planar_speed: float, grounded: bool) -> StringName:
	if not grounded:
		return &"Jump"
	if planar_speed <= WALK_SPEED_THRESHOLD:
		return &"Idle"
	return (
		&"Run"
		if planar_speed >= maxf(speed * RUN_SPEED_RATIO, WALK_SPEED_THRESHOLD)
		else &"Walk"
	)


func _measure_stride_distance(animation: Animation) -> float:
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


func _get_locomotion_playback_speed(animation_name: StringName, planar_speed: float) -> float:
	var animation := animation_player.get_animation(animation_name)
	var stride_distance := float(locomotion_stride_distances.get(animation_name, 0.0)) * visual_scale
	if animation == null or stride_distance <= 0.0 or planar_speed <= 0.0:
		return 1.0
	return animation.length * planar_speed / stride_distance


func _update_visual_facing(planar_velocity: Vector3, planar_speed: float) -> void:
	if planar_speed <= WALK_SPEED_THRESHOLD:
		visual_root.rotation.y = PI
		return
	var local_direction := global_transform.basis.inverse() * planar_velocity.normalized()
	visual_root.rotation.y = atan2(local_direction.x, local_direction.z)


func _play_animation(animation_name: StringName) -> void:
	if animation_player == null or not animation_player.has_animation(animation_name):
		return
	if current_animation == animation_name and animation_player.is_playing():
		return
	current_animation = animation_name
	animation_player.play(animation_name, 0.15)
