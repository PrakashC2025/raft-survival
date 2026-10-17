extends CanvasLayer
## Fade over a position change while the vessel, oars, waves and sound keep running.
const FADE_OUT:=.6
const FADE_IN:=.85
var player: CharacterBody3D
var vehicle: Node3D
var active:=true
var committed:=false
var phase:="out"
var elapsed:=0.0
var _black: ColorRect
var _caption: Label
var _physics_frames:=0
var _floor_layers:=0
var _leave_mode:=CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
var _reveal_alpha:=1.0
var _platform_held:=false
var _stream: Node3D

func _ready() -> void:
	name="TripTransition";layer=150;process_mode=Node.PROCESS_MODE_ALWAYS
	vehicle.set_meta("trip_skip_active",true)
	_black=ColorRect.new();_black.color=Color(0,0,0,0);_black.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(_black);_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption=Label.new();_caption.text="Sailing closer...";_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size",20);_caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_black.add_child(_caption);_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_caption.offset_left=-240;_caption.offset_right=240;_caption.offset_top=-20;_caption.offset_bottom=20;_caption.hide()
	GameSettings.release_gameplay_input()
	player.rope_system._force_cancel()
	_floor_layers=player.platform_floor_layers;_leave_mode=player.platform_on_leave
	player.platform_floor_layers=0;player.platform_on_leave=CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING;_platform_held=true

func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not active:return
	if not is_instance_valid(player) or not is_instance_valid(vehicle) or Stats.health<=0 or get_tree().paused or GameSettings.is_open:
		cancel();return
	if not vehicle.has_active_course() or not preload("res://scripts/course_skip.gd").aboard(vehicle,player):
		if phase!="in":_reveal_alpha=_black.color.a;phase="in";elapsed=0
	elapsed+=minf(delta,.05)
	match phase:
		"out":
			_black.color.a=smoothstep(0,FADE_OUT,elapsed)
			if elapsed>=FADE_OUT:phase="move";elapsed=0;_black.color.a=1
		"move":_black.color.a=1
		"warm":
			_caption.visible=elapsed>.7
			var water_ready: bool=not is_instance_valid(_stream) or bool(_stream.call("ready_at",Vector2(player.global_position.x,player.global_position.z)))
			if _physics_frames>=3 and elapsed>=.2 and (water_ready or elapsed>=2.0):phase="in";elapsed=0;_caption.hide()
		"in":
			_black.color.a=_reveal_alpha*(1-smoothstep(0,FADE_IN,elapsed))
			if elapsed>=FADE_IN:_finish()

func _physics_process(_delta: float) -> void:
	if not active:return
	if not is_instance_valid(player) or not is_instance_valid(vehicle) or Stats.health<=0 or get_tree().paused:
		cancel();return
	if phase=="move":
		# Manual raft carrying owns the passenger for the whole fade, preventing
		# a second platform displacement or a launch from the large relocation.
		committed=bool(vehicle.call("skip_course"));phase="warm";elapsed=0;_physics_frames=0
		var world:=get_tree().get_first_node_in_group("underwater_world")
		if committed and world!=null and is_instance_valid(world.get("stream")):
			_stream=world.get("stream");_stream.call("request_position",Vector2(player.global_position.x,player.global_position.z))
		if not committed:player.call("_hud_toast","NO CLEAR WATER TO SKIP · KEEP SAILING")
	elif phase in ["warm","in"]:
		_physics_frames+=1
		if _physics_frames==3:
			if committed:player.call("_queue_save")

func cancel() -> void:
	_finish()

func _release_platform() -> void:
	if _platform_held and is_instance_valid(player):
		player.platform_floor_layers=_floor_layers;player.platform_on_leave=_leave_mode
	_platform_held=false

func _finish() -> void:
	if not active:return
	active=false;_release_platform()
	if is_instance_valid(vehicle):vehicle.remove_meta("trip_skip_active")
	GameSettings.release_gameplay_input();_black.hide();queue_free()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT] and is_instance_valid(_black):cancel()

func _exit_tree() -> void:
	_release_platform()
	if is_instance_valid(vehicle):vehicle.remove_meta("trip_skip_active")
