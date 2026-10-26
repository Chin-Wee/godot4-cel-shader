extends RefCounted

# Visual reconstruction references: DELIVERY MUST COMPLETE's broad aircraft panels
# and canyon silhouettes. These are deterministic material-test proxies, not asset imports.
static func mesh_from_faces(faces: Array, center := Vector3.ZERO, color := Color.WHITE) -> ArrayMesh:
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
				surface.set_color(color)
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
	var sections := [Vector4(-30,0.04,0.1,-0.1),Vector4(-19,2.0,1.0,-0.8),
		Vector4(-11,3.8,2.0,-1.3),Vector4(-3,6.8,2.8,-1.7),
		Vector4(8,7.0,2.2,-1.8),Vector4(17,5.8,1.3,-1.1)]
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
		var wing_root := [Vector3(side*3,0,-10),Vector3(side*15,-0.2,-1),Vector3(side*14,-0.2,12),Vector3(side*6,0,12)]
		var outer_wing := [Vector3(side*15,-0.2,-1),Vector3(side*25,-0.4,7),Vector3(side*24,-0.4,12),Vector3(side*14,-0.2,12)]
		parts.append(_panel_prism(wing_root,Vector3.DOWN*0.8,Color(0.65,0.75,0.9)))
		# Vertex alpha carries an opaque livery mask; all parts stay in one body surface.
		parts.append(_panel_prism(outer_wing,Vector3.DOWN*0.8,Color(1,1,1,0)))
		parts.append(_panel_prism([Vector3(side*2.5,0.3,-19),Vector3(side*7,0.3,-5),Vector3(side*5.5,0.3,1)],Vector3.DOWN*0.8,Color(0.8,0.85,0.9)))
		var fin := [Vector3(side*5.6,1.5,8),Vector3(side*9,13,11),Vector3(side*9.7,12,16),Vector3(side*7.2,1.5,20)]
		parts.append(_panel_prism(fin,Vector3(side*0.55,0,0),Color(0.7,0.75,0.8)))
		parts.append(_panel_prism([Vector3(side*4,0.1,12),Vector3(side*15,0.1,17),Vector3(side*12,0.1,24),Vector3(side*4,0.1,20)],Vector3.DOWN*0.7,Color(0.75,0.8,0.85)))
		var front := []
		var back := []
		for index in 8:
			var angle := float(index)/8.0*TAU
			var radial := Vector3(side*4.4+cos(angle)*2.7,-1.2+sin(angle)*1.9,0)
			front.append(radial+Vector3(0,0,-4))
			back.append(radial+Vector3(0,0,20.5))
		var pod_faces := []
		for index in 8:
			var next := (index+1)%8
			pod_faces.append([front[index],front[next],back[next],back[index]])
		pod_faces.append(front)
		pod_faces.append(back)
		parts.append(mesh_from_faces(pod_faces,Vector3(side*4.4,-1.2,8),Color(0.5,0.55,0.65)))
		# Dark intake and nozzle faces use the canopy/metal response independently.
		var intake := []
		var nozzle_face := []
		for index in 8:
			var angle := float(index)/8.0*TAU
			intake.append(Vector3(side*4.4+cos(angle)*2.3,-1.2+sin(angle)*1.5,-4.05))
			nozzle_face.append(Vector3(side*4.4+cos(angle)*2.3,-1.2+sin(angle)*1.5,20.55))
		dark_faces.append(intake)
		dark_faces.append(nozzle_face)
	var glass_edge := [Vector3(0,1.7,-23),Vector3(-2.1,3.4,-13),Vector3(-1.7,3.2,-5),Vector3(0,2.8,-3),Vector3(1.7,3.2,-5),Vector3(2.1,3.4,-13)]
	var frame_base := [Vector3(0,0.7,-23),Vector3(-2.1,1.6,-13),Vector3(-1.7,2.3,-5),Vector3(0,2.6,-3),Vector3(1.7,2.3,-5),Vector3(2.1,1.6,-13)]
	var frame_faces := []
	for edge in glass_edge.size():
		var next := (edge+1)%glass_edge.size()
		frame_faces.append([frame_base[edge],frame_base[next],glass_edge[next],glass_edge[edge]])
	parts.append(mesh_from_faces(frame_faces,Vector3(0,2.5,-12),Color(0.7,0.7,0.7)))
	var assembled := SurfaceTool.new()
	assembled.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts: assembled.append_from(part,0,Transform3D.IDENTITY)
	add_mesh(aircraft_root,assembled.commit(),body).name = "Body"
	var front_peak := Vector3(0,4.4,-16)
	var rear_peak := Vector3(0,5.1,-9)
	var canopy_faces := [[glass_edge[0],glass_edge[1],front_peak],
		[glass_edge[1],glass_edge[2],rear_peak,front_peak],
		[glass_edge[2],glass_edge[3],rear_peak],
		[glass_edge[0],front_peak,glass_edge[5]],
		[glass_edge[5],front_peak,rear_peak,glass_edge[4]],
		[glass_edge[4],rear_peak,glass_edge[3]]]
	add_mesh(aircraft_root,mesh_from_faces(canopy_faces,Vector3(0,3,-12)),canopy).name = "Canopy"
	add_mesh(aircraft_root,mesh_from_faces(dark_faces,Vector3(0,-1.2,8)),canopy).name = "Intakes"
	for side in [-1.0,1.0]:
		var nozzle := add_mesh(aircraft_root,afterburner_mesh(),exhaust)
		nozzle.name = "EngineFlame"+str(side)
		nozzle.position = Vector3(side*4.4,-1.2,20.55)
		nozzle.scale = Vector3(2.5,1.7,14.0)
		nozzle.custom_aabb = nozzle.mesh.get_aabb().grow(0.2)
		nozzle.set_instance_shader_parameter("phase_offset",(side+1.0)*0.31)
		nozzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return aircraft_root

static func _panel_prism(points: Array, thickness: Vector3, color := Color.WHITE) -> ArrayMesh:
	# A small physical bevel supplies grazing normals for the bright aircraft rim.
	var back := []
	var front := []
	var edge := []
	var center := Vector3.ZERO
	for point in points:
		center += point
	center /= points.size()
	for point in points:
		var inset: Vector3 = point.move_toward(center,0.35)
		front.append(inset)
		back.append(inset+thickness)
		edge.append(point+thickness*0.5)
	var reversed_back := back.duplicate()
	reversed_back.reverse()
	var faces := [front,reversed_back]
	for index in points.size():
		var next := (index+1)%points.size()
		faces.append([front[index],front[next],edge[next],edge[index]])
		faces.append([edge[index],edge[next],back[next],back[index]])
	return mesh_from_faces(faces,center+thickness*0.5,color)

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

static func afterburner_mesh() -> ArrayMesh:
	# Preserve the disclosed low-poly flame topology, but scale away from its nozzle.
	var mesh := icosphere()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bounds := mesh.get_aabb()
	for index in vertices.size():
		var axial := (vertices[index].z-bounds.position.z)/bounds.size.z
		var taper := 1.0-axial*0.95
		vertices[index] = Vector3(vertices[index].x*taper,vertices[index].y*taper,axial)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var surface := SurfaceTool.new()
	var anchored := ArrayMesh.new()
	anchored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	surface.create_from(anchored,0)
	surface.generate_normals()
	return surface.commit()

static func terrain() -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 704
	noise.frequency = 0.0011
	noise.fractal_octaves = 3
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 240
	# ponytail: the 22m proxy grid limits cliff/self-shadow fidelity; use finer authored cliffs for the final environment.
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
				# DMC's canyon reference has level caps, broken cliff rims and broad scree
				# skirts. Erode the contour rather than putting noise on the plateau top.
				var erosion := noise.get_noise_2d(px*4.0,pz*4.0)
				var mesa := smoothstep(0.55,0.58,n+erosion*0.012)
				var bench := smoothstep(0.48,0.50,n+erosion*0.018)*45.0
				var talus := pow(smoothstep(0.36,0.54,n),3.0)*65.0
				var outcrop := smoothstep(0.60,0.74,noise.get_noise_2d(px*3.5,pz*3.5)*0.5+0.5)*45.0*(1.0-mesa)
				var ribs := pow(1.0-absf(erosion),3.0)*25.0*smoothstep(0.43,0.55,n)*(1.0-mesa)
				var river_x := sin(pz*0.0028)*190.0 + sin(pz*0.006)*45.0
				var canyon := smoothstep(140.0,420.0,absf(px-river_x))
				var h := 8.0 + (talus+bench+outcrop+ribs+mesa*(185.0+noise.get_noise_2d(px*0.4+800,pz*0.4)*35.0))*canyon
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
