extends Resource

# MechAsset's measured skeleton frame is +Z forward. Behavior stays in body/SI
# coordinates; this resource owns asset calibration and mechanical limits.
@export var torso_bones := PackedStringArray(["PelvisBase", "Low_Waist", "Torso_WaistConnect", "Torso"])
@export var torso_weights := PackedFloat32Array([0.14, 0.24, 0.30, 0.32])
@export var thigh_bones := PackedStringArray(["Thigh.L", "Thigh.R"])
@export var knee_bones := PackedStringArray(["Knee.L", "Knee.R"])
@export var foot_bones := PackedStringArray(["Feet.L", "Feet.R"])
@export var arm_roots := PackedStringArray(["Shoulder.L", "Shoulder.R"])
@export var arm_middles := PackedStringArray(["ArmJoint.L", "ArmJoint.R"])
@export var arm_ends := PackedStringArray(["Hands.L", "Hands.R"])
# Thigh, knee, ankle offsets in skeleton axes. Mirror Z for the right leg.
# Retain the calibrated hover anchor: physical heel/calf outlets move with it.
@export var hover_pose := PackedVector3Array([Vector3(-0.25,0,0.12), Vector3(0.42,0,0), Vector3.ZERO])
@export var stream_pose := PackedVector3Array([Vector3.ZERO, Vector3(0.12,0,0), Vector3(0.32,0,0)])
@export var spread_pose := PackedVector3Array([Vector3(-0.88,0,0.46), Vector3(1.07,0,0), Vector3(-0.24,0,0)])
@export var coast_pose := PackedVector3Array([Vector3(-0.32,0,0.16), Vector3(0.58,0,0), Vector3(-0.06,0,0)])
@export var landing_pose := PackedVector3Array([Vector3(-0.36,0,0.20), Vector3(0.68,0,0), Vector3(-0.10,0,0)])
@export var joint_min := PackedVector3Array([Vector3(-1.15,-0.5,-0.65), Vector3(0.05,0,0), Vector3(-0.65,-0.2,-0.2)])
@export var joint_max := PackedVector3Array([Vector3(0.65,0.5,0.65), Vector3(1.65,0,0), Vector3(0.5,0.2,0.2)])
@export var leg_response := Vector3(0.28,0.32,0.36)
@export var joint_speed := Vector3(2.1,2.4,2.6) # Radians/second.
@export var body_response := 0.16
@export var weapon_response := 0.12
@export var receiver_point := Vector3(-2.4,5.661993,-0.832874)
@export var muzzle_point := Vector3(-2.412204,-0.004719,0.436474)
@export var hand_guard := Vector3(2.5,-1.7,0.8)
@export var free_hand_spread := Vector3(4.2,-0.6,1.3)
@export var rifle_low_ready := Vector3(-1.8,-2.1,0.7)
@export var rifle_stream_ready := Vector3(-1.3,-1.6,0.5)
@export var rifle_raised := Vector3(-0.4,0.1,-0.2)
@export var leg_airflow_gain := 0.22
# Measured minimum of both rigid foot meshes, in Feet.L/R bone space.
@export var sole_offset := Vector3(0,0,-0.227218)
@export var ground_sink := 0.18 # Actor units, multiplied by display scale.
@export var impact_sink := 0.10
@export var foot_response := 0.10
@export var landing_lead := 0.8
@export var walk_stance_fraction := 0.55
@export var sole_tilt_limit := 0.5

func leg_target(weights: PackedFloat32Array, side: int, joint: int) -> Vector3:
	var poses := [hover_pose, stream_pose, spread_pose, coast_pose, landing_pose]
	var result := Vector3.ZERO
	for index in poses.size(): result += poses[index][joint] * weights[index]
	if side == 1: result.z = -result.z
	return result

func limit_joint(target: Vector3, side: int, joint: int) -> Vector3:
	if side == 1: target.z = -target.z
	target = target.clamp(joint_min[joint],joint_max[joint])
	if side == 1: target.z = -target.z
	return target
