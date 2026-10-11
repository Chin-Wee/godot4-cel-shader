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
		var jump := animation_player.get_animation(&"Jump")
		var cue_time := float(mech.get("jump_landing_cue_time"))
		var cue_ratio := cue_time / jump.length
		var jump_speed: float = mech.call("_get_locomotion_playback_speed", &"Jump", 0.0)
		var predicted_airtime := 2.0 * float(mech.get("jump_power")) / float(mech.get("gravity"))
		_expect(cue_ratio > 0.7 and cue_ratio < 0.8, "%s landing cue is not the measured post-apex compression" % scene_path)
		_expect(
			is_equal_approx(cue_time / jump_speed, predicted_airtime),
			"%s landing cue does not align with predicted airtime" % scene_path
		)
		_expect(
			(jump.length - cue_time) / jump_speed > 0.0,
			"%s has no recovery after touchdown" % scene_path
		)
		_expect(
			mech.call("_get_locomotion_animation", 0.0, true, true) == &"Jump",
			"%s does not retain Jump through grounded recovery" % scene_path
		)
		if scene_path.ends_with("george.tscn"):
			await _check_restart_behavior(mech, animation_player, jump.length)
		mech.queue_free()
		await process_frame
	if test_failed:
		quit(1)
	else:
		print("Mech jump calibration passed for all four mechs.")
		quit()


func _check_restart_behavior(
	mech: CharacterBody3D, animation_player: AnimationPlayer, jump_length: float
) -> void:
	var original_mouse_mode := Input.get_mouse_mode()
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(4.0, 1.0, 4.0)
	floor_shape.shape = floor_box
	floor.add_child(floor_shape)
	floor.position.y = -0.5
	root.add_child(floor)
	mech.global_position = Vector3.ZERO
	mech.set_physics_process(false)
	await physics_frame
	mech.call("_physics_process", 1.0 / 60.0)
	_expect(mech.is_on_floor(), "Could not place the mech on the test floor")

	mech.velocity.y = float(mech.get("jump_power"))
	mech.call("_physics_process", 1.0 / 60.0)
	_expect(not mech.is_on_floor(), "Jump did not leave the test floor")
	_expect(animation_player.is_playing(), "Takeoff did not start Jump")

	animation_player.seek(jump_length, true)
	animation_player.stop()
	mech.call("_update_locomotion_animation")
	_expect(
		not animation_player.is_playing(),
		"A completed Jump clip restarted while the mech was still airborne"
	)

	mech.global_position = Vector3.ZERO
	mech.set("velocity", Vector3.ZERO)
	mech.call("_physics_process", 1.0 / 60.0)
	_expect(mech.is_on_floor(), "Could not land on the test floor")
	mech.call("_play_animation", &"Jump", true)
	animation_player.seek(jump_length * 0.8, true)
	mech.call("_update_locomotion_animation")
	_expect(animation_player.is_playing(), "Grounded landing recovery ended early")

	mech.velocity.y = float(mech.get("jump_power"))
	mech.call("_physics_process", 1.0 / 60.0)
	_expect(not mech.is_on_floor(), "Second jump did not leave the test floor")
	_expect(animation_player.is_playing(), "A new takeoff did not restart Jump")
	_expect(
		animation_player.current_animation_position < 0.01,
		"A new takeoff did not restart Jump from its first pose"
	)
	Input.set_mouse_mode(original_mouse_mode)
	floor.queue_free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	test_failed = true
	assert(condition, message)
