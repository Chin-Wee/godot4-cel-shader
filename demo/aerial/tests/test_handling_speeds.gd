extends "res://aerial/tests/capture_mech.gd"

# Real native rate checks; directional tap boosts are covered by test_flight_controls.
func _capture() -> void:
	create_timer(90).timeout.connect(func():
		if not completed: push_error("Handling speed checks timed out"); quit(1))
	await _setup_capture()
	var origin := Vector3(175,10000,340)
	for entry in [["pitch",KEY_S,1,0.75,0.9],["flip",KEY_S,0,1.95,2.0],
		["roll",KEY_D,0,1.5,2.0],["yaw",KEY_Q,0,0.8,2.0]]:
		await _fixture(origin,Quaternion(Vector3.RIGHT,-PI/2),Vector3.ZERO,entry[2])
		scene.hero.controller.air_density = 0.0
		var rows: Array = await _play("rate_"+entry[0],360,[[0,[entry[1]]],[180,[]]])
		var moving: Dictionary = _at(rows,entry[4])
		_expect(absf(moving.omega-entry[3])<0.08,entry[0]+": actual angular speed misses tuned rate")
		_expect(rows[-1].omega<0.08,entry[0]+": release fails to arrest")
	_keys([])
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	report["failures"] = failures.duplicate()
	report["controller_sha256"] = FileAccess.get_sha256("res://aerial/flight_controller.gd")
	file.store_string(JSON.stringify(report,"  "))
	scene.queue_free()
	await process_frame
	completed = true
	if failures.is_empty():
		print("Handling speed checks passed: faster roll, slower powered pitch/flips and retained yaw.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)
