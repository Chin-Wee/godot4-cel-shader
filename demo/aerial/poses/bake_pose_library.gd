extends SceneTree

# Authoring fixture, not a movement controller. Sample the real procedural rig
# on a frozen chassis, then export ordinary Godot AnimationPlayer clips.
const Mech = preload("res://aerial/aerial_mech.gd")
const OUTPUT := "res://aerial/poses/flight_pose_keys.tres"
const KEYS := {
	"Ready_Coil":{"land":1.0,"compression":0.3},
	"Launch_Push":{"hover":1.0,"launch":1.0},
	"Hover_Catch":{"hover":1.0,"compression":0.45,"acceleration":Vector3(0,12,0)},
	"Hover_Support":{"hover":1.0,"trim":Vector3(0.35,0.6,-0.3)},
	"Flight_Pierce":{"fighter":1.0,"track":1.0,"steer":Vector3(-0.45,0,0)},
	"Flight_Sustain":{"fighter":1.0,"track":1.0},
	"Bank_Left":{"fighter":1.0,"track":1.0,"steer":Vector3(-0.15,0,1)},
	"Bank_Right":{"fighter":1.0,"track":1.0,"steer":Vector3(-0.15,0,-1)},
	"Coast_Gather":{"coast":1.0,"steer":Vector3(0,0.25,0.7)},
	"Coast_Arrest":{"coast":1.0,"steer":Vector3(-0.25,-0.4,-1)},
	"Coast_Settle":{"coast":1.0},
	"Fall_Box":{"fall":1.0,"box":1.0,"pressure":1.0,"flow":Vector3(0,0,-1)},
	"Fall_Turn_Left":{"fall":1.0,"box":1.0,"pressure":1.0,"flow":Vector3(0,0,-1),"steer":Vector3(0,1,0.25)},
	"Fall_Turn_Right":{"fall":1.0,"box":1.0,"pressure":1.0,"flow":Vector3(0,0,-1),"steer":Vector3(0,-1,-0.25)},
	"Track":{"fall":1.0,"track":1.0,"pressure":1.0,"flow":Vector3(0,-1,0)},
	"Brake_Flare":{"coast":1.0,"brake":1.0,"steer":Vector3(0.4,0,0)},
	"Retro_Brace":{"coast":1.0,"retro":1.0,"acceleration":Vector3(0,0,14)},
	"Landing_Guard":{"land":1.0},
	"Landing_Absorb":{"land":1.0,"compression":1.1,"g_load":4.0},
}
const STUDIES := {
	"Launch":[[0.0,"Ready_Coil"],[0.25,"Ready_Coil"],[0.55,"Launch_Push"],[0.90,"Hover_Catch"],[1.4,"Hover_Support"],[2.0,"Hover_Support"]],
	"Forward_Flight":[[0.0,"Hover_Support"],[1.2,"Flight_Pierce"],[1.6,"Flight_Sustain"],[2.0,"Bank_Left"],[2.7,"Flight_Sustain"],[3.1,"Bank_Right"],[3.8,"Flight_Sustain"]],
	"Brake_And_Retro":[[0.0,"Flight_Sustain"],[0.18,"Flight_Pierce"],[1.5,"Brake_Flare"],[1.8,"Brake_Flare"],[2.5,"Retro_Brace"],[2.8,"Retro_Brace"],[3.4,"Coast_Gather"]],
	"Coast_And_Arrest":[[0.0,"Hover_Support"],[0.8,"Coast_Gather"],[1.15,"Coast_Gather"],[1.45,"Coast_Arrest"],[1.9,"Coast_Settle"],[2.2,"Coast_Settle"]],
	"Skydive":[[0.0,"Track"],[0.9,"Fall_Box"],[1.4,"Fall_Turn_Left"],[1.85,"Fall_Box"],[2.3,"Fall_Turn_Right"],[3.5,"Brake_Flare"],[4.7,"Fall_Box"],[5.7,"Track"]],
	"Landing":[[0.0,"Landing_Guard"],[0.25,"Landing_Guard"],[0.36,"Landing_Absorb"],[0.55,"Landing_Absorb"],[0.95,"Ready_Coil"],[1.4,"Hover_Support"]],
}

func _initialize() -> void: call_deferred("_bake")

func _bake() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var mech := Mech.new()
	stage.add_child(mech)
	var surface := ShaderMaterial.new()
	surface.shader = load("res://shaders/aerial/aircraft.gdshader")
	var exhaust := ShaderMaterial.new()
	exhaust.shader = load("res://shaders/aerial/afterburner.gdshader")
	mech.build(surface,exhaust)
	mech.freeze = true
	var sk := mech.skeleton
	var rig := mech.rig
	var samples := {}
	for name in KEYS:
		rig.reset()
		var frame := {"hover":0.0,"fighter":0.0,"coast":0.0,"fall":0.0,"land":0.0,"launch":0.0,
			"box":0.0,"track":0.0,"brake":0.0,"retro":0.0,"compression":0.0,"g_load":1.0,
			"side_load":0.0,"brake_rate":0.0,"roll_stop":0.0,"pressure":0.0,
			"drive":0.0,"prepare":0.0,"lead":1.0,"asymmetry":0.0,"load_direction":Vector3.ZERO,
			"steer":Vector3.ZERO,"body_steer":Vector3.ZERO,"flow":Vector3.ZERO,"gyro":Vector3.ZERO,
			"trim":Vector3.ZERO,"up":Vector3.UP,"omega":Vector3.ZERO,"alpha":Vector3.ZERO,"acceleration":Vector3.ZERO}
		frame.merge(KEYS[name],true)
		frame["pitch"] = frame.steer.x
		frame["yaw"] = frame.steer.y
		frame["roll"] = frame.steer.z
		frame["body_steer"] = Basis(Vector3.RIGHT,PI/2)*frame.steer if frame.fighter>0 else frame.steer
		frame["spread"] = maxf(frame.box,frame.brake)
		frame["stream"] = frame.track
		rig.motion = frame
		var available: float = 1-frame.land
		var spread: float = frame.spread*available
		var flight: float = frame.track*(available-spread)
		var hover: float = frame.hover*(available-spread-flight)
		rig.posture_weights = PackedFloat32Array([hover,flight,spread,available-spread-flight-hover,frame.land])
		# Fixed-time settle removes simulation history from each authored key.
		for tick in 120:
			rig._update_body(1.0/60)
			rig._update_legs(1.0/60,mech.controller)
			rig.arms.update(1.0/60,frame)
			rig.contacts.pelvis.value = Vector3(0,-0.24*frame.land,0)
			sk.reset_bone_poses()
			rig.set_weight(1)
			mech.actor.rotation = rig.root_angles
			mech.actor.position = (-(Basis.from_euler(rig.root_angles)*Vector3(0,0.9,0))+rig.com.value+rig.contacts.pelvis.value)*mech.display_scale
			sk.advance(1.0/60)
		# SkeletonModifier3D evaluation is deferred to the scene update. Flush the
		# finished key before reading the completion cache, not the restored rest.
		for flush in 3:
			sk.reset_bone_poses()
			sk.advance(1.0/60)
			await process_frame
		var rotations := []
		for index in sk.get_bone_count():
			var parent := sk.get_bone_parent(index)
			var parent_pose: Transform3D = mech.bone_poses[parent] if parent>=0 else Transform3D.IDENTITY
			rotations.append((parent_pose.affine_inverse()*mech.bone_poses[index]).basis.get_rotation_quaternion().normalized())
		var attitude := _study_attitude(name)
		samples[name] = {"bones":rotations,"position":attitude*mech.actor.position,"rotation":attitude*mech.actor.quaternion}
	var library := AnimationLibrary.new()
	var skeleton_path: NodePath = mech.actor.get_path_to(sk)
	for name in KEYS: library.add_animation("K_"+name,_clip([[0.0,name],[0.8,name]],samples,sk,skeleton_path,""))
	for name in STUDIES: library.add_animation("M_"+name,_clip(STUDIES[name],samples,sk,skeleton_path,name))
	assert(library.get_animation_list().size()==25)
	assert(library.get_animation("K_Fall_Box").get_track_count()>15,"Pose export omitted the completed skeleton")
	assert(samples.Hover_Support.position.is_finite())
	assert(ResourceSaver.save(library,OUTPUT)==OK)
	print("Pose library baked: 19 full-body keys and 6 native AnimationPlayer motion studies.")
	stage.queue_free()
	await process_frame
	quit()

func _study_attitude(name: String) -> Quaternion:
	# Presentation attitude belongs only to this frozen-chassis authoring asset.
	# Gameplay gets the corresponding attitude from its physical controller.
	var flight := Quaternion(Vector3.RIGHT,-PI/2)
	match name:
		"Ready_Coil": return Quaternion(Vector3.RIGHT,deg_to_rad(-6))
		"Launch_Push": return Quaternion(Vector3.RIGHT,deg_to_rad(-8))
		"Hover_Catch": return Quaternion(Vector3.RIGHT,deg_to_rad(10))
		"Hover_Support": return Quaternion(Vector3.FORWARD,deg_to_rad(5))
		"Flight_Pierce": return Quaternion(Vector3.RIGHT,deg_to_rad(-75))
		"Flight_Sustain","Fall_Box": return flight
		"Bank_Left": return Quaternion(Vector3.BACK,deg_to_rad(25))*flight
		"Bank_Right": return Quaternion(Vector3.BACK,deg_to_rad(-25))*flight
		"Coast_Gather","Coast_Arrest","Coast_Settle": return Quaternion(Vector3.UP,deg_to_rad(20))*Quaternion(Vector3.RIGHT,deg_to_rad(-35))*Quaternion(Vector3.BACK,deg_to_rad(-35))
		"Fall_Turn_Left": return Quaternion(Vector3.UP,deg_to_rad(15))*Quaternion(Vector3.BACK,deg_to_rad(20))*flight
		"Fall_Turn_Right": return Quaternion(Vector3.UP,deg_to_rad(-15))*Quaternion(Vector3.BACK,deg_to_rad(-20))*flight
		"Track": return Quaternion(Vector3.RIGHT,deg_to_rad(-145))
		"Brake_Flare": return Quaternion(Vector3.RIGHT,deg_to_rad(-25))
		"Retro_Brace": return Quaternion(Vector3.BACK,deg_to_rad(15))*Quaternion(Vector3.RIGHT,deg_to_rad(12))
		"Landing_Guard": return Quaternion(Vector3.RIGHT,deg_to_rad(-8))
		"Landing_Absorb": return Quaternion(Vector3.RIGHT,deg_to_rad(-15))
	return Quaternion.IDENTITY

func _clip(timeline: Array, samples: Dictionary, sk: Skeleton3D, skeleton_path: NodePath, study: String) -> Animation:
	var animation := Animation.new()
	animation.length = timeline[-1][0]
	for index in sk.get_bone_count():
		var changing := false
		var rest := sk.get_bone_rest(index).basis.get_rotation_quaternion()
		for sample in samples.values(): changing = changing or sample.bones[index].angle_to(rest)>0.0001
		if not changing: continue
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track,NodePath(str(skeleton_path)+":"+sk.get_bone_name(index)))
		animation.track_set_interpolation_type(track,Animation.INTERPOLATION_CUBIC)
		var bone := sk.get_bone_name(index)
		var leg := "Thigh" in bone or "Knee" in bone or "Feet" in bone
		var offset := 0.0
		if not study.is_empty():
			if "Neck" in bone: offset = -0.06
			elif "Shoulder" in bone: offset = -0.04
			elif "Hands" in bone: offset = 0.02
			elif leg: offset = -0.04 if study=="Launch" else 0.07
			elif "Waist" in bone or "Pelvis" in bone: offset = 0.04
		for k in timeline.size():
			var key: Array = timeline[k]
			var time: float = key[0] if k==0 or k==timeline.size()-1 else key[0]+offset
			animation.rotation_track_insert_key(track,time,samples[key[1]].bones[index])
	for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D]:
		var track := animation.add_track(type)
		animation.track_set_path(track,NodePath("."))
		animation.track_set_interpolation_type(track,Animation.INTERPOLATION_CUBIC)
		for key in timeline:
			if type==Animation.TYPE_POSITION_3D: animation.position_track_insert_key(track,key[0],samples[key[1]].position)
			else: animation.rotation_track_insert_key(track,key[0],samples[key[1]].rotation)
	return animation
