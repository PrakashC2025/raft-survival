extends StaticBody3D
var _cooldown := 0.0
func _ready() -> void: add_to_group("seabed")
func _process(delta: float) -> void: _cooldown=maxf(0,_cooldown-delta)
func interaction_caption() -> String: return "COLLECT SAND"
func interact_survival(actor: Node3D) -> void:
	if _cooldown>0 or not actor.is_swimming or actor.aim_point.distance_to(actor.camera.global_position)>3.5:return
	if Inventory.try_exchange({},{"Sand":1}):
		_cooldown=.8;Inventory.pickup_received.emit("Sand",1);actor.call("play_action","scoop",.8,actor.aim_point);actor.call("_queue_save")
	else:actor.call("_hud_toast","BAG FULL")
