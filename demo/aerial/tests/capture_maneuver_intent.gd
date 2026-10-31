extends "res://aerial/tests/capture_animation_contract.gd"

func _position_capture_camera() -> void:
	if view=="chase": return
	# Side-biased close-up exposes knee compression and aft arm sweep. The
	# second pass still uses the real independent-look gameplay camera.
	scene.camera.position = scene.hero.position+scene.hero.global_basis*Vector3(-150,25,-70)
	scene.camera.look_at(scene.hero.position,scene.hero.global_basis.y)
	scene.camera.force_update_transform()

# Actual input, native physics, completed sockets and both existing cameras.
func _capture() -> void:
	create_timer(180).timeout.connect(func():
		if not completed: push_error("Maneuver capture did not finish"); quit(1))
	await _setup_capture()
	var destination := output
	scene.explosion_clock = -1000
	for child in scene.hud.get_children():
		if child is CanvasItem: child.hide()
	if capture_enabled: replay_label.show()
	for camera_view in ["body","chase"]:
		view = camera_view
		output = destination.path_join(view)
		assert(DirAccess.make_dir_recursive_absolute(output)==OK)
		scene.follow_camera = view=="chase"
		report = {}
		await _fixture(Vector3(175,7000,340),Quaternion(Vector3.RIGHT,PI/2),Vector3(12,0,-55),0)
		var rows: Array = await _play("reverse",600,[[0,[]],[30,[KEY_SPACE]],[31,[]],[32,[KEY_SPACE]],[33,[]],[34,[KEY_SPACE]],[35,[]]])
		_expect(_peak(rows,"retro")>0.8 and _peak(rows,"knee")>0.8,"Reverse never establishes its loaded squat")
		_expect(_peak(rows,"prepare_effort")>0.3,"Reverse has no throttle preparation")
		_expect(rows[-1].retro<0.1 and rows[-1].velocity[2]>20,"Reverse brace does not release into outgoing travel")
		_expect(_peak(rows,"torque")<1,"Reverse squat overwhelms the actual attitude actuators")
		_expect(_peak(rows,"gimbal_peak")<=Controller.VECTOR_LIMIT+0.00001,"Reverse exceeds a nozzle cone")
		await _fixture(Vector3(175,7000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,0,-65),3)
		rows = await _play("burst",420,[[0,[]],[60,[KEY_SPACE]],[61,[]]])
		_expect(_peak(rows,"drive")>0.8 and _peak(rows,"arm_span")>7.5,"Acceleration lacks a forceful aft arm stroke")
		_expect(_peak(rows,"knee")>0.35,"Acceleration never compresses the legs")
		_expect(_peak(rows,"torque")<1 and _peak(rows,"gimbal_peak")<=Controller.VECTOR_LIMIT+0.00001,"Acceleration pose exceeds actuator limits")
		await _fixture(Vector3(175,7000,340),Quaternion(Vector3.RIGHT,PI/2),Vector3(-18,0,-55),0)
		rows = await _play("interruption",540,[[0,[]],[30,[KEY_SPACE]],[31,[]],[32,[KEY_SPACE]],[33,[]],[34,[KEY_SPACE]],[35,[]],
			[100,[KEY_C]],[101,[]],[102,[KEY_C]],[103,[]],[104,[KEY_C]],[105,[]],
			[210,[KEY_SPACE]],[211,[]],[212,[KEY_SPACE]],[213,[]],[214,[KEY_SPACE]],[215,[]],[270,[KEY_Q]],[300,[]]])
		_expect(_at(rows,3).engine==0 and _at(rows,3).retro<0.1,"Canceled reverse effort remains latched")
		await _maneuvers()
		await _bodyflight()
		await _fixture(Vector3(175,9000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,0,-85),3)
		rows = await _play("flare_exit",600,[[0,[]],[60,[KEY_SHIFT]],[180,[KEY_SPACE]],[181,[]]])
		var braking: Dictionary = _at(rows,2.0)
		var exiting: Dictionary = _at(rows,4.5)
		_expect(braking.flare>0.8 and braking.arm_span>9 and braking.knee>0.8,"Air braking never produces a displayed squat and wide hand flare")
		_expect(braking.leg_asymmetry_size>0.3,"Loaded flare leaves the legs mirrored")
		_expect(exiting.drive>0.6 and exiting.hand_forward<braking.hand_forward-2,"Flare does not release into aft acceleration arms")
		_expect(rows[-1].flare<0.1 and rows[-1].hand_forward<0,"Exit never becomes aerodynamic cruise")
		report["failures"] = failures.duplicate()
		report["camera"] = view
		report["camera_setup"] = "side-biased body-relative review" if view=="body" else "normal independent-look gameplay camera"
		report["physics_hz"] = HZ
		report["driver_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_maneuver_intent.gd")
		report["inputs_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_mech.gd")
		report["source_sha256"] = {}
		for file in ["flight_pose.gd","arm_pose.gd","contact_pose.gd","mech_rig_profile.gd","pose_servo.gd","flight_controller.gd","aerial_mech.gd","aerial_demo.gd"]:
			report.source_sha256[file] = FileAccess.get_sha256("res://aerial/"+file)
		var data := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		data.store_string(JSON.stringify(report,"  "))
		data.close()
	_keys([])
	scene.queue_free()
	await process_frame
	completed = true
	if failures.is_empty():
		print("Maneuver captures passed: oblique reverse through zero, hard acceleration, cancellation/re-ignition and opposing turns in body and chase cameras.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)
