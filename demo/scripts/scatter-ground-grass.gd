extends MultiMeshInstance3D

@export var interaction_target: Node3D

const GRASS_MESH := preload("res://models/foliage/grass_triangle.obj")
const GRASS_MATERIAL := preload("res://materials/materials/wind-grass.tres")
const BLADE_COUNT := 160_000
const SCATTER_EXTENTS := Vector2(28.0, 28.0)
const MIN_UP_DOT := 0.72
const MIN_SCALE := 0.15
const MAX_SCALE := 0.25

var grass_material: ShaderMaterial

func _ready() -> void:
	grass_material = GRASS_MATERIAL.duplicate() as ShaderMaterial
	material_override = grass_material
	_update_interaction()
	var blades := MultiMesh.new()
	blades.transform_format = MultiMesh.TRANSFORM_3D
	blades.mesh = GRASS_MESH
	multimesh = blades
	await get_tree().physics_frame
	_scatter(blades)

func _process(_delta: float) -> void:
	_update_interaction()

func _update_interaction() -> void:
	if not is_instance_valid(interaction_target):
		grass_material.set_shader_parameter("character_push_strength", 0.0)
		set_process(false)
		return
	grass_material.set_shader_parameter("character_position", interaction_target.global_position)

func _scatter(blades: MultiMesh) -> void:
	var ground := get_parent() as Node3D
	var ground_bodies: Array[CollisionObject3D] = []
	var base_body := ground.get_node_or_null("StaticBody3D") as CollisionObject3D
	if base_body:
		ground_bodies.append(base_body)
	for cliff in ground.find_children("terrain-*", "Node3D", true, false):
		var body := cliff.get_node_or_null("StaticBody3D") as CollisionObject3D
		if body and not ground_bodies.has(body):
			ground_bodies.append(body)
	if ground_bodies.is_empty():
		return

	var excluded: Array[RID] = []
	for collider in get_tree().root.find_children("*", "CollisionObject3D", true, false):
		if not ground_bodies.has(collider):
			excluded.append(collider.get_rid())

	var rng := RandomNumberGenerator.new()
	rng.seed = 47391
	var transforms: Array[Transform3D] = []
	# ponytail: rejection sampling caps at four rays per blade; sample triangles if startup time becomes costly.
	for _attempt in range(BLADE_COUNT * 4):
		var x := rng.randf_range(-SCATTER_EXTENTS.x, SCATTER_EXTENTS.x)
		var z := rng.randf_range(-SCATTER_EXTENTS.y, SCATTER_EXTENTS.y)
		var ray_start := ground.to_global(Vector3(x, 40.0, z))
		var ray_end := ground.to_global(Vector3(x, -20.0, z))
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1, excluded)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not ground_bodies.has(hit.collider):
			continue
		var world_up: Vector3 = hit.normal
		if world_up.dot(Vector3.UP) < MIN_UP_DOT:
			continue

		var local_up := (global_transform.basis.inverse() * world_up).normalized()
		var alignment := Basis(Quaternion(Vector3.UP, local_up))
		var yaw := Basis(Quaternion(local_up, rng.randf_range(0.0, TAU)))
		var blade_basis := (yaw * alignment).scaled(Vector3.ONE * rng.randf_range(MIN_SCALE, MAX_SCALE))
		var blade_position := to_local(hit.position) + local_up * 0.01
		transforms.append(Transform3D(blade_basis, blade_position))
		if transforms.size() == BLADE_COUNT:
			break

	blades.instance_count = transforms.size()
	for i in transforms.size():
		blades.set_instance_transform(i, transforms[i])
