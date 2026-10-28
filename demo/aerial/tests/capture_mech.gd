extends "res://aerial/tests/capture_aerial.gd"

const Controller = preload("res://aerial/flight_controller.gd")
var held: Array = []
var viewport: SubViewport

func _keys(keys: Array) -> void:
	for key in held:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = false
		Input.parse_input_event(event)
	held = keys
	for key in held:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func _step(scene: Node3D, delta: float) -> void:
	scene.animate = true
	scene._process(delta)
	for trail in scene.trails:
		if trail.is_processing(): trail._process(delta)
	scene.animate = false

func _capture() -> void:
	create_timer(240.0).timeout.connect(_capture_timeout)
	assert(DisplayServer.get_name() != "headless","Mech validation requires native rendering")
	var args := OS.get_cmdline_user_args()
	var output := args[0] if not args.is_empty() else "/tmp/gundam-flight"
	assert(output.is_absolute_path() and DirAccess.make_dir_recursive_absolute(output) == OK)
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	# A native offscreen viewport keeps capture resolution deterministic and lets
	# the user continue using their desktop without moving the validation camera.
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,800)
	viewport.own_world_3d = true
	viewport.msaa_3d = root.msaa_3d
	viewport.screen_space_aa = root.screen_space_aa
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(scene)
	root.title = "Godot flight validation"
	root.mode = Window.MODE_MINIMIZED
	scene.animate = false
	await _save_frame(output.path_join("controls.png"))
	scene.hud.visible = false
	var mech = scene.hero
	var telemetry := []
	for frame in 180:
		match frame:
			0: _keys([])
			6: _keys([KEY_W,KEY_SPACE])
			7: _keys([KEY_W])
			48: _keys([KEY_W,KEY_D])
			66: _keys([]); _uncage(true)
			90: _keys([KEY_A,KEY_SHIFT])
			93: _keys([])
			108: _keys([KEY_S]); _uncage(false)
			132: _keys([])
			144: _keys([KEY_W,KEY_Q])
			165: _keys([])
		_step(scene,1.0/12.0)
		await _save_frame(output.path_join("flight-%03d.png"%frame))
		assert(not mech.actor.animation_player.is_playing(),"Authored flight animation is still running")
		_check_mounts(mech)
		if frame == 47: assert(mech.controller.velocity.length() > 25,"W did not accelerate normal movement")
		assert(is_zero_approx(mech.controller.rotation_command.x) and is_zero_approx(mech.controller.rotation_command.z),"WASD controls pitch or roll")
		if frame%6 == 0: telemetry.append({"frame":frame,"velocity":str(mech.controller.velocity),"head_axis":str(mech.basis.y.normalized()),"aero":mech.controller.aero_authority,"uncaged":mech.controller.uncaged})
	_keys([])
	_uncage(false)
	# Isolate physics-derived poses from both sides, including belly-up drift.
	scene.clouds.set_coverage(0.0)
	for trail in scene.trails: trail.visible = false
	for scenario in ["hover","cruise","drift","inverted","stall"]:
		mech.controller.reset(Vector3(175,1200,340))
		mech.controller.aim_direction = Vector3.FORWARD
		var raw := {}
		if scenario != "hover":
			mech.controller.attitude = Quaternion(Vector3.RIGHT,-PI/2)
			mech.controller.velocity = Vector3(0,0,-70)
		if scenario in ["drift","inverted","stall"]:
			raw.uncage = true
			mech.controller.attitude = Quaternion.IDENTITY if scenario == "drift" else Quaternion(Vector3.FORWARD,PI)*Quaternion(Vector3.RIGHT,-PI/2)
		if scenario == "stall": raw.brake = true
		for frame in 90: mech.step_flight(1.0/60.0,raw,0.0)
		scene._update_afterburners()
		scene.reset_camera()
		await _save_frame(output.path_join(scenario+"-rear.png"))
		_check_mounts(mech)
		scene.camera_yaw += PI
		scene._update_camera(0.0)
		await _save_frame(output.path_join(scenario+"-front.png"))
	# Native low-ready -> measured receiver support -> wide release -> regrip.
	scene.follow_camera = false
	mech.controller.reset(Vector3(175,1200,340))
	mech.position = mech.controller.position
	mech.quaternion = Quaternion.IDENTITY
	for frame in 90: mech.update_animation(1.0/60.0)
	var minimum_support := 1.0
	var maximum_support := 0.0
	var maximum_contact_error := 0.0
	for frame in 72:
		mech.controller.aiming = frame >= 10
		var yaw := sin(float(frame)*0.09)*0.25 if frame < 38 or frame > 55 else -1.3
		mech.controller.aim_direction = Vector3(sin(yaw),0,-cos(yaw))
		mech.controller.gaze_target = mech.position+mech.controller.aim_direction*4500
		if frame in [26,31,36]: mech.rig.kick_weapon()
		mech.update_animation(1.0/12.0)
		scene._update_afterburners(1.0/12.0)
		scene.camera.position = mech.position+Vector3(135,25,-165)
		scene.camera.look_at(mech.position+Vector3.UP*15)
		await _save_frame(output.path_join("arms-%03d.png"%frame))
		_check_mounts(mech)
		var right: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Hands.R")]
		var left: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Hands.L")]
		var weight: float = mech.rig.weapon.support_weight
		minimum_support = minf(minimum_support,weight)
		maximum_support = maxf(maximum_support,weight)
		if weight > 0.98:
			var error: float = left.origin.distance_to(right*mech.rig.weapon.support_offset)
			maximum_contact_error = maxf(maximum_contact_error,error)
			assert(error < 0.08,"Offhand detached from the rifle receiver")
	assert(maximum_support > 0.95 and minimum_support < 0.05,"Offhand cannot brace/release")
	var metrics := FileAccess.open(output.path_join("arm-metrics.json"),FileAccess.WRITE)
	metrics.store_string(JSON.stringify({"maximum_contact_error_source_units":maximum_contact_error,"maximum_support":maximum_support,"minimum_support":minimum_support},"  "))
	metrics.close()
	var data := FileAccess.open(output.path_join("telemetry.json"),FileAccess.WRITE)
	data.store_string(JSON.stringify(telemetry,"  "))
	data.close()
	scene.follow_camera = false
	mech.controller.reset(Vector3(175,700,340))
	mech.position = mech.controller.position
	mech.quaternion = mech.controller.attitude
	mech.controller.aiming = true
	mech.controller.aim_direction = (scene.wingman.position-mech.position).normalized()
	mech.controller.aim_point = scene.wingman.position
	mech.controller.gaze_target = scene.wingman.position
	for frame in 90: mech.update_animation(1.0/60.0)
	await process_frame
	await process_frame
	scene.animate = true
	scene.fire_weapon()
	scene.animate = false
	assert(scene.hit_time > 0.0,"Rifle failed to hit the native target collider")
	scene.camera.position = mech.position+Vector3(150,45,90)
	scene.camera.look_at(mech.position)
	await _save_frame(output.path_join("rifle-fire.png"))
	# Outlet close-ups: all bases stay seated on their animated attachment bones.
	scene.follow_camera = false
	mech.controller.reset(Vector3(175,600,340))
	for frame in 180: mech.step_flight(1.0/60.0,{},0.0)
	scene.set_afterburner_throttle(1.0)
	await process_frame
	for flame in mech.flames:
		var anchor: Vector3 = flame.global_position
		var direction: Vector3 = flame.global_basis.z.normalized()
		scene.camera.position = anchor+direction*14.0+Vector3.UP*8.0+mech.global_basis.x.normalized()*10.0
		scene.camera.look_at(anchor+direction*2.0)
		await _save_frame(output.path_join(str(flame.name)+".png"))
	for index in mech.gas_jets.size():
		mech.controller.reset(Vector3(175,600,340))
		var controls := {"yaw_right":true,"uncage":true}
		for frame in 30: mech.step_flight(1.0/60.0,controls,0.0)
		for frame in 60:
			mech.step_flight(1.0/60.0,controls,0.0)
			scene._update_afterburners()
			if mech.gas_jets[index].visible: break
		await process_frame
		var jet: MeshInstance3D = mech.gas_jets[index]
		assert(jet.visible,"Maneuver did not fire its cold-gas outlet")
		var direction: Vector3 = jet.global_basis.z.normalized()
		var anchor: Vector3 = jet.global_position
		scene.camera.position = anchor+direction*15.0+Vector3.UP*5.0+mech.global_basis.z.normalized()*8.0
		scene.camera.look_at(anchor+direction*2.0)
		var on_path := output.path_join(str(jet.name)+"-on.png")
		var off_path := output.path_join(str(jet.name)+"-off.png")
		await _save_frame(on_path)
		jet.visible = false
		await _save_frame(off_path)
		assert(Image.load_from_file(on_path).get_data() != Image.load_from_file(off_path).get_data(),"Cold-gas outlet is buried in armor")
	scene.set_walk_mode(true)
	await physics_frame
	scene.hero.update_animation(1.0)
	scene.set_palette(true)
	scene.camera.position = mech.position+Vector3(-130,70,160)
	scene.camera.look_at(mech.position)
	for frame in 36:
		var before: Vector3 = mech.position
		scene.walking_time += 1.0/12.0
		scene._update_walk_pose()
		mech.update_animation(1.0/12.0)
		scene.camera.position += mech.position-before
		await _save_frame(output.path_join("walk-%03d.png"%frame))
	assert(Image.load_from_file(output.path_join("walk-000.png")).get_data() != Image.load_from_file(output.path_join("walk-012.png")).get_data(),"Walk is static")
	var frozen := viewport.get_texture().get_image()
	await _save_frame(output.path_join("paused.png"))
	assert(frozen.get_data() == Image.load_from_file(output.path_join("paused.png")).get_data(),"Paused pose/VFX keeps animating")
	scene.queue_free()
	await process_frame
	completed = true
	print("Native flight checks passed: restored movement, disabled pitch/roll, low-ready/brace/release/recoil, measured offhand contact, rifle hit, thrusters, walk and pause.")
	quit()

func _check_mounts(mech: Node3D) -> void:
	var pivots: Array = mech.gimbals+mech.gas_gimbals
	var sockets: Array = mech.sockets+mech.gas_sockets
	for index in pivots.size():
		var relative: Basis = mech.neutral_bases[index].inverse()*pivots[index].basis
		assert(relative.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) <= mech.VECTOR_LIMIT+0.001,"Motor escaped its local cone")
		var bone: int = mech.skeleton.find_bone(sockets[index].bone_name)
		assert(sockets[index].global_transform.is_equal_approx(mech.skeleton.global_transform*mech.bone_poses[bone]),"Nozzle detached from the animated inlay")

func _save_frame(path: String) -> void:
	print("Capturing ",path.get_file())
	for frame in 3: await process_frame
	RenderingServer.force_draw()
	var rendered := viewport.get_texture().get_image()
	assert(not rendered.is_empty() and rendered.get_size() == viewport.size,"Native viewport changed resolution")
	assert(rendered.save_png(path) == OK)

func _uncage(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
