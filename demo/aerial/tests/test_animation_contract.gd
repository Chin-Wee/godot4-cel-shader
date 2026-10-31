extends SceneTree

# Pose contract over a frozen native actor. Actual forces/momentum/contact are
# covered by test_flight_pose and the shared native input replays.
var scene
var mech
var fc
var finished := false

func _initialize() -> void: call_deferred("_run")

func _ticks(count: int, mirror_request := true) -> void:
	if mirror_request: fc.rotation_request = fc.rotation_command
	for tick in count:
		fc.clock += 1.0/60
		var previous: Vector3 = mech.rig.arms.hands[0]
		mech.update_animation(1.0/60)
		assert(previous.distance_to(mech.rig.arms.hands[0])<=0.7,"Displayed hand teleported")
		var sum := 0.0
		for weight in mech.rig.behavior_weights:
			assert(weight>=0 and weight<=1.0001)
			sum += weight
		assert(absf(sum-1)<0.0001)
		for side in 2:
			for joint in 3:
				var value: Vector3 = mech.rig.legs[side*3+joint].value
				assert(value.is_equal_approx(mech.rig.profile.limit_joint(value,side,joint)))
		await process_frame

func _neutral() -> void:
	fc.hover_assist = 0
	fc.engine_level = 0
	fc.detent = 0
	fc.aero_authority = 0
	fc.brake_amount = 0
	fc.departure = 0
	fc.local_acceleration = Vector3.ZERO
	fc.angular_acceleration = Vector3.ZERO
	fc.rotation_command = Vector3.ZERO
	fc.rotation_request = Vector3.ZERO
	fc.rcs_torque = Vector3.ZERO
	fc.torque_fraction = 0
	fc.local_airflow = Vector3.ZERO
	fc.leg_force = Vector3.ZERO
	fc.main_force = Vector3.ZERO
	fc.g_load = 1
	fc.air_density = 1.225
	mech.quaternion = Quaternion.IDENTITY
	mech.linear_velocity = Vector3.ZERO
	mech.angular_velocity = Vector3.ZERO

func _asymmetry() -> float:
	return mech.rig.arms.hands[0].z-mech.rig.arms.hands[1].z

func _run() -> void:
	create_timer(60).timeout.connect(func():
		if not finished: push_error("Animation contract check did not finish"); quit(1))
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_unhandled_input(false)
	mech = scene.hero
	mech.player_controlled = false
	mech.freeze = true
	mech.reset_flight(Vector3(175,5000,340))
	fc = mech.controller
	_neutral()
	fc.engine_level = 1
	fc.detent = 2
	fc.hover_assist = 1
	await _ticks(150)
	assert(mech.rig.behavior_weights[0]>0.99)
	for side in 2: assert(mech.rig.arms.hands[side].y< -0.6,"Hover uses skydiver arms")
	var before_input: Vector3 = mech.rig.arms.hands[0]
	fc.rotation_request = Vector3(0,1,0)
	await _ticks(12,false) # Heavy powered shoulders prepare within 0.2 seconds.
	assert(fc.rotation_command.is_zero_approx() and mech.angular_velocity.is_zero_approx())
	assert(mech.rig.arms.hands[0].distance_to(before_input)>0.2,"Brief input is lost behind the physics control filter")
	fc.rotation_request = Vector3.ZERO
	await _ticks(60)
	var resting_knee: float = mech.rig.legs[1].value.x
	fc.leg_force = Vector3.UP*mech.mass*9.81*4
	await _ticks(14)
	assert(mech.rig.motion.launch>0.95 and mech.rig.legs[1].value.x<resting_knee-0.15,"Ground push does not extend the legs")
	fc.leg_force = Vector3.ZERO
	await _ticks(100)
	assert(mech.rig.motion.launch<0.01,"Launch pose never recovers into support")
	fc.rotation_command = Vector3(0,1,0)
	await _ticks(45)
	var hover_stroke := absf(_asymmetry())
	assert(hover_stroke>0.35,"Hover does not actively steer its shoulders")
	# Powered useful airflow: pose follows chassis orientation, including inversion.
	_neutral()
	fc.engine_level = 2
	fc.detent = 3
	fc.aero_authority = 1
	fc.local_airflow = Vector3(0,-80,0)
	mech.linear_velocity = Vector3(0,0,-800)
	mech.quaternion = Quaternion(Vector3.RIGHT,-PI/2)
	await _ticks(150)
	assert(mech.rig.behavior_weights[1]>0.99 and mech.rig.motion.track>0.99)
	var fighter_hand: Vector3 = mech.rig.arms.hands[0]
	assert(fighter_hand.z< -0.5 and fighter_hand.distance_to(before_input)>2,"Displayed hover and cruise silhouettes still collapse into the same pose")
	var fighter_knee: Vector3 = mech.rig.legs[1].value
	mech.quaternion = Quaternion(Vector3.FORWARD,PI)*mech.quaternion
	await _ticks(120)
	assert(mech.rig.behavior_weights[1]>0.99 and mech.rig.motion.hover<0.01,"Inversion selected hover")
	assert(mech.rig.arms.hands[0].distance_to(fighter_hand)<0.1 and mech.rig.legs[1].value.distance_to(fighter_knee)<0.1,"Neutral inverted flight changed its body-relative shape")
	# Cutoff retains aerodynamic tracking; broadside lateral coast is not a fall.
	fc.engine_level = 0
	fc.detent = 0
	await _ticks(150)
	assert(mech.rig.behavior_weights[2]>0.99 and mech.rig.motion.box<0.01)
	fc.local_airflow = Vector3(0,0,80)
	await _ticks(120)
	assert(mech.rig.behavior_weights[2]>0.99 and mech.rig.motion.box<0.01,"Thrust cutoff became instant spread")
	# Vacuum independent rotation: active initiation, coast and arrest, no air cues.
	_neutral()
	fc.air_density = 0
	await _ticks(120)
	fc.rotation_command = Vector3(0,1,0)
	await _ticks(30)
	var start := _asymmetry()
	assert(absf(start)>1.0 and hover_stroke>0.35 and mech.rig.chest.value.y>0.08,"Held aerial yaw has no active asymmetric stroke")
	mech.angular_velocity = fc.pilot_frame()*Vector3(0,fc.MAX_RATE.y,0)
	await _ticks(30)
	assert(_asymmetry()*start>0 and absf(_asymmetry())>0.5 and absf(_asymmetry())<absf(start)*0.95,"Held turn loses its readable asymmetric posture")
	fc.rotation_command = Vector3.ZERO
	await _ticks(36) # Powered shoulders decelerate into the opposing arrest stroke.
	assert(_asymmetry()*start<0 and absf(_asymmetry())>0.7,"Coast release has no arrest stroke")
	mech.linear_velocity = Vector3(0,-800,0)
	fc.local_airflow = Vector3(0,0,80)
	await _ticks(100)
	assert(mech.rig.motion.box<0.01 and mech.rig.behavior_weights[3]<0.01,"Vacuum descent became atmospheric skydiving")
	# Falling into relative wind establishes box, arch and wrist cupping.
	_neutral()
	mech.linear_velocity = Vector3(0,-750,0)
	fc.local_airflow = Vector3(0,0,75)
	await _ticks(150)
	assert(mech.rig.behavior_weights[3]>0.99 and mech.rig.motion.box>0.99)
	assert(mech.rig.chest.value.x< -0.06)
	for side in 2:
		assert(mech.rig.arms.hands[side].y>2.5 and mech.rig.arms.wrists[side].value.x< -0.15,"Skydiver arms/wrists remain passive")
		var index: int = mech.skeleton.find_bone(mech.rig.profile.arm_ends[side])
		var parent: Basis = mech.bone_poses[mech.skeleton.get_bone_parent(index)].basis
		var local: Quaternion = (parent.inverse()*mech.bone_poses[index].basis).get_rotation_quaternion()
		var rest: Quaternion = mech.skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		assert(local.angle_to(rest)>0.15 and local.angle_to(rest)<0.4,"Completed skeleton omitted the wrist layer")
	var fall_knee: float = mech.rig.legs[1].value.x
	fc.local_airflow = Vector3(0,-75,0)
	await _ticks(120)
	assert(mech.rig.motion.box<0.01 and mech.rig.motion.track>0.99)
	assert(mech.rig.legs[1].value.x<fall_knee-0.5,"Tracking did not lengthen the legs")
	for side in 2: assert(mech.rig.arms.hands[side].y< -2.3,"Tracking did not tuck both arms")
	fc.brake_amount = 1
	await _ticks(120)
	for side in 2: assert(absf(mech.rig.arms.hands[side].x)>5.0,"Braking did not flare the hands outside the shoulders")
	# Fast powered misalignment receives independent control, never hover catch.
	_neutral()
	fc.engine_level = 2
	fc.detent = 3
	fc.local_airflow = Vector3(0,0,80)
	fc.departure = 1
	mech.linear_velocity = Vector3(800,0,0)
	await _ticks(120)
	assert(mech.rig.behavior_weights[0]<0.01 and mech.rig.behavior_weights[2]>0.99,"Fast stall became upright hover")
	assert(mech.rig.motion.box<0.01,"Powered misalignment became unpowered falling")
	finished = true
	print("Animation contract checks passed: launch extension/recovery, distinct hover/fighter/coast/fall styles, inversion, cutoff continuity, start/coast/stop, vacuum exclusion, box/arch/wrists, tracking/flare and fast-stall exclusion.")
	scene.queue_free()
	await process_frame
	quit()
