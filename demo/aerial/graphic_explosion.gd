extends Node3D

const Geometry = preload("res://aerial/geometry.gd")
var elapsed := 0.0
var duration := 4.0
var materials: Array[ShaderMaterial] = []
var lobes: Array[MeshInstance3D] = []
var directions: Array[Vector3] = []
var sizes: Array[float] = []
var ring: MeshInstance3D

func build(fire: ShaderMaterial, smoke: ShaderMaterial) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 325
	for index in 20:
		var material := (fire if index < 8 else smoke).duplicate() as ShaderMaterial
		if index < 8: material.set_shader_parameter("graphic_fire",true)
		materials.append(material)
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 10
		sphere.rings = 5
		var lobe := Geometry.add_mesh(self,sphere,material)
		lobes.append(lobe)
		directions.append(Vector3(rng.randf_range(-1,1),rng.randf_range(-0.3,1.6),rng.randf_range(-1,1)))
		sizes.append(rng.randf_range(12.0,19.0) if index < 8 else rng.randf_range(10.0,16.0))
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 56
	torus.ring_segments = 5
	ring = Geometry.add_mesh(self,torus,fire)
	for index in 12:
		var streak := Geometry.add_mesh(self,Geometry.icosphere(),fire)
		var direction := Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
		streak.position = direction*rng.randf_range(22,55)
		streak.look_at_from_position(streak.position,streak.position-direction)
		streak.scale = Vector3(0.5,0.5,rng.randf_range(5,14))
	# Graphic curling arcs use a small opaque ribbon rather than transparent flipbooks.
	for index in 3:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for segment in 48:
			var a := float(segment)/48.0*TAU*0.85
			var b := float(segment+1)/48.0*TAU*0.85
			var p := Vector3(cos(a)*48.0,sin(a)*48.0,a*3.0)
			var q := Vector3(cos(b)*48.0,sin(b)*48.0,b*3.0)
			for point in [p,q,p+Vector3.UP*1.4,q,q+Vector3.UP*1.4,p+Vector3.UP*1.4]:
				surface.set_normal(Vector3.FORWARD)
				surface.add_vertex(point)
		var arc := Geometry.add_mesh(self,surface.commit(),fire)
		arc.rotation = Vector3(index*0.7,index*0.9,index*0.4)
	for index in 4:
		var shard := Geometry.add_mesh(self,Geometry.icosphere(),smoke)
		shard.position = Vector3(rng.randf_range(-30,30),rng.randf_range(-20,30),rng.randf_range(-10,10))
		shard.scale = Vector3(1,0.7,2)
	for node in get_children():
		if node is GeometryInstance3D:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_time(0)

func set_time(seconds: float) -> void:
	elapsed = seconds
	var age := clampf(seconds/duration,0.0,1.0)
	for material in materials: material.set_shader_parameter("normalized_age",age)
	var expansion := 1.0-exp(-seconds*3.0)
	for index in lobes.size():
		lobes[index].position = directions[index]*expansion*(13.0 if index < 8 else 25.0)+Vector3.UP*seconds*(4.0 if index < 8 else 9.0)+Vector3(0,0,18 if index < 8 else -14)
		lobes[index].scale = Vector3.ONE*sizes[index]*expansion*(1.0+age*0.4)
	ring.scale = Vector3.ONE*(8.0+seconds*32.0)
	# Shared arc/ring/streak material ages with the same reusable VFX shader.
	(ring.material_override as ShaderMaterial).set_shader_parameter("normalized_age",age)

func _process(delta: float) -> void:
	set_time(elapsed+delta)
	if elapsed >= duration: queue_free()
