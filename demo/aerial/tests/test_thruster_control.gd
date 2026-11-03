extends "res://aerial/tests/capture_mech.gd"

var sample_pulses := false
var pulse_starts := 0
var pulse_ticks := 0
var visible_ticks := 0
var was_firing := false

func _position_capture_camera() -> void:
	# Low three-quarter view exposes heel vectoring and shoulder/thigh puffs.
	scene.camera.position = scene.hero.position+scene.hero.global_basis*Vector3(65,-35,-120)
	scene.camera.look_at(scene.hero.position,scene.hero.global_basis.y)
	scene.camera.force_update_transform()
	replay_label.text += "\nCOLD GAS 3 Hz · delivered %.0f%%"%(scene.hero.controller.rcs_load*100)

func _ticks(count: int) -> void:
	for tick in count:
		await super._ticks(1)
		if not sample_pulses: continue
		var fc = scene.hero.controller
		var firing: bool = fc.rcs_load>0.001
		if firing:
			pulse_ticks += 1
			if not was_firing: pulse_starts += 1
		was_firing = firing
		var visible: bool = scene.hero.gas_jets.any(func(jet):return jet.visible)
		if visible: visible_ticks += 1
		_expect(not visible or firing,"Cold exhaust flashes without delivered torque")
		var local: Vector3 = scene.hero.global_basis.inverse()*fc.rcs_torque
		var fractions: Vector3 = (local/fc.torque_limits.max(Vector3.ONE*0.001)).abs()
		_expect(maxf(fractions.x,maxf(fractions.y,fractions.z))<=1.001,"Pulse exceeds torque capacity")

func _capture() -> void:
	create_timer(120).timeout.connect(func():
		if not completed: push_error("Thruster control checks timed out"); quit(1))
	# Fixed demand: count actual firings and verify the integrated physical impulse.
	var fc = Controller.new()
	fc.torque_limits = Vector3.ONE*100
	fc.control_torque = Vector3(10,0,0)
	var starts := 0
	var impulse := Vector3.ZERO
	var on := false
	for tick in 480:
		fc.clock = float(tick+1)/60
		fc._calculate_rcs_torque(Basis.IDENTITY,1.0/60)
		var active: bool = fc.rcs_load>0.001
		if active and not on: starts += 1
		on = active
		impulse += fc.rcs_torque/60
	_expect(starts==24 and impulse.distance_to(Vector3(80,0,0))<0.01,"3 Hz pulsing changes the requested mean impulse")
	fc.control_torque = Vector3(0.5,0,0)
	fc._calculate_rcs_torque(Basis.IDENTITY,1.0/60)
	_expect(fc.rcs_torque.is_zero_approx(),"Quiet trim ignores the cold-gas dead zone")
	fc.control_torque = Vector3(80,0,0)
	fc._calculate_rcs_torque(Basis.IDENTITY,1.0/60)
	_expect(fc.rcs_torque.is_equal_approx(fc.control_torque),"Strong steering loses sustained cold-gas authority")
	fc.control_torque = Vector3(200,-150,25)
	fc._calculate_rcs_torque(Basis.IDENTITY,1.0/60)
	_expect(fc.rcs_torque.is_equal_approx(Vector3(100,-100,25)),"Sustained pulse bypasses per-axis actuator limits")
	await _setup_capture()
	scene.explosion_clock = -1000
	for child in scene.hud.get_children():
		if child is CanvasItem: child.hide()
	if capture_enabled: replay_label.show()
	var origin := Vector3(175,10000,340)
	for entry in [["forward",KEY_W,Vector3.FORWARD],["back",KEY_S,Vector3.BACK],
		["left",KEY_A,Vector3.LEFT],["right",KEY_D,Vector3.RIGHT]]:
		await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
		var rows: Array = await _play("vector_"+entry[0],180,[[0,[entry[1]]]])
		var early: Dictionary = _at(rows,0.3)
		var force := Vector3(early.main_force[0],early.main_force[1],early.main_force[2])
		_expect(force.dot(entry[2])>scene.hero.mass*Controller.GRAVITY*0.25,entry[0]+": nozzles wait for the body to tilt")
		for row in rows: _expect(row.upright>cos(deg_to_rad(4)),entry[0]+": hover steers by tilting the chassis")
		for index in 6:
			var actual: Vector3 = scene.hero.controller.motor_forces[index].normalized()
			var shown: Vector3 = -scene.hero.gimbals[index].global_basis.z.normalized()
			_expect(actual.angle_to(shown)<0.08,"Rendered nozzle does not follow the force-producing motor")
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	sample_pulses = true
	var rows: Array = await _play("quiet_hover",1800,[[0,[]]])
	sample_pulses = false
	_expect(pulse_ticks>0 and pulse_ticks<1500 and pulse_starts<=30*Controller.RCS_PULSE_HZ+2,"Quiet hover still fires continuously or chatters")
	_expect(visible_ticks>0,"Physical cold-gas pulses have no visible outlets")
	_expect(rows[-1].speed<0.8 and rows[-1].omega<0.15,"Relaxed hover accumulates uncontrolled drift")
	for row in rows: _expect(row.upright>cos(deg_to_rad(5)),"Relaxed hover loses gyro support")
	_keys([])
	report["failures"] = failures.duplicate()
	report["pulse_starts"] = pulse_starts
	report["pulse_ticks"] = pulse_ticks
	report["visible_ticks"] = visible_ticks
	report["controller_sha256"] = FileAccess.get_sha256("res://aerial/flight_controller.gd")
	report["mech_sha256"] = FileAccess.get_sha256("res://aerial/aerial_mech.gd")
	report["driver_sha256"] = FileAccess.get_sha256("res://aerial/tests/test_thruster_control.gd")
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	scene.queue_free()
	await process_frame
	completed = true
	if failures.is_empty():
		print("Thruster control checks passed: early four-way nozzle vectoring, physical/render agreement, 3 Hz mean impulse, dead zone, sustained steering, truthful cold flashes and bounded relaxed hover.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)
