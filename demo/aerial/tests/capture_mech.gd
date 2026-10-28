extends "res://aerial/tests/capture_aerial.gd"

func _step(scene: Node3D, delta: float) -> void:
	scene.animate = true
	scene._process(delta)
	for trail in scene.trails:
		if trail.is_processing(): trail._process(delta)
	scene.animate = false

func _capture() -> void:
	create_timer(150.0).timeout.connect(_capture_timeout)
	assert(DisplayServer.get_name() != "headless","Mech validation requires native rendering")
	var args := OS.get_cmdline_user_args()
	var output := args[0] if not args.is_empty() else "/tmp/aerial-mech"
	assert(output.is_absolute_path() and DirAccess.make_dir_recursive_absolute(output) == OK)
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	scene.hud.visible = false
	await _save_frame(output.path_join("scene.png"))
	for flame in scene.hero.flames:
		assert(flame.global_basis.z.normalized().dot(Vector3.DOWN) > 0.999,"Default hover thrust is not downward")
	var axes: Basis = scene.hero.global_basis.orthonormalized()
	scene.camera.position = scene.hero.position+axes*Vector3(-120,40,150)
	scene.camera.look_at(scene.hero.position)
	for frame in 108:
		if frame == 12: scene.set_afterburner_throttle(1.0)
		if frame == 54: scene.set_afterburner_throttle(0.35)
		_step(scene,1.0/18.0)
		await _save_frame(output.path_join("flight-%03d.png"%frame))
		if frame == 53:
			assert(scene.hero.actor.rotation.x < -0.9,"Cruise is not leaning into flight")
			assert(scene.hero.actor.current_animation == &"Airborne","Cruise returned to an authored combat crouch")
	assert(scene.flight_rate == 0.0 and absf(scene.hero.actor.rotation.x) < 0.01,"Deceleration did not settle into upright hover")
	var hover_position: Vector3 = scene.hero.position
	_step(scene,0.2)
	assert(scene.hero.position.is_equal_approx(hover_position),"Final hover keeps moving along the aircraft route")
	await _save_frame(output.path_join("hover.png"))
	for pose in scene.hero.FLIGHT_POSES.size():
		scene.hero.flight_pose = pose
		scene.hero.flight_amount = 1.0
		scene.hero.update_animation(0.9,1.0)
		scene._update_afterburners()
		await _save_frame(output.path_join("maneuver-%d.png"%pose))
		for index in scene.hero.sockets.size():
			var socket: BoneAttachment3D = scene.hero.sockets[index]
			var skeleton: Skeleton3D = scene.hero.skeleton
			var bone := skeleton.find_bone(socket.bone_name)
			assert(socket.global_transform.is_equal_approx(skeleton.global_transform*skeleton.get_bone_global_pose(bone)),"Thruster detached from its limb")
			var angles: Vector2 = scene.hero.vector_angles[index]
			var expected: Vector3 = scene.hero.actor.global_basis.orthonormalized()*scene.hero.NEUTRAL_EXHAUST*Basis.from_euler(Vector3(angles.y,angles.x,0)).z
			assert(scene.hero.flames[index].global_basis.z.normalized().dot(expected) > 0.999,"Bone animation rotated thrust away from the suit's commanded down axis")
	scene.hero.flight_pose = 0
	scene.hero.flight_amount = 0.0
	scene.hero.update_animation(3.0,0.35)
	scene.set_afterburner_throttle(1.0)
	await _save_frame(output.path_join("neutral.png"))
	for flame in scene.hero.flames:
		assert(flame.global_basis.z.normalized().dot(Vector3.DOWN) > 0.999,"Neutral jets do not face down together")
		var anchor: Vector3 = flame.global_position
		scene.camera.position = anchor+axes*Vector3(-16,9,18)
		scene.camera.look_at(anchor+Vector3.DOWN*4.0)
		await _save_frame(output.path_join(str(flame.name)+".png"))
	scene.hero.set_thrust_vector(0,Vector2(0.35,-0.15))
	scene.hero.update_animation(0.6,1.0)
	scene._update_afterburners()
	await _save_frame(output.path_join("independent-vector.png"))
	assert(scene.hero.flames[0].global_basis.z.normalized().dot(Vector3.DOWN) < 0.98,"Backpack nozzle ignored its independent vector command")
	for index in range(1,5):
		assert(scene.hero.flames[index].global_basis.z.normalized().dot(Vector3.DOWN) > 0.999,"Backpack command moved other jets")
	scene.hero.set_thrust_vector(0,Vector2.ZERO)
	scene.hero.update_animation(2.0,0.35)
	var original_scale: Vector3 = scene.hero.scale
	scene.hero.scale *= Vector3(1.4,0.75,1.6)
	scene._update_afterburners()
	await _save_frame(output.path_join("scaled-nozzles.png"))
	for flame in scene.hero.flames:
		assert(flame.global_basis.z.normalized().dot(Vector3.DOWN) > 0.999,"Nonuniform model scale changed neutral downward thrust")
	scene.hero.scale = original_scale
	scene.set_walk_mode(true)
	await physics_frame
	scene._update_hero_pose(scene.flight_time)
	scene.hero.update_animation(1.0,1.0)
	scene.set_palette(true)
	scene.camera.position = scene.hero.position+Vector3(-130,70,160)
	scene.camera.look_at(scene.hero.position)
	for frame in 36:
		var before: Vector3 = scene.hero.position
		scene.walking_time += 1.0/12.0
		scene.hero.update_animation(1.0/12.0,1.0)
		scene._update_hero_pose(scene.flight_time)
		scene.camera.position += scene.hero.position-before
		await _save_frame(output.path_join("walk-%03d.png"%frame))
	assert(Image.load_from_file(output.path_join("walk-000.png")).get_data() != Image.load_from_file(output.path_join("walk-012.png")).get_data(),"Rendered walk is static")
	var frozen := root.get_texture().get_image()
	await _save_frame(output.path_join("paused.png"))
	assert(frozen.get_data() == Image.load_from_file(output.path_join("paused.png")).get_data(),"Paused flight or walk still animates")
	scene.queue_free()
	await process_frame
	completed = true
	print("Native mech checks passed: downward hover jets, acceleration/lean/braking, five vectoring nozzles, limb attachment, scale, walk and pause.")
	quit()
