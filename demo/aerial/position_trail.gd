extends MultiMeshInstance3D

const CAPACITY := 512
@export var emitter: Node3D
@export var spacing := 3.0
@export var width := 1.5
@export var lifetime := 16.0
var elapsed := 20.0
var next_slot := 0
var previous_position := Vector3.ZERO
var has_previous := false
var sample_count := 0

func configure(material: ShaderMaterial) -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 6
	puff.rings = 3
	multimesh.mesh = puff
	multimesh.instance_count = CAPACITY
	for index in CAPACITY: multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
	material_override = material.duplicate()
	material_override.set_shader_parameter("instance_age",true)
	material_override.set_shader_parameter("expansion",3.0)
	material_override.set_shader_parameter("lifetime",lifetime)
	custom_aabb = AABB(Vector3(-10000,-10000,-10000),Vector3.ONE*20000)

func emit_at(point: Vector3, birth_time: float) -> void:
	var puff_width := width * (0.88 + 0.22*sin(float(sample_count)*2.399))
	multimesh.set_instance_transform(next_slot,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*puff_width),to_local(point)))
	multimesh.set_instance_custom_data(next_slot,Color(birth_time,0,0,1))
	next_slot = (next_slot+1) % CAPACITY
	sample_count += 1

func sample_position(point: Vector3) -> void:
	if not has_previous:
		previous_position = point
		has_previous = true
		emit_at(point,elapsed)
		return
	var distance := previous_position.distance_to(point)
	if distance > spacing*64.0:
		# A teleport starts a fresh trail instead of drawing across the entire world.
		previous_position = point
		return
	var count := mini(int(distance / spacing),64)
	for index in count:
		previous_position = previous_position.move_toward(point,spacing)
		emit_at(previous_position,elapsed)

func _process(delta: float) -> void:
	elapsed += delta
	material_override.set_shader_parameter("effect_time",elapsed)
	if is_instance_valid(emitter): sample_position(emitter.global_position)
