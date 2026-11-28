extends SceneTree

const Articulation = preload("res://aerial/poses/articulation_poses.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var neutral := Articulation.select(Vector3.ZERO,Vector3.ZERO,1.0,0.0)
	var pitch := Articulation.select(Vector3(0.8,0,0),Vector3.ZERO,1.0,0.0)
	var yaw := Articulation.select(Vector3(0,0.8,0),Vector3.ZERO,1.0,0.0)
	var roll := Articulation.select(Vector3(0,0,0.8),Vector3.ZERO,1.0,0.0)
	var combined := Articulation.select(Vector3(0.8,0.7,-0.6),Vector3.ZERO,1.0,0.0)
	assert(_distance(combined,pitch)>0.02,"Combined composition discarded yaw or roll")
	assert(_distance(combined,yaw)>0.02,"Combined composition discarded pitch or roll")
	assert(_distance(combined,roll)>0.02,"Combined composition discarded pitch or yaw")
	assert(_distance(pitch,neutral)>0.02 and _distance(yaw,neutral)>0.02 and _distance(roll,neutral)>0.02,
		"An individual rotational axis produced no articulation")

	var coast := Articulation.select(Vector3.ZERO,Vector3.ZERO,0.0,0.0)
	var unpowered_yaw := Articulation.select(Vector3(0,0.8,0),Vector3.ZERO,0.0,0.0)
	assert(_distance(coast,unpowered_yaw)>0.02,"Engine cutoff disabled rotational articulation")

	var lateral_right := Articulation.select(Vector3.ZERO,Vector3(1,0,0),1.0,0.0)
	var lateral_left := Articulation.select(Vector3.ZERO,Vector3(-1,0,0),1.0,0.0)
	var ascent := Articulation.select(Vector3.ZERO,Vector3(0,1,0),1.0,0.0)
	var descent := Articulation.select(Vector3.ZERO,Vector3(0,-1,0),1.0,0.0)
	var forward := Articulation.select(Vector3.ZERO,Vector3(0,0,1),1.0,0.0)
	var backward := Articulation.select(Vector3.ZERO,Vector3(0,0,-1),1.0,0.0)
	for pose in [lateral_right,lateral_left,ascent,descent,forward,backward]:
		assert(_distance(pose,neutral)>0.02,"A translation direction produced no authored response")
	assert(_distance(ascent,descent)>0.02,"Vertical descent reused the ascent/braking silhouette")
	assert(_distance(forward,backward)>0.02,"Forward and reverse boost collapsed into one silhouette")

	var hover := Articulation.select(Vector3.ZERO,Vector3.ZERO,1.0,0.0,1.0)
	var hover_pitch := Articulation.select(Vector3(0.8,0,0),Vector3.ZERO,1.0,0.0,1.0)
	assert(_distance(hover_pitch,hover)>0.02,"Hover base suppressed directional articulation")
	var braced_yaw := Articulation.select(Vector3(0,0.8,0),Vector3.ZERO,1.0,0.8)
	assert(_distance(braced_yaw,yaw)>0.02,"Structural bracing did not contribute to the composed pose")

	# Torso composition must preserve yaw and lateral translation over the
	# coast base. These are independent requests, not mutually exclusive poses.
	var coast_base := Articulation.torso_target(_torso_frame())
	var coast_yaw := Articulation.torso_target(_torso_frame(Vector3(0,0.8,0)))
	var coast_lateral := Articulation.torso_target(_torso_frame(Vector3.ZERO,Vector3(1,0,0)))
	var coast_combined := Articulation.torso_target(_torso_frame(Vector3(0,0.8,0),Vector3(1,0,0)))
	assert(coast_yaw.z < -0.08 and absf(coast_yaw.z-coast_base.z)>0.08,
		"Coast base suppressed yaw counter-lean")
	assert(coast_lateral.z > 0.08 and absf(coast_lateral.z-coast_base.z)>0.08,
		"Lateral translation did not lean the torso")
	assert(_torso_distance(coast_combined,coast_yaw)>0.02 and _torso_distance(coast_combined,coast_lateral)>0.02,
		"Combined yaw and lateral translation collapsed into one torso pose")

	for intensity_step in 11:
		var intensity := float(intensity_step)/10.0
		var pose := Articulation.select(Vector3(intensity,intensity*0.7,-intensity*0.5),
			Vector3(intensity*0.4,-intensity*0.2,intensity*0.3),1.0,intensity*0.5,intensity*0.7)
		for angle in pose:
			assert(angle.is_finite(),"Quaternion composition produced a non-finite joint target")

	print("Flight pose composition checks passed: six translation directions, three independent rotation axes, unpowered articulation, hover base, torso yaw/translation overlay and common-mode bracing.")
	quit()

func _torso_frame(steer := Vector3.ZERO, reach := Vector3.ZERO) -> Dictionary:
	return {"steer":steer,"reach":reach,"drive":0.0,"coast":1.0,
		"retro":0.0,"flare":0.0,"land":0.0,"back":0.0,"belly":0.0}

func _torso_distance(a: Vector3, b: Vector3) -> float:
	var qa := Basis.from_euler(a).get_rotation_quaternion()
	var qb := Basis.from_euler(b).get_rotation_quaternion()
	return qa.angle_to(qb)

func _distance(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var total := 0.0
	for joint in mini(a.size(),b.size()):
		var qa := Basis.from_euler(a[joint]).get_rotation_quaternion()
		var qb := Basis.from_euler(b[joint]).get_rotation_quaternion()
		total += qa.angle_to(qb)
	return total
