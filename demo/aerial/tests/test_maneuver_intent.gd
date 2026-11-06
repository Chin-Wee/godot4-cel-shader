extends "res://aerial/tests/test_animation_contract.gd"

# Frozen native rig: isolate pose causality and interruption. The separate
# input replays validate the same code with live forces and moving hardpoints.
func _flight(speed: Vector3, output := 2.0) -> void:
	_neutral()
	mech.rig.reset()
	mech.quaternion = Quaternion(Vector3.RIGHT,-PI/2)
	mech.linear_velocity = speed*fc.WORLD_UNITS_PER_METER
	fc.engine_level = output
	fc.thrust_level = output
	fc.detent = 3 if output==2 else 4
	fc.main_force = Vector3.FORWARD*mech.mass*fc.GRAVITY*output
	fc.requested_main_force = fc.main_force
	fc.aero_force = Vector3.ZERO
	fc.aero_authority = 1
	fc.local_airflow = mech.basis.inverse()*-speed
	fc.local_acceleration = Vector3.ZERO

func _hover_departures() -> void:
	# No delivered lateral force, velocity or acceleration: the pose must lead
	# motion from the real controller's unfiltered directional request alone.
	for direction in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
		_neutral()
		mech.rig.reset()
		fc.engine_level = 1
		fc.thrust_level = 1
		fc.detent = 2
		fc.hover_assist = 1
		await _ticks(120)
		var hands: Vector3 = mech.rig.arms.hands[0]
		fc.translation_request = direction
		await _ticks(9)
		assert(fc.velocity.is_zero_approx() and fc.local_acceleration.is_zero_approx())
		assert(mech.rig.chest.value.length()>0.025 and mech.rig.arms.hands[0].distance_to(hands)>0.08,"Hover input has no early whole-body preparation")
		await _ticks(36)
		var torso: int = mech.skeleton.find_bone("Torso")
		var lean: Vector3 = mech.skeleton.global_basis.orthonormalized()*mech.bone_poses[torso].basis.orthonormalized()*mech.skeleton.get_bone_global_rest(torso).basis.orthonormalized().inverse()*Vector3.UP
		assert(lean.dot(direction)>0.10,"Torso leans away from the intended movement")
		var leading := 1 if direction==Vector3.RIGHT else 0
		var trailing := 1-leading
		assert(mech.rig.legs[leading*3+1].value.x-mech.rig.legs[trailing*3+1].value.x>0.45,"Hover departure lacks a gathering and extended leg")
		var upright_frame: Basis = (mech.global_basis.inverse()*mech.skeleton.global_basis).orthonormalized()
		var first: Vector3 = upright_frame*mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.knee_bones[leading])].origin
		var second: Vector3 = upright_frame*mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.knee_bones[trailing])].origin
		assert(first.y>second.y+0.35,"Gather gesture changes angles without lifting the displayed knee")
		var previous: Vector3 = mech.rig.legs[1].value
		fc.translation_request = -direction
		await _ticks(1)
		assert(previous.distance_to(mech.rig.legs[1].value)<0.04,"Reversal snaps the knee roles")
		fc.translation_request = Vector3.ZERO
		await _ticks(180)
		assert(mech.rig.motion.reach.is_zero_approx() and mech.rig.motion.gather.is_zero_approx(),"Unloaded release invents a braking catch")

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
	await _hover_departures()
	_flight(Vector3(0,0,-70))
	await _ticks(120)
	var before_brake: Vector3 = mech.rig.arms.hands[0]
	fc.brake_request = 1
	await _ticks(12)
	assert(fc.brake_amount==0 and mech.rig.motion.flare>0.95,"Braking pose waits for delivered drag")
	assert(mech.rig.arms.hands[0].distance_to(before_brake)>0.15,"Brake intent has no early arm preparation")
	_flight(Vector3(0,0,-70))
	await _ticks(150)
	var cruise_hand: Vector3 = mech.rig.arms.hands[0]
	var cruise_knee: float = mech.rig.legs[1].value.x
	fc.detent = 4
	fc.requested_main_force = Vector3.FORWARD*mech.mass*fc.GRAVITY*4
	await _ticks(6)
	assert(mech.rig.motion.prepare>0.3,"Throttle intent has no preparation before delivery")
	assert(mech.rig.arms.hands[0].distance_to(cruise_hand)>0.1)
	fc.engine_level = 4
	fc.thrust_level = 4
	fc.main_force = fc.requested_main_force
	fc.local_acceleration = Vector3(0,25,0)
	await _ticks(45)
	assert(mech.rig.motion.drive>0.85)
	assert(mech.rig.legs[1].value.x>cruise_knee+0.2,"Hard acceleration never compresses the legs")
	assert(absf(mech.rig.arms.hands[0].x)>cruise_hand.x+0.5,"Hard acceleration never opens the aft arm stroke")
	assert(absf(_asymmetry())>0.15,"Aligned hard acceleration remains perfectly mirrored")
	fc.local_acceleration = Vector3.ZERO
	await _ticks(180)
	assert(mech.rig.motion.drive<0.01,"Constant power retains a transient acceleration squat")
	assert(mech.rig.arms.hands[0].distance_to(cruise_hand)<0.15)
	# Opposing burn: brace direction comes from actual thrust/travel geometry.
	_flight(Vector3(0,0,70))
	await _ticks(120)
	assert(mech.rig.motion.retro>0.95 and mech.rig.legs[1].value.x>0.8)
	assert(mech.rig.arms.hands[0].z>2.5)
	assert(absf(_asymmetry())>0.4)
	assert(absf(mech.rig.arms.finger_curl[0]-mech.rig.arms.finger_curl[1])>0.15,"Both hands perform the same brace")
	# Only the opposed component disappears; total travel remains substantial.
	mech.linear_velocity = Vector3(250,0,0)
	fc.local_airflow = Vector3(-25,0,0)
	fc.local_acceleration = Vector3(0,20,0)
	await _ticks(75)
	assert(mech.rig.motion.retro<0.03 and fc.velocity.length()>20,"Release incorrectly waits for total speed to reach zero")
	assert(mech.rig.motion.drive>0.8 and mech.rig.arms.hands[0].z<1,"Reverse brace never unwinds into outgoing acceleration")
	var lead: float = mech.rig.lead_side
	for tick in 60:
		mech.linear_velocity = Vector3(0.001 if tick%2 else -0.001,0,0)
		await _ticks(1)
	assert(mech.rig.lead_side==lead,"Near-zero velocity chatters the lead side")
	fc.detent = 0
	fc.engine_level = 0
	fc.thrust_level = 0
	fc.main_force = Vector3.ZERO
	fc.requested_main_force = Vector3.ZERO
	fc.local_acceleration = Vector3.ZERO
	await _ticks(180)
	assert(mech.rig.motion.drive<0.01 and mech.rig.motion.retro<0.01)
	assert(mech.rig.effort_phase==&"rest","Canceled effort never settles")
	# Oblique geometry selects complementary roles even without steering input.
	_flight(Vector3(35,0,-60))
	await _ticks(150)
	var left: Vector3 = mech.rig.arms.hands[0]
	var right: Vector3 = mech.rig.arms.hands[1]
	assert(mech.rig.motion.redirect>0.3 and mech.rig.motion.asymmetry>0.3)
	_flight(Vector3(-35,0,-60))
	await _ticks(150)
	var mirrored_left: Vector3 = mech.rig.arms.hands[0]*Vector3(-1,1,1)
	assert(mirrored_left.distance_to(right)<0.05,"Mirrored slip has inconsistent limb roles")
	assert((mech.rig.arms.hands[1]*Vector3(-1,1,1)).distance_to(left)<0.05)
	finished = true
	print("Maneuver intent checks passed: proactive four-way hover knee/arm/torso preparation, bounded reversal/release, anticipatory throttle, loaded acceleration, staggered reverse brace, independent hands, component-wise reversal, interruption, quiet zero-speed roles and mirrored oblique flight.")
	scene.queue_free()
	await process_frame
	quit()
