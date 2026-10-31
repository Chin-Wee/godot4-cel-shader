extends "res://aerial/tests/test_animation_contract.gd"

# Frozen native rig: isolate pose causality and interruption. The separate
# input replays validate the same code with live forces and moving hardpoints.
func _flight(speed: Vector3, output := 2.0) -> void:
	_neutral()
	mech.rig.reset()
	mech.quaternion = Quaternion(Vector3.RIGHT,-PI/2)
	mech.linear_velocity = speed*fc.WORLD_UNITS_PER_METER
	fc.engine_level = output
	fc.detent = 3 if output==2 else 4
	fc.main_force = Vector3.FORWARD*mech.mass*fc.GRAVITY*output
	fc.requested_main_force = fc.main_force
	fc.aero_force = Vector3.ZERO
	fc.aero_authority = 1
	fc.local_airflow = mech.basis.inverse()*-speed
	fc.local_acceleration = Vector3.ZERO

func _run() -> void:
	create_timer(60).timeout.connect(func():
		if not finished: push_error("Maneuver intent check did not finish"); quit(1))
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_unhandled_input(false)
	mech = scene.hero
	mech.player_controlled = false
	mech.freeze = true
	mech.reset_flight(Vector3(175,5000,340))
	fc = mech.controller
	_flight(Vector3(0,0,-70))
	await _ticks(150)
	var cruise_hand: Vector3 = mech.rig.arms.hands[0].value
	var cruise_knee: float = mech.rig.legs[1].value.x
	fc.detent = 4
	fc.requested_main_force = Vector3.FORWARD*mech.mass*fc.GRAVITY*4
	await _ticks(6)
	assert(mech.rig.motion.prepare>0.3,"Throttle intent has no preparation before delivery")
	assert(mech.rig.arms.hands[0].value.distance_to(cruise_hand)>0.1)
	fc.engine_level = 4
	fc.main_force = fc.requested_main_force
	fc.local_acceleration = Vector3(0,25,0)
	await _ticks(45)
	assert(mech.rig.motion.drive>0.85)
	assert(mech.rig.legs[1].value.x>cruise_knee+0.2,"Hard acceleration never compresses the legs")
	assert(absf(mech.rig.arms.hands[0].value.x)>cruise_hand.x+0.5,"Hard acceleration never opens the aft arm stroke")
	assert(absf(_asymmetry())>0.15,"Aligned hard acceleration remains perfectly mirrored")
	fc.local_acceleration = Vector3.ZERO
	await _ticks(180)
	assert(mech.rig.motion.drive<0.01,"Constant power retains a transient acceleration squat")
	assert(mech.rig.arms.hands[0].value.distance_to(cruise_hand)<0.15)
	# Opposing burn: brace direction comes from actual thrust/travel geometry.
	_flight(Vector3(0,0,70))
	await _ticks(120)
	assert(mech.rig.motion.retro>0.95 and mech.rig.legs[1].value.x>0.8)
	assert(mech.rig.arms.hands[0].value.z>2.5)
	assert(absf(_asymmetry())>0.4)
	assert(absf(mech.rig.arms.finger_curl[0]-mech.rig.arms.finger_curl[1])>0.15,"Both hands perform the same brace")
	# Only the opposed component disappears; total travel remains substantial.
	mech.linear_velocity = Vector3(250,0,0)
	fc.local_airflow = Vector3(-25,0,0)
	fc.local_acceleration = Vector3(0,20,0)
	await _ticks(75)
	assert(mech.rig.motion.retro<0.03 and fc.velocity.length()>20,"Release incorrectly waits for total speed to reach zero")
	assert(mech.rig.motion.drive>0.8 and mech.rig.arms.hands[0].value.z<1,"Reverse brace never unwinds into outgoing acceleration")
	var lead: float = mech.rig.lead_side
	for tick in 60:
		mech.linear_velocity = Vector3(0.001 if tick%2 else -0.001,0,0)
		await _ticks(1)
	assert(mech.rig.lead_side==lead,"Near-zero velocity chatters the lead side")
	fc.detent = 0
	fc.engine_level = 0
	fc.main_force = Vector3.ZERO
	fc.requested_main_force = Vector3.ZERO
	fc.local_acceleration = Vector3.ZERO
	await _ticks(180)
	assert(mech.rig.motion.drive<0.01 and mech.rig.motion.retro<0.01)
	assert(mech.rig.effort_phase==mech.rig.EffortPhase.REST,"Canceled effort never settles")
	# Oblique geometry selects complementary roles even without steering input.
	_flight(Vector3(35,0,-60))
	await _ticks(150)
	var left: Vector3 = mech.rig.arms.hands[0].value
	var right: Vector3 = mech.rig.arms.hands[1].value
	assert(mech.rig.motion.redirect>0.3 and mech.rig.motion.asymmetry>0.3)
	_flight(Vector3(-35,0,-60))
	await _ticks(150)
	var mirrored_left: Vector3 = mech.rig.arms.hands[0].value*Vector3(-1,1,1)
	assert(mirrored_left.distance_to(right)<0.05,"Mirrored slip has inconsistent limb roles")
	assert((mech.rig.arms.hands[1].value*Vector3(-1,1,1)).distance_to(left)<0.05)
	finished = true
	print("Maneuver intent checks passed: anticipatory throttle, loaded acceleration, staggered reverse brace, independent hands, component-wise reversal, interruption, quiet zero-speed roles and mirrored oblique flight.")
	scene.queue_free()
	await process_frame
	quit()
