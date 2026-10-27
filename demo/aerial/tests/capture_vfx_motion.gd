extends "res://aerial/tests/capture_aerial.gd"

func _capture() -> void:
	create_timer(90.0).timeout.connect(_capture_timeout)
	if DisplayServer.get_name() == "headless":
		push_error("VFX motion capture requires native rendering")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var output := args[0] if not args.is_empty() else "/tmp/dmc-vfx-motion"
	assert(output.is_absolute_path() and DirAccess.make_dir_recursive_absolute(output) == OK)
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	scene.hud.visible = false
	scene.trigger_explosion()
	scene.explosion.set_process(false)
	for frame in 41:
		scene.explosion.set_time(float(frame)*0.06)
		await _save_frame(output.path_join("burst-%03d.png"%frame))
	scene.explosion.visible = false
	var aircraft_basis: Basis = scene.hero.global_basis.orthonormalized()
	var nozzle: MeshInstance3D = scene.hero.find_child("EngineFlame*",false,false)
	var anchor := nozzle.global_position
	scene.camera.position = anchor+aircraft_basis*Vector3(-27,9,10)
	scene.camera.look_at(anchor+aircraft_basis*Vector3(0,0,8),aircraft_basis.y)
	scene.set_afterburner_throttle(1.0)
	scene.afterburner_flow_phase = 0.0
	for frame in 37:
		scene._update_afterburners(1.0/24.0)
		assert(nozzle.global_position.is_equal_approx(anchor),"Afterburner pulses moved the nozzle")
		await _save_frame(output.path_join("exhaust-%03d.png"%frame))
	var first := Image.load_from_file(output.path_join("exhaust-000.png"))
	assert(first.get_data() != Image.load_from_file(output.path_join("exhaust-012.png")).get_data(),"Native exhaust motion is static")
	scene.queue_free()
	await process_frame
	completed = true
	print("VFX motion capture passed: shared-clock burst and nozzle-anchored exhaust. ",output)
	quit()
