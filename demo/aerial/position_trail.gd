extends MultiMeshInstance3D

# DELIVERY MUST COMPLETE is the production visual reference: discrete faceted
# smoke, wider dithered vapor, and separate fine/HDR ribbons. Its source is unpublished.
const Geometry = preload("res://aerial/geometry.gd")
const CAPACITY := 512
const SMOKE := 0
const THIN := 1
const MISSILE := 2
@export var emitter: Node3D
@export var spacing := 3.0
@export var width := 1.5
@export var lifetime := 16.0
var elapsed := 20.0
var next_slot := 0
var previous_position := Vector3.ZERO
var has_previous := false
var sample_count := 0
var last_sample_position := Vector3.ZERO
var distance_since_sample := 0.0
var previous_time := 20.0
var kind := SMOKE
var vapor: MultiMeshInstance3D
var emissive_core: MultiMeshInstance3D
var _materials: Array[ShaderMaterial] = []
var _layers: Array[MultiMeshInstance3D] = []

func configure(material: ShaderMaterial, style := SMOKE) -> void:
	assert(spacing > 0.0 and width > 0.0 and lifetime > 0.0)
	assert(style in [SMOKE,THIN,MISSILE] and multimesh == null,"Configure a trail once")
	kind = style
	top_level = true
	global_transform = Transform3D.IDENTITY
	_setup_layer(self,_ribbon_mesh() if kind == THIN else _wedge_mesh(),material)
	material_override.set_shader_parameter("trail_style",2 if kind == THIN else 1)
	material_override.set_shader_parameter("trail_profile",2 if kind == THIN else 0)
	material_override.set_shader_parameter("trail_roll_speed",0.055 if kind != THIN else 0.0)
	if kind != THIN:
		vapor = MultiMeshInstance3D.new()
		vapor.name = "DitheredVapor"
		add_child(vapor)
		_setup_layer(vapor,_ribbon_mesh(),material)
		vapor.material_override.set_shader_parameter("trail_style",2)
		vapor.material_override.set_shader_parameter("trail_profile",1)
		vapor.material_override.set_shader_parameter("trail_opacity",0.24)
		vapor.material_override.set_shader_parameter("trail_tint",Color(0.82,0.89,0.96))
	if kind == MISSILE:
		emissive_core = MultiMeshInstance3D.new()
		emissive_core.name = "EmissiveCore"
		add_child(emissive_core)
		_setup_layer(emissive_core,_ribbon_mesh(),material)
		emissive_core.material_override.set_shader_parameter("trail_style",2)
		emissive_core.material_override.set_shader_parameter("trail_profile",2)
		emissive_core.material_override.set_shader_parameter("expansion",0.0)
		emissive_core.material_override.set_shader_parameter("lifetime",minf(lifetime,0.8))
		emissive_core.material_override.set_shader_parameter("emission_strength",3.5)
		emissive_core.material_override.set_shader_parameter("trail_tint",Color(1.0,0.73,0.2))
	set_time(elapsed)

func _setup_layer(node: MultiMeshInstance3D, mesh: Mesh, material: ShaderMaterial) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_custom_data = true
	node.multimesh.mesh = mesh
	node.multimesh.instance_count = CAPACITY
	for index in CAPACITY:
		node.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
	node.material_override = material.duplicate()
	node.material_override.set_shader_parameter("instance_age",true)
	node.material_override.set_shader_parameter("expansion",3.0)
	node.material_override.set_shader_parameter("lifetime",lifetime)
	node.custom_aabb = AABB(Vector3(-10000,-10000,-10000),Vector3.ONE*20000)
	_layers.append(node)
	_materials.append(node.material_override)

func palette_materials() -> Array[ShaderMaterial]:
	return _materials

func set_time(value: float) -> void:
	elapsed = value
	for material in _materials: material.set_shader_parameter("effect_time",elapsed)

func emit_at(point: Vector3, birth_time: float) -> void:
	if not point.is_finite() or not is_finite(birth_time):
		push_error("Trail samples must have finite position and time")
		return
	var phase := float(sample_count)*2.399
	var puff_width := width*(0.85+0.15*sin(phase))
	var segment := point-last_sample_position
	var connected := sample_count > 0 and segment.length_squared() > 0.0001 and segment.length() <= spacing*64.0
	var direction := segment.normalized() if connected else Vector3.FORWARD
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var basis := Basis.looking_at(direction,up)
	var rolled := _rolled_basis(direction,sample_count)
	var data := Color(birth_time,float(sample_count%97)/97.0,puff_width,1.0)
	if kind == THIN:
		_write_ribbon(self,basis,point,connected,puff_width*0.18,segment.length(),data)
	else:
		var chunk_basis := rolled.scaled_local(Vector3(puff_width,puff_width*(0.85+0.08*cos(phase)),spacing*0.52))
		multimesh.set_instance_transform(next_slot,Transform3D(chunk_basis,point))
		multimesh.set_instance_custom_data(next_slot,data)
		_write_ribbon(vapor,basis,point,connected,puff_width*3.4,maxf(segment.length(),spacing)*2.2,data)
		if emissive_core != null:
			_write_ribbon(emissive_core,basis,point,connected,puff_width*0.16,segment.length(),data)
	last_sample_position = point
	next_slot = (next_slot+1)%CAPACITY
	sample_count += 1

func _write_ribbon(node: MultiMeshInstance3D, basis: Basis, point: Vector3, connected: bool, ribbon_width: float, ribbon_length: float, data: Color) -> void:
	var center := (point+last_sample_position)*0.5 if connected else point
	# Slight overlap closes corner wedges; endpoints still follow the recorded path.
	var length := ribbon_length+ribbon_width*0.15 if connected else 0.0
	node.multimesh.set_instance_transform(next_slot,Transform3D(basis.scaled_local(Vector3(ribbon_width,1.0,maxf(length,0.00001))),center))
	node.multimesh.set_instance_custom_data(next_slot,data if connected else Color(0,0,0,0))

func sample_position(point: Vector3) -> void:
	if not point.is_finite():
		push_error("Trail samples must have finite positions")
		return
	if not has_previous:
		previous_position = point
		previous_time = elapsed
		has_previous = true
		emit_at(point,elapsed)
		return
	var distance := previous_position.distance_to(point)
	if distance > spacing*64.0:
		# A teleport breaks the path without moving or clearing already emitted smoke.
		previous_position = point
		last_sample_position = point
		previous_time = elapsed
		distance_since_sample = 0.0
		return
	if distance > 0.000001:
		var along := spacing-distance_since_sample
		while along <= distance+0.000001:
			var fraction := minf(along/distance,1.0)
			emit_at(previous_position.lerp(point,fraction),lerpf(previous_time,elapsed,fraction))
			along += spacing
		distance_since_sample = fposmod(distance_since_sample+distance,spacing)
		if distance_since_sample < 0.000001 or spacing-distance_since_sample < 0.000001: distance_since_sample = 0.0
	previous_position = point
	previous_time = elapsed

func _process(delta: float) -> void:
	set_time(elapsed+delta)
	if is_instance_valid(emitter): sample_position(emitter.global_position)

static func _rolled_basis(direction: Vector3, index: int) -> Basis:
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var phase := float(index)*2.399
	return Basis.looking_at(direction,up)*Basis(Vector3.BACK,sin(phase)*0.38+cos(phase*0.61)*0.15)

static func _wedge_mesh() -> ArrayMesh:
	var front := []
	var back := []
	var radii := [1.0,0.86,1.04,0.91,0.78,0.96]
	for side in 6:
		var angle := float(side)*TAU/6.0
		front.append(Vector3(cos(angle)*radii[side],sin(angle)*radii[side],-0.25))
		back.append(Vector3(cos(angle+0.12)*radii[side]*0.72,sin(angle+0.12)*radii[side]*0.72,0.48))
	var faces := []
	for side in 6:
		var next := (side+1)%6
		faces.append([Vector3(0.08,0.04,-1.0),front[side],front[next]])
		faces.append([front[side],back[side],back[next],front[next]])
		faces.append([back[side],Vector3(-0.04,-0.06,1.0),back[next]])
	return Geometry.mesh_from_faces(faces)

static func _ribbon_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5,0,-0.5),Vector3(0.5,0,-0.5),Vector3(-0.5,0,0.5),Vector3(0.5,0,0.5)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,1,3,2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
