extends "res://scripts/campfire.gd"
func _ready() -> void:
	super._ready()
	var pan:=preload("res://scripts/survival_item_visual.gd").create_pan()
	pan.position.y=.85;add_child(pan)
	var steel:=SURFACES.make(SURFACES.Kind.METAL,Color(.22,.24,.22),.65,.5)
	for index in 3:
		var angle:=float(index)*TAU/3
		var leg:=preload("res://scripts/machine_visual.gd").cylinder(self,Vector3(cos(angle)*.23,.43,sin(angle)*.23),.018,.83,steel)
		leg.rotation=Vector3(sin(angle)*.17,0,-cos(angle)*.17)
