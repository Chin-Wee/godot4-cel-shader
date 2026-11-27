extends Node3D

const AerialMech = preload("res://aerial/aerial_mech.gd")
const MIX_RATE := 22050.0

var subject: AerialMech
var engine_player: AudioStreamPlayer3D
var impact_player: AudioStreamPlayer3D
var engine_playback: AudioStreamGeneratorPlayback
var impact_playback: AudioStreamGeneratorPlayback
var engine_phase := 0.0
var impact_age := 1.0
var impact_strength := 0.0
var last_impact_signal := 0.0
var low_noise := 0.0

func _ready() -> void:
	engine_player = _make_player("EngineBed",-12.0,2400.0,42.0)
	impact_player = _make_player("StructuralImpact",-8.0,1800.0,34.0)
	engine_playback = engine_player.get_stream_playback() as AudioStreamGeneratorPlayback
	impact_playback = impact_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _make_player(player_name: String, volume: float, max_distance: float, unit_size: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.volume_db = volume
	player.max_distance = max_distance
	player.unit_size = unit_size
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.20
	player.stream = stream
	add_child(player)
	player.play()
	return player

func _process(delta: float) -> void:
	if not is_instance_valid(subject):
		return
	var controller = subject.controller
	var active: bool = subject.simulation_enabled
	var speed: float = controller.velocity.length() if active else 0.0
	var throttle: float = clampf(controller.thrust_level / 4.0, 0.0, 1.0) if active else 0.0
	var wind: float = smoothstep(8.0, 100.0, speed)
	var load: float = clampf((controller.g_load - 1.0) / 2.0, 0.0, 1.0) if active else 0.0
	var impact_signal: float = clampf((controller.jerk.length() - 35.0) / 125.0, 0.0, 1.0) if active else 0.0
	if impact_signal > 0.18 and impact_signal > last_impact_signal + 0.045:
		impact_strength = maxf(impact_strength, impact_signal)
		impact_age = 0.0
	last_impact_signal = lerpf(last_impact_signal, impact_signal, 1.0 - exp(-delta / 0.12))
	_fill_engine(throttle, wind, load)
	_fill_impact()

func _fill_engine(throttle: float, wind: float, load: float) -> void:
	if not is_instance_valid(engine_playback):
		engine_playback = engine_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if not is_instance_valid(engine_playback): return
	var frames := engine_playback.get_frames_available()
	var frequency := 34.0 + throttle * 64.0 + load * 18.0
	var idle := 0.035 * float(subject.simulation_enabled and subject.controller.detent > 0)
	while frames > 0:
		var noise := _noise(engine_phase * 1.73)
		low_noise = lerpf(low_noise, noise, 0.018)
		var rumble := sin(TAU * engine_phase * frequency) * 0.18
		rumble += sin(TAU * engine_phase * frequency * 2.13) * 0.07
		rumble += low_noise * 0.14
		var airflow := (noise - low_noise) * wind * 0.12
		var sample := clampf(rumble * sqrt(throttle) + airflow + idle, -0.75, 0.75)
		engine_playback.push_frame(Vector2(sample, sample))
		engine_phase += 1.0 / MIX_RATE
		frames -= 1

func _fill_impact() -> void:
	if not is_instance_valid(impact_playback):
		impact_playback = impact_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if not is_instance_valid(impact_playback): return
	var frames := impact_playback.get_frames_available()
	while frames > 0:
		var envelope := exp(-impact_age * 22.0)
		var ring := sin(TAU * (68.0 + impact_strength * 38.0) * impact_age) * 0.55
		var grit := _noise(impact_age * 3900.0 + 17.0) * 0.45
		var sample := (ring + grit) * envelope * impact_strength * 0.48
		impact_playback.push_frame(Vector2(sample, sample))
		impact_age += 1.0 / MIX_RATE
		frames -= 1
	if impact_age > 0.42:
		impact_strength = 0.0

func _noise(time_value: float) -> float:
	var value := sin(time_value * 12.9898 + 78.233) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0
