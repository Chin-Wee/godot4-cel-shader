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
	# This frozen fixture specifies pilot requests through rotation_command.
	mech.controller.rotation_request = mech.controller.rotation_command
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
	# Powered joints reach and hold a fixed command without a spring overshoot.
	var joint := Servo.new()
	var last_joint := 0.0
	for tick in 240:
		joint.step(Vector3.ONE,1.0/60.0,0.30)
		assert(joint.value.x>=last_joint and joint.value.x<=1.0,"Powered joint rings past a held command")
		last_joint = joint.value.x
	assert(joint.value.distance_to(Vector3.ONE)<0.001)
	var slow := Servo.new()
	var fast := Servo.new()
	for tick in 30: slow.step(Vector3.ONE,1.0/30.0,0.30)
	for tick in 120: fast.step(Vector3.ONE,1.0/120.0,0.30)
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
	# Airborne geometry is covered by test_air_pose on the completed skeleton.
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
			# Check settled authored walking after the flight-pose crossfade.
			if mech.rig.air_weight<0.001 and mech.rig.contacts.planted[side] and mech.rig.contacts.weights[side].value.x>0.99:
				var bone: int = mech.skeleton.find_bone(mech.rig.profile.foot_bones[side])
				var sole: Vector3 = mech.skeleton.global_transform*(mech.bone_poses[bone]*mech.rig.profile.sole_offset)
				var actual_end: Vector3 = mech.skeleton.global_transform*mech.bone_poses[bone].origin
				var target_end: Vector3 = mech.rig.contacts.targets[side].global_position
				assert(actual_end.distance_to(target_end)<0.8,"Ground IK did not reach its constrained endpoint")
				var requested_end: Vector3 = mech.rig.contacts.plant_position(side)+mech.rig.contacts.plant_normal(side)*0.04-mech.rig.contacts.foot_basis(side)*mech.rig.profile.sole_offset*mech.skeleton.global_basis.get_scale().x
				# Mechanical reach limits may intentionally prevent an exact floor lock.
				if target_end.distance_to(requested_end)<0.2:
					assert(sole.distance_to(mech.rig.contacts.plant_position(side))<1.0,"Reachable walking sole left its stance plant")

	for side in 2: assert(stance_ticks[side]>20 and swing_ticks[side]>20,"Walk did not alternate stance and swing")
	completed = true
	print("Procedural pose checks passed: servo bounds, no ringing, landing preparation/impact, one touchdown, actual grounded soles, moving platforms, contact release, slope normals and retained walking.")
	scene.queue_free()
	await process_frame
	quit()
