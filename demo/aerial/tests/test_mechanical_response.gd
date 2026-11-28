extends SceneTree

const Response = preload("res://aerial/mechanical_response.gd")

func _initialize() -> void:
	call_deferred("_run")

func _sample() -> Dictionary:
	return {
		"local_acceleration":Vector3.ZERO,
		"local_jerk":Vector3.ZERO,
		"local_angular_acceleration":Vector3.ZERO,
		"g_load":1.0,"brake":0.0,"retro":0.0,"weight":98100.0,
		"motor_forces":[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO],
		"motor_ratings":[65000.0,65000.0,65000.0,65000.0,65000.0,65000.0],
		"pressure_scales":[1.0,1.0,1.0,1.0,1.0,1.0]
	}

func _run() -> void:
	var response := Response.new()
	var neutral := _sample()
	var frame: Dictionary
	for tick in 120:
		frame = response.step(neutral,1.0/60.0)
	var neutral_torso: Vector3 = frame.mechanical_torso
	var neutral_pelvis: Vector3 = frame.mechanical_pelvis
	assert(neutral_torso.length()<0.0001,"Neutral flight develops passive torso motion")
	assert(neutral_pelvis.length()<0.0001,"Neutral flight develops passive pelvis motion")
	assert(float(frame.mechanical_shock)<0.0001,"Neutral flight invents structural impacts")

	var torque_only := neutral.duplicate(true)
	torque_only["joint_moments"] = {"left_knee":Vector3(0.8,0.0,0.0)}
	var torque_response := Response.new()
	var torque_frame: Dictionary
	for tick in 18: torque_frame = torque_response.step(torque_only,1.0/60.0)
	var torque_legs: PackedVector3Array = torque_frame.mechanical_legs
	assert(torque_legs[1].x>torque_legs[4].x+0.005,"Joint moment does not load only its own knee assembly")

	var vertical := neutral.duplicate(true)
	vertical["local_acceleration"] = Vector3(0,29.43,0)
	vertical["g_load"] = 4.0
	var vertical_response := Response.new()
	var vertical_frame: Dictionary
	for tick in 36: vertical_frame = vertical_response.step(vertical,1.0/60.0)
	var vertical_legs: PackedVector3Array = vertical_frame.mechanical_legs
	assert(vertical_frame.mechanical_compression>0.02 and vertical_legs[1].x>neutral_frame.mechanical_legs[1].x+0.01,"Vertical G does not compress the loaded leg structure")

	var brake := neutral.duplicate(true)
	brake["g_load"] = 2.4
	brake["brake"] = 1.0
	brake["retro"] = 0.9
	brake["local_acceleration"] = Vector3(1.5,0.0,18.0)
	brake["local_jerk"] = Vector3(0.0,0.0,90.0)
	brake["local_angular_acceleration"] = Vector3(0.0,1.2,0.4)
	brake["motor_forces"] = [
		Vector3(0,60000,0),Vector3(0,36000,0),
		Vector3(0,48000,0),Vector3(0,18000,0),
		Vector3(0,30000,0),Vector3(0,12000,0)
	]
	brake["pressure_scales"] = [0.978,0.986,0.982,0.990,0.980,0.988]
	for tick in 18:
		frame = response.step(brake,1.0/60.0)
	var legs: PackedVector3Array = frame.mechanical_legs
	var arms: PackedVector4Array = frame.mechanical_arms
	assert(float(frame.mechanical_shock)>0.5,"Braking shock does not excite the structure")
	assert(legs[1].x>0.005 and legs[4].x>0.005,"Braking does not load both knee assemblies")
	assert(not is_equal_approx(legs[1].x,legs[4].x),"Left and right knees ignore asymmetric engine loading")
	assert(arms[0].distance_to(arms[1])>0.001,"Arms respond as one synchronised assembly")
	var loaded_torso: Vector3 = frame.mechanical_torso
	assert(loaded_torso.length()<0.08,"Torso response exceeds its structural envelope")

	for tick in 240:
		frame = response.step(neutral,1.0/60.0)
	var settled_torso: Vector3 = frame.mechanical_torso
	assert(settled_torso.length()<0.002,"Torso response does not settle after load release")
	var settled_legs: PackedVector3Array = frame.mechanical_legs
	assert(settled_legs[1].length()<0.003,"Knee response does not settle after load release")

	var at_30 := _clock_sample(brake,30)
	var at_60 := _clock_sample(brake,60)
	var at_120 := _clock_sample(brake,120)
	assert(at_30.distance_to(at_60)<0.003 and at_60.distance_to(at_120)<0.003,
		"Structural response changes materially with physics tick rate")
	print("Mechanical response checks passed: neutral stability, asymmetric braking, bounded recoil, settling and timestep consistency.")
	quit()

func _clock_sample(sample: Dictionary, hz: int) -> Vector3:
	var response := Response.new()
	var result: Dictionary
	for tick in int(hz*0.5):
		result = response.step(sample,1.0/float(hz))
	return result.mechanical_torso
