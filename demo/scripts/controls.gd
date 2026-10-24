extends CharacterBody3D

@export_range(0, 1) var sensitivity: float = 0.5;
@export_range(0, 90) var vertical_look_boundary: float = 80;
@export var invert_y_axis: bool = false;
@export var speed: float = 1.7
@export var run_speed: float = 2.8
@export var running_enabled: bool = true
@export_range(0.1, 20.0, 0.1) var acceleration: float = 4.5
@export_range(0.1, 20.0, 0.1) var braking: float = 5.5
@export var jump_power: float = 4.5
@export var gravity: float = 10.0
@export var camera_pivot_path: NodePath = NodePath("Camera3D")

@onready var camera: Node3D = get_node(camera_pivot_path);

var is_running := false
var movement_input_enabled := true


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
	if movement_input_enabled and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_power
	
	var input_dir := Input.get_vector("left", "right", "forward", "back") if movement_input_enabled else Vector2.ZERO
	var active_camera := get_viewport().get_camera_3d()
	var camera_basis := active_camera.global_basis if active_camera != null else camera.global_basis
	var forward := -camera_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var right := camera_basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = forward.cross(Vector3.UP)
	right = right.normalized()

	is_running = running_enabled and input_dir.length_squared() > 0.0001 and Input.is_action_pressed("run")
	var target_speed := run_speed if is_running else speed
	var target_velocity := (right * input_dir.x - forward * input_dir.y) * target_speed
	var planar_velocity := Vector3(velocity.x, 0.0, velocity.z)
	planar_velocity = planar_velocity.move_toward(
		target_velocity, (acceleration if input_dir.length_squared() > 0.0001 else braking) * delta
	)
	velocity.x = planar_velocity.x
	velocity.z = planar_velocity.z
	move_and_slide()


func _input(event):
	if (
			event is InputEventMouseMotion and
			Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	):
		rotate_y(-deg_to_rad(event.relative.x * sensitivity * 0.2))
		if invert_y_axis:
			camera.rotate_x(deg_to_rad(event.relative.y * sensitivity * 0.2))
		else:
			camera.rotate_x(-deg_to_rad(event.relative.y * sensitivity * 0.2))
		camera.rotation_degrees.x = clamp(
				camera.rotation_degrees.x,
				-vertical_look_boundary,
				vertical_look_boundary
		)
	if event.is_action("click"):
		if event.is_pressed() and not event.is_echo():
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
