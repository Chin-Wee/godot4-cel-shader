extends RefCounted

# Star Citizen's published placed-thruster model is the production reference.
# Reuse the controller's native 3x3 force/moment blocks. Forces are normalized by
# body weight and lever arms by model length. No body-state corrections occur.
# ponytail: bounded ADMM sweeps for this mech, not a general vehicle optimizer.
const SWEEPS := 64

static func angle(basis: Basis, force: Vector3, limit: float) -> Vector3:
	if force.is_zero_approx(): return Vector3.ZERO
	var local := basis.transposed()*-force.normalized()
	var axis := Vector3.BACK.cross(local).normalized()
	if axis.is_zero_approx(): axis = Vector3.RIGHT
	return axis*minf(acos(clampf(local.z,-1,1)),limit)

static func direction(basis: Basis, rotation: Vector3) -> Vector3:
	return -basis.z if rotation.is_zero_approx() else -(basis*Basis(Quaternion(rotation.normalized(),rotation.length()))).z

static func project(candidate: Vector3, port: Dictionary) -> Vector3:
	var target: Vector3 = ((angle(port.basis,candidate,port.cone)-port.center)/port.gain).limit_length(port.cone)
	var axis := direction(port.basis,(port.center+target*port.gain).limit_length(port.cone))
	var magnitude := clampf(candidate.dot(axis)-port.fuel,port.minimum,port.maximum)
	var on := axis*magnitude
	var off: Vector3 = axis*port.off
	return off if candidate.distance_squared_to(off)<=candidate.distance_squared_to(on)+2.0*port.fuel*(magnitude-port.off) else on

static func solve(ports: Array, force: Vector3, moment: Vector3, force_axis: Vector3, seed: Array, preferred: Array = [], sweeps := SWEEPS) -> Array[Vector3]:
	var n := ports.size()
	var weights: Array[float] = []
	var reference: Array[Vector3] = []
	for i in n:
		# Hot gimbals prepare for the horizon. Fixed cold jets must remain free
		# to shed cancelling flow rather than track a redundant distribution.
		var tracking := 0.25 if preferred.size()>=n and ports[i].cone>0 else 0.0
		weights.append(1.0/(1.0+tracking))
		reference.append(preferred[i]*(1.0-weights[i]) if tracking>0 else Vector3.ZERO)
	var zero := Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
	var force_inverse := Basis.IDENTITY/20000.0
	if not force_axis.is_zero_approx():
		for axis in 3: force_inverse[axis] += force_axis*force_axis[axis]*(1.0/3.0-1.0/20000.0)
	var a := force_inverse
	var coupling := zero
	var d := Basis.IDENTITY/3000.0
	for i in n:
		var port: Dictionary = ports[i]
		var r: Vector3 = port.lever
		# Fixed RCS ports have one pressure degree of freedom, not three force
		# axes. Include that constraint in the small matrix instead of asking
		# projection sweeps to repeatedly remove impossible lateral forces.
		var axis_direction: Vector3 = -port.basis.z
		var free: bool = port.cone>0
		var enabled: bool = port.maximum>0.0000001 or port.off>0.0000001
		for axis in 3:
			var unit := Vector3.ZERO
			unit[axis] = 1
			var linear: Vector3 = unit if free else axis_direction*axis_direction[axis]
			var angular := unit.cross(r)
			if not free: angular = axis_direction*axis_direction.dot(angular)
			if enabled:
				a[axis] += linear*weights[i]
				coupling[axis] += r.cross(linear)*weights[i]
				d[axis] += r.cross(angular)*weights[i]
	var inverse_a := a.inverse()
	var schur := d
	for axis in 3: schur[axis] -= coupling*inverse_a*coupling.transposed()[axis]
	var inverse_s := schur.inverse()
	var z: Array[Vector3] = []
	var dual: Array[Vector3] = []
	for i in n:
		z.append(project(seed[i] if i<seed.size() else Vector3.ZERO,ports[i]))
		dual.append(Vector3.ZERO)
	for sweep in sweeps:
		var ef := force
		var em := moment
		for i in n:
			var v: Vector3 = (z[i]-dual[i])*weights[i]+reference[i]
			ef -= v
			em -= ports[i].lever.cross(v)
		var angular: Vector3 = inverse_s*(em-coupling*inverse_a*ef)
		var linear: Vector3 = inverse_a*(ef-coupling.transposed()*angular)
		for i in n:
			var v: Vector3 = (z[i]-dual[i])*weights[i]+reference[i]
			var correction: Vector3 = linear+angular.cross(ports[i].lever)
			if ports[i].cone==0:
				var axis: Vector3 = -ports[i].basis.z
				correction = axis*axis.dot(correction)
			if ports[i].maximum<=0.0000001 and ports[i].off<=0.0000001: correction = Vector3.ZERO
			var x: Vector3 = v+correction*weights[i]
			var next := project(x+dual[i],ports[i])
			dual[i] += x-next
			z[i] = next
	return z
