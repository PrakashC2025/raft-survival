extends StaticBody3D
## Active-time catches stay in the saved net when the bag is full.
var fish:=0
var seconds:=0.0
var _sample:=0.0
var _preview:=false
var _label: Label3D
var _ocean: Node3D
var _catch: Node3D
const INTERVAL:=35.0
func _ready() -> void:
	_preview=get_parent()!=null and get_parent().name=="BuildPreviewRoot"
	add_to_group("build_surface")
	add_child(preload("res://scripts/fishing_net_visual.gd").create())
	_ocean=get_tree().get_first_node_in_group("ocean") as Node3D
	_label=Label3D.new();_label.position=Vector3(0,.20,-.25);_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size=22;_label.pixel_size=.003;_label.visibility_range_end=4;add_child(_label)
	_catch=preload("res://models/coastal_fish.glb").instantiate();_catch.position=Vector3(0,-.70,0);_catch.scale=Vector3.ONE*.45;add_child(_catch)
	for mesh: MeshInstance3D in _catch.find_children("*","MeshInstance3D",true,false):mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_refresh()
func _process(delta: float) -> void:
	if _preview:return
	_sample+=delta
	if _sample<1.0:return
	advance(minf(_sample,2.0));_sample=0
func advance(step: float) -> void:
	if _preview:return
	if fish<3 and in_water():
		seconds=minf(INTERVAL,seconds+step)
		if seconds>=INTERVAL:
			for school in get_tree().get_nodes_in_group("surface_fish_school"):
				if school.call("take_nearby",to_global(Vector3(0,-.5,0)),2.0):fish+=1;seconds=0;break
	_refresh()
func in_water() -> bool:
	if not is_instance_valid(_ocean):return false
	var at:=to_global(Vector3(0,-.65,0))
	if at.y>float(_ocean.call("get_height",at))+.05:return false
	var ray:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*.15,at-Vector3.UP*.2,1,[get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
func _refresh() -> void:
	_label.visible=not _preview
	_label.text="NET · %d/3 FISH · COLLECT"%fish if fish>0 else "NET · %ds / WAITING FOR FISH"%maxi(0,ceili(INTERVAL-seconds)) if in_water() else "NET · NEEDS OPEN SEAWATER"
	_catch.visible=fish>0 and not _preview
func interaction_caption() -> String:return "COLLECT FISH" if fish>0 else "CHECK NET"
func empty() -> bool:return fish==0
func interact_survival(player: Node) -> void:
	if fish<=0:player.call("_hud_toast","NET SET · SMALL FISH NEED TIME TO SWIM INTO IT");return
	if not Inventory.try_exchange({},{"Fish":fish}):player.call("_hud_toast","BAG FULL · YOUR CATCH STAYS IN THE NET");return
	var caught:=fish;fish=0;_refresh()
	player.call("play_action","grab",.75,global_position,"Fish")
	Inventory.notify_pickup("Fish",caught)
	player.call("_hud_toast","COLLECTED %d FISH"%caught);player.call("_queue_save")
func save_survival_state() -> Dictionary:return {"fish":fish,"seconds":seconds}
func restore_survival_state(data: Dictionary) -> void:
	fish=clampi(int(data.get("fish",0)),0,3);seconds=clampf(float(data.get("seconds",0)),0,INTERVAL)
	_refresh()
