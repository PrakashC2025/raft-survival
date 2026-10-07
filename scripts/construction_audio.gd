extends RefCounted
## Reuse the included CC0 timber impact; no electronic sine-wave build tone.
const TIMBER_IMPACT: AudioStream = preload("res://audio/chop.ogg")
static func build_sound(_piece: String) -> AudioStream:
	return TIMBER_IMPACT
