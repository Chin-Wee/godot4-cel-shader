extends RefCounted

# Coarse marching cubes is the production meshing pattern used by Space Engineers.
# https://github.com/KeenSoftwareHouse/SpaceEngineers/blob/master/Sources/Sandbox.Game/Engine/Voxels/MyMarchingCubesMesher.cs
# DELIVERY MUST COMPLETE is the visual reference; its unpublished cloud technique
# is not assumed to be known. No code from the game is used here.
const SIZE := Vector3i(33,21,29)
const BOUNDS := AABB(Vector3(-1.6,-0.6,-1.4),Vector3(3.2,2.0,2.8))
const CORNERS := [Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(1,1,0),Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(1,1,1),Vector3i(0,1,1)]
const EDGES := [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]

# Standard marching-cubes case table from PyMCubes (BSD-3-Clause).
# https://github.com/pmneila/PyMCubes/blob/master/mcubes/src/marchingcubes.cpp
# Copyright (c) 2012-2015, P. M. Neila. License: cloud_field.LICENSE.txt.
const TRIANGLES := [
	[],
	[0,8,3],
	[0,1,9],
	[1,8,3,9,8,1],
	[1,2,10],
	[0,8,3,1,2,10],
	[9,2,10,0,2,9],
	[2,8,3,2,10,8,10,9,8],
	[3,11,2],
	[0,11,2,8,11,0],
	[1,9,0,2,3,11],
	[1,11,2,1,9,11,9,8,11],
	[3,10,1,11,10,3],
	[0,10,1,0,8,10,8,11,10],
	[3,9,0,3,11,9,11,10,9],
	[9,8,10,10,8,11],
	[4,7,8],
	[4,3,0,7,3,4],
	[0,1,9,8,4,7],
	[4,1,9,4,7,1,7,3,1],
	[1,2,10,8,4,7],
	[3,4,7,3,0,4,1,2,10],
	[9,2,10,9,0,2,8,4,7],
	[2,10,9,2,9,7,2,7,3,7,9,4],
	[8,4,7,3,11,2],
	[11,4,7,11,2,4,2,0,4],
	[9,0,1,8,4,7,2,3,11],
	[4,7,11,9,4,11,9,11,2,9,2,1],
	[3,10,1,3,11,10,7,8,4],
	[1,11,10,1,4,11,1,0,4,7,11,4],
	[4,7,8,9,0,11,9,11,10,11,0,3],
	[4,7,11,4,11,9,9,11,10],
	[9,5,4],
	[9,5,4,0,8,3],
	[0,5,4,1,5,0],
	[8,5,4,8,3,5,3,1,5],
	[1,2,10,9,5,4],
	[3,0,8,1,2,10,4,9,5],
	[5,2,10,5,4,2,4,0,2],
	[2,10,5,3,2,5,3,5,4,3,4,8],
	[9,5,4,2,3,11],
	[0,11,2,0,8,11,4,9,5],
	[0,5,4,0,1,5,2,3,11],
	[2,1,5,2,5,8,2,8,11,4,8,5],
	[10,3,11,10,1,3,9,5,4],
	[4,9,5,0,8,1,8,10,1,8,11,10],
	[5,4,0,5,0,11,5,11,10,11,0,3],
	[5,4,8,5,8,10,10,8,11],
	[9,7,8,5,7,9],
	[9,3,0,9,5,3,5,7,3],
	[0,7,8,0,1,7,1,5,7],
	[1,5,3,3,5,7],
	[9,7,8,9,5,7,10,1,2],
	[10,1,2,9,5,0,5,3,0,5,7,3],
	[8,0,2,8,2,5,8,5,7,10,5,2],
	[2,10,5,2,5,3,3,5,7],
	[7,9,5,7,8,9,3,11,2],
	[9,5,7,9,7,2,9,2,0,2,7,11],
	[2,3,11,0,1,8,1,7,8,1,5,7],
	[11,2,1,11,1,7,7,1,5],
	[9,5,8,8,5,7,10,1,3,10,3,11],
	[5,7,0,5,0,9,7,11,0,1,0,10,11,10,0],
	[11,10,0,11,0,3,10,5,0,8,0,7,5,7,0],
	[11,10,5,7,11,5],
	[10,6,5],
	[0,8,3,5,10,6],
	[9,0,1,5,10,6],
	[1,8,3,1,9,8,5,10,6],
	[1,6,5,2,6,1],
	[1,6,5,1,2,6,3,0,8],
	[9,6,5,9,0,6,0,2,6],
	[5,9,8,5,8,2,5,2,6,3,2,8],
	[2,3,11,10,6,5],
	[11,0,8,11,2,0,10,6,5],
	[0,1,9,2,3,11,5,10,6],
	[5,10,6,1,9,2,9,11,2,9,8,11],
	[6,3,11,6,5,3,5,1,3],
	[0,8,11,0,11,5,0,5,1,5,11,6],
	[3,11,6,0,3,6,0,6,5,0,5,9],
	[6,5,9,6,9,11,11,9,8],
	[5,10,6,4,7,8],
	[4,3,0,4,7,3,6,5,10],
	[1,9,0,5,10,6,8,4,7],
	[10,6,5,1,9,7,1,7,3,7,9,4],
	[6,1,2,6,5,1,4,7,8],
	[1,2,5,5,2,6,3,0,4,3,4,7],
	[8,4,7,9,0,5,0,6,5,0,2,6],
	[7,3,9,7,9,4,3,2,9,5,9,6,2,6,9],
	[3,11,2,7,8,4,10,6,5],
	[5,10,6,4,7,2,4,2,0,2,7,11],
	[0,1,9,4,7,8,2,3,11,5,10,6],
	[9,2,1,9,11,2,9,4,11,7,11,4,5,10,6],
	[8,4,7,3,11,5,3,5,1,5,11,6],
	[5,1,11,5,11,6,1,0,11,7,11,4,0,4,11],
	[0,5,9,0,6,5,0,3,6,11,6,3,8,4,7],
	[6,5,9,6,9,11,4,7,9,7,11,9],
	[10,4,9,6,4,10],
	[4,10,6,4,9,10,0,8,3],
	[10,0,1,10,6,0,6,4,0],
	[8,3,1,8,1,6,8,6,4,6,1,10],
	[1,4,9,1,2,4,2,6,4],
	[3,0,8,1,2,9,2,4,9,2,6,4],
	[0,2,4,4,2,6],
	[8,3,2,8,2,4,4,2,6],
	[10,4,9,10,6,4,11,2,3],
	[0,8,2,2,8,11,4,9,10,4,10,6],
	[3,11,2,0,1,6,0,6,4,6,1,10],
	[6,4,1,6,1,10,4,8,1,2,1,11,8,11,1],
	[9,6,4,9,3,6,9,1,3,11,6,3],
	[8,11,1,8,1,0,11,6,1,9,1,4,6,4,1],
	[3,11,6,3,6,0,0,6,4],
	[6,4,8,11,6,8],
	[7,10,6,7,8,10,8,9,10],
	[0,7,3,0,10,7,0,9,10,6,7,10],
	[10,6,7,1,10,7,1,7,8,1,8,0],
	[10,6,7,10,7,1,1,7,3],
	[1,2,6,1,6,8,1,8,9,8,6,7],
	[2,6,9,2,9,1,6,7,9,0,9,3,7,3,9],
	[7,8,0,7,0,6,6,0,2],
	[7,3,2,6,7,2],
	[2,3,11,10,6,8,10,8,9,8,6,7],
	[2,0,7,2,7,11,0,9,7,6,7,10,9,10,7],
	[1,8,0,1,7,8,1,10,7,6,7,10,2,3,11],
	[11,2,1,11,1,7,10,6,1,6,7,1],
	[8,9,6,8,6,7,9,1,6,11,6,3,1,3,6],
	[0,9,1,11,6,7],
	[7,8,0,7,0,6,3,11,0,11,6,0],
	[7,11,6],
	[7,6,11],
	[3,0,8,11,7,6],
	[0,1,9,11,7,6],
	[8,1,9,8,3,1,11,7,6],
	[10,1,2,6,11,7],
	[1,2,10,3,0,8,6,11,7],
	[2,9,0,2,10,9,6,11,7],
	[6,11,7,2,10,3,10,8,3,10,9,8],
	[7,2,3,6,2,7],
	[7,0,8,7,6,0,6,2,0],
	[2,7,6,2,3,7,0,1,9],
	[1,6,2,1,8,6,1,9,8,8,7,6],
	[10,7,6,10,1,7,1,3,7],
	[10,7,6,1,7,10,1,8,7,1,0,8],
	[0,3,7,0,7,10,0,10,9,6,10,7],
	[7,6,10,7,10,8,8,10,9],
	[6,8,4,11,8,6],
	[3,6,11,3,0,6,0,4,6],
	[8,6,11,8,4,6,9,0,1],
	[9,4,6,9,6,3,9,3,1,11,3,6],
	[6,8,4,6,11,8,2,10,1],
	[1,2,10,3,0,11,0,6,11,0,4,6],
	[4,11,8,4,6,11,0,2,9,2,10,9],
	[10,9,3,10,3,2,9,4,3,11,3,6,4,6,3],
	[8,2,3,8,4,2,4,6,2],
	[0,4,2,4,6,2],
	[1,9,0,2,3,4,2,4,6,4,3,8],
	[1,9,4,1,4,2,2,4,6],
	[8,1,3,8,6,1,8,4,6,6,10,1],
	[10,1,0,10,0,6,6,0,4],
	[4,6,3,4,3,8,6,10,3,0,3,9,10,9,3],
	[10,9,4,6,10,4],
	[4,9,5,7,6,11],
	[0,8,3,4,9,5,11,7,6],
	[5,0,1,5,4,0,7,6,11],
	[11,7,6,8,3,4,3,5,4,3,1,5],
	[9,5,4,10,1,2,7,6,11],
	[6,11,7,1,2,10,0,8,3,4,9,5],
	[7,6,11,5,4,10,4,2,10,4,0,2],
	[3,4,8,3,5,4,3,2,5,10,5,2,11,7,6],
	[7,2,3,7,6,2,5,4,9],
	[9,5,4,0,8,6,0,6,2,6,8,7],
	[3,6,2,3,7,6,1,5,0,5,4,0],
	[6,2,8,6,8,7,2,1,8,4,8,5,1,5,8],
	[9,5,4,10,1,6,1,7,6,1,3,7],
	[1,6,10,1,7,6,1,0,7,8,7,0,9,5,4],
	[4,0,10,4,10,5,0,3,10,6,10,7,3,7,10],
	[7,6,10,7,10,8,5,4,10,4,8,10],
	[6,9,5,6,11,9,11,8,9],
	[3,6,11,0,6,3,0,5,6,0,9,5],
	[0,11,8,0,5,11,0,1,5,5,6,11],
	[6,11,3,6,3,5,5,3,1],
	[1,2,10,9,5,11,9,11,8,11,5,6],
	[0,11,3,0,6,11,0,9,6,5,6,9,1,2,10],
	[11,8,5,11,5,6,8,0,5,10,5,2,0,2,5],
	[6,11,3,6,3,5,2,10,3,10,5,3],
	[5,8,9,5,2,8,5,6,2,3,8,2],
	[9,5,6,9,6,0,0,6,2],
	[1,5,8,1,8,0,5,6,8,3,8,2,6,2,8],
	[1,5,6,2,1,6],
	[1,3,6,1,6,10,3,8,6,5,6,9,8,9,6],
	[10,1,0,10,0,6,9,5,0,5,6,0],
	[0,3,8,5,6,10],
	[10,5,6],
	[11,5,10,7,5,11],
	[11,5,10,11,7,5,8,3,0],
	[5,11,7,5,10,11,1,9,0],
	[10,7,5,10,11,7,9,8,1,8,3,1],
	[11,1,2,11,7,1,7,5,1],
	[0,8,3,1,2,7,1,7,5,7,2,11],
	[9,7,5,9,2,7,9,0,2,2,11,7],
	[7,5,2,7,2,11,5,9,2,3,2,8,9,8,2],
	[2,5,10,2,3,5,3,7,5],
	[8,2,0,8,5,2,8,7,5,10,2,5],
	[9,0,1,5,10,3,5,3,7,3,10,2],
	[9,8,2,9,2,1,8,7,2,10,2,5,7,5,2],
	[1,3,5,3,7,5],
	[0,8,7,0,7,1,1,7,5],
	[9,0,3,9,3,5,5,3,7],
	[9,8,7,5,9,7],
	[5,8,4,5,10,8,10,11,8],
	[5,0,4,5,11,0,5,10,11,11,3,0],
	[0,1,9,8,4,10,8,10,11,10,4,5],
	[10,11,4,10,4,5,11,3,4,9,4,1,3,1,4],
	[2,5,1,2,8,5,2,11,8,4,5,8],
	[0,4,11,0,11,3,4,5,11,2,11,1,5,1,11],
	[0,2,5,0,5,9,2,11,5,4,5,8,11,8,5],
	[9,4,5,2,11,3],
	[2,5,10,3,5,2,3,4,5,3,8,4],
	[5,10,2,5,2,4,4,2,0],
	[3,10,2,3,5,10,3,8,5,4,5,8,0,1,9],
	[5,10,2,5,2,4,1,9,2,9,4,2],
	[8,4,5,8,5,3,3,5,1],
	[0,4,5,1,0,5],
	[8,4,5,8,5,3,9,0,5,0,3,5],
	[9,4,5],
	[4,11,7,4,9,11,9,10,11],
	[0,8,3,4,9,7,9,11,7,9,10,11],
	[1,10,11,1,11,4,1,4,0,7,4,11],
	[3,1,4,3,4,8,1,10,4,7,4,11,10,11,4],
	[4,11,7,9,11,4,9,2,11,9,1,2],
	[9,7,4,9,11,7,9,1,11,2,11,1,0,8,3],
	[11,7,4,11,4,2,2,4,0],
	[11,7,4,11,4,2,8,3,4,3,2,4],
	[2,9,10,2,7,9,2,3,7,7,4,9],
	[9,10,7,9,7,4,10,2,7,8,7,0,2,0,7],
	[3,7,10,3,10,2,7,4,10,1,10,0,4,0,10],
	[1,10,2,8,7,4],
	[4,9,1,4,1,7,7,1,3],
	[4,9,1,4,1,7,0,8,1,8,7,1],
	[4,0,3,7,4,3],
	[4,8,7],
	[9,10,8,10,11,8],
	[3,0,9,3,9,11,11,9,10],
	[0,1,10,0,10,8,8,10,11],
	[3,1,10,11,3,10],
	[1,2,11,1,11,9,9,11,8],
	[3,0,9,3,9,11,1,2,9,2,11,9],
	[0,2,11,8,0,11],
	[3,2,11],
	[2,3,8,2,8,10,10,8,9],
	[9,10,2,0,9,2],
	[2,3,8,2,8,10,0,1,8,1,10,8],
	[1,10,2],
	[1,3,8,9,1,8],
	[0,9,1],
	[0,3,8],
	[],
]

static func generate(variant: int) -> PackedFloat32Array:
	var macro := FastNoiseLite.new()
	macro.seed = 2917+variant*103
	macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	macro.fractal_type = FastNoiseLite.FRACTAL_NONE
	macro.frequency = 1.4
	var detail := FastNoiseLite.new()
	detail.seed = 7919+variant*127
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.fractal_type = FastNoiseLite.FRACTAL_NONE
	detail.frequency = 5.0
	var values := PackedFloat32Array()
	values.resize(SIZE.x*SIZE.y*SIZE.z)
	for z in SIZE.z:
		for y in SIZE.y:
			for x in SIZE.x:
				var p := grid_position(Vector3i(x,y,z))
				var field := _ellipsoid(p,Vector3(1.22,0.30,0.99))
				field = _union(field,_ellipsoid(p-Vector3(0.72,-0.015,0.14),Vector3(0.70,0.22,0.68)),0.12)
				field = _union(field,_ellipsoid(p-Vector3(-0.77,-0.08,-0.25),Vector3(0.65,0.21,0.70)),0.1)
				field = _union(field,_ellipsoid(p-Vector3(1.10,-0.10,0.14),Vector3(0.32,0.22,0.55)),0.08)
				if variant == 1:
					field = _union(field,_ellipsoid(p-Vector3(-0.40,0.24,-0.20),Vector3(0.60,0.44,0.56)),0.13)
				elif variant == 2:
					field = _union(field,_ellipsoid(p-Vector3(0.18,0.40,-0.20),Vector3(0.53,0.68,0.52)),0.14)
				elif variant == 3:
					field = _union(field,_ellipsoid(p-Vector3(-0.58,0.26,-0.22),Vector3(0.49,0.49,0.55)),0.11)
					field = _union(field,_ellipsoid(p-Vector3(0.49,0.22,0.30),Vector3(0.48,0.40,0.48)),0.1)
				# Two frequencies only: broad warped mass plus weak secondary breakup.
				field += macro.get_noise_3dv(p)*0.11+detail.get_noise_3dv(p)*0.018
				# A side-open underside cut creates an overhang, with solid shelf beyond
				# it. A radial envelope cannot represent its exit/re-entry boundary.
				var cut := _ellipsoid(p-Vector3(0.72,-0.19,0.14),Vector3(0.28,0.19,0.56))
				field = minf(field,-cut)
				# A rounded outer envelope keeps the sampled boundary strictly empty.
				field = minf(field,_ellipsoid(p-Vector3(0,0.25,0),Vector3(1.52,1.08,1.31)))
				values[_index(Vector3i(x,y,z))] = field
	# Remove detached noise specks in the authoritative field, before meshing.
	# Weather and GPU shadows therefore discard exactly the same tiny islands.
	_keep_connected(values)
	return values

static func _keep_connected(values: PackedFloat32Array) -> void:
	var visited := PackedByteArray()
	visited.resize(values.size())
	var seed := _index(Vector3i(16,6,14))
	assert(values[seed]>0.0,"The cloud deck must contain its origin")
	var queue := PackedInt32Array([seed])
	visited[seed]=1
	var head := 0
	while head<queue.size():
		var cell := queue[head]
		head+=1
		# Outer grid faces are strictly negative, so positive cells never wrap.
		for offset in [-1,1,-SIZE.x,SIZE.x,-SIZE.x*SIZE.y,SIZE.x*SIZE.y]:
			var next: int=cell+offset
			if visited[next]==0 and values[next]>0.0:
				visited[next]=1
				queue.append(next)
	for index in values.size():
		if values[index]>0.0 and visited[index]==0: values[index]=-values[index]

static func _ellipsoid(point: Vector3, radius: Vector3) -> float:
	return (1.0-(point/radius).length())*minf(radius.x,minf(radius.y,radius.z))

static func _union(a: float, b: float, softness: float) -> float:
	var h := maxf(softness-absf(a-b),0.0)/softness
	return maxf(a,b)+h*h*softness*0.25

static func _index(point: Vector3i) -> int:
	return point.x+SIZE.x*(point.y+SIZE.y*point.z)

static func grid_position(point: Vector3i) -> Vector3:
	return BOUNDS.position+Vector3(point)/Vector3(SIZE-Vector3i.ONE)*BOUNDS.size

static func sample(values: PackedFloat32Array, point: Vector3) -> float:
	if not BOUNDS.has_point(point): return -1.0
	var coord := (point-BOUNDS.position)/BOUNDS.size*Vector3(SIZE-Vector3i.ONE)
	var cell := Vector3i(coord.floor()).min(SIZE-Vector3i(2,2,2))
	var f := coord-Vector3(cell)
	var a := lerpf(values[_index(cell)],values[_index(cell+Vector3i(1,0,0))],f.x)
	var b := lerpf(values[_index(cell+Vector3i(0,1,0))],values[_index(cell+Vector3i(1,1,0))],f.x)
	var c := lerpf(values[_index(cell+Vector3i(0,0,1))],values[_index(cell+Vector3i(1,0,1))],f.x)
	var d := lerpf(values[_index(cell+Vector3i(0,1,1))],values[_index(cell+Vector3i(1,1,1))],f.x)
	return lerpf(lerpf(a,b,f.y),lerpf(c,d,f.y),f.z)

static func normal(values: PackedFloat32Array, point: Vector3) -> Vector3:
	var step := BOUNDS.size/Vector3(SIZE-Vector3i.ONE)*0.5
	var gradient := Vector3(
		(sample(values,point+Vector3(step.x,0,0))-sample(values,point-Vector3(step.x,0,0)))/step.x,
		(sample(values,point+Vector3(0,step.y,0))-sample(values,point-Vector3(0,step.y,0)))/step.y,
		(sample(values,point+Vector3(0,0,step.z))-sample(values,point-Vector3(0,0,step.z)))/step.z)
	return -gradient.normalized()

static func mesh(values: PackedFloat32Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var shared_edges := {}
	for z in SIZE.z-1:
		for y in SIZE.y-1:
			for x in SIZE.x-1:
				var origin := Vector3i(x,y,z)
				var corners := PackedInt32Array()
				var cell := 0
				for corner in 8:
					var id := _index(origin+CORNERS[corner])
					corners.append(id)
					if values[id] > 0.0: cell |= 1<<corner
				var faces: Array = TRIANGLES[cell]
				for triangle in range(0,faces.size(),3):
					var face := PackedInt32Array()
					for corner in 3:
						var edge: Array = EDGES[faces[triangle+corner]]
						var a: int = corners[edge[0]]
						var b: int = corners[edge[1]]
						var key := mini(a,b)*SIZE.x*SIZE.y*SIZE.z+maxi(a,b)
						if not shared_edges.has(key):
							var weight := values[a]/(values[a]-values[b])
							var point := grid_position(origin+CORNERS[edge[0]]).lerp(grid_position(origin+CORNERS[edge[1]]),weight)
							shared_edges[key] = vertices.size()
							vertices.append(point)
							normals.append(normal(values,point))
						face.append(shared_edges[key])
					var average := normals[face[0]]+normals[face[1]]+normals[face[2]]
					if (vertices[face[1]]-vertices[face[0]]).cross(vertices[face[2]]-vertices[face[0]]).dot(average) > 0.0:
						var swap := face[1]
						face[1] = face[2]
						face[2] = swap
					indices.append_array(face)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
