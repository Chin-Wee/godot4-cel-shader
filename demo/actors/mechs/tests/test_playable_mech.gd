extends SceneTree

class InteractionGrass:
	extends MultiMeshInstance3D
	var interaction_target: Node3D

var failed := false

func _initialize() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 1, 50)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	var roster = load("res://actors/mechs/mech_roster.tscn").instantiate()
	var grass := InteractionGrass.new()
	root.add_child(grass)
	roster.grass = grass
	root.add_child(roster)
	await process_frame
	await process_frame
	var george = roster.get_node("George")
	var mech = roster.get_node("MechAsset")
	var player: AnimationPlayer = mech.animation_player
	_expect(roster.active_mech == george and george.actor_camera.is_current(), "George must start selected")
	_expect(player.has_animation("Idle") and player.has_animation("Walk"), "Canonical animation mapping missing")
	_expect(player.has_animation("GunPose") and player.has_animation("Boost_Forward"), "Source preview poses missing")
	_expect(player.get_animation("Idle").loop_mode == Animation.LOOP_NONE, "Idle pose should stay static")
	_expect(player.get_animation("Walk").loop_mode == Animation.LOOP_LINEAR, "Walk should loop")
	_expect(player.get_animation("Fall").loop_mode == Animation.LOOP_LINEAR, "Fall should loop")
	var captured_mode := Input.get_mouse_mode()
	var rest: Vector3
	for name in [&"Idle", &"Walk", &"Jump", &"Fall", &"Land"]:
		var animation := player.get_animation(name)
		var index: int = mech._find_position_track(animation, &"Root")
		_expect(index >= 0, "Missing root track for " + name)
		if name == &"Idle": rest = animation.track_get_key_value(index, 0)
		for key in animation.track_get_key_count(index):
			_expect((animation.track_get_key_value(index,key) as Vector3).is_equal_approx(rest), "Root displacement remains in " + name)
	_expect(float(mech.locomotion_stride_distances[&"Walk"]) > 16.0, "Stride must come from original root travel")
	var imported = load("res://models/MechAsset/MechAsset.glb").instantiate()
	var original: Animation = imported.find_child("AnimationPlayer",true,false).get_animation("Walk_Forward")
	var original_track: int = mech._find_position_track(original, &"Root")
	_expect((original.track_get_key_value(original_track,original.track_get_key_count(original_track)-1) as Vector3).z > 16.0, "Imported library was mutated")
	imported.free()
	var green_found := false
	for mesh in mech.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material: ShaderMaterial = mesh.get_surface_override_material(surface)
			_expect(material != null and material.get_shader_parameter("specular_strength") == 0.0, "Matte cel material missing")
			var color: Color = material.get_shader_parameter("color")
			green_found = green_found or color.g > color.r + 0.1
	_expect(green_found, "Green emissive accent became black")
	var switch_event := InputEventKey.new()
	switch_event.physical_keycode = KEY_TAB
	switch_event.pressed = true
	Input.parse_input_event(switch_event.duplicate())
	await process_frame
	await process_frame
	_expect(roster.active_mech == mech and mech.actor_camera.is_current(), "Tab did not switch mech/camera")
	_expect(grass.interaction_target == mech, "Grass target did not transfer")
	_expect(not george.player_controlled and not george.movement_input_enabled, "Inactive George still accepts input")
	_expect(george.is_physics_processing() and mech.is_physics_processing(), "Inactive playable body stopped simulating")
	switch_event.echo = true
	Input.parse_input_event(switch_event.duplicate())
	await process_frame
	await process_frame
	_expect(roster.active_mech == mech, "Key repeat switched twice")
	switch_event.echo = false
	switch_event.pressed = false
	Input.parse_input_event(switch_event.duplicate())
	Input.action_press("forward")
	Input.action_press("run")
	for frame in 90: await physics_frame
	_expect(not mech.is_running, "New mech can run")
	_expect(Vector2(mech.velocity.x,mech.velocity.z).length() <= mech.speed + 0.01, "New mech exceeds walking speed")
	_expect(Vector2(george.velocity.x,george.velocity.z).length() < 0.01, "Inactive George moved from shared input")
	Input.action_release("forward")
	Input.action_release("run")
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	_expect(not mech.is_on_floor() and mech.current_animation == &"Jump", "Takeoff did not play Jump")
	switch_event.pressed = true
	Input.parse_input_event(switch_event.duplicate())
	await process_frame
	await process_frame
	_expect(roster.active_mech == george, "Could not switch while airborne")
	switch_event.pressed = false
	Input.parse_input_event(switch_event.duplicate())
	var saw_fall := false
	var saw_land := false
	var land_entries := 0
	var previous_animation: StringName = mech.current_animation
	for frame in 180:
		await physics_frame
		saw_fall = saw_fall or mech.current_animation == &"Fall"
		saw_land = saw_land or mech.current_animation == &"Land"
		if mech.current_animation == &"Land" and previous_animation != &"Land":
			land_entries += 1
		previous_animation = mech.current_animation
	_expect(saw_fall and saw_land and mech.is_on_floor(), "Inactive airborne mech did not fall and land")
	_expect(mech.current_animation == &"Idle", "Landing recovery did not return to Idle")
	_expect(land_entries == 1, "Landing should play exactly once")
	for cycle in 4:
		switch_event.pressed = true
		Input.parse_input_event(switch_event.duplicate())
		await process_frame
		await process_frame
		var expected = mech if cycle % 2 == 0 else george
		_expect(roster.active_mech == expected and expected.actor_camera.is_current(), "Repeated switching lost camera ownership")
		switch_event.pressed = false
		Input.parse_input_event(switch_event.duplicate())
		await process_frame
		await process_frame
	_expect(Input.get_mouse_mode() == captured_mode, "Switching changed mouse capture")
	mech.set_physics_process(false)
	player.play("Idle")
	player.advance(0)
	await process_frame
	await process_frame
	var minimum_y := INF
	var maximum_y := -INF
	for mesh in mech.find_children("*", "MeshInstance3D", true, false):
		# Armor and feet are rigid attachments; measure actual vertices, not rotated AABBs.
		if mesh.skin != null: continue
		var local_transform: Transform3D = mech.global_transform.affine_inverse() * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var position: Vector3 = local_transform * vertex
				minimum_y = minf(minimum_y, position.y)
				maximum_y = maxf(maximum_y, position.y)
	_expect(absf(minimum_y) < 0.005, "Standing feet do not meet the floor")
	_expect(absf(maximum_y - minimum_y - 1.8) < 0.005, "Standing model does not fit the 1.8m capsule")
	roster.queue_free()
	floor_body.queue_free()
	grass.queue_free()
	await process_frame
	await process_frame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not failed: print("Playable mech checks passed: mapping, materials, root motion, switching, walking, jump/fall/land.")
	quit(1 if failed else 0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
