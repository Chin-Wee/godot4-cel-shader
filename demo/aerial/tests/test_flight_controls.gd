extends "res://aerial/tests/capture_mech.gd"

func _position_capture_camera() -> void:
	super._position_capture_camera()
	var fc = scene.hero.controller
	replay_label.position.y = 525
	replay_label.text += "\nChassis tilt %.1f° · speed %.1f m/s"%[rad_to_deg(acos(clampf(scene.hero.basis.y.y,-1,1))),fc.velocity.length()]
	if fc.flight_protection>0.05: replay_label.text += " · airflow pitch error %.1f°"%rad_to_deg(fc.angle_of_attack)

# Real native body and real key timelines. Optional native renderer records the
# same runs; no duplicate flight solver or render-only pose controller.
func _capture() -> void:
	create_timer(600).timeout.connect(func():
		if not completed: push_error("Flight control checks did not finish"); quit(1))
	await _setup_capture()
	scene.explosion_clock = -1000
	for child in scene.hud.get_children():
		if child is CanvasItem: child.hide()
	if capture_enabled: replay_label.show()
	var origin := Vector3(175,10000,340)
	var directions := [["forward",KEY_W,Vector3.FORWARD],["back",KEY_S,Vector3.BACK],
		["left",KEY_A,Vector3.LEFT],["right",KEY_D,Vector3.RIGHT]]
	_check_burst_clock()
	for entry in directions:
		await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
		var rows: Array = await _play("hover_"+entry[0],360,[[0,[entry[1]]],[1,[]]])
		var moving: Dictionary = _at(rows,0.3)
		var force := Vector3(moving.main_force[0],moving.main_force[1],moving.main_force[2])
		_expect(absf(moving.engine-4.0)<0.001,entry[0]+": tap never reaches fourfold hover thrust")
		_expect(force.dot(entry[2])>scene.hero.mass*Controller.GRAVITY*0.5,entry[0]+": burst produces no physical directional push")
		_expect(_at(rows,0.7).burst_remaining==0 and _at(rows,0.7).engine<2,entry[0]+": boost leaks beyond half a second")
		_expect(rows[-1].upright>0.98 and rows[-1].speed<0.8,entry[0]+": tap release never catches drift")
		_expect(_peak(rows,"gimbal_peak")<=Controller.VECTOR_LIMIT+0.0001,entry[0]+": nozzle cone exceeded")
		_expect(_peak(rows,"omega")<1.0,entry[0]+": burst develops an uncontrolled spin")
	# Held input rotates immediately alongside the one-shot burst.
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	var rows: Array = await _play("hover_rotation",120,[[0,[KEY_W]]],false)
	_expect(absf(_at(rows,0.2).command[0])>0.5 and _at(rows,0.2).pitch_rate< -0.05 and _at(rows,1.2).angle>0.1,"Hover still delays pitch behind a movement lock")
	_expect(_at(rows,1.8).burst_remaining==0,"Held input automatically repeats the burst")
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	rows = await _play("diagonal_hover",180,[[0,[KEY_W,KEY_D]],[1,[]]],false)
	for row in rows:
		_expect(Vector3(row.hover_translation[0],0,row.hover_translation[2]).length()<=1.0001,"Diagonal input doubles directional demand")
	_expect(_at(rows,0.3).velocity[0]>0.2 and _at(rows,0.3).velocity[2]<-0.2,"Diagonal burst loses an input axis")
	# Direction follows chassis heading, independently of mouse look.
	await _fixture(origin,Quaternion(Vector3.UP,PI/2),Vector3.ZERO,2)
	scene.camera.orbit(Vector2(500,-80))
	rows = await _play("heading_relative",180,[[0,[KEY_W]],[1,[]]],false)
	_expect(_at(rows,0.3).velocity[0]<-0.5 and absf(_at(rows,0.3).velocity[2])<0.5,"Burst follows world/camera axes")
	# Native hover compensation must not prevent reactivation at the cooldown.
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	rows = await _play("burst_retap",180,[[0,[KEY_W]],[1,[]],[45,[KEY_S]],[46,[]],[60,[KEY_S]],[61,[]]],false)
	_expect(_at(rows,0.8).burst_remaining==0,"Early native tap bypasses cooldown")
	_expect(absf(_at(rows,1.3).engine-4.0)<0.001 and _at(rows,1.3).hover_translation[2]>0.9,"One-second native re-tap does not reactivate in the new direction")
	# Cutoff cancels a burst without altering the selected power or momentum.
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	rows = await _play("burst_cutoff",180,[[0,[KEY_W]],[1,[]],[6,[KEY_C]],[7,[]],[8,[KEY_C]],[9,[]]],false)
	_expect(_at(rows,0.3).burst_remaining==0 and rows[-1].engine==0,"Cutoff leaves boost power running")
	# Every flight case holds real W/S for six seconds, well beyond the old stall.
	for level in [1,2,3,4]:
		for speed in [35.0,70.0,110.0]:
			var downward_velocity := 0.0
			for code in [KEY_W,KEY_S]:
				await _fixture(origin,Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,0,-speed),level)
				var name := "flight_"+("down" if code==KEY_W else "up")+"_"+str(int(speed))
				if level!=3: name += "_"+str(Controller.DETENTS[level])+"x"
				rows = await _play(name,540,[[0,[code]],[360,[]]],speed==70 and level>=3)
				for row in rows:
					# At half power, a climbing trajectory can run out of energy
					# after release. Test the held steering corridor, not stall immunity.
					if row.time<6 or level>=3:
						_expect(absf(row.aoa)<deg_to_rad(33),name+": pitch escaped the 30-degree airflow corridor")
						_expect(row.attached_flow>0.9,name+": held pitch loses attached airflow")
					_expect(row.torque<1,name+": pitch saturates the actual attitude actuators")
				if code==KEY_W: downward_velocity = _at(rows,1.5).velocity[1]
				else: _expect(_at(rows,1.5).velocity[1]>downward_velocity+2.0,name+": S does not bend travel upward relative to W")
				# Low thrust/low airspeed may still descend under gravity. Normal
				# powered cruise must also achieve the absolute requested direction.
				if level>=3:
					var sign := -1.0 if code==KEY_W else 1.0
					# The new limb surfaces build lift as a low-speed pull settles.
					var response_time := 2.0 if speed==35 else 1.5
					_expect(_at(rows,response_time).velocity[1]*sign>2.0,name+": W/S curves travel the wrong way")
					for row in rows:
						if row.time>1 and row.time<6: _expect(row.pitch_rate*sign>0.05,name+": held pitch reverses under engine torque")
					_expect(rows[-1].omega<0.08,name+": full-power rotation does not arrest after release")
	for bank in [PI/2,PI]:
		var orientation := Quaternion(Vector3.BACK,bank)*Quaternion(Vector3.RIGHT,-PI/2)
		var normal := Basis(orientation)*Basis(Vector3.RIGHT,PI/2)*Vector3.UP
		await _fixture(origin,orientation,Vector3(0,0,-70),3)
		rows = await _play("banked_pitch_"+str(int(rad_to_deg(bank))),360,[[0,[KEY_S]]],false)
		for row in rows: _expect(absf(row.aoa)<deg_to_rad(33),"Bank/inversion swaps or destabilizes pitch")
		var turning: Dictionary = _at(rows,1.5)
		_expect(Vector3(turning.velocity[0],turning.velocity[1],turning.velocity[2]).dot(normal)>2,"Banked S does not pull toward the wing normal")
	# Braking permits a deliberate combat departure; cutoff retains free rotation.
	await _fixture(origin,Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,0,-70),3)
	rows = await _play("combat_departure",240,[[0,[KEY_S,KEY_SHIFT]]],false)
	_expect(_at(rows,1.0).effective_rates[0]>1.8 and _at(rows,1.0).flight_protection<0.01,"Brake input failed to release the pitch envelope")
	# At this dynamic pressure the real cold ports may saturate. An impossible
	# moment must be reported rather than supplied as a free body torque.
	_expect(_peak(rows,"aoa")>deg_to_rad(45) or rows.any(func(row):return row.rcs_saturated),"Blocked departure hides its physical actuator limit")
	await _fixture(origin,Quaternion(Vector3.RIGHT,-PI/2),Vector3(35,0,-70),0)
	rows = await _play("unpowered_rotation",240,[[0,[KEY_S]]],false)
	_expect(_peak(rows,"angle")>PI/2 and _peak(rows,"flight_protection")==0,"Unpowered rotation is trapped by flight protection")
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	rows = await _play("hover_yaw",240,[[0,[KEY_Q]],[150,[]]])
	_expect(_peak(rows,"angle")>0.8 and absf(_at(rows,0.8).yaw_rate)>0.5,"Q does not yaw around the fixed aircraft axis")
	_expect(absf(_at(rows,0.8).roll_rate)<0.1,"Q yaw became longitudinal roll in upright space motion")
	_expect(_peak(rows,"arm_asymmetry_size")>0.7 and _peak(rows,"leg_asymmetry_size")>0.3,"Hover yaw lacks deliberate arm/leg roles")
	_keys([])
	report["failures"] = failures.duplicate()
	report["controller_sha256"] = FileAccess.get_sha256("res://aerial/flight_controller.gd")
	report["pose_sha256"] = {}
	for file in ["flight_pose.gd","arm_pose.gd","mech_rig_profile.gd"]: report.pose_sha256[file] = FileAccess.get_sha256("res://aerial/"+file)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	scene.queue_free()
	await process_frame
	completed = true
	if failures.is_empty():
		print("Flight control checks passed: half-second fourfold directional bursts, tap/cooldown/reset semantics, immediate pitch/roll, physical nozzle limits, flight envelope, inversion, departures and free cutoff rotation.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check_burst_clock() -> void:
	for hz in [30,60,144,240]:
		var fc = Controller.new()
		fc.hover_assist = 1.0
		var dt: float = 1.0/hz
		fc._read_commands({"forward":true,"right":true},dt)
		_expect(fc.rotation_request.is_equal_approx(Vector3(-1,0,-1)),"Tap locks normal pitch/roll")
		_expect(fc.burst_direction.is_equal_approx(Vector3(1,0,-1).normalized()),"Diagonal boost is not normalized")
		for tick in hz*2:
			fc._read_commands({"forward":true,"right":true},dt)
			if tick==int(hz*0.25): _expect(is_equal_approx(fc.burst_amount,1.0),"Burst never reaches full output")
			if tick>=int(hz*0.5): _expect(fc.burst_remaining<0.000001 and fc.burst_amount==0.0,"Burst duration depends on clock or held keys")
		fc.reset()
		fc.hover_assist = 1.0
		fc._read_commands({"forward":true},dt)
		for tick in hz-1: fc._read_commands({},dt)
		fc._read_commands({"back":true},dt)
		_expect(is_equal_approx(fc.burst_remaining,0.5) and fc.burst_direction==Vector3.BACK,"Ready re-tap fails to choose the new direction")
		# An early tap is discarded, never queued for cooldown expiry.
		for tick in int(hz*0.6): fc._read_commands({},dt)
		fc._read_commands({"left":true},dt)
		_expect(fc.burst_remaining<0.000001,"Early tap bypasses cooldown")
		for tick in hz: fc._read_commands({"left":true},dt)
		_expect(fc.burst_remaining==0,"Cooldown expiry repeats a held/rejected tap")
		fc._read_commands({},dt)
		fc._read_commands({"left":true,"precision":true},dt)
		_expect(fc.burst_direction.is_equal_approx(Vector3.LEFT*0.35),"Precision does not scale directional intention")
		fc.detent = 0
		fc._read_commands({},dt)
		_expect(fc.burst_remaining<=Controller.HOVER_BURST_RAMP,"Cutoff does not begin burst cancellation")
		for tick in ceili(hz*Controller.HOVER_BURST_RAMP): fc._read_commands({},dt)
		_expect(fc.burst_remaining==0 and fc.burst_amount==0,"Cutoff cannot finish cancelling the burst")
		fc.reset()
		_expect(fc.burst_remaining==0 and fc.burst_cooldown==0 and fc.burst_direction==Vector3.ZERO,"Reset leaves a stale burst")
	# Flight, cutoff and yaw cannot arm the hover-only boost.
	var fc = Controller.new()
	fc._read_commands({"forward":true},1.0/60)
	_expect(fc.burst_remaining==0 and fc.rotation_request.x== -1,"Flight tap either boosts or loses pitch")
	fc.hover_assist = 1.0
	fc._read_commands({"yaw_left":true},1.0/60)
	_expect(fc.burst_remaining==0 and fc.rotation_request.y==1,"Yaw incorrectly arms directional boost")
