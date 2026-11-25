extends "res://aerial/pose_studio.gd"

const Fixture = preload("res://aerial/articulation_fixture.gd")
const FlightInput = preload("res://aerial/flight_input.gd")
const Poses = preload("res://aerial/poses/articulation_poses.gd")
const SAVED_KEYS := "user://lower_body_keys.tres"
const JOINT_NAMES := ["Hip", "Knee", "Ankle"]

var fixture: Fixture
var view_index := 0
var sliders := {}
var joint_sliders: Array[SpinBox] = []
var pose_picker: OptionButton
var mode_picker: OptionButton
var retro: CheckButton
var joint_picker: OptionButton
var readout: Label
var status: Label
var vectors: MeshInstance3D
var show_vectors := true

func _ready() -> void:
	super._ready()
	FlightInput.install_input_actions()
	player.stop()
	player.active = false
	$ContactFloor.hide()
	var sk: Skeleton3D = actor.find_child("Skeleton3D",true,false)
	sk.reset_bone_poses()
	for attachment in sk.find_children("*","BoneAttachment3D",true,false):
		var parent := String(attachment.bone_name).get_slice(".",0)
		attachment.visible = parent in ["PelvisBase","Low_Waist","Thigh","Knee","Shin","Feet"]
	sk.get_node("Cube").hide() # Torso-weighted backpack is outside the attachment tree.
	fixture = Fixture.new()
	fixture.freeze = true
	add_child(fixture)
	actor.reparent(fixture,false)
	fixture.configure(sk)
	_build_controls()
	vectors = MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	vectors.material_override = material
	vectors.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fixture.add_child(vectors)
	camera.size = 145
	_reframe()
	caption.hide()

func _build_controls() -> void:
	var screen := PanelContainer.new()
	$CanvasLayer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	screen.offset_left = 16
	screen.offset_right = 350
	screen.offset_top = 16
	screen.offset_bottom = -16
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",2)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var title := Label.new()
	title.text = "Flight Articulation Lab"
	content.add_child(title)
	mode_picker = _picker(content,["Force analysis","Pose authoring","Dynamic simulation"])
	mode_picker.item_selected.connect(_change_mode)
	var pose_names := ["Pilot_Blend"]+Poses.AUTHORED.keys()+Poses.MIRRORED.keys()
	pose_picker = _picker(content,pose_names)
	pose_picker.select(1)
	pose_picker.item_selected.connect(func(index: int):
		fixture.key = pose_names[index]
		fixture.override_angles.clear()
		_read_joint())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("v_separation",0)
	content.add_child(grid)
	_slider(grid,"Intensity",0,1,1)
	_slider(grid,"Thrust request (× weight)",0,4,1)
	_slider(grid,"Left power cap",0,1,1)
	_slider(grid,"Right power cap",0,1,1)
	_slider(grid,"Pitch",-1,1,0)
	_slider(grid,"Yaw",-1,1,0)
	_slider(grid,"Roll",-1,1,0)
	_slider(grid,"Lateral",-1,1,0)
	_slider(grid,"Vertical",-1,1,0)
	_slider(grid,"Forward",-1,1,0)
	_slider(grid,"Time scale",0.1,1,1)
	var options := HBoxContainer.new()
	content.add_child(options)
	retro = CheckButton.new()
	retro.text = "Retrograde"
	options.add_child(retro)
	var arrows := CheckButton.new()
	arrows.text = "Vectors"
	arrows.button_pressed = true
	options.add_child(arrows)
	arrows.toggled.connect(func(enabled: bool): show_vectors = enabled)
	joint_picker = _picker(content,["Left hip","Left knee","Left ankle","Right hip","Right knee","Right ankle"])
	joint_picker.item_selected.connect(func(_index: int): _read_joint())
	var axes := HBoxContainer.new()
	content.add_child(axes)
	for axis in 3:
		var control := SpinBox.new()
		control.min_value = -95
		control.max_value = 95
		control.step = 0.1
		control.suffix = ["° X","° Y","° Z"][axis]
		control.value_changed.connect(func(_value: float): _edit_joint())
		joint_sliders.append(control)
		axes.add_child(control)
	var commands := HBoxContainer.new()
	content.add_child(commands)
	var save := Button.new()
	save.text = "Save key"
	save.pressed.connect(_save_key)
	commands.add_child(save)
	var reset := Button.new()
	reset.text = "Reset fixture"
	reset.pressed.connect(fixture.reset_lab)
	commands.add_child(reset)
	status = Label.new()
	status.text = "1 front   2 side   3 top\nW/S pitch   A/D roll   Q/E yaw"
	content.add_child(status)
	readout = Label.new()
	readout.add_theme_font_size_override("font_size",14)
	content.add_child(readout)
	sliders["Intensity"].value_changed.connect(func(value: float):
		fixture.intensity = value
		_read_joint())
	_read_joint()

func _picker(parent: Control, names: Array) -> OptionButton:
	var picker := OptionButton.new()
	for name in names: picker.add_item(String(name).replace("_"," "))
	parent.add_child(picker)
	return picker

func _slider(parent: Control, label: String, minimum: float, maximum: float, value: float) -> void:
	var name_label := Label.new()
	name_label.text = label
	parent.add_child(name_label)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = 0.05
	field.value = value
	parent.add_child(field)
	sliders[label] = field

func _change_mode(index: int) -> void:
	fixture.freeze = index!=2
	fixture.reset_lab()
	_read_joint()

func _read_joint() -> void:
	var values := fixture.targets()
	var joint := joint_picker.selected
	for axis in 3:
		joint_sliders[axis].set_value_no_signal(rad_to_deg(values[joint][axis]))
		joint_sliders[axis].editable = mode_picker.selected==1 and (joint%3!=1 or axis==0)

func _edit_joint() -> void:
	if fixture.override_angles.is_empty(): fixture.override_angles = fixture.targets()
	var joint := joint_picker.selected
	var angles := Vector3(joint_sliders[0].value,joint_sliders[1].value,joint_sliders[2].value)*PI/180
	fixture.override_angles[joint] = Fixture.Profile.limit_joint(angles,joint/3,joint%3)
	_read_joint()

func _save_key() -> void:
	if mode_picker.selected!=1:
		status.text = "Select Pose authoring to save a key"
		return
	fixture.set_pose(fixture.targets())
	var library := ResourceLoader.load(SAVED_KEYS,"AnimationLibrary",ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary if FileAccess.file_exists(SAVED_KEYS) else AnimationLibrary.new()
	var clip := Animation.new()
	var sk := fixture.skeleton
	var path := actor.get_path_to(sk)
	for id in fixture.bone_ids:
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track,NodePath(str(path)+":"+sk.get_bone_name(id)))
		clip.rotation_track_insert_key(track,0,sk.get_bone_pose_rotation(id))
	var name := StringName("K_"+fixture.key)
	if library.has_animation(name): library.remove_animation(name)
	library.add_animation(name,clip)
	status.text = "Saved "+str(name) if ResourceSaver.save(library,SAVED_KEYS)==OK else "Could not save key"

func _physics_process(delta: float) -> void:
	fixture.power = sliders["Thrust request (× weight)"].value
	fixture.intensity = sliders["Intensity"].value
	fixture.side_power = Vector2(sliders["Left power cap"].value,sliders["Right power cap"].value)
	fixture.steer = Vector3(sliders["Pitch"].value,sliders["Yaw"].value,sliders["Roll"].value)
	fixture.move = Vector3(sliders["Lateral"].value,sliders["Vertical"].value,sliders["Forward"].value)
	fixture.brake = retro.button_pressed
	if mode_picker.selected!=1 and not (get_viewport().gui_get_focus_owner() is LineEdit):
		var keys := FlightInput.read_input()
		var turn := Vector3(float(keys.back)-float(keys.forward),float(keys.yaw_left)-float(keys.yaw_right),
			float(keys.left)-float(keys.right))
		fixture.steer = (fixture.steer+turn).clamp(-Vector3.ONE,Vector3.ONE)
		fixture.brake = fixture.brake or keys.brake
	fixture.tick(delta,mode_picker.selected==1)

func _process(_delta: float) -> void:
	Engine.time_scale = sliders["Time scale"].value
	_reframe()
	vectors.visible = show_vectors
	if show_vectors: _draw_vectors()
	var pilot := Fixture.Flight.PILOT_AXES.inverse()
	var force_error: Vector3 = fixture.requested_force-fixture.force
	var moment_error: Vector3 = fixture.requested_moment-fixture.moment
	var live := 0
	var restarting := 0
	for valve in fixture.valves:
		live += int(valve.running and valve.ignition_remaining<=0.0)
		restarting += int(valve.restart_remaining>0.0)
	readout.text = "Body force (kN)  %s\nWorld force (kN)  %s\nPilot moment (kN·m)  %s\nResidual force (kN)  %s\nResidual moment (kN·m)  %s\nLeft / right output  %.1f / %.1f kN\n%d firing · %d restarting%s\nCyan thrust · orange exhaust · grey lever" % [
		_fmt(fixture.force),_fmt(fixture.global_basis*fixture.force),_fmt(pilot*fixture.moment),_fmt(force_error),_fmt(pilot*moment_error),
		fixture.side_output.x/1000,fixture.side_output.y/1000,live,restarting," · saturated" if fixture.saturated else ""]

func _fmt(vector: Vector3) -> String:
	return "%.1f / %.1f / %.1f"%[vector.x/1000,vector.y/1000,vector.z/1000]

func _reframe() -> void:
	var center := fixture.global_position-Vector3.UP*18
	# Set the chassis slightly right of the controls for every camera.
	camera.position = center+[Vector3(0,15,220),Vector3(220,25,0),Vector3(0,220,0)][view_index]
	camera.look_at(center,Vector3.FORWARD if view_index==2 else Vector3.UP)
	camera.h_offset = -21

func _draw_vectors() -> void:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in fixture.ports.size():
		var port: Dictionary = fixture.ports[i]
		var point: Vector3 = port.lever*(Fixture.LENGTH*Fixture.UNITS)
		var axis: Vector3 = -port.basis.z
		_line(lines,Vector3.ZERO,point,Color(0.52,0.57,0.65))
		var length: float = 5.0+30.0*fixture.outputs[i]/Fixture.WEIGHT
		_arrow(lines,point,axis*length,Color.CYAN)
		_arrow(lines,point,-axis*length,Color.ORANGE)
	_arrow(lines,Vector3.ZERO,fixture.force/Fixture.WEIGHT*30,Color.AQUAMARINE)
	for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]: _line(lines,-axis*3,axis*3,Color.WHITE)
	lines.surface_end()
	vectors.mesh = lines

func _line(mesh: ImmediateMesh, start: Vector3, end: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(start)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(end)

func _arrow(mesh: ImmediateMesh, start: Vector3, vector: Vector3, color: Color) -> void:
	if vector.is_zero_approx(): return
	var direction := vector.normalized()
	var spread := direction.cross(Vector3.UP)
	if spread.length_squared()<0.01: spread = direction.cross(Vector3.BACK)
	var tip := start+vector
	var tail := tip-direction*4
	_line(mesh,start,tip,color)
	_line(mesh,tip,tail+spread.normalized()*1.5,color)
	_line(mesh,tip,tail-spread.normalized()*1.5,color)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_1: view_index = 0
		KEY_2: view_index = 1
		KEY_3: view_index = 2

func _exit_tree() -> void:
	Engine.time_scale = 1.0
