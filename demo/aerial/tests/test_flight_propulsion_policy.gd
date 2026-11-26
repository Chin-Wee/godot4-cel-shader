extends SceneTree

const Flight = preload("res://aerial/flight_controller.gd")
const Poses = preload("res://aerial/poses/articulation_poses.gd")

func _initialize() -> void:
	var neutral := Poses.select(Vector3.ZERO,Vector3.ZERO,1.0,0.0)
	var partial := Poses.select(Vector3.ZERO,Vector3.ZERO,1.0,0.5)
	assert(partial[1].x>deg_to_rad(30.0),"Partial retrograde barely bends the knee")
	assert(absf(partial[0].z)>absf(neutral[0].z),"Partial retrograde does not widen the stance")
	for steer in [Vector3.ZERO,Vector3(0,1,0),Vector3(0,0,-1),Vector3(1,0,0)]:
		var brace := Poses.select(steer,Vector3.RIGHT,2.0,1.0)
		assert(brace[0].z>deg_to_rad(28.0) and brace[3].z<deg_to_rad(-28.0),"Steering overrides wide braking")
		assert(brace[1].x>=deg_to_rad(70.0) and brace[4].x>=deg_to_rad(70.0),"Steering overrides knee bracing")
	var travel := Vector3.FORWARD*40.0
	assert(Poses.retrograde_weight(travel,Vector3.BACK*98100.0,Vector3.ZERO,98100.0,false)>0.99)
	assert(Poses.retrograde_weight(travel,Vector3.FORWARD*98100.0,Vector3.ZERO,98100.0,false)==0.0)
	assert(Poses.retrograde_weight(travel,Vector3.ZERO,Vector3.BACK*98100.0,98100.0,true)>0.99)
	assert(Poses.retrograde_weight(travel,Vector3.ZERO,Vector3.BACK*98100.0,98100.0,false)==0.0)
	assert(Poses.retrograde_weight(Vector3.ZERO,Vector3.BACK*98100.0,Vector3.ZERO,98100.0,true)==0.0)
	var hot = Flight.Valve.new(Flight.HOT_IGNITION,Flight.HOT_RESTART,Flight.HOT_RESPONSE,Flight.HOT_RESPONSE,Flight.HOT_MINIMUM_ON)
	var cold = Flight.Valve.new()
	hot.reset(0.2)
	cold.reset(0.2)
	hot.step(1.0,1.0/60.0)
	cold.step(1.0,1.0/60.0)
	assert(hot.level-0.2<=1.0/60.0/Flight.HOT_RESPONSE+0.000001)
	assert(cold.level>hot.level,"Cold jets lost fast response")
	var fc = Flight.new()
	assert(fc._cold_trim_axis(0,0.03,0.02,1.0/60.0)>0.0)
	for i in 12:
		assert(fc._cold_trim_axis(0,-0.03,0.02,1.0/60.0)==0.0)
		assert(fc._cold_trim_axis(0,0.03,0.02,1.0/60.0)>0.0)
	for i in 5: assert(fc._cold_trim_axis(0,-0.03,0.02,1.0/60.0)==0.0)
	assert(fc._cold_trim_axis(0,-0.03,0.02,0.02)<0.0,"Persistent correction suppressed")
	assert(fc._cold_trim_axis(0,0.1,0.02,1.0/60.0)>0.0,"Strong arrest delayed")
	assert(fc._cold_trim_axis(0,0.005,0.02,1.0/60.0)==0.0)
	print("Flight propulsion policy checks passed: brace, projected reverse force, pressure slew and cold reversal hysteresis.")
	quit()
