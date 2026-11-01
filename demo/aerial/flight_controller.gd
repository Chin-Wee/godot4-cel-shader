extends RefCounted

# Behavioral references: DCS Su-27 envelope protection and Elite Dangerous
# independent attitude/momentum. One native body owns motion; this supplies forces.
const Spring = preload("res://aerial/pose_servo.gd")
const DETENTS := [0.0, 0.5, 1.0, 2.0, 4.0]
# Scene geometry is retained: 10 world units = 1 meter. Forces use N, torque N m.
const WORLD_UNITS_PER_METER := 10.0
const GRAVITY := 9.81
const TRIM_SHARES := [0.05, 0.05, 0.05, 0.05, 0.40, 0.40]
const VECTOR_LIMIT := PI / 6.0
const MAX_RATE := Vector3(1.0, 0.8, 1.2)
const RATE_GAIN := 6.0
const MAX_ANGULAR_ACCELERATION := 5.0
# Feel parameters. Time in seconds, speed in m/s, accelerations in multiples of g.
const INPUT_RESPONSE := 0.14
const BRAKE_RESPONSE := 0.28
const ENGINE_SPOOL_RATE := 3.0 # Hover multiples per second; no velocity impulses.
const HOVER_DRIFT_GAIN := 3.6 # Dampen the moving-port transient within the same force limit.
const HOVER_TRIM_GAIN := 1.0
const HOVER_CANT_BIAS := 0.15
const HOVER_TRANSLATE_TIME := 3.0
const HOVER_TILT_RAMP := 1.25
const HOVER_TRANSLATE_G := 0.35
const FLIGHT_PITCH_LIMIT := PI / 6.0
const FLIGHT_PITCH_GAIN := 3.0
const JUMP_PUSH_TIME := 0.22
const JUMP_PEAK_G := 4.0
# Cd stays positive in every pose. High-speed drag supplies a finite energy bound.
const AERO_AREA_M2 := 80.0
const BASE_DRAG_CD := 0.075
const HIGH_SPEED_DRAG_CD := 0.28
const BRAKE_DRAG_CD := 1.8
const ACTION_KEYS := {
	"flight_forward": KEY_W, "flight_back": KEY_S,
	"flight_left": KEY_A, "flight_right": KEY_D,
	"flight_yaw_left": KEY_Q, "flight_yaw_right": KEY_E,
	"flight_thrust_up": KEY_SPACE, "flight_thrust_down": KEY_C,
	"flight_brake": KEY_SHIFT, "flight_jump": KEY_R, "flight_precision": KEY_CTRL,
}
var body: RigidBody3D
# These are readbacks, never a second integrated position/velocity/attitude.
var position: Vector3:
	get: return body.global_position
var velocity: Vector3:
	get: return body.linear_velocity / WORLD_UNITS_PER_METER
var attitude: Quaternion:
	get: return body.global_basis.orthonormalized().get_rotation_quaternion()
var angular_velocity: Vector3:
	get: return body.angular_velocity
var model_scale := 50.0
var detent := 2
var engine_level := 1.0
var requested_thrust := 0.0
var requested_main_force := Vector3.ZERO # Existing motor request, before spool/cone limits.
var delivered_thrust := 0.0
var main_force := Vector3.ZERO
var main_torque := Vector3.ZERO
var aero_force := Vector3.ZERO
var rcs_torque := Vector3.ZERO
var torque_fraction := 0.0
var torque_saturated := false
var motor_saturated := false
var grounded := false
var jump_requested := false
var jump_remaining := 0.0
var leg_force := Vector3.ZERO
var hover_assist := 0.0
var hover_gimbal_trim := Vector3.ZERO
var brake_amount := 0.0
var rotation_command := Vector3.ZERO
var rotation_request := Vector3.ZERO # Animation intent before control smoothing.
var hover_translation := Vector3.ZERO # Heading-local force request, not velocity.
var hover_actuation := Vector3.ZERO # Planned heading-local acceleration for posing.
var hover_hold := Vector2.ZERO # Pitch/roll hold duration; a reversal starts fresh.
var hover_press_axes := Vector2.ZERO # This press began in powered upright hover.
var last_direction := Vector2.ZERO
var translation := Spring.new()
var flight_protection := 0.0
var requested_rates := Vector3.ZERO # World angular-rate request after protection.
var released_axes := Vector3(1, 0, 1)
var control_blend := 0.0
var acceleration := Vector3.ZERO
var angular_acceleration := Vector3.ZERO
var local_acceleration := Vector3.ZERO
var local_velocity := Vector3.ZERO
var local_airflow := Vector3.ZERO
var required_force := Vector3.ZERO # Specific propulsion force, m/s², for posing.
var angle_of_attack := 0.0
var sideslip := 0.0
var attached_flow := 0.0
var aero_authority := 0.0 # Readable airflow telemetry, never an input gate.
var departure := 0.0
var g_load := 1.0
var clock := 0.0
var time_to_impact := INF
var air_density := 1.225 # kg/m³; zero permits a vacuum invariant check.
var wind := Vector3.ZERO # m/s, world axes.
var air_velocity := Vector3.ZERO
var engine_shares := PackedFloat32Array(TRIM_SHARES)
var motor_angles: Array[Vector3] = []
var motor_forces: Array[Vector3] = []
var motor_springs: Array = []
var command := Spring.new()
var brake := Spring.new()
var accel := Spring.new()
var last_velocity := Vector3.ZERO
var last_rates := Vector3.ZERO
var sampled := false

static func install_input_actions() -> void:
	for action in ACTION_KEYS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new()
		event.physical_keycode = ACTION_KEYS[action]
		InputMap.action_add_event(action, event)
	# Retire the old aerial-only actions, including their Shift/X bindings.
	for action in ["flight_burst", "flight_rise", "flight_sink"]:
		if InputMap.has_action(action): InputMap.erase_action(action)

static func read_input() -> Dictionary:
	var result := {}
	for key in ["forward", "back", "left", "right", "yaw_left", "yaw_right", "brake", "precision"]:
		result[key] = Input.is_action_pressed("flight_" + key)
	return result

func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("flight_thrust_up"): detent = mini(detent + 1, DETENTS.size() - 1)
	if event.is_action_pressed("flight_thrust_down"): detent = maxi(detent - 1, 0)
	if event.is_action_pressed("flight_jump"): jump_requested = true

func configure(owner_body: RigidBody3D, display_scale: float) -> void:
	body = owner_body
	model_scale = display_scale
	for index in 6:
		motor_springs.append(Spring.new())
		motor_angles.append(Vector3.ZERO)
		motor_forces.append(Vector3.ZERO)

func reset() -> void:
	detent = 2
	engine_level = 1.0
	jump_requested = false
	jump_remaining = 0.0
	brake_amount = 0.0
	hover_gimbal_trim = Vector3.ZERO
	control_blend = 0.0
	clock = 0.0
	rotation_request = Vector3.ZERO
	hover_translation = Vector3.ZERO
	hover_actuation = Vector3.ZERO
	hover_hold = Vector2.ZERO
	hover_press_axes = Vector2.ZERO
	last_direction = Vector2.ZERO
	flight_protection = 0.0
	requested_rates = Vector3.ZERO
	requested_main_force = Vector3.ZERO
	sampled = false
	for spring in [command, brake, accel, translation] + motor_springs:
		spring.value = Vector3.ZERO
		spring.velocity = Vector3.ZERO

func step(state: PhysicsDirectBodyState3D, controls: Dictionary, outlets: Array, on_ground: bool, leg_reach: bool) -> void:
	var dt := state.step
	clock += dt
	grounded = on_ground
	_measure_motion(state, dt)
	_measure_airflow(state.transform.basis.orthonormalized(), dt)
	var frame := state.transform.basis.orthonormalized()
	_calculate_hover(frame)
	_read_commands(controls, dt)
	_calculate_aerodynamics(frame)
	_calculate_main_thrusters(outlets, frame, dt)
	_calculate_attitude_torque(state)
	_calculate_jump(leg_reach, dt)
	for index in 6:
		state.apply_force(motor_forces[index] * WORLD_UNITS_PER_METER, outlets[index].position)
	state.apply_central_force((aero_force + leg_force) * WORLD_UNITS_PER_METER)
	state.apply_torque(rcs_torque * WORLD_UNITS_PER_METER * WORLD_UNITS_PER_METER)
	required_force = (main_force + leg_force) / body.mass

func _measure_motion(state: PhysicsDirectBodyState3D, dt: float) -> void:
	var current_velocity := state.linear_velocity / WORLD_UNITS_PER_METER
	air_velocity = current_velocity - wind
	acceleration = (current_velocity - last_velocity) / dt if sampled else Vector3.ZERO
	angular_acceleration = (state.angular_velocity - last_rates) / dt if sampled else Vector3.ZERO
	last_velocity = current_velocity
	last_rates = state.angular_velocity
	sampled = true
	var frame := state.transform.basis.orthonormalized()
	local_velocity = frame.inverse() * current_velocity
	local_airflow = frame.inverse() * (wind - current_velocity)
	local_acceleration = accel.step(frame.inverse() * acceleration, dt, 0.12)
	g_load = (acceleration - Vector3.DOWN * GRAVITY).length() / GRAVITY

func _read_commands(raw: Dictionary, dt: float) -> void:
	var precision := 0.35 if raw.get("precision", false) else 1.0
	var request := Vector3(float(raw.get("back", false)) - float(raw.get("forward", false)),
		float(raw.get("yaw_left", false)) - float(raw.get("yaw_right", false)),
		float(raw.get("left", false)) - float(raw.get("right", false)))
	var direction := Vector2(request.x,request.z)
	var tilt := Vector2.ONE
	for axis in 2:
		if direction[axis]==0 or direction[axis]!=last_direction[axis]:
			hover_hold[axis] = 0.0
			hover_press_axes[axis] = float(direction[axis]!=0 and hover_assist>0.5)
		if detent==0: hover_press_axes[axis] = 0.0
		if direction[axis]!=0: hover_hold[axis] += dt
		# Keep the promised interval even if powered ascent increases airspeed.
		# A new airborne press still rotates immediately; cutoff cancels the latch.
		tilt[axis] = 1.0-hover_press_axes[axis]*(1.0-smoothstep(HOVER_TRANSLATE_TIME,HOVER_TRANSLATE_TIME+HOVER_TILT_RAMP,hover_hold[axis]))
	last_direction = direction
	var planar := Vector3(-request.z*(1.0-tilt.y),0,request.x*(1.0-tilt.x)).limit_length(1.0)*precision
	hover_translation = translation.step(planar,dt,INPUT_RESPONSE)
	rotation_request = request*Vector3(tilt.x,1,tilt.y)*precision
	released_axes = Vector3(1.0-absf(rotation_request.x),0,1.0-absf(rotation_request.z))
	rotation_command = command.step(rotation_request, dt, INPUT_RESPONSE)
	brake_amount = clampf(brake.step(Vector3(float(raw.get("brake", false)), 0, 0), dt, BRAKE_RESPONSE).x, 0, 1)

func _measure_airflow(frame: Basis, dt: float) -> void:
	var speed := air_velocity.length()
	var flight_frame := frame * Basis(Vector3.RIGHT, PI / 2.0) # Head-first flight.
	var local := flight_frame.inverse() * air_velocity
	angle_of_attack = atan2(-local.y, -local.z) if speed > 0.1 else 0.0
	sideslip = atan2(local.x, maxf(0.01, absf(local.z))) if speed > 0.1 else 0.0
	attached_flow = (1.0 - smoothstep(FLIGHT_PITCH_LIMIT, deg_to_rad(65), absf(angle_of_attack))) * (1.0 - smoothstep(0.3, 1.2, absf(sideslip)))
	aero_authority = smoothstep(20, 70, speed) * attached_flow
	departure = smoothstep(20, 60, speed) * (1.0 - attached_flow)
	# One explicit coordinate conversion: chest-forward hover to head-first flight.
	# Absolute pitch projection excludes bank, so inverted rolls cannot swap axes.
	var projection := Vector2(frame.y.y, frame.z.y)
	var posture := control_blend if projection.length() < 0.15 else atan2(absf(projection.y), absf(projection.x)) / (PI / 2.0)
	var vertical_flight := smoothstep(20, 50, speed) * absf(frame.y.dot(air_velocity.normalized()))
	control_blend = lerpf(control_blend, maxf(posture, vertical_flight), 1.0 - exp(-dt / 0.20))

func _calculate_hover(frame: Basis) -> void:
	var tilt := acos(clampf(frame.y.dot(Vector3.UP), -1, 1))
	var powered := clampf(engine_level, 0, 1) if detent > 0 else 0.0
	hover_assist = powered * (1.0 - smoothstep(18, 45, air_velocity.length())) * (1.0 - smoothstep(deg_to_rad(30), deg_to_rad(60), tilt))

func _calculate_aerodynamics(frame: Basis) -> void:
	var speed := air_velocity.length()
	var direction := air_velocity.normalized()
	var wing := frame * Basis(Vector3.RIGHT, PI / 2.0)
	# ponytail: one calibrated lifting area/polar; use measured data if supplied.
	var area := AERO_AREA_M2 * pow(model_scale / 50.0, 2)
	var pressure_area := 0.5 * air_density * speed * speed * area
	var lift_coefficient := clampf(angle_of_attack * 3.2 + 0.32, -1.1, 1.1) * attached_flow
	var lift := wing.y.slide(direction).normalized() * pressure_area * lift_coefficient if speed > 0.1 else Vector3.ZERO
	var broadside := absf(direction.dot(frame.z))
	var drag_coefficient := BASE_DRAG_CD + HIGH_SPEED_DRAG_CD * smoothstep(35, 100, speed) + 0.75 * broadside * broadside + 0.15 * lift_coefficient * lift_coefficient + BRAKE_DRAG_CD * brake_amount
	aero_force = lift - direction * pressure_area * drag_coefficient

func _calculate_main_thrusters(outlets: Array, frame: Basis, dt: float) -> void:
	var neutral := minf(released_axes.x, released_axes.z)
	var motion := air_velocity + wind
	var horizontal := Vector3(motion.x, 0, motion.z)
	var back := frame.z.slide(Vector3.UP).normalized()
	var right := Vector3.UP.cross(back).normalized()
	var move := right*hover_translation.x+back*hover_translation.z
	# Do not brake or integrate trim against a commanded translation. Neutral
	# directions still catch drift, and release smoothly restores the full catch.
	var drift := horizontal-horizontal.project(move)*minf(move.length(),1.0) if not move.is_zero_approx() else horizontal
	var correction := (-drift * HOVER_DRIFT_GAIN).limit_length(GRAVITY * 0.45) * hover_assist * neutral
	correction += move*GRAVITY*HOVER_TRANSLATE_G
	# The pose prepares the actual push, including the opposite force on release.
	# Animated ankles can then point real heel thrust into the braking direction.
	hover_actuation = (frame.inverse()*correction/(GRAVITY*HOVER_TRANSLATE_G)).limit_length(1.0)
	# Bounded integral trim removes steady bias from the canted physical ports.
	# It only moves gimbals; it cannot add translational force or exceed a cone.
	if hover_assist > 0.01 and neutral > 0.9 and move.length()<0.05 and horizontal.length()<1.5:
		hover_gimbal_trim = (hover_gimbal_trim - drift * dt * HOVER_TRIM_GAIN * hover_assist).limit_length(GRAVITY * 1.5)
	else:
		hover_gimbal_trim *= exp(-dt / 0.4)
	# Port cant is body-relative feed-forward, so yaw cannot leave stale world
	# trim fighting the motors. Integral trim only learns the remaining error.
	var cant_bias := frame.z * GRAVITY * HOVER_CANT_BIAS
	var desired := (frame.y * GRAVITY + correction + (cant_bias + hover_gimbal_trim) * hover_assist).normalized()
	var vertical_fraction := 0.0
	motor_saturated = false
	for index in 6:
		var local: Vector3 = outlets[index].basis.inverse() * -desired
		var requested_angle := acos(clampf(local.z, -1, 1))
		motor_saturated = motor_saturated or requested_angle > VECTOR_LIMIT + 0.01
		var axis := Vector3.BACK.cross(local).normalized()
		if axis.is_zero_approx(): axis = Vector3.RIGHT
		var angle: Vector3 = motor_springs[index].step(axis * minf(requested_angle, VECTOR_LIMIT), dt, 0.16).limit_length(VECTOR_LIMIT)
		motor_springs[index].value = angle
		motor_angles[index] = angle
		var rotation := Basis.IDENTITY if angle.is_zero_approx() else Basis(Quaternion(angle.normalized(), angle.length()))
		motor_forces[index] = -(outlets[index].basis * rotation).z.normalized()
		vertical_fraction += motor_forces[index].y * engine_shares[index]
	var target: float = DETENTS[detent]
	if detent == 2 and vertical_fraction > 0.3:
		var support := body.mass * (GRAVITY - motion.y * 1.8) - aero_force.y
		var compensated := clampf(support / (body.mass * GRAVITY * vertical_fraction), 0, 2)
		target = lerpf(target, compensated, hover_assist)
	requested_thrust = target * body.mass * GRAVITY
	requested_main_force = desired * requested_thrust
	engine_level = move_toward(engine_level, target, dt * ENGINE_SPOOL_RATE)
	delivered_thrust = engine_level * body.mass * GRAVITY
	main_force = Vector3.ZERO
	main_torque = Vector3.ZERO
	for index in 6:
		# Steerable heels carry hover. Redistribute as each reaches its common
		# capacity; all six equalize at 4x. Canted barrels cannot oppose every slide.
		var heel_share := minf(TRIM_SHARES[4],(4.0/6.0)/maxf(engine_level,0.01))
		engine_shares[index] = heel_share if index>=4 else (1.0-2.0*heel_share)/4.0
		motor_forces[index] *= delivered_thrust * engine_shares[index]
		main_force += motor_forces[index]
		# Application positions are world-oriented offsets from the body origin.
		var lever: Vector3 = outlets[index].position / WORLD_UNITS_PER_METER
		main_torque += lever.cross(motor_forces[index])

func _calculate_attitude_torque(state: PhysicsDirectBodyState3D) -> void:
	var frame := state.transform.basis.orthonormalized()
	var pilot := frame * Basis(Vector3.RIGHT, PI / 2.0 * control_blend)
	var local_rates := rotation_command*MAX_RATE
	# DCS-style soft AoA protection: pitch with the trajectory instead of rotating
	# the chassis far faster than lift/thrust can bend it. No attitude/velocity snap.
	# Brake or engine cutoff releases the protection for deliberate combat stalls.
	var alignment := frame.y.dot(air_velocity.normalized())
	flight_protection = smoothstep(18,35,air_velocity.length())*smoothstep(0.2,0.9,engine_level)*(1.0-smoothstep(deg_to_rad(35),deg_to_rad(60),acos(clampf(alignment,-1,1))))*(1.0-brake_amount)
	if flight_protection>0.0001:
		var net_acceleration := (main_force+aero_force)/body.mass+Vector3.DOWN*GRAVITY
		var path_rate := air_velocity.cross(net_acceleration).dot(pilot.x)/maxf(air_velocity.length_squared(),1.0)
		var predicted := angle_of_attack+(state.angular_velocity.dot(pilot.x)-path_rate)*0.20
		var protected_pitch := clampf(local_rates.x,path_rate+(-FLIGHT_PITCH_LIMIT-predicted)*FLIGHT_PITCH_GAIN,path_rate+(FLIGHT_PITCH_LIMIT-predicted)*FLIGHT_PITCH_GAIN)
		local_rates.x = lerpf(local_rates.x,protected_pitch,flight_protection)
	var rates := pilot*local_rates
	var upright := pilot.inverse() * frame.y.cross(Vector3.UP) * 2.5 * hover_assist
	upright *= released_axes
	rates += pilot * upright
	requested_rates = rates
	var local_accel := frame.inverse() * (rates - state.angular_velocity) * RATE_GAIN
	# Native inertia uses world units²; controller torque is explicitly N m.
	var inertia := frame.inverse() * state.inverse_inertia_tensor.inverse() * frame
	inertia = inertia.scaled(Vector3.ONE / (WORLD_UNITS_PER_METER * WORLD_UNITS_PER_METER))
	var request := inertia * local_accel - frame.inverse() * main_torque
	# ponytail: lumped three-axis cold-gas actuator; per-outlet allocation only
	# if its fuel usage or force coupling becomes gameplay-relevant.
	var limits := Vector3(inertia.x.x, inertia.y.y, inertia.z.z) * MAX_ANGULAR_ACCELERATION
	var applied := request.clamp(-limits, limits)
	torque_fraction = maxf(absf(request.x) / maxf(limits.x, 0.001), maxf(absf(request.y) / maxf(limits.y, 0.001), absf(request.z) / maxf(limits.z, 0.001)))
	torque_saturated = torque_fraction > 1.0
	rcs_torque = frame * applied

func _calculate_jump(leg_reach: bool, dt: float) -> void:
	if jump_requested:
		if grounded and jump_remaining <= 0: jump_remaining = JUMP_PUSH_TIME
		jump_requested = false
	leg_force = Vector3.ZERO
	if jump_remaining > 0 and leg_reach:
		# Finite stance extension, permitted only while the ground is in leg reach.
		var extension := 1.0 - jump_remaining / JUMP_PUSH_TIME
		leg_force = Vector3.UP * body.mass * GRAVITY * JUMP_PEAK_G * sin(PI * extension)
	jump_remaining = maxf(0, jump_remaining - dt)

func pilot_frame() -> Basis:
	return Basis(attitude) * Basis(Vector3.RIGHT, PI / 2.0 * control_blend)
