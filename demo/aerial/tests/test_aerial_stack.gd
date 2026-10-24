extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	await process_frame
	await process_frame
	assert(scene.hero.get_child_count() >= 4,"Aircraft body/canopy/exhaust missing")
	var clouds = scene.clouds
	var bank: Vector4 = clouds.banks[0]
	var inside: Vector3 = clouds.to_global(Vector3(bank.x,bank.y,bank.z))
	assert(clouds.density_at(inside) > 0.99,"Cloud centers must be traversable weather volumes")
	var outside: Vector3 = scene.camera.position
	scene.camera.position = inside
	await process_frame
	await process_frame
	assert(scene.environment.fog_enabled and scene.environment.fog_density > 0.02,"Cloud entry did not reduce visibility")
	scene.camera.position = outside
	await process_frame
	await process_frame
	assert(not scene.environment.fog_enabled,"Cloud fog leaked outside the bank")
	var trail = scene.trails[0]
	assert(trail.sample_count > 200 and trail.multimesh.instance_count == 512,"Persistent trail history missing or unbounded")
	assert(trail.material_override.get_shader_parameter("effect_time") == trail.elapsed,"Frozen trail history has no shader clock")
	var fixed_transform: Transform3D = trail.multimesh.get_instance_transform(0)
	scene.hero.position += Vector3(0,0,-30)
	trail.sample_position(trail.emitter.global_position)
	assert(trail.multimesh.get_instance_transform(0) == fixed_transform,"Old trail samples followed the aircraft")
	var samples: int = trail.sample_count
	trail.sample_position(trail.emitter.global_position+Vector3(10000,0,0))
	assert(trail.sample_count == samples,"Teleport drew a cross-world trail")
	scene.set_palette(true)
	var palette_size: int = scene.palette_materials.size()
	scene.trigger_explosion()
	var explosion = scene.explosion
	explosion.set_process(false)
	explosion.set_time(0.7)
	assert(explosion.lobes.size() == 20,"Explosion must contain eight fire and twelve smoke lobes")
	assert(explosion.get_child_count() >= 36,"Explosion ring, arcs or streaks missing")
	assert(scene.palette_materials.size() == palette_size,"Transient effects leaked into persistent palette storage")
	assert(explosion.materials[0].get_shader_parameter("haze_color") == scene.current_haze,"New VFX did not inherit the active weather palette")
	scene.set_palette(false)
	assert(explosion.materials[0].get_shader_parameter("haze_color") == scene.current_haze,"Live VFX missed a palette transition")
	explosion._process(5.0)
	await process_frame
	await process_frame
	assert(not is_instance_valid(explosion),"Expired explosion was not freed")
	scene.queue_free()
	await process_frame
	print("Aerial checks passed: cloud entry/exit, fixed world trails, bounded storage, teleport handling, VFX palette and expiry.")
	quit()
