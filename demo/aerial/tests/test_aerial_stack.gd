extends SceneTree

var completed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(15.0).timeout.connect(_checks_timeout)
	var prism := preload("res://aerial/geometry.gd")._panel_prism([Vector3(12,0,-5),Vector3(25,0,10),Vector3(23,0,14),Vector3(13,0,7)],Vector3.DOWN)
	var normals: PackedVector3Array = prism.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var top := false
	var bottom := false
	var bevel := false
	for normal in normals:
		top = top or normal.y > 0.99
		bottom = bottom or normal.y < -0.99
		bevel = bevel or (absf(normal.y) > 0.05 and absf(normal.y) < 0.95)
	assert(top and bottom,"Detached aircraft parts lost opposing surface normals")
	assert(bevel,"Aircraft panels lost their bevel normals for rim lighting")
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	await process_frame
	await process_frame
	await _check_river_clearance(scene)
	_check_afterburners(scene)
	assert(scene.hero.get_child_count() >= 4,"Aircraft body/canopy/exhaust missing")
	var body_arrays: Array = scene.hero.get_node("Body").mesh.surface_get_arrays(0)
	var panel_colors: PackedColorArray = body_arrays[Mesh.ARRAY_COLOR]
	var has_body := false
	var has_livery := false
	for color in panel_colors:
		has_body = has_body or color.a > 0.99
		has_livery = has_livery or color.a < 0.01
	assert(has_body and has_livery,"Aircraft livery is not attached to its panel geometry")
	for wing_trail in scene.trails.slice(0,2):
		var attached := false
		for vertex in body_arrays[Mesh.ARRAY_VERTEX]:
			attached = attached or vertex.is_equal_approx(wing_trail.emitter.position)
		assert(attached,"A wingtip trail emitter is detached from its wing")
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
	assert(scene.post_material.get_shader_parameter("sun_visible") == 0.0,"Cloud interior still enabled direct-sun optics")
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
	explosion.set_time(0.2)
	var early_arc_size: float = explosion.accents[-1].scale.length()
	explosion.set_time(0.7)
	assert(explosion.accents[-1].scale.length() > early_arc_size*4.0,"Explosion arcs appeared at full radius during onset")
	explosion.set_time(1.8)
	assert(explosion.ring.material_override.get_shader_parameter("normalized_age") == 1.0,"Explosion accents outlived their burst")
	assert(explosion.materials[0].get_shader_parameter("normalized_age") < 1.0,"Fire ended before the smoke phase")
	explosion.set_time(3.4)
	assert(explosion.materials[0].get_shader_parameter("normalized_age") == 1.0 and explosion.materials[8].get_shader_parameter("normalized_age") < 1.0,"Fire and smoke no longer have separate lifetimes")
	explosion.set_time(0.7)
	assert(scene.palette_materials.size() == palette_size,"Transient effects leaked into persistent palette storage")
	assert(explosion.materials[0].get_shader_parameter("haze_color") == scene.current_haze,"New VFX did not inherit the active weather palette")
	assert(explosion.materials[8].get_shader_parameter("sun_direction") == scene.sun_direction,"New smoke did not inherit the active sunlight")
	scene.set_palette(false)
	assert(explosion.materials[0].get_shader_parameter("haze_color") == scene.current_haze,"Live VFX missed a palette transition")
	assert(explosion.materials[8].get_shader_parameter("sun_direction") == scene.sun_direction,"Live smoke missed a sunlight transition")
	explosion._process(5.0)
	await process_frame
	await process_frame
	assert(not is_instance_valid(explosion),"Expired explosion was not freed")
	scene.queue_free()
	await process_frame
	completed = true
	print("Aerial checks passed: consistent pose, cloud coverage, storm entry rain, fixed world trails, bounded storage, teleport handling, VFX palette and expiry.")
	quit()

func _check_river_clearance(scene: Node3D) -> void:
	# Native raycasts test the actual generated geometry at the river's own vertices.
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var collider := CollisionShape3D.new()
	collider.shape = scene.get_node("Terrain").mesh.create_trimesh_shape()
	ground.add_child(collider)
	scene.add_child(ground)
	await physics_frame
	var water: PackedVector3Array = scene.get_node("River").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in water:
		var point := scene.to_global(vertex)
		var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*20.0,point-Vector3.UP*20.0,2)
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
		assert(not hit.is_empty(),"Canyon floor is missing below the river")
		assert(hit.position.y < point.y-0.05,"Canyon terrain clips through the river ribbon")
	ground.queue_free()
	await process_frame

func _check_afterburners(scene: Node3D) -> void:
	var flames: Array[MeshInstance3D] = []
	var anchors: Array[Vector3] = []
	for aircraft in [scene.hero,scene.wingman]:
		var exit_z: float = aircraft.get_node("Intakes").mesh.get_aabb().end.z
		for child in aircraft.get_children():
			if not child.name.begins_with("EngineFlame"): continue
			flames.append(child)
			anchors.append(child.global_position)
			var bounds: AABB = child.mesh.get_aabb()
			assert(is_zero_approx(bounds.position.z) and is_equal_approx(bounds.end.z,1.0),"Exhaust is not normalized from nozzle to tip")
			assert(is_equal_approx(child.position.z,exit_z),"Exhaust anchor is detached from the nozzle exit")
	assert(flames.size() == 4,"Twin afterburners are missing from the aircraft")
	var previous_length := 0.0
	for throttle in [0.0,0.35,1.0]:
		scene.set_afterburner_throttle(throttle)
		assert(scene.afterburner_material.get_shader_parameter("throttle") == throttle,"Mesh and shader throttle differ")
		assert(flames[0].scale.z > previous_length,"Exhaust did not elongate with throttle")
		previous_length = flames[0].scale.z
		for index in flames.size():
			assert(flames[index].global_position.is_equal_approx(anchors[index]),"Scaling moved the exhaust nozzle anchor")
			assert(flames[index].visible == (throttle > 0.0),"Zero throttle left visible exhaust")
	scene.set_afterburner_throttle(0.35)
	scene._update_afterburners(0.1)
	var slow_phase: float = scene.afterburner_flow_phase
	scene.set_afterburner_throttle(1.0)
	assert(scene.afterburner_flow_phase == slow_phase,"Throttle change reset the noise phase")
	var before_pulse := flames[0].scale
	scene._update_afterburners(0.1)
	assert(scene.afterburner_flow_phase-slow_phase > slow_phase,"Higher throttle did not speed up the flow")
	assert(not flames[0].scale.is_equal_approx(before_pulse),"Afterburner silhouette does not pulse")
	assert(flames[0].global_position.is_equal_approx(anchors[0]),"Afterburner pulse shook the nozzle attachment")
	var frozen_phase: float = scene.afterburner_flow_phase
	var frozen_scale := flames[0].scale
	scene._process(0.1)
	assert(scene.afterburner_flow_phase == frozen_phase,"Paused scene still animated exhaust")
	assert(flames[0].scale.is_equal_approx(frozen_scale),"Paused scene still pulsed the exhaust")
	scene.afterburner_flow_phase = 99.99
	scene._update_afterburners(1.0)
	assert(scene.afterburner_flow_phase >= 0.0 and scene.afterburner_flow_phase < 100.0,"Exhaust clock grew without bound")
	scene.afterburner_flow_phase = 0.0
	scene._update_afterburners()

func _checks_timeout() -> void:
	if not completed:
		push_error("Aerial checks did not finish; inspect earlier assertion or script errors.")
		quit(1)
