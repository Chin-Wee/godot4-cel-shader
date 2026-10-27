extends SceneTree

const Trail = preload("res://aerial/position_trail.gd")
class Recorder extends Trail:
	var records: Array[Vector4] = []
	func emit_at(point: Vector3, birth_time: float) -> void:
		records.append(Vector4(point.x,point.y,point.z,birth_time))
		super.emit_at(point,birth_time)

func _initialize() -> void:
	call_deferred("_run")

func _material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/aerial/mesh-vfx.gdshader")
	return material

func _trail(style := Trail.SMOKE) -> Recorder:
	var trail := Recorder.new()
	root.add_child(trail)
	trail.set_process(false)
	trail.configure(_material(),style)
	return trail

func _run() -> void:
	create_timer(15.0).timeout.connect(func(): quit(1))
	assert(FileAccess.get_file_as_string("res://shaders/aerial/mesh-vfx.gdshader") == FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../src/aerial/mesh-vfx.gdshader")),"Runtime VFX shader drifted")
	var smoke := _trail()
	var mesh: ArrayMesh = smoke.multimesh.mesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert(vertices.size() == 72,"Trail core is not a bounded six-sided irregular prism")
	var normal_count := {}
	for index in range(0,vertices.size(),3):
		assert(normals[index].is_equal_approx(normals[index+1]) and normals[index].is_equal_approx(normals[index+2]),"Wedge triangles lost flat normals")
		assert((vertices[index+1]-vertices[index]).cross(vertices[index+2]-vertices[index]).length_squared() > 0.0001,"Degenerate wedge triangle")
		assert(normals[index].dot((vertices[index]+vertices[index+1]+vertices[index+2])/3.0) > 0.0,"Wedge normal points inward")
		normal_count[Vector3i((normals[index]*100).round())] = true
	assert(normal_count.size() > 8,"Smoke no longer contains separate lit facets")
	var tangent := Vector3(1,0.3,-2).normalized()
	for index in 20:
		var basis := Trail._rolled_basis(tangent,index)
		assert(absf(basis.z.dot(tangent)) > 0.99999,"Roll tilted the trail away from its trajectory")
		assert(basis.is_finite(),"Roll introduced non-finite geometry")
	assert(not Trail._rolled_basis(tangent,0).x.is_equal_approx(Trail._rolled_basis(tangent,1).x),"Trail roll still repeats exactly")
	assert(smoke.palette_materials().size() == 2 and smoke.vapor.multimesh.instance_count == Trail.CAPACITY,"Wide vapor layer is missing or unbounded")
	assert(smoke.vapor.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 4,"Vapor must use a lightweight path ribbon")
	var thin := _trail(Trail.THIN)
	var missile := _trail(Trail.MISSILE)
	assert(thin.palette_materials().size() == 1 and thin.vapor == null,"Thin contrail still uses smoke chunks")
	assert(thin.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 4,"Fine trail is not a ribbon")
	assert(missile.palette_materials().size() == 3 and missile.emissive_core != null,"Missile needs smoke, vapor and a separate emissive core")
	assert(missile.emissive_core.material_override.get_shader_parameter("emission_strength") > 1.0,"Missile core cannot feed HDR bloom")
	assert(missile.emissive_core.material_override.get_shader_parameter("lifetime") < missile.lifetime,"Missile glow must end before its smoke")
	assert(missile.material_override.get_shader_parameter("trail_smoke_delay") == 0.25 and missile.vapor.material_override.get_shader_parameter("trail_smoke_delay") == 0.25,"Missile opaque smoke covers its young HDR burn")
	assert(missile.emissive_core.material_override.get_shader_parameter("trail_smoke_delay") == 0.0,"Missile glow inherits the smoke delay")
	assert(smoke.material_override.get_shader_parameter("trail_smoke_delay") == 0.0,"Ordinary smoke gained a missile-only onset delay")
	for trail in [smoke,thin,missile]:
		for layer in trail._layers:
			assert(layer.multimesh.instance_count == Trail.CAPACITY,"Trail layer storage grew beyond capacity")
		trail.set_time(12.0)
		assert(trail.elapsed == 12.0)
		for material in trail.palette_materials(): assert(material.get_shader_parameter("effect_time") == 12.0,"A trail layer missed the pause clock")
	# Identical piecewise-linear path at 10 Hz versus 100 Hz: positions AND birth
	# times must agree, including the fractional distance carried across the corner.
	var coarse := _trail()
	var fine := _trail()
	_feed_path(coarse,10)
	_feed_path(fine,100)
	assert(coarse.records.size() == fine.records.size(),"Trail density depends on frame rate")
	for index in coarse.records.size():
		assert(coarse.records[index].is_equal_approx(fine.records[index]),"Sampling or age depends on frame rate")
		if index > 0:
			var a := Vector3(coarse.records[index-1].x,coarse.records[index-1].y,coarse.records[index-1].z)
			var b := Vector3(coarse.records[index].x,coarse.records[index].y,coarse.records[index].z)
			assert(a.distance_to(b) <= coarse.spacing+0.0001,"Fixed-distance trail left a gap")
	var samples: int = coarse.sample_count
	coarse.sample_position(Vector3(10000,0,0))
	assert(coarse.sample_count == samples and coarse.distance_since_sample == 0.0,"Teleport connected across the world")
	coarse.set_time(9.0)
	coarse.sample_position(Vector3(10003,0,0))
	assert(coarse.sample_count == samples+1,"Trail did not restart after teleport")
	var saved: Vector4 = fine.records[0]
	for index in 600:
		smoke.set_time(float(index)*0.1)
		smoke.sample_position(Vector3(float(index)*3.0,0,0))
	assert(smoke.sample_count > Trail.CAPACITY and smoke.next_slot == smoke.sample_count%Trail.CAPACITY,"Ring buffer did not wrap")
	assert(fine.records[0] == saved,"Emitted world history moved when a new point arrived")
	var shader := FileAccess.get_file_as_string("res://shaders/aerial/mesh-vfx.gdshader")
	assert("NORMAL = normalize(vec3(roll*NORMAL.xy/growth" in shader,"Age roll no longer rotates flat normals")
	assert("fade *= density" in shader and "bayer4x4(FRAGCOORD.xy)" in shader,"Vapor lost screen-door density")
	assert("inverse(mat3(MODEL_MATRIX))*(wind_velocity+curl*wind_curl)*seconds" in shader,"Oriented trail wind is no longer world-space")
	assert("age >= 1.0" in shader,"Expired trail samples are still visible")
	for trail in [smoke,thin,missile,coarse,fine]: trail.queue_free()
	await process_frame
	print("Faceted trail checks passed: flat prism normals, distance/time invariance, roll, bounded smoke/vapor/core/ribbon layers, clocks, expiry and teleport.")
	quit()

func _feed_path(trail: Recorder, rate: int) -> void:
	for index in rate*6+1:
		var time := float(index)/float(rate)
		trail.set_time(time)
		var point := Vector3(time*10.0,0,0) if time <= 3.0 else Vector3(30,0,(time-3.0)*10.0)
		trail.sample_position(point)
