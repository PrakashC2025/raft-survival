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
## Short CC0 recordings for action contacts; kept separate from footsteps so
## existing terrain selection and its surface variation remain unchanged.
const ACTION := {
	"body_impact": [preload("res://audio/contact/body_impact.wav")],
	"animal_snap": [preload("res://audio/contact/animal_snap.wav")],
	"bite": [preload("res://audio/contact/bite1.wav"),preload("res://audio/contact/bite2.wav"),preload("res://audio/contact/bite3.wav")],
	"water": [preload("res://audio/contact/water1.wav"),preload("res://audio/contact/water2.wav"),preload("res://audio/contact/water3.wav")],
	"entry": [preload("res://audio/contact/water_entry.wav")],
	"swim": [preload("res://audio/contact/swim_stroke.wav")], "bubble": [preload("res://audio/contact/bubbles.wav")],
	"cut_food": [preload("res://audio/contact/cut_food.wav")],
	"stir": [preload("res://audio/contact/stir1.wav"),preload("res://audio/contact/stir2.wav"),preload("res://audio/contact/stir3.wav")],
	"cloth": [preload("res://audio/contact/handle1.wav"),preload("res://audio/contact/handle2.wav")],
	"bandage": [preload("res://audio/contact/bandage.wav")], "unpack": [preload("res://audio/contact/unpack.wav")],
	"switch": [preload("res://audio/contact/switch.wav")], "battery": [preload("res://audio/contact/battery.wav")],
	"reel": [preload("res://audio/contact/reel.wav")], "anchor": [preload("res://audio/contact/anchor.wav")],
	"draw_tool": [preload("res://audio/contact/draw_tool.wav")],
	"door_open": [preload("res://audio/contact/door_open.wav")], "door_close": [preload("res://audio/contact/door_close.wav")],
	"swing": [preload("res://audio/contact/swing1.wav"),preload("res://audio/contact/swing2.wav")],
	"fire_loop": [preload("res://audio/contact/fire_loop.wav")],
	"boil_loop": [preload("res://audio/contact/boil_loop.wav")], "cook_loop": [preload("res://audio/contact/cook_loop.wav")],
	"rain_loop": [preload("res://audio/contact/rain_loop.wav")], "underwater_loop": [preload("res://audio/contact/underwater_loop.wav")],
	"radio_send": [preload("res://audio/contact/radio_send.wav")], "radio_receive": [preload("res://audio/contact/radio_receive.wav")]
}
static var _last: Dictionary = {}
static var _action_last: Dictionary = {}
static func pick(surface: String) -> AudioStream:
	var options: Array=BANK.get(surface,BANK.wood)
	var previous: int=int(_last.get(surface,-1))
	var index:=randi_range(0,options.size()-1)
	if index==previous and options.size()>1:index=(index+randi_range(1,options.size()-1))%options.size()
	_last[surface]=index
	return options[index]

static func pick_action(action: String) -> AudioStream:
	var options: Array=ACTION.get(action,[])
	if options.is_empty():return pick("cloth")
	var previous: int=int(_action_last.get(action,-1))
	var index:=randi_range(0,options.size()-1)
	if index==previous and options.size()>1:index=(index+randi_range(1,options.size()-1))%options.size()
	_action_last[action]=index
	return options[index]
