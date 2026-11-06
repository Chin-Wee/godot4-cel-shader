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
	replay_label.text += "\nCOLD GAS %s · delivered %.0f%%"%["STEADY" if scene.hero.controller.rcs_continuous else "3 Hz TRIM",scene.hero.controller.rcs_load*100]

func _ticks(count: int) -> void:
	for tick in count:
		await super._ticks(1)
		if not sample_pulses: continue
		var fc = scene.hero.controller
		var firing: bool = fc.cold_forces.any(func(force):return force.length()>1.0)
		if firing:
			pulse_ticks += 1
			if not was_firing: pulse_starts += 1
		was_firing = firing
		var visible: bool = scene.hero.gas_jets.any(func(jet):return jet.visible)
		if visible: visible_ticks += 1
		_expect(not visible or firing,"Cold exhaust flashes without delivered torque")
		for index in 4:
			if fc.cold_forces[index].length()>1.0:
				var shown: Vector3 = -scene.hero.gas_gimbals[index].global_basis.z.normalized()
				_expect(shown.angle_to(fc.cold_forces[index].normalized())<0.08,"Rendered cold nozzle differs from its applied force direction")
			_expect(fc.cold_forces[index].length()<=scene.hero.mass*Controller.GRAVITY*Controller.COLD_THRUST_G+1.0,"Cold outlet exceeds its physical thrust capacity")

func _capture() -> void:
	create_timer(120).timeout.connect(func():
		if not completed: push_error("Thruster control checks timed out"); quit(1))
	_check_valves()
	await _setup_capture()
	_check_nozzle_allocation()
	scene.explosion_clock = -1000
	for child in scene.hud.get_children():
		if child is CanvasItem: child.hide()
	if capture_enabled: replay_label.show()
	var origin := Vector3(175,10000,340)
	for entry in [["forward",KEY_W,Vector3.FORWARD],["back",KEY_S,Vector3.BACK],
		["left",KEY_A,Vector3.LEFT],["right",KEY_D,Vector3.RIGHT]]:
		await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
		var rows: Array = await _play("vector_"+entry[0],180,[[0,[entry[1]]],[1,[]]])
		var early: Dictionary = _at(rows,0.3)
		var force := Vector3(early.main_force[0],early.main_force[1],early.main_force[2])
		_expect(force.dot(entry[2])>scene.hero.mass*Controller.GRAVITY*0.25,entry[0]+": nozzles wait for the body to tilt")
		for row in rows: _expect(row.upright>cos(deg_to_rad(20)),entry[0]+": delayed physical jets lose bounded recovery")
		for index in 6:
			var actual: Vector3 = scene.hero.controller.motor_forces[index].normalized()
			var shown: Vector3 = -scene.hero.gimbals[index].global_basis.z.normalized()
			_expect(actual.angle_to(shown)<0.08,"Rendered nozzle does not follow the force-producing motor")
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	sample_pulses = true
	var rows: Array = await _play("quiet_hover",1800,[[0,[]]])
	sample_pulses = false
	_expect(pulse_ticks>0 and pulse_starts<=30*Controller.RCS_PULSE_HZ+2,"Quiet hover chatters beyond the physical trim schedule")
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
		print("Thruster control checks passed: early four-way nozzle vectoring, physical/render agreement, finite valve timing and nozzle-force torque, dead zone, sustained steering, truthful cold flashes and bounded relaxed hover.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check_valves() -> void:
	var Valve = Controller.Valve
	for timings in [[0.008,0.03,0.012,0.014,0.02],
		[Controller.HOT_IGNITION,Controller.HOT_RESTART,Controller.HOT_RESPONSE,Controller.HOT_RESPONSE,Controller.HOT_MINIMUM_ON]]:
		var reference := -1.0
		for hz in [30,60,144,240]:
			var valve = Valve.new(timings[0],timings[1],timings[2],timings[3],timings[4])
			var impulse := 0.0
			for segment in [[1.0,0.3],[0.0,0.02],[1.0,0.4],[0.0,0.3]]:
				var remaining: float = segment[1]
				while remaining>0.000000001:
					var dt := minf(remaining,1.0/hz)
					var output: float = valve.step(segment[0],dt)
					_expect(output>=0 and output<=1.000001,"Valve delivers negative or excessive flow")
					impulse += output*dt
					remaining -= dt
			if reference<0: reference = impulse
			_expect(absf(reference-impulse)<0.000001,"Valve impulse depends on frame/tick rate")
		var valve = Valve.new(timings[0],timings[1],timings[2],timings[3],timings[4])
		_expect(valve.step(1.0,timings[0]*0.5)==0,"Thruster bypasses ignition delay")
		valve.step(1.0,0.5)
		valve.step(0.0,timings[3]+0.0001)
		_expect(valve.level==0 and valve.step(1.0,timings[1]*0.5)==0,"Thruster bypasses shutdown/restart dead time")
		valve.reset()
		valve.step(1.0,0.001)
		_expect(valve.step(0.0,timings[0]+timings[4])>0,"Accepted short command bypasses minimum impulse time")

func _check_nozzle_allocation() -> void:
	var fc = Controller.new()
	fc.configure(scene.hero,50.0)
	var outlets := []
	for point in [Vector3(-20,30,0),Vector3(20,30,0),Vector3(-20,-10,0),Vector3(20,-10,0)]:
		outlets.append({"position":point,"basis":Basis.looking_at(Vector3.RIGHT if point.x<0 else Vector3.LEFT,Vector3.UP)})
	for axis in 3:
		for sign in [-1.0,1.0]:
			fc.reset(0.0)
			fc.torque_limits = Vector3.ONE*100000
			fc.control_torque = Vector3.ZERO
			fc.control_torque[axis] = sign*40000
			var mean_moment := Vector3.ZERO
			for tick in 120:
				fc.clock += 1.0/60
				fc._calculate_cold_thrusters(outlets,Basis.IDENTITY,1.0/60)
				if tick>=60: mean_moment += fc.rcs_torque/60.0
				var force := Vector3.ZERO
				var moment := Vector3.ZERO
				for index in 4:
					force += fc.cold_forces[index]
					moment += (outlets[index].position/Controller.WORLD_UNITS_PER_METER).cross(fc.cold_forces[index])
					_expect(fc.cold_angles[index].length()<=Controller.VECTOR_LIMIT+0.00001,"Cold nozzle exceeds its cone")
				_expect(force.distance_to(fc.cold_force)<0.1 and moment.distance_to(fc.rcs_torque)<0.1,"Cold thrust/torque is not the sum of its actual outlet forces")
			_expect(mean_moment[axis]*sign>20000,"Placed cold nozzles cannot produce a requested torque axis")
		fc.control_torque = Vector3.ZERO
		for tick in 30:
			fc.clock += 1.0/60
			fc._calculate_cold_thrusters(outlets,Basis.IDENTITY,1.0/60)
		_expect(fc.cold_force.is_zero_approx() and fc.rcs_torque.is_zero_approx(),"Shutdown leaves unrequested cold force/torque")
	fc.reset(0.0)
	fc.control_torque = Vector3.ONE*100000
	for outlet in outlets: outlet.position = Vector3.ZERO
	for tick in 30:
		fc.clock += 1.0/60
		fc._calculate_cold_thrusters(outlets,Basis.IDENTITY,1.0/60)
	_expect(fc.rcs_torque.is_zero_approx(),"Cold gas invents torque without a physical moment arm")
	var direction := Vector3(1,0.3,0.2).normalized()
	_expect(fc._motor_angle(Basis.IDENTITY,direction).is_equal_approx(fc._motor_angle(Basis.IDENTITY,direction*100000)),"Nozzle aiming depends on force magnitude")
	var source := FileAccess.get_file_as_string("res://aerial/flight_controller.gd")
	_expect(not source.contains("apply_torque(") and not source.contains("apply_central_force("),"Flight dynamics reintroduced a force/torque bypass")
