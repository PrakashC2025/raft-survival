extends Node
## Review first; contact-timed cutting/unpacking exchanges all outputs together.
const ITEMS:=preload("res://scripts/garden_items.gd")
const UI:=preload("res://scripts/ocean_ui.gd")
var player: CharacterBody3D
var menu_open:=false
var pending: Dictionary={}
var _menu: Control
var _sheet: PanelContainer
var _item:=""
var _start:=Vector3.ZERO
var _damage:=0
func _ready() -> void:player=get_parent() as CharacterBody3D
func busy() -> bool:return not pending.is_empty()
func usable(item: String) -> bool:return item in ITEMS.CROPS or not ITEMS.box_crop(item).is_empty() or not ITEMS.seed_crop(item,true).is_empty()
func use(item: String) -> void:
	if not ITEMS.seed_crop(item,true).is_empty():player.call("_hud_toast","HOLD THESE SEEDS · AIM AT A WOODEN SEED TRAY TO DRY THEM");return
	if not Inventory.has(item,1) or menu_open or busy() or player.is_swimming:return
	var services:=player.get_node("SurvivalServices")
	if services.busy() or services.is_modal() or services._blocked():return
	_item=item;menu_open=true;GameSettings.release_gameplay_input();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var layer:=CanvasLayer.new();layer.layer=12;add_child(layer)
	_menu=Control.new();layer.add_child(_menu);_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(.01,.035,.055,.92);_menu.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet=PanelContainer.new();_sheet.theme=UI.theme();_sheet.add_theme_stylebox_override("panel",UI.box(Color("092333"),UI.AQUA,18));_menu.add_child(_sheet)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_sheet.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",12);scroll.add_child(column)
	var title:=Label.new();title.text=item;title.add_theme_font_size_override("font_size",23);title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(title)
	var art:=preload("res://scripts/craft_menu.gd").ItemPicture.new();art.item=item;art.custom_minimum_size=Vector2(0,110);column.add_child(art)
	var info:=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.add_theme_font_size_override("font_size",17)
	info.text="Cut with a knife, separate the seeds and keep the food. Dry seeds on a wooden tray for two minutes before planting." if item in ITEMS.CROPS else "A rare garden supply crate. Open it to save its food, planting seeds and recovered parts."
	column.add_child(info)
	for reward in ITEMS.rewards(item):
		var row:=HBoxContainer.new();column.add_child(row)
		var label:=Label.new();label.text="%s  ×%d"%[reward,ITEMS.rewards(item)[reward]];label.add_theme_font_size_override("font_size",17);row.add_child(label)
	var build:=Button.new();build.name="Prepare";build.text="CUT & SAVE SEEDS" if item in ITEMS.CROPS else "OPEN RARE BOX";build.custom_minimum_size.y=52;column.add_child(build)
	build.disabled=not Inventory.can_exchange({item:1},ITEMS.rewards(item));build.pressed.connect(func():start(_item))
	if build.disabled:
		var full:=Label.new();full.text="Free bag space for the food and seeds.";column.add_child(full)
	if item in ITEMS.CROPS:
		var eat:=Button.new();eat.name="Eat";eat.text="EAT WHOLE FRUIT";eat.custom_minimum_size.y=52;column.add_child(eat)
		eat.pressed.connect(func():var chosen:=_item;close();player.get_node("SurvivalServices").use_item(chosen))
	var cancel:=Button.new();cancel.text="Cancel";cancel.custom_minimum_size.y=52;column.add_child(cancel);cancel.pressed.connect(close)
	_menu.resized.connect(_fit);_fit()
func _fit() -> void:
	if not is_instance_valid(_sheet):return
	var scale:=UI.scale_for(get_viewport());var view:=get_viewport().get_visible_rect().size/scale
	_sheet.scale=Vector2.ONE*scale;_sheet.size=Vector2(minf(460,view.x-24),minf(610,view.y-24))
	_sheet.position=(view-_sheet.size)*.5*scale
func close() -> void:
	menu_open=false
	if is_instance_valid(_menu):_menu.get_parent().queue_free()
	_menu=null;_sheet=null;GameSettings.release_gameplay_input()
	if not GameSettings.is_open:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func start(item: String) -> bool:
	var services:=player.get_node("SurvivalServices")
	if player.active_item!=item or player.is_swimming or services.busy() or services._blocked() or not Inventory.can_exchange({item:1},ITEMS.rewards(item)) or ITEMS.rewards(item).is_empty():return false
	close();pending={"item":item,"seconds":0.0,"duration":2.8 if item in ITEMS.CROPS else 2.0}
	_start=player.global_position;_damage=Stats.damage_revision
	player.call("play_action","prepare_seed" if item in ITEMS.CROPS else "unpack",pending.duration,Vector3.ZERO,item)
	return true
func _process(delta: float) -> void:advance(delta)
func advance(step: float) -> void:
	if menu_open and (GameSettings.is_open or get_tree().paused or Stats.health<=0):close()
	if pending.is_empty():return
	var item:=str(pending.item)
	if player.active_item!=item or not Inventory.has(item,1) or player.is_swimming or player.global_position.distance_to(_start)>.35 or Stats.damage_revision!=_damage or GameSettings.is_open or player.get_node("CanvasLayer/SurvivalHUD").gameplay_input_blocked():
		pending.clear();player.get_node("SurvivalAction").stop();player.call("_hud_toast","PREPARATION CANCELLED · ITEM KEPT");return
	pending.seconds=float(pending.seconds)+maxf(0,step)
	if pending.seconds<float(pending.duration):return
	var loot:=ITEMS.rewards(item);pending.clear()
	if not Inventory.try_exchange({item:1},loot):player.call("_hud_toast","BAG FULL · FRUIT / BOX KEPT");return
	for reward in loot:Inventory.notify_pickup(reward,int(loot[reward]))
	player.call("_hud_toast","FOOD CUT · SEEDS SAVED · DRY ON A SEED TRAY" if item in ITEMS.CROPS else "RARE BOX OPENED · FOOD, SEEDS AND PARTS SAVED")
	player.call("_queue_save")
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		if busy():pending.clear();player.get_node("SurvivalAction").stop()
		if menu_open:close()
