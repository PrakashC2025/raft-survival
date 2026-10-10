extends RefCounted
## Original lobby/settings theme; gameplay HUD keeps its existing theme.
const AQUA := Color("64e3d5")
const TEXT := Color("eef8fa")
const MUTED := Color("94b8c4")
static var _theme: Theme

static func scale_for(viewport: Viewport) -> float:
	return maxf(1.0,1.0/maxf(viewport.get_stretch_transform().get_scale().x,0.1))

static func box(color: Color, border: Color=Color.TRANSPARENT, radius: int=14) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color;style.border_color=border
	style.set_corner_radius_all(radius);style.set_border_width_all(1 if border.a>0 else 0)
	style.set_content_margin_all(14);style.anti_aliasing=true
	return style

static func theme() -> Theme:
	if _theme!=null:return _theme
	_theme=Theme.new();_theme.default_font_size=18
	_theme.set_color("font_color","Label",TEXT)
	for control in ["Button","OptionButton","CheckButton","SpinBox","LineEdit"]:
		_theme.set_color("font_color",control,TEXT)
		_theme.set_color("font_hover_color",control,TEXT)
		_theme.set_color("font_pressed_color",control,AQUA)
		_theme.set_stylebox("normal",control,box(Color("123344"),Color("2a5464")))
		_theme.set_stylebox("hover",control,box(Color("1b4958"),AQUA.darkened(.35)))
		_theme.set_stylebox("pressed",control,box(Color("0d535a"),AQUA))
		_theme.set_stylebox("disabled",control,box(Color("142d3a")))
		var focus:=box(Color.TRANSPARENT,AQUA);focus.set_border_width_all(2)
		_theme.set_stylebox("focus",control,focus)
	_theme.set_stylebox("panel","PopupMenu",box(Color("0c2736"),Color("386274")))
	_theme.set_color("font_color","PopupMenu",TEXT)
	_theme.set_stylebox("hover","PopupMenu",box(Color("1b4958")))
	for state in ["tab_unselected","tab_selected","tab_hovered"]:
		var style:=box(Color("12434e") if state=="tab_selected" else Color("0d2636"),Color.TRANSPARENT,8)
		style.content_margin_left=12;style.content_margin_right=12
		style.content_margin_top=12;style.content_margin_bottom=12
		if state=="tab_selected":style.border_color=AQUA;style.border_width_bottom=2
		_theme.set_stylebox(state,"TabContainer",style)
	_theme.set_stylebox("panel","TabContainer",box(Color.TRANSPARENT,Color.TRANSPARENT,0))
	_theme.set_color("font_selected_color","TabContainer",AQUA)
	_theme.set_color("font_unselected_color","TabContainer",MUTED)
	_theme.set_font_size("font_size","TabContainer",15)
	for key in ["slider","grabber_area","grabber_area_highlight"]:
		var track:=box(AQUA if key!="slider" else Color("284a59"),Color.TRANSPARENT,4)
		track.set_content_margin_all(3)
		_theme.set_stylebox(key,"HSlider",track)
	_theme.set_color("grabber_color","HSlider",AQUA)
	_theme.set_color("grabber_highlight_color","HSlider",TEXT)
	return _theme
