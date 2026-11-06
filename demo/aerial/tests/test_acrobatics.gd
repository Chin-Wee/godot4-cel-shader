extends "res://aerial/tests/test_animation_contract.gd"

func _run() -> void:
	create_timer(60).timeout.connect(func():
		if not finished: push_error("Acrobatics checks did not finish"); quit(1))
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_unhandled_input(false)
	mech = scene.hero
	mech.player_controlled = false
	mech.freeze = true
	fc = mech.controller
	_neutral()
	fc.grounded = false
	fc.rotation_request = Vector3.RIGHT
	for tick in 120: fc._update_maneuvers(1.0/60)
	assert(fc.maneuver_strength.x>0.99 and fc.maneuver_travel.is_zero_approx(),"Held input advanced a blocked flip")
	mech.angular_velocity = Vector3.RIGHT*2.0
	for tick in 60: fc._update_maneuvers(1.0/60)
	assert(absf(fc.maneuver_travel.x-2.0)<0.001,"Progress is not actual signed angular travel")
	fc.rotation_request = Vector3.LEFT
	fc._update_maneuvers(1.0/60)
	assert(fc.maneuver_travel.x<0.04 and fc.maneuver_recovery.x>0.9,"Reversal retained the old committed revolution")
	fc.rotation_request = Vector3.ZERO
	fc._update_maneuvers(1.0/60)
	assert(fc.maneuver_recovery.x>0.9,"Release cannot open before completing the flip")
	mech.angular_velocity = Vector3.ZERO
	for tick in 180: fc._update_maneuvers(1.0/60)
	assert(fc.maneuver_travel.is_zero_approx() and fc.maneuver_strength.length()<0.001)
	# Upright space motion, transition, plane, bank and inversion all retain
	# the aircraft's physical axes. Airspeed cannot exchange yaw and roll.
	for orientation in [Quaternion.IDENTITY, Quaternion(Vector3.RIGHT,-PI/4), Quaternion(Vector3.RIGHT,-PI/2), Quaternion(Vector3.FORWARD,PI)*Quaternion(Vector3.RIGHT,-PI/2)]:
		mech.quaternion = orientation
		var body_frame := Basis(orientation)
		for velocity in [Vector3.ZERO,Vector3.UP*60,body_frame.y*80]:
			fc.air_velocity = velocity
			fc._measure_airflow(body_frame)
			var pilot: Basis = fc.pilot_frame()
			assert(pilot.x.is_equal_approx(body_frame.x),"Pitch axis changed with flight regime")
			assert(pilot.y.is_equal_approx(body_frame.z),"Yaw swapped to the roll axis")
			assert(pilot.z.is_equal_approx(-body_frame.y),"Roll swapped to the yaw axis")
	fc.reset()
	_neutral()
	# The authoring curve is continuous at complete revolutions, including 720°.
	var profile = mech.rig.profile
	assert(profile.maneuver_shape(TAU-0.0001).distance_to(profile.maneuver_shape(0))<0.001)
	assert(profile.maneuver_shape(TAU*2).is_equal_approx(profile.maneuver_shape(0)))
	for degree in 721:
		var shape: Vector3 = profile.maneuver_shape(deg_to_rad(degree))
		assert(absf(shape.x+shape.y+shape.z-1.0)<0.0001,"Maneuver phases exceed one blend budget")
	assert(profile.maneuver_shape(deg_to_rad(180)).y>0.99)
	assert(profile.maneuver_shape(deg_to_rad(315)).z>0.9)
	# Real completed geometry differs from the long swing at inversion.
	fc.maneuver_direction = Vector2(1,0)
	fc.maneuver_strength = Vector2(1,0)
	fc.maneuver_travel = Vector2(deg_to_rad(25),0)
	await _ticks(90)
	var long_hand: Vector3 = mech.rig.arms.hands[0]
	var long_knee: float = mech.rig.legs[1].value.x
	fc.maneuver_travel.x = PI
	await _ticks(90)
	assert(mech.rig.arms.hands[0].distance_to(long_hand)>0.7,"Flip keeps one static arm pose")
	assert(mech.rig.legs[1].value.x>long_knee+0.35,"Inversion never compacts the legs")
	fc.maneuver_strength = Vector2.ONE
	fc.maneuver_direction = Vector2.ONE
	await _ticks(30)
	assert(mech.rig.motion.acro.x+mech.rig.motion.acro.y<=1.0001,"Compound corrections duplicate their blend budget")
	fc.maneuver_travel = Vector2.ZERO
	await _ticks(1)
	assert(mech.rig.motion.acro.x<=0.5001 and absf(mech.rig.motion.bank_gesture)>0.45,"Pitch preparation consumed the simultaneous bank gesture")
	# Capturing a powered, loaded bank must retain its offset silhouette even
	# after all rotational intent and maneuver envelopes have settled to zero.
	_neutral()
	fc.maneuver_strength = Vector2.ZERO
	fc.maneuver_direction = Vector2.ZERO
	fc.aero_authority = 1
	fc.engine_level = 2
	fc.thrust_level = 2
	fc.g_load = 2
	mech.quaternion = Quaternion(Vector3.FORWARD,0.7)*Quaternion(Vector3.RIGHT,-PI/2)
	await _ticks(120)
	assert(absf(mech.rig.motion.bank_gesture)>0.2,"Captured bank becomes a neutral flat pose")
	finished = true
	print("Acrobatics checks passed: actual signed progress, blocked motion, interruption, continuous revolutions, distinct swing/tuck geometry and compound limits.")
	scene.queue_free()
	await process_frame
	quit()
