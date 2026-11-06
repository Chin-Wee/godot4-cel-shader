extends "res://aerial/tests/capture_animation_contract.gd"

func _position_capture_camera() -> void:
	super._position_capture_camera()
	scene.camera.force_update_transform()
	var points: Array[Vector3] = []
	for side in [-1.0,1.0]: points.append(scene.hero.position+scene.hero.global_basis.y*scene.hero.display_scale*0.9*side)
	for name in ["Hands.L","Hands.R","Feet.L","Feet.R"]:
		points.append(scene.hero.skeleton.global_transform*scene.hero.bone_poses[scene.hero.skeleton.find_bone(name)].origin)
	for point in points:
		var screen: Vector2 = scene.camera.unproject_position(point)/Vector2(viewport.size)
		_expect(not scene.camera.is_position_behind(point) and Rect2(0.02,0.02,0.96,0.96).has_point(screen),"Camera loses the mech during acrobatics")
	var fc = scene.hero.controller
	replay_label.position.y = 515
	replay_label.text += "\nPITCH %.0f° · ROLL %.0f° · TUCK %.0f%%"%[rad_to_deg(fc.maneuver_travel.x),rad_to_deg(fc.maneuver_travel.y),scene.hero.rig.motion.flip_shape.y*100]

func _capture() -> void:
	create_timer(420).timeout.connect(func():
		if not completed: push_error("Acrobatics replay timed out"); quit(1))
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
		scene.camera.follow_enabled = view=="chase"
		report = {}
		for entry in [["front",KEY_W,-1.0],["back",KEY_S,1.0]]:
			await _fixture(Vector3(175,12000,340),Quaternion.IDENTITY,Vector3.ZERO,0)
			scene.hero.controller.air_density = 0.0
			var rows: Array = await _play(entry[0]+"_flip",540,[[0,[entry[1]]],[270,[]]])
			var crossing := INF
			for row in rows:
				if row.maneuver_travel[0]*entry[2]>=TAU and crossing==INF: crossing = row.time
			_expect(crossing>=3.3 and crossing<=5.5,entry[0]+": clean flip is outside the finite-actuator timing corridor")
			_expect(_peak(rows,"omega")<=2.05 and rows[-1].omega<0.08,entry[0]+": rate limit or release arrest failed")
			report[entry[0]+"_flip"]["full_turn_time"] = crossing if is_finite(crossing) else -1.0
			scene.hero.controller.air_density = 1.225
		for entry in [["left",KEY_A],["right",KEY_D]]:
			await _fixture(Vector3(175,12000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3.FORWARD*70,3)
			var rows: Array = await _play("bank_"+entry[0],360,[[0,[entry[1]]],[48,[]]])
			_expect(rows[-1].omega<0.08,"Bank release does not arrest")
			_expect(absf(_at(rows,3.0).bank_gesture)>0.1,"Captured bank loses its loaded offset pose")
			await _fixture(Vector3(175,12000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3.FORWARD*20,0)
			rows = await _play("roll_"+entry[0],540,[[0,[entry[1]]],[390,[]]])
			var turn: float = rows.map(func(r):return absf(r.maneuver_travel[1])).max()
			_expect(turn>TAU and rows[-1].omega<0.08,"Full roll cannot pass 360° or recover")
			for row in rows:
				if row.time>0.5 and row.time<6.5:
					_expect(absf(row.roll_rate)>row.omega*0.8,"Roll becomes yaw through inversion")
		for entry in [["early_cancel",[[0,[KEY_S]],[25,[]]]],["inverted_cancel",[[0,[KEY_W]],[133,[]]]],
			["reverse",[[0,[KEY_S]],[120,[KEY_W]],[280,[]]]],
			["compound",[[0,[KEY_S,KEY_D]],[150,[]]]],
			["sustained",[[0,[KEY_S]],[474,[]]]]]:
			await _fixture(Vector3(175,12000,340),Quaternion.IDENTITY,Vector3.ZERO,0)
			var rows: Array = await _play(entry[0],660,entry[1],entry[0] in ["inverted_cancel","reverse","compound"])
			_expect(rows[-1].omega<0.08,entry[0]+": interrupted/combined rotation does not recover")
			if entry[0]=="sustained":
				var turn: float = rows.map(func(r):return absf(r.maneuver_travel[0])).max()
				_expect(turn>TAU*2,"Held pitch cannot continue into a second revolution")
		await _fixture(Vector3(175,12000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3.FORWARD*70,3)
		var rows: Array = await _play("braked_flip",480,[[0,[KEY_SHIFT,KEY_S]],[230,[KEY_SHIFT]],[300,[]]])
		_expect(rows.map(func(r):return absf(r.maneuver_travel[0])).max()>PI or rows.any(func(r):return r.rcs_saturated),"Braked flip stalls without reporting physical actuator saturation")
		_expect(rows[-1].omega<0.08,"Brake flip does not recover")
		# Powered, unbraked turns must never enter the somersault articulation/rate.
		await _fixture(Vector3(175,12000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3.FORWARD*70,3)
		rows = await _play("protected_pitch",480,[[0,[KEY_S]],[300,[]]],false)
		for row in rows:
			_expect(row.acro[0]<0.001,"Powered protected turn triggers a flip")
			if row.time<5: _expect(absf(row.aoa)<deg_to_rad(33),"Powered turn lost pitch protection")
		report["camera"] = view
		report["failures"] = failures.duplicate()
		report["source_sha256"] = {}
		for file in ["flight_controller.gd","flight_pose.gd","arm_pose.gd","mech_rig_profile.gd","aerial_demo.gd"]:
			report.source_sha256[file] = FileAccess.get_sha256("res://aerial/"+file)
		report["driver_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_acrobatics.gd")
		report["fixture_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_animation_contract.gd")
		report["inputs_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_mech.gd")
		var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
	_keys([])
	scene.queue_free()
	await process_frame
	completed = true
	if failures.is_empty():
		print("Acrobatics replays passed: measured heavy flips, banks/rolls, axis stability, multiple turns, cancellation/reversal, compound motion, braking and retained powered protection in both cameras.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)
