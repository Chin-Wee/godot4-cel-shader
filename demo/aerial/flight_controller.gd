extends RefCounted

# Behavioral references: DCS Su-27 for the airflow envelope, Elite Dangerous
# flight-assist-off for independent attitude/momentum, AC VI for directional bursts.
# Native Quaternion/Vector3 integration reuses the existing fixed-step controller.
const Spring = preload("res://aerial/flight_pose.gd").Spring
const DETENTS := [0.0,0.5,1.0,2.0,4.0]
const GRAVITY := 9.81
const ACTION_KEYS := {
	"flight_forward":[KEY_W,KEY_UP],"flight_back":[KEY_S,KEY_DOWN],
	"flight_left":[KEY_A,KEY_LEFT],"flight_right":[KEY_D,KEY_RIGHT],
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
var aim_chassis_follow := false
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
var latches := {} # true = attitude, false = vector, absent = released.
var previous := {}
var attitude_bindings := false
var brake := Spring.new()
var accel := Spring.new()
var authority := Spring.new()

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
	for key in ["forward","back","left","right","yaw_left","yaw_right","thrust_up","thrust_down","burst","brake"]:
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
	aim_chassis_follow = false
	aim_direction = -Basis(attitude).z
	gaze_target = position+aim_direction*4500.0
	local_velocity = Vector3.ZERO
	local_acceleration = Vector3.ZERO
	local_airflow = Vector3.ZERO
	required_force = Vector3.UP*GRAVITY
	aerodynamic_force = Vector3.ZERO
	aero_authority = 0.0
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
	latches.clear()
	previous.clear()
	attitude_bindings = false
	for spring in [brake,accel,authority]:
		spring.value = Vector3.ZERO
		spring.velocity = Vector3.ZERO

func advance(delta: float, controls: Dictionary, camera_yaw: float) -> void:
	# Edges are sampled once per display update, never once per integration step.
	_read_edges(controls,camera_yaw)
	var remaining := minf(delta,0.25)
	while remaining > 0.000001:
		var step := minf(remaining,1.0/120.0)
		_step(step,controls,camera_yaw)
		remaining -= step

func _read_edges(raw: Dictionary, camera_yaw: float) -> void:
	var was_uncaged := uncaged
	uncaged = bool(raw.get("uncage",false))
	for key in ["forward","back","left","right"]:
		if not raw.get(key,false): latches.erase(key)
		elif not previous.get(key,false) or was_uncaged and not uncaged: latches[key] = attitude_bindings
	for key in ["thrust_up","thrust_down"]:
		if raw.get(key,false) and not previous.get(key,false): detent = clampi(detent+(1 if key == "thrust_up" else -1),0,DETENTS.size()-1)
	var directional_edge := false
	for key in ["forward","back","left","right"]:
		if raw.get(key,false) and not previous.get(key,false): directional_edge = true
	if raw.get("burst",false) and (not previous.get("burst",false) or directional_edge) and burst_cooldown <= 0.0:
		var direction := Vector3(float(raw.get("right",false))-float(raw.get("left",false)),0,float(raw.get("back",false))-float(raw.get("forward",false)))
		if not direction.is_zero_approx():
			burst_direction = Basis(Vector3.UP,camera_yaw)*direction.normalized()
			burst_remaining = 0.20
			burst_cooldown = 0.50
	previous = raw.duplicate()

func _step(delta: float, raw: Dictionary, camera_yaw: float) -> void:
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
	if aero_authority > 0.65: attitude_bindings = true
	elif aero_authority < 0.35: attitude_bindings = false
	vector_stabilization = 0.0 if uncaged else 1.0-aero_authority
	departure = smoothstep(20,60,speed)*(1.0-attached_flow)
	var vector_input := Vector3.ZERO
	var rotation_input := Vector3.ZERO
	for key in latches:
		var attitude_key: bool = uncaged or latches[key]
		match key:
			"forward":
				if attitude_key: rotation_input.x -= 1.0
				else: vector_input.z -= 1.0
			"back":
				if attitude_key: rotation_input.x += 1.0
				else: vector_input.z += 1.0
			"left":
				if attitude_key: rotation_input.z += 1.0
				else: vector_input.x -= 1.0
			"right":
				if attitude_key: rotation_input.z -= 1.0
				else: vector_input.x += 1.0
	rotation_input.y = float(raw.get("yaw_left",false))-float(raw.get("yaw_right",false))
	var control_frame := aim_frame()
	var desired_rates := control_frame.x*rotation_input.x*1.25+control_frame.z*rotation_input.z*1.65+control_frame.y*rotation_input.y*1.1
	if not uncaged:
		# Continuous body-lift transition. Latches change interpretation only on a
		# new press, while an already-held translation request keeps working.
		var horizontal := Vector3(velocity.x,0,velocity.z)
		var forward := -Basis(Vector3.UP,heading_yaw).z
		var forward_alignment := horizontal.normalized().dot(forward)
		if horizontal.length() > 8.0 and forward_alignment > 0.5: forward = horizontal.normalized()
		var cruise := smoothstep(8,45,speed)*smoothstep(0.45,0.9,forward_alignment)
		var upright := Basis.looking_at(forward,Vector3.UP).get_rotation_quaternion()
		var target := (upright*Quaternion(Vector3.RIGHT,-PI/2.0*cruise)).normalized()
		# Banking remains the pilot's; no automatic wings-level correction during
		# aerodynamic flight. Flight-path assist acts only on the nose direction.
		var error := target*attitude.inverse()
		if error.w < 0.0: error = -error
		var alignment := error.get_axis()*error.get_angle()*lerpf(2.4,0.65,aero_authority)
		if aero_authority > 0.4: alignment = alignment.slide(airframe.z)
		if absf(rotation_input.x) > 0.05: alignment = alignment.slide(basis.x)
		if absf(rotation_input.z) > 0.05: alignment = alignment.slide(control_frame.z)
		if absf(rotation_input.y) > 0.05: alignment = alignment.slide(control_frame.y)
		desired_rates += alignment.limit_length(1.2)
	# Outer aim envelope: head/weapon/torso do the small corrections first.
	var aim_local := aim_frame().inverse()*aim_direction
	var aim_yaw := atan2(-aim_local.x,-aim_local.z)
	var aim_pitch := atan2(aim_local.y,Vector2(aim_local.x,aim_local.z).length())
	var follow := (1.25 if uncaged else lerpf(0.65,0.18,aero_authority))
	if aim_chassis_follow and absf(rotation_input.y) < 0.05: desired_rates += control_frame.y*signf(aim_yaw)*maxf(0.0,absf(aim_yaw)-deg_to_rad(75))*follow
	if aim_chassis_follow and absf(rotation_input.x) < 0.05: desired_rates += basis.x*signf(aim_pitch)*maxf(0.0,absf(aim_pitch)-deg_to_rad(65))*follow
	var old_rates := angular_velocity
	# Finite vernier torque servo; releasing input damps angular rates, not motion.
	angular_velocity = angular_velocity.move_toward(desired_rates.limit_length(2.2),delta*4.5)
	angular_acceleration = (angular_velocity-old_rates)/delta
	if angular_velocity.length() > 0.00001: attitude = (Quaternion(angular_velocity.normalized(),angular_velocity.length()*delta)*attitude).normalized()
	basis = Basis(attitude)
	var nose := basis.y
	heading_yaw = atan2(-nose.x,-nose.z) if Vector2(nose.x,nose.z).length() > 0.2 else atan2(basis.z.x,basis.z.z)
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
	if not uncaged:
		var camera_basis := Basis(Vector3.UP,camera_yaw)
		var requested_velocity := camera_basis*vector_input.limit_length(1.0)*65.0
		var horizontal_velocity := Vector3(velocity.x,0,velocity.z)
		var correction := (requested_velocity-horizontal_velocity)*1.1
		if vector_input.is_zero_approx(): correction *= pow(vector_stabilization,3)
		correction = correction.limit_length(16.0)
		var support := (GRAVITY-aerodynamic_force.y-required_force.y-velocity.y*1.8)*vector_stabilization if detent == 2 else -velocity.y*0.3*vector_stabilization
		# FBW verniers supplement the main thrust. Budget is finite; detent zero
		# really cuts power, and recaging bends velocity rather than replacing it.
		var trim := Vector3(correction.x-required_force.x*vector_stabilization,support,correction.z-required_force.z*vector_stabilization)
		required_force += trim.limit_length(thrust*1.5)
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

func aim_frame() -> Basis:
	var body := Basis(attitude)
	var tilt := acos(clampf(body.y.dot(Vector3.UP),-1.0,1.0))
	return body*Basis(Vector3.RIGHT,PI/2.0*smoothstep(0.0,PI/2.0,tilt))
