extends RefCounted
## Cached original synthesized sounds: a timber hammer impact and short saw scrape.
static var _sounds: Dictionary = {}
static func build_sound(piece: String) -> AudioStreamWAV:
	var saw := piece in ["Wall", "Roof", "Window"]
	var key := "saw" if saw else "hammer"
	if _sounds.has(key):
		return _sounds[key]
	var sample_rate := 22050
	var count := int(sample_rate * (0.24 if saw else 0.18))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 70921
	for index in count:
		var t := float(index) / sample_rate
		var noise := random.randf_range(-1.0, 1.0)
		var amplitude := exp(-t * (13.0 if saw else 28.0))
		var value := (noise * 0.35 + sin(t*TAU*(460.0 if saw else 175.0))*0.42)*amplitude
		if saw:
			value *= 0.6 + sin(t*TAU*43.0)*0.4
		bytes.encode_s16(index*2, int(clampf(value,-1,1)*23000))
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = sample_rate
	audio.data = bytes
	_sounds[key] = audio
	return audio
