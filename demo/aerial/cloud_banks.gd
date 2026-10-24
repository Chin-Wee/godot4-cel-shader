extends MultiMeshInstance3D

var banks: Array[Vector4] = []
var extents: Array[Vector3] = []

func build(material: Material) -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 1947
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 5
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sphere
	multimesh.instance_count = 540
	material_override = material
	custom_aabb = AABB(Vector3(-5000,-1000,-5000),Vector3(10000,3000,10000))
	var index := 0
	for bank in 18:
		var center := Vector3(rng.randf_range(-2300,2300),rng.randf_range(430,680),rng.randf_range(-2800,-400))
		var size := Vector3(rng.randf_range(140,270),rng.randf_range(55,100),rng.randf_range(90,180))
		banks.append(Vector4(center.x,center.y,center.z,1))
		extents.append(size)
		for lobe in 30:
			var offset := Vector3(rng.randf_range(-0.65,0.65),rng.randf_range(-0.35,0.35),rng.randf_range(-0.65,0.65)) * size
			var radius := rng.randf_range(55,100)
			var shape := Vector3(radius*1.5,radius*1.0,radius)
			multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(shape),center+offset))
			index += 1

func density_at(world_position: Vector3) -> float:
	var point := to_local(world_position)
	var density := 0.0
	for index in banks.size():
		var center := Vector3(banks[index].x,banks[index].y,banks[index].z)
		var radius := ((point-center)/(extents[index]*1.2)).length()
		density = maxf(density,1.0-smoothstep(0.65,1.1,radius))
	return density
