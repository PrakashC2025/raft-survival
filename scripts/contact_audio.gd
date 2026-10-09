extends RefCounted
## Preloaded CC0 recordings; no decoding or sound generation at contact time.
const BANK := {
	"wood": [preload("res://audio/contact/wood1.wav"),preload("res://audio/contact/wood2.wav"),preload("res://audio/contact/wood3.wav")],
	"sand": [preload("res://audio/contact/sand1.wav"),preload("res://audio/contact/sand2.wav")],
	"grass": [preload("res://audio/contact/grass1.wav"),preload("res://audio/contact/grass2.wav"),preload("res://audio/contact/grass3.wav")],
	"snow": [preload("res://audio/contact/snow1.wav"),preload("res://audio/contact/snow2.wav"),preload("res://audio/contact/snow3.wav")],
	"stone": [preload("res://audio/contact/stone1.wav"),preload("res://audio/contact/stone2.wav"),preload("res://audio/contact/stone3.wav")],
	"metal": [preload("res://audio/contact/metal1.wav"),preload("res://audio/contact/metal2.wav"),preload("res://audio/contact/metal3.wav")],
	"casing": [preload("res://audio/contact/casing1.wav"),preload("res://audio/contact/casing2.wav"),preload("res://audio/contact/casing3.wav")],
	"cloth": [preload("res://audio/contact/cloth.wav")],
	"hammer": [preload("res://audio/contact/hammer.wav")]
}
static var _last: Dictionary = {}
static func pick(surface: String) -> AudioStream:
	var options: Array=BANK.get(surface,BANK.wood)
	var previous: int=int(_last.get(surface,-1))
	var index:=randi_range(0,options.size()-1)
	if index==previous and options.size()>1:index=(index+randi_range(1,options.size()-1))%options.size()
	_last[surface]=index
	return options[index]
