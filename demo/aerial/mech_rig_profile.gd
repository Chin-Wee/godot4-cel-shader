extends Resource

# MechAsset's measured skeleton frame is +Z forward. Behavior stays in body/SI
# coordinates; this resource owns asset calibration and mechanical limits.
# Newton ratings, in aerial_mech MOUNTS / COLD_MOUNTS order. Same housing, same cap.
@export var main_booster_max_thrust := PackedFloat32Array([65000,65000,65000,65000,65000,65000,65000,65000,65000,65000])
@export var cold_booster_max_thrust := PackedFloat32Array([90000,90000,90000,90000,90000,90000,90000,90000,90000,90000,90000,90000])
@export var torso_bones := PackedStringArray(["PelvisBase", "Low_Waist", "Torso_WaistConnect", "Torso"])
@export var torso_weights := PackedFloat32Array([0.14, 0.24, 0.30, 0.32])
@export var thigh_bones := PackedStringArray(["Thigh.L", "Thigh.R"])
@export var knee_bones := PackedStringArray(["Knee.L", "Knee.R"])
@export var foot_bones := PackedStringArray(["Feet.L", "Feet.R"])
@export var arm_roots := PackedStringArray(["Shoulder.L", "Shoulder.R"])
@export var arm_middles := PackedStringArray(["ArmJoint.L", "ArmJoint.R"])
@export var arm_ends := PackedStringArray(["Hands.L", "Hands.R"])
# MSFS 2020 surface-force principle, reduced to torso and four limb panels.
# Fractions share the controller's existing total area; no duplicated body lift.
@export var aero_bones := PackedStringArray(["Torso","ArmJoint.L","ArmJoint.R","Shin.L","Shin.R"])
@export var aero_fractions := PackedFloat32Array([0.5,0.075,0.075,0.175,0.175])
@export var aero_incidence := PackedFloat32Array([0.04,0.15,0.15,0.12,0.12]) # Neutral stream calibration, radians.
# Thigh, knee, ankle offsets in skeleton axes. Mirror Z for the right leg.
# Retain the calibrated hover anchor: physical heel/calf outlets move with it.
@export var hover_pose := PackedVector3Array([Vector3(-1.0,0,0.12), Vector3(1.17,0,0), Vector3.ZERO])
@export var stream_pose := PackedVector3Array([Vector3.ZERO, Vector3(0.12,0,0), Vector3(0.32,0,0)])
@export var spread_pose := PackedVector3Array([Vector3(-0.88,0,0.46), Vector3(1.07,0,0), Vector3(-0.24,0,0)])
@export var fall_pose := PackedVector3Array([Vector3(0.08,0,0.28),Vector3(1.30,0,0),Vector3(-0.20,0,0)])
# Back-facing air: knees gather toward the torso instead of folding behind it.
@export var back_fall_pose := PackedVector3Array([Vector3(-0.98,0,0.22),Vector3(1.35,0,0),Vector3(0.20,0,0)])
@export var layout_pose := PackedVector3Array([Vector3(-0.08,0,0.12),Vector3(0.18,0,0),Vector3(0.08,0,0)])
@export var coast_pose := PackedVector3Array([Vector3(-0.32,0,0.16), Vector3(0.58,0,0), Vector3(-0.06,0,0)])
@export var landing_pose := PackedVector3Array([Vector3(-0.36,0,0.20), Vector3(0.68,0,0), Vector3(-0.10,0,0)])
@export var launch_pose := PackedVector3Array([Vector3(-0.03,0,0.08),Vector3(0.05,0,0),Vector3.ZERO])
# Coupled flexion keeps the calf/heel axes close to the main thrust line.
@export var retro_pose := PackedVector3Array([Vector3(-0.62,0,0.20),Vector3(1.02,0,0),Vector3(-0.35,0,0)])
@export var drive_pose := PackedVector3Array([Vector3(-0.32,0,0.13),Vector3(0.58,0,0),Vector3(-0.20,0,0)])
@export var joint_min := PackedVector3Array([Vector3(-1.15,-0.5,-0.65), Vector3(0.05,0,0), Vector3(-0.65,-0.2,-0.2)])
@export var joint_max := PackedVector3Array([Vector3(0.65,0.5,0.65), Vector3(1.65,0,0), Vector3(0.5,0.2,0.2)])
@export var leg_response := Vector3(0.32,0.38,0.42)
@export var joint_speed := Vector3(1.6,1.8,1.5) # Radians/second.
# Radians: aft swing, outward elevation, elbow flexion. No elbow-pole guesses.
@export var arm_hover := Vector3(0.04,0.38,0.95)
@export var arm_stream := Vector3(0.35,0.20,0.20)
@export var arm_brake := Vector3(-0.15,1.35,1.10)
@export var arm_retro := Vector3(-0.2,0.95,1.05)
@export var arm_drive := Vector3(0.65,0.45,0.38)
@export var arm_prepare := Vector3(-0.10,0.6,1.0)
@export var effort_response := Vector3(0.07,0.13,0.20) # Prepare, reverse load, acceleration.
@export var role_stagger := 0.24 # Coupled thigh/knee offset, radians.
@export var slide_knees := Vector2(0.50,-0.36) # Gathering and extended leg offsets, radians.
@export var slide_lean := Vector2(0.38,0.42) # Forward/back and lateral chest lean, radians.
@export var slide_response := 0.22 # Knee commitment; normal recovery uses leg_response.
@export var high_thrust_tuck := 0.65 # Draw leg outlets forward under full engine load.
@export var high_thrust_reverse := 0.8 # Present canted calf ports for a reverse hover push.
@export var arm_coast := Vector3(-0.10,0.6,0.95)
@export var arm_land := Vector3(-0.15,0.55,0.95)
@export var arm_box := Vector3(-0.35,1.05,1.40)
@export var arm_back := Vector3(-0.55,1.10,0.75)
@export var arm_back_twist := -0.15
@export var brake_projection := Vector2(0.30,0.60) # Completed lateral arm projection / reach.
@export var head_min := Vector3(-0.95,-0.80,-0.15)
@export var head_max := Vector3(0.50,0.80,0.15)
@export var head_response := 0.18 # Eyes/head lead the slower shoulders and pelvis.
@export var head_speed := 1.6
@export var arm_box_twist := 0.55 # Humerus rotation; forearms rise, elbows stay below shoulders.
@export var arm_speed := 1.8 # Radians per second; powered joints hold their targets.
@export var hover_leg_motion := 0.04
@export var maneuver_leg_motion := 0.22
@export var leg_airflow_gain := 0.22
# Measured minimum of both rigid foot meshes, in Feet.L/R bone space.
@export var sole_offset := Vector3(0,0,-0.227218)
@export var ground_sink := 0.18 # Actor units, multiplied by display scale.
@export var impact_sink := 0.10
@export var foot_response := 0.10
@export var landing_lead := 0.8
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

# Overgrowth authored corrections: long swing, compact inversion, open recovery.
# World Athletics pole-vault reference supplies the long-leg swing/inversion cue.
# No timeline advances these weights; the controller supplies actual angular travel.
func maneuver_shape(travel: float) -> Vector3:
	var angle := rad_to_deg(fposmod(travel,TAU))
	var tuck := smoothstep(35,140,angle)*(1.0-smoothstep(260,340,angle))
	var opening := smoothstep(260,310,angle)*(1.0-smoothstep(340,360,angle))
	return Vector3((1.0-tuck)*(1.0-opening),tuck*(1.0-opening),opening)

func limit_head(target: Vector3) -> Vector3:
	return target.clamp(head_min,head_max)
