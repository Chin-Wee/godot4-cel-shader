extends "res://aerial/tests/capture_mech.gd"

# Reuse real input timelines in close-up and the unchanged gameplay camera.
# No render-only pose evaluation: captures and physical nozzles share one clock.
var view := "body"
const CASES := ["hover","fighter","inverted","coast","bodyflight","fall","transitions","recovery"]

func _recovery() -> void:
	# Continue the preceding powered-flight replay: no fixture reset, teleport,
	# attitude write, pose reset or velocity write at this handoff.
	var rows: Array = await _play("recovery",1200,[[0,[KEY_C]],[1,[]],[2,[KEY_C]],[3,[]],[4,[KEY_C]],[5,[]],
		[600,[KEY_SPACE]],[601,[]],[602,[KEY_SPACE]],[603,[]],[604,[KEY_SPACE]],[605,[]]])
	report.recovery["continuation_of"] = "transitions"
	var restored: Array = rows.slice(70).map(func(row): return row.behavior_weights[1])
	var coast_peak: float = rows.map(func(row): return row.behavior_weights[2]).max()
	# Unpowered aerodynamic lift may keep this entry gliding. Cutoff itself
	# must not manufacture falling; the preceding transition covers real descent.
	_expect(coast_peak>0.9 and _minimum(rows,"engine")==0,"recovery: thrust cutoff never established independent coast")
	_expect(restored.max()>0.5,"recovery: re-ignition did not recover powered aerodynamic flight")
	_expect(_peak(rows,"hover")<0.01,"recovery: fast stall activated hover catch")

func _fixture(origin: Vector3, orientation: Quaternion, speed: Vector3, level: int) -> void:
	await super._fixture(origin,orientation,speed,level)
	if view=="chase": scene.reset_camera()

func _position_capture_camera() -> void:
	if view=="chase": return # scene._process already evaluated the real camera.
	scene.camera.position = scene.hero.position+scene.hero.global_basis*Vector3(-70,25,-150)
	scene.camera.look_at(scene.hero.position,scene.hero.global_basis.y)
	scene.camera.force_update_transform()

func _capture() -> void:
	create_timer(240).timeout.connect(func():
		if not completed: push_error("Animation contract capture did not finish"); quit(1))
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
		await _hover()
		await _fighter()
		await _coast()
		await _bodyflight()
		await _fall()
		await _transitions()
		for behavior in 4:
			var peak: float = report.transitions.samples.map(func(row): return row.behavior_weights[behavior]).max()
			_expect(peak>0.6,"transitions: uninterrupted flight never visited behavior "+str(behavior))
		await _recovery()
		for name in CASES: _expect(report.has(name),view+": missing "+name)
		report["failures"] = failures.duplicate()
		report["camera"] = view
		report["physics_hz"] = HZ
		report["driver_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_animation_contract.gd")
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
		print("Animation contract captures passed: jump/hover, powered/inverted fighter flight, independent coast, skydiver falling and continuous transitions in body and gameplay chase views.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)
