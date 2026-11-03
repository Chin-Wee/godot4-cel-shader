extends "res://aerial/tests/capture_mech.gd"

# Real force/rate checks. Baseline hover speeds were measured at 2.5 s on
# 32c4f36: forward 9.59, reverse 7.61, lateral 9.07 m/s.
func _capture() -> void:
	create_timer(90).timeout.connect(func():
		if not completed: push_error("Handling speed checks timed out"); quit(1))
	await _setup_capture()
	var origin := Vector3(175,10000,340)
	for entry in [["forward",KEY_W,Vector3.FORWARD,10.1],["back",KEY_S,Vector3.BACK,8.0],
		["left",KEY_A,Vector3.LEFT,9.6],["right",KEY_D,Vector3.RIGHT,9.6]]:
		await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
		var rows: Array = await _play("faster_hover_"+entry[0],480,[[0,[entry[1]]],[180,[]]])
		var moving: Dictionary = _at(rows,2.5)
		var velocity := Vector3(moving.velocity[0],moving.velocity[1],moving.velocity[2])
		_expect(velocity.dot(entry[2])>entry[3],entry[0]+": tuned hover is not faster than baseline")
		_expect(moving.upright>0.995 and rows[-1].speed<0.6,entry[0]+": faster hover loses upright support or release catch")
		for row in rows:
			_expect(row.gimbal_peak<=Controller.VECTOR_LIMIT+0.0001 and row.torque<1,entry[0]+": hover exceeds actuator bounds")
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
		print("Handling speed checks passed: faster four-way hover, bounded nozzles/release catch, faster roll, slower powered pitch/flips and retained yaw.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)
