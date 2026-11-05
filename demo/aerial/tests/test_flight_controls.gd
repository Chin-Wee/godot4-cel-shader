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
	for entry in directions:
		await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
		var rows: Array = await _play("hover_"+entry[0],540,[[0,[entry[1]]],[240,[]]])
		for row in rows:
			if row.time<3.0:
				_expect(row.upright>cos(deg_to_rad(3)),entry[0]+": first three seconds tilt instead of translate")
				_expect(absf(row.command[0])+absf(row.command[2])<0.001,entry[0]+": early pitch/roll command")
				_expect(row.torque<1,entry[0]+": translation pose overwhelms the attitude actuators")
		var moving: Dictionary = _at(rows,2.5)
		_expect(Vector3(moving.velocity[0],moving.velocity[1],moving.velocity[2]).dot(entry[2])>2.0,entry[0]+": thrust moves in the wrong direction")
		_expect(Vector3(moving.main_force[0],moving.main_force[1],moving.main_force[2]).dot(entry[2])>scene.hero.mass,entry[0]+": no physical directional thrust")
		_expect(_at(rows,3.8).angle>deg_to_rad(1),entry[0]+": sustained hold never starts gradual tilt")
		_expect(rows[-1].upright>0.995 and rows[-1].speed<0.6,entry[0]+": release never catches drift upright")
		_expect(_peak(rows,"gimbal_peak")<=Controller.VECTOR_LIMIT+0.0001,entry[0]+": nozzle cone exceeded")
		_expect(_peak(rows,"omega")<1.0,entry[0]+": tilt/recovery develops an uncontrolled spin")
	var forward_hand: float = report.hover_forward.samples[25].hand_forward
	var reverse_hand: float = report.hover_back.samples[25].hand_forward
	_expect(reverse_hand>forward_hand+0.5,"Forward/reverse slides reuse the same hand pose")
	var left_pose: Dictionary = report.hover_left.samples[25]
	var right_pose: Dictionary = report.hover_right.samples[25]
	_expect(left_pose.arm_asymmetry_size>0.5 and right_pose.arm_asymmetry_size>0.5,"Lateral slides have mirrored passive arms")
	_expect(left_pose.knee_asymmetry*right_pose.knee_asymmetry<0,"Lateral slides do not exchange the leading leg")
	# Release/reversal resets the three-second promise, not just the visual pose.
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	var rows: Array = await _play("hover_reversal",480,[[0,[KEY_W]],[120,[KEY_S]],[300,[]]],false)
	for row in rows:
		if row.time<5.0: _expect(row.upright>cos(deg_to_rad(3)),"Reversal inherits an old hold timer")
	_expect(_at(rows,2.1).hover_hold[0]<0.2 and _at(rows,4.9).velocity[2]>1,"Reverse input does not restart directional thrust")
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	rows = await _play("hover_repress",420,[[0,[KEY_W]],[120,[]],[121,[KEY_W]],[300,[]]],false)
	for row in rows:
		if row.time<5.0: _expect(row.upright>cos(deg_to_rad(3)),"Re-press inherits the previous press's tilt time")
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	rows = await _play("diagonal_hover",180,[[0,[KEY_W,KEY_D]]],false)
	for row in rows:
		var planar := Vector3(row.hover_translation[0],0,row.hover_translation[2])
		_expect(planar.length()<=1.0001 and row.upright>cos(deg_to_rad(3)),"Diagonal hover doubles thrust or starts premature tilt")
	_expect(rows[-1].velocity[0]>2 and rows[-1].velocity[2]< -2,"Diagonal thrust does not combine the requested directions")
	# The force direction follows the chassis heading, independently of mouse look.
	await _fixture(origin,Quaternion(Vector3.UP,PI/2),Vector3.ZERO,2)
	scene.camera.orbit(Vector2(500,-80))
	rows = await _play("heading_relative",180,[[0,[KEY_W]]],false)
	_expect(rows[-1].velocity[0]<-2 and absf(rows[-1].velocity[2])<1,"Hover translation follows world/camera axes")
	# A powered climb crossing the old speed threshold cannot cancel this press.
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,3)
	rows = await _play("powered_hover",180,[[0,[KEY_W]]],false)
	for row in rows: _expect(row.upright>cos(deg_to_rad(3)),"Climb airspeed cuts short the translation interval")
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,1)
	rows = await _play("half_power_hover",180,[[0,[KEY_W]]],false)
	for row in rows: _expect(row.upright>cos(deg_to_rad(3)),"Half-power upright thrust tilts before three seconds")
	_expect(rows[-1].velocity[2]<-1,"Half-power hover input supplies no directional force")
	for entry in directions:
		await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,4)
		rows = await _play("full_power_hover_"+entry[0],180,[[0,[entry[1]]]],false)
		for row in rows:
			_expect(row.upright>cos(deg_to_rad(3)),"Full-power hover tilts before three seconds")
			# Pulsed cold gas permits small rate ripple instead of perfect lock.
			_expect(absf(row.yaw_rate)<0.1,entry[0]+": full-power translation develops uncommanded yaw")
			_expect(row.torque<1,entry[0]+": full-power translation exceeds attitude actuator reserve")
		var travel := Vector3(rows[-1].velocity[0],rows[-1].velocity[1],rows[-1].velocity[2])
		_expect(travel.dot(entry[2])>1,entry[0]+": full-power upright thrust loses its requested direction")
	# Initial lean inside the user's 30-degree margin still recovers upright.
	await _fixture(origin,Quaternion(Vector3.RIGHT,-deg_to_rad(25)),Vector3.ZERO,2)
	rows = await _play("tilted_hover",180,[[0,[KEY_W]]],false)
	_expect(rows[-1].upright>cos(deg_to_rad(3)),"A modest initial lean falls out of hover support")
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
	_expect(_peak(rows,"aoa")>deg_to_rad(45),"Pitch protection prevents deliberate braking departures")
	await _fixture(origin,Quaternion(Vector3.RIGHT,-PI/2),Vector3(35,0,-70),0)
	rows = await _play("unpowered_rotation",240,[[0,[KEY_S]]],false)
	_expect(_peak(rows,"angle")>PI/2 and _peak(rows,"flight_protection")==0,"Unpowered rotation is trapped by flight protection")
	await _fixture(origin,Quaternion.IDENTITY,Vector3.ZERO,2)
	rows = await _play("hover_yaw",240,[[0,[KEY_Q]],[150,[]]])
	_expect(_peak(rows,"angle")>0.8 and _minimum(rows,"upright")>0.99,"Q yaw loses upright stabilization")
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
		print("Flight control checks passed: three-second force translation, reset/reversal, powered climb, lean recovery, flight W/S envelope, bank/inversion, deliberate departure, free cutoff rotation and directional full-body posing.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)
