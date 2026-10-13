extends Node
## Ignition/mounting commit at hand contact, with no cost on interruption.
var player: CharacterBody3D
var pending: Dictionary = {}
func _ready() -> void:
	player=get_parent() as CharacterBody3D
	process_mode=Node.PROCESS_MODE_ALWAYS
func busy() -> bool:return not pending.is_empty()
func start(kind: String,target: Node3D=null) -> bool:
	var service:=player.get_node("SurvivalServices")
	if busy() or service._blocked() or service.is_modal() or service.busy() or player.is_swimming:return false
	if kind not in ["ignite_fire","snuff_fire","torch_light","torch_off","torch_mount"]:return false
	if target!=null and (not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion() or player.global_position.distance_to(target.global_position)>3.5):return false
	if kind in ["ignite_fire","snuff_fire"] and (target==null or not (target.is_in_group("campfire") or target.is_in_group("wall_torch"))):return false
	if kind.begins_with("torch_") and (str(player.active_item) not in ["Torch","Burning Torch"] or not Inventory.has(str(player.active_item),1)):return false
	if kind=="torch_off" and not player.get_node("SurvivalProgression").is_held_lit():return false
	var mount: Dictionary={}
	if kind=="torch_mount":
		mount=player.call("_resolve_wall_torch")
		if not mount.get("valid",false):
			player.call("_hud_toast","AIM AT CLEAR SOLID TIMBER · TORCH KEPT IN HAND")
			return false
		# Lock to the wall, not the camera or the moving raft's world position.
		mount.local_transform=mount.support.global_transform.affine_inverse()*mount.transform
		target=mount.support
	if kind=="ignite_fire":
		if not Inventory.has("Stone",2):player.call("_hud_toast","LIGHT FIRE · NEED 2 STONES (REUSABLE)");return false
		if target==null or not target.has_method("exposed_to_rain"):return false
		if target.call("exposed_to_rain"):player.call("_hud_toast","FIRE IS WET · SHELTER IT FIRST");return false
		if float(target.get("fuel"))<=0 and not Inventory.has("Wood",1):player.call("_hud_toast","LIGHT FIRE · NEED 1 WOOD FOR FUEL");return false
	if kind=="torch_light" and not player.get_node("SurvivalProgression").fire_source_ready(target):player.call("_hud_toast","AIM AT A LIT TORCH, BONFIRE OR COOKING SETUP");return false
	var seconds:=2.2 if kind=="ignite_fire" else (1.3 if kind in ["torch_light","torch_mount"] else 1.0)
	pending={"kind":kind,"target":target,"item":str(player.active_item),"elapsed":0.0,"seconds":seconds,"committed":false,
		"damage":Stats.damage_revision,"start":player.global_position,"raft":player.call("_get_raft_node")}
	if not mount.is_empty(): pending.mount=mount
	var raft:=pending.raft as Node3D
	if raft!=null and player.global_position.distance_to(raft.global_position)>15:pending.raft=null;raft=null
	if raft!=null:pending.start=raft.to_local(player.global_position)
	player.call("play_action",kind,seconds,target.global_position if is_instance_valid(target) else player.global_position)
	return true
func cancel() -> void:
	if not busy():return
	var action:=player.get_node("SurvivalAction")
	if action.kind==pending.kind:action.stop()
	pending.clear()
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:cancel()
func _process(delta: float) -> void:
	if not busy():return
	var action:=player.get_node("SurvivalAction")
	var service:=player.get_node("SurvivalServices")
	if service._blocked() or service.is_modal() or Stats.damage_revision!=pending.damage or player.is_swimming:
		cancel();return
	if not pending.committed:
		var raft:=pending.raft as Node3D
		var at: Vector3=raft.to_local(player.global_position) if is_instance_valid(raft) else player.global_position
		if at.distance_squared_to(pending.start)>1 or str(player.active_item)!=pending.item or action.kind!=pending.kind:
			cancel();return
		var target: Variant=pending.target
		if target!=null and (not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_inside_tree() or player.global_position.distance_to(target.global_position)>3.5):
			cancel();return
		if pending.kind in ["ignite_fire","torch_light"] and (target==null or target.call("exposed_to_rain")):
			cancel();return
	pending.elapsed+=delta
	if not pending.committed and pending.elapsed>=pending.seconds*.70:
		if not _commit():cancel();return
		pending.committed=true
		player.call("_queue_save")
	if pending.elapsed>=pending.seconds:pending.clear()
func _commit() -> bool:
	var target:=pending.target as Node3D
	var progress:=player.get_node("SurvivalProgression")
	match str(pending.kind):
		"ignite_fire":
			if not Inventory.has("Stone",2) or target==null or target.call("exposed_to_rain"):return false
			if float(target.get("fuel"))<=0:
				if not Inventory.try_exchange({"Wood":1},{}):return false
				target.set("fuel",90.0)
			target.set("burning",true)
			if target.is_in_group("wall_torch"):
				target.set("end_time",preload("res://scripts/torch_cycle.gd").next_dawn(player))
				target.set("fuel",preload("res://scripts/torch_cycle.gd").seconds_left(player,target.end_time))
			player.call("_hud_toast","FIRE LIT · STONES KEPT")
		"snuff_fire":
			if target==null:return false
			target.call("extinguish");player.call("_hud_toast","FIRE OFF · UNUSED FUEL SAVED")
		"torch_light":
			if not progress.fire_source_ready(target) or not Inventory.try_exchange({"Torch":1},{"Burning Torch":1}):return false
			progress.legacy_torch=false;progress.torch_end_time=preload("res://scripts/torch_cycle.gd").next_dawn(player)
			progress.torch_fuel=preload("res://scripts/torch_cycle.gd").seconds_left(player,progress.torch_end_time)
			player.get_node("SurvivalServices").equip_owned("Burning Torch")
			player.call("_hud_toast","TORCH LIT · LASTS UNTIL DAWN")
		"torch_off":
			progress.extinguish_torch();player.get_node("SurvivalServices").equip_owned("Torch")
			player.call("_hud_toast","TORCH PUT OUT")
		"torch_mount":
			if not player.call("mount_held_torch",pending.get("mount",{})):
				player.call("_hud_toast","MOUNTING SPACE BLOCKED · TORCH KEPT IN HAND")
				return false
	return true
