extends Node
## Original synthesized audio; no third-party recordings or runtime downloads.
var sounds: Dictionary = {}
var ambience: AudioStreamPlayer
var effects: Array[AudioStreamPlayer] = []
var muted := false
var step_clock := 0.0
var bird_clock := 7.0

func _ready() -> void:
	for kind in ["ocean", "step", "splash", "craft", "bow", "impact", "bird", "quake", "rescue"]:
		sounds[kind] = _synthesize(kind)
	ambience = AudioStreamPlayer.new()
	ambience.stream = sounds.ocean
	ambience.volume_db = -18.0
	add_child(ambience)
	ambience.play()
	for i in range(6):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -13.0
		add_child(voice)
		effects.append(voice)

func play(kind: String) -> void:
	if muted or not sounds.has(kind):
		return
	for voice in effects:
		if not voice.playing:
			voice.stream = sounds[kind]
			voice.pitch_scale = randf_range(0.94, 1.06)
			voice.play()
			return

func set_muted(value: bool) -> void:
	muted = value
	ambience.volume_db = -80.0 if muted else -18.0
	if muted:
		for voice in effects:
			voice.stop()

func tick(delta: float, player: CharacterBody3D, submerged: bool) -> void:
	if not muted:
		ambience.volume_db = -25.0 if submerged else -18.0
	step_clock -= delta
	if player.velocity.length() > 1.0 and step_clock <= 0.0:
		if player.is_on_floor() or player.get("is_swimming"):
			play("splash" if player.get("is_swimming") else "step")
			step_clock = 0.65 if player.get("is_swimming") else 0.42
	bird_clock -= delta
	if bird_clock <= 0.0:
		bird_clock = randf_range(12.0, 24.0)
		play("bird")

func _synthesize(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var duration := 8.0 if kind == "ocean" else (3.0 if kind == "quake" else 0.45)
	var size := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(size * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var low := 0.0
	for i in range(size):
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.04)
		var envelope := sin(PI * float(i) / size)
		var value := 0.0
		match kind:
			"ocean": value = low * (0.7 + 0.3 * sin(TAU * t / 8.0)) + noise * 0.025
			"quake": value = low * 2.5 + sin(TAU * 36.0 * t) * 0.12
			"step": value = noise * exp(-t * 26.0) * 0.5
			"splash": value = noise * exp(-t * 9.0) * 0.3 + low
			"bow": value = sin(TAU * (180.0 * t - 120.0 * t * t)) * exp(-t * 15.0)
			"bird": value = sin(TAU * (1600.0 * t + 300.0 * t * t)) * pow(sin(PI * t / duration), 4.0) * 0.2
			"craft": value = sin(TAU * 700.0 * t) * exp(-t * 18.0) + noise * exp(-t * 40.0)
			"rescue": value = (sin(TAU * 440.0 * t) + sin(TAU * 660.0 * t)) * 0.25
			_: value = low * 2.0 * exp(-t * 10.0)
		# Fade loop endpoints to zero to prevent a discontinuity click.
		var fade := minf(1.0, minf(t * 10.0, (duration - t) * 10.0)) if kind == "ocean" else envelope
		bytes.encode_s16(i * 2, int(clampf(value * fade, -0.95, 0.95) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	if kind == "ocean":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = size
	return stream
