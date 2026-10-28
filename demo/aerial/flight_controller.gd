extends RefCounted

# Behavioral references: DCS Su-27 for the airflow envelope, Elite Dangerous
# flight-assist-off for independent attitude/momentum, AC VI for directional bursts.
# Native Quaternion/Vector3 integration reuses the existing fixed-step controller.
const Spring = preload("res://aerial/flight_pose.gd").Spring
const DETENTS := [0.0,0.5,1.0,2.0,4.0]
const GRAVITY := 9.81
const HIGH_SPEED_DRAG := 0.28
const COMBAT_AERO_THRESHOLD := 0.5
const ACTION_KEYS := {
	"flight_forward":[KEY_W],"flight_back":[KEY_S],
	"flight_left":[KEY_A],"flight_right":[KEY_D],
	"flight_rise":[KEY_R],"flight_sink":[KEY_F],
	"flight_precision":[KEY_CTRL],
	"flight_yaw_left":[KEY_Q],"flight_yaw_right":[KEY_E],
	"flight_thrust_up":[KEY_SPACE],"flight_thrust_down":[KEY_C],
	"flight_burst":[KEY_SHIFT],"flight_brake":[KEY_X],
}
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var acceleration := Vector3.ZERO
var attitude := Quaternion.IDENTITY
var angular_velocity := Vector3.ZERO
var angular_acceleration := Vector3.ZERO
var aim_direction := Vector3.FORWARD
var aim_point := Vector3(INF,INF,INF)
var weapon_aim := Vector3.FORWARD
var gaze_target := Vector3.ZERO
var local_velocity := Vector3.ZERO
var local_acceleration := Vector3.ZERO
var local_airflow := Vector3.ZERO
var required_force := Vector3.UP*GRAVITY
var aerodynamic_force := Vector3.ZERO
var angle_of_attack := 0.0
var sideslip := 0.0
var attached_flow := 0.0
var aero_authority := 0.0
var flight_blend := 0.0
var control_blend := 0.0
var high_speed_drag := 0.0
var aiming := false
var combat_attitude := false
var combat_bindings := false
var translation_input := Vector3.ZERO
var rotation_command := Vector3.ZERO
var vector_stabilization := 1.0
var departure := 0.0
var uncaged := false
var detent := 2
var brake_amount := 0.0
var boost_amount := 0.0
var burst_remaining := 0.0
var burst_cooldown := 0.0
var burst_direction := Vector3.ZERO
var time_to_impact := INF
var recovery_request := 0.0
var g_load := 1.0
var clock := 0.0
var heading_yaw := 0.0
var yaw_rate := 0.0
var yaw_acceleration := 0.0
# Control/pose units are meters; the giant display model travels at this scale.
var distance_scale := 10.0
var model_scale := 50.0
var previous := {}
var brake := Spring.new()
var accel := Spring.new()
var authority := Spring.new()
var envelope := Spring.new()
var command := Spring.new()
var move_command := Spring.new()

static func install_input_actions() -> void:
	for action in ACTION_KEYS:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		for key in ACTION_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action,event)

static func read_input() -> Dictionary:
	var result := {"uncage":Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)}
	for key in ["forward","back","left","right","yaw_left","yaw_right","thrust_up","thrust_down","burst","brake","rise","sink","precision"]:
		result[key] = Input.is_action_pressed("flight_"+key)
	return result

func reset(origin: Vector3, yaw_angle := 0.0) -> void:
	position = origin
	velocity = Vector3.ZERO
	acceleration = Vector3.ZERO
	attitude = Quaternion(Vector3.UP,yaw_angle)
	angular_velocity = Vector3.ZERO
	angular_acceleration = Vector3.ZERO
	heading_yaw = yaw_angle
	yaw_rate = 0.0
	yaw_acceleration = 0.0
	angle_of_attack = 0.0
	sideslip = 0.0
	attached_flow = 0.0
	recovery_request = 0.0
	g_load = 1.0
	burst_direction = Vector3.ZERO
	aim_point = Vector3(INF,INF,INF)
	weapon_aim = -Basis(attitude).z
	aim_direction = -Basis(attitude).z
	gaze_target = position+aim_direction*4500.0
	local_velocity = Vector3.ZERO
	local_acceleration = Vector3.ZERO
	local_airflow = Vector3.ZERO
	required_force = Vector3.UP*GRAVITY
	aerodynamic_force = Vector3.ZERO
	aero_authority = 0.0
	flight_blend = 0.0
	control_blend = 0.0
	high_speed_drag = 0.0
	aiming = false
	combat_attitude = false
	combat_bindings = false
	translation_input = Vector3.ZERO
	rotation_command = Vector3.ZERO
	vector_stabilization = 1.0
	departure = 0.0
	uncaged = false
	detent = 2
	brake_amount = 0.0
	boost_amount = 0.0
	burst_remaining = 0.0
	burst_cooldown = 0.0
	clock = 0.0
	time_to_impact = INF
	previous.clear()
	for spring in [brake,accel,authority,envelope,command,move_command]:
		spring.value = Vector3.ZERO
		spring.velocity = Vector3.ZERO

func advance(delta: float, controls: Dictionary, _camera_yaw := 0.0) -> void:
	# Edges are sampled once per display update, never once per integration step.
	_read_edges(controls)
	var remaining := minf(delta,0.25)
	while remaining > 0.000001:
		var step := minf(remaining,1.0/120.0)
		_step(step,controls)
		remaining -= step

func _read_edges(raw: Dictionary) -> void:
	uncaged = bool(raw.get("uncage",false))
	var held_direction := false
	for key in ["forward","back","left","right"]:
		if raw.get(key,false) and previous.get(key,false): held_direction = true
	var was_combat := combat_bindings
	# Capture input meaning through a flow dip, while the authority gate remains
	# strict. Captured keys go neutral below 50%, never straight into translation.
	combat_attitude = bool(raw.get("brake",false)) and aero_authority > COMBAT_AERO_THRESHOLD
	combat_bindings = combat_attitude or bool(raw.get("brake",false)) and combat_bindings and held_direction
	if combat_bindings and not was_combat: control_blend = 1.0
	for key in ["thrust_up","thrust_down"]:
		if raw.get(key,false) and not previous.get(key,false): detent = clampi(detent+(1 if key == "thrust_up" else -1),0,DETENTS.size()-1)
	var directional_edge := false
	for key in ["forward","back","left","right"]:
		if raw.get(key,false) and not previous.get(key,false): directional_edge = true
	if raw.get("burst",false) and (not previous.get("burst",false) or directional_edge) and burst_cooldown <= 0.0:
		var direction := Vector3(float(raw.get("right",false))-float(raw.get("left",false)),0,float(raw.get("back",false))-float(raw.get("forward",false)))
		if not direction.is_zero_approx():
			burst_direction = pilot_frame()*direction.normalized()
			burst_remaining = 0.20
			burst_cooldown = 0.50
	previous = raw.duplicate()

func _step(delta: float, raw: Dictionary) -> void:
	clock += delta
	burst_remaining = maxf(0.0,burst_remaining-delta)
	burst_cooldown = maxf(0.0,burst_cooldown-delta)
	boost_amount = 1.0 if burst_remaining > 0.0 else 0.0
	brake_amount = brake.step(Vector3(float(raw.get("brake",false)),0,0),delta,0.12).x
	var basis := Basis(attitude)
	var airframe := basis*Basis(Vector3.RIGHT,PI/2.0) # head is the flight nose.
	var speed := velocity.length()
	var air_velocity := airframe.inverse()*velocity
	angle_of_attack = atan2(-air_velocity.y,-air_velocity.z) if speed > 0.1 else 0.0
	sideslip = atan2(air_velocity.x,maxf(0.01,absf(air_velocity.z)))
	attached_flow = (1.0-smoothstep(deg_to_rad(15),deg_to_rad(55),absf(angle_of_attack)))*(1.0-smoothstep(0.3,1.2,absf(sideslip)))
	var lift_orientation := 1.0-absf(velocity.normalized().dot(airframe.y)) if speed > 0.1 else 0.0
	aero_authority = authority.step(Vector3(smoothstep(20,70,speed)*attached_flow*lift_orientation,0,0),delta,0.16).x
	combat_attitude = bool(raw.get("brake",false)) and aero_authority > COMBAT_AERO_THRESHOLD
	if combat_attitude and not combat_bindings:
		combat_bindings = true
		control_blend = 1.0
	# Airflow controls lift, not the hover brake. A high-AoA pull must not
	# suddenly cancel momentum or level the bank in the middle of a turn.
	var speed_envelope := smoothstep(12,50,speed)
	var longitudinal := 1.0-smoothstep(0.55,1.35,absf(sideslip))
	flight_blend = envelope.step(Vector3(speed_envelope*longitudinal,0,0),delta,0.25).x
	var tilt := acos(clampf(basis.y.dot(Vector3.UP),-1.0,1.0))
	var hover_support := 1.0-smoothstep(deg_to_rad(15),deg_to_rad(60),tilt)
	vector_stabilization = 0.0 if uncaged or combat_bindings else (1.0-flight_blend)*hover_support
	departure = smoothstep(20,60,speed)*(1.0-attached_flow)
	var planar := Vector3(float(raw.get("right",false))-float(raw.get("left",false)),0,float(raw.get("back",false))-float(raw.get("forward",false)))
	var precision := 0.35 if raw.get("precision",false) else 1.0
	var vector_planar := Vector3.ZERO if combat_bindings else planar
	var move := move_command.step(vector_planar.limit_length(1.0)*precision,delta,0.20)
	if combat_bindings: move = Vector3.ZERO
	var rotation_input := Vector3.ZERO
	if combat_attitude and not raw.get("burst",false): rotation_input = Vector3(planar.z,0,-planar.x)
	var yaw_input := float(raw.get("yaw_left",false))-float(raw.get("yaw_right",false))
	rotation_command = command.step(Vector3(rotation_input.x,yaw_input,rotation_input.z)*precision,delta,0.14)
	var requested_yaw_rate := rotation_command.y*lerpf(0.9,0.32,flight_blend)
	heading_yaw = wrapf(heading_yaw+requested_yaw_rate*delta,-PI,PI)
	if not combat_bindings: control_blend = flight_blend
	var heading := Basis(Vector3.UP,heading_yaw)
	var desired_rates := Vector3.UP*requested_yaw_rate
	if combat_attitude:
		# DCS-style body-axis pitch/roll; the mouse remains independent aim/look.
		var frame := pilot_frame()
		desired_rates += frame.x*rotation_command.x+frame.z*rotation_command.z*1.25
	if not uncaged and not combat_bindings:
		# Elite Dangerous-style assisted translation, with automatic suit streamlining.
		# X plus sufficient aero explicitly overrides WASD with body attitude.
		var forward_speed := maxf(0.0,velocity.dot(-heading.z))
		var cruise := smoothstep(8,45,forward_speed)
		var target := (heading.get_rotation_quaternion()*Quaternion(Vector3.RIGHT,-PI/2.0*cruise)).normalized()
		var error := target*attitude.inverse()
		if error.w < 0.0: error = -error
		desired_rates += (error.get_axis()*error.get_angle()*lerpf(2.4,1.3,flight_blend)).limit_length(1.2)
	var old_rates := angular_velocity
	# Finite vernier torque servo; releasing input damps angular rates, not motion.
	angular_velocity = angular_velocity.move_toward(desired_rates.limit_length(1.8),delta*4.5)
	angular_acceleration = (angular_velocity-old_rates)/delta
	if angular_velocity.length() > 0.00001: attitude = (Quaternion(angular_velocity.normalized(),angular_velocity.length()*delta)*attitude).normalized()
	basis = Basis(attitude)
	yaw_acceleration = (angular_velocity.y-yaw_rate)/delta
	yaw_rate = angular_velocity.y
	# A lifting-body approximation: finite q, attached-flow lift, induced/broadside
	# drag. ponytail: tune coefficients, replace with measured polars if available.
	var direction := velocity.normalized()
	var q := speed*speed*0.005
	var cl := clampf(angle_of_attack*3.2+0.32,-1.1,1.1)*attached_flow
	var lift := airframe.y.slide(direction).normalized()*q*cl if speed > 0.01 else Vector3.ZERO
	var broadside := absf(direction.dot(basis.z))
	high_speed_drag = smoothstep(35,100,speed)
	var cd := 0.075+HIGH_SPEED_DRAG*high_speed_drag+0.75*broadside*broadside+0.15*cl*cl+brake_amount*3.2
	aerodynamic_force = lift-direction*q*cd
	var thrust: float = DETENTS[detent]*GRAVITY
	required_force = basis.y*thrust
	translation_input = Vector3(move.x,float(raw.get("rise",false))-float(raw.get("sink",false)),move.z)
	var translation_basis := heading
	if not uncaged and not combat_bindings:
		var target_speed := lerpf(24.0,65.0,flight_blend)
		var requested_velocity := translation_basis*move*target_speed
		var horizontal_velocity := Vector3(velocity.x,0,velocity.z)
		var correction := (requested_velocity-horizontal_velocity)*1.8
		if vector_planar.is_zero_approx(): correction *= pow(vector_stabilization,3)
		correction = correction.limit_length(16.0)
		var support := (GRAVITY-aerodynamic_force.y-required_force.y-velocity.y*1.8)*vector_stabilization if detent == 2 else -velocity.y*0.3*vector_stabilization
		var trim := Vector3(correction.x-required_force.x*vector_stabilization,support,correction.z-required_force.z*vector_stabilization)
		required_force += trim.limit_length(maxf(thrust*1.5,GRAVITY))
	else:
		required_force += translation_basis*move*GRAVITY*2.0
	required_force += Vector3.UP*translation_input.y*GRAVITY*2.0*precision
	recovery_request = 1.0-smoothstep(0.6,1.3,time_to_impact)
	if not is_finite(time_to_impact): recovery_request = 0.0
	var escape := recovery_request*(0.25 if uncaged else 4.0)*GRAVITY
	required_force += Vector3.UP*escape
	if boost_amount > 0.0: required_force += burst_direction*GRAVITY*7.0
	var old_velocity := velocity
	velocity += (required_force+aerodynamic_force+Vector3.DOWN*GRAVITY)*delta
	position += velocity*delta*distance_scale
	acceleration = (velocity-old_velocity)/delta
	local_velocity = basis.inverse()*velocity
	local_acceleration = accel.step(basis.inverse()*acceleration,delta,0.12)
	local_airflow = -local_velocity
	g_load = (required_force+aerodynamic_force).length()/GRAVITY
	gaze_target = aim_point if aim_point.is_finite() else position+aim_direction*4500.0
	weapon_aim = limit_aim_direction(aim_direction)

func aim_frame() -> Basis:
	var body := Basis(attitude)
	# Resolve pitch separately from bank: rolling a standing suit must not
	# turn its forward firing arc into an overhead firing arc.
	var projection := Vector2(body.y.y,body.z.y)
	var blend := control_blend if projection.length() < 0.15 else atan2(absf(projection.y),absf(projection.x))/(PI/2.0)
	return body*Basis(Vector3.RIGHT,PI/2.0*blend)

func pilot_frame() -> Basis:
	return Basis(attitude)*Basis(Vector3.RIGHT,PI/2.0*control_blend)

func limit_aim_direction(direction: Vector3) -> Vector3:
	var frame := aim_frame()
	var local := frame.inverse()*direction
	var yaw := clampf(atan2(-local.x,-local.z),-deg_to_rad(85),deg_to_rad(85))
	var pitch := clampf(atan2(local.y,Vector2(local.x,local.z).length()),-deg_to_rad(70),deg_to_rad(70))
	return (frame*Vector3(-sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))).normalized()
