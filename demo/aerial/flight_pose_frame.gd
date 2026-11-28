class_name FlightPoseFrame
extends RefCounted

# One physical-state snapshot per physics tick. Consumers treat captured values
# as immutable; derived animation weights are owned by FlightPose.
var delta: float
var clock: float
var attitude: Quaternion
var pilot_frame: Basis
var velocity: Vector3
var angular_velocity: Vector3
var angular_acceleration: Vector3
var local_acceleration: Vector3
var local_jerk: Vector3
var local_airflow: Vector3
var air_density: float
var pilot_rotation_intent: Vector3
var rotation_request: Vector3
var effective_rates: Vector3
var translation_request: Vector3
var hover_actuation: Vector3
var g_load: float
var main_force: Vector3
var requested_main_force: Vector3
var aero_force: Vector3
var cold_force: Vector3
var rcs_torque: Vector3
var torque_fraction: float
var thrust_level: float
var detent: int
var detent_output: float
var jump_remaining: float
var hover_assist: float
var aero_authority: float
var brake_amount: float
var brake_request: float
var motor_saturated: bool
var motor_forces: Array[Vector3] = []
var motor_ratings := PackedFloat32Array()
var engine_pressure_scales := PackedFloat32Array()
var maneuver_strength: Vector2
var maneuver_recovery: Vector2
var maneuver_direction: Vector2
var maneuver_travel: Vector2
var gaze_direction: Vector3
var control_torque: Vector3
var main_torque: Vector3
var aero_torque: Vector3
var torque_limits: Vector3
var delivered_thrust: float
var body_mass: float
var gravity: float
var max_rate: Vector3
var articulated_flight: bool
var joint_moments: Dictionary

static func capture(controller, loads: Dictionary, step_delta: float) -> FlightPoseFrame:
	var frame := FlightPoseFrame.new()
	frame.delta = step_delta
	frame.clock = controller.clock
	frame.attitude = controller.attitude
	frame.pilot_frame = controller.pilot_frame()
	frame.velocity = controller.velocity
	frame.angular_velocity = controller.angular_velocity
	frame.angular_acceleration = controller.angular_acceleration
	frame.local_acceleration = controller.local_acceleration
	frame.local_jerk = controller.local_jerk
	frame.local_airflow = controller.local_airflow
	frame.air_density = controller.air_density
	frame.pilot_rotation_intent = controller.pilot_rotation_intent
	frame.rotation_request = controller.rotation_request
	frame.effective_rates = controller.effective_rates
	frame.translation_request = controller.translation_request
	frame.hover_actuation = controller.hover_actuation
	frame.g_load = controller.g_load
	frame.main_force = controller.main_force
	frame.requested_main_force = controller.requested_main_force
	frame.aero_force = controller.aero_force
	frame.cold_force = controller.cold_force
	frame.rcs_torque = controller.rcs_torque
	frame.torque_fraction = controller.torque_fraction
	frame.thrust_level = controller.thrust_level
	frame.detent = controller.detent
	frame.detent_output = float(controller.DETENTS[controller.detent])
	frame.jump_remaining = controller.jump_remaining
	frame.hover_assist = controller.hover_assist
	frame.aero_authority = controller.aero_authority
	frame.brake_amount = controller.brake_amount
	frame.brake_request = controller.brake_request
	frame.motor_saturated = controller.motor_saturated
	for force in controller.motor_forces:
		frame.motor_forces.append(force)
	frame.motor_ratings = controller.hardware.main_booster_max_thrust.duplicate()
	frame.engine_pressure_scales = controller.engine_pressure_scales.duplicate()
	frame.maneuver_strength = controller.maneuver_strength
	frame.maneuver_recovery = controller.maneuver_recovery
	frame.maneuver_direction = controller.maneuver_direction
	frame.maneuver_travel = controller.maneuver_travel
	frame.gaze_direction = controller.gaze_direction
	frame.control_torque = controller.control_torque
	frame.main_torque = controller.main_torque
	frame.aero_torque = controller.aero_torque
	frame.torque_limits = controller.torque_limits
	frame.delivered_thrust = controller.delivered_thrust
	frame.body_mass = controller.body.mass
	frame.gravity = controller.GRAVITY
	frame.max_rate = controller.MAX_RATE
	frame.articulated_flight = controller.articulated_flight
	frame.joint_moments = loads.duplicate(true)
	frame.joint_moments.make_read_only()
	return frame
