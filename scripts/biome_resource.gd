extends StaticBody3D
## Finite deposits and regrowing winter trees with stable saved IDs.
var required_tool := "Pickaxe"
var health := 4
var resource_id := ""
var rewards := {"Stone":4,"Metal":2}
var visual: Node3D
var _cooldown := 0.0
var regrow_wait := 360.0
var growth := 1.0
var _fall_tween: Tween

func _ready() -> void:
	add_to_group("biome_resource")
	var saved: Dictionary = Inventory.loaded_meta.get("biome_resources",{})
	health=clampi(int(saved.get(resource_id,4)),0,4)
	if health==0:hide();collision_layer=0
	if required_tool=="Axe":
		var forest:Dictionary=Inventory.loaded_meta.get("biome_tree_growth",{}).get(resource_id,{})
		regrow_wait=clampf(float(forest.get("wait",360)),0,360)
		growth=clampf(float(forest.get("growth",0.0 if health==0 else 1.0)),0,1)
		if health>0 and growth<1:
			if visual!=null:visual.scale=Vector3.ONE*growth
			collision_layer=0
	set_process(false)

func interaction_caption() -> String:
	return ("CHOP TREE" if required_tool=="Axe" else "MINE DEPOSIT")+" %d/4"%(4-health)

func interact_survival(actor: Node3D) -> void:
	if actor.get("active_item")!=required_tool:
		actor.call("_hud_toast","EQUIP "+required_tool.to_upper());return
	actor.get_node("SurvivalTools").call("use")

func tool_hit(actor: Node3D,item: String) -> bool:
	if health<=0 or growth<1 or item!=required_tool or not Inventory.has(item,1) or actor.global_position.distance_to(global_position)>4.5 \
		or Time.get_ticks_msec()<int(_cooldown):return false
	var damage := 2 if item=="Axe" else 1
	if health<=damage and not Inventory.can_store_rewards(rewards):
		actor.call("_hud_toast","BAG FULL - CLEAR SPACE TO COLLECT");return false
	if health<=damage and not Inventory.try_exchange({},rewards):return false
	_cooldown=float(Time.get_ticks_msec()+500)
	health=maxi(0,health-damage)
	actor.call("play_world_sfx",preload("res://audio/chop.ogg") if item=="Axe" else preload("res://audio/footstep_gravel.ogg"),-9.0)
	if health==0:
		if item=="Axe":regrow_wait=360;growth=0
		for reward in rewards:Inventory.pickup_received.emit(reward,int(rewards[reward]))
		collision_layer=0
		if item=="Axe" and is_instance_valid(visual):
			_fall_tween = create_tween();_fall_tween.tween_property(visual,"rotation:z",1.4,.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_fall_tween.tween_callback(hide)
		else:hide()
	elif is_instance_valid(visual):
		visual.position.x=.035
		create_tween().tween_property(visual,"position:x",0.0,.15)
	actor.call("_queue_save")
	return true

func tree_growth_state() -> Dictionary:return {"wait":regrow_wait,"growth":growth}

func advance_tree(seconds: float) -> void:
	if required_tool!="Axe" or (health>0 and growth>=1):return
	if health==0:
		regrow_wait=maxf(0,regrow_wait-seconds)
		if regrow_wait>0:return
	var actor:=get_tree().get_first_node_in_group("player") as Node3D
	if actor!=null and actor.global_position.distance_squared_to(global_position+Vector3.UP)<.8*.8:return
	# A planted crop owns this clearing until it is harvested/removed.
	for plot in get_tree().get_nodes_in_group("ground_plot"):
		if plot.is_queued_for_deletion() or not plot.has_plant():continue
		var distance_value:=Vector2(plot.global_position.x-global_position.x,plot.global_position.z-global_position.z).length()
		if distance_value<2.0:
			if health>0:health=0;growth=0;collision_layer=0;hide()
			return
	if health==0:
		if _fall_tween!=null and _fall_tween.is_valid():_fall_tween.kill()
		health=4;growth=.02;show()
		if visual!=null:visual.rotation=Vector3.ZERO;visual.position=Vector3.ZERO
	growth=minf(1.0,growth+maxf(0,seconds)/30.0)
	if visual!=null:visual.scale=Vector3.ONE*growth
	if growth>=1:collision_layer=1
