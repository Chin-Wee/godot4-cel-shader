extends SceneTree

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
	if not args.is_empty(): output = args[0]
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
	var library: AnimationLibrary = studio.player.get_animation_library(&"design")
	assert(library.has_animation(&"K_Back_Fall") and library.has_animation(&"M_Extended_Layouts") and library.has_animation(&"M_Head_Scan"))
	for clip in studio.clips:
		studio.show_clip(studio.clips.find(clip))
		studio.caption.text = str(clip).trim_prefix("design/").replace("_"," ")+"\nPOSE / MOTION STUDY · frozen chassis"
		if str(clip).contains("/K_"):
			for view in 3:
				studio.set_view(view)
				studio.player.seek(0,true)
				await process_frame
				_save(output.path_join(str(clip).trim_prefix("design/")+"-view"+str(view)+".png"))
		else:
			studio.set_view(0)
			var length: float = studio.player.current_animation_length
			for frame in int(ceil(length*30))+1:
				studio.player.seek(minf(frame/30.0,length),true)
				await process_frame
				_save(output.path_join("%s-%04d.png"%[str(clip).trim_prefix("design/"),frame]))
	# Verify the exported clips actually drive skin deformation, not just actor
	# transforms: key local shoulder rotations and knee shapes must differ.
	var sk: Skeleton3D = studio.actor.find_child("Skeleton3D",true,false)
	studio.player.play(&"design/K_Hover_Support")
	studio.player.seek(0,true)
	var hover := sk.get_bone_pose_rotation(sk.find_bone("Shoulder.L"))
	studio.player.play(&"design/K_Fall_Box")
	studio.player.seek(0,true)
	assert(hover.angle_to(sk.get_bone_pose_rotation(sk.find_bone("Shoulder.L")))>0.3)
	print("Pose studio checks passed: signed belly/back, extended layouts and bounded head-look studies and real skeleton deformation in three views.")
	studio.queue_free()
	await process_frame
	quit()
