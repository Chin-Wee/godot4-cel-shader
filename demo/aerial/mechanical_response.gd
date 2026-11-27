extends RefCounted

# Bounded structural modes driven by delivered flight telemetry.
# These are visual compliance estimates, not a second physics simulation.
const FREQUENCIES := [2.1, 2.3, 2.7, 2.7, 4.2, 4.2, 7.0, 7.0, 3.1, 3.3, 4.4, 4.4, 5.8, 5.8, 1.8]
const DAMPING := [0.78, 0.78, 0.68, 0.68, 0.48, 0.48, 0.36, 0.36, 0.55, 0.55, 0.50, 0.50, 0.42, 0.42, 0.85]
const LIMITS := [0.035, 0.035, 0.040, 0.040, 0.075, 0.075, 0.090, 0.090, 0.055, 0.055, 0.070, 0.070, 0.080, 0.080, 0.035]
const MODE_COUNT := 15
const ENGINE_COUNT := 6

var positions: Array[Vector3] = []
var velocities: Array[Vector3] = []
var previous_forces: Array[Vector3] = []
var previous_initialized := false
var shock := 0.0

func _init() -> void:
	for index in MODE_COUNT:
		positions.append(Vector3.ZERO)
		velocities.append(Vector3.ZERO)
	for index in ENGINE_COUNT:
		previous_forces.append(Vector3.ZERO)

func reset() -> void:
	for index in MODE_COUNT:
		positions[index] = Vector3.ZERO
		velocities[index] = Vector3.ZERO
	for index in ENGINE_COUNT:
		previous_forces[index] = Vector3.ZERO
	previous_initialized = false
	shock = 0.0

func step(sample: Dictionary, delta: float) -> Dictionary:
	if delta <= 0.0:
		return _frame()

	var acceleration: Vector3 = sample.get("local_acceleration", Vector3.ZERO)
	var jerk: Vector3 = sample.get("local_jerk", Vector3.ZERO)
	var angular_acceleration: Vector3 = sample.get("local_angular_acceleration", Vector3.ZERO)
	var g_load: float = maxf(float(sample.get("g_load", 1.0)), 0.0)
	var brake: float = clampf(float(sample.get("brake", 0.0)), 0.0, 1.0)
	var retro: float = clampf(float(sample.get("retro", 0.0)), 0.0, 1.0)
	var weight: float = maxf(float(sample.get("weight", 98100.0)), 1.0)
	var motor_forces: Array = sample.get("motor_forces", [])
	var motor_ratings: Array = sample.get("motor_ratings", [])
	var pressure_scales: Array = sample.get("pressure_scales", [])

	var left_load := 0.0
	var right_load := 0.0
	var left_slew := 0.0
	var right_slew := 0.0
	var pressure_ripple := 0.0
	var total_effort := 0.0
	var sampled_engines := mini(motor_forces.size(), ENGINE_COUNT)

	for index in sampled_engines:
		var force: Vector3 = motor_forces[index]
		var rating: float = float(motor_ratings[index]) if index < motor_ratings.size() else 65000.0
		rating = maxf(rating, 1.0)
		var normalized_load := clampf(force.length() / rating, 0.0, 1.0)
		var normalized_slew := 0.0
		if previous_initialized:
			normalized_slew = clampf((force - previous_forces[index]).length() / (rating * maxf(delta, 0.0001) * 3.0), 0.0, 1.0)
		previous_forces[index] = force
		if index % 2 == 0:
			left_load += normalized_load
			left_slew = maxf(left_slew, normalized_slew)
		else:
			right_load += normalized_load
			right_slew = maxf(right_slew, normalized_slew)
		var scale: float = float(pressure_scales[index]) if index < pressure_scales.size() else 1.0
		pressure_ripple += clampf(1.0 - scale, 0.0, 0.05)
		total_effort += force.length()

	previous_initialized = true
	var side_total := maxf(left_load + right_load, 0.001)
	var side_difference := clampf((left_load - right_load) / side_total, -1.0, 1.0)
	var load := clampf(maxf(smoothstep(1.0, 2.5, g_load), smoothstep(0.8, 3.5, total_effort / weight)), 0.0, 1.0)
	var braking_load := clampf(maxf(brake, retro) * smoothstep(1.0, 2.4, g_load), 0.0, 1.0)
	var mean_pressure_ripple := pressure_ripple / maxf(float(sampled_engines), 1.0)
	var shock_input := maxf(clampf(jerk.length() / 110.0, 0.0, 1.0), maxf(left_slew, right_slew))
	shock = maxf(shock * exp(-delta / 0.24), shock_input)

	var lateral_g := clampf(acceleration.x / 9.81, -4.0, 4.0)
	var longitudinal_g := clampf(acceleration.z / 9.81, -4.0, 4.0)
	var yaw_load := clampf(angular_acceleration.y / 5.0, -1.0, 1.0)
	var roll_load := clampf(angular_acceleration.z / 5.0, -1.0, 1.0)
	var pressure_load := mean_pressure_ripple * load

	var targets: Array[Vector3] = [
		Vector3(-longitudinal_g * 0.004 + braking_load * 0.012, lateral_g * 0.006 + side_difference * 0.010, yaw_load * 0.006),
		Vector3(longitudinal_g * 0.005 + braking_load * 0.018, -lateral_g * 0.008, yaw_load * 0.010 + shock * 0.004),
		Vector3(braking_load * 0.012 + left_load * 0.008, lateral_g * 0.004, side_difference * 0.008),
		Vector3(braking_load * 0.012 + right_load * 0.008, -lateral_g * 0.004, -side_difference * 0.008),
		Vector3(braking_load * 0.045 + shock * 0.018 + left_slew * 0.012, 0.0, side_difference * 0.008),
		Vector3(braking_load * 0.045 + shock * 0.018 + right_slew * 0.012, 0.0, -side_difference * 0.008),
		Vector3(-longitudinal_g * 0.005 - left_load * 0.008 + shock * 0.010, lateral_g * 0.003, side_difference * 0.005),
		Vector3(-longitudinal_g * 0.005 - right_load * 0.008 + shock * 0.010, -lateral_g * 0.003, -side_difference * 0.005),
		Vector3(braking_load * 0.014 + shock * 0.016 + left_slew * 0.012, side_difference * 0.014 + yaw_load * 0.003, roll_load * 0.003),
		Vector3(braking_load * 0.014 + shock * 0.016 + right_slew * 0.012, -side_difference * 0.014 + yaw_load * 0.003, -roll_load * 0.003),
		Vector3(shock * 0.030 + left_slew * 0.012, 0.0, side_difference * 0.008),
		Vector3(shock * 0.030 + right_slew * 0.012, 0.0, -side_difference * 0.008),
		Vector3(shock * 0.035 + pressure_load * 0.35, 0.0, side_difference * 0.010),
		Vector3(shock * 0.035 + pressure_load * 0.35, 0.0, -side_difference * 0.010),
		- angular_acceleration * 0.0015
	]

	for index in MODE_COUNT:
		_step_mode(index, targets[index], delta)

	return _frame(load, braking_load)

func _step_mode(index: int, target: Vector3, delta: float) -> void:
	var result := damped_step(positions[index], velocities[index], target.limit_length(LIMITS[index]),
		float(FREQUENCIES[index]), float(DAMPING[index]), delta)
	var next_position: Vector3 = result[0]
	var next_velocity: Vector3 = result[1]
	positions[index] = next_position.clamp(Vector3.ONE * -LIMITS[index], Vector3.ONE * LIMITS[index])
	velocities[index] = next_velocity.limit_length(3.0)

static func damped_step(position: Vector3, velocity: Vector3, target: Vector3,
		frequency: float, damping: float, delta: float) -> Array[Vector3]:
	if delta <= 0.0:
		return [position, velocity]
	var omega := TAU * maxf(frequency, 0.01)
	var ratio := clampf(damping, 0.0, 0.98)
	var damped_frequency := omega * sqrt(1.0 - ratio * ratio)
	var decay := exp(-ratio * omega * delta)
	var cosine := cos(damped_frequency * delta)
	var sine_over_frequency := sin(damped_frequency * delta) / maxf(damped_frequency, 0.001)
	var offset := position - target
	var next_offset := decay * (offset * cosine + (velocity + ratio * omega * offset) * sine_over_frequency)
	var next_velocity := decay * (velocity * cosine - (ratio * omega * velocity + omega * omega * offset) * sine_over_frequency)
	return [target + next_offset, next_velocity]

func _frame(load := 0.0, braking_load := 0.0) -> Dictionary:
	var legs := PackedVector3Array([
		positions[2], positions[4], positions[6],
		positions[3], positions[5], positions[7]
	])
	var arms := PackedVector4Array([
		Vector4(positions[8].x, positions[8].y, positions[8].z, positions[10].x),
		Vector4(positions[9].x, positions[9].y, positions[9].z, positions[11].x)
	])
	var wrists := PackedVector3Array([positions[12], positions[13]])
	return {
		"mechanical_pelvis": positions[0],
		"mechanical_torso": positions[1],
		"mechanical_legs": legs,
		"mechanical_arms": arms,
		"mechanical_wrists": wrists,
		"mechanical_head": positions[14],
		"mechanical_grip": clampf(load * 0.12 + braking_load * 0.18 + shock * 0.20, 0.0, 0.35),
		"mechanical_shock": shock,
		"mechanical_load": load
	}
