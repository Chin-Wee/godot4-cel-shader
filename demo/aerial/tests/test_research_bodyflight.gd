extends "res://aerial/tests/test_animation_contract.gd"

func _run() -> void:
	create_timer(90).timeout.connect(func():
		if not finished: push_error("Research body-flight checks did not finish"); quit(1))
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_unhandled_input(false)
	mech = scene.hero
	mech.player_controlled = false
	mech.freeze = true
	mech.reset_flight(Vector3(175,9000,340))
	fc = mech.controller
	_neutral()
	# Actual commanded flip rate must not read as an animation overspeed.
	fc.rotation_request = Vector3.RIGHT
	fc.effective_rates = Vector3.RIGHT*fc.FLIP_RATE
	mech.angular_velocity = Vector3.RIGHT*fc.FLIP_RATE
	await _ticks(45,false)
	assert(mech.rig.motion.steer.x>0.6,"Correct flip rate produces an opposing stroke")
	fc.effective_rates = Vector3.ZERO
	fc.rotation_request = Vector3.ZERO
	await _ticks(15,false)
	assert(mech.rig.motion.steer.x< -0.8,"Release omits its rate-error counterstroke")
	_neutral()
	# Head anticipates longitudinal aircraft roll before the chassis moves;
	# this is rotation around the torso's Y axis, independent of flight mode.
	fc.rotation_request = Vector3(0,0,-1)
	await _ticks(9,false)
	assert(mech.rig.head.value.y>0.06 and mech.angular_velocity.is_zero_approx(),"Head waits for body rotation instead of leading intention")
	fc.rotation_request = Vector3.ZERO
	await _ticks(180,false)
	var quiet: Vector3 = mech.rig.head.value
	await _ticks(60,false)
	assert(mech.rig.head.value.distance_to(quiet)<0.001,"Quiet head swims without intent")
	# Camera input supplies vision intent without a head-to-camera/body loop.
	mech.player_controlled = true
	var camera_before: Transform3D = scene.camera.global_transform
	var body_before: Transform3D = mech.global_transform
	scene.camera.orbit(Vector2(120,-30))
	scene._physics_process(1.0/60)
	assert(fc.gaze_direction.is_equal_approx(scene.camera.look_direction()))
	assert(scene.camera.global_transform==camera_before and mech.global_transform==body_before)
	mech.player_controlled = false
	# Camera gaze affects the displayed neck, not the physical control surfaces.
	var skeleton_frame: Basis = mech.skeleton.global_basis.orthonormalized()
	fc.gaze_direction = skeleton_frame*Vector3(0.6,0.2,1).normalized()
	await _ticks(120)
	assert(mech.rig.head.value.y>0.2 and mech.rig.head.value.x< -0.05,"Vision target does not turn the neck")
	var surfaces: Array = mech.aerodynamic_surfaces()
	fc.gaze_direction = skeleton_frame*Vector3(-0.6,0.2,1).normalized()
	await _ticks(120)
	assert(mech.rig.head.value.y< -0.2,"Head cannot look in the opposite direction")
	var opposite: Array = mech.aerodynamic_surfaces()
	for i in surfaces.size():
		assert(surfaces[i].normal.distance_to(opposite[i].normal)<0.0001,"Head look moves an air-control surface")
		assert(surfaces[i].position.distance_to(opposite[i].position)<0.001,"Head look moves a physical hardpoint")
	for direction in [Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK]:
		fc.gaze_direction = skeleton_frame*direction
		for tick in 30:
			var previous: Vector3 = mech.rig.head.value
			await _ticks(1)
			assert(mech.rig.head.value.is_equal_approx(mech.rig.profile.limit_head(mech.rig.head.value)))
			assert(mech.rig.head.value.distance_to(previous)<=mech.rig.profile.head_speed/60+0.0001,"Head snaps across a neck limit")
	_neutral()
	mech.linear_velocity = Vector3.DOWN*500
	fc.local_airflow = Vector3(0,0,50)
	await _ticks(180)
	assert(mech.rig.motion.belly>0.99 and mech.rig.motion.back<0.01)
	var belly_hip: float = mech.rig.legs[0].value.x
	var belly_head: Vector3 = mech.rig.head.value
	fc.local_airflow = Vector3(0,0,-50)
	await _ticks(180)
	assert(mech.rig.motion.back>0.99 and mech.rig.motion.belly<0.01)
	assert(mech.rig.legs[0].value.x<belly_hip-0.6,"Back-facing air still uses belly-fall legs")
	assert(mech.rig.head.value.distance_to(belly_head)>0.08,"Head ignores belly/back presentation")
	_neutral()
	mech.quaternion = Quaternion(Vector3.FORWARD,0.7)*Quaternion(Vector3.RIGHT,-PI/2)
	mech.linear_velocity = Vector3.FORWARD*800
	fc.aero_authority = 1
	fc.local_airflow = Vector3(0,-80,0)
	fc.g_load = 2
	await _ticks(180)
	assert(mech.rig.motion.fighter<0.001 and mech.rig.motion.air_control>0.99 and absf(mech.rig.motion.bank_gesture)>0.2,"Engine cutoff erases a lift-loaded bank")
	fc.aero_authority = 0
	await _ticks(30)
	assert(mech.rig.motion.air_control>0.99,"Stalled but air-loaded body loses all aerodynamic expression")
	fc.air_density = 0
	await _ticks(120)
	assert(absf(mech.rig.motion.bank_gesture)<0.01,"Vacuum keeps a wind-driven bank cue")
	# Geometry supplies the extra drag; the key alone cannot change it.
	_neutral()
	mech.quaternion = Quaternion(Vector3.RIGHT,-PI/2)
	mech.linear_velocity = Vector3.FORWARD*700
	fc.air_velocity = Vector3.FORWARD*70
	fc.local_airflow = Vector3(0,-70,0)
	await _ticks(180)
	var neutral_spread: float = mech.rig.arms.brake_spread()
	fc.brake_spread = neutral_spread
	fc._calculate_aerodynamics(mech.aerodynamic_surfaces())
	var neutral_force: Vector3 = fc.aero_force
	fc.brake_request = 1
	fc.brake_amount = 1
	fc._calculate_aerodynamics(mech.aerodynamic_surfaces())
	assert(fc.aero_force.distance_to(neutral_force)<0.01,"Brake command adds drag before the limbs move")
	await _ticks(150)
	var open_spread: float = mech.rig.arms.brake_spread()
	assert(open_spread>0.8 and open_spread>neutral_spread+0.5,"Completed flare does not expose more area")
	fc.brake_spread = open_spread
	fc._calculate_aerodynamics(mech.aerodynamic_surfaces())
	assert(fc.aero_force.dot(Vector3.FORWARD)<neutral_force.dot(Vector3.FORWARD)-50000 and fc.aero_power<0,"Actual spreading fails to add passive braking")
	fc.brake_request = 0
	fc.brake_amount = 0
	fc.local_acceleration = Basis(fc.attitude).inverse()*Vector3.BACK*12
	await _ticks(180)
	assert(mech.rig.motion.flare<0.01 and mech.rig.arms.brake_spread()<0.3,"Braking drag keeps its own flare latched after release")
	# Useful air/rate tracking supports a long layout; vacuum retains a tuck.
	fc.aero_authority = 1
	fc.local_acceleration = Vector3.ZERO
	fc.rotation_request = Vector3.RIGHT
	fc.effective_rates = Vector3.RIGHT*fc.FLIP_RATE
	mech.angular_velocity = fc.pilot_frame()*Vector3.RIGHT*fc.FLIP_RATE
	fc.maneuver_strength = Vector2(1,0)
	fc.maneuver_direction = Vector2(1,0)
	fc.maneuver_travel = Vector2(PI,0)
	fc.local_airflow = Vector3(0,-80,0)
	await _ticks(180,false)
	assert(mech.rig.motion.layout>0.9,"Air-supported flip never selects a long-body layout")
	var long_knee: float = mech.rig.legs[1].value.x
	fc.air_density = 0
	await _ticks(180,false)
	assert(mech.rig.motion.layout<0.01 and mech.rig.legs[1].value.x>long_knee+0.4,"Low-airload flip cannot gather into a compact shape")
	finished = true
	print("Research body-flight checks passed: consistent rate feedback, proactive bounded gaze/head motion, signed belly/back, unpowered air-loaded bank, completed-geometry braking/release and adaptive layouts.")
	scene.queue_free()
	await process_frame
	quit()
