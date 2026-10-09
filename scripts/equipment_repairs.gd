extends Node
## Local, contact-committed repairs and portable assembly. No cost on cancel.
const PORTABLE := ["Solar Torch","Walkie Talkie","Binoculars","Repair Kit"]
const PARTS := {
	"Solar Torch":{"Wire":1,"Plastic":1}, "Walkie Talkie":{"Wire":2,"Screw":1},
	"Binoculars":{"Metal":1,"Plastic":1}, "WindGenerator":{"Wire":2,"Screw":2},
	"ElectricPurifier":{"Wire":1,"Screw":2}, "RescueRadio":{"Wire":2,"Screw":2},
	"ElectricLamp":{"Wire":1,"Plastic":1}
}
var player: CharacterBody3D
var pending: Dictionary = {}
var menu_open := false
var _target: Node
var _item := ""
var _panel: PanelContainer
var _title: Label
var _details: Label
var _repair: Button
var _shake: Button
var _screen_tick := 0.0

func _ready() -> void:
	player=get_parent() as CharacterBody3D
	process_mode=Node.PROCESS_MODE_ALWAYS
	var layer:=CanvasLayer.new();layer.layer=22;add_child(layer)
	var backdrop:=Control.new();backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(backdrop)
	_panel=PanelContainer.new();_panel.name="EquipmentRepairMenu";backdrop.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left=-240;_panel.offset_right=240;_panel.offset_top=-210;_panel.offset_bottom=210
	var style:=StyleBoxFlat.new();style.bg_color=Color(.055,.085,.09,.98);style.border_color=Color(.34,.43,.38)
	style.set_border_width_all(2);style.set_corner_radius_all(14)
	style.content_margin_left=24;style.content_margin_right=24;style.content_margin_top=20;style.content_margin_bottom=20
	_panel.add_theme_stylebox_override("panel",style)
	var rows:=VBoxContainer.new();rows.add_theme_constant_override("separation",12);_panel.add_child(rows)
	_title=Label.new();_title.add_theme_font_size_override("font_size",23);rows.add_child(_title)
	_details=Label.new();_details.add_theme_font_size_override("font_size",17);rows.add_child(_details)
	_repair=_button(rows,"REPAIR",func():start("repair",_target,_item))
	_shake=_button(rows,"SHAKE · NO PARTS NEEDED",func():start("shake",_target,_item))
	_button(rows,"CLOSE",close)
	_panel.hide()

func _button(rows: VBoxContainer, label: String, command: Callable) -> Button:
	var button:=Button.new();button.text=label;button.custom_minimum_size=Vector2(420,48)
	button.add_theme_font_size_override("font_size",17);button.button_down.connect(GameSettings.release_gameplay_input)
	button.pressed.connect(command);rows.add_child(button);return button

func busy() -> bool:return not pending.is_empty()
func _blocked() -> bool:
	var services:=player.get_node("SurvivalServices")
	return services._blocked() or services.menu_open or not services.action.is_empty() or player.get_node("FireActions").busy() or player.is_swimming

func _valid(target: Node, item: String) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_inside_tree():return false
	if target==player.get_node("PortableElectronics"):return str(player.active_item)==item and Inventory.has(item,1)
	return target is Node3D and target.is_in_group("build_surface") and str(target.get("machine_type"))==item and player.global_position.distance_to(target.global_position)<=3.5

func repair_cost(target: Node, item: String) -> Dictionary:
	var result: Dictionary=PARTS.get(item,{}).duplicate()
	if is_instance_valid(target) and str(target.call("fault_for",item))=="motor":result["Motor"]=1
	return result

func open(target: Node, item: String) -> void:
	if busy() or _blocked() or not _valid(target,item) or str(target.call("fault_for",item)).is_empty():return
	_target=target;_item=item;menu_open=true;GameSettings.release_gameplay_input()
	_refresh();_panel.show();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func close() -> void:
	menu_open=false;_panel.hide();_target=null;_item=""
	GameSettings.release_gameplay_input()
	if not GameSettings.mobile_effects_profile() and not _blocked():Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func _refresh() -> void:
	if not _valid(_target,_item):close();return
	var fault:=str(_target.call("fault_for",_item))
	if fault.is_empty():close();return
	var parts:=repair_cost(_target,_item)
	_title.text=_item.to_upper()+" · REPAIR"
	_details.text=("Loose contact" if fault=="contact" else "Seized motor" if fault=="motor" else "Damaged wiring")+"\n\nREUSABLE TOOL\nRepair Kit: HAVE %d / NEED 1\n\nPARTS USED AT FINISH"%Inventory.total("Repair Kit")
	for ingredient in parts:_details.text+="\n%s: HAVE %d / NEED %d"%[ingredient,Inventory.total(ingredient),parts[ingredient]]
	var ready:=Inventory.has("Repair Kit",1) and Inventory.has_cost(parts)
	_repair.disabled=not ready;_repair.text="REPAIR · 6 SECONDS" if ready else "NEED TOOL / PARTS · CRAFT IN BAG"
	_shake.visible=fault=="contact"

func start(kind: String, target: Node, item: String) -> bool:
	if busy() or _blocked() or kind not in ["repair","shake","assemble_electronics"]:return false
	var cost: Dictionary={}
	if kind=="assemble_electronics":
		if item not in PORTABLE or not Inventory.can_afford_item(item) or not Inventory.can_store_craft_result(item):return false
		cost=Inventory.ITEM_RECIPES[item].duplicate()
	else:
		if not _valid(target,item):return false
		var fault:=str(target.call("fault_for",item))
		if fault.is_empty() or (kind=="shake" and fault!="contact"):return false
		cost=repair_cost(target,item) if kind=="repair" else {}
		if kind=="repair" and (not Inventory.has("Repair Kit",1) or not Inventory.has_cost(cost)):return false
	var seconds:=1.4 if kind=="shake" else 6.0
	var raft:=player.call("_get_raft_node") as Node3D
	if raft!=null and player.global_position.distance_to(raft.global_position)>15:raft=null
	pending={"kind":kind,"item":item,"target":target,"cost":cost,"time":0.0,"seconds":seconds,
		"selected":str(player.active_item),"damage":Stats.damage_revision,"committed":false,"raft":raft,
		"start":raft.to_local(player.global_position) if raft!=null else player.global_position}
	close()
	var at: Vector3=target.global_position if target is Node3D else player.global_position
	player.call("play_action",kind,seconds,at,item)
	return true

func cancel() -> void:
	if not busy():return
	var action:=player.get_node("SurvivalAction")
	if action.kind==pending.kind:action.stop()
	pending.clear()

func _process(delta: float) -> void:
	if menu_open:
		if _blocked() or not _valid(_target,_item):close()
		else:
			_screen_tick+=delta
			if _screen_tick>=.2:_screen_tick=0;_refresh()
	if not busy():return
	var action:=player.get_node("SurvivalAction")
	if _blocked() or Stats.damage_revision!=pending.damage:cancel();return
	if not pending.committed:
		var raft:=pending.raft as Node3D
		var here: Vector3=raft.to_local(player.global_position) if is_instance_valid(raft) else player.global_position
		if here.distance_squared_to(pending.start)>1 or str(player.active_item)!=pending.selected or action.kind!=pending.kind:
			cancel();return
		if pending.kind!="assemble_electronics" and not _valid(pending.target,pending.item):cancel();return
	pending.time+=delta
	if not pending.committed and pending.time>=pending.seconds*.85:
		if not _commit():cancel();player.call("_hud_toast","REPAIR / BUILD STOPPED · CHECK PARTS AND BAG SPACE");return
		pending.committed=true;player.call("_queue_save")
	if pending.time>=pending.seconds:pending.clear()

func _commit() -> bool:
	var item:=str(pending.item)
	if pending.kind=="assemble_electronics":
		if not Inventory.can_afford_item(item) or not Inventory.try_exchange({} if Inventory.infinite else pending.cost,{item:1}):return false
		player.get_node("SurvivalProgression").record("craft:"+item)
		player.call("_hud_toast",item.to_upper()+" ASSEMBLED · READY IN BAG");return true
	var target:=pending.target as Node
	var fault:=str(target.call("fault_for",item))
	if fault.is_empty() or (pending.kind=="shake" and fault!="contact"):return false
	if pending.kind=="repair" and (not Inventory.has("Repair Kit",1) or not Inventory.try_exchange(repair_cost(target,item),{})):return false
	target.call("clear_fault",item)
	player.call("_hud_toast",item.to_upper()+" · CONTACT RESTORED" if pending.kind=="shake" else item.to_upper()+" REPAIRED · TOOL KEPT")
	return true

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:cancel();close()

func _unhandled_input(event: InputEvent) -> void:
	if menu_open and event.is_action_pressed("ui_cancel"):get_viewport().set_input_as_handled();close()
