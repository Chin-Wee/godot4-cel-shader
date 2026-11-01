extends SceneTree

# Fixed-input behavioral replays: DCS Su-27 flight and Elite Dangerous momentum.
# This is a test driver, never a gameplay movement/pose controller.
const Controller = preload("res://aerial/flight_controller.gd")
const HZ := 60
var completed := false
var viewport: SubViewport
var scene
var held := []
var output := "/tmp/flight-scenarios"
var capture_enabled := false
var failures := []
var report := {}
var replay_label: Label

func _initialize() -> void:
	call_deferred("_capture")

func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func _keys(keys: Array) -> void:
	for code in held:
		if not code in keys: _event(code, false)
	for code in keys:
		if not code in held: _event(code, true)
	held = keys.duplicate()
	# Reuse the actor's existing replay-input path. OS focus/key releases must
	# never change a hardcoded timeline while the user works in another app.
	scene.hero.controls = {}
	for action in Controller.ACTION_KEYS:
		scene.hero.controls[action.trim_prefix("flight_")] = keys.has(Controller.ACTION_KEYS[action])

func _event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	scene._unhandled_input(event) # Same native InputEvent/InputMap handler as play.

func _save(path: String) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.force_sync()
	RenderingServer.force_draw(false) # Offscreen capture needs no window presentation.
	var frame := viewport.get_texture().get_image()
	assert(not frame.is_empty() and frame.get_size() == viewport.size)
	assert(frame.save_png(path) == OK)

func _fixture(origin: Vector3, orientation: Quaternion, speed: Vector3, level: int) -> void:
	_keys([])
	scene.animate = true
	scene.hero.freeze = true
	await _ticks(1)
	scene.hero.reset_flight(origin, orientation, speed)
	scene.hero.controller.detent = level
	scene.hero.controller.engine_level = Controller.DETENTS[level]
	scene.hero.freeze = false
	await _ticks(3)

func _setup_capture() -> void:
	assert(Engine.physics_ticks_per_second == HZ, "Run these fixed inputs at 60 physics ticks/s")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	capture_enabled = DisplayServer.get_name() != "headless" and not "--metrics-only" in args
	assert(output.is_absolute_path() and DirAccess.make_dir_recursive_absolute(output) == OK)
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,600)
	viewport.own_world_3d = true
	viewport.msaa_3d = root.msaa_3d
	# Physics keeps ticking. Render only requested captures, independent of the GPU.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	viewport.add_child(scene)
	scene.set_process(false)
	scene.set_process_unhandled_input(false)
	scene.hero.player_controlled = false
	scene.follow_camera = false
	scene.clouds.set_coverage(0.4)
	if DisplayServer.get_name() != "headless":
		root.title = "Godot flight scenario validation"
		root.mode = Window.MODE_MINIMIZED
	if capture_enabled:
		replay_label = Label.new()
		replay_label.position = Vector2(20,555)
		replay_label.add_theme_font_size_override("font_size",18)
		replay_label.add_theme_constant_override("outline_size",4)
		replay_label.add_theme_color_override("font_outline_color",Color.BLACK)
		scene.hud.add_child(replay_label)
	await _ticks(2)

func _capture() -> void:
	create_timer(240).timeout.connect(func():
		if not completed: push_error("Flight scenario replays did not finish"); quit(1))
	await _setup_capture()
	await _hover()
	await _fighter()
	await _coast()
	await _fall()
	await _landing()
	await _braking()
	await _retro()
	await _maneuvers()
	await _bodyflight()
	await _transitions()
	await _endurance()
	_keys([])
	scene.animate = false
	for name in ["hover","fighter","inverted","coast","fall","landing","braking","retro","maneuvers","bodyflight","transitions","endurance"]:
		_expect(report.has(name),"Replay did not complete: "+name)
	report["failures"] = failures
	report["physics_hz"] = HZ
	report["inputs_sha256"] = FileAccess.get_sha256("res://aerial/tests/capture_mech.gd")
	report["controller_sha256"] = FileAccess.get_sha256("res://aerial/flight_controller.gd")
	report["pose_sha256"] = {}
	for file in ["aerial_mech.gd","aerial_demo.gd","flight_pose.gd","arm_pose.gd","contact_pose.gd","mech_rig_profile.gd","mech_rig_profile.tres","pose_servo.gd"]:
		report.pose_sha256[file] = FileAccess.get_sha256("res://aerial/"+file)
	var data := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	data.store_string(JSON.stringify(report,"  "))
	data.close()
	scene.queue_free()
	await process_frame
	completed = true
	if failures.is_empty():
		print("Flight scenario replays passed: jump/hover, banked and inverted lift, unpowered attitude/momentum, skydiver contact and active body-flight, planted landing/jump, full-body braking/retro/steering/roll recovery, seamless transitions, full-thrust drag equilibrium.")
		quit()
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _hover() -> void:
	var ground: float = scene.ground_height(Vector3(175,0,340))
	await _fixture(Vector3(175,ground+45.2,340),Quaternion.IDENTITY,Vector3.ZERO,0)
	var rows: Array = await _play("hover",600,[[0,[KEY_R]],[1,[]],[2,[KEY_SPACE]],[3,[]],[4,[KEY_SPACE]],[5,[]],
		[120,[KEY_W]],[150,[]],[240,[KEY_D,KEY_CTRL]],[270,[]],[330,[KEY_Q]],[360,[]]])
	_expect(_peak(rows,"leg") > 0,"hover: R never produced a contact-leg push")
	_expect(_peak(rows,"height") > (ground+48.0)/10.0,"hover: jump never cleared the ground")
	_expect(report.hover.max_jerk < 700,"hover: jump or catch force arrived too abruptly")
	_expect(rows[-1].speed < 0.5 and rows[-1].upright > 0.99,"hover: neutral flight failed to settle upright")

func _fighter() -> void:
	await _fixture(Vector3(175,6000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,0,-70),3)
	var rows: Array = await _play("fighter",720,[[0,[]],[60,[KEY_D]],[217,[]],[280,[KEY_W]],[298,[]],[390,[KEY_D]],[547,[]]])
	_expect(_peak(rows,"engine") >= 1.99,"fighter: powered flight did not maintain thrust")
	_expect(_peak(rows,"inverted") > 0.9,"fighter: fixed roll did not reach inverted flight")
	_expect(_peak(rows,"aero") > 0.8,"fighter: never established useful airflow")
	# An inverted negative-AoA entry must produce upward lift, still using physics.
	var inverted := Quaternion(Vector3.FORWARD,PI)*Quaternion(Vector3.RIGHT,-PI/2-deg_to_rad(10))
	await _fixture(Vector3(175,6000,340),inverted,Vector3(0,0,-80),3)
	rows = await _play("inverted",180,[[0,[]]])
	_expect(rows[0].lift_up > 0,"fighter: inverted negative-AoA flight produced no upward lift")

func _coast() -> void:
	await _fixture(Vector3(175,6000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3(35,0,-70),0)
	var rows: Array = await _play("coast",360,[[0,[KEY_S]],[60,[KEY_S,KEY_D]],[120,[]],[210,[KEY_Q]],[240,[]]])
	_expect(_peak(rows,"engine") == 0 and _peak(rows,"hover") == 0,"coast: unpowered flight received main/hover assistance")
	_expect(_peak(rows,"angle") > 1.0,"coast: freely rotating chassis did not turn")
	_expect(rows[-1].velocity[0] > 0 and rows[-1].velocity[2] < 0,"coast: reorientation reversed existing travel")
	_expect(rows[-1].omega < 0.05,"coast: released angular input never settled")

func _fall() -> void:
	var ground: float = scene.ground_height(Vector3(175,0,340))
	await _fixture(Vector3(175,ground+5000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,-20,0),0)
	var rows: Array = await _play("fall",1320,[[0,[]],[180,[KEY_SHIFT]],[420,[]],[600,[KEY_SHIFT]]])
	_expect(report.fall.max_jerk < 80,"fall: spread force arrived too abruptly")
	_expect(_peak(rows,"contacts") > 0,"fall: native capsule never reached terrain")
	_expect(_peak(rows,"engine") == 0,"fall: descent silently powered the boosters")
	_expect(absf(_at(rows,6.0).velocity[1]) < absf(_at(rows,3.0).velocity[1]),"fall: spreading did not slow descent")

func _landing() -> void:
	# A flat, visible fixture isolates sole placement and contact events from
	# the aerial scene's irregular terrain. It never supplies movement.
	var platform := StaticBody3D.new()
	platform.collision_layer = 2
	platform.collision_mask = 8
	platform.position = Vector3(175,3100,340)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300,20,300)
	shape.shape = box
	platform.add_child(shape)
	var mesh := MeshInstance3D.new()
	var surface := BoxMesh.new()
	surface.size = box.size
	mesh.mesh = surface
	mesh.material_override = scene.get_node("Terrain").material_override
	platform.add_child(mesh)
	scene.add_child(platform)
	await _fixture(Vector3(175,3270,340),Quaternion.IDENTITY,Vector3(0,-8,0),0)
	var rows: Array = await _play("landing",480,[[0,[]],[240,[KEY_R]],[241,[]]])
	_expect(_peak(rows,"preparation")>0.1,"landing: no leg preparation before touchdown")
	_expect(_peak(rows,"impact")>0.1,"landing: actual contact produced no impact response")
	_expect(rows[-1].plants==2 and rows[-1].touchdowns==2,"landing: drop/jump did not create exactly two supported touchdowns")
	platform.queue_free()

func _braking() -> void:
	await _fixture(Vector3(175,7000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,0,-80),0)
	var rows: Array = await _play("braking",480,[[0,[]],[60,[KEY_SHIFT]],[240,[]]])
	_expect(_at(rows,2.5).speed < _at(rows,1.0).speed-10,"braking: spread did not shed speed")
	_expect(_peak(rows,"arm_span")>8.0,"braking: both arms never opened")
	_expect(_peak(rows,"knee")>0.8,"braking: legs did not brace")

func _retro() -> void:
	await _fixture(Vector3(175,7000,340),Quaternion(Vector3.RIGHT,PI/2),Vector3(0,0,-70),3)
	var rows: Array = await _play("retro",420,[[0,[]],[180,[KEY_SHIFT]],[240,[]]])
	_expect(_peak(rows,"retro")>0.8,"retro: opposing engines never selected reverse bracing")
	_expect(_peak(rows,"hand_forward")>2.0,"retro: neither arm caught the reverse-thrust load")
	_expect(rows[-1].velocity[2]>0,"retro: physics never accelerated back along the facing direction")

func _maneuvers() -> void:
	await _fixture(Vector3(175,7000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,0,-65),3)
	var rows: Array = await _play("maneuvers",600,[[0,[KEY_D]],[110,[]],[180,[KEY_A]],[290,[]],
		[360,[KEY_Q]],[390,[]],[450,[KEY_E]],[480,[]]])
	_expect(_peak(rows,"arm_asymmetry")>0.7 and _minimum(rows,"arm_asymmetry") < -0.7,"maneuvers: opposing turns have no mirrored arm action")
	_expect(_peak(rows,"roll_stop")>0.2,"maneuvers: roll release has no arrest/recovery phase")
	_expect(_peak(rows,"knee_asymmetry")>0.06 or _minimum(rows,"knee_asymmetry") < -0.06,"maneuvers: legs never scissor in a turn")

func _bodyflight() -> void:
	await _fixture(Vector3(175,7000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,-50,0),0)
	var rows: Array = await _play("bodyflight",540,[[0,[]],[60,[KEY_Q]],[88,[]],[165,[KEY_E]],[193,[]],
		[270,[KEY_D]],[300,[]],[360,[KEY_S]],[390,[]],[435,[KEY_W]],[465,[]]])
	_expect(_peak(rows,"engine")==0,"bodyflight: freefall silently powered the main engines")
	_expect(_peak(rows,"box")>0.8 and _peak(rows,"hand_height")>2.0,"bodyflight: arms never establish a raised box position")
	_expect(_peak(rows,"arm_asymmetry_size")>1.0,"bodyflight: hands remain mirrored through the turn")
	_expect(_peak(rows,"leg_asymmetry_size")>0.5,"bodyflight: freefall blending erased the leg stagger")

func _transitions() -> void:
	await _fixture(Vector3(175,7000,340),Quaternion.IDENTITY,Vector3.ZERO,2)
	# The hover entry now spends three seconds translating before tilt ramps in.
	# Brake while pulling upright; align the unpowered fall before re-ignition.
	var rows: Array = await _play("transitions",1800,[[0,[]],[120,[KEY_SPACE,KEY_W]],[121,[KEY_W]],[462,[]],
		[660,[KEY_C,KEY_S,KEY_SHIFT]],[661,[KEY_S,KEY_SHIFT]],[771,[]],
		[870,[KEY_C]],[871,[]],[872,[KEY_C]],[873,[]],[900,[KEY_S]],[984,[]],[1020,[KEY_W]],[1272,[]],
		[1320,[KEY_SPACE]],[1321,[]],[1322,[KEY_SPACE]],[1323,[]],[1324,[KEY_SPACE]],[1325,[]],[1368,[KEY_S]],[1524,[]]])
	_expect(report.transitions.max_jerk < 250,"transitions: brake or thrust handoff arrived too abruptly")
	_expect(_at(rows,9.0).forward > 0.9 and _at(rows,9.0).speed > 35,"transitions: hover-to-jet did not establish forward flight")
	_expect(_at(rows,13.5).upright > 0.9,"transitions: combat slide never became upright")
	_expect(_at(rows,13.0).speed > 10,"transitions: upright rotation erased the slide")
	_expect(_at(rows,15.5).engine == 0,"transitions: C cutoff did not reach zero")
	_expect(rows[-1].engine > 1.9 and rows[-1].forward > 0.85 and rows[-1].speed > 35,"transitions: re-ignition never recovered forward flight")

func _endurance() -> void:
	await _fixture(Vector3(175,200000,340),Quaternion(Vector3.RIGHT,-PI/2),Vector3(0,0,-70),4)
	var rows: Array = await _play("endurance",5400,[[0,[]]],false)
	var early: Dictionary = _at(rows,70.0)
	var late: Dictionary = _at(rows,89.0)
	# Even the least-drag orientation must dissipate more power than maximum
	# thrust plus gravity can supply above this speed. This is not a speed clamp.
	var drag_scale: float = 0.5 * scene.hero.controller.air_density * Controller.AERO_AREA_M2 * (Controller.BASE_DRAG_CD + Controller.HIGH_SPEED_DRAG_CD)
	var bound := sqrt(5.0 * scene.hero.mass * Controller.GRAVITY / drag_scale)
	report.endurance["physical_speed_bound"] = bound
	_expect(_peak(rows,"speed") < minf(175,bound*1.03),"endurance: full thrust exceeded the physical drag ceiling")
	_expect(absf(late.speed-early.speed) < 2.0,"endurance: speed never converged under sustained full thrust")
	_expect(late.omega < 0.1,"endurance: uncommanded full-power rotation did not settle")

func _play(name: String, count: int, events: Array, capture := true) -> Array:
	var mech = scene.hero
	var fc = mech.controller
	var rows := []
	var event_index := 0
	var max_speed := 0.0
	var max_jerk := 0.0
	var max_residual := 0.0
	var last_acceleration := Vector3.ZERO
	var initial: Quaternion = mech.quaternion
	for tick in count:
		if event_index < events.size() and tick == events[event_index][0]:
			_keys(events[event_index][1])
			event_index += 1
		var before: Vector3 = fc.velocity
		var force: Vector3 = fc.main_force+fc.aero_force+fc.leg_force
		await _ticks(1)
		scene._process(1.0/HZ)
		var acceleration: Vector3 = fc.acceleration
		var jerk: float = (acceleration-last_acceleration).length()*HZ
		last_acceleration = acceleration
		var residual: float = (fc.velocity-before-(force/mech.mass+Vector3.DOWN*Controller.GRAVITY)/HZ).length()
		if tick > 2 and not mech.collided:
			max_jerk = maxf(max_jerk,jerk)
			max_residual = maxf(max_residual,residual)
		max_speed = maxf(max_speed,fc.velocity.length())
		_expect(fc.velocity.is_finite() and mech.position.is_finite(),name+": non-finite physics state")
		_expect(fc.aero_power <= 1.0,name+": passive surfaces added translation/rotation energy")
		if tick%6 == 0:
			var ti: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Torso")].affine_inverse()
			var knees := []
			var flex := []
			for side in 2:
				var hip: Vector3 = mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.thigh_bones[side])].origin
				var knee: Vector3 = mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.knee_bones[side])].origin
				var foot: Vector3 = mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.foot_bones[side])].origin
				knees.append(ti*knee)
				flex.append((knee-hip).angle_to(foot-knee))
			var wing: Basis = mech.global_basis*Basis(Vector3.RIGHT,PI/2)
			var body_frame: Basis = (mech.global_basis.inverse()*mech.skeleton.global_basis).orthonormalized()
			var left_knee: Vector3 = body_frame*mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.knee_bones[0])].origin
			var right_knee: Vector3 = body_frame*mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.knee_bones[1])].origin
			var torso_index: int = mech.skeleton.find_bone("Torso")
			var torso_up: Vector3 = mech.skeleton.global_basis.orthonormalized()*mech.bone_poses[torso_index].basis.orthonormalized()*mech.skeleton.get_bone_global_rest(torso_index).basis.orthonormalized().inverse()*Vector3.UP
			var lift: Vector3 = fc.aero_force.slide(fc.air_velocity.normalized()) if fc.air_velocity.length_squared()>0.00001 else Vector3.ZERO
			rows.append({"time":float(tick)/HZ,"speed":fc.velocity.length(),"height":mech.position.y/10.0,
				"velocity":_array(fc.velocity),"command":_array(fc.rotation_command),"acceleration":_array(acceleration),"omega":fc.angular_velocity.length(),
				"alpha":fc.angular_acceleration.length(),"engine":fc.engine_level,"hover":fc.hover_assist,"aero":fc.aero_authority,
				"aoa":fc.angle_of_attack,"slip":fc.sideslip,"attached_flow":fc.attached_flow,"flight_protection":fc.flight_protection,
				"hover_translation":_array(fc.hover_translation),"hover_hold":[fc.hover_hold.x,fc.hover_hold.y],"requested_rates":_array(fc.requested_rates),
				"move_intent":_array(mech.rig.motion.move_intent),"reach":_array(mech.rig.motion.reach),"gather":[mech.rig.motion.gather.x,mech.rig.motion.gather.y],
				"pitch_rate":fc.angular_velocity.dot(fc.pilot_frame().x),
				"yaw_rate":fc.angular_velocity.dot(mech.global_basis.y),
				"bank":atan2(wing.y.x,wing.y.y),"visual_lean":acos(clampf(torso_up.dot(mech.global_basis.y),-1,1)),
				"upright":mech.global_basis.y.y,"forward":mech.global_basis.y.dot(Vector3.FORWARD),"inverted":-wing.y.y,
				"angle":initial.angle_to(mech.quaternion),"brake":fc.brake_amount,"leg":fc.leg_force.length(),"lift_up":lift.y,
				"contacts":int(mech.collided),"torque":fc.torque_fraction,
				"pose_weights":Array(mech.rig.posture_weights),"plants":int(mech.rig.contacts.planted[0])+int(mech.rig.contacts.planted[1]),
				"preparation":mech.rig.contacts.preparation,"impact":mech.rig.contacts.impact,"touchdowns":mech.rig.contacts.touchdown_count,
				"retro":mech.rig.motion.retro,"roll_stop":mech.rig.motion.roll_stop,
				"flare":mech.rig.motion.flare,"left_elbow":_array(mech.rig.arms.elbow_positions[0]),"right_elbow":_array(mech.rig.arms.elbow_positions[1]),
				"drive":mech.rig.motion.drive,"prepare_effort":mech.rig.motion.prepare,"redirect":mech.rig.motion.redirect,
				"effort_phase":mech.rig.effort_phase,"lead_side":mech.rig.lead_side,"role_strength":mech.rig.motion.asymmetry,
				"alignment":mech.rig.motion.alignment,"request_alignment":mech.rig.motion.request_alignment,"load_direction":_array(mech.rig.motion.load_direction),
				"main_force":_array(fc.main_force),"requested_main_force":_array(fc.requested_main_force),
				"main_torque":_array(fc.main_torque),"aero_torque":_array(fc.aero_torque),"rcs_torque":_array(fc.rcs_torque),"aero_power":fc.aero_power,
				"gimbal_peak":fc.motor_angles.map(func(angle): return angle.length()).max(),"rcs_saturated":fc.torque_saturated,
				"left_fingers":mech.rig.arms.finger_curl[0],"right_fingers":mech.rig.arms.finger_curl[1],
				"box":mech.rig.motion.box,"steer":_array(mech.rig.motion.steer),
				"behavior_weights":Array(mech.rig.behavior_weights),"launch_pose":mech.rig.motion.launch,"track_pose":mech.rig.motion.track,
				"left_wrist":_array(mech.rig.arms.wrists[0].value),"right_wrist":_array(mech.rig.arms.wrists[1].value),
				"arm_span":absf(mech.rig.arms.hands[0].x-mech.rig.arms.hands[1].x),
				"arm_asymmetry":mech.rig.arms.hands[0].z-mech.rig.arms.hands[1].z,
				"arm_asymmetry_size":mech.rig.arms.hands[0].distance_to(mech.rig.arms.hands[1]*Vector3(-1,1,1)),
				"leg_asymmetry_size":knees[0].distance_to(knees[1]*Vector3(-1,1,1)),
				"hand_forward":(mech.rig.arms.hands[0].z+mech.rig.arms.hands[1].z)*0.5,
				"hand_height":(mech.rig.arms.hands[0].y+mech.rig.arms.hands[1].y)*0.5,
				"knee":flex[0],"knee_asymmetry":flex[0]-flex[1],
				"knee_height_difference":left_knee.y-right_knee.y,
				"chest":_array(mech.rig.chest.value),"hip_pose":_array(mech.rig.hips.value),
				"left_hand":_array(mech.rig.arms.hands[0]),"right_hand":_array(mech.rig.arms.hands[1]) })
		if capture_enabled and capture and tick%4 == 0:
			var names := PackedStringArray()
			for key in held: names.append(OS.get_keycode_string(key))
			replay_label.text = "%s · %.1f s · %s" % [name.to_upper(), float(tick)/HZ, " + ".join(names) if not names.is_empty() else "NO KEYS"]
			_position_capture_camera()
			# Finish queued camera/text updates before drawing, within this frame.
			call_deferred("_save",output.path_join("%s-%04d.png"%[name,tick/4]))
	_keys([])
	report[name] = {"inputs":events,"samples":rows,"max_speed":max_speed,"max_jerk":max_jerk,"max_motion_residual":max_residual}
	_expect(max_residual < 0.3,name+": velocity changed outside the applied force budget")
	print("SCENARIO ",name," max_speed=",snappedf(max_speed,0.01)," final_speed=",snappedf(rows[-1].speed,0.01)," jerk=",snappedf(max_jerk,0.1)," residual=",snappedf(max_residual,0.001))
	return rows

func _position_capture_camera() -> void:
	scene.camera.position = scene.hero.position+Vector3(165,55,115)
	scene.camera.look_at(scene.hero.position)
	scene.camera.force_update_transform()

func _expect(ok: bool, message: String) -> void:
	if not ok and not message in failures: failures.append(message)

func _at(rows: Array, time: float) -> Dictionary:
	return rows[mini(int(time*10),rows.size()-1)]

func _peak(rows: Array, key: String) -> float:
	var peak := -INF
	for row in rows: peak = maxf(peak,float(row[key]))
	return peak

func _array(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func _minimum(rows: Array, key: String) -> float:
	var result := INF
	for row in rows: result = minf(result,float(row[key]))
	return result
