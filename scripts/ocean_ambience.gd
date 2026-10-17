extends AudioStreamPlayer

## Recorded waves, original wind/leaf beds and underwater filtering. One
## scene-owned bus feeds Master, preserving the existing volume/mute setting.
const OCEAN_STREAM: AudioStream = preload("res://audio/ocean_ambience.mp3")
const WIND_STREAM: AudioStreamWAV = preload("res://audio/sea_wind.wav")
const FOLIAGE_STREAM: AudioStreamWAV = preload("res://audio/foliage_rustle.wav")

var _wind: AudioStreamPlayer
var _foliage: AudioStreamPlayer
var _underwater: AudioStreamPlayer
var _low_pass: AudioEffectLowPassFilter
var _bus_name: StringName
var _ocean: Node3D
var _rain: Node
var _islands: Array[Node] = []
var _shore_mix := 0.0
var _under_mix := 0.0
var _context_timer := 0.0
var _elapsed := 0.0

func _ready() -> void:
	stream = OCEAN_STREAM
	var mp3 := stream as AudioStreamMP3
	if mp3 != null:
		mp3.loop = true
	volume_db = -20.0
	_bus_name = StringName("OceanEnvironment_%d" % get_instance_id())
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, _bus_name)
	AudioServer.set_bus_send(bus_index, &"Master")
	_low_pass = AudioEffectLowPassFilter.new()
	_low_pass.cutoff_hz = 18000.0
	_low_pass.resonance = 0.1
	AudioServer.add_bus_effect(bus_index, _low_pass)
	bus = _bus_name
	_wind = _make_layer("SeaWind", WIND_STREAM, -32.0)
	_foliage = _make_layer("FoliageRustle", FOLIAGE_STREAM, -80.0)
	_underwater = _make_layer("UnderwaterBubbles",preload("res://audio/contact/underwater_loop.wav"),-80.0)
	_ocean = get_tree().get_first_node_in_group("ocean") as Node3D
	_islands = get_tree().get_nodes_in_group("island")
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		_rain = player.get_node_or_null("RainSystem")
		if _rain != null:
			var rain_audio := _rain.get_node_or_null("RainAudio") as AudioStreamPlayer
			if rain_audio != null:
				rain_audio.bus = _bus_name
	play()


func _make_layer(label: String, source: AudioStreamWAV, level: float) -> AudioStreamPlayer:
	var layer := AudioStreamPlayer.new()
	layer.name = label
	var looping := source.duplicate() as AudioStreamWAV
	looping.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looping.loop_begin = 0
	looping.loop_end = int(looping.get_length() * looping.mix_rate)
	layer.stream = looping
	layer.volume_db = level
	layer.bus = _bus_name
	add_child(layer)
	layer.play()
	return layer


func _process(delta: float) -> void:
	_elapsed += delta
	_context_timer -= delta
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if _context_timer <= 0.0:
		_context_timer = 0.15
		_shore_mix = shoreline_factor(camera.global_position)
	var depth := 0.0
	if is_instance_valid(_ocean):
		depth = float(_ocean.call("get_height", camera.global_position)) - camera.global_position.y
	var smoothing := 1.0 - exp(-delta * 3.0)
	_under_mix = lerpf(_under_mix, smoothstep(0.08, 0.85, depth), smoothing)
	var rain_amount := 0.0
	if is_instance_valid(_rain):
		rain_amount = maxf(clampf(float(_rain.get("_intensity")), 0.0, 1.0),float(_rain.call("sky_storm_strength"))*.7)
	var swell := sin(_elapsed * 0.48) * 0.7 + sin(_elapsed * 0.17 + 1.3) * 0.4
	volume_db = lerpf(volume_db, -20.0 + _shore_mix * 5.0 + swell - _under_mix * 5.0, smoothing)
	_wind.volume_db = lerpf(_wind.volume_db, -32.0 + rain_amount * 5.0 - _under_mix * 20.0, smoothing)
	var leaf_target := linear_to_db(maxf(_shore_mix * (1.0 - _under_mix) * 0.08, 0.0001))
	_foliage.volume_db = lerpf(_foliage.volume_db, leaf_target, smoothing)
	# Fade amplitude so even shallow dives are audible; dB interpolation from
	# -80 kept most of the transition effectively silent on small speakers.
	_underwater.volume_db=linear_to_db(maxf(.25*_under_mix,.0001))
	_low_pass.cutoff_hz = lerpf(18000.0, 850.0, _under_mix)


func shoreline_factor(listener: Vector3) -> float:
	var nearest := INF
	for island in _islands:
		if is_instance_valid(island) and island is Node3D:
			var offset := listener - (island as Node3D).global_position
			nearest = minf(nearest, Vector2(offset.x, offset.z).length())
	return 1.0 - smoothstep(20.0, 65.0, nearest)


func stop_environment() -> void:
	set_process(false)
	stop()
	if is_instance_valid(_wind):
		_wind.stop()
	if is_instance_valid(_foliage):
		_foliage.stop()
	if is_instance_valid(_underwater):
		_underwater.stop()
	if is_instance_valid(_rain):
		var rain_audio := _rain.get_node_or_null("RainAudio") as AudioStreamPlayer
		if rain_audio != null:
			rain_audio.stop()
			rain_audio.bus = &"Master"


func _exit_tree() -> void:
	stop_environment()
	var bus_index := AudioServer.get_bus_index(_bus_name)
	if bus_index > 0:
		AudioServer.remove_bus(bus_index)
