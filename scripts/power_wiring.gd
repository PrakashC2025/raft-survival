extends Node
## Select two real terminals using held Wire. Power follows this saved cable only.
var player: CharacterBody3D
var source: Node3D
func _ready() -> void:player=get_parent() as CharacterBody3D
func target() -> Node3D:
	var body:=player.aim_collider as Node3D
	if not player.aim_valid or not is_instance_valid(body) or player.global_position.distance_to(player.aim_point)>3.5:return null
	if not body.has_method("request_power") or body.machine_type not in body.ELECTRICAL:return null
	return body
func caption() -> String:
	var body:=target()
	if body==null:return ""
	if body.machine_type=="WindGenerator":return "START WIRE"
	return "CONNECT WIRE" if is_instance_valid(source) else "SELECT GENERATOR FIRST"
func use() -> void:
	var body:=target()
	if body==null:return
	if body.machine_type=="WindGenerator":
		source=body;player.call("_hud_toast","WIRE STARTED · AIM AT YOUR LED, PUMP OR RADIO TO CONNECT");return
	if not is_instance_valid(source) or source.is_queued_for_deletion():player.call("_hud_toast","AIM AT THE GENERATOR WITH WIRE FIRST");return
	var length:=source.global_position.distance_to(body.global_position)
	if length>12:player.call("_hud_toast","CABLE TOO LONG · PLACE EQUIPMENT WITHIN 12 METRES");return
	if not body.wired_source.is_empty():player.call("_hud_toast","ALREADY WIRED · REMOVE THE EQUIPMENT TO RECOVER ITS CABLE");return
	var count:=maxi(1,ceili(length/2))
	if not Inventory.try_exchange({"Wire":count},{}):player.call("_hud_toast","CONNECTING NEEDS %d WIRE · ONE PER TWO METRES"%count);return
	body.wired_source=source.machine_id
	var original: Dictionary=player.RECIPE_REFUND.get(player._piece_name_from_node(body),{})
	var cost: Dictionary=body.get_meta("construction_cost",original).duplicate();cost.Wire=int(cost.get("Wire",0))+count;body.set_meta("construction_cost",cost)
	body.call("_refresh_cable")
	player.call("play_action","install",.9,body.global_position,"Wire")
	player.call("_hud_toast","CABLE CONNECTED · %d WIRE USED"%count);player.call("_queue_save");source=null
