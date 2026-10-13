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
			var movement_speed := float(
				mech.get("speed") if animation_name == &"Walk" else mech.get("run_speed")
			)
			var animation := animation_player.get_animation(animation_name)
			var stride_distance := (
				float(mech.get("locomotion_stride_distances").get(animation_name, 0.0))
				* float(mech.get("visual_scale"))
			)
			_expect(stride_distance > 0.0, "%s has no %s stride" % [scene_path, animation_name])
			var playback_speed: float = mech.call(
				"_get_locomotion_playback_speed", animation_name, movement_speed
			)
			_expect(
				is_equal_approx(
					stride_distance * playback_speed / animation.length, movement_speed
				),
				"%s %s does not match planar speed" % [scene_path, animation_name]
			)
		var visual_root: Node3D = mech.get_node("VisualRoot")
		mech.call("_update_visual_facing", Vector3(0.0, 0.0, -1.0), 1.0, 0.25)
		_expect(is_equal_approx(visual_root.rotation.y, PI), "%s forward facing is incorrect" % scene_path)
		mech.call("_update_visual_facing", Vector3(1.0, 0.0, 0.0), 1.0, 0.25)
		_expect(
			visual_root.rotation.y > PI / 2.0 and visual_root.rotation.y < PI,
			"%s facing snapped instead of turning smoothly" % scene_path
		)
		for _frame in 60:
			mech.call("_update_visual_facing", Vector3(1.0, 0.0, 0.0), 1.0, 0.05)
		_expect(
			is_equal_approx(visual_root.rotation.y, PI / 2.0),
			"%s did not face its movement direction" % scene_path
		)
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
	var run_events := InputMap.action_get_events("run")
	_expect(
		run_events.size() == 1
		and run_events[0] is InputEventKey
		and (run_events[0] as InputEventKey).physical_keycode == KEY_SHIFT,
		"Run should be bound to Shift in the InputMap"
	)
	mech.rotation.y = PI / 2.0
	await process_frame
	var active_camera := mech.get_viewport().get_camera_3d()
	var expected_forward := -active_camera.global_basis.z
	expected_forward.y = 0.0
	expected_forward = expected_forward.normalized()
	Input.action_press("forward", 0.75)
	var input_strength := Input.get_vector("left", "right", "forward", "back").length()
	var speed := float(mech.get("speed"))
	var partial_target_speed := input_strength * speed
	mech.call("_physics_process", 1.0 / 60.0)
	var first_velocity: Vector3 = mech.get("velocity")
	_expect(
		Vector2(first_velocity.x, first_velocity.z).length() > 0.0
		and Vector2(first_velocity.x, first_velocity.z).length() < partial_target_speed,
		"Movement should accelerate instead of snapping to speed"
	)
	for _frame in 120:
		mech.call("_physics_process", 1.0 / 60.0)
	var partial_velocity: Vector3 = mech.get("velocity")
	var partial_speed := Vector2(partial_velocity.x, partial_velocity.z).length()
	_expect(
		is_equal_approx(partial_speed, partial_target_speed),
		"Camera-relative partial input did not reach its walk speed"
	)
	_expect(
		Vector3(partial_velocity.x, 0.0, partial_velocity.z).normalized().dot(expected_forward)
		> 0.999,
		"Forward input should follow the active camera direction"
	)
	_expect(
		mech.call("_get_locomotion_animation", partial_speed, true, false, false) == &"Walk",
		"Default movement should select Walk"
	)
	Input.action_press("run")
	for _frame in 120:
		mech.call("_physics_process", 1.0 / 60.0)
	var run_velocity: Vector3 = mech.get("velocity")
	var expected_run_speed := input_strength * float(mech.get("run_speed"))
	_expect(
		is_equal_approx(Vector2(run_velocity.x, run_velocity.z).length(), expected_run_speed),
		"Holding Shift should accelerate to run speed"
	)
	_expect(
		mech.call("_get_locomotion_animation", expected_run_speed, true, false, true) == &"Run",
		"Holding Shift should select Run"
	)
	Input.action_release("forward")
	Input.action_press("right", 0.75)
	var camera_right := active_camera.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	mech.call("_physics_process", 1.0 / 60.0)
	var turning_velocity: Vector3 = mech.get("velocity")
	var turning_direction := Vector3(turning_velocity.x, 0.0, turning_velocity.z).normalized()
	_expect(
		turning_direction.dot(camera_right) > 0.0 and turning_direction.dot(camera_right) < 1.0,
		"Changing direction should follow a curved path"
	)
	Input.action_release("right")
	Input.action_release("run")
	Input.action_release("forward")
	Input.set_mouse_mode(original_mouse_mode)
	mech.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	test_failed = true
	assert(condition, message)
