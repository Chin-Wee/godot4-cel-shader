extends SceneTree

const Clouds = preload("res://aerial/cloud_banks.gd")
var completed := false

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	create_timer(25.0).timeout.connect(func():
		if not completed: quit(1)
	)
	var started := Time.get_ticks_msec()
	var clouds := Clouds.new()
	root.add_child(clouds)
	clouds.build(null)
	var build_ms := Time.get_ticks_msec()-started
	assert(clouds.density_fields.size()==4 and clouds.batches.size()==4)
	assert(clouds.field_size==Vector3i(33,21,29))
	var total_triangles := 0
	var flat_height := 0.0
	for variant in 4:
		var field: PackedFloat32Array = clouds.density_fields[variant]
		assert(field.size()==33*21*29,"Signed cloud grid changed layout")
		assert(field==clouds.Field.generate(variant),"Cloud generation is nondeterministic")
		for z in clouds.field_size.z:
			for y in clouds.field_size.y:
				for x in clouds.field_size.x:
					if x==0 or y==0 or z==0 or x==32 or y==20 or z==28:
						assert(field[x+33*(y+21*z)]<0.0,"Cloud density reaches its meshing boundary")
		var arrays: Array = clouds.batches[variant].multimesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var edges := {}
		var components := PackedInt32Array()
		for vertex in vertices.size(): components.append(vertex)
		var bounds := AABB(vertices[0],Vector3.ZERO)
		for index in vertices.size():
			bounds=bounds.expand(vertices[index])
			assert(vertices[index].is_finite() and normals[index].is_finite())
			assert(absf(normals[index].length()-1.0)<0.001,"Cloud normals are not smooth unit gradients")
			assert(absf(clouds.field_value(vertices[index],variant))<0.00001,"Marching cubes and weather sample different fields")
			assert(clouds._shape_density(vertices[index],variant)<0.00001,"Weather leaked beyond the visible surface")
		for triangle in range(0,indices.size(),3):
			var a: int=indices[triangle]
			var b: int=indices[triangle+1]
			var c: int=indices[triangle+2]
			components[_component(components,b)]=_component(components,a)
			components[_component(components,c)]=_component(components,a)
			var face := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
			assert(face.length_squared()>0.0,"Cloud has a degenerate triangle")
			assert(face.dot(normals[a]+normals[b]+normals[c])<0.0,"Cloud triangle winding disagrees with its outward normals")
			for edge in [[a,b],[b,c],[c,a]]:
				var key := Vector2i(mini(edge[0],edge[1]),maxi(edge[0],edge[1]))
				edges[key]=int(edges.get(key,0))+1
		for count in edges.values(): assert(count==2,"Cloud iso-surface is not closed")
		var islands := {}
		for vertex in vertices.size(): islands[_component(components,vertex)]=true
		assert(islands.size()==1,"Cloud deck broke into disconnected cotton-ball islands")
		assert(indices.size()/3<10000,"Cloud topology exceeded its intentionally coarse budget")
		total_triangles += indices.size()/3
		assert(clouds._shape_density(clouds.interior_probe(variant),variant)>0.99,"Cloud interior probe is outside the visible volume")
		assert(clouds._shape_density(Vector3(0,-0.8,0),variant)==0.0,"Fog leaked below cloud field bounds")
		if variant==0:
			flat_height=bounds.size.y
			assert(bounds.size.y/maxf(bounds.size.x,bounds.size.z)<0.3,"Deck lost its vertical compression")
		if variant==2: assert(bounds.size.y>flat_height*1.8,"Selected cloud variant lost its tower")
		# A side-open underside cut must exist in BOTH field occupancy and triangles.
		# Three positive-distance hits from a filled origin prove exit, re-entry,
		# then outer exit. A deformed radial sphere can only produce one exit.
		var hits := _ray_hits(vertices,indices,Vector3(1,-0.22,0.14).normalized())
		assert(hits.size()>=3,"Cloud cutter did not produce a non-radial mesh overhang")
		var direction := Vector3(1,-0.22,0.14).normalized()
		assert(clouds.field_value(direction*((hits[0]+hits[1])*0.5),variant)<0.0,"Mesh overhang cavity differs from weather field")
		assert(clouds.field_value(direction*((hits[1]+hits[2])*0.5),variant)>0.0,"Mesh shelf beyond cavity differs from weather field")
		print("Cloud variant ",variant,": ",vertices.size()," vertices, ",indices.size()/3," triangles; overhang hits ",hits)
	assert(clouds.density_fields[0]!=clouds.density_fields[1],"Clouds repeat one density shape")
	for bank in range(1,clouds.BANK_COUNT):
		assert(clouds.coverage_scores[bank]<=clouds.coverage_scores[bank-1],"Coverage is not ordered by its procedural map")
	for active in range(19):
		clouds.set_coverage(float(active)/18.0)
		var visible := 0
		for batch in clouds.batches: visible+=batch.multimesh.visible_instance_count
		assert(visible==active,"Cloud coverage diverged across four batches")
	clouds.set_coverage(1.0)
	var probe := clouds.to_global(clouds.bank_transforms[0]*clouds.interior_probe(0))
	assert(clouds.density_at(probe)>0.99)
	var revision: int=clouds.field_revision
	clouds.position=Vector3(500,50,-100)
	assert(clouds.field_revision==revision,"Rigid drift changed the cloud field revision")
	probe=clouds.to_global(clouds.bank_transforms[0]*clouds.interior_probe(0))
	assert(clouds.density_at(probe)>0.99,"Cloud weather did not follow its transformed mesh")
	clouds.set_coverage(0.0)
	assert(clouds.density_at(probe)==0.0,"Hidden cloud still contributes weather")
	clouds.queue_free()
	await process_frame
	completed=true
	print("Cloud field checks passed: closed coarse MC meshes, non-radial overhangs, shared density, gradient normals, variants, coverage and drift. Build ",build_ms,"ms; total ",total_triangles," triangles.")
	quit()

func _ray_hits(vertices: PackedVector3Array, indices: PackedInt32Array, direction: Vector3) -> Array[float]:
	var hits: Array[float]=[]
	for triangle in range(0,indices.size(),3):
		var point = Geometry3D.ray_intersects_triangle(Vector3.ZERO,direction,vertices[indices[triangle]],vertices[indices[triangle+1]],vertices[indices[triangle+2]])
		if point==null: continue
		var distance: float=point.length()
		var unique := true
		for previous in hits: unique=unique and absf(previous-distance)>0.0001
		if unique: hits.append(distance)
	hits.sort()
	return hits

func _component(parents: PackedInt32Array, vertex: int) -> int:
	while parents[vertex]!=vertex: vertex=parents[vertex]
	return vertex
