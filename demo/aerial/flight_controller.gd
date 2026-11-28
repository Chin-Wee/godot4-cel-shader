extends RefCounted

# Behavioral references: DCS Su-27 envelope protection and Elite Dangerous
# independent attitude/momentum. One native body owns motion; this supplies forces.
const Spring = preload("res://aerial/pose_servo.gd")
const Allocator = preload("res://aerial/thruster_allocator.gd")
const Valve = preload("res://aerial/thruster_valve.gd")
const DETENTS := [0.0, 0.5, 1.0, 2.0, 4.0]
# Scene geometry is retained: 10 world units = 1 meter. Forces use N, torque N m.
const WORLD_UNITS_PER_METER := 10.0
const GRAVITY := 9.81
const TRIM_SHARES := [0.02, 0.02, 0.02, 0.02, 0.46, 0.46]
const VECTOR_LIMIT := PI / 6.0 # Offline laboratory comparison only; all live outlets are fixed.
const FIXED_FIT := Vector2(1100.0,150.0)
const MAX_RATE := Vector3(0.75, 0.8, 1.5)
# Elite Dangerous reference: fixed ship axes with or without flight assistance.
# This mech flies head-first: pitch = body X, yaw = body Z, roll = body -Y.
const PILOT_AXES := Basis(Vector3.RIGHT, PI / 2.0)
const FLIP_RATE := 1.95 # Motor-assisted somersault; fixed capsule inertia is retained.
const RATE_GAIN := 6.0
const MAX_ANGULAR_ACCELERATION := 5.0
# Feel parameters. Time in seconds, speed in m/s, accelerations in multiples of g.
const INPUT_RESPONSE := 0.14
const FULL_POWER_INPUT_RESPONSE := 0.28 # Leave torque reserve while loaded joints settle.
const BRAKE_RESPONSE := 0.28
const ENGINE_SPOOL_RATE := 3.0 # Hover multiples per second; no velocity impulses.
const HOVER_TRANSLATION_RESPONSE := 0.08 # Translation input filter, not a nozzle servo.
# Armored Core VI Quick Boost reference; reuse the existing directional motors.
const HOVER_BURST_TIME := 0.5
const HOVER_BURST_COOLDOWN := 1.0 # Activation to activation; never auto-repeats.
const HOT_RATING := 4.0 # Launch request only; individual hardware ratings limit delivery.
const HOVER_BURST_ACCELERATION := 2.4 # Requested ceiling; available balanced thrust sets output.
const HOVER_BURST_RAMP := 0.16
const HOVER_DRIFT_GAIN := 1.5
const FORCE_SLEW_G := 6.0 # Complete propulsion-reference slew, g per second.
const HOVER_TRANSLATE_G := 0.60
const FLIGHT_PITCH_LIMIT := PI / 6.0
const FLIGHT_PITCH_GAIN := 3.0
const LAUNCH_TIME := 0.5
# Fictional mech calibration, not a claim that all real engines share timings.
const HOT_IGNITION := 0.06
const HOT_RESTART := 0.18
const HOT_RESPONSE := 0.40 # Full-range pressure ramp, seconds.
const HOT_MINIMUM_ON := 0.16
const HOT_TRACKING := 6.0 # Prefer current heavy-engine pressure distribution.
const COLD_REVERSE_DWELL := 0.10
const COLD_REVERSE_OVERRIDE := 3.0
const COLD_IGNITION := 0.008
const COLD_RESTART := 0.03
const COLD_RESPONSE := 0.012
const COLD_FALL := 0.014
const COLD_MINIMUM_ON := 0.02
const COLD_FLOW_SLEW := 8.0 # Normalized cold-gas output per second; the valve itself remains fast.
const QUIET_HOVER_FORCE_ENTER := 0.012
const HOT_IDLE_FLOW := 0.01 # Powered engines retain pilot flow; cutoff closes valves.
const COLD_ACTUATION_FUEL_COST := 0.06 # Penalize cancellation in the reachable solve too.
const COLD_MINIMUM_FLOW := 0.01 # Minimum useful impulse; small errors coast instead.
# Cd stays positive in every pose. High-speed drag supplies a finite energy bound.
const AERO_AREA_M2 := 80.0
const BASE_DRAG_CD := 0.075
const HIGH_SPEED_DRAG_CD := 0.28
const BRAKE_DRAG_CD := 1.8
const LIFT_BIAS := 0.36 # Shared camber calibrated after splitting the original area.
# The same body and allocator also support the gimballed comparison path.
var articulated_flight := false
var hardware: Resource
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
var cold_force := Vector3.ZERO
var rcs_torque := Vector3.ZERO
var rcs_request := Vector3.ZERO # Delivered cold-nozzle moment.
var hover_cold_correction := false
var rcs_load := 0.0 # Delivered pulse, shared by physical torque and exhaust.
var control_torque := Vector3.ZERO # Desired total moment before actuator allocation.
var torque_limits := Vector3.ZERO # Inertia-scaled control reference, N m; outlets set actual capacity.
var torque_fraction := 0.0
var torque_saturated := false
var motor_saturated := false
var grounded := false
var jump_requested := false
var jump_remaining := 0.0
var hover_assist := 0.0
var brake_amount := 0.0
var brake_request := 0.0 # Pose preparation before aerodynamic brake smoothing.
var rotation_command := Vector3.ZERO
var rotation_request := Vector3.ZERO # Control intent after precision scaling.
var pilot_rotation_intent := Vector3.ZERO # Unscaled input for authored mechanical anticipation.
var hover_translation := Vector3.ZERO # Heading-local force request, not velocity.
var translation_request := Vector3.ZERO # Unfiltered intent for pose preparation.
var hover_actuation := Vector3.ZERO # Planned heading-local acceleration for posing.
var burst_remaining := 0.0
var burst_cooldown := 0.0
var burst_direction := Vector3.ZERO
var burst_amount := 0.0
var last_move_buttons := 0
var net_acceleration_request := Vector3.ZERO
var ideal_forces: Array[Vector3] = []
var force_reference := Vector3.ZERO # Feasible propulsion reference, in body weights.
var allocated_force := Vector3.ZERO
var allocated_moment := Vector3.ZERO
# Actual collective after per-outlet valve response, shared by physics and VFX.
var thrust_level := 1.0
var translation := Spring.new()
var flight_protection := 0.0
var requested_rates := Vector3.ZERO # World angular-rate request after protection.
var effective_rates := Vector3.ZERO # Pilot-local rate after protection and flip scaling.
var gaze_direction := Vector3.ZERO # Optional world-space vision target; no force authority.
var brake_spread := 0.0 # Completed limb projection, independent of the brake command.
var released_axes := Vector3.ONE
# Pitch/roll channels, measured in the current pilot frame. Signed, unwrapped
# travel is telemetry, never an integrated replacement for native attitude.
var maneuver_travel := Vector2.ZERO
var maneuver_strength := Vector2.ZERO
var maneuver_recovery := Vector2.ZERO
var maneuver_direction := Vector2.ZERO
var maneuver_hold := Vector2.ZERO
var acceleration := Vector3.ZERO
var angular_acceleration := Vector3.ZERO
var jerk := Vector3.ZERO
var local_acceleration := Vector3.ZERO
var local_jerk := Vector3.ZERO
var last_acceleration := Vector3.ZERO
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
var engine_shares := PackedFloat32Array()
var engine_pressure_scales := PackedFloat32Array()
var motor_angles: Array[Vector3] = []
var motor_forces: Array[Vector3] = []
# Signed residual wrench channels in the chassis frame, not nozzle pairs.
var cold_last_sign := PackedInt32Array([0,0,0,0,0,0])
var cold_active := PackedInt32Array([0,0,0,0,0,0])
var cold_reverse_age := PackedFloat32Array([0,0,0,0,0,0])
var hot_valves: Array = []
var cold_valves: Array = []
var cold_requests: Array[Vector3] = []
var cold_forces: Array[Vector3] = []
var cold_angles: Array[Vector3] = []
var cold_force_caps: Array[float] = []
var command := Spring.new()
var brake := Spring.new()
var accel := Spring.new()
var last_velocity := Vector3.ZERO
var last_rates := Vector3.ZERO
var sampled := false

func configure(owner_body: RigidBody3D, display_scale: float, profile: Resource) -> void:
	body = owner_body
	hardware = profile
	engine_shares.resize(hardware.main_booster_max_thrust.size())
	engine_pressure_scales.resize(hardware.main_booster_max_thrust.size())
	engine_pressure_scales.fill(1.0)
	for rating in hardware.main_booster_max_thrust + hardware.cold_booster_max_thrust:
		assert(is_finite(rating) and rating>=0,"Booster ratings must be finite, nonnegative Newtons")
	model_scale = display_scale
	for index in hardware.main_booster_max_thrust.size():
		motor_angles.append(Vector3.ZERO)
		motor_forces.append(Vector3.ZERO)
		hot_valves.append(Valve.new(HOT_IGNITION,HOT_RESTART,HOT_RESPONSE,HOT_RESPONSE,HOT_MINIMUM_ON))
	for index in hardware.cold_booster_max_thrust.size():
		cold_valves.append(Valve.new(COLD_IGNITION,COLD_RESTART,COLD_RESPONSE,COLD_FALL,COLD_MINIMUM_ON))
		cold_requests.append(Vector3.ZERO)
		cold_forces.append(Vector3.ZERO)
		cold_angles.append(Vector3.ZERO)
		cold_force_caps.append(0.0)
	reset()

func reset(power := 1.0) -> void:
	detent = 2
	engine_level = power
	thrust_level = power
	jump_requested = false
	jump_remaining = 0.0
	brake_amount = 0.0
	brake_request = 0.0
	maneuver_travel = Vector2.ZERO
	maneuver_strength = Vector2.ZERO
	maneuver_recovery = Vector2.ZERO
	maneuver_direction = Vector2.ZERO
	maneuver_hold = Vector2.ZERO
	clock = 0.0
	rotation_request = Vector3.ZERO
	pilot_rotation_intent = Vector3.ZERO
	hover_translation = Vector3.ZERO
	translation_request = Vector3.ZERO
	hover_actuation = Vector3.ZERO
	burst_remaining = 0.0
	burst_cooldown = 0.0
	burst_direction = Vector3.ZERO
	burst_amount = 0.0
	last_move_buttons = 0
	net_acceleration_request = Vector3.ZERO
	ideal_forces.clear()
	force_reference = body.global_basis.y*power if is_instance_valid(body) else Vector3.ZERO
	flight_protection = 0.0
	requested_rates = Vector3.ZERO
	effective_rates = Vector3.ZERO
	gaze_direction = Vector3.ZERO
	brake_spread = 0.0
	requested_main_force = Vector3.ZERO
	main_force = Vector3.ZERO
	main_torque = Vector3.ZERO
	aero_force = Vector3.ZERO
	cold_force = Vector3.ZERO
	rcs_torque = Vector3.ZERO
	rcs_request = Vector3.ZERO
	rcs_load = 0.0
	hover_cold_correction = false
	control_torque = Vector3.ZERO
	aero_torque = Vector3.ZERO
	aero_power = 0.0
	sampled = false
	jerk = Vector3.ZERO
	local_jerk = Vector3.ZERO
	last_acceleration = Vector3.ZERO
	engine_pressure_scales.fill(1.0)
	# Warm-start the original hover pair within its caps. Added foot engines
	# start closed and pass through normal ignition; live shares are solved.
	delivered_thrust = 0.0
	for index in hot_valves.size():
		var capacity := _hot_capacity(index)
		var sole_share := minf(TRIM_SHARES[4],minf(_hot_capacity(4),_hot_capacity(5))/maxf(power,0.01))
		var share := (sole_share if index>=4 else (1.0-2.0*sole_share)/4.0) if index<6 else 0.0
		hot_valves[index].reset(power*share/capacity if capacity>0 else 0.0)
		delivered_thrust += hot_valves[index].level*hot_max_thrust(index)
		motor_forces[index] = Vector3.ZERO
		motor_angles[index] = Vector3.ZERO
	thrust_level = delivered_thrust/(body.mass*GRAVITY) if is_instance_valid(body) else power
	force_reference = body.global_basis.y*thrust_level if is_instance_valid(body) else Vector3.ZERO
	for index in cold_valves.size():
		cold_valves[index].reset()
		cold_requests[index] = Vector3.ZERO
		cold_forces[index] = Vector3.ZERO
		cold_angles[index] = Vector3.ZERO
	cold_last_sign.fill(0)
	cold_active.fill(0)
	cold_reverse_age.fill(0.0)
	for spring in [command, brake, accel, translation]:
		spring.value = Vector3.ZERO
		spring.velocity = Vector3.ZERO

func step(state: PhysicsDirectBodyState3D, controls: Dictionary, outlets: Array, cold_outlets: Array, on_ground: bool, leg_reach: bool, surfaces: Array, spread: float) -> void:
	var dt := state.step
	clock += dt
	grounded = on_ground
	_measure_motion(state, dt)
	_measure_airflow(state.transform.basis.orthonormalized())
	var frame := state.transform.basis.orthonormalized()
	_calculate_hover(frame)
	_read_commands(controls, dt)
	_update_maneuvers(dt)
	brake_spread = clampf(spread,0,1)
	_calculate_aerodynamics(surfaces)
	_calculate_attitude_demand(state)
	_calculate_launch(leg_reach,dt)
	_calculate_thrusters(outlets,cold_outlets,frame,dt)
	_apply_actuator_forces(state,outlets,cold_outlets)

func step_ground(state: PhysicsDirectBodyState3D, outlets: Array, cold_outlets: Array, surfaces: Array,
		supported: bool, force_n: Vector3, moment_nm: Vector3, hot_enabled: bool) -> void:
	clock += state.step
	grounded = supported
	var frame := state.transform.basis.orthonormalized()
	_measure_motion(state,state.step)
	_measure_airflow(frame)
	_calculate_aerodynamics(surfaces)
	control_torque = moment_nm
	var weight := body.mass*GRAVITY
	torque_limits = Vector3.ONE*weight*model_scale/WORLD_UNITS_PER_METER
	var lever_scale := model_scale/WORLD_UNITS_PER_METER
	_solve_thrusters(outlets,cold_outlets,frame,state.step,force_n/weight,
		(control_torque-aero_torque)/(weight*lever_scale),Vector3.ZERO,hot_enabled,12.0,true,false)
	_apply_actuator_forces(state,outlets,cold_outlets)

func _apply_actuator_forces(state: PhysicsDirectBodyState3D, outlets: Array, cold_outlets: Array) -> void:
	for index in hot_valves.size():
		state.apply_force(motor_forces[index] * WORLD_UNITS_PER_METER, outlets[index].position)
	for index in aero_surfaces.size():
		state.apply_force(aero_surface_forces[index]*WORLD_UNITS_PER_METER,aero_surfaces[index].position)
	for index in cold_outlets.size():
		state.apply_force(cold_forces[index]*WORLD_UNITS_PER_METER,cold_outlets[index].position)
	required_force = (main_force+cold_force)/body.mass

func _measure_motion(state: PhysicsDirectBodyState3D, dt: float) -> void:
	var current_velocity := state.linear_velocity / WORLD_UNITS_PER_METER
	air_velocity = current_velocity - wind
	acceleration = (current_velocity - last_velocity) / dt if sampled else Vector3.ZERO
	angular_acceleration = (state.angular_velocity - last_rates) / dt if sampled else Vector3.ZERO
	var raw_jerk := (acceleration-last_acceleration)/dt if sampled else Vector3.ZERO
	jerk = jerk.lerp(raw_jerk,1.0-exp(-dt/0.075)) if sampled else Vector3.ZERO
	last_acceleration = acceleration
	last_velocity = current_velocity
	last_rates = state.angular_velocity
	sampled = true
	var frame := state.transform.basis.orthonormalized()
	local_velocity = frame.inverse() * current_velocity
	local_airflow = frame.inverse() * (wind - current_velocity)
	local_acceleration = accel.step(frame.inverse() * acceleration, dt, 0.12)
	local_jerk = frame.inverse() * jerk
	g_load = (acceleration - Vector3.DOWN * GRAVITY).length() / GRAVITY

func _read_commands(raw: Dictionary, dt: float) -> void:
	var precision := 0.35 if raw.get("precision", false) else 1.0
	var request := Vector3(float(raw.get("back", false)) - float(raw.get("forward", false)),
		float(raw.get("yaw_left", false)) - float(raw.get("yaw_right", false)),
		float(raw.get("left", false)) - float(raw.get("right", false)))
	var buttons := 0
	for index in 4:
		if raw.get(["forward", "back", "left", "right"][index], false): buttons |= 1 << index
	var pressed := (buttons & ~last_move_buttons) != 0
	last_move_buttons = buttons
	burst_remaining = maxf(0.0, burst_remaining - dt)
	burst_cooldown = maxf(0.0, burst_cooldown - dt)
	var planar := Vector3(-request.z, 0, request.x).limit_length(1.0)
	# Altitude compensation can lower cruise output after a boost; eligibility
	# depends on the remaining upright/low-speed support, not that spool dip.
	var hover_ready := detent > 0 and thrust_level>0.5 and hover_assist > 0.001 and hover_assist >= 0.5 * clampf(minf(engine_level,thrust_level),0,1)
	if pressed and not planar.is_zero_approx() and hover_ready and burst_cooldown <= 0.000001:
		burst_direction = planar * precision
		burst_remaining = HOVER_BURST_TIME
		burst_cooldown = HOVER_BURST_COOLDOWN
	if detent == 0: burst_remaining = minf(burst_remaining, HOVER_BURST_RAMP)
	# Smooth the force envelope on the fixed clock, including a fractional last
	# tick. Tap release cannot truncate the burst or queue another activation.
	var active_time := minf(dt, burst_remaining)
	var age := HOVER_BURST_TIME - burst_remaining
	burst_amount = smoothstep(0.0, HOVER_BURST_RAMP, age) * smoothstep(0.0, HOVER_BURST_RAMP, burst_remaining) * active_time / dt
	translation_request = burst_direction if burst_remaining > 0.0 else Vector3.ZERO
	hover_translation = translation.step(translation_request, dt, HOVER_TRANSLATION_RESPONSE)
	pilot_rotation_intent = request
	rotation_request = request * precision
	released_axes = Vector3.ONE-rotation_request.abs()
	var rotation_response := lerpf(INPUT_RESPONSE,FULL_POWER_INPUT_RESPONSE,smoothstep(2,4,thrust_level))
	rotation_command = command.step(rotation_request, dt, rotation_response)
	brake_request = float(raw.get("brake", false))
	brake_amount = clampf(brake.step(Vector3(brake_request, 0, 0), dt, BRAKE_RESPONSE).x, 0, 1)

func _measure_airflow(frame: Basis) -> void:
	var speed := air_velocity.length()
	var flight_frame := frame * PILOT_AXES
	var local := flight_frame.inverse() * air_velocity
	angle_of_attack = atan2(-local.y, -local.z) if speed > 0.1 else 0.0
	sideslip = atan2(local.x, maxf(0.01, absf(local.z))) if speed > 0.1 else 0.0
	attached_flow = (1.0 - smoothstep(FLIGHT_PITCH_LIMIT, deg_to_rad(65), absf(angle_of_attack))) * (1.0 - smoothstep(0.3, 1.2, absf(sideslip)))
	aero_authority = smoothstep(20, 70, speed) * attached_flow
	departure = smoothstep(20, 60, speed) * (1.0 - attached_flow)

func _update_maneuvers(dt: float) -> void:
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

func _calculate_hover(frame: Basis) -> void:
	var tilt := acos(clampf(frame.y.dot(Vector3.UP), -1, 1))
	var powered := clampf(engine_level,0,1) if detent>0 else 0.0
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

static func burst_acceleration(envelope: float, remaining: float, slew: float) -> float:
	# A trim engine is already burning. Reserving the full 0-to-100% response
	# time erased the entire drive phase. Limit the incremental force by its
	# remaining slew budget; real valve previews still constrain every outlet.
	return minf(HOVER_BURST_ACCELERATION*envelope,slew*maxf(remaining,0.0))

func _calculate_thrusters(outlets: Array, cold_outlets: Array, frame: Basis, dt: float) -> void:
	var weight := body.mass*GRAVITY
	var length_scale := model_scale/WORLD_UNITS_PER_METER
	var target: float = DETENTS[detent]
	engine_level = move_toward(engine_level,target,dt*ENGINE_SPOOL_RATE)
	var heading_back := frame.z.slide(Vector3.UP).normalized()
	var heading_right := Vector3.UP.cross(heading_back).normalized()
	var move := heading_right*burst_direction.x+heading_back*burst_direction.z
	var horizontal := velocity.slide(Vector3.UP)
	var drift := horizontal
	if burst_amount>0.0001: drift -= move.normalized()*horizontal.dot(move.normalized())
	var catch_force := (-drift*HOVER_DRIFT_GAIN).limit_length(GRAVITY*0.30)*minf(released_axes.x,released_axes.z)
	# Reduced trim authority needs a gentler force ramp and earlier shutdown.
	var force_slew := FORCE_SLEW_G # Main-engine response is independent of cold-gas trim reserve.
	var boost := burst_acceleration(burst_amount,burst_remaining,force_slew)
	var requested := move*GRAVITY*boost+catch_force*(1.0-burst_amount)
	requested.y = clampf(-velocity.y*1.8,-GRAVITY*0.5,GRAVITY*0.5)
	# Reserve shutdown time before the burst ends. Only point forces move the body.
	net_acceleration_request = requested
	hover_actuation = (frame.transposed()*net_acceleration_request/(GRAVITY*HOVER_TRANSLATE_G)).limit_length(1.0)
	var cruise := frame.y*engine_level*GRAVITY
	var hover_force := net_acceleration_request+Vector3.UP*GRAVITY
	var specific := cruise.lerp(hover_force,hover_assist if detent==2 else hover_assist*burst_amount)
	if jump_remaining>0: specific = Vector3.UP*GRAVITY*HOT_RATING
	if detent==0 and jump_remaining<=0: specific = Vector3.ZERO
	var hot_enabled := detent>0 or jump_remaining>0
	var force_target := (specific*body.mass-aero_force*hover_assist)/weight
	var moment_target := (control_torque-aero_torque)/(weight*length_scale)
	var along := move.normalized() if burst_amount>0.0001 else Vector3.ZERO
	var translating := burst_amount>0.0001 or rotation_request.length()>0.1
	var quiet_hover := hover_assist>0.5 and rotation_request.length()<0.1 and burst_remaining<=0 and jump_remaining<=0 and horizontal.length()<0.6
	_solve_thrusters(outlets,cold_outlets,frame,dt,force_target,moment_target,along,
		hot_enabled,12.0 if jump_remaining>0 else force_slew,translating,quiet_hover)

func _solve_thrusters(outlets: Array, cold_outlets: Array, frame: Basis, dt: float,
		force_target: Vector3, moment_target: Vector3, along: Vector3, hot_enabled: bool,
		force_slew: float, translating: bool, quiet_hover: bool) -> void:
	var hot_count := outlets.size()
	var weight := body.mass*GRAVITY
	var length_scale := model_scale/WORLD_UNITS_PER_METER
	requested_main_force = force_target*weight
	requested_thrust = requested_main_force.length()
	var combined := outlets+cold_outlets
	var horizon_ports := []
	var ports := []
	var seed: Array[Vector3] = []
	var preferred: Array[Vector3] = []
	var effective_capacities: Array[float] = []

	# Retain a theoretical horizon plan for heavy-engine ignition priming.
	# Current feasibility and cold-gas decisions use valve-reachable pressure.
	for i in combined.size():
		var hot := i<hot_count
		var index := i if hot else i-hot_count
		var capacity := _hot_capacity(index) if hot else _cold_capacity(index)
		var pressure_scale := _hot_pressure_scale(index) if hot else 1.0
		var effective_capacity := capacity*pressure_scale
		effective_capacities.append(effective_capacity)
		if hot:
			engine_pressure_scales[index] = pressure_scale
		else:
			cold_force_caps[index] = effective_capacity*weight

		var valve = hot_valves[index] if hot else cold_valves[index]
		var minimum_command := (HOT_IDLE_FLOW if hot_enabled else 0.000001) if hot else COLD_MINIMUM_FLOW
		var horizon_minimum := HOT_IDLE_FLOW*effective_capacity if hot and hot_enabled else 0.0
		var horizon_maximum := effective_capacity if (not hot or hot_enabled) else 0.0
		horizon_ports.append({
			"basis":combined[i].basis,
			"lever":combined[i].position/(WORLD_UNITS_PER_METER*length_scale),
			"cone":0.0,"center":Vector3.ZERO,"gain":1.0,
			"minimum":horizon_minimum,"maximum":horizon_maximum,"off":0.0,
			"fuel":0.002 if hot else COLD_ACTUATION_FUEL_COST
		})

		var off_output: float = valve.preview(0.0,dt)
		var minimum_output: float = valve.preview(minimum_command,dt)
		var maximum_output: float = valve.preview(1.0 if (not hot or hot_enabled) else minimum_command,dt)
		var off := off_output*effective_capacity
		var minimum := minimum_output*effective_capacity
		if hot and hot_enabled: off = maxf(off,minimum)
		minimum = maxf(minimum,off)
		if hot and not hot_enabled: maximum_output = off_output
		var axis: Vector3 = -combined[i].basis.z
		ports.append({
			"basis":combined[i].basis,
			"lever":combined[i].position/(WORLD_UNITS_PER_METER*length_scale),
			"cone":0.0,"center":Vector3.ZERO,"gain":1.0,
			"minimum":minimum,"maximum":maxf(maximum_output*effective_capacity,off),"off":off,
			"fuel":0.0 if hot else COLD_ACTUATION_FUEL_COST,
			"tracking":HOT_TRACKING if hot and hot_enabled else 0.0
		})
		preferred.append(axis*valve.level*effective_capacity if hot else Vector3.ZERO)
		var delivered: Vector3 = motor_forces[index] if hot else cold_forces[index]
		seed.append(axis*delivered.length()/weight)

	var off_force := Vector3.ZERO
	var off_moment := Vector3.ZERO
	var off_plan: Array[Vector3] = []
	for i in range(hot_count,ports.size()):
		var off: Vector3 = -ports[i].basis.z*ports[i].off
		off_plan.append(off)
		off_force += off
		off_moment += ports[i].lever.cross(off)

	if not hot_enabled:
		for i in hot_count:
			force_target += -ports[i].basis.z*ports[i].off
			ports[i].minimum = ports[i].off
			ports[i].maximum = ports[i].off
			horizon_ports[i].minimum = 0.0
			horizon_ports[i].maximum = 0.0
		force_reference = Vector3.ZERO

	var needs_ignition_prime := false
	if hot_enabled:
		for i in hot_count:
			if effective_capacities[i]>0.0 and ports[i].maximum<0.000001:
				needs_ignition_prime = true
				break
	if needs_ignition_prime:
		var horizon_hot := Allocator.solve(horizon_ports.slice(0,hot_count),force_target,moment_target,along,
			ideal_forces,[],64,FIXED_FIT)
		var horizon_error := -force_target
		var horizon_moment_error := -moment_target
		for i in hot_count:
			horizon_error += horizon_hot[i]
			horizon_moment_error += horizon_ports[i].lever.cross(horizon_hot[i])
		if horizon_error.length()<0.02 and horizon_moment_error.length()<0.005:
			ideal_forces = horizon_hot
			for i in cold_outlets.size(): ideal_forces.append(Vector3.ZERO)
		else:
			ideal_forces = Allocator.solve(horizon_ports,force_target,moment_target,along,ideal_forces,[],96,FIXED_FIT)

	# The current hot-only solve includes average valve output and unavoidable
	# cold shutdown tails. A full-capacity hot solution cannot veto a needed RCS burn.
	var reachable_hot := Allocator.solve(ports.slice(0,hot_count),force_target-off_force,
		moment_target-off_moment,along,seed.slice(0,hot_count),preferred.slice(0,hot_count),96,FIXED_FIT)
	var reachable_hot_force := Vector3.ZERO
	var reachable_hot_moment := Vector3.ZERO
	for i in hot_count:
		reachable_hot_force += reachable_hot[i]
		reachable_hot_moment += ports[i].lever.cross(reachable_hot[i])
	var reachable_force_error := force_target-reachable_hot_force-off_force
	var reachable_moment_error := moment_target-reachable_hot_moment-off_moment
	var local_rates := frame.transposed()*angular_velocity
	var pilot_intent := PILOT_AXES*rotation_request
	var deliberate_arrest := false
	for axis in 3:
		if absf(pilot_intent[axis])>0.1 and pilot_intent[axis]*local_rates[axis]<0.0:
			deliberate_arrest = true
	var force_tolerance := 0.012 if quiet_hover else 0.02
	var moment_tolerance := 0.0015 if quiet_hover or deliberate_arrest or local_rates.length()>0.08 else 0.005
	var reachable_ideal: Array[Vector3]
	if reachable_force_error.length()<force_tolerance and reachable_moment_error.length()<moment_tolerance:
		reachable_ideal = reachable_hot
		reachable_ideal.append_array(off_plan)
	else:
		reachable_ideal = Allocator.solve(ports,force_target,moment_target,along,seed,preferred,96,FIXED_FIT)
	var feasible_force := Vector3.ZERO
	for force in reachable_ideal: feasible_force += force
	var previous_force := force_reference if clock<=dt+0.000001 else (main_force+cold_force)/weight
	force_reference = previous_force.move_toward(feasible_force,force_slew*dt)
	force_target = force_reference
	along = Vector3.ZERO

	var hot_plan := Allocator.solve(ports.slice(0,hot_count),force_target-off_force,
		moment_target-off_moment,along,seed.slice(0,hot_count),preferred.slice(0,hot_count),96,FIXED_FIT)
	var hot_force := Vector3.ZERO
	var hot_moment := Vector3.ZERO
	for i in hot_count:
		hot_force += hot_plan[i]
		hot_moment += ports[i].lever.cross(hot_plan[i])
	var correction := _cold_trim(frame,force_target-hot_force-off_force,
		moment_target-hot_moment-off_moment,dt,translating,quiet_hover)
	var correction_force: Vector3 = correction[0]
	var correction_moment: Vector3 = correction[1]
	var cold_needed := not correction_force.is_zero_approx() or not correction_moment.is_zero_approx()

	# A quiet-hover correction window opens for real drift as well as angular
	# error, and closes only after linear and angular motion have settled.
	if quiet_hover:
		var tilt := acos(clampf(frame.y.y,-1,1))
		var horizontal_speed := velocity.slide(Vector3.UP).length()
		var vertical_speed := absf(velocity.y)
		if angular_velocity.length()>0.12 or tilt>deg_to_rad(1.8) or horizontal_speed>0.18 or vertical_speed>0.18:
			hover_cold_correction = true
		elif angular_velocity.length()<0.04 and tilt<deg_to_rad(0.8) and horizontal_speed<0.06 and vertical_speed<0.06:
			hover_cold_correction = false
		cold_needed = cold_needed and hover_cold_correction
	else:
		hover_cold_correction = false

	var keep_open: Array[bool] = []
	var plan: Array[Vector3]
	if cold_needed:
		var corrected_force := hot_force+off_force+correction_force
		var corrected_moment := hot_moment+off_moment+correction_moment
		var candidate_plan := Allocator.solve(ports,corrected_force,corrected_moment,along,
			seed,preferred,96,FIXED_FIT)
		for i in range(hot_count,ports.size()):
			var threshold := maxf(ports[i].off,ports[i].minimum*0.5)+0.000001
			var needed := candidate_plan[i].length()>threshold
			keep_open.append(needed)
			if needed:
				ports[i].off = ports[i].minimum
			else:
				ports[i].minimum = ports[i].off
				ports[i].maximum = ports[i].off
		plan = Allocator.solve(ports,corrected_force,corrected_moment,along,
			seed,preferred,96,FIXED_FIT)
	else:
		for i in range(hot_count,ports.size()):
			ports[i].minimum = ports[i].off
			ports[i].maximum = ports[i].off
		plan = hot_plan
		plan.append_array(off_plan)

	main_force = Vector3.ZERO
	main_torque = Vector3.ZERO
	cold_force = Vector3.ZERO
	rcs_torque = Vector3.ZERO
	delivered_thrust = 0.0
	rcs_load = 0.0
	torque_fraction = 0.0
	allocated_force = Vector3.ZERO
	allocated_moment = Vector3.ZERO
	for i in combined.size():
		var hot := i<hot_count
		var index := i if hot else i-hot_count
		var valve = hot_valves[index] if hot else cold_valves[index]
		var effective_capacity: float = effective_capacities[i]
		var minimum := (HOT_IDLE_FLOW if hot_enabled else 0.000001) if hot else COLD_MINIMUM_FLOW
		if hot: motor_angles[index] = Vector3.ZERO
		var flow := 0.0
		if effective_capacity>0 and hot:
			flow = valve.command_for(plan[i].length()/effective_capacity,dt,minimum)
		elif effective_capacity>0 and cold_needed and keep_open[index]:
			var desired_output := plan[i].length()/effective_capacity
			var shaped_output := move_toward(valve.level,desired_output,COLD_FLOW_SLEW*dt)
			flow = valve.command_for(shaped_output,dt,minimum)
		# Prime a useful heavy outlet during ignition using the theoretical plan;
		# other outlets balance its actual zero delivered pressure.
		if hot and effective_capacity>0 and hot_enabled and ports[i].maximum<0.000001 and ideal_forces[i].length()>0.001:
			flow = ideal_forces[i].length()/effective_capacity
		if hot:
			flow = maxf(flow,HOT_IDLE_FLOW) if hot_enabled and hardware.main_booster_max_thrust[index]>0 else 0.0
		elif cold_needed and keep_open[index]:
			flow = maxf(flow,COLD_MINIMUM_FLOW)
		var output: float = valve.step(flow,dt)
		var actual: Vector3 = -ports[i].basis.z*output*effective_capacity*weight
		var moment: Vector3 = combined[i].position/WORLD_UNITS_PER_METER
		moment = moment.cross(actual)
		allocated_force += plan[i]*weight
		allocated_moment += ports[i].lever.cross(plan[i])*weight*length_scale
		if hot:
			motor_forces[index] = actual
			main_force += actual
			main_torque += moment
			delivered_thrust += actual.length()
		else:
			cold_requests[index] = plan[i]*weight
			cold_forces[index] = actual
			cold_force += actual
			rcs_torque += moment
			rcs_load = maxf(rcs_load,actual.length()/maxf(cold_max_thrust(index),0.000001))
			torque_fraction = maxf(torque_fraction,plan[i].length()/maxf(effective_capacity,0.000001))
	ideal_forces = plan.duplicate()
	thrust_level = delivered_thrust/weight
	for i in hot_count: engine_shares[i] = motor_forces[i].length()/maxf(delivered_thrust,0.000001)
	rcs_request = rcs_torque
	torque_saturated = (control_torque-main_torque-rcs_torque-aero_torque).length()>torque_limits.length()*0.05
	motor_saturated = (force_target*weight-main_force-cold_force).length()>weight*0.05
func _hot_pressure_scale(index: int) -> float:
	# Small pressure dips are confined to loaded retrograde burns. The allocator
	# uses this same capacity before selecting each engine's valve command.
	var speed := velocity.length()
	if speed < 2.0: return 1.0
	var travel := velocity/speed
	var weight := maxf(body.mass*GRAVITY,1.0)
	var actual := maxf(0.0,-main_force.dot(travel))/weight
	var requested := maxf(0.0,-requested_main_force.dot(travel))/weight
	var retro := smoothstep(2.0,10.0,speed)*smoothstep(0.08,0.65,maxf(actual,requested*0.8))
	var load := smoothstep(1.15,2.8,g_load)
	var envelope := clampf(load*maxf(brake_amount,maxf(brake_request,retro)),0.0,1.0)
	if envelope <= 0.001: return 1.0
	var phase := clock*TAU*0.72+float(index)*0.91
	var pulse := pow(maxf(0.0,sin(phase)),8.0)
	var flutter := absf(sin(clock*TAU*3.7+float(index)*1.17))
	return clampf(1.0-envelope*(0.004+0.020*pulse+0.006*flutter),0.970,1.0)

func _cold_trim(frame: Basis, force: Vector3, moment: Vector3, dt: float, translating: bool, quiet_hover := false) -> Array[Vector3]:
	var local_force := frame.transposed()*force
	var local_moment := frame.transposed()*moment
	var pilot_intent := PILOT_AXES*rotation_request
	var body_rates := frame.transposed()*angular_velocity
	var moment_enter := 0.003 if quiet_hover else (0.0015 if body_rates.length()>0.08 else (0.005 if translating or body_rates.length()>0.01 else 0.02))
	var force_enter := QUIET_HOVER_FORCE_ENTER if quiet_hover else (0.025 if translating else 0.04)
	for axis in 3:
		local_force[axis] = _cold_trim_axis(axis,local_force[axis],force_enter,dt)
		# A deliberate pilot-commanded arrest is not automatic trim chatter.
		var arrest := absf(pilot_intent[axis])>0.1 and pilot_intent[axis]*body_rates[axis]<0.0 and pilot_intent[axis]*local_moment[axis]>0.0
		local_moment[axis] = _cold_trim_axis(axis+3,local_moment[axis],moment_enter,dt,arrest)
	return [frame*local_force,frame*local_moment]

func _cold_trim_axis(index: int, request: float, enter: float, dt: float, deliberate_arrest := false) -> float:
	var magnitude := absf(request)
	if magnitude<enter*0.5:
		cold_active[index] = 0
		cold_reverse_age[index] = 0.0
		return 0.0
	var direction := int(signf(request))
	if cold_active[index]==0 and magnitude<enter:
		cold_reverse_age[index] = 0.0
		return 0.0
	# Delay small repeated reversals, never a large deliberate arrest.
	if not deliberate_arrest and cold_last_sign[index]!=0 and direction!=cold_last_sign[index] and magnitude<enter*COLD_REVERSE_OVERRIDE:
		cold_reverse_age[index] += dt
		if cold_reverse_age[index]<COLD_REVERSE_DWELL:
			cold_active[index] = 0
			return 0.0
	cold_reverse_age[index] = 0.0
	cold_last_sign[index] = direction
	cold_active[index] = direction
	return request

func _calculate_attitude_demand(state: PhysicsDirectBodyState3D) -> void:
	var frame := state.transform.basis.orthonormalized()
	var pilot := frame * PILOT_AXES
	var local_rates := rotation_command*MAX_RATE
	# Existing coast/brake departure only. Ordinary powered W/S keeps the
	# DCS-style envelope below; acceleration remains finite actuator torque.
	var flip_rate := lerpf(MAX_RATE.x,FLIP_RATE,smoothstep(0.20,0.65,maneuver_hold.x))
	local_rates.x = rotation_command.x*flip_rate
	# DCS-style soft AoA protection: pitch with the trajectory instead of rotating
	# the chassis far faster than lift/thrust can bend it. No attitude/velocity snap.
	# Brake or engine cutoff releases the protection for deliberate combat stalls.
	var alignment := frame.y.dot(air_velocity.normalized())
	flight_protection = smoothstep(18,35,air_velocity.length())*smoothstep(0.05,0.45,thrust_level)*(1.0-smoothstep(deg_to_rad(35),deg_to_rad(60),acos(clampf(alignment,-1,1))))*(1.0-brake_amount)
	if flight_protection>0.0001:
		var net_acceleration := (main_force+cold_force+aero_force)/body.mass+Vector3.DOWN*GRAVITY
		var path_rate := air_velocity.cross(net_acceleration).dot(pilot.x)/maxf(air_velocity.length_squared(),1.0)
		var predicted := angle_of_attack+(state.angular_velocity.dot(pilot.x)-path_rate)*0.20
		var protected_pitch := clampf(local_rates.x,path_rate+(-FLIGHT_PITCH_LIMIT-predicted)*FLIGHT_PITCH_GAIN,path_rate+(FLIGHT_PITCH_LIMIT-predicted)*FLIGHT_PITCH_GAIN)
		local_rates.x = lerpf(local_rates.x,protected_pitch,flight_protection)
	effective_rates = local_rates
	var rates := pilot*local_rates
	var hover_up := Vector3.UP
	if hover_assist>0.5 and rotation_request.length()<0.1 and burst_remaining<=0 and jump_remaining<=0:
		hover_up = (Vector3.UP+frame*hover_actuation*HOVER_TRANSLATE_G).normalized()
	var upright := pilot.inverse() * frame.y.cross(hover_up) * 2.5 * hover_assist
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

func hot_max_thrust(index: int) -> float:
	return hardware.main_booster_max_thrust[index]

func cold_max_thrust(index: int) -> float:
	return hardware.cold_booster_max_thrust[index]

func _hot_capacity(index: int) -> float:
	return hot_max_thrust(index)/(body.mass*GRAVITY)

func cold_power_fraction() -> float:
	# The fixed full rig reserves more of the existing cold-port rating at
	# hover to cover the six feet's missing transverse couples.
	var hover_reserve := 0.23 if articulated_flight else 0.15
	return lerpf(hover_reserve,1.0,clampf(velocity.length()/40.0,0.0,1.0))

func cold_thrust_limit(index: int) -> float:
	# Speed in m/s from the native body, including vertical motion. Keep the
	# hardware rating fixed; both allocation and delivered force share this cap.
	return cold_max_thrust(index)*cold_power_fraction()

func _cold_capacity(index: int) -> float:
	return cold_thrust_limit(index)/(body.mass*GRAVITY)

func _calculate_launch(leg_reach: bool, dt: float) -> void:
	jump_remaining = maxf(0.0,jump_remaining-dt)
	if jump_requested:
		if grounded and leg_reach and jump_remaining<=0: jump_remaining = LAUNCH_TIME
		jump_requested = false

func pilot_frame() -> Basis:
	return Basis(attitude)*PILOT_AXES
