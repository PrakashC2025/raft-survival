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
var _boil_button: Button
var _boil_hint: Label
var _last_progress := -1
var _popups: Array[Label]=[]
var _popup_ages := PackedFloat32Array([2.0,2.0,2.0,2.0])
var _popup_next := 0
var _fire_status: Label
var _fire_button: Button
var _cook_category := "ALL"
var _cook_refresh := 0.0
var _recipe_scroll: ScrollContainer
var _recipe_touch := -1
var _recipe_touch_start := Vector2.ZERO
var _recipe_dragging := false
var _recipe_suppress_until := 0
func _ready() -> void:
	layer=12
	slot_style=StyleBoxFlat.new();slot_style.bg_color=Color(.035,.065,.072,.97);slot_style.border_color=Color(.34,.47,.39);slot_style.set_border_width_all(1);slot_style.set_corner_radius_all(5)
	_overlay=Control.new();_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_overlay)
	var shade:=ColorRect.new();shade.color=Color(.01,.025,.03,.82);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_overlay.add_child(shade)
	_panel=PanelContainer.new();_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);_overlay.add_child(_panel)
	var style:=_card_style(Color(.025,.047,.052,.99),Color(.26,.34,.29),16)
	style.content_margin_left=20;style.content_margin_right=20;style.content_margin_top=16;style.content_margin_bottom=16;_panel.add_theme_stylebox_override("panel",style)
	var theme:=Theme.new();theme.set_color("font_color","Button",Color(.90,.95,.87));theme.set_font_size("font_size","Button",16)
	for state in ["normal","hover","pressed","disabled"]:
		var surface:=_card_style(Color(.13,.23,.20) if state=="normal" else (Color(.20,.33,.27) if state=="hover" else Color(.07,.14,.13)),Color(.29,.42,.33),8)
		surface.content_margin_left=12;surface.content_margin_right=12;surface.content_margin_top=8;surface.content_margin_bottom=8
		theme.set_stylebox(state,"Button",surface)
	theme.set_color("font_disabled_color","Button",Color(.45,.53,.49));_panel.theme=theme
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
	_cook_refresh+=delta
	if _mode=="cook" and _overlay.visible and _cook_refresh>=.25:_cook_refresh=0;_refresh_cooking()
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
	_recipe_scroll=null;_recipe_touch=-1;_recipe_dragging=false
	for popup in _popups:popup.hide()
	for child in _body.get_children():_body.remove_child(child);child.queue_free()
	_rows.clear();_slots.clear();drag_source=null;_mode=mode;_boil_button=null;_boil_hint=null
	_fire_status=null;_fire_button=null
	var viewport_size:=get_viewport().get_visible_rect().size
	var width:=minf(viewport_size.x*.92,980);var height:=minf(viewport_size.y*.88,610)
	_panel.offset_left=-width*.5;_panel.offset_right=width*.5;_panel.offset_top=-height*.5;_panel.offset_bottom=height*.5
	var header:=HBoxContainer.new();_body.add_child(header)
	_title=Label.new();_title.text=title;_title.add_theme_font_size_override("font_size",22);_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(_title)
	var close_button:=Button.new();close_button.text="CLOSE";close_button.custom_minimum_size=Vector2(85,38);close_button.pressed.connect(service.close_menu);header.add_child(close_button)
	_overlay.show()
func close() -> void:_overlay.hide();drag_source=null;_mode="";_recipe_touch=-1;_recipe_dragging=false
func _card_style(surface: Color,edge: Color,radius: int=10) -> StyleBoxFlat:
	var result:=StyleBoxFlat.new();result.bg_color=surface;result.border_color=edge;result.set_border_width_all(1);result.set_corner_radius_all(radius)
	result.content_margin_left=12;result.content_margin_right=12;result.content_margin_top=10;result.content_margin_bottom=10
	return result
func _note(text: String,size: int=14,color: Color=Color(.68,.76,.70)) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;return label
func _recipe_art(dish: String) -> TextureRect:
	var art:=TextureRect.new();art.name="DishPicture";art.custom_minimum_size=Vector2(86,86);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture=preload("res://scripts/item_art.gd").food_texture(dish);art.mouse_filter=Control.MOUSE_FILTER_IGNORE;return art
func _filter_recipes(category: String) -> void:
	_cook_category=category
	var tabs:=_body.get_node_or_null("RecipeCategories") as TabBar
	if tabs!=null:
		for index in tabs.get_tab_count():
			if tabs.get_tab_title(index)==category and tabs.current_tab!=index:tabs.current_tab=index;break
	for row in _rows:row.card.visible=category=="ALL" or RULES.category(row.dish)==category
func show_cooking() -> void:
	_begin("CAMP KITCHEN","cook")
	_cook_category="ALL"
	var fire_row:=HBoxContainer.new();fire_row.add_theme_constant_override("separation",10);_body.add_child(fire_row)
	_fire_status=_note("",16,Color(.98,.74,.39));_fire_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;fire_row.add_child(_fire_status)
	_fire_button=Button.new();_fire_button.custom_minimum_size=Vector2(126,44);_fire_button.pressed.connect(service.toggle_station_fire);fire_row.add_child(_fire_button)
	var fuel:=Button.new();fuel.text="+ WOOD · 90s";fuel.custom_minimum_size=Vector2(130,44);fuel.pressed.connect(service.fuel_station);fire_row.add_child(fuel)
	_body.add_child(_note("Cook what you catch and grow. Ingredients show HAVE / NEED. Fire stops when your meal is ready."))
	var categories:=TabBar.new();categories.name="RecipeCategories";categories.custom_minimum_size.y=42
	categories.add_theme_font_size_override("font_size",15)
	categories.add_theme_color_override("font_selected_color",Color(.97,.86,.63));categories.add_theme_color_override("font_unselected_color",Color(.64,.73,.69))
	for selected in [false,true]:
		var tab:=_card_style(Color(.13,.24,.20) if selected else Color(.045,.08,.074),Color(.44,.49,.31) if selected else Color(.18,.26,.23),7)
		tab.content_margin_left=16;tab.content_margin_right=16;tab.content_margin_top=10;tab.content_margin_bottom=10
		categories.add_theme_stylebox_override("tab_selected" if selected else "tab_unselected",tab)
	for category in ["ALL","GRILL","SOUPS & STEWS","FRUIT"]:categories.add_tab(category)
	categories.tab_changed.connect(func(index: int):_filter_recipes(categories.get_tab_title(index)));_body.add_child(categories)
	var scroll:=ScrollContainer.new();scroll.name="RecipeScroll";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.scroll_deadzone=10;_body.add_child(scroll)
	_recipe_scroll=scroll
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var list:=GridContainer.new();list.name="RecipeCards";list.columns=2 if get_viewport().get_visible_rect().size.x>=850 else 1;list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("h_separation",12);list.add_theme_constant_override("v_separation",12);scroll.add_child(list)
	var water_card:=PanelContainer.new();water_card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;water_card.add_theme_stylebox_override("panel",_card_style(Color(.045,.12,.14),Color(.19,.35,.38)));list.add_child(water_card)
	var water_body:=VBoxContainer.new();water_card.add_child(water_body)
	var water_row:=HBoxContainer.new();water_body.add_child(water_row)
	water_row.add_child(_recipe_art("Boiled Water Tumbler"))
	var water_details:=VBoxContainer.new();water_details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;water_row.add_child(water_details)
	water_details.add_child(_note("Boil drinking water",18,Color(.91,.95,.90)));water_details.add_child(_note("8 SECONDS  •  WATER +65"))
	_boil_hint=_note("");water_details.add_child(_boil_hint)
	water_body.add_child(_note("Heat the filled metal tumbler; keep the cup after drinking."))
	_boil_button=Button.new();_boil_button.text="BOIL WATER";_boil_button.custom_minimum_size.y=48;_boil_button.pressed.connect(_boil_recipe);water_body.add_child(_boil_button)
	for dish in RULES.RECIPES:
		var recipe: Dictionary=RULES.RECIPES[dish]
		var card:=PanelContainer.new();card.name="RecipeCard";card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.add_theme_stylebox_override("panel",_card_style(Color(.047,.084,.083),Color(.19,.27,.23)));list.add_child(card)
		var content:=VBoxContainer.new();content.add_theme_constant_override("separation",7);card.add_child(content)
		var row:=HBoxContainer.new();content.add_child(row);row.add_child(_recipe_art(dish))
		var details:=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(details)
		details.add_child(_note(dish,18,Color(.93,.94,.86)));details.add_child(_note("%s  •  %ds"%[RULES.category(dish),int(recipe.seconds)],13,Color(.87,.69,.40)))
		details.add_child(_note("Food +%d   Water +%d   Health +%d"%[recipe.effects[0],recipe.effects[1],recipe.effects[2]],13,Color(.60,.82,.65)))
		content.add_child(_note(RULES.method(dish)))
		var ingredients:=RichTextLabel.new();ingredients.bbcode_enabled=true;ingredients.fit_content=true;ingredients.scroll_active=false;ingredients.add_theme_font_size_override("normal_font_size",14);ingredients.custom_minimum_size.y=24;content.add_child(ingredients)
		var button:=Button.new();button.name="CookRecipe";button.text="COOK · %ds"%int(recipe.seconds);button.custom_minimum_size.y=48;button.pressed.connect(_cook_recipe.bind(dish));content.add_child(button)
		_rows.append({"dish":dish,"ingredients":ingredients,"button":button,"card":card})
	_forward_recipe_swipes(list)
	_refresh_cooking()
func _forward_recipe_swipes(control: Control) -> void:
	# Decorative cards/text must not swallow the ScrollContainer's drag events.
	control.mouse_filter=Control.MOUSE_FILTER_PASS
	for child in control.get_children():
		if child is Control:
			_forward_recipe_swipes(child)
			if child is Label or child is RichTextLabel or child is TextureRect:
				child.mouse_filter=Control.MOUSE_FILTER_IGNORE
func _input(event: InputEvent) -> void:
	if _mode!="cook" or not _overlay.visible or not is_instance_valid(_recipe_scroll):return
	if event is InputEventScreenTouch:
		if event.pressed and _recipe_touch==-1 and _recipe_scroll.get_global_rect().has_point(event.position):
			_recipe_touch=event.index;_recipe_touch_start=event.position;_recipe_dragging=false
		elif not event.pressed and event.index==_recipe_touch:
			_recipe_touch=-1
			if _recipe_dragging:
				_recipe_suppress_until=Time.get_ticks_msec()+150
				call_deferred("_finish_recipe_swipe")
	elif event is InputEventScreenDrag and event.index==_recipe_touch:
		if not _recipe_dragging and event.position.distance_to(_recipe_touch_start)>10.0:_recipe_dragging=true
		if _recipe_dragging:
			_recipe_scroll.scroll_vertical-=roundi(event.relative.y)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and event.device==InputEvent.DEVICE_ID_EMULATION and _recipe_dragging:
		# A phone drag also emits mouse motion; scroll that physical gesture once.
		get_viewport().set_input_as_handled()
func _finish_recipe_swipe() -> void:
	if _recipe_touch==-1:_recipe_dragging=false
func _cook_recipe(dish: String) -> void:
	if not _recipe_dragging and Time.get_ticks_msec()>=_recipe_suppress_until:service.start_cooking(dish)
func _boil_recipe() -> void:
	if not _recipe_dragging and Time.get_ticks_msec()>=_recipe_suppress_until:service.start_boiling()
func _refresh_cooking() -> void:
	if is_instance_valid(_fire_status) and is_instance_valid(service.station):
		var seconds:=int(service.station.fuel)
		_fire_status.text=("FIRE ON" if service.station.burning else "FIRE OFF")+"  •  FUEL %d:%02d"%[floori(seconds/60.0),seconds%60]
		_fire_button.text="PUT OUT FIRE" if service.station.burning else "LIGHT FIRE"
	if is_instance_valid(_boil_button):
		_boil_button.disabled=not service.can_boil();_boil_hint.text="Ocean Water Tumbler  %d / 1"%Inventory.total("Ocean Water Tumbler")
	for row in _rows:
		var text_value:=""
		for item in RULES.RECIPES[row.dish].ingredients:
			var need:=int(RULES.RECIPES[row.dish].ingredients[item]);var have:=Inventory.total(item)
			text_value+="[color="+("#8dd49c" if have>=need else "#f28b7f")+"]"+item+"  %d / %d"%[have,need]+"[/color]   "
		if row.ingredients.text!=text_value:row.ingredients.text=text_value
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
