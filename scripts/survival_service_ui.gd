extends CanvasLayer
const RULES := preload("res://scripts/food_rules.gd")
const SLOT := preload("res://scripts/storage_slot_ui.gd")
var service: Node
var slot_style: StyleBoxFlat
var drag_source: Control
var _overlay: Control
var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _progress: ProgressBar
var _progress_title: Label
var _progress_root: VBoxContainer
var _rows: Array[Dictionary]=[]
var _slots: Array[Control]=[]
var _mode := ""
var _filter_button: Button
var _last_progress := -1
var _popups: Array[Label]=[]
var _popup_ages := PackedFloat32Array([2.0,2.0,2.0,2.0])
var _popup_next := 0
func _ready() -> void:
	layer=12
	slot_style=StyleBoxFlat.new();slot_style.bg_color=Color(.035,.065,.072,.97);slot_style.border_color=Color(.34,.47,.39);slot_style.set_border_width_all(1);slot_style.set_corner_radius_all(5)
	_overlay=Control.new();_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_overlay)
	var shade:=ColorRect.new();shade.color=Color(.01,.025,.03,.82);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_overlay.add_child(shade)
	_panel=PanelContainer.new();_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);_overlay.add_child(_panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.045,.09,.105,.99);style.border_color=Color(.54,.57,.35);style.set_border_width_all(2);style.set_corner_radius_all(14);style.content_margin_left=18;style.content_margin_right=18;style.content_margin_top=14;style.content_margin_bottom=14;_panel.add_theme_stylebox_override("panel",style)
	_body=VBoxContainer.new();_body.add_theme_constant_override("separation",9);_panel.add_child(_body)
	_progress_root=VBoxContainer.new();_progress_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);_progress_root.offset_left=-190;_progress_root.offset_right=190;_progress_root.offset_top=-178;_progress_root.offset_bottom=-124;_progress_root.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_progress_root)
	_progress_title=Label.new();_progress_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_progress_title.add_theme_font_size_override("font_size",16);_progress_root.add_child(_progress_title)
	_progress=ProgressBar.new();_progress.custom_minimum_size=Vector2(380,18);_progress.show_percentage=false;_progress_root.add_child(_progress)
	_progress.mouse_filter=Control.MOUSE_FILTER_IGNORE;_progress_title.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_progress_root.hide();_overlay.hide()
	Inventory.changed.connect(_inventory_changed)
	for index in 4:
		var popup:=Label.new();popup.add_theme_font_size_override("font_size",18);popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP);popup.offset_left=-160;popup.offset_right=160;popup.offset_top=130+index*23;popup.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;popup.mouse_filter=Control.MOUSE_FILTER_IGNORE;popup.hide();add_child(popup);_popups.append(popup)
	Stats.stat_delta.connect(_stat_delta)
func _stat_delta(kind: String,amount: float) -> void:
	if service.menu_open:return
	var index:=_popup_next;_popup_next=(_popup_next+1)%4;_popup_ages[index]=0.0
	var popup:=_popups[index];popup.text=("+" if amount>=0 else "")+str(snappedf(amount,.1))+" "+kind.to_upper();popup.modulate=Color(.66,1,.72) if amount>0 else Color(1,.45,.35);popup.show()
func _process(delta: float) -> void:
	for index in 4:
		if _popup_ages[index]>=1.6:continue
		_popup_ages[index]+=delta
		_popups[index].modulate.a=1.0-clampf((_popup_ages[index]-.8)/.8,0,1)
		if _popup_ages[index]>=1.6:_popups[index].hide()
func _inventory_changed() -> void:
	if _overlay.visible:
		if _mode=="cook":_refresh_cooking()
		elif _mode=="storage":refresh_storage()
		elif _mode=="filter" and is_instance_valid(_filter_button):_filter_button.disabled=not Inventory.has("Dirty Water Can",1)
func _begin(title: String,mode: String) -> void:
	for popup in _popups:popup.hide()
	for child in _body.get_children():_body.remove_child(child);child.queue_free()
	_rows.clear();_slots.clear();drag_source=null;_mode=mode
	var viewport_size:=get_viewport().get_visible_rect().size
	var width:=minf(viewport_size.x*.92,980);var height:=minf(viewport_size.y*.88,610)
	_panel.offset_left=-width*.5;_panel.offset_right=width*.5;_panel.offset_top=-height*.5;_panel.offset_bottom=height*.5
	var header:=HBoxContainer.new();_body.add_child(header)
	_title=Label.new();_title.text=title;_title.add_theme_font_size_override("font_size",22);_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(_title)
	var close_button:=Button.new();close_button.text="CLOSE";close_button.custom_minimum_size=Vector2(85,38);close_button.pressed.connect(service.close_menu);header.add_child(close_button)
	_overlay.show()
func close() -> void:_overlay.hide();drag_source=null;_mode=""
func show_cooking() -> void:
	_begin("COOKING · ALL RECIPES","cook")
	var hint:=Label.new();hint.text="Ingredients show HAVE / NEED. Keep the fire fuelled and sheltered. Used cans are returned.";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(hint)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;_body.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",8);scroll.add_child(list)
	for dish in RULES.RECIPES:
		var recipe: Dictionary=RULES.RECIPES[dish]
		var row:=HBoxContainer.new();row.custom_minimum_size.y=104;list.add_child(row)
		var details:=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(details)
		var name_label:=Label.new();name_label.text=dish+" · %ds"%int(recipe.seconds);name_label.add_theme_font_size_override("font_size",18);details.add_child(name_label)
		var ingredients:=RichTextLabel.new();ingredients.bbcode_enabled=true;ingredients.fit_content=true;ingredients.scroll_active=false;ingredients.custom_minimum_size.y=28;details.add_child(ingredients)
		var effects:=Label.new();effects.text="Hunger +%d   Water +%d   Health +%d"%[recipe.effects[0],recipe.effects[1],recipe.effects[2]];effects.add_theme_font_size_override("font_size",14);effects.modulate=Color(.75,.86,.77);details.add_child(effects)
		var button:=Button.new();button.text="COOK";button.custom_minimum_size=Vector2(90,48);button.size_flags_vertical=Control.SIZE_SHRINK_CENTER;button.pressed.connect(func():service.start_cooking(dish));row.add_child(button)
		_rows.append({"dish":dish,"ingredients":ingredients,"button":button})
	_refresh_cooking()
func _refresh_cooking() -> void:
	for row in _rows:
		var text_value:=""
		for item in RULES.RECIPES[row.dish].ingredients:
			var need:=int(RULES.RECIPES[row.dish].ingredients[item]);var have:=Inventory.total(item)
			text_value+="[color="+("#8dd49c" if have>=need else "#f28b7f")+"]"+item+"  %d / %d"%[have,need]+"[/color]   "
		row.ingredients.text=text_value
		row.button.disabled=not service.can_cook(row.dish)
func show_filter() -> void:
	_begin("FILTER WATER CAN","filter")
	var text_label:=Label.new();text_label.text="Insert one Dirty Water Can. Filtering takes 5 seconds.\nThe cleaned can returns to your bag; drink it or use it in cooking.";text_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_body.add_child(text_label)
	_filter_button=Button.new();_filter_button.text="INSERT & FILTER · 5 SECONDS";_filter_button.custom_minimum_size.y=52;_filter_button.disabled=not Inventory.has("Dirty Water Can",1);_filter_button.pressed.connect(service.start_filtering);_body.add_child(_filter_button)
func show_storage() -> void:
	_begin("LOST BACKPACK" if service.storage.loot_bag else "STORAGE BOX · SAFE ON DEATH","storage")
	var hint:=Label.new();hint.text="Drag between slots, or tap an item to move its stack into a free slot.";_body.add_child(hint)
	var columns:=HBoxContainer.new();columns.add_theme_constant_override("separation",18);columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;_body.add_child(columns)
	for is_box in [false,true]:
		var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(column)
		var heading:=Label.new();heading.text="BOX" if is_box else "BACKPACK + HOTBAR";column.add_child(heading)
		var grid:=GridContainer.new();grid.columns=6;column.add_child(grid)
		var count_value: int=service.storage.contents.size() if is_box else Inventory.SLOT_COUNT
		var width:=maxf(32.0,(_panel.offset_right-_panel.offset_left-80.0)/12.0-5.0)
		var height:=maxf(30.0,minf(width,(_panel.offset_bottom-_panel.offset_top-140.0)/5.0))
		for index in count_value:
			var slot:=SLOT.new();slot.service=service;slot.box_slot=is_box;slot.slot_index=index;slot.custom_minimum_size=Vector2(width,height);grid.add_child(slot);_slots.append(slot)
	refresh_storage()
func refresh_storage() -> void:
	for slot in _slots:
		if is_instance_valid(slot):slot.queue_redraw()
func finish_drag(at: Vector2,tap: bool) -> void:
	if not is_instance_valid(drag_source):return
	var origin:=drag_source;drag_source=null
	if tap:
		var target: Array=Inventory.slots if origin.box_slot else service.storage.contents
		for index in target.size():
			if target[index].is_empty():service.transfer(origin.box_slot,origin.slot_index,not origin.box_slot,index);break
		return
	for slot in _slots:
		if slot.get_global_rect().has_point(at):service.transfer(origin.box_slot,origin.slot_index,slot.box_slot,slot.slot_index);break
func show_progress(label: String,fraction: float) -> void:
	var value:=roundi(clampf(fraction,0,1)*100)
	if _progress_title.text!=label:_progress_title.text=label
	if _last_progress!=value:_last_progress=value;_progress.value=value
	_progress_root.show()
func hide_progress() -> void:_progress_root.hide();_last_progress=-1
func _unhandled_key_input(event: InputEvent) -> void:
	if service.menu_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled();service.close_menu()
