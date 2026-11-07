extends Camera3D

# Armored Core VI camera behavior, composed from the installed Phantom Camera.
# The scene calls update_view once before camera-dependent weather/post effects.
const AerialMech = preload("res://aerial/aerial_mech.gd")
var subject: AerialMech
var follow_enabled := true
var input_paused := false
var yaw := 0.45
var pitch := 0.22
var distance := 3.8
var camera_target: Node3D
var phantom_camera: PhantomCamera3D
var camera_host: PhantomCameraHost
var focus_target: Node3D
var focus_targets: Array[Node3D] = []
var focus_index := -1

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_target = Node3D.new()
	camera_target.name = "CameraTarget"
	camera_target.top_level = true
	add_child(camera_target)
	phantom_camera = PhantomCamera3D.new()
	phantom_camera.name = "FlightPhantomCamera"
	phantom_camera.follow_mode = PhantomCamera3D.FollowMode.SIMPLE
	phantom_camera.follow_target = camera_target
	phantom_camera.follow_damping = true
	phantom_camera.follow_damping_value = Vector3.ONE*0.14
	phantom_camera.look_at_mode = PhantomCamera3D.LookAtMode.SIMPLE
	phantom_camera.look_at_target = camera_target
	phantom_camera.tween_on_load = false
	phantom_camera.top_level = true
	add_child(phantom_camera)
	camera_host = PhantomCameraHost.new()
	camera_host.name = "PhantomCameraHost"
	# Update once, after the render target and before camera-dependent weather/VFX.
	camera_host.interpolation_mode = PhantomCameraHost.InterpolationMode.MANUAL
	add_child(camera_host)
	camera_host.refresh_pcam_list_priorty()

func reset_view() -> void:
	yaw = atan2(-subject.global_basis.z.x, -subject.global_basis.z.z) + PI
	pitch = 0.08
	distance = 3.8
	update_view(0.0)

func update_view(delta: float) -> void:
	if not follow_enabled or not is_instance_valid(subject): return
	# Read the same transform the renderer uses, never the latest physics tick.
	var hero_position: Vector3 = subject.get_global_transform_interpolated().origin
	var center: Vector3 = hero_position+Vector3.UP*subject.display_scale*0.35
	var snap: bool = delta <= 0.0 or camera_target.global_position.distance_to(center) > subject.display_scale*20.0
	camera_target.global_position = center
	var lag: Vector3 = (-subject.controller.acceleration*0.016*subject.display_scale).limit_length(0.45*subject.display_scale)
	var aim: Vector3 = hero_position+look_direction()*4500.0
	if is_instance_valid(focus_target):
		aim = focus_target.get_global_transform_interpolated().origin if focus_target.is_physics_interpolated_and_enabled() else focus_target.global_position
		var focus_direction := (aim-center).normalized()
		yaw = atan2(-focus_direction.x,-focus_direction.z)
		pitch = -asin(clampf(focus_direction.y,-1,1))
	var offset: Vector3 = Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance*subject.display_scale
	# Compensate damping's constant-velocity lag so fast climbs stay framed.
	var lead: Vector3 = subject.linear_velocity*0.14 if not snap else Vector3.ZERO
	phantom_camera.follow_offset = offset+Basis(Vector3.UP,yaw).x*subject.display_scale*0.4+lead+lag
	phantom_camera.look_at_offset = aim-center
	if snap: phantom_camera.teleport_position()
	# The addon's SmoothDamp divides by delta when snapping; bypass it at zero.
	phantom_camera.follow_damping = not snap
	camera_host.process(delta)
	phantom_camera.follow_damping = true

func look_direction() -> Vector3:
	if is_instance_valid(focus_target): return (focus_target.global_position-subject.global_position).normalized()
	return -Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))

func focus_next() -> void:
	if focus_targets.is_empty(): return
	focus_index = (focus_index+1)%focus_targets.size()
	focus_target = focus_targets[focus_index]

func orbit(relative: Vector2) -> void:
	# Camera remains gravity-upright even during inverted/body-independent flight.
	focus_target = null
	focus_index = -1
	yaw -= relative.x*0.004
	pitch = clampf(pitch+relative.y*0.004,-1.45,1.45)
	if input_paused: update_view(0.0)

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE: focus_next()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance+(-0.3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.3),1.8,9.5)
			if input_paused: update_view(0.0)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: orbit(event.relative)
	if event is InputEventScreenDrag: orbit(event.relative)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_HOME: reset_view()
			KEY_TAB: focus_next()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
