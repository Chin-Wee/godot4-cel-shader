extends RefCounted

# Critical control response and underdamped presentation follow-through.
# Finite speed limits apply only to animation, never to body movement.
var value := Vector3.ZERO
var velocity := Vector3.ZERO

func step(target: Vector3, delta: float, tau: float, max_speed := INF) -> Vector3:
	if delta <= 0: return value
	var previous := value
	var omega := 2.0 / maxf(tau, 0.001)
	var change := value - target
	var impulse := (velocity + change * omega) * delta
	var decay := exp(-omega * delta)
	value = target + (change + impulse) * decay
	velocity = (velocity - impulse * omega) * decay
	if is_finite(max_speed):
		value = previous + (value - previous).limit_length(max_speed * delta)
		velocity = velocity.limit_length(max_speed)
	return value

func reset(target := Vector3.ZERO) -> void:
	value = target
	velocity = Vector3.ZERO

func follow(target: Vector3, delta: float, frequency: float, damping: float, max_speed: float) -> Vector3:
	# Exact underdamped oscillator for bounded presentation follow-through.
	# ponytail: no limb rigid bodies/collision; use PhysicalBoneSimulator3D if
	# articulated knockdowns become gameplay. This never integrates world motion.
	if delta <= 0: return value
	var previous := value
	var omega := TAU * maxf(frequency,0.01)
	var drag := clampf(damping,0.05,0.99)*omega
	var rate := sqrt(omega*omega-drag*drag)
	var phase := rate*delta
	var decay := exp(-drag*delta)
	var change := value-target
	value = target+decay*(change*cos(phase)+(velocity+drag*change)*sin(phase)/rate)
	velocity = decay*(velocity*cos(phase)-(drag*velocity+omega*omega*change)*sin(phase)/rate)
	value = previous+(value-previous).limit_length(max_speed*delta)
	velocity = velocity.limit_length(max_speed)
	return value
