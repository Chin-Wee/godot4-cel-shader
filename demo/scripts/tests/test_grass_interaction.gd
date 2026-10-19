extends SceneTree


func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	var scene := load("res://sample-scene.tscn").instantiate() as Node3D
	root.add_child(scene)
	var grass := scene.get_node("ground-2/Grass")
	var target := scene.get_node("MechRoster/George") as Node3D
	assert(grass.interaction_target == target, "Grass must reference the playable mech.")
	target.set_physics_process(false)
	var material := grass.material_override as ShaderMaterial
	assert(material != load("res://materials/materials/wind-grass.tres"))
	assert(float(material.get_shader_parameter("character_push_strength")) > 0.0)
	target.global_position += Vector3(4.0, 0.0, 2.0)
	await process_frame
	await process_frame
	assert(
		material.get_shader_parameter("character_position").is_equal_approx(target.global_position),
		"The bend field must follow a moving mech."
	)
	target.queue_free()
	await process_frame
	await process_frame
	assert(is_zero_approx(float(material.get_shader_parameter("character_push_strength"))))
	assert(not grass.is_processing(), "A freed target must disable interaction safely.")
	print("Grass interaction checks passed: target binding, movement, material isolation, removal.")
	scene.queue_free()
	await process_frame
	quit()
