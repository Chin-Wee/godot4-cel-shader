extends SceneTree

const Explosion = preload("res://aerial/graphic_explosion.gd")

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	create_timer(10.0).timeout.connect(func(): quit(1))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/aerial/mesh-vfx.gdshader")
	material.set_shader_parameter("emission_strength",0.85)
	var burst := Explosion.new()
	root.add_child(burst)
	burst.build(material,material.duplicate(),material.duplicate())
	burst.set_process(false)
	burst.set_time(0.04)
	assert(burst.lobes[0].scale.length() > 0.0 and burst.lobes[8].scale == Vector3.ZERO,"Secondary smoke must follow the first flash")
	burst.set_time(0.1)
	var snap := burst.lobes[0].scale.x/burst.sizes[0]/(1.0+0.4*0.1/burst.duration)
	assert(snap > 0.7,"Primary burst still eases in too slowly")
	burst.set_time(0.25)
	var overshoot := burst.lobes[0].scale.x/burst.sizes[0]/(1.0+0.4*0.25/burst.duration)
	assert(overshoot > 1.05,"Primary burst lost its overshoot")
	burst.set_time(0.6)
	var settled := burst.lobes[0].scale.x/burst.sizes[0]/(1.0+0.4*0.6/burst.duration)
	assert(absf(settled-1.0) < 0.001,"Primary overshoot did not settle")
	var poses := []
	for lobe in burst.lobes: poses.append(lobe.transform)
	burst.set_time(0.03)
	var flash: float = burst.materials[0].get_shader_parameter("emission_strength")
	burst.set_time(0.6)
	assert(flash > burst.materials[0].get_shader_parameter("emission_strength")*1.5,"Initial energy flash has no punch")
	for index in poses.size(): assert(poses[index].is_equal_approx(burst.lobes[index].transform),"VFX depends on frame history instead of its clock")
	burst.set_time(0.05)
	var early_wave: float = burst.ring.scale.x
	burst.set_time(0.15)
	var early_speed: float = burst.ring.scale.x-early_wave
	burst.set_time(0.75)
	var late_wave: float = burst.ring.scale.x
	burst.set_time(0.85)
	assert(early_speed > (burst.ring.scale.x-late_wave)*3.0,"Shockwave lost its fast attack and slower tail")
	burst._process(5.0)
	await process_frame
	assert(not is_instance_valid(burst),"Juiced VFX no longer expires")
	print("VFX timing checks passed: flash, fast attack, overshoot/settle, delayed smoke, decelerating wave, deterministic seeking and expiry.")
	quit()
