extends MultiMeshInstance3D

var banks: Array[Vector4] = []
var extents: Array[Vector3] = []
var bank_transforms: Array[Transform3D] = []
var coverage := 1.0

func build(material: Material) -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 1947
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _cloud_mesh()
	multimesh.instance_count = 18
	material_override = material
	custom_aabb = AABB(Vector3(-5000,-1000,-5000),Vector3(10000,3000,10000))
	for bank in 18:
		var center := Vector3(rng.randf_range(-2300,2300),rng.randf_range(440,650),rng.randf_range(-2800,-400))
		var size := Vector3(rng.randf_range(190,330),rng.randf_range(65,115),rng.randf_range(120,210))
		banks.append(Vector4(center.x,center.y,center.z,1))
		extents.append(size)
		var basis := Basis(Vector3.UP,rng.randf_range(-PI,PI))*Basis.IDENTITY.scaled(size)
		var transform := Transform3D(basis,center)
		bank_transforms.append(transform)
		multimesh.set_instance_transform(bank,transform)

func _cloud_mesh() -> ArrayMesh:
	# DELIVERY MUST COMPLETE is the visual reference. A single native SphereMesh
	# deformed at low frequency avoids the intersection rings of overlapping lobes.
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 22
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		var point := vertices[index]
		var mass := _radial_mass(point)
		point *= mass
		point.x += 0.08*sin(point.y*5.0+point.z*3.0)
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
	multimesh.visible_instance_count = roundi(banks.size()*coverage)

func density_at(world_position: Vector3) -> float:
	var point := to_local(world_position)
	var density := 0.0
	for index in roundi(banks.size()*coverage):
		density = maxf(density,_shape_density(bank_transforms[index].affine_inverse()*point))
	return density

func _radial_mass(point: Vector3) -> float:
	return 1.0+0.18*sin(point.x*5.2+point.z*3.0)*cos(point.y*4.1)+0.10*sin(point.z*8.0+point.y*3.0)

func _shape_density(point: Vector3) -> float:
	# Invert the same deformation used to build the mesh. A spherical region would
	# create invisible fog below the flattened base and miss the sculpted crests.
	if point.y < -0.38:
		point.y = -0.38+(point.y+0.38)/0.23
	point.x -= 0.08*sin(point.y*5.0+point.z*3.0)
	var radius := point.length()/_radial_mass(point.normalized())
	return 1.0-smoothstep(0.70,1.06,radius)
