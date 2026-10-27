extends "res://aerial/tests/capture_aerial.gd"

func _capture() -> void:
	create_timer(90.0).timeout.connect(_capture_timeout)
	assert(DisplayServer.get_name() != "headless","Mech validation requires native rendering")
	var args := OS.get_cmdline_user_args()
	var output := args[0] if not args.is_empty() else "/tmp/aerial-mech"
	assert(output.is_absolute_path() and DirAccess.make_dir_recursive_absolute(output) == OK)
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	scene.hud.visible = false
	await _save_frame(output.path_join("scene.png"))
	var center: Vector3 = scene.hero.position
	var axes: Basis = scene.hero.global_basis.orthonormalized()
	scene.camera.position = center+axes*Vector3(-100,40,150)
	scene.camera.look_at(center+Vector3.UP*8)
	for throttle in [0.0,0.35,1.0]:
		scene.set_afterburner_throttle(throttle)
		scene.hero.update_animation(1.0,throttle)
		await _save_frame(output.path_join("throttle-%.2f.png"%throttle))
	for pose in scene.hero.FLIGHT_POSES.size():
		scene.hero.flight_pose = pose
		for frame in 13:
			scene.hero.update_animation(1.0/24.0,1.0)
			scene._update_afterburners(1.0/24.0)
			await _save_frame(output.path_join("flight-%03d.png"%(pose*13+frame)))
		# Native BoneAttachment3D updates must follow the animated torso in every pose.
		var skeleton: Skeleton3D = scene.hero.actor.find_child("Skeleton3D",true,false)
		var torso := skeleton.find_bone("Torso")
		for socket in scene.hero.sockets:
			assert(socket.global_transform.is_equal_approx(skeleton.global_transform*skeleton.get_bone_global_pose(torso)),"Thruster detached while blending boost poses")
	assert(Image.load_from_file(output.path_join("flight-000.png")).get_data() != Image.load_from_file(output.path_join("flight-038.png")).get_data(),"Rendered flight poses are identical")
	scene.set_walk_mode(true)
	await physics_frame
	scene._update_hero_pose(scene.elapsed)
	scene.hero.update_animation(1.0,1.0)
	scene.set_palette(true)
	scene.camera.position = scene.hero.position+Vector3(-130,70,160)
	scene.camera.look_at(scene.hero.position)
	for frame in 72:
		var before: Vector3 = scene.hero.position
		scene.walking_time += 1.0/24.0
		scene.hero.update_animation(1.0/24.0,1.0)
		scene._update_hero_pose(scene.elapsed)
		scene.camera.position += scene.hero.position-before
		await _save_frame(output.path_join("walk-%03d.png"%frame))
	assert(Image.load_from_file(output.path_join("walk-000.png")).get_data() != Image.load_from_file(output.path_join("walk-024.png")).get_data(),"Rendered walk is static")
	var frozen := root.get_texture().get_image()
	await _save_frame(output.path_join("paused.png"))
	assert(frozen.get_data() == Image.load_from_file(output.path_join("paused.png")).get_data(),"Paused skeletal animation changed on native redraw")
	scene.queue_free()
	await process_frame
	completed = true
	print("Native mech checks passed: directional pose blends, torso thrusters, throttle, ground walk and pause.")
	quit()
