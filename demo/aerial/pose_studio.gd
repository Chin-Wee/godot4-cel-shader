extends Node3D

# Native AnimationPlayer authoring preview. This scene never runs flight physics.
@onready var actor := $MechAsset
@onready var player: AnimationPlayer = $PosePlayer
@onready var camera: Camera3D = $Camera3D
@onready var caption: Label = $CanvasLayer/Caption
var clips: Array[StringName] = []
var selected := 0

func _ready() -> void:
	actor.set_player_controlled(false)
	actor.set_physics_process(false)
	actor.animation_player.stop()
	actor.animation_player.active = false
	var sk: Skeleton3D = actor.find_child("Skeleton3D",true,false)
	for name in ["GUN","Cube_001"]: sk.find_child(name,false,false).visible = false
	# Match the runtime's matte palette, under neutral pose-review lighting.
	var colors := {}
	for mesh in actor.find_children("*","MeshInstance3D",true,false):
		for index in mesh.mesh.get_surface_count():
			var source: ShaderMaterial = mesh.get_active_material(index)
			var color: Color = source.get_shader_parameter("color")
			if not colors.has(color):
				var material := ShaderMaterial.new()
				material.shader = load("res://shaders/aerial/aircraft.gdshader")
				material.set_shader_parameter("body_color",color)
				for parameter in ["orientation_bias","panel_strength","highlight_mask","rim_strength"]: material.set_shader_parameter(parameter,0.0)
				material.set_shader_parameter("shadow_fill",0.35)
				colors[color] = material
			mesh.set_surface_override_material(index,colors[color])
	clips.assign(player.get_animation_list())
	show_clip(clips.find(&"design/M_Launch"))
	set_view(0)

func set_view(view: int) -> void:
	camera.position = [Vector3(170,70,-170),Vector3(0,12,-220),Vector3(220,12,0)][view]
	camera.look_at(Vector3.ZERO)

func show_clip(index: int) -> void:
	selected = posmod(index,clips.size())
	player.play(clips[selected])
	player.seek(0,true)
	caption.text = "%s\nPOSE / MOTION STUDY · frozen chassis\n← / → clips · Space pause · R restart · 1 / 2 / 3 views" % str(clips[selected]).trim_prefix("design/").replace("_"," ")

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_RIGHT: show_clip(selected+1)
		KEY_LEFT: show_clip(selected-1)
		KEY_SPACE:
			if player.is_playing(): player.pause()
			else: player.play()
		KEY_R: show_clip(selected)
		KEY_1: set_view(0)
		KEY_2: set_view(1)
		KEY_3: set_view(2)
