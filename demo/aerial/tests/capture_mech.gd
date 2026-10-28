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
			66: _keys([KEY_S]); _uncage(true)
			78: _keys([KEY_C])
			79: _keys([])
			96: _keys([KEY_D,KEY_SHIFT])
			99: _keys([])
			112: _keys([KEY_W])
			126: _keys([KEY_SPACE]); _uncage(false)
			127: _keys([])
		_step(scene,1.0/12.0)
		await _save_frame(output.path_join("flight-%03d.png"%frame))
		assert(not mech.actor.animation_player.is_playing(),"Authored flight animation is still running")
		_check_mounts(mech)
		if frame == 65: assert(mech.controller.aero_authority > 0.65,"Sequence failed to reach aerodynamic cruise")
		if frame == 90: assert(mech.basis.y.normalized().y > 0.8 and -mech.controller.velocity.z > 50,"Upright drift lost its original momentum")
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
	var data := FileAccess.open(output.path_join("telemetry.json"),FileAccess.WRITE)
	data.store_string(JSON.stringify(telemetry,"  "))
	data.close()
	scene.follow_camera = false
	mech.controller.reset(Vector3(175,700,340))
	mech.position = mech.controller.position
	mech.quaternion = mech.controller.attitude
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
	print("Native flight checks passed: keyboard detent/uncage/burst/recovery sequence, cruise/drift/inverted/stall poses, local motors, visible cold jets, walk and pause.")
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
