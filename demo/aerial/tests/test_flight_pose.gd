extends SceneTree

const Controller = preload("res://aerial/flight_controller.gd")
const Pose = preload("res://aerial/flight_pose.gd")
var completed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(25).timeout.connect(func():
		if not completed: push_error("Continuous flight checks did not complete"); quit(1))
	_check_controller()
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
		for frame in 180: mech.step_flight(1.0/60.0,raw,0.0)
		await process_frame
		await process_frame
		assert(not mech.actor.animation_player.is_playing(),"Flight uses an authored clip")
		assert(_check_ik(mech),"Native arm IK missed its target")
		assert(_check_motors(mech),"A motor exceeded its local mechanical cone")
		assert(mech.rig.weapon.barrel_direction.dot(mech.controller.aim_direction) > 0.99,"Rifle does not follow independent aim")
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
	scene.animate = true
	scene.fire_weapon()
	assert(scene.shots_fired == 1 and scene.shots.size() == 8)
	scene.fire_weapon()
	assert(scene.shots_fired == 1,"Gun rate limiter failed")
	scene.animate = false
	scene.queue_free()
	await process_frame
	completed = true
	print("Flight checks passed: detents, latched controls, continuous aero, independent momentum/attitude/aim, bursts, drag, ground prediction/collision, IK, seated motors, walk, gunfire, focus and pause.")
	quit()

func _advance(fc, seconds: float, raw: Dictionary) -> void:
	for frame in roundi(seconds*120): fc.advance(1.0/120.0,raw,0.0)

func _check_controller() -> void:
	Controller.install_input_actions()
	for pair in [[KEY_W,"forward"],[KEY_S,"back"],[KEY_A,"left"],[KEY_D,"right"],[KEY_Q,"yaw_left"],[KEY_E,"yaw_right"],[KEY_SPACE,"thrust_up"],[KEY_C,"thrust_down"],[KEY_SHIFT,"burst"],[KEY_X,"brake"]]:
		for pressed in [true,false]:
			var event := InputEventKey.new()
			event.physical_keycode = pair[0]
			event.pressed = pressed
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			assert(Controller.read_input()[pair[1]] == pressed,"Input binding differs from design")
	var previous := Vector3.ZERO
	for fps in [30,60,120]:
		var fc = Controller.new()
		fc.reset(Vector3(0,600,0))
		for frame in fps*3: fc.advance(1.0/fps,{"forward":true},0.0)
		if fps > 30: assert(fc.position.distance_to(previous) < 0.001,"Force integration depends on display rate")
		previous = fc.position
	var fc = Controller.new()
	fc.reset(Vector3(0,600,0))
	_advance(fc,3,{})
	assert(fc.position.distance_to(Vector3(0,600,0)) < 0.01,"Default hover drifts")
	_advance(fc,1,{"thrust_up":true})
	assert(fc.detent == 3,"Held thrust key repeats detents")
	fc.advance(0.01,{},0)
	fc.advance(0.01,{"thrust_up":true},0)
	assert(fc.detent == 4)
	for press in 6:
		fc.advance(0.01,{},0)
		fc.advance(0.01,{"thrust_down":true},0)
	assert(fc.detent == 0,"Thrust detents do not clamp at zero")
	fc.reset(Vector3.ZERO)
	fc.advance(0.01,{"right":true},0)
	fc.attitude_bindings = true
	fc.advance(0.01,{"right":true},0)
	assert(fc.latches.right == false,"Held vector input changed meaning")
	fc.attitude_bindings = true
	fc.advance(0.01,{},0)
	fc.attitude_bindings = true
	fc.advance(0.01,{"right":true},0)
	assert(fc.latches.right == true,"New press did not recapture aerodynamic binding")
	fc.reset(Vector3.ZERO)
	fc.velocity = Vector3(16,0,0)
	fc.detent = 0
	_advance(fc,0.6,{"uncage":true,"forward":true})
	assert(fc.attitude.angle_to(Quaternion.IDENTITY) > 0.35,"Uncage at low speed does not pitch")
	_advance(fc,1,{"uncage":true})
	var held: Quaternion = fc.attitude
	_advance(fc,1,{"uncage":true})
	assert(fc.attitude.angle_to(held) < 0.001,"Uncaged suit tumbles after input release")
	assert(fc.velocity.x > 14.5,"Uncage erased sideways momentum")
	for control in ["right","yaw_left"]:
		fc.reset(Vector3.ZERO)
		_advance(fc,0.4,{"uncage":true,control:true})
		if control == "right": assert(absf(Basis(fc.attitude).y.x) > 0.1,"Low-speed roll became yaw")
		else: assert(absf(Basis(fc.attitude).z.x) > 0.1,"Q/E stopped being yaw in hover")
	fc.reset(Vector3.ZERO)
	fc.aim_direction = Vector3(-1,0,0.4).normalized()
	fc.aim_chassis_follow = true
	_advance(fc,1,{"uncage":true})
	assert(Basis(fc.attitude).z.x > 0.2 and absf(Basis(fc.attitude).z.y) < 0.02,"Outer aim envelope rolls instead of yawing the chassis")
	var caged = Controller.new()
	var uncaged = Controller.new()
	for actor in [caged,uncaged]: actor.reset(Vector3.ZERO)
	_advance(caged,0.2,{"right":true,"burst":true})
	_advance(uncaged,0.2,{"right":true,"burst":true,"uncage":true})
	assert(caged.velocity.x > 10 and uncaged.velocity.x > 10,"Vernier burst lacks a finite impulse")
	_advance(caged,3,{})
	_advance(uncaged,3,{"uncage":true})
	assert(caged.velocity.x < 1.0 and uncaged.velocity.x > 10,"Caged/uncaged burst recovery is identical")
	var drop = Controller.new()
	var stall = Controller.new()
	for actor in [drop,stall]:
		actor.reset(Vector3.ZERO)
		actor.attitude = Quaternion(Vector3.RIGHT,-PI/2)
		actor.velocity = Vector3(0,0,-70)
		actor.detent = 0
	_advance(drop,2,{"uncage":true})
	_advance(stall,2,{"uncage":true,"brake":true})
	assert(-drop.velocity.z > -stall.velocity.z*2,"Airbrake does not shed energy through drag")
	assert(drop.velocity.y < 0 and stall.velocity.y < 0,"Dropping/airbraking cancels gravity")
	assert(drop.aero_authority > 0.8,"Aligned high-speed flow never gains aerodynamic authority")
	fc.reset(Vector3.ZERO)
	_advance(fc,6,{"forward":true})
	assert(fc.aero_authority > 0.6 and Basis(fc.attitude).y.dot(Vector3.FORWARD) > 0.9,"Automatic body-lift transition failed")
	fc.reset(Vector3.ZERO)
	fc.attitude = Quaternion(Vector3.RIGHT,-PI/2)
	fc.velocity = Vector3(0,0,-70)
	fc.detent = 3
	_advance(fc,2,{})
	assert(-fc.velocity.z > 70,"Aerodynamic cruise assist brakes against sustained thrust")
	fc.time_to_impact = 0.3
	_advance(fc,0.05,{"uncage":true})
	var limited: float = fc.required_force.y
	_advance(fc,0.05,{})
	assert(fc.required_force.y > limited+20,"Recaging does not permit full ground escape assistance")

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
