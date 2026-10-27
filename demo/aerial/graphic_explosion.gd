extends Node3D

# Battlefront II is the production reference for independently simulated VFX
# particles with gravity and air resistance; DMC remains the cel visual reference.
# https://forums.ea.com/discussions/star-wars-battlefront-2-en/community-transmission-%E2%80%94-visual-effects-in-star-wars-battlefront-ii/10820960
# Closed-form drag keeps this small mesh effect deterministic when paused/scrubbed.
const Geometry = preload("res://aerial/geometry.gd")
var elapsed := 0.0
var duration := 0.0
var burst_seed := 0
var materials: Array[ShaderMaterial] = []
var lobes: Array[MeshInstance3D] = []
var accents: Array[MeshInstance3D] = []
var debris: Array[MeshInstance3D] = []
var particles: Array[Dictionary] = []
var fire_emission := 0.0
var _flow := FastNoiseLite.new()

func build(fire: ShaderMaterial, smoke: ShaderMaterial, accent: ShaderMaterial, seed_value := -1) -> void:
	fire_emission = float(fire.get_shader_parameter("emission_strength"))
	var rng := RandomNumberGenerator.new()
	if seed_value < 0: rng.randomize()
	else: rng.seed = seed_value
	burst_seed = rng.seed
	_flow.seed = int(burst_seed%2147483647)
	_flow.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_flow.fractal_type = FastNoiseLite.FRACTAL_NONE
	_flow.frequency = 0.7
	var wind := Vector3(rng.randf_range(-3,3),0,rng.randf_range(-2,2))
	for index in 20:
		var fiery := index < 8
		var material := (fire if fiery else smoke).duplicate() as ShaderMaterial
		if fiery:
			material.set_shader_parameter("graphic_fire",true)
			material.set_shader_parameter("shape_seed",rng.randf_range(0,32))
		if not fiery:
			material.set_shader_parameter("vfx_soft_edge",0.8)
			material.set_shader_parameter("vfx_bands",true)
			material.set_shader_parameter("trail_opacity",rng.randf_range(0.75,0.95))
		var direction := Vector3(rng.randf_range(-1,1),rng.randf_range(-0.25,0.9),rng.randf_range(-1,1)).normalized()
		var tint := Color.WHITE if fiery else Color(0.72,0.79,0.9)*rng.randf_range(0.85,1.1)
		var state := {
			"kind":0 if fiery else 1,"birth":0.0 if index == 0 else rng.randf_range(0.01,0.12) if fiery else rng.randf_range(0.05,0.22),
			"life":rng.randf_range(0.55,1.05) if fiery else rng.randf_range(2.9,4.2),
			"origin":direction*rng.randf_range(0,2.5) if fiery else direction*rng.randf_range(3,8),
			"velocity":direction*rng.randf_range(42,65)+Vector3.UP*7.0 if fiery else direction*rng.randf_range(24,45)+Vector3.UP*8.0,
			"terminal":wind+Vector3.UP*(rng.randf_range(4,8) if fiery else rng.randf_range(10,16)),
			"drag":rng.randf_range(2.7,4.5) if fiery else rng.randf_range(1.0,2.2),
			"radius":rng.randf_range(7,12) if fiery else rng.randf_range(9,15),
			"growth":rng.randf_range(13,24) if fiery else rng.randf_range(2.6,4.1),
			"shape":Vector3(rng.randf_range(0.85,1.2),rng.randf_range(0.85,1.15),rng.randf_range(0.85,1.2)),
			"rotation":Vector3(rng.randf_range(-PI,PI),rng.randf_range(-PI,PI),rng.randf_range(-PI,PI)),
			"spin":Vector3(rng.randf_range(-0.3,0.3),rng.randf_range(-0.3,0.3),rng.randf_range(-0.3,0.3)),
			"flow_anchor":Vector3(rng.randf_range(-20,20),rng.randf_range(-20,20),rng.randf_range(-20,20)),
		}
		var node := _spawn(_lobe_mesh(rng.randf_range(0,100),tint),material,state)
		lobes.append(node)
	for index in 12:
		var direction := Vector3(rng.randf_range(-1,1),rng.randf_range(-0.5,1),rng.randf_range(-1,1)).normalized()
		var state := {"kind":2,"birth":rng.randf_range(0,0.04),"life":rng.randf_range(0.14,0.48),
			"origin":Vector3.ZERO,"velocity":direction*rng.randf_range(65,130),"terminal":Vector3(0,-12,0),
			"drag":rng.randf_range(1.8,3.2),"width":rng.randf_range(0.18,0.4),"length":rng.randf_range(3,9)}
		accents.append(_spawn(Geometry.icosphere(),accent.duplicate(),state))
	for index in 6:
		var drag := rng.randf_range(0.2,0.45)
		var state := {"kind":3,"birth":0.0,"life":rng.randf_range(1.0,2.2),
			"origin":Vector3.ZERO,"velocity":Vector3(rng.randf_range(-32,32),rng.randf_range(18,42),rng.randf_range(-32,32)),
			"terminal":Vector3(wind.x,-28.0/drag,wind.z),"drag":drag,
			"shape":Vector3(rng.randf_range(0.5,1.0),rng.randf_range(0.4,0.8),rng.randf_range(1.3,2.4)),
			"rotation":Vector3(rng.randf_range(-PI,PI),rng.randf_range(-PI,PI),rng.randf_range(-PI,PI)),
			"spin":Vector3(rng.randf_range(-4,4),rng.randf_range(-4,4),rng.randf_range(-4,4))}
		debris.append(_spawn(Geometry.icosphere(),smoke.duplicate(),state))
	duration += 0.15
	set_time(0)

func _spawn(mesh: Mesh, material: ShaderMaterial, state: Dictionary) -> MeshInstance3D:
	var node := Geometry.add_mesh(self,mesh,material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	state["node"] = node
	state["material"] = material
	if state.has("flow_anchor"): state["flow_start"] = _flow_vector(state.flow_anchor)
	particles.append(state)
	materials.append(material)
	duration = maxf(duration,state.birth+state.life)
	return node

func _flow_vector(point: Vector3) -> Vector3:
	return Vector3(_flow.get_noise_3dv(point),_flow.get_noise_3dv(point+Vector3(31,17,9)),_flow.get_noise_3dv(point+Vector3(7,43,23)))

static func transport(velocity: Vector3, terminal: Vector3, drag: float, seconds: float) -> Vector3:
	return terminal*seconds+(velocity-terminal)*((1.0-exp(-drag*seconds))/drag)

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
	elapsed = maxf(seconds,0.0)
	for state in particles:
		var t := clampf(elapsed-float(state.birth),0.0,float(state.life))
		var age := t/float(state.life)
		var node: MeshInstance3D = state.node
		var material: ShaderMaterial = state.material
		node.visible = elapsed >= float(state.birth) and age < 1.0
		material.set_shader_parameter("normalized_age",age)
		material.set_shader_parameter("effect_time",t)
		node.position = state.origin+transport(state.velocity,state.terminal,state.drag,t)
		if int(state.kind) <= 1:
			var fiery := int(state.kind) == 0
			var flow := _flow_vector(state.flow_anchor+Vector3(0,t*0.9,t*0.35))-Vector3(state.flow_start)
			node.position += flow*(1.0-exp(-t*1.5))*(1.8 if fiery else 4.0)
			node.rotation = state.rotation+state.spin*t
			var radius := float(state.radius)*(1.0-exp(-t*float(state.growth)))*(1.0+age*0.3)
			if fiery: radius *= 1.0-smoothstep(0.6,1.0,age)*0.45
			node.scale = Vector3(state.shape)*radius
			if fiery: material.set_shader_parameter("emission_strength",fire_emission*exp(-age*2.8)*(1.0+2.5*exp(-t*28.0)))
		elif int(state.kind) == 2:
			var velocity: Vector3 = (Vector3(state.velocity)-Vector3(state.terminal))*exp(-float(state.drag)*t)+Vector3(state.terminal)
			var up := Vector3.RIGHT if absf(velocity.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
			node.basis = Basis.looking_at(velocity.normalized(),up)
			node.scale = Vector3(state.width,state.width,float(state.length)*(1.0-age*0.75))
			material.set_shader_parameter("emission_strength",2.5+(1.0-age)*1.5)
		else:
			node.rotation = state.rotation+state.spin*t
			node.scale = state.shape

func _process(delta: float) -> void:
	set_time(elapsed+delta)
	if elapsed >= duration: queue_free()
