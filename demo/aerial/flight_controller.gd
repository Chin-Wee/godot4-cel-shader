extends RefCounted

# The supplied Iron Man rig's velocity controller, in Godot's -Z-forward frame.
# Marvel's Iron Man VR is the production reference for momentum-led suit flight.
const Spring = preload("res://aerial/flight_pose.gd").Spring
const MODES := [&"manual",&"hover",&"cruise",&"boost",&"brake",&"bank_left",&"bank_right",&"figure8"]
const ACTION_KEYS := {
	"flight_forward":[KEY_W,KEY_UP],"flight_back":[KEY_S,KEY_DOWN],
	"flight_yaw_left":[KEY_A,KEY_LEFT],"flight_yaw_right":[KEY_D,KEY_RIGHT],
	"flight_strafe_left":[KEY_Q],"flight_strafe_right":[KEY_E],
	"flight_climb":[KEY_SPACE],"flight_descend":[KEY_C,KEY_CTRL],
	"flight_boost":[KEY_SHIFT],"flight_brake":[KEY_X],
}
var mode: StringName = &"manual"
var mode_time := 0.0
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var acceleration := Vector3.ZERO
var local_velocity := Vector3.ZERO # +X left, +Y up, +Z forward, like the reference.
var local_acceleration := Vector3.ZERO
var desired_acceleration := Vector3.ZERO
var required_force := Vector3.UP*9.81 # Force per unit mass.
var heading_yaw := 0.0
var yaw_rate := 0.0
var yaw_acceleration := 0.0
var boost_amount := 0.0
var brake_amount := 0.0
var climb_input := 0.0
var gaze_yaw := 0.0
var gaze_target := Vector3.ZERO
# The canyon uses a giant display model. Keep the reference's control/pose units
# separate from world travel distance so speed and spring tuning remain readable.
var distance_scale := 10.0
var model_scale := 50.0
var forward_input := Spring.new()
var strafe_input := Spring.new()
var vertical_input := Spring.new()
var turn_input := Spring.new()
var boost := Spring.new()
var brake := Spring.new()
var yaw := Spring.new()
var accel := Spring.new()
var gaze := Spring.new()

static func install_input_actions() -> void:
	for action in ACTION_KEYS:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		for key in ACTION_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action,event)

static func read_input() -> Dictionary:
	return {
		"forward":Input.get_axis("flight_back","flight_forward"),
		"strafe":Input.get_axis("flight_strafe_right","flight_strafe_left"),
		"vertical":Input.get_axis("flight_descend","flight_climb"),
		"turn":Input.get_axis("flight_yaw_right","flight_yaw_left"),
		"boost":Input.get_action_strength("flight_boost"),
		"brake":Input.get_action_strength("flight_brake"),
	}

func set_mode(value: StringName) -> void:
	assert(value in MODES,"Unknown flight mode")
	mode = value
	mode_time = 0.0

func reset(origin: Vector3, yaw_angle := 0.0) -> void:
	position = origin
	velocity = Vector3.ZERO
	acceleration = Vector3.ZERO
	local_acceleration = Vector3.ZERO
	local_velocity = Vector3.ZERO
	desired_acceleration = Vector3.ZERO
	heading_yaw = yaw_angle
	yaw_rate = 0.0
	yaw_acceleration = 0.0
	boost_amount = 0.0
	brake_amount = 0.0
	climb_input = 0.0
	mode_time = 0.0
	for spring in [forward_input,strafe_input,vertical_input,turn_input,boost,brake,yaw,accel]:
		spring.value = Vector3.ZERO
		spring.velocity = Vector3.ZERO
	gaze_yaw = heading_yaw
	gaze_target = position-Basis(Vector3.UP,heading_yaw).z*18.0*distance_scale+Vector3.UP*model_scale*0.5
	gaze.value = gaze_target
	gaze.velocity = Vector3.ZERO
	required_force = Vector3.UP*9.81

func advance(delta: float, controls: Dictionary, camera_yaw: float, floor_height := -INF) -> void:
	# Fixed small integration steps preserve the prototype's inertia at different
	# display rates. Pose springs and rendering are advanced separately.
	var remaining := delta
	while remaining > 0.000001:
		var step := minf(remaining,1.0/120.0)
		_step(step,controls,camera_yaw,floor_height)
		remaining -= step

func _step(delta: float, controls: Dictionary, camera_yaw: float, floor_height: float) -> void:
	mode_time += delta
	var raw := controls.duplicate() if mode == &"manual" else {}
	match mode:
		&"hover": raw = {"forward":sin(mode_time*0.75)*0.06,"strafe":cos(mode_time*0.55)*0.07,"vertical":sin(mode_time*1.15)*0.08}
		&"cruise": raw = {"forward":0.85,"turn":sin(mode_time*0.45)*0.28}
		&"boost": raw = {"forward":1.0,"boost":1.0,"turn":sin(mode_time*0.55)*0.22}
		&"brake": raw = {"forward":1.0,"boost":0.85} if fposmod(mode_time,5.4) < 3.2 else {"forward":-0.25,"brake":1.0}
		&"bank_left": raw = {"forward":0.92,"turn":0.88,"strafe":0.2}
		&"bank_right": raw = {"forward":0.92,"turn":-0.88,"strafe":-0.2}
		&"figure8": raw = {"forward":0.92,"boost":0.35+0.35*sin(mode_time*1.1),"turn":sin(mode_time*0.65)*1.05,"vertical":cos(mode_time*1.3)*0.28}
	var move_forward := forward_input.step(Vector3(raw.get("forward",0),0,0),delta,0.24).x
	var move_strafe := strafe_input.step(Vector3(raw.get("strafe",0),0,0),delta,0.26).x
	climb_input = vertical_input.step(Vector3(raw.get("vertical",0),0,0),delta,0.26).x
	var turn := turn_input.step(Vector3(raw.get("turn",0),0,0),delta,0.22).x
	boost_amount = boost.step(Vector3(raw.get("boost",0),0,0),delta,0.32).x
	brake_amount = brake.step(Vector3(raw.get("brake",0),0,0),delta,0.18).x
	var previous_yaw_rate := yaw_rate
	yaw_rate = yaw.step(Vector3(turn*1.85,0,0),delta,0.28).x
	yaw_acceleration = (yaw_rate-previous_yaw_rate)/delta
	heading_yaw = wrapf(heading_yaw+yaw_rate*delta,-PI,PI)
	var basis := Basis(Vector3.UP,heading_yaw)
	var forward := -basis.z
	var left := -basis.x
	var speed := lerpf(28.0,52.0,boost_amount)
	var target := forward*move_forward*speed+left*move_strafe*speed*0.5+Vector3.UP*climb_input*12.5
	target *= maxf(0.0,1.0-0.92*brake_amount)
	var coasting := absf(raw.get("forward",0.0)) < 0.05 and brake_amount < 0.05
	var gain := 4.2 if brake_amount > 0.1 else (1.35 if coasting else 2.1+boost_amount*1.4)
	var maximum := 38.0 if brake_amount > 0.1 else 30.0*(1.0+0.45*boost_amount)
	desired_acceleration = ((target-velocity)*gain).limit_length(maximum)
	var previous_velocity := velocity
	velocity = (velocity+desired_acceleration*delta)*pow(0.988,delta*60.0)
	position += velocity*delta*distance_scale
	# The reference's floor cushion now samples native canyon collision geometry.
	# ponytail: vertical cushion only; use swept collision for level gameplay.
	if position.y < floor_height+3.0*distance_scale:
		velocity.y += (floor_height+3.0*distance_scale-position.y)/distance_scale*12.0*delta
		if position.y < floor_height+2.2*distance_scale:
			position.y = floor_height+2.2*distance_scale
			if velocity.y < 0.0: velocity.y *= 0.2
	acceleration = (velocity-previous_velocity)/delta
	local_velocity = Vector3(velocity.dot(left),velocity.y,velocity.dot(forward))
	local_acceleration = accel.step(Vector3(acceleration.dot(left),acceleration.y,acceleration.dot(forward)),delta,0.22)
	required_force = desired_acceleration+Vector3.UP*9.81+velocity*1.4
	gaze_yaw = heading_yaw+yaw_rate*0.60
	if mode == &"manual": gaze_yaw += sin(camera_yaw-heading_yaw)*0.35
	var gaze_direction := -Basis(Vector3.UP,gaze_yaw).z
	var target_gaze := position+gaze_direction*18.0*distance_scale+Vector3.UP*(model_scale*0.5+climb_input*4.0*distance_scale)
	gaze_target = gaze.step(target_gaze,delta,0.20)
