extends "res://aerial/tests/capture_animation_contract.gd"

# Same native body/inputs in both camera paths. Baseline impulse values are
# sampled from main 18cab0a's identical eight-second 70 m/s bank/pull timelines.
const BASELINE_COLD_IMPULSE := {3:1381631.05,4:2143602.90} # N m s, integral of torque magnitude.

func _position_capture_camera() -> void:
	super._position_capture_camera()
	scene.camera.force_update_transform()
	if view=="chase":
		for side in [-1.0,1.0]:
			var point: Vector3 = scene.hero.position+scene.hero.global_basis.y*scene.hero.display_scale*0.9*side
			var screen: Vector2 = scene.camera.unproject_position(point)/Vector2(viewport.size)
			_expect(screen.x>0.02 and screen.x<0.98 and screen.y>0.02 and screen.y<0.98,"Chase camera loses the mech during fast movement")
	var c = scene.hero.controller
	replay_label.position.y = 515
	replay_label.text += "\nAIR %.0f kNm · MAIN %.0f kNm · COLD %.0f kNm"%[c.aero_torque.length()/1000,c.main_torque.length()/1000,c.rcs_torque.length()/1000]

func _capture() -> void:
	create_timer(300).timeout.connect(func():
		if not completed: push_error("Body-flight replays did not finish"); quit(1))
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
		for speed in [35.0,70.0,110.0]:
			for level in [3,4]:
				await _fixture(Vector3(175,9000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3.FORWARD*speed,level)
				var name := "bank_pull_"+str(int(speed))+"_"+str(level)
				var rows: Array = await _play(name,480,[[0,[]],[30,[KEY_D]],[78,[]],[120,[KEY_S]],[240,[]]],speed==70)
				var banked: Dictionary = _at(rows,2)
				_expect(absf(banked.bank)>deg_to_rad(35) and absf(banked.bank)<deg_to_rad(75),name+": bank never captures a useful angle")
				_expect(_at(rows,4).velocity[0]>10,name+": banked pull does not bend the trajectory")
				_expect(rows[-1].omega<0.08,name+": maneuver release leaves uncontrolled rotation")
				for row in rows:
					if row.time>=2 and row.time<4: _expect(absf(row.aoa)<deg_to_rad(33),name+": pull loses the pitch envelope")
				if speed==70:
					var impulse := 0.0
					var air_peak := 0.0
					for row in rows:
						impulse += Vector3(row.rcs_torque[0],row.rcs_torque[1],row.rcs_torque[2]).length()*0.1
						air_peak = maxf(air_peak,Vector3(row.aero_torque[0],row.aero_torque[1],row.aero_torque[2]).length())
					var ratio: float = impulse/BASELINE_COLD_IMPULSE[level]
					report[name]["cold_impulse_ratio"] = ratio
					_expect(ratio<0.65,name+": cold gas still carries the old engine-cancellation burden")
					_expect(air_peak>20000,name+": body pressure has no significant physical moment")
		await _fixture(Vector3(175,9000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3.FORWARD*70,3)
		var rows: Array = await _play("overlap",480,[[0,[]],[30,[KEY_D,KEY_S]],[78,[KEY_S]],[240,[]]])
		_expect(rows[-1].omega<0.08 and _at(rows,4).velocity[0]>10,"Overlapping bank/pull cannot recover")
		await _fixture(Vector3(175,9000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3.FORWARD*70,3)
		rows = await _play("cancel_reverse",480,[[0,[]],[30,[KEY_D]],[78,[KEY_S]],[120,[KEY_A,KEY_W]],[180,[]]])
		_expect(rows[-1].omega<0.08,"Canceled/reversed maneuver remains committed")
		for entry in [["left",KEY_A,Vector3.LEFT],["right",KEY_D,Vector3.RIGHT],["forward",KEY_W,Vector3.FORWARD],["back",KEY_S,Vector3.BACK]]:
			await _fixture(Vector3(175,9000,340),Quaternion.IDENTITY,Vector3.ZERO,2)
			rows = await _play("strong_hover_"+entry[0],420,[[0,[entry[1]]],[180,[]]])
			var lean: Dictionary = _at(rows,2.5)
			_expect(lean.visual_lean>deg_to_rad(20) and lean.visual_lean<deg_to_rad(28),entry[0]+": stronger lean is absent or excessive")
			var travel := Vector3(lean.velocity[0],lean.velocity[1],lean.velocity[2])
			_expect(travel.dot(entry[2])>6,entry[0]+": horizontal departure has no useful delivered thrust")
			_expect(rows[-1].speed<0.6,entry[0]+": stronger hover cannot catch its drift")
			for row in rows:
				_expect(row.upright>0.995 and absf(row.yaw_rate)<0.04,entry[0]+": animation changes destabilize the chassis")
		await _fixture(Vector3(175,9000,340),Quaternion.IDENTITY,Vector3.ZERO,4)
		rows = await _play("full_power_side",180,[[0,[KEY_A]]])
		for row in rows: _expect(row.torque<1 and absf(row.yaw_rate)<0.1,"Full-power lateral flight repeats the yaw overload")
		report["failures"] = failures.duplicate()
		report["camera"] = view
		report["source_sha256"] = {}
		report["driver_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_bodyflight.gd")
		for file in ["flight_controller.gd","aerial_mech.gd","aerial_demo.gd","flight_pose.gd","arm_pose.gd","mech_rig_profile.gd"]:
			report.source_sha256[file] = FileAccess.get_sha256("res://aerial/"+file)
		var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	_keys([])
	scene.queue_free()
	await process_frame
	completed = true
	if failures.is_empty():
		print("Body-flight replays passed: staged/overlapping bank and pull, cancellation/reversal, stronger four-way hover, full-power yaw reserve and reduced cold-gas demand in both cameras.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)
