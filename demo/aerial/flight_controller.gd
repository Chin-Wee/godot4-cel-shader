extends RefCounted

# Behavioral references: DCS Su-27 envelope protection and Elite Dangerous
# independent attitude/momentum. One native body owns motion; this supplies forces.
const Spring = preload("res://aerial/pose_servo.gd")
const DETENTS := [0.0, 0.5, 1.0, 2.0, 4.0]
# Scene geometry is retained: 10 world units = 1 meter. Forces use N, torque N m.
const WORLD_UNITS_PER_METER := 10.0
const GRAVITY := 9.81
const TRIM_SHARES := [0.02, 0.02, 0.02, 0.02, 0.46, 0.46]
const VECTOR_LIMIT := PI / 6.0
const MAX_RATE := Vector3(0.75, 0.8, 1.5)
const FLIP_RATE := 1.95 # Motor-assisted somersault; fixed capsule inertia is retained.
const RATE_GAIN := 6.0
const MAX_ANGULAR_ACCELERATION := 5.0
# Feel parameters. Time in seconds, speed in m/s, accelerations in multiples of g.
const INPUT_RESPONSE := 0.14
const FULL_POWER_INPUT_RESPONSE := 0.28 # Leave torque reserve while loaded joints settle.
const BRAKE_RESPONSE := 0.28
const ENGINE_SPOOL_RATE := 3.0 # Hover multiples per second; no velocity impulses.
const HOVER_VECTOR_RESPONSE := 0.08 # AC VI directional boost reference: jets lead the slide.
const RCS_PULSE_HZ := 3.0
const RCS_DEADBAND := 0.012 # Fraction of actuator capacity; tolerate quiet trim error.
const RCS_TRIM_DUTY := 0.65 # Long, soft trim bursts with a visible coast interval.
const RCS_CONTINUOUS_DEMAND := 0.35 # Larger attitude demands use a sustained burn.
const HOVER_DRIFT_GAIN := 3.6 # Dampen the moving-port transient within the same force limit.
const HOVER_TRIM_GAIN := 1.0
const HOVER_CANT_BIAS := 0.07
const HOVER_TRANSLATE_TIME := 3.0
const HOVER_TILT_RAMP := 1.25
const HOVER_TRANSLATE_G := 0.60
const FLIGHT_PITCH_LIMIT := PI / 6.0
const FLIGHT_PITCH_GAIN := 3.0
const JUMP_PUSH_TIME := 0.22
const JUMP_PEAK_G := 4.0
# Cd stays positive in every pose. High-speed drag supplies a finite energy bound.
const AERO_AREA_M2 := 80.0
const BASE_DRAG_CD := 0.075
const HIGH_SPEED_DRAG_CD := 0.28
const BRAKE_DRAG_CD := 1.8
const LIFT_BIAS := 0.36 # Shared camber calibrated after splitting the original area.
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
var aero_torque := Vector3.ZERO
var aero_power := 0.0 # Passive air power including angular point velocity, watts.
var aero_surface_forces: Array[Vector3] = []
var aero_surfaces: Array = []
var rcs_torque := Vector3.ZERO
var rcs_request := Vector3.ZERO # Bounded continuous demand for nozzle aiming.
var rcs_load := 0.0 # Delivered pulse, shared by physical torque and exhaust.
var control_torque := Vector3.ZERO # Desired total moment before actuator allocation.
var torque_limits := Vector3.ZERO # Body-local cold-gas capacity, N m.
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
var brake_request := 0.0 # Pose preparation before aerodynamic brake smoothing.
var rotation_command := Vector3.ZERO
var rotation_request := Vector3.ZERO # Animation intent before control smoothing.
var hover_translation := Vector3.ZERO # Heading-local force request, not velocity.
var translation_request := Vector3.ZERO # Unfiltered intent for pose preparation.
var hover_actuation := Vector3.ZERO # Planned heading-local acceleration for posing.
var hover_hold := Vector2.ZERO # Pitch/roll hold duration; a reversal starts fresh.
var hover_press_axes := Vector2.ZERO # This press began in powered upright hover.
var last_direction := Vector2.ZERO
var translation := Spring.new()
var flight_protection := 0.0
var requested_rates := Vector3.ZERO # World angular-rate request after protection.
var effective_rates := Vector3.ZERO # Pilot-local rate after protection and flip scaling.
var gaze_direction := Vector3.ZERO # Optional world-space vision target; no force authority.
var brake_spread := 0.0 # Completed limb projection, independent of the brake command.
var released_axes := Vector3(1, 0, 1)
var control_blend := 0.0
var control_target := 0.0
# Pitch/roll channels, measured in the current pilot frame. Signed, unwrapped
# travel is telemetry, never an integrated replacement for native attitude.
var maneuver_travel := Vector2.ZERO
var maneuver_strength := Vector2.ZERO
var maneuver_recovery := Vector2.ZERO
var maneuver_direction := Vector2.ZERO
var maneuver_hold := Vector2.ZERO
var roll_frame_locked := false
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
	brake_request = 0.0
	hover_gimbal_trim = Vector3.ZERO
	control_blend = 0.0
	control_target = 0.0
	maneuver_travel = Vector2.ZERO
	maneuver_strength = Vector2.ZERO
	maneuver_recovery = Vector2.ZERO
	maneuver_direction = Vector2.ZERO
	maneuver_hold = Vector2.ZERO
	roll_frame_locked = false
	clock = 0.0
	rotation_request = Vector3.ZERO
	hover_translation = Vector3.ZERO
	translation_request = Vector3.ZERO
	hover_actuation = Vector3.ZERO
	hover_hold = Vector2.ZERO
	hover_press_axes = Vector2.ZERO
	last_direction = Vector2.ZERO
	flight_protection = 0.0
	requested_rates = Vector3.ZERO
	effective_rates = Vector3.ZERO
	gaze_direction = Vector3.ZERO
	brake_spread = 0.0
	requested_main_force = Vector3.ZERO
	main_force = Vector3.ZERO
	main_torque = Vector3.ZERO
	aero_force = Vector3.ZERO
	rcs_torque = Vector3.ZERO
	rcs_request = Vector3.ZERO
	rcs_load = 0.0
	control_torque = Vector3.ZERO
	aero_torque = Vector3.ZERO
	aero_power = 0.0
	sampled = false
	for spring in [command, brake, accel, translation] + motor_springs:
		spring.value = Vector3.ZERO
		spring.velocity = Vector3.ZERO

func step(state: PhysicsDirectBodyState3D, controls: Dictionary, outlets: Array, on_ground: bool, leg_reach: bool, surfaces: Array, spread: float) -> void:
	var dt := state.step
	clock += dt
	grounded = on_ground
	_measure_motion(state, dt)
	_measure_airflow(state.transform.basis.orthonormalized(), dt)
	var frame := state.transform.basis.orthonormalized()
	_calculate_hover(frame)
	_read_commands(controls, dt)
	_update_maneuvers(dt)
	brake_spread = clampf(spread,0,1)
	_calculate_aerodynamics(surfaces)
	_calculate_attitude_demand(state)
	_calculate_main_thrusters(outlets, frame, dt)
	_calculate_rcs_torque(frame,dt)
	_calculate_jump(leg_reach, dt)
	for index in 6:
		state.apply_force(motor_forces[index] * WORLD_UNITS_PER_METER, outlets[index].position)
	for index in aero_surfaces.size():
		state.apply_force(aero_surface_forces[index]*WORLD_UNITS_PER_METER,aero_surfaces[index].position)
	state.apply_central_force(leg_force * WORLD_UNITS_PER_METER)
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
			hover_press_axes[axis] = float(direction[axis]!=0 and hover_assist>=0.5)
		if detent==0: hover_press_axes[axis] = 0.0
		if direction[axis]!=0: hover_hold[axis] += dt
		# Keep the promised interval even if powered ascent increases airspeed.
		# A new airborne press still rotates immediately; cutoff cancels the latch.
		tilt[axis] = 1.0-hover_press_axes[axis]*(1.0-smoothstep(HOVER_TRANSLATE_TIME,HOVER_TRANSLATE_TIME+HOVER_TILT_RAMP,hover_hold[axis]))
	last_direction = direction
	var planar := Vector3(-request.z*(1.0-tilt.y),0,request.x*(1.0-tilt.x)).limit_length(1.0)*precision
	translation_request = planar
	hover_translation = translation.step(planar,dt,INPUT_RESPONSE)
	rotation_request = request*Vector3(tilt.x,1,tilt.y)*precision
	released_axes = Vector3(1.0-absf(rotation_request.x),0,1.0-absf(rotation_request.z))
	var rotation_response := lerpf(INPUT_RESPONSE,FULL_POWER_INPUT_RESPONSE,smoothstep(2,4,engine_level))
	rotation_command = command.step(rotation_request, dt, rotation_response)
	brake_request = float(raw.get("brake", false))
	brake_amount = clampf(brake.step(Vector3(brake_request, 0, 0), dt, BRAKE_RESPONSE).x, 0, 1)

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
	control_target = maxf(posture, vertical_flight)
	if not roll_frame_locked:
		control_blend = lerpf(control_blend, control_target, 1.0 - exp(-dt / 0.20))

func _update_maneuvers(dt: float) -> void:
	# Capture the intended convention, not a partially filtered transition
	# from a reset/hover entry that would turn a lengthwise roll into yaw.
	if not roll_frame_locked and absf(rotation_request.z)>0.1 and not grounded and jump_remaining<=0.0:
		control_blend = control_target
	var rates := pilot_frame().inverse()*angular_velocity
	var request := Vector2(rotation_request.x,rotation_request.z)
	var measured := Vector2(rates.x,rates.z)
	var airborne := not grounded and jump_remaining<=0.0
	var flip_allowed := airborne and (detent==0 or brake_request>0.5)
	for axis in 2:
		var active := absf(request[axis])>0.1 and airborne and (axis==1 or flip_allowed)
		if active:
			if maneuver_direction[axis]!=signf(request[axis]):
				maneuver_travel[axis] = 0.0
				maneuver_hold[axis] = 0.0
			maneuver_direction[axis] = signf(request[axis])
			maneuver_hold[axis] += dt
		else: maneuver_hold[axis] = 0.0
		# Native angular motion advances the gesture; held input alone cannot.
		maneuver_travel[axis] += measured[axis]*dt
		var opposing := float(request[axis]*measured[axis]<0.0)
		var recovering := maxf(1.0-absf(request[axis]),opposing) if airborne else 0.0
		maneuver_recovery[axis] = smoothstep(0.15,1.0,absf(measured[axis]))*recovering
		var target := absf(request[axis]) if active else 0.0
		maneuver_strength[axis] = lerpf(maneuver_strength[axis],target,1.0-exp(-dt/(0.12 if active else 0.28)))
		if not active and absf(measured[axis])<0.15 and maneuver_strength[axis]<0.01:
			maneuver_travel[axis] = 0.0
			maneuver_direction[axis] = 0.0
	roll_frame_locked = airborne and (absf(request.y)>0.1 or absf(measured.y)>=0.15)

func _calculate_hover(frame: Basis) -> void:
	var tilt := acos(clampf(frame.y.dot(Vector3.UP), -1, 1))
	var powered := clampf(engine_level, 0, 1) if detent > 0 else 0.0
	hover_assist = powered * (1.0 - smoothstep(18, 45, air_velocity.length())) * (1.0 - smoothstep(deg_to_rad(30), deg_to_rad(60), tilt))

func _calculate_aerodynamics(surfaces: Array) -> void:
	# MSFS 2020 production reference: forces follow individual posed surfaces.
	# ponytail: five calibrated panels and fixed capsule inertia, not mesh CFD.
	aero_surfaces = surfaces
	aero_surface_forces.clear()
	aero_force = Vector3.ZERO
	aero_torque = Vector3.ZERO
	aero_power = 0.0
	for surface in surfaces:
		var lever: Vector3 = surface.position/WORLD_UNITS_PER_METER
		var flow := air_velocity+angular_velocity.cross(lever)
		var speed := flow.length()
		var direction := flow/maxf(speed,0.001)
		var normal: Vector3 = surface.normal
		var forward: Vector3 = surface.forward
		var alpha := atan2(-flow.dot(normal),flow.dot(forward)) if speed>0.1 else 0.0
		var span: Vector3 = forward.cross(normal)
		var slip := absf(direction.dot(span))
		var attached := (1.0-smoothstep(FLIGHT_PITCH_LIMIT,deg_to_rad(65),absf(alpha)))*(1.0-smoothstep(0.3,0.93,slip))
		var area: float = AERO_AREA_M2*pow(model_scale/50.0,2)*surface.fraction
		var pressure_area := 0.5*air_density*speed*speed*area
		var lift_coefficient := clampf(alpha*3.2+LIFT_BIAS,-1.1,1.1)*attached
		var lift := normal.slide(direction).normalized()*pressure_area*lift_coefficient if speed>0.1 else Vector3.ZERO
		var broadside := absf(direction.dot(normal))
		var cd := BASE_DRAG_CD+HIGH_SPEED_DRAG_CD*smoothstep(35,100,speed)+0.75*broadside*broadside+0.15*lift_coefficient*lift_coefficient+BRAKE_DRAG_CD*brake_spread
		var force := lift-direction*pressure_area*cd
		aero_surface_forces.append(force)
		aero_force += force
		aero_torque += lever.cross(force)
		aero_power += force.dot(flow)

func _calculate_main_thrusters(outlets: Array, frame: Basis, dt: float) -> void:
	var neutral := minf(released_axes.x, released_axes.z)
	var motion := air_velocity + wind
	var horizontal := Vector3(motion.x, 0, motion.z)
	var back := frame.z.slide(Vector3.UP).normalized()
	var right := Vector3.UP.cross(back).normalized()
	var move := right*hover_translation.x+back*hover_translation.z
	# Do not brake or integrate trim against a commanded translation. Neutral
	# directions still catch drift, and release smoothly restores the full catch.
	var drift := horizontal
	if not move.is_zero_approx():
		# Only preserve travel already going the requested way. An opposing
		# command should catch the old momentum before accelerating out of it.
		var along := maxf(horizontal.dot(move.normalized()),0.0)
		drift -= move.normalized()*along*minf(move.length(),1.0)
	var correction := (-drift * HOVER_DRIFT_GAIN).limit_length(GRAVITY * 0.55) * hover_assist * neutral
	correction += move*GRAVITY*HOVER_TRANSLATE_G
	# Deliberate authority curve: stronger nominal slides without multiplying
	# their lateral demand fourfold during maximum-power vertical ascent.
	correction -= move*GRAVITY*HOVER_TRANSLATE_G*(1.0-1.0/sqrt(maxf(engine_level,1.0)))
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
	var directions: Array[Vector3] = []
	for index in 6:
		var requested_angle := acos(clampf((outlets[index].basis.inverse()*-desired).z,-1,1))
		motor_saturated = motor_saturated or requested_angle > VECTOR_LIMIT + 0.01
		directions.append(_motor_direction(outlets[index].basis,_motor_angle(outlets[index].basis,desired)))
		vertical_fraction += directions[index].y * engine_shares[index]
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
	_trim_main_moment(outlets,directions)
	for index in 6:
		var response := lerpf(0.16,HOVER_VECTOR_RESPONSE,minf(translation_request.length(),1.0))
		var angle: Vector3 = motor_springs[index].step(_motor_angle(outlets[index].basis,directions[index]),dt,response).limit_length(VECTOR_LIMIT)
		motor_springs[index].value = angle
		motor_angles[index] = angle
		motor_forces[index] = _motor_direction(outlets[index].basis,angle)*delivered_thrust*engine_shares[index]
		main_force += motor_forces[index]
		# Application positions are world-oriented offsets from the body origin.
		var lever: Vector3 = outlets[index].position / WORLD_UNITS_PER_METER
		main_torque += lever.cross(motor_forces[index])

func _motor_angle(basis: Basis, direction: Vector3) -> Vector3:
	var local := basis.inverse()*-direction
	var axis := Vector3.BACK.cross(local).normalized()
	if axis.is_zero_approx(): axis = Vector3.RIGHT
	return axis*minf(acos(clampf(local.z,-1,1)),VECTOR_LIMIT)

func _motor_direction(basis: Basis, angle: Vector3) -> Vector3:
	var rotation := Basis.IDENTITY if angle.is_zero_approx() else Basis(Quaternion(angle.normalized(),angle.length()))
	return -(basis*rotation).z.normalized()

func _trim_main_moment(outlets: Array, directions: Array[Vector3]) -> void:
	# Force-priority control allocation. Native 3x3 blocks solve the small
	# force/moment correction; each sweep projects back into the real cones.
	# ponytail: six linearized sweeps, not a general-purpose optimizer.
	if delivered_thrust<1.0: return
	var reference := Vector3.ZERO
	var original: Array[Vector3] = directions.duplicate()
	for i in 6: reference += directions[i]*engine_shares[i]
	for sweep in 6:
		# Allocate the desired total moment after accounting for the actual air
		# moment. Main engines help with the deficit; cold gas covers what remains.
		var moment := (aero_torque-control_torque)/maxf(delivered_thrust,1.0)
		var force := Vector3.ZERO
		var force_response := Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
		var coupling := Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
		var moment_response := Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
		for i in 6:
			var lever: Vector3 = outlets[i].position/WORLD_UNITS_PER_METER
			var weight: float = engine_shares[i]
			moment += lever.cross(directions[i])*weight
			force += directions[i]*weight
			for axis in 3:
				var unit := Vector3.ZERO
				unit[axis] = 1.0
				var rotational := unit.cross(lever).slide(directions[i])
				force_response[axis] += unit.slide(directions[i])*weight
				coupling[axis] += rotational*weight
				moment_response[axis] += lever.cross(rotational)*weight
		# Translation has much higher priority than removing the final trim error.
		for axis in 3:
			var unit := Vector3.ZERO
			unit[axis] = 1.0
			force_response[axis] += unit*0.001
			moment_response[axis] += unit*0.08
		var inverse_force := force_response.inverse()
		var residual := moment_response
		for axis in 3: residual[axis] -= coupling.transposed()*inverse_force*coupling[axis]
		if absf(residual.determinant())<0.000001: break
		var linear_error := reference-force
		var angular: Vector3 = (residual.inverse()*(-moment-coupling.transposed()*inverse_force*linear_error)).limit_length(0.3)
		var linear: Vector3 = inverse_force*(linear_error-coupling*angular)
		for i in 6:
			var lever: Vector3 = outlets[i].position/WORLD_UNITS_PER_METER
			var change: Vector3 = (linear+angular.cross(lever)).slide(directions[i]).limit_length(0.2)
			var candidate := (directions[i]+change*0.65).normalized()
			directions[i] = _motor_direction(outlets[i].basis,_motor_angle(outlets[i].basis,candidate))
	var delivered := Vector3.ZERO
	for i in 6: delivered += directions[i]*engine_shares[i]
	# Lift-supported flight can trade some resultant thrust for a balanced
	# engine moment. Upright directional hover keeps its tighter force budget.
	var flight_margin := aero_authority*(1.0-minf(hover_translation.length(),1.0))
	var force_budget := lerpf(0.03,0.10,flight_margin)
	var blend := minf(1.0,force_budget/maxf(delivered.distance_to(reference),0.00001))
	for i in 6: directions[i] = original[i].lerp(directions[i],blend).normalized()

func _calculate_attitude_demand(state: PhysicsDirectBodyState3D) -> void:
	var frame := state.transform.basis.orthonormalized()
	var pilot := frame * Basis(Vector3.RIGHT, PI / 2.0 * control_blend)
	var local_rates := rotation_command*MAX_RATE
	# Existing coast/brake departure only. Ordinary powered W/S keeps the
	# DCS-style envelope below; acceleration remains finite actuator torque.
	var flip_rate := lerpf(MAX_RATE.x,FLIP_RATE,smoothstep(0.20,0.65,maneuver_hold.x))
	local_rates.x = rotation_command.x*flip_rate
	# DCS-style soft AoA protection: pitch with the trajectory instead of rotating
	# the chassis far faster than lift/thrust can bend it. No attitude/velocity snap.
	# Brake or engine cutoff releases the protection for deliberate combat stalls.
	var alignment := frame.y.dot(air_velocity.normalized())
	flight_protection = smoothstep(18,35,air_velocity.length())*smoothstep(0.05,0.45,engine_level)*(1.0-smoothstep(deg_to_rad(35),deg_to_rad(60),acos(clampf(alignment,-1,1))))*(1.0-brake_amount)
	# A latched upright thrust press must not acquire flight-path pitch commands.
	flight_protection *= 1.0-hover_translation.length()
	if flight_protection>0.0001:
		var net_acceleration := (main_force+aero_force)/body.mass+Vector3.DOWN*GRAVITY
		var path_rate := air_velocity.cross(net_acceleration).dot(pilot.x)/maxf(air_velocity.length_squared(),1.0)
		var predicted := angle_of_attack+(state.angular_velocity.dot(pilot.x)-path_rate)*0.20
		var protected_pitch := clampf(local_rates.x,path_rate+(-FLIGHT_PITCH_LIMIT-predicted)*FLIGHT_PITCH_GAIN,path_rate+(FLIGHT_PITCH_LIMIT-predicted)*FLIGHT_PITCH_GAIN)
		local_rates.x = lerpf(local_rates.x,protected_pitch,flight_protection)
	effective_rates = local_rates
	var rates := pilot*local_rates
	var upright := pilot.inverse() * frame.y.cross(Vector3.UP) * 2.5 * hover_assist
	upright *= released_axes
	rates += pilot * upright
	requested_rates = rates
	var local_accel := frame.inverse() * (rates - state.angular_velocity) * RATE_GAIN
	local_accel = local_accel.clamp(-Vector3.ONE*MAX_ANGULAR_ACCELERATION,Vector3.ONE*MAX_ANGULAR_ACCELERATION)
	# Native inertia uses world units²; controller torque is explicitly N m.
	var inertia := frame.inverse() * state.inverse_inertia_tensor.inverse() * frame
	inertia = inertia.scaled(Vector3.ONE / (WORLD_UNITS_PER_METER * WORLD_UNITS_PER_METER))
	control_torque = frame*(inertia*local_accel)
	torque_limits = Vector3(inertia.x.x,inertia.y.y,inertia.z.z)*MAX_ANGULAR_ACCELERATION

func _calculate_rcs_torque(frame: Basis, dt: float) -> void:
	var request := frame.inverse()*(control_torque-main_torque-aero_torque)
	# ponytail: lumped three-axis cold-gas actuator; per-outlet allocation only
	# if its fuel usage or force coupling becomes gameplay-relevant.
	var applied := request.clamp(-torque_limits, torque_limits)
	torque_fraction = maxf(absf(request.x) / maxf(torque_limits.x, 0.001), maxf(absf(request.y) / maxf(torque_limits.y, 0.001), absf(request.z) / maxf(torque_limits.z, 0.001)))
	torque_saturated = torque_fraction > 1.0
	rcs_request = frame*applied
	var fractions := (applied/torque_limits.max(Vector3.ONE*0.001)).abs()
	var demand := maxf(fractions.x,maxf(fractions.y,fractions.z))
	rcs_load = 0.0
	rcs_torque = Vector3.ZERO
	if demand<=RCS_DEADBAND: return
	# Low-demand correction is an actual bounded pulse, not a cosmetic flicker.
	# A longer, softer burst avoids full-capacity kicks during quiet hover.
	var duty := 1.0 if demand>=RCS_CONTINUOUS_DEMAND else RCS_TRIM_DUTY
	# Integrate the on-window over this physics step, including a cycle wrap.
	# This avoids rounding every short pulse up to an entire physics tick.
	var end := clock*RCS_PULSE_HZ
	var start := (clock-dt)*RCS_PULSE_HZ
	var on_time := (floorf(end)-floorf(start))*duty+minf(fposmod(end,1.0),duty)-minf(fposmod(start,1.0),duty)
	var fraction := clampf(on_time/maxf(dt*RCS_PULSE_HZ,0.000001),0,1)
	rcs_torque = rcs_request*(fraction/duty)
	rcs_load = demand*fraction/duty

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
