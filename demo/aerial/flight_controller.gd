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
const VECTOR_LIMIT := PI / 6.0
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
const HOVER_VECTOR_RESPONSE := 0.08 # AC VI directional boost reference: jets lead the slide.
# Armored Core VI Quick Boost reference; reuse the existing directional motors.
const HOVER_BURST_TIME := 0.5
const HOVER_BURST_COOLDOWN := 1.0 # Activation to activation; never auto-repeats.
const HOT_RATING := 4.0 # Hardware collective rating; never a boost multiplier.
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
const HOT_RESTART := 0.12
const HOT_RESPONSE := 0.06
const HOT_MINIMUM_ON := 0.08
const HOT_IDLE_FLOW := 0.01 # Powered engines retain pilot flow; cutoff closes valves.
const COLD_THRUST_G := 0.9
const COLD_MINIMUM_FLOW := 0.025 # Minimum useful impulse; small errors coast instead.
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
var rotation_request := Vector3.ZERO # Animation intent before control smoothing.
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
var hot_valves: Array = []
var cold_valves: Array = []
var cold_requests: Array[Vector3] = []
var cold_forces: Array[Vector3] = []
var cold_angles: Array[Vector3] = []
var command := Spring.new()
var brake := Spring.new()
var accel := Spring.new()
var last_velocity := Vector3.ZERO
var last_rates := Vector3.ZERO
var sampled := false

func configure(owner_body: RigidBody3D, display_scale: float, cold_count := 12) -> void:
	body = owner_body
	model_scale = display_scale
	for index in 6:
		motor_springs.append(Spring.new())
		motor_angles.append(Vector3.ZERO)
		motor_forces.append(Vector3.ZERO)
		hot_valves.append(Valve.new(HOT_IGNITION,HOT_RESTART,HOT_RESPONSE,HOT_RESPONSE,HOT_MINIMUM_ON))
	for index in cold_count:
		cold_valves.append(Valve.new())
		cold_requests.append(Vector3.ZERO)
		cold_forces.append(Vector3.ZERO)
		cold_angles.append(Vector3.ZERO)
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
	delivered_thrust = power*body.mass*GRAVITY if is_instance_valid(body) else 0.0
	for index in hot_valves.size():
		var share := minf(TRIM_SHARES[4],(4.0/6.0)/maxf(power,0.01))
		share = share if index>=4 else (1.0-2.0*share)/4.0
		hot_valves[index].reset(power*share/_hot_capacity(index))
		motor_forces[index] = Vector3.ZERO
		motor_angles[index] = Vector3.ZERO
	for index in cold_valves.size():
		cold_valves[index].reset()
		cold_requests[index] = Vector3.ZERO
		cold_forces[index] = Vector3.ZERO
		cold_angles[index] = Vector3.ZERO
	for spring in [command, brake, accel, translation] + motor_springs:
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
	for index in 6:
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
	hover_translation = translation.step(translation_request, dt, HOVER_VECTOR_RESPONSE)
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
	var boost := minf(HOVER_BURST_ACCELERATION*burst_amount,FORCE_SLEW_G*maxf(0,burst_remaining-HOT_RESPONSE))
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
	requested_main_force = force_target*weight
	requested_thrust = requested_main_force.length()
	var ports := []
	var combined := outlets+cold_outlets
	for i in combined.size():
		var hot := i<6
		ports.append({"basis":combined[i].basis,"lever":combined[i].position/(WORLD_UNITS_PER_METER*length_scale),
			"cone":VECTOR_LIMIT if hot else 0.0,"center":Vector3.ZERO,"gain":1.0,
			"minimum":HOT_IDLE_FLOW*_hot_capacity(i) if hot and hot_enabled else 0.0,"maximum":_hot_capacity(i) if hot and hot_enabled else (COLD_THRUST_G if not hot else 0.0),
			"off":0.0,"fuel":0.002 if hot else 0.3})
	var hot_plan := Allocator.solve(ports.slice(0,6),force_target,moment_target,along,ideal_forces,[],64)
	var hot_error := -force_target
	var hot_moment_error := -moment_target
	for i in 6:
		hot_error += hot_plan[i]
		hot_moment_error += ports[i].lever.cross(hot_plan[i])
	if hot_error.length()<0.02 and hot_moment_error.length()<0.005:
		ideal_forces = hot_plan
		for i in cold_outlets.size(): ideal_forces.append(Vector3.ZERO)
	else: ideal_forces = Allocator.solve(ports,force_target,moment_target,along,ideal_forces,[],96)
	# Choose attainable magnitude first; then slew the complete wrench request.
	# The next-step solve fits all force axes equally, so fuel savings cannot
	# suddenly drop the along-axis push or create an upward hop.
	var feasible_force := Vector3.ZERO
	for force in ideal_forces: feasible_force += force
	# Anchor slew to delivered force, not an unreachable previous request:
	# delayed valves must not accumulate a catch-up jump in the reference.
	var previous_force := force_reference if clock<=dt+0.000001 else (main_force+cold_force)/weight
	force_reference = previous_force.move_toward(feasible_force,(12.0 if jump_remaining>0 else FORCE_SLEW_G)*dt)
	force_target = force_reference
	along = Vector3.ZERO
	var seed: Array[Vector3] = []
	for i in combined.size():
		var hot := i<6
		var valve = hot_valves[i] if hot else cold_valves[i-6]
		var capacity := _hot_capacity(i) if hot else COLD_THRUST_G
		var minimum := (HOT_IDLE_FLOW if hot_enabled else 0.000001) if hot else COLD_MINIMUM_FLOW
		ports[i].fuel = 0.0 # Fuel choice is made by the horizon and hot-only solves.
		ports[i].off = valve.preview(0,dt)*capacity
		ports[i].minimum = valve.preview(minimum,dt)*capacity
		if hot and hot_enabled: ports[i].off = ports[i].minimum
		ports[i].maximum = valve.preview(1.0 if not hot or hot_enabled else minimum,dt)*capacity
		if hot:
			var spring = motor_springs[i]
			var omega := 2.0/HOVER_VECTOR_RESPONSE
			var decay := exp(-omega*dt)
			ports[i].gain = 1.0-(1.0+omega*dt)*decay
			ports[i].center = (spring.value*(1.0+omega*dt)+spring.velocity*dt)*decay
		seed.append((motor_forces[i] if hot else cold_forces[i-6])/weight)
	if not hot_enabled:
		# Coast requests zero added translation. Track unavoidable hot shutdown
		# impulse, rather than wasting cold gas trying to replace cut-off power.
		force_reference = Vector3.ZERO
		force_target = Vector3.ZERO
		for i in 6:
			ports[i].minimum = ports[i].off
			ports[i].maximum = ports[i].off
			force_target += _motor_direction(ports[i].basis,motor_angles[i])*ports[i].off
	# Fuel priority: first try hot vectoring plus unavoidable cold shutdown
	# tails. Open a cold valve only when that cannot meet the wrench tolerance.
	var off_force := Vector3.ZERO
	var off_moment := Vector3.ZERO
	var off_plan: Array[Vector3] = []
	for i in range(6,ports.size()):
		var off: Vector3 = -ports[i].basis.z*ports[i].off
		off_plan.append(off)
		off_force += off
		off_moment += ports[i].lever.cross(off)
	var plan := Allocator.solve(ports.slice(0,6),force_target-off_force,moment_target-off_moment,along,seed,ideal_forces.slice(0,6))
	var residual_force := off_force-force_target
	var residual_moment := off_moment-moment_target
	for i in 6:
		residual_force += plan[i]
		residual_moment += ports[i].lever.cross(plan[i])
	var force_error := residual_force
	var translating := burst_amount>0.0001 or rotation_request.length()>0.1
	var cold_needed := force_error.length()>(0.025 if translating else 0.04) or residual_moment.length()>(0.005 if translating else 0.02)
	# Shutdown impulse can briefly disguise a continuing need. Do not close a
	# required jet just because its minimum burn covers this one physics tick.
	var keep_open := []
	for i in range(6,ports.size()):
		var needed: bool = ideal_forces[i].length()>COLD_THRUST_G*COLD_MINIMUM_FLOW*0.5
		keep_open.append(needed)
		cold_needed = cold_needed or needed
	# Real motion, not a trim clock, opens a quiet-hover correction window.
	# Hysteresis lets the body coast through small errors without valve chatter.
	var quiet_hover := hover_assist>0.5 and rotation_request.length()<0.1 and burst_remaining<=0 and jump_remaining<=0 and horizontal.length()<0.6
	if quiet_hover:
		var tilt := acos(clampf(frame.y.y,-1,1))
		if angular_velocity.length()>0.025 or tilt>deg_to_rad(0.75): hover_cold_correction = true
		elif angular_velocity.length()<0.007 and tilt<deg_to_rad(0.3): hover_cold_correction = false
		cold_needed = cold_needed and hover_cold_correction
	else: hover_cold_correction = false
	if cold_needed:
		for i in range(6,ports.size()):
			if keep_open[i-6]: ports[i].off = ports[i].minimum
		plan = Allocator.solve(ports,force_target,moment_target,along,seed,ideal_forces)
	else: plan.append_array(off_plan)
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
		var hot := i<6
		var valve = hot_valves[i] if hot else cold_valves[i-6]
		var capacity := _hot_capacity(i) if hot else COLD_THRUST_G
		var minimum := (HOT_IDLE_FLOW if hot_enabled else 0.000001) if hot else COLD_MINIMUM_FLOW
		var command_angle := Vector3.ZERO
		if hot:
			var aim := plan[i] if plan[i].length()>0.00001 else ideal_forces[i]
			command_angle = ((Allocator.angle(ports[i].basis,aim,VECTOR_LIMIT)-ports[i].center)/ports[i].gain).limit_length(VECTOR_LIMIT)
			motor_angles[i] = motor_springs[i].step(command_angle,dt,HOVER_VECTOR_RESPONSE).limit_length(VECTOR_LIMIT)
			motor_springs[i].value = motor_angles[i]
		var flow: float = valve.command_for(plan[i].length()/capacity,dt,minimum) if hot or cold_needed else 0.0
		# Prime the next useful hot engine during ignition, while other outlets
		# balance its actual zero output. Never bypass ignition or restart time.
		if hot and hot_enabled and ports[i].maximum<0.000001 and ideal_forces[i].length()>0.001:
			flow = ideal_forces[i].length()/capacity
		if hot: flow = maxf(flow,HOT_IDLE_FLOW) if hot_enabled else 0.0
		elif cold_needed and keep_open[i-6]: flow = maxf(flow,COLD_MINIMUM_FLOW)
		var output: float = valve.step(flow,dt)
		var actual := Allocator.direction(ports[i].basis,motor_angles[i] if hot else Vector3.ZERO)*output*capacity*weight
		var moment: Vector3 = combined[i].position/WORLD_UNITS_PER_METER
		moment = moment.cross(actual)
		allocated_force += plan[i]*weight
		allocated_moment += ports[i].lever.cross(plan[i])*weight*length_scale
		if hot:
			motor_forces[i] = actual
			main_force += actual
			main_torque += moment
			delivered_thrust += actual.length()
		else:
			cold_requests[i-6] = plan[i]*weight
			cold_forces[i-6] = actual
			cold_force += actual
			rcs_torque += moment
			rcs_load = maxf(rcs_load,output)
			torque_fraction = maxf(torque_fraction,plan[i].length()/capacity)
	thrust_level = delivered_thrust/weight
	for i in 6: engine_shares[i] = motor_forces[i].length()/maxf(delivered_thrust,0.000001)
	rcs_request = rcs_torque
	torque_saturated = (control_torque-main_torque-rcs_torque-aero_torque).length()>torque_limits.length()*0.05
	motor_saturated = (force_target*weight-main_force-cold_force).length()>weight*0.05

func _motor_angle(basis: Basis, direction: Vector3) -> Vector3:
	return Allocator.angle(basis,direction,VECTOR_LIMIT)

func _motor_direction(basis: Basis, angle: Vector3) -> Vector3:
	return Allocator.direction(basis,angle)

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

func _hot_capacity(index: int) -> float:
	return maxf(HOT_RATING/6.0,HOT_RATING*TRIM_SHARES[index])

func _calculate_launch(leg_reach: bool, dt: float) -> void:
	jump_remaining = maxf(0.0,jump_remaining-dt)
	if jump_requested:
		if grounded and leg_reach and jump_remaining<=0: jump_remaining = LAUNCH_TIME
		jump_requested = false

func pilot_frame() -> Basis:
	return Basis(attitude)*PILOT_AXES
