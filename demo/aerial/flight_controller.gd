extends RefCounted

# Behavioral references: DCS Su-27 for the airflow envelope, Elite Dangerous
# flight-assist-off for independent attitude/momentum, AC VI for directional bursts.
# Native Quaternion/Vector3 integration reuses the existing fixed-step controller.
const Spring = preload("res://aerial/flight_pose.gd").Spring
const DETENTS := [0.0,0.5,1.0,2.0,4.0]
const GRAVITY := 9.81
const ACTION_KEYS := {
	"flight_forward":[KEY_W],"flight_back":[KEY_S],
	"flight_left":[KEY_A],"flight_right":[KEY_D],
	"flight_pitch_down":[KEY_UP],"flight_pitch_up":[KEY_DOWN],
	"flight_roll_left":[KEY_LEFT],"flight_roll_right":[KEY_RIGHT],
	"flight_rise":[KEY_R],"flight_sink":[KEY_F],
	"flight_vector":[KEY_ALT],"flight_precision":[KEY_CTRL],
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
var pull_limit := 0.0
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
	for key in ["forward","back","left","right","yaw_left","yaw_right","thrust_up","thrust_down","burst","brake","pitch_up","pitch_down","roll_left","roll_right","rise","sink","vector","precision"]:
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
	pull_limit = 0.0
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
	for spring in [brake,accel,authority,envelope,command]:
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
	# Airflow controls lift, not the hover brake. A high-AoA pull must not
	# suddenly cancel momentum or level the bank in the middle of a turn.
	var speed_envelope := smoothstep(12,50,speed)
	var longitudinal := 1.0-smoothstep(0.55,1.35,absf(sideslip))
	flight_blend = envelope.step(Vector3(speed_envelope*longitudinal,0,0),delta,0.25).x
	var tilt := acos(clampf(basis.y.dot(Vector3.UP),-1.0,1.0))
	var hover_support := 1.0-smoothstep(deg_to_rad(15),deg_to_rad(60),tilt)
	vector_stabilization = 0.0 if uncaged else (1.0-flight_blend)*hover_support
	departure = smoothstep(20,60,speed)*(1.0-attached_flow)
	var planar := Vector3(float(raw.get("right",false))-float(raw.get("left",false)),0,float(raw.get("back",false))-float(raw.get("forward",false)))
	var vector_input := planar if raw.get("vector",false) else Vector3.ZERO
	# Constant bindings. Shift selects a burst without also rolling the suit.
	var rotation_input := Vector3.ZERO if raw.get("vector",false) or raw.get("burst",false) else Vector3(planar.z,0,-planar.x)
	rotation_input.y = float(raw.get("yaw_left",false))-float(raw.get("yaw_right",false))
	rotation_input.x += float(raw.get("pitch_up",false))-float(raw.get("pitch_down",false))
	rotation_input.z += float(raw.get("roll_left",false))-float(raw.get("roll_right",false))
	rotation_input = rotation_input.clamp(Vector3(-1,-1,-1),Vector3.ONE)
	# Hold the pilot axes through a maneuver. Gravity-relative tilt used to rotate
	# the controls themselves during a loop or bank. Native body axes do not.
	if not uncaged and absf(rotation_input.y) < 0.01 and absf(rotation_input.z) < 0.01 and absf(rotation_command.y) < 0.02 and absf(rotation_command.z) < 0.02: control_blend = flight_blend
	var control_frame := pilot_frame()
	var precision := 0.35 if raw.get("precision",false) else 1.0
	rotation_command = command.step(rotation_input*precision,delta,0.14)
	var pitch_rate := rotation_command.x*(1.15 if uncaged else lerpf(1.0,0.9,flight_blend))
	pull_limit = 0.0
	# DCS Su-27 reference: assisted AoA protection, with deliberate departure
	# available when uncaged or spreading the airbrake. This limits rates, not pose.
	if not uncaged and flight_blend > 0.35 and brake_amount < 0.2:
		var maximum := deg_to_rad(23.0)
		var allowed := maxf(0.0,(maximum-signf(pitch_rate)*angle_of_attack)/0.45)
		var limited := signf(pitch_rate)*minf(absf(pitch_rate),allowed)
		pull_limit = 1.0-absf(limited)/maxf(absf(pitch_rate),0.001) if absf(pitch_rate) > 0.01 else 0.0
		pitch_rate = limited
	var desired_rates := control_frame.x*pitch_rate+control_frame.z*rotation_command.z*1.4+control_frame.y*rotation_command.y*0.9
	if not uncaged:
		# Continuous body-lift assist; control bindings stay fixed at every speed.
		var horizontal := Vector3(velocity.x,0,velocity.z)
		var forward := -Basis(Vector3.UP,heading_yaw).z
		var forward_alignment := horizontal.normalized().dot(forward)
		if horizontal.length() > 8.0 and forward_alignment > 0.5: forward = horizontal.normalized()
		var upright := Basis.looking_at(forward,Vector3.UP).get_rotation_quaternion()
		var error := upright*attitude.inverse()
		if error.w < 0.0: error = -error
		var level := error.get_axis()*error.get_angle()*2.0
		# Shortest-arc nose alignment preserves bank and works through vertical
		# flight. It has no Euler heading singularity and never asks for wings level.
		var swing := Quaternion(basis.y.normalized(),velocity.normalized()) if speed > 0.1 else Quaternion.IDENTITY
		if swing.w < 0.0: swing = -swing
		var path := swing.get_axis()*swing.get_angle()*0.75
		var guide := maxf(flight_blend,smoothstep(deg_to_rad(20),deg_to_rad(70),tilt)*smoothstep(3,15,speed))
		var alignment := level*(1.0-guide)+path*guide
		if absf(rotation_input.x) > 0.05: alignment = alignment.slide(control_frame.x)
		if absf(rotation_input.z) > 0.05: alignment = alignment.slide(control_frame.z)
		if absf(rotation_input.y) > 0.05: alignment = alignment.slide(control_frame.y)
		desired_rates += alignment.limit_length(1.2)
	var old_rates := angular_velocity
	# Finite vernier torque servo; releasing input damps angular rates, not motion.
	angular_velocity = angular_velocity.move_toward(desired_rates.limit_length(1.8),delta*(3.2 if rotation_input.length() > 0.01 else 5.5))
	angular_acceleration = (angular_velocity-old_rates)/delta
	if angular_velocity.length() > 0.00001: attitude = (Quaternion(angular_velocity.normalized(),angular_velocity.length()*delta)*attitude).normalized()
	basis = Basis(attitude)
	var nose := basis.y
	heading_yaw = atan2(-nose.x,-nose.z) if Vector2(nose.x,nose.z).length() > 0.2 else (atan2(basis.z.x,basis.z.z) if flight_blend < 0.3 else heading_yaw)
	yaw_acceleration = (angular_velocity.y-yaw_rate)/delta
	yaw_rate = angular_velocity.y
	# A lifting-body approximation: finite q, attached-flow lift, induced/broadside
	# drag. ponytail: tune coefficients, replace with measured polars if available.
	var direction := velocity.normalized()
	var q := speed*speed*0.005
	var cl := clampf(angle_of_attack*3.2+0.32,-1.1,1.1)*attached_flow
	var lift := airframe.y.slide(direction).normalized()*q*cl if speed > 0.01 else Vector3.ZERO
	var broadside := absf(direction.dot(basis.z))
	var cd := 0.075+0.75*broadside*broadside+0.15*cl*cl+brake_amount*3.2
	aerodynamic_force = lift-direction*q*cd
	var thrust: float = DETENTS[detent]*GRAVITY
	required_force = basis.y*thrust
	translation_input = Vector3(vector_input.x,float(raw.get("rise",false))-float(raw.get("sink",false)),vector_input.z)
	if not uncaged:
		var horizontal_velocity := Vector3(velocity.x,0,velocity.z)
		var correction := (-horizontal_velocity*1.1*pow(vector_stabilization,3)).limit_length(16.0)
		var support := (GRAVITY-aerodynamic_force.y-required_force.y-velocity.y*1.8)*vector_stabilization if detent == 2 else -velocity.y*0.3*vector_stabilization
		# Hover trim fades with speed and deliberate body tilt. It must not cancel
		# a pilot-commanded launch into forward flight.
		var trim := Vector3(correction.x-required_force.x*vector_stabilization,support,correction.z-required_force.z*vector_stabilization)
		required_force += trim.limit_length(thrust*1.5)
	# Assisted vectoring uses chassis heading/gravity, never camera orientation.
	# Uncaged vectoring retains the body's full three-dimensional pilot frame.
	var translation_basis := control_frame if uncaged else Basis(Vector3.UP,heading_yaw)
	required_force += translation_basis*translation_input.limit_length(1.0)*GRAVITY*2.0*precision
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
