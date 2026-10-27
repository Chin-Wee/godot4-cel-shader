extends SceneTree

const Explosion = preload("res://aerial/graphic_explosion.gd")

func _initialize() -> void: call_deferred("_run")

func _burst(seed_value: int) -> Node3D:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/aerial/mesh-vfx.gdshader")
	material.set_shader_parameter("emission_strength",0.85)
	var burst := Explosion.new()
	root.add_child(burst)
	burst.build(material,material.duplicate(),material.duplicate(),seed_value)
	burst.set_process(false)
	return burst

func _run() -> void:
	create_timer(15.0).timeout.connect(func(): quit(1))
	var burst = _burst(325)
	var repeat = _burst(325)
	var alternate = _burst(326)
	assert(burst.lobes.size() == 20 and burst.accents.size() == 12 and burst.debris.size() == 6)
	assert(burst.get_child_count() <= 40,"Explosion storage is unbounded")
	for child in burst.get_children(): assert(not child.mesh is TorusMesh,"Explosion contains a long-lived graphic ring")
	var births := {}
	var lifetimes := {}
	for state in burst.particles:
		births[state.birth] = true
		lifetimes[state.life] = true
	assert(births.size() > 10 and lifetimes.size() > 20,"Explosion components are synchronized again")
	# Drag slows an outward launch toward its terminal flow without a tween recoil.
	var early := Explosion.transport(Vector3(40,0,0),Vector3.ZERO,3.0,0.2)
	var middle := Explosion.transport(Vector3(40,0,0),Vector3.ZERO,3.0,0.4)
	var late := Explosion.transport(Vector3(40,0,0),Vector3.ZERO,3.0,0.6)
	assert(early.x < middle.x and middle.x < late.x and (middle-early).length() > (late-middle).length(),"Blast motion is not a decelerating launch")
	burst.set_time(0.35)
	repeat.set_time(0.35)
	alternate.set_time(0.35)
	var distinct := false
	var transforms := []
	for index in burst.particles.size():
		var node: MeshInstance3D = burst.particles[index].node
		transforms.append(node.transform)
		assert(node.transform.is_finite() and node.transform.is_equal_approx(repeat.particles[index].node.transform),"Fixed-seed VFX is not reproducible")
		distinct = distinct or not node.transform.is_equal_approx(alternate.particles[index].node.transform)
	assert(distinct,"Every explosion repeats the same choreography")
	burst.set_time(2.5)
	burst.set_time(0.35)
	for index in transforms.size(): assert(transforms[index].is_equal_approx(burst.particles[index].node.transform),"Seeking changes particle trajectories")
	burst.set_time(0.03)
	var flash: float = burst.materials[0].get_shader_parameter("emission_strength")
	burst.set_time(0.3)
	assert(flash > burst.materials[0].get_shader_parameter("emission_strength")*2.0,"Flash does not cool rapidly")
	var falling: Dictionary = burst.particles[-1]
	var before: Vector3 = Explosion.transport(falling.velocity,falling.terminal,falling.drag,0.2)
	var center: Vector3 = Explosion.transport(falling.velocity,falling.terminal,falling.drag,0.3)
	var after: Vector3 = Explosion.transport(falling.velocity,falling.terminal,falling.drag,0.4)
	assert((after-center).y < (center-before).y,"Debris does not arc under gravity")
	burst.set_time(0.8)
	var smoke_height := 0.0
	for node in burst.lobes.slice(8): smoke_height += node.position.y
	burst.set_time(1.8)
	for node in burst.lobes.slice(0,8): assert(not node.visible,"Fire lasts as long as the smoke")
	for node in burst.accents: assert(not node.visible,"Sparks remain as frozen graphic ornaments")
	var risen := 0.0
	for node in burst.lobes.slice(8): risen += node.position.y
	assert(risen > smoke_height and burst.lobes[8].visible,"Smoke does not rise after the flash")
	var count: int = burst.get_child_count()
	for frame in 100: burst.set_time(float(frame)*0.04)
	assert(burst.get_child_count() == count,"Playback allocates more mesh particles")
	var end: float = burst.duration
	burst._process(end+1.0)
	await process_frame
	assert(not is_instance_valid(burst),"Explosion no longer expires")
	repeat.queue_free()
	alternate.queue_free()
	await process_frame
	print("Explosion checks passed: independent births/cooling, drag, gravity, buoyancy, seed variation, deterministic seeking, bounded storage and expiry.")
	quit()
