extends SceneTree

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
	scene._update_hero_pose(0.0)
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
	var palette_size: int = scene.palette_materials.size()
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
	assert(scene.palette_materials.size() == palette_size,"Transient effects leaked into persistent palette storage")
	assert(explosion.materials[0].get_shader_parameter("haze_color") == scene.current_haze,"New VFX did not inherit the active weather palette")
	assert(explosion.materials[8].get_shader_parameter("sun_direction") == scene.sun_direction,"New smoke did not inherit the active sunlight")
	scene.set_palette(false)
	assert(explosion.materials[0].get_shader_parameter("haze_color") == scene.current_haze,"Live VFX missed a palette transition")
	assert(explosion.materials[8].get_shader_parameter("sun_direction") == scene.sun_direction,"Live smoke missed a sunlight transition")
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
			assert(flame.get_parent() is BoneAttachment3D and flame.get_parent().bone_name == &"Torso","Exhaust does not follow the animated torso")
			assert(is_equal_approx(flame.position.z,-1.95),"Exhaust is detached from its nozzle exit")
	assert(flames.size() == 4,"Twin afterburners are missing from the mechs")
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

func _check_mechs(scene: Node3D) -> void:
	var source := preload("res://models/MechAsset/MechAsset.glb").instantiate()
	var source_player: AnimationPlayer = source.find_child("AnimationPlayer",true,false)
	assert(source_player.get_animation(&"Boost_Forward").length < 0.01,"Runtime pose holding modified the source animation")
	source.free()
	for mech in [scene.hero,scene.wingman]:
		assert(mech.find_child("MechAssetModel",true,false) != null,"The supplied white mech is missing")
		assert(mech.find_child("Body",false,false) == null,"An aircraft proxy remains in the scene")
		assert(not mech.actor.is_physics_processing(),"Showcase actor is still simulating the roster controller")
		assert(not mech.actor.actor_camera.current,"Mech camera stole the showcase view")
		assert(mech.actor.animation_player.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
		assert(is_equal_approx(mech.actor.animation_player.speed_scale,0.7),"Ordinary playback lost its 30% slowdown")
		for clip_name in [&"Walk",&"Fall"] + mech.FLIGHT_POSES:
			var clip: Animation = mech.actor.animation_player.get_animation(clip_name)
			assert(clip.loop_mode == Animation.LOOP_LINEAR)
			var track: int = mech.actor._find_position_track(clip,&"Root")
			var origin: Vector3 = clip.track_get_key_value(track,0)
			for key in clip.track_get_key_count(track):
				assert(origin.is_equal_approx(clip.track_get_key_value(track,key)),"Animation translates the flying/walking mech twice")
		for index in mech.FLIGHT_POSES.size():
			mech.flight_pose = index
			mech.update_animation(0.9,1.0)
			assert(mech.actor.current_animation == mech.FLIGHT_POSES[index],"A supplied directional boost pose is unavailable")
		mech.flight_pose = 0
		mech.update_animation(0.9,0.35)
		assert(mech.actor.current_animation == &"Fall","Hover did not use the supplied flying loop")
		mech.update_animation(0.9,1.0)
		for material in mech.palette_materials:
			assert(material.get_shader_parameter("highlight_mask") == 0.0,"Matte armor regained glossy highlights")
	scene.set_walk_mode(true)
	await physics_frame
	scene._update_hero_pose(scene.elapsed)
	var ground_ray := PhysicsRayQueryParameters3D.create(scene.hero.position,scene.hero.position+Vector3.DOWN*2000.0,2)
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(ground_ray)
	assert(not hit.is_empty() and absf(scene.hero.position.y-45.1-hit.position.y) < 0.01,"Walking preview floats above or penetrates the terrain")
	scene.hero.update_animation(0.9,1.0)
	assert(scene.hero.actor.current_animation == &"Walk")
	var skeleton: Skeleton3D = scene.hero.actor.find_child("Skeleton3D",true,false)
	var thigh := skeleton.find_bone("Thigh.L")
	var pose := skeleton.get_bone_pose_rotation(thigh)
	scene.hero.update_animation(0.3,1.0)
	assert(not pose.is_equal_approx(skeleton.get_bone_pose_rotation(thigh)),"Walking is a static pose")
	for flame in scene.hero.flames: assert(not flame.visible,"Walking leaves the afterburners lit")
	for trail in scene.trails.slice(0,2): assert(not trail.visible,"Walking leaves airborne trails visible")
	scene.animate = true
	var start: Vector3 = scene.hero.position
	scene._process(0.1)
	assert(is_equal_approx(scene.walking_time,0.1) and scene.hero.position.distance_to(start) > 1.0,"Walking animation has no matching movement")
	var movement: Vector3 = scene.hero.position-start
	movement.y = 0.0
	assert((-scene.hero.basis.z).dot(movement.normalized()) > 0.999,"Walking faces away from its movement")
	scene.animate = false
	var frozen: float = scene.hero.actor.animation_player.current_animation_position
	scene._process(0.1)
	assert(is_equal_approx(scene.hero.actor.animation_player.current_animation_position,frozen),"Paused scene still advances skeletal animation")
	scene.elapsed = 0.0
	scene.set_walk_mode(false)
	scene.hero.update_animation(0.9,1.0)
	assert(scene.hero.actor.current_animation == &"Boost_Forward")
	assert(scene.camera.current,"Switching walk/flight lost camera ownership")
	for flame in scene.hero.flames: assert(flame.visible,"Returning to flight did not restore the exhaust")

func _checks_timeout() -> void:
	if not completed:
		push_error("Aerial checks did not finish; inspect earlier assertion or script errors.")
		quit(1)
