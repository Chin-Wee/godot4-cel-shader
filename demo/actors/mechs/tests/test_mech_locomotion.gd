extends SceneTree

const MECH_SCENES := [
	"res://actors/mechs/george.tscn",
	"res://actors/mechs/leela.tscn",
	"res://actors/mechs/mike.tscn",
	"res://actors/mechs/stan.tscn",
]


func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	for scene_path in MECH_SCENES:
		var mech: Node = load(scene_path).instantiate()
		root.add_child(mech)
		await process_frame
		var animation_player := mech.find_child("AnimationPlayer", true, false) as AnimationPlayer
		assert(animation_player != null, "%s has no AnimationPlayer" % scene_path)
		for animation_name in [&"Walk", &"Run"]:
			var animation := animation_player.get_animation(animation_name)
			var stride_distance := (
				float(mech.get("locomotion_stride_distances").get(animation_name, 0.0))
				* float(mech.get("visual_scale"))
			)
			assert(stride_distance > 0.0, "%s has no %s stride" % [scene_path, animation_name])
			var playback_speed: float = mech.call(
				"_get_locomotion_playback_speed", animation_name, 2.0
			)
			assert(
				is_equal_approx(stride_distance * playback_speed / animation.length, 2.0),
				"%s %s does not match planar speed" % [scene_path, animation_name]
			)
		var visual_root: Node3D = mech.get_node("VisualRoot")
		mech.call("_update_visual_facing", Vector3(0.0, 0.0, -1.0), 1.0)
		assert(is_equal_approx(visual_root.rotation.y, PI), "%s forward facing is incorrect" % scene_path)
		mech.call("_update_visual_facing", Vector3(1.0, 0.0, 0.0), 1.0)
		assert(is_equal_approx(visual_root.rotation.y, PI / 2.0), "%s strafe facing is incorrect" % scene_path)
		mech.queue_free()
		await process_frame
	print("Mech locomotion calibration passed for all four mechs.")
	quit()
