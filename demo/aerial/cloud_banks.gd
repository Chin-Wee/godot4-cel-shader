extends Node3D

const Field = preload("res://aerial/cloud_field.gd")
const BANK_COUNT := 18
const SHAPE_COUNT := 4

var banks: Array[Vector4] = []
var extents: Array[Vector3] = []
var bank_transforms: Array[Transform3D] = []
var batches: Array[MultiMeshInstance3D] = []
var coverage := 1.0
var coverage_scores := PackedFloat32Array()
# x-fast signed grids are shared by marching cubes, weather and GPU cloud shadows.
var field_size := Field.SIZE
var field_bounds := Field.BOUNDS
var density_fields: Array[PackedFloat32Array] = []
var field_revision := 0

func build(material: Material) -> void:
	for variant in SHAPE_COUNT:
		var values := Field.generate(variant)
		density_fields.append(values)
		var batch := MultiMeshInstance3D.new()
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = Field.mesh(values)
		batch.multimesh.instance_count = ceili(float(BANK_COUNT-variant)/SHAPE_COUNT)
		batch.material_override = material
		add_child(batch)
		batches.append(batch)
	field_revision = hash(density_fields)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1947
	for bank in BANK_COUNT:
		var center := Vector3(rng.randf_range(-2300,2300),rng.randf_range(640,800),rng.randf_range(-2800,-400))
		# Broad compressed decks share a few optional towers instead of cotton balls.
		var size := Vector3(rng.randf_range(240,360),rng.randf_range(200,280),rng.randf_range(200,320))
		var basis := Basis(Vector3.UP,rng.randf_range(-PI,PI))*Basis.IDENTITY.scaled(size)
		var transform := Transform3D(basis,center)
		bank_transforms.append(transform)
	# Threshold order follows a broad procedural coverage map, so less cloud
	# cover removes low-density regions instead of random scattered banks.
	var coverage_map := FastNoiseLite.new()
	coverage_map.seed = 1947
	coverage_map.frequency = 0.00065
	coverage_map.fractal_type = FastNoiseLite.FRACTAL_NONE
	bank_transforms.sort_custom(func(a: Transform3D,b: Transform3D):
		return coverage_map.get_noise_2d(a.origin.x,a.origin.z)>coverage_map.get_noise_2d(b.origin.x,b.origin.z)
	)
	for bank in BANK_COUNT:
		var transform := bank_transforms[bank]
		var center := transform.origin
		coverage_scores.append(coverage_map.get_noise_2d(center.x,center.z))
		banks.append(Vector4(center.x,center.y,center.z,1))
		extents.append(transform.basis.get_scale())
		batches[bank%SHAPE_COUNT].multimesh.set_instance_transform(bank/SHAPE_COUNT,transform)

func set_coverage(value: float) -> void:
	coverage = clampf(value,0.0,1.0)
	var active := roundi(banks.size()*coverage)
	for variant in SHAPE_COUNT:
		batches[variant].multimesh.visible_instance_count = maxi(0,ceili(float(active-variant)/SHAPE_COUNT))

func field_value(point: Vector3, variant := 0) -> float:
	return Field.sample(density_fields[variant],point)

func _shape_density(point: Vector3, variant := 0) -> float:
	return smoothstep(0.0,0.14,field_value(point,variant))

func interior_probe(_variant := 0) -> Vector3:
	return Vector3.ZERO

func density_at(world_position: Vector3) -> float:
	var point := to_local(world_position)
	var density := 0.0
	for index in roundi(banks.size()*coverage):
		density = maxf(density,_shape_density(bank_transforms[index].affine_inverse()*point,index%SHAPE_COUNT))
	return density
