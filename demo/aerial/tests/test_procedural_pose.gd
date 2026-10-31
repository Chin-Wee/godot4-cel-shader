extends SceneTree

const Servo = preload("res://aerial/pose_servo.gd")
var scene
var mech
var completed := false

func _initialize() -> void: call_deferred("_run")

func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func _pose_ticks(count: int) -> void:
	for tick in count:
		mech.controller.clock += 1.0/60.0
		mech.update_animation(1.0/60.0)
		for side in 2:
			for joint in 3:
				var value: Vector3 = mech.rig.legs[side*3+joint].value
				assert(value.is_equal_approx(mech.rig.profile.limit_joint(value,side,joint)),"Servo crossed a mechanical joint limit")
		await process_frame

func _run() -> void:
	create_timer(60).timeout.connect(func():
		if not completed: push_error("Procedural pose checks did not finish"); quit(1))
	var servo := Servo.new()
	for tick in 90:
		var previous := servo.value
		servo.step(Vector3(5 if tick<45 else -5,0,0),1.0/60.0,0.3,2.0)
		assert(servo.value.distance_to(previous)<=2.0/60.0+0.00001)
		assert(servo.velocity.length()<=2.00001)
	# The secondary layer overshoots mildly, settles and remains independent of
	# fixed-step frequency. It never supplies rigid-body forces or collisions.
	var secondary := Servo.new()
	var peak := 0.0
	for tick in 240:
		secondary.follow(Vector3.ONE,1.0/60.0,1.35,0.68,INF)
		peak = maxf(peak,secondary.value.x)
	assert(peak>1.01 and peak<1.15 and secondary.value.distance_to(Vector3.ONE)<0.001)
	var slow := Servo.new()
	var fast := Servo.new()
	for tick in 30: slow.follow(Vector3.ONE,1.0/30.0,1.35,0.68,INF)
	for tick in 120: fast.follow(Vector3.ONE,1.0/120.0,1.35,0.68,INF)
	assert(slow.value.distance_to(fast.value)<0.0001)
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_unhandled_input(false)
	mech = scene.hero
	mech.player_controlled = false
	await _ticks(3)
	mech.freeze = true
	mech.reset_flight(Vector3(175,5000,340))
	var fc = mech.controller
	fc.hover_assist = 1
	fc.engine_level = 1
	fc.aero_authority = 0
	fc.departure = 0
	fc.brake_amount = 0
	fc.local_acceleration = Vector3.ZERO
	fc.angular_acceleration = Vector3.ZERO
	fc.local_airflow = Vector3.ZERO
	fc.g_load = 1
	await _pose_ticks(180)
	var still: Vector3 = mech.rig.legs[0].value
	var hand_before: Vector3 = mech.rig.arms.hands[0].value
	var chest_before: Vector3 = mech.rig.chest.value
	var transform: Transform3D = mech.global_transform
	await _pose_ticks(90)
	assert(mech.rig.legs[0].value.distance_to(still)>0.01,"Hover legs never transfer weight")
	assert(mech.rig.arms.hands[0].value.distance_to(hand_before)>0.2,"Hover arms remain static")
	assert(mech.rig.chest.value.distance_to(chest_before)>0.005,"Hover torso never counterbalances the limbs")
	# Check completed joint geometry, not just target numbers: relaxed elbows
	# must hang near the ribs and behind the hands instead of turning out.
	var torso_inverse: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Torso")].affine_inverse()
	for side in 2:
		var shoulder: Vector3 = torso_inverse*mech.bone_poses[mech.rig.arms.ik.get_root_bone(side)].origin
		var elbow: Vector3 = torso_inverse*mech.bone_poses[mech.rig.arms.ik.get_middle_bone(side)].origin
		var hand: Vector3 = torso_inverse*mech.bone_poses[mech.rig.arms.ik.get_end_bone(side)].origin
		assert(absf(elbow.x-shoulder.x)<0.65 and elbow.z<shoulder.z-0.35,"Relaxed elbow flares outward")
		assert(hand.y < -2.2 and hand.z>elbow.z+0.5,"Relaxed arm does not hang with a forward forearm")
	assert(mech.global_transform.is_equal_approx(transform) and mech.linear_velocity.is_zero_approx(),"Presentation moved the physical body")
	assert(mech.rig.contacts.probe_count==0 and not mech.rig.contacts.planted[0])
	assert(not mech.skeleton.find_child("GUN",false,false).visible and not scene.has_method("fire_weapon"))
	fc.brake_amount = 1
	fc.local_airflow = Vector3(0,0,60)
	fc.g_load = 0
	await _pose_ticks(120)
	assert(mech.rig.legs[0].value.distance_to(still)>0.25,"Spread posture has no readable leg change")
	for side in 2: assert(absf(mech.rig.arms.hands[side].value.x)>4.0,"Braking did not open both arms")
	assert(mech.rig.motion.compression==0,"Freefall created powered G-load compression")
	var sum := 0.0
	for weight in mech.rig.posture_weights:
		assert(weight>=0 and weight<=1.0001)
		sum += weight
	assert(absf(sum-1)<0.0001)
	# No steering input: measured acceleration alone must produce a mirrored
	# balance catch, persist briefly after release, then settle back to neutral.
	fc.brake_amount = 0
	fc.local_airflow = Vector3.ZERO
	fc.hover_assist = 0
	fc.g_load = 1
	fc.local_acceleration = Vector3(14,0,0)
	await _pose_ticks(60)
	var lateral_catch: float = (mech.rig.arms.hands[0].value.x+mech.rig.arms.hands[1].value.x)*0.5
	assert(lateral_catch>0.4,"Arms did not balance a change in lateral momentum")
	fc.local_acceleration = Vector3(-14,0,0)
	await _pose_ticks(60)
	assert((mech.rig.arms.hands[0].value.x+mech.rig.arms.hands[1].value.x)*0.5 < -0.4,"Balance catch did not reverse with acceleration")
	fc.local_acceleration = Vector3(0,0,12)
	await _pose_ticks(60)
	var forward_catch: float = mech.rig.arms.hands[0].value.z
	fc.local_acceleration = Vector3(0,0,-12)
	await _pose_ticks(60)
	assert(forward_catch-mech.rig.arms.hands[0].value.z>0.7,"Arms do not distinguish acceleration from deceleration")
	fc.local_acceleration = Vector3.ZERO
	await _pose_ticks(1)
	assert(mech.rig.arms.hands[0].value.z<0.7,"Balance catch snapped away on release")
	await _pose_ticks(120)
	assert(mech.rig.arms.hands[0].value.distance_to(mech.rig.profile.arm_coast)<0.01,"Arms never settled after momentum stopped changing")
	fc.g_load = 0
	fc.local_acceleration = Vector3.DOWN*9.81
	await _pose_ticks(60)
	assert(mech.rig.arms.hands[0].value.distance_to(mech.rig.profile.arm_coast)<0.01,"Freefall gravity created a false arm balance catch")
	fc.g_load = 1
	fc.local_acceleration = Vector3.ZERO
	# Steering anticipates chassis movement; left/right poses must be distinct.
	fc.brake_amount = 0
	fc.local_airflow = Vector3.ZERO
	fc.hover_assist = 0
	fc.rotation_command = Vector3(0,1,0)
	await _pose_ticks(90)
	var left_yaw: float = mech.rig.arms.hands[0].value.z-mech.rig.arms.hands[1].value.z
	assert(left_yaw>1 and mech.rig.chest.value.y>0.04)
	fc.rotation_command = Vector3(0,-1,0)
	await _pose_ticks(90)
	assert(mech.rig.arms.hands[0].value.z-mech.rig.arms.hands[1].value.z < -1)
	fc.rotation_command = Vector3(-1,0,0)
	await _pose_ticks(90)
	var pitch_down: float = (mech.rig.arms.hands[0].value.y+mech.rig.arms.hands[1].value.y)*0.5
	assert(mech.rig.chest.value.x < -0.04)
	fc.rotation_command = Vector3(1,0,0)
	await _pose_ticks(90)
	assert((mech.rig.arms.hands[0].value.y+mech.rig.arms.hands[1].value.y)*0.5 > pitch_down+1.5,"Pitch does not actively reach/tuck both arms")
	assert(mech.rig.chest.value.x>0.04)
	fc.rotation_command = Vector3(0,0,1)
	await _pose_ticks(90)
	assert(absf(mech.rig.arms.hands[1].value.x)-absf(mech.rig.arms.hands[0].value.x)>0.8,"Roll has no inside/outside arm choreography")
	mech.angular_velocity = Vector3(0,0,0.8)
	fc.rotation_command = Vector3.ZERO
	fc.angular_acceleration = Vector3(0,0,-4)
	await _pose_ticks(1)
	assert(mech.rig.motion.roll_stop>0.3 and mech.rig.arms.hands[0].velocity.length()>0.1,"Roll release lost follow-through")
	mech.angular_velocity = Vector3.ZERO
	fc.angular_acceleration = Vector3.ZERO
	# With no motion or load response, the pilot must still initiate a visible
	# shoulder stroke. Matching angular speed relaxes it; release counterstrokes.
	fc.rotation_command = Vector3(0,1,0)
	await _pose_ticks(24)
	var start_stroke: float = mech.rig.arms.hands[0].value.z-mech.rig.arms.hands[1].value.z
	assert(start_stroke>2 and mech.rig.chest.value.y>0.08,"Upper body waits for inertia instead of initiating the turn")
	mech.angular_velocity = fc.pilot_frame()*Vector3(0,fc.MAX_RATE.y,0)
	await _pose_ticks(30)
	var coast_stroke: float = mech.rig.arms.hands[0].value.z-mech.rig.arms.hands[1].value.z
	assert(coast_stroke>0.1 and coast_stroke<start_stroke*0.5,"Held turn never relaxes toward neutral")
	fc.rotation_command = Vector3.ZERO
	await _pose_ticks(18)
	assert(mech.rig.arms.hands[0].value.z-mech.rig.arms.hands[1].value.z < -0.8 and mech.rig.chest.value.y<0,"Turn release does not actively counterstroke")
	mech.angular_velocity = Vector3.ZERO
	mech.linear_velocity = Vector3(0,-750,0)
	fc.engine_level = 0
	fc.detent = 0
	fc.local_airflow = Vector3(0,0,75)
	await _pose_ticks(120)
	assert(mech.rig.motion.box>0.9 and mech.rig.chest.value.x< -0.06,"Broadside freefall never establishes an arch")
	for side in 2:
		assert(mech.rig.arms.hands[side].value.y>2.5,"Freefall forearms do not rise toward head level")
	fc.local_airflow = Vector3(0,-75,0)
	fc.aero_authority = 1
	await _pose_ticks(120)
	assert(mech.rig.motion.box<0.01)
	for side in 2: assert(mech.rig.arms.hands[side].value.y< -2.3,"Head-first tracking did not tuck the arms")
	fc.aero_authority = 0
	# A real opposing force/travel geometry selects retro bracing, independently
	# of Shift and independent of the animation's world orientation.
	mech.quaternion = Quaternion(Vector3.RIGHT,PI/2)
	mech.linear_velocity = Vector3(0,0,-700)
	fc.main_force = Vector3(0,0,mech.mass*9.81*2)
	fc.engine_level = 2
	fc.local_airflow = Vector3(0,70,0)
	await _pose_ticks(120)
	assert(mech.rig.motion.retro>0.95)
	for side in 2: assert(mech.rig.arms.hands[side].value.z>2,"Retro thrust has no forward arm brace")
	mech.quaternion = Quaternion(Vector3.FORWARD,PI)*Quaternion(Vector3.RIGHT,-PI/2)
	fc.local_airflow = Vector3(0,-80,0)
	fc.aero_authority = 1
	await _pose_ticks(120)
	for pose in mech.bone_poses.values(): assert(pose.origin.is_finite() and pose.basis.is_finite())
	assert(mech.rig.contacts.state==0 and mech.rig.contacts.probe_count==0)
	# Actual capsule landing on a flat fixture; ray prediction cannot plant early.
	var platform := StaticBody3D.new()
	platform.collision_layer = 2
	platform.collision_mask = 8
	platform.position = Vector3(175,3100,340)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300,20,300)
	shape.shape = box
	platform.add_child(shape)
	scene.add_child(platform)
	mech.reset_flight(Vector3(175,3270,340),Quaternion.IDENTITY,Vector3(0,-8,0))
	fc.detent = 0
	fc.engine_level = 0
	mech.freeze = false
	var saw_preparation := false
	var saw_impact := false
	for tick in 240:
		await _ticks(1)
		if not mech.native_support:
			assert(not mech.rig.contacts.planted[0] and not mech.rig.contacts.planted[1],"Prediction planted a foot before physical support")
			saw_preparation = saw_preparation or mech.rig.contacts.preparation>0.1
		saw_impact = saw_impact or mech.rig.contacts.impact>0.1
	assert(saw_preparation and saw_impact,"Landing never prepared and absorbed the impact")
	assert(mech.rig.contacts.touchdown_count==1,"One landing fired touchdown more than once")
	assert(mech.native_support and mech.rig.contacts.state==1)
	for side in 2:
		assert(mech.rig.contacts.planted[side])
		var index: int = mech.skeleton.find_bone(mech.rig.profile.foot_bones[side])
		var sole: Vector3 = mech.skeleton.global_transform*(mech.bone_poses[index]*mech.rig.profile.sole_offset)
		assert(absf(sole.y-3110)<0.6,"Foot sole failed to meet the actual floor")
	# Plants follow their platform and survive its removal without an origin snap.
	mech.freeze = true
	var before: Vector3 = mech.rig.contacts.plant_position(0)
	platform.position.x += 2
	await _pose_ticks(30)
	assert(mech.rig.contacts.plant_position(0).distance_to(before+Vector3(2,0,0))<0.001)
	var last: Vector3 = mech.rig.contacts.plant_position(0)
	platform.queue_free()
	await process_frame
	await _pose_ticks(60)
	assert(mech.rig.contacts.plant_position(0).distance_to(last)<0.001)
	assert(mech.rig.contacts.weights[0].value.x<0.001)
	assert(mech.rig.contacts.state==0)
	# Both the body and floor lean 25 degrees. Re-rotating Godot's world-space
	# contact normal would incorrectly reject this valid support (cos(50)<0.65).
	platform = StaticBody3D.new()
	platform.collision_layer = 2
	platform.collision_mask = 8
	platform.position = Vector3(175,3100,340)
	platform.rotation.z = deg_to_rad(25)
	shape = CollisionShape3D.new()
	shape.shape = box
	platform.add_child(shape)
	scene.add_child(platform)
	mech.reset_flight(Vector3(175,3270,340),Quaternion(Vector3.BACK,deg_to_rad(25)),Vector3(0,-8,0))
	fc.detent = 0
	fc.engine_level = 0
	mech.freeze = false
	var slope_contact := false
	for tick in 180:
		await _ticks(1)
		if mech.collided:
			assert(mech.native_support,"Tilted supporting contact was mistaken for a wall")
			slope_contact = true
			break
	assert(slope_contact)
	mech.freeze = true
	platform.queue_free()
	await process_frame
	# Retained authored walk supplies stride; the contact layer owns stance locks.
	scene.set_walk_mode(true)
	var stance_ticks := [0,0]
	var swing_ticks := [0,0]
	for tick in 240:
		await _pose_ticks(1)
		for side in 2:
			if mech.rig.contacts.planted[side]: stance_ticks[side] += 1
			else: swing_ticks[side] += 1
	for side in 2: assert(stance_ticks[side]>20 and swing_ticks[side]>20,"Walk did not alternate stance and swing")
	completed = true
	print("Procedural pose checks passed: active start/coast/stop shoulder strokes before motion, freefall box/arch and tracking tuck, secondary balance/recovery, natural elbows, fluid hover, braking, steering/roll/retro, servo limits, inversion, landing prediction, one touchdown, grounded soles, platform tracking, contact release, slope normals and walking stance/swing.")
	scene.queue_free()
	await process_frame
	quit()
