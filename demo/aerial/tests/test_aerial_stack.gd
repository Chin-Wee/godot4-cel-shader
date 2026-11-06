extends SceneTree

const MechAssets = preload("res://actors/mechs/mech_assets.gd")
var completed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(15.0).timeout.connect(_checks_timeout)
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	await process_frame
	await process_frame
	await _check_river_clearance(scene)
	_check_afterburners(scene)
	await _check_mechs(scene)
	var frozen_pose: Transform3D = scene.hero.transform
	assert(scene.hero.transform.is_equal_approx(frozen_pose),"Frozen and live mech poses disagree")
	var clouds = scene.clouds
	assert(clouds.batches.size() == 4,"Cloud silhouette variants were not instanced")
	var vertices_by_shape := []
	for variant in clouds.batches.size():
		var vertices: PackedVector3Array = clouds.batches[variant].multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		vertices_by_shape.append(vertices)
		for index in range(0,vertices.size(),23):
			assert(absf(clouds.field_value(vertices[index],variant)) < 0.0001,"Cloud mesh and weather field diverged at the iso-surface")
		assert(clouds._shape_density(Vector3(0,-0.85,0),variant) == 0.0,"Cloud fog leaked below the density field")
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
	assert(scene.lighting.environment.fog_enabled and scene.lighting.environment.fog_density > 0.02,"Cloud entry did not reduce visibility")
	assert(scene.lighting.post_material.get_shader_parameter("sun_visible") == 0.0,"Cloud interior still enabled direct-sun optics")
	scene.lighting.storm = true
	scene.set_palette(false)
	await process_frame
	await process_frame
	assert(scene.lighting.post_material.get_shader_parameter("rain_strength") > 0.9,"Storm cloud entry did not enable camera rain")
	clouds.set_coverage(0.0)
	for batch in clouds.batches:
		assert(batch.multimesh.visible_instance_count == 0,"Coverage left a visible cloud variant")
	await process_frame
	await process_frame
	assert(not scene.lighting.environment.fog_enabled and scene.lighting.post_material.get_shader_parameter("rain_strength") == 0.0,"Invisible banks still produced weather")
	clouds.set_coverage(1.0)
	scene.lighting.storm = false
	scene.set_palette(false)
	scene.camera.position = outside
	await process_frame
	await process_frame
	assert(not scene.lighting.environment.fog_enabled,"Cloud fog leaked outside the bank")
	var trail = scene.trails[0]
	assert(trail.multimesh.instance_count == 512,"Trail storage is unbounded")
	trail.sample_position(trail.emitter.global_position)
	trail.sample_position(trail.emitter.global_position+Vector3(30,0,0))
	assert(trail.material_override.get_shader_parameter("effect_time") == trail.elapsed,"Frozen trail history has no shader clock")
	for layer_material in trail.palette_materials():
		assert(layer_material.get_shader_parameter("effect_time") == trail.elapsed,"A frozen trail layer missed its history clock")
	var fixed_transform: Transform3D = trail.multimesh.get_instance_transform(0)
	scene.hero.position += Vector3(0,0,-30)
	trail.sample_position(trail.emitter.global_position)
	assert(trail.multimesh.get_instance_transform(0) == fixed_transform,"Old trail samples followed the aircraft")
	var samples: int = trail.sample_count
	trail.sample_position(trail.emitter.global_position+Vector3(10000,0,0))
	assert(trail.sample_count == samples,"Teleport drew a cross-world trail")
	scene.set_palette(true)
	var palette_size: int = scene.lighting.palette_materials.size()
	scene.trigger_explosion()
	var explosion = scene.explosion
	explosion.set_process(false)
	explosion.set_time(0.7)
	assert(explosion.lobes.size() == 20,"Explosion must contain eight fire and twelve smoke lobes")
	assert(explosion.accents.size() == 12 and explosion.debris.size() == 6,"Explosion sparks or moving debris are missing")
	explosion.set_time(0.04)
	var early_size: float = explosion.lobes[0].scale.length()
	explosion.set_time(0.2)
	assert(explosion.lobes[0].scale.length() > early_size,"Explosion did not expand from its initial flash")
	explosion.set_time(1.8)
	assert(explosion.materials[0].get_shader_parameter("normalized_age") == 1.0,"Fire did not cool before the smoke phase")
	assert(explosion.lobes[8].visible,"Smoke ended with the initial flash")
	explosion.set_time(explosion.duration+0.1)
	for node in explosion.get_children(): assert(not node.visible,"Expired explosion component stayed visible")
	explosion.set_time(0.7)
	assert(scene.lighting.palette_materials.size() == palette_size,"Transient effects leaked into persistent palette storage")
	assert(explosion.materials[0].get_shader_parameter("haze_color") == scene.lighting.current_haze,"New VFX did not inherit the active weather palette")
	assert(explosion.materials[8].get_shader_parameter("sun_direction") == scene.lighting.sun_direction,"New smoke did not inherit the active sunlight")
	scene.set_palette(false)
	assert(explosion.materials[0].get_shader_parameter("haze_color") == scene.lighting.current_haze,"Live VFX missed a palette transition")
	assert(explosion.materials[8].get_shader_parameter("sun_direction") == scene.lighting.sun_direction,"Live smoke missed a sunlight transition")
	explosion._process(explosion.duration+1.0)
	await process_frame
	await process_frame
	assert(not is_instance_valid(explosion),"Expired explosion was not freed")
	scene.queue_free()
	await process_frame
	completed = true
	print("Aerial checks passed: white mechs, walk/hover/boost mapping, torso exhaust, consistent pose, cloud coverage, storm entry rain, fixed world trails, bounded storage, teleport handling, VFX palette and expiry.")
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
	for mech in [scene.hero,scene.wingman]:
		for flame in mech.flames:
			flames.append(flame)
			anchors.append(flame.global_position)
			var bounds: AABB = flame.mesh.get_aabb()
			assert(is_zero_approx(bounds.position.z) and is_equal_approx(bounds.end.z,1.0),"Exhaust is not normalized from nozzle to tip")
			assert(flame.get_parent() in mech.gimbals and flame.position.z > 0.0,"Exhaust is detached from its vectoring pivot")
	assert(flames.size() == scene.hero.MOUNTS.size()*2,"Each mech must have exhaust for every main thruster")
	# Frozen render fixture supplies delivered forces; a material preview slider
	# must never fabricate a lit engine independently of these outlet outputs.
	var saved_forces := [scene.hero.controller.motor_forces.duplicate(),scene.wingman.controller.motor_forces.duplicate()]
	for mech in [scene.hero,scene.wingman]: mech.controller.motor_forces.fill(Vector3.ZERO)
	scene.set_afterburner_throttle(1.0)
	assert(flames.all(func(flame):return not flame.visible),"Preview throttle fabricated exhaust without delivered nozzle thrust")
	var previous_length := -1.0
	for throttle in [0.0,0.35,1.0]:
		for mech in [scene.hero,scene.wingman]:
			for index in mech.MOUNTS.size(): mech.controller.motor_forces[index] = -mech.gimbals[index].global_basis.z.normalized()*mech.controller.hot_max_thrust(index)*throttle
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
	scene.hero.controller.motor_forces = saved_forces[0]
	scene.wingman.controller.motor_forces = saved_forces[1]
	scene._update_afterburners()

func _check_mechs(scene: Node3D) -> void:
	var source := preload("res://models/MechAsset/MechAsset.glb").instantiate()
	var source_player: AnimationPlayer = source.find_child("AnimationPlayer",true,false)
	assert(source_player.get_animation(&"Boost_Forward").length < 0.01,"Runtime modified an imported static pose")
	source.free()
	for mech in [scene.hero,scene.wingman]:
		assert(mech.find_child("MechAssetModel",true,false) != null)
		assert(not mech.actor.is_physics_processing() and not mech.actor.actor_camera.current)
		assert(not mech.actor.animation_player.is_playing(),"Flight still plays an authored clip")
		assert(not mech.actor.animation_player.has_animation(&"Airborne"),"Static flight hold remains")
		assert(mech.sockets.size() == mech.MOUNTS.size() and mech.gas_jets.size() == mech.COLD_MOUNTS.size())
		for name in ["GUN","Cube_001"]: assert(not mech.skeleton.find_child(name,false,false).visible,"Detached weapon geometry survived gun removal")
		assert(mech.skeleton.find_child("Cube",false,false).visible,"Backpack was hidden with the weapon")
		for name in [&"Walk",&"Fall"]:
			var clip: Animation = mech.actor.animation_player.get_animation(name)
			var track: int = MechAssets.find_position_track(clip,&"Root")
			var origin: Vector3 = clip.track_get_key_value(track,0)
			for key in clip.track_get_key_count(track): assert(origin.is_equal_approx(clip.track_get_key_value(track,key)),"Walk root displacement was restored")
		for material in mech.palette_materials:
			if material.shader == preload("res://shaders/aerial/aircraft.gdshader"):
				assert(material.get_shader_parameter("highlight_mask") == 0.0)
	scene.set_walk_mode(true)
	await physics_frame
	scene._update_walk_pose()
	assert(absf(scene.hero.position.y-45.1-scene.ground_height(scene.hero.position)) < 0.01,"Walk preview lost grounding")
	scene.hero.update_animation(0.9)
	assert(scene.hero.actor.current_animation == &"Walk")
	var sk: Skeleton3D = scene.hero.skeleton
	var pose := sk.get_bone_pose_rotation(sk.find_bone("Thigh.L"))
	scene.hero.update_animation(0.3)
	assert(not pose.is_equal_approx(sk.get_bone_pose_rotation(sk.find_bone("Thigh.L"))),"Walking is static")
	for flame in scene.hero.flames: assert(not flame.visible)
	scene.animate = true
	var start: Vector3 = scene.hero.position
	scene._process(0.1)
	assert(scene.hero.position.distance_to(start) > 1.0)
	var movement: Vector3 = scene.hero.position-start
	movement.y = 0.0
	assert((-scene.hero.basis.z).dot(movement.normalized()) > 0.999)
	scene.animate = false
	var frozen: float = scene.hero.actor.animation_player.current_animation_position
	scene._process(0.1)
	assert(is_equal_approx(scene.hero.actor.animation_player.current_animation_position,frozen))
	scene.set_walk_mode(false)
	scene.hero.update_animation(0.9)
	assert(not scene.hero.actor.animation_player.is_playing() and scene.camera.current)
	scene.elapsed = 0.0

func _checks_timeout() -> void:
	if not completed:
		push_error("Aerial checks did not finish; inspect earlier assertion or script errors.")
		quit(1)
