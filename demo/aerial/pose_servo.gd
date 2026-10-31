extends RefCounted

# Critically damped control and powered-joint response, without ringing.
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
