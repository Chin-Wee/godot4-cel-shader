extends SceneTree

const Allocator = preload("res://aerial/thruster_allocator.gd")

func _port(point: Vector3, axis: Vector3, minimum := 0.0, maximum := 1.0) -> Dictionary:
	return {"basis":Basis.looking_at(axis,Vector3.UP if absf(axis.y)<0.9 else Vector3.BACK),
		"lever":point,"cone":0.0,"center":Vector3.ZERO,"gain":1.0,
		"minimum":minimum,"maximum":maximum,"off":minimum,"fuel":0.03}

func _initialize() -> void:
	# Same-point counter-jets add no useful moment. Even a redundant preferred
	# distribution must collapse to the single useful jet at unchanged net force.
	var ports := [_port(Vector3.ZERO,Vector3.RIGHT),_port(Vector3.ZERO,Vector3.LEFT)]
	var preferred := [Vector3.RIGHT*0.8,Vector3.LEFT*0.6]
	var plan := Allocator.solve(ports,Vector3.RIGHT*0.2,Vector3.ZERO,Vector3.ZERO,preferred,preferred)
	assert((plan[0]+plan[1]).distance_to(Vector3.RIGHT*0.2)<0.001)
	assert(plan[1].length()<0.0001,"Allocator retains cancelling counter-thrust")
	assert(plan[0].length()+plan[1].length()<0.201,"Allocator wastes fuel in its force null space")
	# Opposite forces at different lever arms are necessary for pure rotation.
	ports = [_port(Vector3.RIGHT,Vector3.UP),_port(Vector3.LEFT,Vector3.DOWN),
		_port(Vector3.RIGHT,Vector3.DOWN),_port(Vector3.LEFT,Vector3.UP)]
	preferred = [Vector3.UP*0.8,Vector3.DOWN*0.8,Vector3.DOWN*0.6,Vector3.UP*0.6]
	plan = Allocator.solve(ports,Vector3.ZERO,Vector3.BACK*0.4,Vector3.ZERO,preferred,preferred)
	var force := Vector3.ZERO
	var moment := Vector3.ZERO
	var fuel := 0.0
	for i in ports.size():
		force += plan[i]
		moment += ports[i].lever.cross(plan[i])
		fuel += plan[i].length()
	assert(force.length()<0.001 and moment.distance_to(Vector3.BACK*0.4)<0.001)
	assert(plan[0].length()>0.19 and plan[1].length()>0.19,"Fuel saving removed a necessary torque couple")
	assert(fuel<0.401,"Allocator retains opposing torque couples that cancel each other")
	# A closing valve cannot lose its real residual pressure instantly.
	ports = [_port(Vector3.ZERO,Vector3.RIGHT),_port(Vector3.ZERO,Vector3.LEFT,0.1,0.1)]
	plan = Allocator.solve(ports,Vector3.RIGHT*0.2,Vector3.ZERO,Vector3.ZERO,[],[])
	assert(plan[1].distance_to(Vector3.LEFT*0.1)<0.00001)
	assert((plan[0]+plan[1]).distance_to(Vector3.RIGHT*0.2)<0.001,"Fuel saving ignored unavoidable shutdown thrust")
	print("Thruster allocator checks passed: no redundant counter-thrust, preserved torque couples and real shutdown tails.")
	quit()
