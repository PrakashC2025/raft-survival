extends RefCounted
## Original quiet fire bed, cached PCM. Existing waves/footsteps are recordings.
static var _fire: AudioStreamWAV
static var _electronics: Dictionary = {}
static func electronic_stream(kind: String) -> AudioStreamWAV:
	if _electronics.has(kind):return _electronics[kind]
	var duration:=0.12 if kind=="switch" else (0.38 if kind=="battery" else 1.3)
	var samples:=int(duration*22050)
	var bytes:=PackedByteArray();bytes.resize(samples*2)
	var rng:=RandomNumberGenerator.new();rng.seed=kind.hash()
	for index in samples:
		var t:=float(index)/22050.0
		var envelope:=minf(1.0,t*100.0)*minf(1.0,(duration-t)*60.0)
		var value:=0.0
		if kind in ["switch","battery"]:
			value=rng.randf_range(-1,1)*exp(-t*65.0)*0.6
			if kind=="battery" and t>0.22:value+=rng.randf_range(-1,1)*exp(-(t-0.22)*80.0)*0.4
		else:
			var frequency:=880.0 if kind=="radio_send" else 660.0
			var beep:=t<0.16 or (t>0.24 and t<0.39)
			value=sin(t*TAU*frequency)*0.22 if beep else rng.randf_range(-1,1)*0.11*(0.5+0.5*sin(t*TAU*13.0))
		bytes.encode_s16(index*2,int(clampf(value*envelope,-1,1)*32767))
	var sound:=AudioStreamWAV.new();sound.format=AudioStreamWAV.FORMAT_16_BITS;sound.mix_rate=22050;sound.data=bytes
	_electronics[kind]=sound
	return sound
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
