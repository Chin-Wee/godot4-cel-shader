extends "res://aerial/tests/capture_animation_contract.gd"

var gaze_scan := false
var gaze_frame := Basis.IDENTITY
var only := ""

func _ticks(count: int) -> void:
	for tick in count:
		if gaze_scan:
			var time: float = scene.hero.controller.clock
			var target := Vector3.ZERO
			if time<1: target = Vector3(0.7,0.1,1)
			elif time<2: target = Vector3(-0.7,0.1,1)
			elif time<3: target = Vector3(0,1,1)
			elif time<4: target = Vector3(0,-1,1)
			scene.hero.controller.gaze_direction = gaze_frame*target.normalized()
		await super._ticks(1)

func _position_capture_camera() -> void:
	super._position_capture_camera()
	scene.camera.force_update_transform()
	for name in ["Neck","Hands.L","Hands.R","Feet.L","Feet.R"]:
		var point: Vector3 = scene.hero.skeleton.global_transform*scene.hero.bone_poses[scene.hero.skeleton.find_bone(name)].origin
		var uv: Vector2 = scene.camera.unproject_position(point)/Vector2(viewport.size)
		_expect(not scene.camera.is_position_behind(point) and Rect2(0.02,0.02,0.96,0.96).has_point(uv),"Camera loses the completed head/limbs")
	var rig = scene.hero.rig
	replay_label.position.y = 510
	replay_label.text += "\nBELLY %.0f / BACK %.0f%% · LAYOUT %.0f%% · BRAKE AREA %.0f%%\nNECK pitch %.0f° / yaw %.0f°"%[rig.motion.belly*100,rig.motion.back*100,rig.motion.layout*100,scene.hero.controller.brake_spread*100,rad_to_deg(rig.head.value.x),rad_to_deg(rig.head.value.y)]

func _capture() -> void:
	create_timer(420).timeout.connect(func():
		if not completed: push_error("Research body-flight replays timed out"); quit(1))
	await _setup_capture()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	var destination := output
	scene.explosion_clock = -1000
	for child in scene.hud.get_children():
		if child is CanvasItem: child.hide()
	if capture_enabled: replay_label.show()
	var cases := ["head_scan","air_bank_coast","belly_fall","back_fall","belly_back","layout_front","layout_back","posture_brake","reverse_thrust","jump_hover"]
	assert(only.is_empty() or only in cases,"Unknown selected replay")
	for camera_view in ["body","chase"]:
		view = camera_view
		output = destination.path_join(view)
		assert(DirAccess.make_dir_recursive_absolute(output)==OK)
		scene.camera.follow_enabled = view=="chase"
		report = {}
		for name in cases:
			if not only.is_empty() and name!=only: continue
			gaze_scan = false
			if name=="jump_hover":
				await _hover()
				continue
			if name=="reverse_thrust":
				await _retro()
				continue
			var orientation := Quaternion(Vector3.RIGHT,-PI/2)
			var velocity := Vector3.FORWARD*70
			var level := 0
			var count := 480
			var events: Array = [[0,[]]]
			match name:
				"head_scan":
					orientation = Quaternion.IDENTITY
					velocity = Vector3.ZERO
					level = 2
					count = 360
				"air_bank_coast":
					level = 3
					events = [[0,[]],[30,[KEY_D]],[78,[]],[150,[KEY_C]],[151,[]],[152,[KEY_C]],[153,[]],[154,[KEY_C]],[155,[]]]
				"belly_fall","back_fall":
					orientation = Quaternion(Vector3.RIGHT,-PI/2 if name=="belly_fall" else PI/2)
					velocity = Vector3.DOWN*45
					events = [[0,[]],[60,[KEY_Q]],[90,[]],[150,[KEY_SHIFT]],[240,[]]]
				"belly_back":
					velocity = Vector3.DOWN*45
					count = 720
					events = [[0,[]],[30,[KEY_D]],[185,[]],[360,[KEY_A]],[515,[]]]
				"layout_front","layout_back":
					velocity = Vector3.FORWARD*80
					events = [[0,[KEY_W if name=="layout_front" else KEY_S]],[158,[]]]
				"posture_brake":
					level = 3
					events = [[0,[KEY_SHIFT]],[120,[]]]
			await _fixture(Vector3(175,12000,340),orientation,velocity,level)
			if name=="head_scan":
				gaze_frame = scene.hero.skeleton.global_basis.orthonormalized()
				gaze_scan = true
			var rows: Array = await _play(name,count,events)
			gaze_scan = false
			for row in rows:
				var head := Vector3(row.head[0],row.head[1],row.head[2])
				_expect(head.is_equal_approx(scene.hero.rig.profile.limit_head(head)),name+": neck exceeds mechanical limits")
			_expect(rows[-1].omega<0.10,name+": release fails to arrest angular motion")
			match name:
				"head_scan":
					_expect(_at(rows,0.8).head[1]>0.3 and _at(rows,1.8).head[1]< -0.3,"Head scan lacks independent left/right vision")
					_expect(_at(rows,2.8).head[0]< -0.4 and _at(rows,3.8).head[0]>0.3,"Head scan lacks up/down articulation")
					_expect(_peak(rows,"speed")<0.5,"Looking moves the hovering chassis")
				"air_bank_coast":
					_expect(_at(rows,4).engine==0 and _at(rows,4).air_control>0.4 and absf(_at(rows,4).bank_gesture)>0.15,"Thrust cutoff erases air-loaded bank control")
				"belly_fall": _expect(_at(rows,0.8).belly>0.8 and _at(rows,0.8).back<0.01,"Belly-facing wind selects the wrong neutral")
				"back_fall": _expect(_at(rows,0.8).back>0.8 and _at(rows,0.8).belly<0.01,"Back-facing wind selects the wrong neutral")
				"belly_back": _expect(_peak(rows,"belly")>0.8 and _peak(rows,"back")>0.6,"Roll transition does not visit both wind-facing poses")
				"layout_front","layout_back": _expect(_peak(rows,"layout")>0.4,"Useful air/rate tracking never supports an extended layout")
				"posture_brake":
					_expect(_peak(rows,"brake_spread")>0.8,"Visible spreading does not develop braking area")
					_expect(_at(rows,5).brake_spread<0.3 and _at(rows,5).flare<0.1,"Released braking latches its own spread")
		report["camera"] = view
		report["failures"] = failures.duplicate()
		report["source_sha256"] = {}
		for file in ["flight_controller.gd","flight_pose.gd","arm_pose.gd","mech_rig_profile.gd","aerial_mech.gd","aerial_demo.gd"]:
			report.source_sha256[file] = FileAccess.get_sha256("res://aerial/"+file)
		report["driver_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_research_bodyflight.gd")
		report["fixture_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_animation_contract.gd")
		report["inputs_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_mech.gd")
		var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
	_keys([])
	scene.queue_free()
	await process_frame
	completed = true
	if failures.is_empty():
		print("Research body-flight replays passed: independent bounded head scan, air-loaded coast/bank, signed belly/back and transitions, extended layouts, geometry braking/release, reverse thrust and jump/hover in both views.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)
