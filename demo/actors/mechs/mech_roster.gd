extends Node3D

@export var grass: MultiMeshInstance3D

var active_mech: CharacterBody3D
@onready var playable_mechs: Array[Node] = [$George, $MechAsset]


func _ready() -> void:
	_set_active_mech(playable_mechs[0])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_mech") and not event.is_echo():
		var next_index := (playable_mechs.find(active_mech) + 1) % playable_mechs.size()
		_set_active_mech(playable_mechs[next_index])
		get_viewport().set_input_as_handled()


func _set_active_mech(mech: CharacterBody3D) -> void:
	for candidate in playable_mechs:
		candidate.set_player_controlled(candidate == mech)
	active_mech = mech
	if is_instance_valid(grass):
		grass.interaction_target = active_mech
