extends SceneTree

# Authoring fixture, not a movement controller. Sample the real procedural rig
# on a frozen chassis, then export ordinary Godot AnimationPlayer clips.
const Mech = preload("res://aerial/aerial_mech.gd")
const PoseSheet = preload("res://aerial/poses/flight_pose_sheet.gd")
const OUTPUT := "res://aerial/poses/flight_pose_keys.tres"
const KEYS := {
	"Ready_Coil":{"land":1.0,"compression":0.3,"feet":Vector2.ZERO,"body_shift":Vector3(0,0,0.14)},
	"Launch_Push":{"hover":1.0,"launch":1.0},
	"Hover_Catch":{"hover":1.0,"compression":0.45,"acceleration":Vector3(0,12,0)},
	"Hover_Support":{"hover":1.0,"trim":Vector3(0.35,0.6,-0.3)},
	"Hover_Left":{"hover":1.0,"move_intent":Vector3.RIGHT},
	"Hover_Right":{"hover":1.0,"move_intent":Vector3.LEFT},
	"Hover_Forward":{"hover":1.0,"move_intent":Vector3.BACK},
	"Hover_Back":{"hover":1.0,"move_intent":Vector3.FORWARD},
	"Flight_Pierce":{"fighter":1.0,"track":1.0,"steer":Vector3(-0.45,0,0)},
	"Flight_Sustain":{"fighter":1.0,"track":1.0},
	"Bank_Left":{"bank_gesture":1.0,"fighter":1.0,"track":1.0,"steer":Vector3(-0.15,0,1)},
	"Bank_Right":{"bank_gesture":-1.0,"fighter":1.0,"track":1.0,"steer":Vector3(-0.15,0,-1)},
	"Bank_Pull_Left":{"bank_gesture":1.0,"fighter":1.0,"track":1.0,"steer":Vector3(0.65,0,0.45)},
	"Bank_Pull_Right":{"bank_gesture":-1.0,"fighter":1.0,"track":1.0,"steer":Vector3(0.65,0,-0.45)},
	"Coast_Gather":{"coast":1.0,"steer":Vector3(0,0.25,0.7)},
	"Coast_Arrest":{"coast":1.0,"steer":Vector3(-0.25,-0.4,-1)},
	"Coast_Settle":{"coast":1.0},
	"Fall_Box":{"fall":1.0,"box":1.0,"pressure":1.0,"flow":Vector3(0,0,-1)},
	"Fall_Turn_Left":{"fall":1.0,"box":1.0,"pressure":1.0,"flow":Vector3(0,0,-1),"steer":Vector3(0,1,0.25)},
	"Fall_Turn_Right":{"fall":1.0,"box":1.0,"pressure":1.0,"flow":Vector3(0,0,-1),"steer":Vector3(0,-1,-0.25)},
	"Track":{"fall":1.0,"track":1.0,"pressure":1.0,"flow":Vector3(0,-1,0)},
	"Brake_Flare":{"coast":1.0,"brake":1.0,"steer":Vector3(0.4,0,0)},
	"Retro_Brace":{"coast":1.0,"retro":1.0,"acceleration":Vector3(0,0,14)},
	"Front_Swing":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(-1,0),"flip_degrees":25},
	"Front_Inversion":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(-1,0),"flip_degrees":180},
	"Front_Opening":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(-1,0),"flip_degrees":310},
	"Back_Swing":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(1,0),"flip_degrees":25},
	"Back_Inversion":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(1,0),"flip_degrees":180},
	"Back_Opening":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(1,0),"flip_degrees":310},
	"Roll_Initiate":{"coast":1.0,"acro":Vector2(0,1),"acro_sign":Vector2(0,1),"roll_degrees":55},
	"Roll_Corkscrew":{"coast":1.0,"acro":Vector2(0,1),"acro_sign":Vector2(0,1),"roll_degrees":180},
	"Roll_Open":{"coast":1.0,"acro":Vector2(0,1),"acro_sign":Vector2(0,1),"roll_degrees":310},
	"Back_Fall":{"fall":1.0,"box":1.0,"back":1.0,"pressure":1.0,"flow":Vector3(0,0,1)},
	"Front_Layout_Swing":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(-1,0),"layout":1.0,"flip_degrees":25},
	"Front_Layout_Inversion":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(-1,0),"layout":1.0,"flip_degrees":180},
	"Front_Layout_Opening":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(-1,0),"layout":1.0,"flip_degrees":310},
	"Back_Layout_Swing":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(1,0),"layout":1.0,"flip_degrees":25},
	"Back_Layout_Inversion":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(1,0),"layout":1.0,"flip_degrees":180},
	"Back_Layout_Opening":{"coast":1.0,"acro":Vector2(1,0),"acro_sign":Vector2(1,0),"layout":1.0,"flip_degrees":310},
	"Head_Look_Left":{"hover":1.0,"look_weight":1.0,"look_angles":Vector3(0,0.65,0)},
	"Head_Look_Right":{"hover":1.0,"look_weight":1.0,"look_angles":Vector3(0,-0.65,0)},
	"Head_Look_Up":{"hover":1.0,"look_weight":1.0,"look_angles":Vector3(-0.70,0,0)},
	"Head_Look_Down":{"hover":1.0,"look_weight":1.0,"look_angles":Vector3(0.40,0,0)},
	"Landing_Guard":{"land":1.0,"feet":Vector2(5,5),"body_shift":Vector3(0,0,0.14)},
	"Landing_Absorb":{"land":1.0,"compression":1.1,"g_load":4.0,"feet":Vector2.ZERO,"pelvis_drop":0.19,"body_shift":Vector3(0,0,0.18)},
}
const STUDIES := {
	"Launch":[[0.0,"Ready_Coil"],[0.25,"Ready_Coil"],[0.55,"Launch_Push"],[0.90,"Hover_Catch"],[1.4,"Hover_Support"],[2.0,"Hover_Support"]],
	"Forward_Flight":[[0.0,"Hover_Support"],[1.2,"Flight_Pierce"],[1.6,"Flight_Sustain"],[2.0,"Bank_Left"],[2.7,"Flight_Sustain"],[3.1,"Bank_Right"],[3.8,"Flight_Sustain"]],
	"Brake_And_Retro":[[0.0,"Flight_Sustain"],[0.18,"Flight_Pierce"],[1.5,"Brake_Flare"],[1.8,"Brake_Flare"],[2.5,"Retro_Brace"],[2.8,"Retro_Brace"],[3.4,"Coast_Gather"]],
	"Coast_And_Arrest":[[0.0,"Hover_Support"],[0.8,"Coast_Gather"],[1.15,"Coast_Gather"],[1.45,"Coast_Arrest"],[1.9,"Coast_Settle"],[2.2,"Coast_Settle"]],
	"Skydive":[[0.0,"Track"],[0.9,"Fall_Box"],[1.4,"Fall_Turn_Left"],[1.85,"Fall_Box"],[2.3,"Fall_Turn_Right"],[3.5,"Brake_Flare"],[4.7,"Fall_Box"],[5.7,"Track"]],
	"Landing":[[0.0,"Landing_Guard"],[0.25,"Landing_Guard"],[0.36,"Landing_Absorb"],[0.55,"Landing_Absorb"],[0.95,"Ready_Coil"],[1.4,"Hover_Support"]],
	"Front_Flip":[[0.0,"Hover_Support"],[0.35,"Front_Swing"],[1.5,"Front_Inversion"],[2.6,"Front_Opening"],[2.9,"Front_Arrest"],[3.2,"Hover_Support"]],
	"Back_Flip":[[0.0,"Hover_Support"],[0.35,"Back_Swing"],[1.5,"Back_Inversion"],[2.6,"Back_Opening"],[2.9,"Back_Arrest"],[3.2,"Hover_Support"]],
	"Dynamic_Roll":[[0.0,"Flight_Sustain"],[0.8,"Roll_Initiate"],[2.6,"Roll_Corkscrew"],[4.6,"Roll_Open"],[5.0,"Roll_Left_Arrest"],[5.4,"Flight_Sustain"]],
	"Belly_Back_Recovery":[[0.0,"Fall_Box"],[1.3,"Back_Fall"],[2.6,"Fall_Box"],[3.7,"Track"]],
	"Extended_Layouts":[[0.0,"Hover_Support"],[0.35,"Front_Layout_Swing"],[1.5,"Front_Layout_Inversion"],[2.6,"Front_Layout_Opening"],[3.2,"Hover_Support"],[3.55,"Back_Layout_Swing"],[4.7,"Back_Layout_Inversion"],[5.8,"Back_Layout_Opening"],[6.4,"Hover_Support"]],
	"Head_Scan":[[0.0,"Hover_Support"],[0.6,"Head_Look_Left"],[1.5,"Head_Look_Right"],[2.4,"Head_Look_Up"],[3.3,"Head_Look_Down"],[4.2,"Hover_Support"]],
	"Horizontal_Slides":[[0.0,"Hover_Support"],[0.6,"Hover_Left"],[1.3,"Hover_Right"],[2.0,"Hover_Forward"],[2.7,"Hover_Back"],[3.5,"Hover_Support"]],
	"Bank_And_Pull":[[0.0,"Flight_Sustain"],[0.5,"Bank_Left"],[1.2,"Bank_Pull_Left"],[2.1,"Bank_Right"],[2.8,"Bank_Pull_Right"],[3.6,"Flight_Sustain"]],
}

func _initialize() -> void: call_deferred("_bake")

func _bake() -> void:
	var keys := KEYS.duplicate()
	var studies := STUDIES.duplicate()
	keys.merge(PoseSheet.KEYS)
	studies.merge(PoseSheet.STUDIES)
	PoseSheet.add_directional_variants(keys,studies)
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
	for name in keys:
		rig.reset()
		var key: Dictionary = keys[name]
		var frame := {"hover":0.0,"fighter":0.0,"coast":0.0,"fall":0.0,"land":0.0,"launch":0.0,
			"belly":0.0,"back":0.0,"air_control":0.0,"layout":0.0,"look_angles":Vector3.ZERO,"look_weight":0.0,
			"box":0.0,"track":0.0,"brake":0.0,"retro":0.0,"compression":0.0,"g_load":1.0,
			"side_load":0.0,"brake_rate":0.0,"brake_turn":Vector3.ZERO,"roll_stop":0.0,"pressure":0.0,
			"drive":0.0,"prepare":0.0,"lead":1.0,"asymmetry":0.0,"load_direction":Vector3.ZERO,"flare":0.0,
			"steer":Vector3.ZERO,"body_steer":Vector3.ZERO,"flow":Vector3.ZERO,"gyro":Vector3.ZERO,
			"acro":Vector2.ZERO,"acro_sign":Vector2.ZERO,"acro_recovery":Vector2.ZERO,"flip_shape":Vector3.ZERO,"roll_shape":Vector3.ZERO,
			"reach":Vector3.ZERO,"gather":Vector2.ZERO,"move_intent":Vector3.ZERO,"translate":Vector3.ZERO,
			"trim":Vector3.ZERO,"up":Vector3.UP,"omega":Vector3.ZERO,"alpha":Vector3.ZERO,"acceleration":Vector3.ZERO}
		frame.merge(key,true)
		var attitude := _study_attitude(name,key)
		mech.controller.thrust_level = key.get("thrust",1.0)
		frame.flare = maxf(frame.flare,frame.brake)
		if not key.has("back"): frame.belly = frame.box*smoothstep(-0.2,0.2,-frame.flow.z)
		frame.flip_shape = rig.profile.maneuver_shape(deg_to_rad(frame.get("flip_degrees",0))).lerp(Vector3.BACK,frame.acro_recovery.x)
		frame.roll_shape = rig.profile.maneuver_shape(deg_to_rad(frame.get("roll_degrees",0))).lerp(Vector3.BACK,frame.acro_recovery.y)
		frame["pitch"] = frame.steer.x
		frame["yaw"] = frame.steer.y
		frame["roll"] = frame.steer.z
		frame["body_steer"] = Basis(Vector3.RIGHT,PI/2)*frame.steer if frame.fighter>0 else frame.steer
		frame.body_steer *= Vector3(-1,1,-1)
		frame["spread"] = maxf(frame.box,frame.flare)
		frame["stream"] = frame.track
		rig.motion = frame
		rig._prepare_directional_pose(mech.controller)
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
			rig.contacts.pelvis.value = Vector3(0,-frame.get("pelvis_drop",0.24*frame.land),0)
			sk.reset_bone_poses()
			mech.actor.rotation = rig.root_angles
			mech.actor.position = (-(Basis.from_euler(rig.root_angles)*Vector3(0,0.9,0))+rig.com.value+rig.contacts.pelvis.value)*mech.display_scale
			sk.advance(1.0/60)
		_apply_authored_leg_offsets(rig,frame)
		_apply_authored_upper_body(rig,frame)
		mech.actor.position = attitude*mech.actor.position+frame.get("body_shift",Vector3.ZERO)*mech.display_scale
		mech.actor.quaternion = attitude*mech.actor.quaternion
		_prepare_contact(rig.contacts,frame)
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
		var pivot := mech.actor.position+mech.actor.quaternion*Vector3.UP*0.9*mech.display_scale
		samples[name] = {"bones":rotations,"position":pivot,"rotation":mech.actor.quaternion}
	var library := AnimationLibrary.new()
	var skeleton_path: NodePath = mech.actor.get_path_to(sk)
	for name in keys:
		var clip := _clip([[0.0,name],[0.8,name]],samples,sk,skeleton_path,"")
		clip.resource_scene_unique_id = "Animation_K_"+name
		assert(library.add_animation("K_"+name,clip)==OK)
	for name in studies:
		var timeline: Array = studies[name]
		if name.begins_with("Boost_"):
			timeline = _retime_boost(timeline,samples,sk,rig.profile)
		var clip := _clip(timeline,samples,sk,skeleton_path,name)
		clip.resource_scene_unique_id = "Animation_M_"+name
		assert(library.add_animation("M_"+name,clip)==OK)
	assert(library.get_animation_list().size()==keys.size()+studies.size())
	assert(library.get_animation("K_Fall_Box").get_track_count()>15,"Pose export omitted the completed skeleton")
	assert(samples.Hover_Support.position.is_finite())
	assert(ResourceSaver.save(library,OUTPUT)==OK)
	print("Pose library baked: %d full-body keys and %d native AnimationPlayer motion studies."%[keys.size(),studies.size()])
	stage.queue_free()
	await process_frame
	quit()

func _apply_authored_leg_offsets(rig, frame: Dictionary) -> void:
	for side in 2:
		var lead: bool = frame.lead>0.0 if side==0 else frame.lead<0.0
		var stance: Vector3 = frame.get("stance",Vector3.ZERO)
		stance += frame.get("lead_leg" if lead else "trail_leg",Vector3.ZERO)
		for joint in 3:
			var servo = rig.legs[side*3+joint]
			var offset := Vector3(stance[joint],0,0)
			if joint==2: offset += frame.get("ankle_aim",Vector3.ZERO)
			servo.value = rig.profile.limit_joint(servo.value+offset,side,joint)

func _apply_authored_upper_body(rig, frame: Dictionary) -> void:
	rig.chest.value += frame.get("chest_offset",Vector3.ZERO)
	var brace: float = frame.get("shoulder_brace",0.0)
	var support: float = frame.get("support_lean",0.0)
	for side in 2:
		var sign := 1.0 if side==0 else -1.0
		rig.arms.upper[side].value += Vector3(brace+sign*support*0.18,0,sign*brace*0.45+support*0.12)
		rig.arms.elbows[side].value.x -= brace*0.65+sign*support*0.12

func _prepare_contact(contacts, frame: Dictionary) -> void:
	# Use the runtime two-bone and sole constraints on the Studio contact plane.
	if not frame.has("feet"): return
	var feet: Vector2 = frame.feet
	var shift: Vector2 = frame.get("contact_shift",Vector2.ZERO)
	var inset: Vector2 = frame.get("foot_inset",Vector2.ZERO)
	for side in 2:
		var x := (16.0-inset[side])*(-1.0 if side==0 else 1.0)
		contacts.last_world_plants[side] = Vector3(x+shift.x,-47.0+feet[side],11.0+shift.y)
		contacts.last_world_normals[side] = Vector3.UP
		contacts.weights[side].reset(Vector3.RIGHT)
		contacts.solvers[side].active = true
		contacts.solvers[side].influence = 1.0

func _retime_boost(timeline: Array, samples: Dictionary, sk: Skeleton3D, profile) -> Array:
	var result := [timeline[0]]
	var time := 0.0
	for index in range(1,timeline.size()):
		var from: Array = samples[timeline[index-1][1]].bones
		var to: Array = samples[timeline[index][1]].bones
		var duration: float = timeline[index][0]-timeline[index-1][0]
		for side in 2:
			var names := [profile.thigh_bones[side],profile.knee_bones[side],profile.foot_bones[side]]
			for joint in 3:
				var bone := sk.find_bone(names[joint])
				duration = maxf(duration,from[bone].angle_to(to[bone])/profile.joint_speed[joint])
		time += duration
		result.append([time,timeline[index][1]])
	return result

func _study_attitude(name: String, key: Dictionary) -> Quaternion:
	# Presentation attitude belongs only to this frozen-chassis authoring asset.
	# Gameplay gets the corresponding attitude from its physical controller.
	var flight := Quaternion(Vector3.RIGHT,-PI/2)
	if key.has("preview"): return Quaternion.from_euler(key.preview*PI/180.0)
	if key.has("flip_degrees"):
		return Quaternion(Vector3.RIGHT,deg_to_rad(key.flip_degrees)*key.acro_sign.x)
	if key.has("roll_degrees"):
		return Quaternion(Vector3.FORWARD,deg_to_rad(key.roll_degrees)*key.acro_sign.y)*flight
	match name:
		"Ready_Coil": return Quaternion(Vector3.RIGHT,deg_to_rad(-6))
		"Launch_Push": return Quaternion(Vector3.RIGHT,deg_to_rad(-8))
		"Hover_Catch": return Quaternion(Vector3.RIGHT,deg_to_rad(10))
		"Hover_Support": return Quaternion(Vector3.FORWARD,deg_to_rad(5))
		"Hover_Left","Hover_Right","Hover_Forward","Hover_Back": return Quaternion.IDENTITY
		"Flight_Pierce": return Quaternion(Vector3.RIGHT,deg_to_rad(-75))
		"Flight_Sustain","Fall_Box": return flight
		"Back_Fall": return Quaternion(Vector3.RIGHT,PI/2)
		"Bank_Left": return Quaternion(Vector3.BACK,deg_to_rad(25))*flight
		"Bank_Right": return Quaternion(Vector3.BACK,deg_to_rad(-25))*flight
		"Bank_Pull_Left": return Quaternion(Vector3.BACK,deg_to_rad(45))*Quaternion(Vector3.RIGHT,deg_to_rad(15))*flight
		"Bank_Pull_Right": return Quaternion(Vector3.BACK,deg_to_rad(-45))*Quaternion(Vector3.RIGHT,deg_to_rad(15))*flight
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
	var landing := study.begins_with("Landing") and study!="Landing_Missed"
	if not study.is_empty():
		for index in timeline.size():
			var key: Array = timeline[index]
			animation.add_marker("%02d_%s"%[index+1,key[1]],key[0])
	for index in sk.get_bone_count():
		var changing := false
		var rest := sk.get_bone_rest(index).basis.get_rotation_quaternion()
		for sample in samples.values(): changing = changing or sample.bones[index].angle_to(rest)>0.0001
		if not changing: continue
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track,NodePath(str(skeleton_path)+":"+sk.get_bone_name(index)))
		var bone := sk.get_bone_name(index)
		var leg := "Thigh" in bone or "Knee" in bone or "Feet" in bone
		var controlled_leg := leg and (study.begins_with("Boost_") or landing)
		animation.track_set_interpolation_type(track,Animation.INTERPOLATION_LINEAR if controlled_leg else Animation.INTERPOLATION_CUBIC)
		var offset := 0.0
		if STUDIES.has(study) and not landing:
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
		animation.track_set_path(track,NodePath(".."))
		animation.track_set_interpolation_type(track,Animation.INTERPOLATION_LINEAR if landing else Animation.INTERPOLATION_CUBIC)
		for key in timeline:
			if type==Animation.TYPE_POSITION_3D: animation.position_track_insert_key(track,key[0],samples[key[1]].position)
			else: animation.rotation_track_insert_key(track,key[0],samples[key[1]].rotation)
	return animation
