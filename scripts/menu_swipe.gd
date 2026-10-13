extends Node
## Own a single finger/mouse drag even when it begins over a button.
var areas: Array[ScrollContainer]=[]
var _owner := -1
var _scroll: ScrollContainer
var _start := Vector2.ZERO
var _dragging := false
var _position := 0.0
var _velocity := 0.0
var _last_motion := 0
var _suppress_until := 0

func tap_allowed() -> bool:
	return not _dragging and Time.get_ticks_msec()>=_suppress_until

func _begin(at: Vector2, owner_id: int) -> void:
	_velocity=0
	for area in areas:
		if area.is_visible_in_tree() and area.get_global_rect().has_point(at):
			_scroll=area;_owner=owner_id;_start=at;_dragging=false
			_position=float(area.scroll_vertical);_last_motion=Time.get_ticks_msec()
			return

func _move(at: Vector2, relative: Vector2) -> void:
	if not is_instance_valid(_scroll):return
	if not _dragging and at.distance_to(_start)>10.0:_dragging=true
	if not _dragging:return
	var now:=Time.get_ticks_msec()
	var scale_y:=maxf(.01,_scroll.get_global_transform().get_scale().y)
	var travel:=-relative.y/scale_y
	var seconds:=maxf(.008,float(now-_last_motion)/1000.0)
	_velocity=lerpf(_velocity,clampf(travel/seconds,-2200,2200),.55)
	_last_motion=now
	_scroll_to(_position+travel)
	get_viewport().set_input_as_handled()

func _release() -> void:
	_owner=-1
	if _dragging:
		_suppress_until=Time.get_ticks_msec()+180
		if Time.get_ticks_msec()-_last_motion>100:_velocity=0
		_finish.call_deferred()

func _finish() -> void:
	if _owner==-1:_dragging=false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _owner==-1:_begin(event.position,event.index)
		elif not event.pressed and event.index==_owner:
			if event.canceled:_velocity=0;_suppress_until=Time.get_ticks_msec()+180
			_release()
	elif event is InputEventScreenDrag and event.index==_owner:_move(event.position,event.relative)
	elif event is InputEventMouseButton and event.device!=InputEvent.DEVICE_ID_EMULATION:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:_velocity=0
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed and _owner==-1:_begin(event.position,-2)
			elif not event.pressed and _owner==-2:_release()
	elif event is InputEventMouseMotion:
		if event.device==InputEvent.DEVICE_ID_EMULATION and _dragging:get_viewport().set_input_as_handled()
		elif _owner==-2:_move(event.position,event.relative)

func _scroll_to(value: float) -> void:
	var bar:=_scroll.get_v_scroll_bar()
	_position=clampf(value,0,maxf(0,bar.max_value-bar.page))
	_scroll.scroll_vertical=roundi(_position)
	if not is_equal_approx(value,_position):_velocity=0

func _process(delta: float) -> void:
	if _owner!=-1 or absf(_velocity)<15:return
	if not is_instance_valid(_scroll) or not _scroll.is_visible_in_tree():_velocity=0;return
	_scroll_to(_position+_velocity*minf(delta,.05))
	_velocity*=exp(-delta*8.0)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		_owner=-1;_dragging=false;_velocity=0;_suppress_until=Time.get_ticks_msec()+180
