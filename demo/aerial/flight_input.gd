extends RefCounted

# Platform input adapter for the existing DCS/Elite Dangerous flight commands.
# Replays and alternate input providers pass the same command dictionary to step.
const Controller = preload("res://aerial/flight_controller.gd")
const ACTION_KEYS := {
	"flight_forward": KEY_W, "flight_back": KEY_S,
	"flight_left": KEY_A, "flight_right": KEY_D,
	"flight_yaw_left": KEY_Q, "flight_yaw_right": KEY_E,
	"flight_thrust_up": KEY_SPACE, "flight_thrust_down": KEY_C,
	"flight_brake": KEY_SHIFT, "flight_jump": KEY_R, "flight_precision": KEY_CTRL,
}

static func install_input_actions() -> void:
	for action in ACTION_KEYS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new()
		event.physical_keycode = ACTION_KEYS[action]
		InputMap.action_add_event(action, event)
	# Retire the old aerial-only actions, including their Shift/X bindings.
	for action in ["flight_burst", "flight_rise", "flight_sink"]:
		if InputMap.has_action(action): InputMap.erase_action(action)

static func read_input() -> Dictionary:
	var result := {}
	for key in ["forward", "back", "left", "right", "yaw_left", "yaw_right", "brake", "precision"]:
		result[key] = Input.is_action_pressed("flight_" + key)
	return result

static func handle_input(event: InputEvent, controller: Controller) -> void:
	if event.is_action_pressed("flight_thrust_up"): controller.detent = mini(controller.detent + 1, Controller.DETENTS.size() - 1)
	if event.is_action_pressed("flight_thrust_down"): controller.detent = maxi(controller.detent - 1, 0)
	if event.is_action_pressed("flight_jump"): controller.jump_requested = true
