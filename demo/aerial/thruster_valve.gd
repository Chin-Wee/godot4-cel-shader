extends RefCounted

# Finite valve/engine response, shared by hot and cold outlets. The returned
# average integrates thrust across ignition, ramp, shutdown and restart events.
# Star Citizen's per-thruster response is the production behavior reference.
var ignition_delay: float
var restart_delay: float
var rise_time: float
var fall_time: float
var minimum_on: float
var level := 0.0
var running := false
var ignition_remaining := 0.0
var restart_remaining := 0.0
var minimum_remaining := 0.0
var latched_request := 0.0

func _init(ignition := 0.008, restart := 0.03, rise := 0.012, fall := 0.014, minimum := 0.02) -> void:
	assert(ignition>0 and restart>0 and rise>0 and fall>0 and minimum>0)
	ignition_delay = ignition
	restart_delay = restart
	rise_time = rise
	fall_time = fall
	minimum_on = minimum

func reset(output := 0.0) -> void:
	level = clampf(output,0,1)
	running = level>0
	ignition_remaining = 0.0
	restart_remaining = 0.0
	minimum_remaining = 0.0
	latched_request = level

func step(request: float, dt: float) -> float:
	if dt<=0: return level
	request = clampf(request,0,1)
	var remaining := dt
	var impulse := 0.0
	# Constant input crosses at most ignition, minimum burn, decay and restart.
	for event in 8:
		if remaining<=0.000000001: break
		if not running and level<=0.000000001:
			if restart_remaining>0:
				var wait := minf(remaining,restart_remaining)
				restart_remaining = maxf(0.0,restart_remaining-wait)
				remaining -= wait
				continue
			if request<=0: break
			running = true
			ignition_remaining = ignition_delay
			minimum_remaining = minimum_on
			latched_request = request
		if running and ignition_remaining>0:
			var wait := minf(remaining,ignition_remaining)
			ignition_remaining = maxf(0.0,ignition_remaining-wait)
			remaining -= wait
			continue
		if running and request<=0 and minimum_remaining<=0.000000001:
			running = false
			restart_remaining = restart_delay
			continue
		var target := 0.0
		var duration := remaining
		if running:
			if request>0: latched_request = request
			target = latched_request if minimum_remaining>0 else request
			if request<=0 and minimum_remaining>0: duration = minf(duration,minimum_remaining)
			minimum_remaining = maxf(0.0,minimum_remaining-duration)
		else:
			duration = minf(duration,level*fall_time)
		var response := rise_time if target>level else fall_time
		var ramp := minf(duration,absf(target-level)*response)
		var next := move_toward(level,target,ramp/response)
		impulse += (level+next)*0.5*ramp+target*(duration-ramp)
		level = next
		remaining = maxf(0.0,remaining-duration)
	return impulse/dt

# Allocation predicts delivered impulse without advancing the real valve clock.
func preview(request: float, dt: float) -> float:
	var saved := [level,running,ignition_remaining,restart_remaining,minimum_remaining,latched_request]
	var output := step(request,dt)
	level = saved[0]
	running = saved[1]
	ignition_remaining = saved[2]
	restart_remaining = saved[3]
	minimum_remaining = saved[4]
	latched_request = saved[5]
	return output

func command_for(output: float, dt: float, minimum := 0.000001) -> float:
	var off := preview(0,dt)
	var low := minimum
	var high := 1.0
	for iteration in 14:
		var middle := (low+high)*0.5
		if preview(middle,dt)<output: low = middle
		else: high = middle
	var command := (low+high)*0.5
	return 0.0 if absf(off-output)<=absf(preview(command,dt)-output)+0.000001 else command
