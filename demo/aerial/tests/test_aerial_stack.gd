extends SceneTree

var completed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(15.0).timeout.connect(_checks_timeout)
	var prism := preload("res://aerial/geometry.gd")._triangular_prism([Vector3(12,0,-5),Vector3(25,0,10),Vector3(13,0,7)],Vector3.DOWN)
	var normals: PackedVector3Array = prism.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var top := false
	var bottom := false
	for normal in normals:
		top = top or normal.y > 0.99
		bottom = bottom or normal.y < -0.99
	assert(top and bottom,"Detached aircraft parts lost opposing surface normals")
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	await process_frame
	await process_frame
	assert(scene.hero.get_child_count() >= 4,"Aircraft body/canopy/exhaust missing")
	var frozen_pose: Transform3D = scene.hero.transform
	scene._update_hero_pose(0.0)
	assert(scene.hero.transform.is_equal_approx(frozen_pose),"Frozen and live aircraft poses disagree")
	var clouds = scene.clouds
	assert(clouds.batches.size() == 4,"Cloud silhouette variants were not instanced")
	var vertices_by_shape := []
	for variant in clouds.batches.size():
		var vertices: PackedVector3Array = clouds.batches[variant].multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		vertices_by_shape.append(vertices)
		for index in range(0,vertices.size(),23):
			assert(absf(clouds._shape_density(vertices[index],variant)-0.074074) < 0.01,"Cloud density does not match its visible envelope")
		assert(clouds._shape_density(Vector3(0,-0.85,0),variant) == 0.0,"Cloud fog leaked below a variant's flattened base")
	assert(vertices_by_shape[0] != vertices_by_shape[1],"Clouds still repeat one silhouette")
	for active in range(19):
		clouds.set_coverage(float(active)/18.0)
		var visible_banks := 0
		for batch in clouds.batches: visible_banks += batch.multimesh.visible_instance_count
		assert(visible_banks == active,"Partial cloud cover diverged across silhouette batches")
	clouds.set_coverage(1.0)
	var bank: Vector4 = clouds.banks[0]
	var inside: Vector3 = clouds.to_global(Vector3(bank.x,bank.y,bank.z))
	assert(clouds.density_at(inside) > 0.99,"Cloud centers must be traversable weather volumes")
	var outside: Vector3 = scene.camera.position
	scene.camera.position = inside
	await process_frame
	await process_frame
	assert(scene.environment.fog_enabled and scene.environment.fog_density > 0.02,"Cloud entry did not reduce visibility")
	scene.storm = true
	scene.set_palette(false)
	await process_frame
	await process_frame
	assert(scene.post_material.get_shader_parameter("rain_strength") > 0.9,"Storm cloud entry did not enable camera rain")
	clouds.set_coverage(0.0)
	for batch in clouds.batches:
		assert(batch.multimesh.visible_instance_count == 0,"Coverage left a visible cloud variant")
	await process_frame
	await process_frame
	assert(not scene.environment.fog_enabled and scene.post_material.get_shader_parameter("rain_strength") == 0.0,"Invisible banks still produced weather")
	clouds.set_coverage(1.0)
	scene.storm = false
	scene.set_palette(false)
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
	completed = true
	print("Aerial checks passed: consistent pose, cloud coverage, storm entry rain, fixed world trails, bounded storage, teleport handling, VFX palette and expiry.")
	quit()

func _checks_timeout() -> void:
	if not completed:
		push_error("Aerial checks did not finish; inspect earlier assertion or script errors.")
		quit(1)
