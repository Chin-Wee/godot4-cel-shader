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
	scene.trigger_explosion(325)
	scene.explosion.set_process(false)
	var frames := ceili((scene.explosion.duration+0.4)/0.06)+1
	for frame in frames:
		scene.explosion.set_time(float(frame)*0.06)
		await _save_frame(output.path_join("burst-%03d.png"%frame))
	var last := Image.load_from_file(output.path_join("burst-%03d.png"%(frames-1)))
	var peak := Image.load_from_file(output.path_join("burst-007.png"))
	var smoke := Image.load_from_file(output.path_join("burst-025.png"))
	assert(peak.get_data() != smoke.get_data(),"Rendered explosion does not transition from fire to smoke")
	scene.explosion.visible = false
	await _save_frame(output.path_join("burst-cleared.png"))
	assert(last.get_data() == Image.load_from_file(output.path_join("burst-cleared.png")).get_data(),"Preview cuts off a live explosion component")
	for seed_value in [326,327]:
		scene.trigger_explosion(seed_value)
		scene.explosion.set_process(false)
		for time in [0.12,0.42,1.2,2.4]:
			scene.explosion.set_time(time)
			await _save_frame(output.path_join("seed-%d-%.2f.png"%[seed_value,time]))
	assert(Image.load_from_file(output.path_join("seed-326-0.42.png")).get_data() != Image.load_from_file(output.path_join("seed-327-0.42.png")).get_data(),"Native bursts all look identical")
	var metadata := FileAccess.open(output.path_join("motion.json"),FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"seed":325,"step_seconds":0.06,"frames":frames,"renderer":RenderingServer.get_current_rendering_method()},"  "))
	if "--explosion-only" not in args:
		scene.explosion.visible = false
		var aircraft_basis: Basis = scene.hero.global_basis.orthonormalized()
		var nozzle: MeshInstance3D = scene.hero.find_child("EngineFlame*",true,false)
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
	print("VFX motion capture passed: complete independently moving bursts and seed variants. ",output)
	quit()
