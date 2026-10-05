extends RefCounted
## Original quiet fire bed, cached PCM. Existing waves/footsteps are recordings.
static var _fire: AudioStreamWAV
static func fire_stream() -> AudioStreamWAV:
	if _fire != null: return _fire
	var rng := RandomNumberGenerator.new()
	rng.seed = 61273
	var bytes := PackedByteArray()
	var samples := 33075
	bytes.resize(samples*2)
	var bed := 0.0
	var crackle := 0.0
	for index in range(samples):
		bed = lerpf(bed,rng.randf_range(-1,1),0.09)
		if rng.randf() < 0.0015: crackle = rng.randf_range(0.2,0.65)
		crackle *= 0.91
		var seam := minf(1,minf(float(index)/150,float(samples-index)/150))
		var sample := (bed*0.35+rng.randf_range(-1,1)*crackle)*seam
		bytes.encode_s16(index*2,int(clampf(sample,-1,1)*32767))
	_fire = AudioStreamWAV.new()
	_fire.format = AudioStreamWAV.FORMAT_16_BITS
	_fire.mix_rate = 11025
	_fire.data = bytes
	_fire.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_fire.loop_end = samples
	return _fire
