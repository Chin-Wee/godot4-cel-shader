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
	var parts: Array[ArrayMesh] = []
	var sections := [Vector4(-25,0.04,0.1,-0.1),Vector4(-14,1.8,1.6,-1.2),
		Vector4(-6,4.5,3.0,-2.0),Vector4(4,6,2.5,-2.5),Vector4(15,5.5,2,-2)]
	var rings := []
	for section in sections:
		var z: float = section.x
		var w: float = section.y
		var top: float = section.z
		var bottom: float = section.w
		rings.append([Vector3(0,top,z),Vector3(w*0.7,top*0.75,z),Vector3(w,0,z),
			Vector3(w*0.7,bottom*0.8,z),Vector3(0,bottom,z),Vector3(-w*0.7,bottom*0.8,z),
			Vector3(-w,0,z),Vector3(-w*0.7,top*0.75,z)])
	var faces := []
	for ring in range(rings.size()-1):
		for edge in 8:
			var next := (edge+1)%8
			faces.append([rings[ring][edge],rings[ring][next],rings[ring+1][next],rings[ring+1][edge]])
	faces.append(rings[0])
	faces.append(rings[-1])
	parts.append(mesh_from_faces(faces,Vector3(0,0,-3)))
	var dark_faces := []
	for side in [-1.0,1.0]:
		# Each convex part gets its own interior center before native SurfaceTool
		# combines it into one surface. A fuselage center cannot orient a detached fin.
		var wing := [Vector3(side*3,0,-10),Vector3(side*27,-0.6,13),Vector3(side*7,0,9)]
		parts.append(_triangular_prism(wing,Vector3.DOWN))
		var fin := [Vector3(side*6,1,8),Vector3(side*14,19,14),Vector3(side*10,1,18)]
		parts.append(_triangular_prism(fin,Vector3(side*0.6,0,0)))
		parts.append(_triangular_prism([Vector3(side*4,0,11),Vector3(side*14,0,19),Vector3(side*4,0,17)],Vector3.DOWN*0.6))
		var front := []
		var back := []
		for index in 8:
			var angle := float(index)/8.0*TAU
			var radial := Vector3(side*3.8+cos(angle)*2.3,-0.5+sin(angle)*2.3,0)
			front.append(radial+Vector3(0,0,-2))
			back.append(radial+Vector3(0,0,15.5))
		var pod_faces := []
		for index in 8:
			var next := (index+1)%8
			pod_faces.append([front[index],front[next],back[next],back[index]])
		pod_faces.append(front)
		pod_faces.append(back)
		parts.append(mesh_from_faces(pod_faces,Vector3(side*3.8,-0.5,6)))
		# Dark intake and nozzle faces use the canopy/metal response independently.
		var intake := []
		var nozzle_face := []
		for index in 8:
			var angle := float(index)/8.0*TAU
			intake.append(Vector3(side*3.8+cos(angle)*1.85,-0.5+sin(angle)*1.85,-2.05))
			nozzle_face.append(Vector3(side*3.8+cos(angle)*1.85,-0.5+sin(angle)*1.85,15.55))
		dark_faces.append(intake)
		dark_faces.append(nozzle_face)
	var glass_edge := [Vector3(0,2.5,-19),Vector3(-2.2,4.5,-7),Vector3(0,4.7,-3),Vector3(2.2,4.5,-7)]
	var frame_base := [Vector3(0,0.7,-19),Vector3(-2.2,2,-7),Vector3(0,2.6,-3),Vector3(2.2,2,-7)]
	var frame_faces := []
	for edge in 4:
		var next := (edge+1)%4
		frame_faces.append([frame_base[edge],frame_base[next],glass_edge[next],glass_edge[edge]])
	parts.append(mesh_from_faces(frame_faces,Vector3(0,2.8,-9)))
	var assembled := SurfaceTool.new()
	assembled.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts: assembled.append_from(part,0,Transform3D.IDENTITY)
	add_mesh(aircraft_root,assembled.commit(),body)
	var canopy_faces := [[Vector3(0,2.5,-19),Vector3(-2.2,4.5,-7),Vector3(0,6.5,-8)],
		[Vector3(0,2.5,-19),Vector3(0,6.5,-8),Vector3(2.2,4.5,-7)],
		[Vector3(-2.2,4.5,-7),Vector3(0,4.7,-3),Vector3(0,6.5,-8)],
		[Vector3(0,6.5,-8),Vector3(0,4.7,-3),Vector3(2.2,4.5,-7)]]
	add_mesh(aircraft_root,mesh_from_faces(canopy_faces,Vector3(0,3,-9)),canopy)
	add_mesh(aircraft_root,mesh_from_faces(dark_faces,Vector3(0,0,6)),canopy)
	for side in [-1.0,1.0]:
		var nozzle := add_mesh(aircraft_root,icosphere(),exhaust)
		nozzle.name = "EngineFlame"+str(side)
		nozzle.position = Vector3(side*3.8,-0.5,16.5)
		nozzle.scale = Vector3(1.6,1.6,3.6)
	return aircraft_root

static func _triangular_prism(points: Array, thickness: Vector3) -> ArrayMesh:
	var faces := [points,[points[2]+thickness,points[1]+thickness,points[0]+thickness]]
	for index in 3:
		var next := (index+1)%3
		faces.append([points[index],points[next],points[next]+thickness,points[index]+thickness])
	var center: Vector3 = (points[0]+points[1]+points[2])/3.0+thickness*0.5
	return mesh_from_faces(faces,center)

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
	noise.frequency = 0.0011
	noise.fractal_octaves = 3
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 240
	const STEP := 22.0
	for z in STEPS:
		for x in STEPS:
			var points := []
			for offset in [Vector2(0,0),Vector2(0,1),Vector2(1,0),Vector2(1,1)]:
				var px: float = (x + offset.x - STEPS/2.0) * STEP
				var pz: float = (z + offset.y - STEPS/2.0) * STEP - 1100.0
				px += sin((x+offset.x)*73.17+(z+offset.y)*19.43)*STEP*0.10
				pz += sin((x+offset.x)*31.79+(z+offset.y)*67.13)*STEP*0.10
				var warp := Vector2(noise.get_noise_2d(px+1200,pz-400),noise.get_noise_2d(px-600,pz+900))*110.0
				var n := noise.get_noise_2d(px+warp.x,pz+warp.y) * 0.5 + 0.5
				n += noise.get_noise_2d(px*2.7+1500,pz*2.7)*0.045
				var mesa := pow(smoothstep(0.55,0.64,n),0.50)
				var talus := smoothstep(0.45,0.58,n)*40.0
				var river_x := sin(pz*0.0028)*190.0 + sin(pz*0.006)*45.0
				var canyon := smoothstep(200.0,550.0,absf(px-river_x))
				var h := 8.0 + (talus+mesa*(210.0+noise.get_noise_2d(px+800,pz)*95.0))*canyon
				points.append(Vector3(px,h,pz))
			for triangle in [[0,1,2],[2,1,3]]:
				var a: Vector3 = points[triangle[0]]
				var b: Vector3 = points[triangle[1]]
				var c: Vector3 = points[triangle[2]]
				var normal := (b-a).cross(c-a).normalized()
				for vertex in [a,c,b]:
					surface.set_normal(normal)
					surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

static func river() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 180:
		var points := []
		for step in [index,index+1]:
			var z: float = 700.0-step*20.0
			var x := sin(z*0.0028)*190.0+sin(z*0.006)*45.0
			var width := 12.0+sin(z*0.007)*4.0
			points.append(Vector3(x-width,8.2,z))
			points.append(Vector3(x+width,8.2,z))
		for vertex in [points[0],points[2],points[1],points[1],points[2],points[3]]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	return surface.commit()
