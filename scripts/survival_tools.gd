extends Node
## Tools use existing HAND/E ownership. Rewards commit at the contact pose;
## changing tool, target, reach, life or modal state cancels without a reward.
const VISUAL := preload("res://scripts/survival_tool_visual.gd")
var player: CharacterBody3D
var pending: Dictionary = {}
var cooldown := 0.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	player=get_parent() as CharacterBody3D

func blocked() -> bool:
	var hud := player.get_node_or_null("CanvasLayer/SurvivalHUD")
	return get_tree().paused or GameSettings.is_open or Stats.health<=0 or player.build_mode \
		or is_instance_valid(player.get("_editing")) or (hud!=null and hud.call("gameplay_input_blocked")) \
		or player.get_node("SurvivalServices").call("busy")

func _raft() -> Node3D:
	var raft := get_tree().get_first_node_in_group("raft") as Node3D
	if raft==null or player.is_swimming or not player.is_on_floor(): return null
	# A short ray must hit this compound raft; a nearby beach is not aboard.
	var query := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*.1,player.global_position+Vector3.DOWN*1.8,1,[player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():return null
	var body := hit.collider as Node
	while body!=null:
		if body==raft:return raft
		body=body.get_parent()
	return null

func target() -> Node3D:
	if player.active_item=="Spear":
		var animal: Node3D=player.call("_get_aimed_shark")
		return animal if animal!=null and player.aim_distance<=5.2 and animal.global_position.distance_to(player.camera.global_position)<5.5 else null
	if not player.aim_valid or not is_instance_valid(player.aim_collider) or player.aim_distance>3.5:return null
	var node := player.aim_collider as Node
	while node!=null:
		if node.has_method("tool_hit") and str(node.get("required_tool")) in VISUAL.ITEMS:return node as Node3D
		node=node.get_parent()
	return null

func caption() -> String:
	var item := str(player.active_item)
	if item=="Spear":
		var animal:=target()
		return "HUNT "+str(animal.get("species")).to_upper() if animal!=null and "species" in animal else "STRIKE"
	if item=="Paddle":return "ROW"
	if item=="Anchor":
		var raft := get_tree().get_first_node_in_group("raft")
		return "RAISE ANCHOR" if raft!=null and raft.anchored else "DROP ANCHOR"
	if item=="Shovel":return "DIG SOIL" if player.aim_point.y>1 else "DIG SAND"
	var deposit := target()
	if deposit!=null:return deposit.call("interaction_caption")
	return "CHOP" if item=="Axe" else "MINE"

func can_use() -> bool:
	if blocked() or cooldown>0 or not pending.is_empty() or not Inventory.has(player.active_item,1):return false
	match str(player.active_item):
		"Spear": return target()!=null
		"Paddle":
			var raft := _raft()
			return raft!=null and not raft.anchored and player.get_node("SurvivalProgression").stamina>=6
		"Anchor":return _raft()!=null
		"Shovel":return _shovel_hit()
		"Pickaxe","Axe":
			var deposit := target()
			return deposit!=null and deposit.required_tool==player.active_item and deposit.health>0
	return false

func _shovel_hit() -> bool:
	return (player.call("_is_sand_surface_hit") and not player.is_swimming) or (player.aim_valid and is_instance_valid(player.aim_collider) and player.aim_collider.is_in_group("seabed") and player.aim_distance<=3.5)

func use() -> bool:
	if not can_use():return false
	var item := str(player.active_item)
	var seconds := 1.1 if item=="Paddle" else .85
	var camera := player.camera as Camera3D
	var direction := -camera.global_basis.z;direction.y=0
	if direction.length_squared()<.01:direction=-player.global_basis.z
	pending={"item":item,"age":0.0,"duration":seconds,"at":player.aim_point,"target":target(),
		"raft":_raft() if item in ["Paddle","Anchor"] else null,"direction":direction.normalized(),"committed":false,
		"damage":Stats.damage_revision,"ground":player.aim_collider if item=="Shovel" else null}
	cooldown=seconds
	player.call("play_action",{"Axe":"chop","Pickaxe":"mine","Shovel":"dig","Paddle":"paddle","Anchor":"anchor","Spear":"strike"}[item],seconds,player.aim_point)
	return true

func cancel() -> void:
	if pending.is_empty():return
	pending.clear()
	player.get_node("SurvivalAction").call("stop")

func advance(delta: float) -> void:
	cooldown=maxf(0,cooldown-delta)
	if pending.is_empty():return
	if blocked() or player.active_item!=pending.item or not Inventory.has(pending.item,1) or Stats.damage_revision!=int(pending.damage):cancel();return
	pending.age=float(pending.age)+delta
	if bool(pending.committed):
		if float(pending.age)>=float(pending.duration):pending.clear()
		return
	var valid := true
	if pending.item in ["Paddle","Anchor"]:valid=is_instance_valid(pending.raft) and _raft()==pending.raft
	elif pending.item=="Shovel":
		valid=is_instance_valid(pending.ground) and player.aim_collider==pending.ground and _shovel_hit() \
			and player.aim_point.distance_squared_to(pending.at)<1.0
	else:valid=is_instance_valid(pending.target) and target()==pending.target
	if not valid:cancel();return
	if float(pending.age)<float(pending.duration)*.57:return
	pending.committed=true
	match str(pending.item):
		"Spear": pending.target.call("take_damage",38.0,player)
		"Shovel":
			var item := "Soil" if Vector3(pending.at).y>1 else "Sand"
			if Inventory.try_exchange({},{item:3}):
				Inventory.notify_pickup(item,3);player.call("_hud_toast",item.to_upper()+" +3")
			else:player.call("_hud_toast","BAG FULL")
		"Paddle":
			var progress := player.get_node("SurvivalProgression")
			if progress.stamina>=6 and pending.raft.call("paddle_stroke",pending.direction):progress.stamina-=6
		"Anchor":
			pending.raft.call("set_anchored",not pending.raft.anchored)
			player.call("_hud_toast","ANCHOR DOWN" if pending.raft.anchored else "ANCHOR RAISED")
		_:pending.target.call("tool_hit",player,str(pending.item))
	player.call("_queue_save")

func _physics_process(delta: float) -> void:
	if get_tree().paused:cancel();return
	advance(delta)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:cancel()
