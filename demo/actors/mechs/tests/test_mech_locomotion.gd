extends SceneTree

const MECH_SCENES := [
	"res://actors/mechs/george.tscn",
	"res://actors/mechs/leela.tscn",
	"res://actors/mechs/mike.tscn",
	"res://actors/mechs/stan.tscn",
]
var test_failed := false


func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	for scene_path in MECH_SCENES:
		var mech: Node = load(scene_path).instantiate()
		root.add_child(mech)
		await process_frame
		var animation_player := mech.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_expect(animation_player != null, "%s has no AnimationPlayer" % scene_path)
		for animation_name in [&"Walk", &"Run"]:
			var animation := animation_player.get_animation(animation_name)
			var stride_distance := (
				float(mech.get("locomotion_stride_distances").get(animation_name, 0.0))
				* float(mech.get("visual_scale"))
			)
			_expect(stride_distance > 0.0, "%s has no %s stride" % [scene_path, animation_name])
			var playback_speed: float = mech.call(
				"_get_locomotion_playback_speed", animation_name, 2.0
			)
			_expect(
				is_equal_approx(stride_distance * playback_speed / animation.length, 2.0),
				"%s %s does not match planar speed" % [scene_path, animation_name]
			)
		var visual_root: Node3D = mech.get_node("VisualRoot")
		mech.call("_update_visual_facing", Vector3(0.0, 0.0, -1.0), 1.0)
		_expect(is_equal_approx(visual_root.rotation.y, PI), "%s forward facing is incorrect" % scene_path)
		mech.call("_update_visual_facing", Vector3(1.0, 0.0, 0.0), 1.0)
		_expect(is_equal_approx(visual_root.rotation.y, PI / 2.0), "%s strafe facing is incorrect" % scene_path)
		mech.queue_free()
		await process_frame
	await _check_partial_and_full_input()
	if test_failed:
		quit(1)
	else:
		print("Mech locomotion calibration passed for all four mechs.")
		quit()


func _check_partial_and_full_input() -> void:
	var mech: Node = load(MECH_SCENES[0]).instantiate()
	root.add_child(mech)
	await process_frame
	mech.set_physics_process(false)
	var original_mouse_mode := Input.get_mouse_mode()
	Input.action_press("forward", 0.75)
	var partial_input := Input.get_vector("left", "right", "forward", "back")
	var speed := float(mech.get("speed"))
	var partial_speed := partial_input.length() * speed
	mech.call("_physics_process", 1.0 / 60.0)
	var partial_velocity: Vector3 = mech.get("velocity")
	_expect(
		is_equal_approx(Vector2(partial_velocity.x, partial_velocity.z).length(), partial_speed),
		"Partial input magnitude was not preserved"
	)
	_expect(
		mech.call("_get_locomotion_animation", partial_speed, true) == &"Walk",
		"Partial input should select Walk"
	)
	Input.action_press("forward", 1.0)
	var full_speed := Input.get_vector("left", "right", "forward", "back").length() * speed
	mech.call("_physics_process", 1.0 / 60.0)
	var full_velocity: Vector3 = mech.get("velocity")
	_expect(
		is_equal_approx(Vector2(full_velocity.x, full_velocity.z).length(), full_speed),
		"Full input should reach max speed"
	)
	_expect(
		mech.call("_get_locomotion_animation", full_speed, true) == &"Run",
		"Full input should select Run"
	)
	Input.action_release("forward")
	Input.set_mouse_mode(original_mouse_mode)
	mech.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	test_failed = true
	assert(condition, message)
