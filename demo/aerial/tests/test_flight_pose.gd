extends SceneTree

const Controller = preload("res://aerial/flight_controller.gd")
const Pose = preload("res://aerial/flight_pose.gd")
var completed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(25).timeout.connect(func():
		if not completed: push_error("Continuous flight checks did not complete"); quit(1))
	assert(_check_controller(),"Flight controller checks failed")
	assert(_check_handling(),"Flight handling checks failed")
	assert(_check_combat_gate(),"Combat aero gate checks failed")
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	scene.follow_camera = false
	var mech = scene.hero
	await physics_frame
	await process_frame
	assert(mech.flames.size() == 6 and mech.gas_jets.size() == 4)
	assert(_check_mount_surfaces(mech),"A booster floats away from source armor")
	for raw in [{},{"forward":true},{"uncage":true,"back":true},{"uncage":true,"right":true,"burst":true},{"uncage":true,"brake":true}]:
		mech.controller.reset(Vector3(175,1600,340))
		mech.controller.aiming = true
		for frame in 180: mech.step_flight(1.0/60.0,raw,0.0)
		await process_frame
		await process_frame
		assert(not mech.actor.animation_player.is_playing(),"Flight uses an authored clip")
		assert(_check_ik(mech),"Native arm IK missed its target")
		assert(_check_motors(mech),"A motor exceeded its local mechanical cone")
		# The weapon deliberately trails a moving aim boundary. Verify its final
		# alignment after settling, rather than requiring a zero-lag wrist snap.
		for frame in 45: mech.update_animation(1.0/60.0)
		await process_frame
		await process_frame
		assert(mech.rig.weapon.barrel_direction.dot(mech.controller.limit_aim_direction(mech.controller.aim_direction)) > 0.99,"Settled rifle missed its bounded aim")
	# Low-ready -> supported aim -> wide one-hand tracking, using one native IK.
	mech.controller.reset(Vector3(175,1600,340))
	mech.position = mech.controller.position
	mech.quaternion = Quaternion.IDENTITY
	for frame in 90: mech.update_animation(1.0/60.0)
	await process_frame
	var low_hand: Vector3 = mech.bone_poses[mech.skeleton.find_bone("Hands.R")].origin
	mech.controller.aiming = true
	for frame in 90: mech.update_animation(1.0/60.0)
	await process_frame
	var right: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Hands.R")]
	var left: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Hands.L")]
	assert(right.origin.distance_to(low_hand) > 1.0,"Aiming hand does not raise from low-ready")
	assert(mech.rig.weapon.support_weight > 0.95,"Offhand never braces the rifle")
	assert(left.origin.distance_to(right*mech.rig.weapon.support_offset) < 0.05,"Offhand floats away from the receiver")
	var before_recoil: Vector3 = mech.rig.hands[1].value
	mech.rig.kick_weapon()
	for frame in 5: mech.update_animation(1.0/60.0)
	assert(mech.rig.hands[1].value.distance_to(before_recoil) > 0.03,"Firing has no arm follow-through")
	mech.controller.aim_direction = Vector3.LEFT
	mech.controller.gaze_target = mech.position+Vector3.LEFT*4500
	for frame in 90: mech.update_animation(1.0/60.0)
	await process_frame
	assert(mech.rig.weapon.support_weight < 0.05,"Offhand cannot release for wide tracking")
	assert(_check_ik(mech))
	# Readable leg response to real loads, with opposed vernier bracing.
	mech.controller.reset(Vector3(175,1600,340))
	for frame in 90: mech.update_animation(1.0/60.0)
	var relaxed: float = mech.rig.legs[1].value.x
	mech.controller.g_load = 4.0
	mech.controller.boost_amount = 1.0
	mech.controller.burst_direction = Vector3.RIGHT
	mech.controller.local_acceleration = Vector3(22,0,0)
	for frame in 30: mech.update_animation(1.0/60.0)
	assert(mech.rig.legs[1].value.x > relaxed+0.5,"Legs do not tuck under maneuver/burst load")
	assert(absf(mech.rig.legs[1].value.x-mech.rig.legs[4].value.x) > 0.2,"Vernier burst moves both legs identically")
	await process_frame
	assert(_check_ik(mech) and _check_motors(mech))
	# Aim moves the weapon/head without first rotating the chassis.
	mech.controller.reset(Vector3(175,1000,340))
	mech.controller.aim_direction = Vector3(-0.25,0,-1).normalized()
	for frame in 60: mech.step_flight(1.0/60.0,{},0.0)
	await process_frame
	assert(mech.controller.attitude.angle_to(Quaternion.IDENTITY) < 0.01)
	assert(absf(mech.rig.head.value.y) > 0.1)
	assert(_check_ik(mech))
	# Native terrain prediction and swept capsule collision, with assist capped.
	var ground: float = scene.ground_height(Vector3(175,0,340))
	mech.controller.reset(Vector3(175,ground+150,340))
	mech.position = mech.controller.position
	mech.controller.velocity = Vector3(0,-25,0)
	mech.controller.detent = 0
	await physics_frame
	assert(mech.predict_impact() < 1.0,"Swept terrain prediction missed an imminent impact")
	var collision_seen := false
	for frame in 90:
		mech.step_flight(1.0/60.0,{"uncage":true},0)
		collision_seen = collision_seen or mech.collided
	assert(collision_seen,"Native capsule did not collide with canyon terrain")
	assert(mech.position.y >= ground+35,"Chassis tunneled through terrain")
	assert(mech.position.y < ground+90,"Collision was replaced by an altitude teleport")
	# Existing ground preview, pause, focus cycle and bounded gunfire remain live.
	scene.set_walk_mode(true)
	for frame in 90: mech.update_animation(1.0/60.0)
	await process_frame
	assert(not mech.rig.active and not mech.rig.ik.active and not mech.rig.weapon.active)
	assert(mech.actor.current_animation == &"Walk")
	scene.set_walk_mode(false)
	for frame in 30: mech.update_animation(1.0/60.0)
	await process_frame
	var position: Vector3 = mech.position
	var clock: float = mech.controller.clock
	var posture: Transform3D = mech.actor.transform
	scene._process(0.2)
	assert(mech.position == position and mech.controller.clock == clock and mech.actor.transform == posture,"Pause advances flight")
	for target in [scene.wingman,scene.missile,null]:
		scene.focus_next()
		assert(scene.focus_target == target)
	mech.controller.aiming = true
	for frame in 90: mech.update_animation(1.0/60.0)
	await process_frame
	scene.animate = true
	scene.fire_weapon()
	assert(scene.shots_fired == 1 and scene.shots.size() == 8)
	scene.fire_weapon()
	assert(scene.shots_fired == 1,"Gun rate limiter failed")
	scene.animate = false
	scene.queue_free()
	await process_frame
	completed = true
	print("Flight checks passed: restored movement, X/aero-gated combat pitch/roll, held-input continuity, passive high-speed drag, independent aim, low-ready/braced/offhand poses, recoil, IK, seated motors, terrain, walk and pause.")
	quit()

func _advance(fc, seconds: float, raw: Dictionary) -> void:
	for frame in roundi(seconds*120): fc.advance(1.0/120.0,raw,0.0)

func _check_controller() -> bool:
	Controller.install_input_actions()
	for pair in [[KEY_W,"forward"],[KEY_S,"back"],[KEY_A,"left"],[KEY_D,"right"],[KEY_Q,"yaw_left"],[KEY_E,"yaw_right"],[KEY_SPACE,"thrust_up"],[KEY_C,"thrust_down"],[KEY_SHIFT,"burst"],[KEY_X,"brake"],[KEY_R,"rise"],[KEY_F,"sink"],[KEY_CTRL,"precision"]]:
		for pressed in [true,false]:
			var event := InputEventKey.new()
			event.physical_keycode = pair[0]
			event.pressed = pressed
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			assert(Controller.read_input()[pair[1]] == pressed)
	for action in ["flight_pitch_up","flight_pitch_down","flight_roll_left","flight_roll_right"]:
		assert(not InputMap.has_action(action),"Manual pitch/roll binding remains")
	var previous := Vector3.ZERO
	for fps in [30,60,120]:
		var fc = Controller.new()
		fc.reset(Vector3(0,600,0))
		for frame in fps*3: fc.advance(1.0/fps,{"forward":true},0)
		if fps > 30: assert(fc.position.distance_to(previous) < 0.001,"Movement depends on display rate")
		previous = fc.position
	var fc = Controller.new()
	fc.reset(Vector3(0,600,0))
	_advance(fc,3,{})
	assert(fc.position.distance_to(Vector3(0,600,0)) < 0.01,"Default hover drifts")
	_advance(fc,1,{"thrust_up":true})
	assert(fc.detent == 3,"Held thrust key repeats detents")
	for press in 6:
		fc.advance(0.01,{},0)
		fc.advance(0.01,{"thrust_down":true},0)
	assert(fc.detent == 0)
	for control in ["forward","back","left","right","rise","sink"]:
		fc.reset(Vector3.ZERO)
		_advance(fc,1,{control:true})
		var direction: Vector3 = {"forward":Vector3.FORWARD,"back":Vector3.BACK,"left":Vector3.LEFT,"right":Vector3.RIGHT,"rise":Vector3.UP,"sink":Vector3.DOWN}[control]
		assert(fc.velocity.dot(direction) > 4,"Normal movement is unavailable: "+control)
	fc.reset(Vector3.ZERO)
	_advance(fc,2,{"right":true})
	_advance(fc,3,{})
	assert(absf(fc.velocity.x) < 1,"Assisted movement does not catch a released strafe")
	var caged = Controller.new()
	var free = Controller.new()
	for actor in [caged,free]: actor.reset(Vector3.ZERO)
	_advance(caged,0.2,{"right":true,"burst":true})
	_advance(free,0.2,{"right":true,"burst":true,"uncage":true})
	_advance(caged,3,{})
	_advance(free,3,{"uncage":true})
	assert(caged.velocity.x < 1 and free.velocity.x > 8,"Uncaged drift and assisted braking are indistinguishable")
	return true

func _check_handling() -> bool:
	# Direct/raw pitch and roll requests are ignored at every speed and with RMB.
	for speed in [0.0,40.0,90.0]:
		for uncage in [false,true]:
			var neutral = Controller.new()
			var attempted = Controller.new()
			for fc in [neutral,attempted]:
				fc.reset(Vector3.ZERO)
				fc.velocity = Vector3(0,0,-speed)
				if speed > 0: fc.attitude = Quaternion(Vector3.RIGHT,-PI/2)
			for frame in 120:
				neutral.advance(1.0/120.0,{"uncage":uncage},0)
				attempted.advance(1.0/120.0,{"uncage":uncage,"pitch_up":true,"roll_left":true},PI/2)
			assert(neutral.attitude.angle_to(attempted.attitude) < 0.001 and neutral.position.distance_to(attempted.position) < 0.001,"Disabled rotation/camera input still steers")
	# Passive extra drag scales with speed and dissipates energy even without X.
	var slow = Controller.new()
	var fast = Controller.new()
	for fc in [slow,fast]:
		fc.reset(Vector3.ZERO)
		fc.attitude = Quaternion(Vector3.RIGHT,-PI/2)
		fc.detent = 0
	slow.velocity = Vector3(0,0,-20)
	fast.velocity = Vector3(0,0,-100)
	_advance(slow,1,{"uncage":true})
	_advance(fast,1,{"uncage":true})
	assert(100+fast.velocity.z > (20+slow.velocity.z)*8,"High-speed drag does not strengthen with speed")
	assert(fast.high_speed_drag > 0.5 and slow.high_speed_drag == 0)
	var brake = Controller.new()
	brake.reset(Vector3.ZERO)
	brake.attitude = Quaternion(Vector3.RIGHT,-PI/2)
	brake.velocity = Vector3(0,0,-100)
	brake.detent = 0
	_advance(brake,1,{"uncage":true,"brake":true})
	assert(-brake.velocity.z < -fast.velocity.z*0.7,"X no longer adds airbrake drag")
	var straight = Controller.new()
	var looking = Controller.new()
	for fc in [straight,looking]: fc.reset(Vector3.ZERO)
	looking.aim_direction = Vector3.BACK
	for frame in 240:
		straight.advance(1.0/120.0,{"forward":true,"yaw_left":true},0)
		looking.advance(1.0/120.0,{"forward":true,"yaw_left":true},PI/2)
	assert(straight.position.distance_to(looking.position) < 0.001 and straight.attitude.angle_to(looking.attitude) < 0.001,"Mouse vision steers normal movement")
	return true

func _check_combat_gate() -> bool:
	for aero in [0.0,0.5,0.5001,0.9]:
		for braking in [false,true]:
			var fc = Controller.new()
			fc.reset(Vector3.ZERO)
			fc.aero_authority = aero
			fc.advance(0,{"brake":braking,"back":true})
			assert(fc.combat_attitude == (braking and aero > 0.5),"Combat gate does not require X and aero strictly above 50%")
	var fc = Controller.new()
	fc.reset(Vector3.ZERO)
	fc.aero_authority = 0.8
	fc.advance(0,{"forward":true})
	fc.advance(0,{"forward":true,"brake":true})
	assert(fc.combat_attitude,"X does not override an already-held movement key")
	fc.aero_authority = 0.2
	fc.advance(0,{"forward":true,"brake":true})
	assert(not fc.combat_attitude and fc.combat_bindings,"Flow dip violates the strict gate or loses captured keys")
	fc.velocity = Vector3.ZERO
	fc.authority.value = Vector3.ZERO
	fc.advance(0.1,{"forward":true,"brake":true})
	assert(not fc.combat_attitude and fc.combat_bindings and fc.translation_input.is_zero_approx(),"Captured low-aero key requests movement")
	fc.advance(0,{"brake":true})
	assert(not fc.combat_attitude,"Released maneuver stays latched below the aero gate")
	fc.advance(0,{"back":true,"brake":true})
	assert(not fc.combat_attitude,"New low-aero input incorrectly gains attitude control")
	fc.aero_authority = 0.7
	fc.advance(0,{"back":true,"brake":true})
	assert(fc.combat_attitude)
	fc.advance(0,{"back":true})
	assert(not fc.combat_attitude,"Releasing X does not restore movement")
	for key in ["forward","back","left","right"]:
		fc.reset(Vector3.ZERO)
		fc.attitude = Quaternion(Vector3.RIGHT,-PI/2)
		fc.velocity = Vector3(0,0,-90)
		_advance(fc,0.5,{"uncage":true})
		assert(fc.aero_authority > 0.5)
		var before: Quaternion = fc.attitude
		_advance(fc,0.4,{"brake":true,key:true})
		assert(fc.combat_attitude and fc.combat_bindings and fc.attitude.angle_to(before) > 0.15,"Combat WASD cannot pitch/roll")
		assert(Vector2(fc.translation_input.x,fc.translation_input.z).length() < 0.001,"Combat WASD also requests translation")
		var sign_value := -1.0 if key in ["forward","right"] else 1.0
		var value: float = fc.rotation_command.x if key in ["forward","back"] else fc.rotation_command.z
		assert(value*sign_value > 0.5,"Combat pitch/roll input has the wrong axis or direction")
		assert(fc.vector_stabilization == 0.0,"Combat maneuver activates hover braking")
	fc.reset(Vector3.ZERO)
	_advance(fc,1,{"brake":true,"right":true})
	assert(not fc.combat_attitude and fc.velocity.x > 4,"Low-aero combat brake loses normal strafe")
	fc.reset(Vector3.ZERO)
	fc.attitude = Quaternion(Vector3.RIGHT,-PI/2)
	fc.velocity = Vector3(0,0,-90)
	_advance(fc,0.5,{"uncage":true})
	fc.advance(0.1,{"brake":true,"right":true,"burst":true})
	assert(fc.combat_attitude and fc.boost_amount > 0 and is_zero_approx(fc.rotation_command.z),"Vernier burst also rolls the chassis")
	return true

func _check_motors(mech: Node3D) -> bool:
	var pivots: Array = mech.gimbals+mech.gas_gimbals
	for index in pivots.size():
		var relative: Basis = mech.neutral_bases[index].inverse()*pivots[index].basis
		if relative.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) > mech.VECTOR_LIMIT+0.001: return false
	return true

func _check_ik(mech: Node3D) -> bool:
	for side in 2:
		var suffix := ".L" if side == 0 else ".R"
		var hand: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Hands"+suffix)]
		var target: Vector3 = mech.rig.hand_targets[side].position
		if not hand.origin.is_finite() or not hand.basis.is_finite() or hand.origin.distance_to(target) >= 0.05: return false
	return true

func _check_mount_surfaces(mech: Node3D) -> bool:
	# Test against source triangles, excluding the collars we add ourselves. Bone
	# attachment alone cannot prove that a booster is seated against the armor.
	var sk: Skeleton3D = mech.skeleton
	for mount in mech.MOUNTS+mech.COLD_MOUNTS:
		var nearest := INF
		for child in sk.get_children():
			var candidates := []
			var transform := Transform3D.IDENTITY
			if child is BoneAttachment3D and child.bone_name == mount[1] and not str(child.name).begins_with("Thruster"):
				candidates = child.get_children()
			elif child is MeshInstance3D and child.name == &"Cube" and mount[1] == &"Torso":
				candidates = [child]
				transform = sk.get_bone_global_rest(sk.find_bone("Torso")).affine_inverse()
			for mesh in candidates:
				if not mesh is MeshInstance3D: continue
				var to_bone: Transform3D = transform*mesh.transform
				var faces: PackedVector3Array = mesh.mesh.get_faces()
				for index in range(0,faces.size(),3):
					nearest = minf(nearest,_triangle_distance(mount[2],to_bone*faces[index],to_bone*faces[index+1],to_bone*faces[index+2]))
		if nearest >= 0.02:
			push_error("Booster floats away from source armor: %s (%s source units)"%[mount[0],nearest])
			return false
	return true

func _triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b-a).cross(c-a).normalized()
	var hit = Geometry3D.segment_intersects_triangle(point+normal*100,point-normal*100,a,b,c)
	if hit != null: return point.distance_to(hit)
	return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point,a,b)),minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point,b,c)),point.distance_to(Geometry3D.get_closest_point_to_segment(point,c,a))))
