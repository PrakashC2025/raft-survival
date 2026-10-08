extends Control
var service: Node
var box_slot := false
var slot_index := 0
var _start := Vector2.ZERO
var _pressed := false
var _dragged := false
var _touch_owner := -1
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
func entry() -> Dictionary:
	if box_slot:
		if not is_instance_valid(service.storage) or slot_index>=service.storage.contents.size():return {}
		return service.storage.contents[slot_index]
	return Inventory.slot_get(slot_index)
func _draw() -> void:
	var rect:=Rect2(Vector2.ONE,size-Vector2.ONE*2)
	draw_style_box(_style(),rect)
	var data:=entry()
	if data.is_empty():return
	preload("res://scripts/ui_icons.gd").item_icon(self,str(data.item),size*Vector2(.5,.42),minf(size.x,size.y)*.31)
	var font:=ThemeDB.fallback_font
	draw_string(font,Vector2(4,size.y-6),str(data.item),HORIZONTAL_ALIGNMENT_CENTER,size.x-8,10,Color(.9,.91,.84))
	draw_string(font,Vector2(4,15),str(data.count),HORIZONTAL_ALIGNMENT_RIGHT,size.x-8,12,Color.WHITE)
func _style() -> StyleBoxFlat:
	# Cached by the parent panel, shared across every slot.
	return service.ui.slot_style
func _gui_input(event: InputEvent) -> void:
	var down:=false;var up:=false;var position_value:=Vector2.ZERO
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		down=event.pressed;up=not event.pressed;position_value=event.position
	elif event is InputEventScreenTouch:
		if event.pressed and _touch_owner>=0 and event.index!=_touch_owner:return
		if not event.pressed and event.index!=_touch_owner:return
		if event.pressed:_touch_owner=event.index
		down=event.pressed;up=not event.pressed;position_value=event.position
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		if event is InputEventScreenDrag and event.index!=_touch_owner:return
		if _pressed and event.position.distance_to(_start)>6:_dragged=true
		if _pressed:accept_event()
		return
	else:return
	if down:
		_pressed=true;_dragged=false;_start=position_value
		service.ui.drag_source=self
		GameSettings.release_gameplay_input();accept_event()
	elif up and _pressed:
		_pressed=false;_touch_owner=-1;accept_event()
		service.ui.finish_drag(get_global_transform_with_canvas()*position_value,not _dragged)
func _get_drag_data(_position: Vector2) -> Variant:
	if entry().is_empty():return null
	var preview:=Label.new();preview.text=str(entry().item)+" ×"+str(entry().count);set_drag_preview(preview)
	return {"owner":service.get_instance_id(),"box":box_slot,"slot":slot_index}
func _can_drop_data(_position: Vector2,data: Variant) -> bool:
	return data is Dictionary and data.get("owner")==service.get_instance_id() and data.get("slot") is int and data.get("box") is bool
func _drop_data(_position: Vector2,data: Variant) -> void:
	if _can_drop_data(_position,data):service.transfer(data.box,data.slot,box_slot,slot_index)
