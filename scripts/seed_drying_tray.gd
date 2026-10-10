extends StaticBody3D
const ITEMS:=preload("res://scripts/garden_items.gd")
const ART:=preload("res://scripts/garden_visual.gd")
const PARTS:=preload("res://scripts/machine_visual.gd")
const DRY_SECONDS:=120.0
var crop:=""
var count:=0
var seconds:=0.0
var _sample:=0.0
var _preview:=false
var _seeds: Node3D
var _label: Label3D
func _ready() -> void:
	_preview=get_parent()!=null and get_parent().name=="BuildPreviewRoot"
	add_to_group("build_surface")
	PARTS.timber_box(self,Vector3.ZERO,Vector3(.56,.025,.40))
	for x in [-.28,.28]:PARTS.timber_box(self,Vector3(x,.03,0),Vector3(.025,.065,.43))
	for z in [-.20,.20]:PARTS.timber_box(self,Vector3(0,.03,z),Vector3(.56,.065,.025))
	_label=Label3D.new();_label.position=Vector3(0,.28,0);_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;_label.font_size=23;_label.pixel_size=.003;add_child(_label);_refresh()
func raining_on_seeds() -> bool:
	var rain:=get_tree().get_first_node_in_group("rain_system")
	if rain==null or not bool(rain.call("is_raining")):return false
	var ray:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.09,global_position+Vector3.UP*8,1,[get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
func _process(delta: float) -> void:
	if _preview:return
	_sample+=delta
	if _sample>=1:advance(minf(_sample,2.0));_sample=0
	var actor:=get_tree().get_first_node_in_group("player")
	_label.visible=actor!=null and actor.aim_valid and actor.aim_collider==self and actor.aim_distance<=4
func advance(step: float) -> void:
	if _preview:return
	if count>0 and seconds<DRY_SECONDS and not raining_on_seeds():seconds=minf(DRY_SECONDS,seconds+maxf(0,step))
	_refresh()
func empty() -> bool:return count==0
func interaction_caption() -> String:return "COLLECT DRY SEEDS" if count>0 and seconds>=DRY_SECONDS else "DRY SEEDS" if count==0 else "CHECK DRYING"
func interact_survival(player: Node) -> void:
	if count>0:
		if seconds<DRY_SECONDS:player.call("_hud_toast","SEEDS DRYING · %ds LEFT"%ceili(DRY_SECONDS-seconds));return
		var dried_seeds:="Dry "+crop+" Seeds"
		if not Inventory.try_exchange({},{dried_seeds:count}):player.call("_hud_toast","BAG FULL · SEEDS STAY ON THE TRAY");return
		Inventory.notify_pickup(dried_seeds,count);player.call("play_action","grab",.8,global_position,dried_seeds)
		player.call("_hud_toast","DRY SEEDS SAVED · PLANT IN SOIL OR A MATCHING POT");crop="";count=0;seconds=0;_refresh();player.call("_queue_save");return
	var item:=str(player.get("active_item"));var chosen:=ITEMS.seed_crop(item,true)
	if chosen.is_empty() or not Inventory.has(item,1):player.call("_hud_toast","CUT A WHOLE FRUIT · HOLD ITS WET SEEDS TO FILL THIS TRAY");return
	var amount:=mini(8,Inventory.total(item))
	if not Inventory.try_exchange({item:amount},{}):return
	crop=chosen;count=amount;seconds=0;_refresh();player.call("play_action","plant",.9,global_position,item)
	player.call("_hud_toast","SEEDS LAID OUT · 2 MINUTES TO DRY · SHELTER FROM RAIN");player.call("_queue_save")
func _refresh() -> void:
	if _label==null:return
	_label.text="SEED TRAY · EMPTY" if count==0 else "%s · %d DRY SEEDS · COLLECT"%[crop,count] if seconds>=DRY_SECONDS else "%s · %d SEEDS · %ds TO DRY"%[crop,count,ceili(DRY_SECONDS-seconds)]
	var state:="" if count==0 else crop+str(seconds>=DRY_SECONDS)
	if str(get_meta("seed_visual",""))==state:return
	set_meta("seed_visual",state)
	if is_instance_valid(_seeds):remove_child(_seeds);_seeds.queue_free();_seeds=null
	if count>0:_seeds=ART.seeds(crop,seconds<DRY_SECONDS);_seeds.scale=Vector3.ONE*2;_seeds.position.y=.025;add_child(_seeds)
func save_survival_state() -> Dictionary:return {"crop":crop,"count":count,"seconds":seconds}
func restore_survival_state(data: Dictionary) -> void:
	crop=str(data.get("crop",""));count=clampi(int(data.get("count",0)),0,8) if crop in ITEMS.CROPS else 0
	var clock: Variant=data.get("seconds",0.0)
	seconds=clampf(float(clock),0,DRY_SECONDS) if (clock is float or clock is int) and is_finite(float(clock)) else 0.0
	if count==0:crop="";seconds=0
	_refresh()
