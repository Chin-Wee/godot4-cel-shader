extends SceneTree

const Mech = preload("res://aerial/aerial_mech.gd")

var viewport: SubViewport
var studio
var output := "/tmp/flight-key-poses"

func _initialize() -> void: call_deferred("_run")

func _save(path: String) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.force_sync()
	RenderingServer.force_draw(false)
	assert(viewport.get_texture().get_image().save_png(path)==OK)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if not arg.begins_with("--"): output = arg
	var render := DisplayServer.get_name()!="headless"
	if render:
		assert(DirAccess.make_dir_recursive_absolute(output)==OK)
		root.mode = Window.MODE_MINIMIZED
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	studio = load("res://aerial/pose_studio.tscn").instantiate()
	viewport.add_child(studio)
	studio.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	await process_frame
	var sk: Skeleton3D = studio.actor.find_child("Skeleton3D",true,false)
	var library: AnimationLibrary = studio.player.get_animation_library(&"design")
	var pose_count := 0
	var study_count := 0
	for clip in studio.clips:
		studio.show_clip(studio.clips.find(clip))
		studio.caption.text = str(clip).trim_prefix("design/").replace("_"," ")+"\nPOSE / MOTION STUDY · frozen chassis"
		var animation: Animation = studio.player.get_animation(clip)
		var markers := animation.get_marker_names()
		if str(clip).contains("/K_"):
			pose_count += 1
			if not render: continue
			for view in 3:
				studio.set_view(view)
				studio.player.seek(0,true)
				await process_frame
				_save(output.path_join(str(clip).trim_prefix("design/")+"-view"+str(view)+".png"))
		else:
			study_count += 1
			assert(markers.size()>=3 and is_zero_approx(animation.get_marker_time(markers[0])))
			assert(is_equal_approx(animation.get_marker_time(markers[-1]),animation.length))
			var previous_time := -1.0
			for marker in markers:
				var phase: String = marker.substr(3)
				assert(library.has_animation("K_"+phase), "Missing full-body key for "+phase)
				var time := animation.get_marker_time(marker)
				assert(time>previous_time, "Out-of-order phase in "+str(clip))
				studio.player.seek(time,true)
				assert(sk.get_bone_global_pose(sk.find_bone("Feet.L")).is_finite())
				previous_time = time
			if not render: continue
			studio.set_view(0)
			var name := str(clip).trim_prefix("design/")
			if "--keyframes-only" in args:
				for marker in markers:
					studio.caption.text = name.replace("_"," ")+"\n"+marker.substr(3).replace("_"," ")
					studio.player.seek(animation.get_marker_time(marker),true)
					await process_frame
					_save(output.path_join(name+"-"+marker+".png"))
			else:
				for frame in int(ceil(animation.length*30))+1:
					studio.player.seek(minf(frame/30.0,animation.length),true)
					await process_frame
					_save(output.path_join("%s-%04d.png"%[name,frame]))
	# Check joint-local deformation. A preview attitude change alone must fail.
	for pair in [
		["Hover_Neutral","Fall_Box","Shoulder.L",0.30],
		["Hover_Left","Boost_Left_Drive","Knee.L",0.10],
		["Boost_Left_Drive","Boost_Right_Drive","Feet.L",0.15],
		["Boost_Forward_Drive","Boost_Back_Drive","Feet.L",0.20],
		["Boost_Forward_Soft","Boost_Forward_Heavy","Feet.L",0.12],
		["Flight_Sustain","Flight_Drive","Shoulder.L",0.20],
		["Brake_Open","Brake_Symmetric","Shoulder.L",0.20],
		["Retro_Brace_Left","Retro_Brace_Right","Knee.L",0.15],
		["Front_Inversion","Front_Layout_Inversion","Knee.L",0.20],
		["Roll_Initiate","Roll_Right_Initiate","Knee.L",0.15],
		["Landing_Reach_Left","Landing_Reach_Right","Knee.L",0.15],
		["Landing_Reach_Left","Landing_Catch_Left","Knee.L",0.15],
		["Landing_Absorb","Landing_Hard_Absorb","Knee.L",0.20],
	]:
		var start := _joint_rotation(sk,pair[0],pair[2])
		var finish := _joint_rotation(sk,pair[1],pair[2])
		assert(start.angle_to(finish)>pair[3], "Insufficient joint change between %s and %s"%[pair[0],pair[1]])
	assert(_heel_axis(sk,"Hover_Neutral").dot(Vector3.UP)>0.99,"Neutral heels do not point up")
	for entry in [
		["Left",Vector3.LEFT],["Right",Vector3.RIGHT],["Forward",Vector3.FORWARD],["Back",Vector3.BACK],
		["Forward_Left",Vector3(-1,0,-1)],["Forward_Right",Vector3(1,0,-1)],
		["Back_Left",Vector3(-1,0,1)],["Back_Right",Vector3(1,0,1)],
	]:
		var drive := _heel_axis(sk,"Boost_"+entry[0]+"_Drive")
		var arrest := _heel_axis(sk,"Boost_"+entry[0]+"_Catch")
		var direction: Vector3 = entry[1]
		for axis in [0,2]:
			if direction[axis]==0.0: continue
			assert(drive[axis]*direction[axis]>0.05,"Heel drive points away from "+entry[0])
			assert(arrest[axis]*direction[axis]<-0.05,"Heel catch fails to oppose "+entry[0])
	print("Pose studio checks passed: %d full-body keys and %d phase-marked motion studies."%[pose_count,study_count])
	studio.queue_free()
	await process_frame
	quit()

func _joint_rotation(sk: Skeleton3D, pose: String, bone: String) -> Quaternion:
	_show_key(pose)
	return sk.get_bone_pose_rotation(sk.find_bone(bone))

func _heel_axis(sk: Skeleton3D, pose: String) -> Vector3:
	_show_key(pose)
	var axis := Vector3.ZERO
	for mount in Mech.MOUNTS:
		if not mount[0].begins_with("Heel"): continue
		var bone := sk.find_bone(mount[1])
		axis -= (sk.global_basis*sk.get_bone_global_pose(bone).basis*mount[3]).normalized()
	return axis.normalized()

func _show_key(pose: String) -> void:
	var clip := StringName("design/K_"+pose)
	assert(studio.player.has_animation(clip))
	studio.player.play(clip)
	studio.player.seek(0,true)
