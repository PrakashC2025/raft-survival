extends StaticBody3D
const CONTACT_AUDIO:=preload("res://scripts/contact_audio.gd")
## Stable finite pickups survive streamed tile unloads and Continue.
var resource_id := ""
var rewards: Dictionary = {}
var caption := "COLLECT"
var owner_world: Node3D
var taken := false

func _ready() -> void:
	add_to_group("underwater_loot")
	taken=bool(owner_world.resource_state.get(resource_id,false))
	if taken:hide();collision_layer=0

func interaction_caption() -> String:return caption

func interact_survival(actor: Node3D) -> void:
	if taken or not actor.get("is_swimming") or actor.global_position.distance_to(global_position)>3.5:return
	if not Inventory.try_exchange({},rewards):actor.call("_hud_toast","BAG FULL - CLEAR SPACE TO COLLECT");return
	taken=true;owner_world.resource_state[resource_id]=true
	for item in rewards:Inventory.notify_pickup(item,int(rewards[item]))
	actor.get_node("SurvivalAction").call("play","grab",.65,global_position)
	actor.call("play_world_sfx",CONTACT_AUDIO.pick_action("water"),-16.0,global_position)
	collision_layer=0;hide();actor.call("_queue_save")
