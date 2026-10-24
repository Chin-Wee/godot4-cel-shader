extends RefCounted

# Visual reconstruction references: DELIVERY MUST COMPLETE's broad aircraft panels
# and canyon silhouettes. These are deterministic material-test proxies, not asset imports.
static func mesh_from_faces(faces: Array, center := Vector3.ZERO) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		for index in range(1, face.size() - 1):
			var a: Vector3 = face[0]
			var b: Vector3 = face[index]
			var c: Vector3 = face[index + 1]
			var normal := (b - a).cross(c - a).normalized()
			if normal.dot((a + b + c) / 3.0 - center) < 0.0:
				var swap := b
				b = c
				c = swap
				normal = -normal
			for vertex in [a,c,b]:
				surface.set_normal(normal)
				surface.add_vertex(vertex)
	return surface.commit()

static func add_mesh(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	return node

static func aircraft(body: Material, canopy: Material, exhaust: Material) -> Node3D:
	var aircraft_root := Node3D.new()
	var nose := Vector3(0,0,-25)
	var top := Vector3(0,4,-5)
	var left := Vector3(-4,0,-5)
	var right := Vector3(4,0,-5)
	var bottom := Vector3(0,-2.5,-5)
	var tail_top := Vector3(0,2,15)
	var tail_left := Vector3(-5,0,15)
	var tail_right := Vector3(5,0,15)
	var tail_bottom := Vector3(0,-2,15)
	var faces := [[nose,left,top],[nose,top,right],[nose,bottom,left],[nose,right,bottom],
		[top,left,tail_left,tail_top],[top,tail_top,tail_right,right],
		[bottom,tail_bottom,tail_left,left],[bottom,right,tail_right,tail_bottom],
		[tail_top,tail_left,tail_bottom,tail_right]]
	# Thick delta wings and canted tail fins retain readable silhouettes from below.
	for side in [-1.0,1.0]:
		var p := [Vector3(side*3,0,-10),Vector3(side*27,-0.6,13),Vector3(side*7,0,9)]
		faces.append(p)
		faces.append([p[0]-Vector3.UP,p[2]-Vector3.UP,p[1]-Vector3.UP])
		faces.append([p[0],p[1],p[1]-Vector3.UP,p[0]-Vector3.UP])
		var fin := [Vector3(side*4,1,8),Vector3(side*10,16,14),Vector3(side*9,1,18)]
		faces.append(fin)
		faces.append([fin[2]-Vector3(0,0,0.5),fin[1]-Vector3(0,0,0.5),fin[0]-Vector3(0,0,0.5)])
		faces.append([Vector3(side*4,0,11),Vector3(side*14,0,19),Vector3(side*4,0,17)])
	add_mesh(aircraft_root,mesh_from_faces(faces),body)
	var canopy_faces := [[Vector3(0,2,-17),Vector3(-1.8,3,-6),Vector3(0,5,-5)],
		[Vector3(0,2,-17),Vector3(0,5,-5),Vector3(1.8,3,-6)]]
	add_mesh(aircraft_root,mesh_from_faces(canopy_faces,Vector3(0,2,-7)),canopy)
	for side in [-1.0,1.0]:
		var nozzle := add_mesh(aircraft_root,icosphere(),exhaust)
		nozzle.name = "EngineFlame"+str(side)
		nozzle.position = Vector3(side*2.7,0,15)
		nozzle.scale = Vector3(1.8,1.8,6.0)
	return aircraft_root

static func icosphere() -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var points := [Vector3(-1,t,0),Vector3(1,t,0),Vector3(-1,-t,0),Vector3(1,-t,0),
		Vector3(0,-1,t),Vector3(0,1,t),Vector3(0,-1,-t),Vector3(0,1,-t),
		Vector3(t,0,-1),Vector3(t,0,1),Vector3(-t,0,-1),Vector3(-t,0,1)]
	var indices := [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],
		[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],
		[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]]
	var faces := []
	for triangle in indices:
		var face := []
		for index in triangle:
			var point: Vector3 = points[index].normalized()
			# Yollie's disclosed missile flame: unsubdivided icosphere, rear half stretched.
			if point.z > 0: point.z *= 2.5
			face.append(point)
		faces.append(face)
	return mesh_from_faces(faces)

static func terrain() -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 704
	noise.frequency = 0.0014
	noise.fractal_octaves = 3
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 150
	const STEP := 24.0
	for z in STEPS:
		for x in STEPS:
			var points := []
			for offset in [Vector2(0,0),Vector2(0,1),Vector2(1,0),Vector2(1,1)]:
				var px: float = (x + offset.x - STEPS/2.0) * STEP
				var pz: float = (z + offset.y - STEPS/2.0) * STEP - 1100.0
				var n := noise.get_noise_2d(px,pz) * 0.5 + 0.5
				var mesa := smoothstep(0.40,0.48,n)
				var river_x := sin(pz*0.0028)*190.0 + sin(pz*0.006)*45.0
				var canyon := smoothstep(75.0,210.0,absf(px-river_x))
				var h := 8.0 + mesa * (200.0 + floorf((noise.get_noise_2d(px+800,pz)+1.0)*3.0)*25.0) * canyon
				points.append(Vector3(px,h,pz))
			for triangle in [[0,1,2],[2,1,3]]:
				var a: Vector3 = points[triangle[0]]
				var b: Vector3 = points[triangle[1]]
				var c: Vector3 = points[triangle[2]]
				var normal := (b-a).cross(c-a).normalized()
				for vertex in [a,c,b]:
					surface.set_normal(normal)
					surface.add_vertex(vertex)
	return surface.commit()
