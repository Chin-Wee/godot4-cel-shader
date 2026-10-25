extends Node3D

const BANK_COUNT := 18
const SHAPE_COUNT := 4

var banks: Array[Vector4] = []
var extents: Array[Vector3] = []
var bank_transforms: Array[Transform3D] = []
var shapes: Array[PackedVector4Array] = []
var batches: Array[MultiMeshInstance3D] = []
var coverage := 1.0

func build(material: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1947
	for variant in SHAPE_COUNT:
		var lobes := PackedVector4Array([Vector4(0,-0.1,0,0.72)])
		for lobe in 5:
			var angle := float(lobe)/5.0*TAU + float(variant)*0.7
			lobes.append(Vector4(cos(angle)*0.65,rng.randf_range(-0.12,0.12),sin(angle)*0.5,rng.randf_range(0.4,0.6)))
		for lobe in 6+variant:
			lobes.append(Vector4(rng.randf_range(-0.65,0.65),rng.randf_range(0.25,0.95),rng.randf_range(-0.5,0.5),rng.randf_range(0.25,0.45)))
		shapes.append(lobes)
		var batch := MultiMeshInstance3D.new()
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = _cloud_mesh(variant)
		batch.multimesh.instance_count = ceili(float(BANK_COUNT-variant)/SHAPE_COUNT)
		batch.material_override = material
		add_child(batch)
		batches.append(batch)
	for bank in BANK_COUNT:
		var center := Vector3(rng.randf_range(-2300,2300),rng.randf_range(640,800),rng.randf_range(-2800,-400))
		var size := Vector3(rng.randf_range(150,280),rng.randf_range(90,170),rng.randf_range(130,230))
		banks.append(Vector4(center.x,center.y,center.z,1))
		extents.append(size)
		var basis := Basis(Vector3.UP,rng.randf_range(-PI,PI))*Basis.IDENTITY.scaled(size)
		var transform := Transform3D(basis,center)
		bank_transforms.append(transform)
		batches[bank%SHAPE_COUNT].multimesh.set_instance_transform(bank/SHAPE_COUNT,transform)

func _cloud_mesh(variant: int) -> ArrayMesh:
	# DELIVERY MUST COMPLETE is the visual reference, not a claim about its renderer.
	# Sculpt one native sphere toward a smooth union of broad cumulus lobes. The
	# same radial envelope defines entry density, without intersecting lobe meshes.
	# ponytail: radial surfaces cannot form cavities; use field meshing if clouds need them.
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 72
	sphere.rings = 40
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		var direction := vertices[index].normalized()
		var point := direction*_radial_mass(direction,variant)
		if point.y < -0.38:
			point.y = -0.38+(point.y+0.38)*0.23
		vertices[index] = point
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var deformed := ArrayMesh.new()
	deformed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var surface := SurfaceTool.new()
	surface.create_from(deformed,0)
	surface.generate_normals()
	return surface.commit()

func set_coverage(value: float) -> void:
	coverage = clampf(value,0.0,1.0)
	var active := roundi(banks.size()*coverage)
	for variant in SHAPE_COUNT:
		batches[variant].multimesh.visible_instance_count = maxi(0,ceili(float(active-variant)/SHAPE_COUNT))

func density_at(world_position: Vector3) -> float:
	var point := to_local(world_position)
	var density := 0.0
	for index in roundi(banks.size()*coverage):
		density = maxf(density,_shape_density(bank_transforms[index].affine_inverse()*point,index%SHAPE_COUNT))
	return density

func _radial_mass(direction: Vector3, variant := 0) -> float:
	var radius := 0.0
	for lobe in shapes[variant]:
		var center := Vector3(lobe.x,lobe.y,lobe.z)
		var projection := direction.dot(center)
		var discriminant := projection*projection-center.length_squared()+lobe.w*lobe.w
		if discriminant < 0.0: continue
		var exit := (projection+sqrt(discriminant))*smoothstep(0.0,0.04,discriminant)
		var blend := maxf(0.12-absf(radius-exit),0.0)/0.12
		radius = maxf(radius,exit)+blend*blend*0.03
	return radius*(1.0+0.025*sin(direction.x*9.0+variant)*sin(direction.y*8.0+direction.z*5.0)+0.012*cos(direction.z*14.0+direction.y*5.0))

func _shape_density(point: Vector3, variant := 0) -> float:
	# Invert the same deformation used to build the mesh. A spherical region would
	# create invisible fog below the flattened base and miss the sculpted crests.
	if point.y < -0.38:
		point.y = -0.38+(point.y+0.38)/0.23
	var radius := point.length()/_radial_mass(point.normalized(),variant)
	return 1.0-smoothstep(0.70,1.06,radius)
