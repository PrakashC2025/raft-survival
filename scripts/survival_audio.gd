extends RefCounted
## Small pre-imported CC0 loops. Decoding or sound generation never runs at
## fire ignition, station activation or other gameplay contacts.
const CONTACT := preload("res://scripts/contact_audio.gd")
static var _fire: AudioStreamWAV
static func electronic_stream(kind: String) -> AudioStream:
	return CONTACT.pick_action(kind if CONTACT.ACTION.has(kind) else "switch")
static func fire_stream() -> AudioStreamWAV:
	if _fire != null:return _fire
	_fire=CONTACT.ACTION.fire_loop[0].duplicate() as AudioStreamWAV
	_fire.loop_mode=AudioStreamWAV.LOOP_FORWARD
	_fire.loop_begin=0
	_fire.loop_end=floori(float(_fire.data.size())/2.0)
	return _fire
