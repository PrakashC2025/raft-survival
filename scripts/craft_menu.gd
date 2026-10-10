extends Control
## Native scroll containers own touch drags, wheel input and keyboard focus.
signal build_requested(item: String)
signal closed
const UI := preload("res://scripts/ocean_ui.gd")
class ItemPicture extends Control:
	var item := ""
	func _draw() -> void:
		preload("res://scripts/ui_icons.gd").item_icon(self,item,size*.5,minf(size.x,size.y)*.44)
var cards: Dictionary={}
var selected := ""
var _labels: Dictionary={}
var _sheet: PanelContainer
var _columns: HBoxContainer
var _list: ScrollContainer
var _detail: VBoxContainer
var _contents: VBoxContainer
var _build: Button
var _cancel: Button
var _compact := false

func setup(order: Array, labels: Dictionary) -> void:
	_labels=labels
	process_mode=Node.PROCESS_MODE_ALWAYS
	theme=UI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(.015,.04,.06,.94)
	add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet=PanelContainer.new();add_child(_sheet)
	_sheet.add_theme_stylebox_override("panel",UI.box(Color("092333"),Color("346073"),20))
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",12);_sheet.add_child(column)
	var header:=HBoxContainer.new();column.add_child(header)
	var heading:=_label("CRAFT & BUILD",25);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(heading)
	var close:=Button.new();close.text="Close";close.custom_minimum_size=Vector2(76,48);header.add_child(close);close.pressed.connect(func():closed.emit())
	column.add_child(_label("Choose a product. Review your materials before building.",15,UI.MUTED))
	_columns=HBoxContainer.new();_columns.add_theme_constant_override("separation",16);_columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(_columns)
	_list=ScrollContainer.new();_list.name="RecipeScroll";_list.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_list.size_flags_stretch_ratio=1.0;_list.follow_focus=true;_list.scroll_deadzone=10;_columns.add_child(_list)
	var recipes:=VBoxContainer.new();recipes.size_flags_horizontal=Control.SIZE_EXPAND_FILL;recipes.add_theme_constant_override("separation",8);_list.add_child(recipes)
	recipes.add_child(_label("PRODUCTS  ·  Swipe or scroll",14,UI.MUTED))
	for entry in order:
		var item:=str(entry)
		var card:=Button.new();card.name="Recipe_"+item;card.custom_minimum_size=Vector2(0,80);card.tooltip_text=str(labels.get(item,item))
		card.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
		var row:=HBoxContainer.new();card.add_child(row);row.mouse_filter=Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);row.offset_left=10;row.offset_right=-12;row.offset_top=8;row.offset_bottom=-8
		row.add_child(_picture(item,60))
		var text:=VBoxContainer.new();text.mouse_filter=Control.MOUSE_FILTER_IGNORE;text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
		text.add_child(_label(str(labels.get(item,item)),18))
		text.add_child(_label("Place on your raft" if Inventory.RECIPES.has(item) else "Make and keep in your bag",13,UI.MUTED))
		recipes.add_child(card);cards[item]=card;card.pressed.connect(select_item.bind(item))
	_detail=VBoxContainer.new();_detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_detail.size_flags_stretch_ratio=1.15;_detail.add_theme_constant_override("separation",12);_columns.add_child(_detail)
	var detail_scroll:=ScrollContainer.new();detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;detail_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;_detail.add_child(detail_scroll)
	_contents=VBoxContainer.new();_contents.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_contents.add_theme_constant_override("separation",12);detail_scroll.add_child(_contents)
	var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",10);_detail.add_child(actions)
	_cancel=Button.new();_cancel.text="Cancel";_cancel.custom_minimum_size.y=54;_cancel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(_cancel)
	_cancel.pressed.connect(func():select_item(""))
	_build=Button.new();_build.text="Build";_build.custom_minimum_size.y=54;_build.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(_build)
	_build.add_theme_stylebox_override("normal",UI.box(Color("15595c"),UI.AQUA))
	_build.pressed.connect(func():
		if not selected.is_empty() and not _build.disabled:build_requested.emit(selected))
	Inventory.changed.connect(_refresh_detail)
	resized.connect(_fit)
	_refresh_detail();_fit()

func _label(value: String, font_size: int=18, color: Color=UI.TEXT) -> Label:
	var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",color)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return label

func _picture(item: String, extent: float) -> Control:
	var picture:=ItemPicture.new();picture.item=item;picture.custom_minimum_size=Vector2.ONE*extent;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return picture

func _fit() -> void:
	if _sheet==null:return
	var ui_scale:=UI.scale_for(get_viewport())
	var view:=get_viewport_rect().size/ui_scale
	_compact=view.x<660
	_sheet.scale=Vector2.ONE*ui_scale
	_sheet.position=Vector2(12,12)*ui_scale
	_sheet.size=view-Vector2(24,24)
	_list.visible=not _compact or selected.is_empty()
	_detail.visible=not _compact or not selected.is_empty()

func select_item(item: String) -> void:
	selected=item
	_refresh_detail();_fit()

func _refresh_detail() -> void:
	if _contents==null:return
	for child in _contents.get_children():_contents.remove_child(child);child.queue_free()
	for item in cards:
		var card:=cards[item] as Button
		if item==selected:card.add_theme_stylebox_override("normal",UI.box(Color("154752"),UI.AQUA))
		else:card.remove_theme_stylebox_override("normal")
	_cancel.visible=not selected.is_empty();_build.visible=not selected.is_empty()
	if selected.is_empty():
		_contents.add_child(_label("MAKE YOUR NEXT SURVIVAL TOOL",23))
		_contents.add_child(_label("Scroll through the products, then select one to see its ingredients and purpose.",18,UI.MUTED))
		return
	_contents.add_child(_label(str(_labels.get(selected,selected)),25))
	_contents.add_child(_picture(selected,144))
	var hints: Dictionary={"WindGenerator":"Outdoor wind charges its battery. Walls and ceilings block its rotor. Equip Wire to connect nearby lights, pumps or radios.","Wire":"One Wire connects two metres of cable. Aim at a generator, use, then aim at the equipment and use again.","FishingNet":"Hang off a clear raft edge over the sea. Small fish collect in the weighted net. Aim at it to collect your catch.","Barrel":"Wooden staves, metal bands and rope. Used to build a rain collector.","Torch":"Light at a burning campfire. Mount on clear solid timber. Burns until dawn.","PlanterPot":"Root crops. Place on a foundation or roof.","TreePot":"Trees. Place on a foundation or roof."}
	hints.SeedDryingTray="Spread wet fruit seeds on this wooden tray. Dry for two minutes, shelter from rain, then collect for your garden."
	_contents.add_child(_label(str(hints.get(selected,"Choose a place, then press Place. Materials are spent only when it is placed." if Inventory.RECIPES.has(selected) else "Build one item and keep it in your bag.")),16,UI.MUTED))
	_contents.add_child(_label("MATERIALS                 HAVE / NEED",14,UI.AQUA))
	var costs: Dictionary=Inventory.recipe_cost(selected) if Inventory.RECIPES.has(selected) else Inventory.ITEM_RECIPES.get(selected,{})
	for item in costs:
		var row:=HBoxContainer.new();row.custom_minimum_size.y=38;_contents.add_child(row)
		row.add_child(_picture(str(item),32));row.add_child(_label(str(item),17))
		var have:=Inventory.total(item);var need:=int(costs[item])
		var count:=_label("%d / %d"%[have,need],17,UI.AQUA if have>=need else Color("ffad88"));count.custom_minimum_size.x=110;count.size_flags_horizontal=Control.SIZE_SHRINK_END;row.add_child(count)
	var can_build: bool=Inventory.can_afford(selected) if Inventory.RECIPES.has(selected) else Inventory.can_craft_item(selected)
	_build.disabled=not can_build
	if not can_build:
		_contents.add_child(_label("Complete your current mission to unlock this." if not Inventory.recipe_unlocked(selected) else "Gather the missing materials or free space in your bag.",16,Color("ffad88")))
