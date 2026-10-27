extends Node3D

# Production visual reference: DELIVERY MUST COMPLETE's few large fire/smoke
# masses and sweeping energy arcs. Its unpublished implementation is not assumed.
const Geometry = preload("res://aerial/geometry.gd")
const SMOKE_OFFSETS := [Vector3(-20,-9,-6),Vector3(-24,-1,18),Vector3(8,-5,-14),
	Vector3(-24,16,-4),Vector3(-22,22,18),Vector3(18,14,-13),
	Vector3(-13,38,-8),Vector3(9,41,-12),Vector3(22,31,10),
	Vector3(-1,56,-10),Vector3(18,53,-18),Vector3(-26,42,-3)]
var elapsed := 0.0
var duration := 4.0
var materials: Array[ShaderMaterial] = []
var lobes: Array[MeshInstance3D] = []
var offsets: Array[Vector3] = []
var shapes: Array[Vector3] = []
var sizes: Array[float] = []
var ring: MeshInstance3D
var accents: Array[MeshInstance3D] = []
var accent_transforms: Array[Transform3D] = []
var fire_emission := 0.0

func build(fire: ShaderMaterial, smoke: ShaderMaterial, accent: ShaderMaterial) -> void:
	fire_emission = float(fire.get_shader_parameter("emission_strength"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 325
	for index in 20:
		var material := (fire if index < 8 else smoke).duplicate() as ShaderMaterial
		if index < 8:
			material.set_shader_parameter("graphic_fire",true)
			material.set_shader_parameter("shape_seed",float(index)*0.618)
		materials.append(material)
		var tint := Color.WHITE if index < 8 else Color(0.65+0.25*sin(index*1.7),0.72+0.2*sin(index*1.7),0.9)
		var lobe := Geometry.add_mesh(self,_lobe_mesh(float(index)*1.37,tint),material)
		lobes.append(lobe)
		var angle := float(index)*2.399
		if index < 8:
			offsets.append(Vector3(sin(angle)*13.0-6.0,float(index)*6.4-8.0,cos(angle)*9.0+18.0))
			sizes.append(rng.randf_range(12.0,18.0))
			shapes.append(Vector3.ONE)
		else:
			offsets.append(SMOKE_OFFSETS[index-8])
			sizes.append(rng.randf_range(15.0,21.0))
			shapes.append(Vector3(1.1+0.15*sin(angle),0.95+0.18*cos(angle),1.0))
	materials.append(smoke) # The four debris shards share this source material.
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 56
	torus.ring_segments = 5
	ring = Geometry.add_mesh(self,torus,accent)
	for index in 12:
		var streak := Geometry.add_mesh(self,Geometry.icosphere(),accent)
		var direction := Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
		streak.position = direction*rng.randf_range(22,55)
		streak.look_at_from_position(streak.position,streak.position-direction)
		streak.scale = Vector3(0.5,0.5,rng.randf_range(5,14))
		accents.append(streak)
		accent_transforms.append(streak.transform)
	# Graphic curling arcs use a small opaque ribbon rather than transparent flipbooks.
	for index in 3:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for segment in 48:
			var t := float(segment)/48.0
			var u := float(segment+1)/48.0
			var a := t*TAU*0.78
			var b := u*TAU*0.78
			var radial_p := Vector3(cos(a),sin(a),0)
			var radial_q := Vector3(cos(b),sin(b),0)
			var p := radial_p*(48.0+t*22.0)+Vector3.BACK*a*3.0
			var q := radial_q*(48.0+u*22.0)+Vector3.BACK*b*3.0
			var outer_p := p+radial_p*(0.1+pow(sin(t*PI),0.8)*4.8)
			var outer_q := q+radial_q*(0.1+pow(sin(u*PI),0.8)*4.8)
			for vertex in [[p,true],[q,true],[outer_p,false],[q,true],[outer_q,false],[outer_p,false]]:
				surface.set_normal(Vector3.FORWARD)
				surface.set_color(Color(1,1,0.65) if vertex[1] else Color(1,0.17,0.005))
				surface.add_vertex(vertex[0])
		var arc := Geometry.add_mesh(self,surface.commit(),accent)
		arc.rotation = Vector3(index*0.7,index*0.9,index*0.4)
		accents.append(arc)
		accent_transforms.append(arc.transform)
	for index in 4:
		var shard := Geometry.add_mesh(self,Geometry.icosphere(),smoke)
		shard.position = Vector3(rng.randf_range(-30,30),rng.randf_range(-20,30),rng.randf_range(-10,10))
		shard.scale = Vector3(1,0.7,2)
	for node in get_children():
		if node is GeometryInstance3D:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_time(0)

func _lobe_mesh(seed: float, tint: Color) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		var p := vertices[index]
		vertices[index] *= 1.0+0.13*sin(p.x*5.0+seed)*sin(p.y*4.0+p.z*4.0)+0.07*cos(p.z*7.0+p.x*2.0+seed)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(tint)
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var surface := SurfaceTool.new()
	surface.create_from(mesh,0)
	surface.generate_normals()
	return surface.commit()

func set_time(seconds: float) -> void:
	elapsed = seconds
	var age := clampf(seconds/duration,0.0,1.0)
	for index in materials.size():
		materials[index].set_shader_parameter("normalized_age",clampf(seconds/2.4,0.0,1.0) if index < 8 else age)
	# Destiny 2 is the timing reference: fast primary energy, delayed secondary smoke.
	# Evaluate native easing on the shared clock so pause/scrubbing stay deterministic.
	var fire_growth: float = Tween.interpolate_value(0.0,1.0,clampf(seconds,0.0,0.4),0.4,Tween.TRANS_BACK,Tween.EASE_OUT)
	var smoke_growth: float = Tween.interpolate_value(0.0,1.0,clampf(seconds-0.07,0.0,0.9),0.9,Tween.TRANS_QUART,Tween.EASE_OUT)
	for index in lobes.size():
		var expansion := fire_growth if index < 8 else smoke_growth
		var phase := float(index)*2.399
		var billow := Vector3(sin(seconds*2.2+phase),0.0,cos(seconds*1.7+phase))*smoke_growth*2.0 if index >= 8 else Vector3.ZERO
		lobes[index].position = offsets[index]*expansion+Vector3.UP*seconds*(4.0 if index < 8 else 9.0)+billow
		var stretch := Vector3(1.0,1.0+sin(seconds*3.0+phase)*0.08*smoke_growth,1.0) if index >= 8 else Vector3.ONE
		lobes[index].scale = shapes[index]*stretch*sizes[index]*expansion*(1.0+age*0.4)
		if index < 8: materials[index].set_shader_parameter("emission_strength",fire_emission*(1.0+1.5*exp(-seconds*24.0)))
	var onset: float = Tween.interpolate_value(0.0,1.0,clampf(seconds,0.0,0.45),0.45,Tween.TRANS_BACK,Tween.EASE_OUT)
	for index in accents.size():
		accents[index].transform = accent_transforms[index].scaled(Vector3.ONE*onset)
	var wave: float = Tween.interpolate_value(0.0,1.0,clampf(seconds,0.0,1.3),1.3,Tween.TRANS_QUART,Tween.EASE_OUT)
	ring.scale = Vector3.ONE*(8.0+wave*52.0)
	# Shared arc/ring/streak material ages with the same reusable VFX shader.
	(ring.material_override as ShaderMaterial).set_shader_parameter("normalized_age",clampf(seconds/1.6,0.0,1.0))

func _process(delta: float) -> void:
	set_time(elapsed+delta)
	if elapsed >= duration: queue_free()
