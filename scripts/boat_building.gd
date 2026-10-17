extends Node
## Build costs commit once after the visible assembly; launching is a separate action.
const BOAT:=preload("res://scripts/rowboat.gd")
const DURATION:=5.5
var player: CharacterBody3D
var boat: CharacterBody3D
var menu_open:=false
var building:=false
var ready_to_launch:=false
var elapsed:=0.0
var workshop: Node3D
var _assembly: Node3D
var _cost: Dictionary={}
var _damage_revision:=0
var _layer: CanvasLayer
var _panel: Control
var _status: Label
var _build_button: Button
var _launch_button: Button
var _restore_done:=false
var _restoring:=false
var _needs_workshop:=false
var _ui_clock:=0.0

func _ready() -> void:
	player=get_parent() as CharacterBody3D
	var screen:=preload("res://scripts/boat_workshop_ui.gd").new();screen.service=self;add_child(screen)
	_layer=screen;_panel=screen.panel;_status=screen.status;_build_button=screen.build_button;_launch_button=screen.launch_button

func open(target: Node3D) -> void:
	if building or player.build_mode or Stats.health<=0 or get_tree().paused:return
	if not is_instance_valid(target) or player.global_position.distance_to(target.global_position)>5:return
	workshop=target;menu_open=true;GameSettings.release_gameplay_input();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_refresh();_layer.show()
	if ready_to_launch:_show_assembly(1.0)

func _refresh() -> void:
	_layer.call("refresh")

func close() -> void:
	if building:cancel_build()
	menu_open=false;_layer.hide();GameSettings.release_gameplay_input()
	if not get_tree().paused and not GameSettings.is_open:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func start_build(target: Node3D=null) -> bool:
	if building or ready_to_launch or is_instance_valid(boat) or Stats.health<=0 or get_tree().paused or GameSettings.is_open or player.build_mode:return false
	if player.is_swimming or is_instance_valid(player.boat_vehicle) or is_instance_valid(player.get("_editing")):return false
	if is_instance_valid(target):
		if not target.is_in_group("boat_workshop") or player.global_position.distance_to(target.global_position)>5:return false
	else:
		var raft:=get_tree().get_first_node_in_group("raft") as Node3D
		if raft==null or not player.rope_system.can_cast_from_raft() or not Inventory.has("Rowboat Kit",1):return false
	_cost={"Rowboat Kit":1} if Inventory.has("Rowboat Kit",1) else Inventory.ITEM_RECIPES["Rowboat Kit"].duplicate()
	if not Inventory.can_exchange(_cost,{}):return false
	workshop=target;_needs_workshop=is_instance_valid(target);building=true;elapsed=0;_damage_revision=Stats.damage_revision
	GameSettings.release_gameplay_input()
	if is_instance_valid(workshop):_show_assembly(0)
	if menu_open:_refresh()
	player.call("play_action","build",DURATION,workshop.global_position if is_instance_valid(workshop) else player.global_position)
	return true

func _show_assembly(progress: float) -> void:
	if not is_instance_valid(workshop):return
	if not is_instance_valid(_assembly):
		_assembly=preload("res://scripts/rowboat_visual.gd").create();_assembly.name="BoatBeingAssembled";_assembly.position=Vector3(0,.66,0);_assembly.rotation.y=PI/2;_assembly.scale=Vector3.ONE*.72;workshop.add_child(_assembly)
	preload("res://scripts/rowboat_visual.gd").assemble(_assembly,progress)

func cancel_build() -> void:
	if not building:return
	building=false;_cost.clear();player.get_node("SurvivalAction").stop()
	if is_instance_valid(_assembly):_assembly.queue_free()
	_assembly=null;player.call("_hud_toast","BOAT ASSEMBLY CANCELLED · MATERIALS KEPT")
	if menu_open:_refresh()

func _process(delta: float) -> void:
	if menu_open:
		if Stats.health<=0 or not is_instance_valid(workshop) or player.global_position.distance_to(workshop.global_position)>5:close()
		else:
			_ui_clock+=delta
			if _ui_clock>=.1:_ui_clock=0;_refresh()
	if not building:return
	var raft:=get_tree().get_first_node_in_group("raft") as Node3D
	if Stats.health<=0 or Stats.damage_revision!=_damage_revision or player.is_swimming or is_instance_valid(player.boat_vehicle) or GameSettings.is_open or (_needs_workshop and not is_instance_valid(workshop)) or (is_instance_valid(workshop) and player.global_position.distance_to(workshop.global_position)>5) or (not is_instance_valid(workshop) and (raft==null or not player.rope_system.can_cast_from_raft())):
		cancel_build();return
	elapsed+=delta
	_show_assembly(clampf(elapsed/DURATION,0,1))
	if elapsed<DURATION:return
	if not Inventory.try_exchange(_cost,{}):cancel_build();return
	building=false;_cost.clear();ready_to_launch=true;player.raft_boat_built=true
	if raft!=null:raft.call("set_rowboat_built",true)
	player.get_node("SurvivalAction").stop();player.call("_queue_save")
	if is_instance_valid(workshop):open(workshop)
	else:launch()

func _launch_position() -> Vector3:
	var raft:=get_tree().get_first_node_in_group("raft") as Node3D
	if raft==null:return Vector3.INF
	raft.call("_refresh_deck_samples")
	var distance_value: float=float(raft.get("_deck_radius"))+3.2
	for index in 48:
		var angle:=float(index%16)*TAU/16
		var at:=raft.global_position+Vector3(cos(angle),0,sin(angle))*(distance_value+float(floori(index/16.0))*5.0);at.y=.03
		var ocean:=get_tree().get_first_node_in_group("ocean")
		if ocean!=null:at.y=float(ocean.call("get_height",at))+.03
		var query:=PhysicsShapeQueryParameters3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.65,1.2,3.7);query.shape=box
		query.transform=Transform3D(Basis.IDENTITY,at);query.collision_mask=1
		var excluded: Array[RID]=[player.get_rid()]
		if is_instance_valid(boat):excluded.append(boat.get_rid())
		query.exclude=excluded
		if player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return at
	return Vector3.INF

func launch() -> bool:
	if not ready_to_launch or is_instance_valid(boat) or building or Stats.health<=0:return false
	var at:=_launch_position()
	if not at.is_finite():player.call("_hud_toast","NO CLEAR WATER BESIDE THE RAFT · MOVE AWAY FROM SHORE");return false
	boat=BOAT.new();boat.position=at;get_tree().current_scene.add_child(boat)
	ready_to_launch=false
	if is_instance_valid(_assembly):_assembly.queue_free()
	_assembly=null;close();player.call("_queue_save");player.call("_hud_toast","BOAT LAUNCHED · APPROACH IT AND TAP BOARD ROWBOAT",4.0)
	return true

func return_home() -> void:
	if not is_instance_valid(boat):return
	boat.call("_release_driver");boat.clear_course();boat.velocity=Vector3.ZERO
	var at:=_launch_position()
	if at.is_finite():
		boat.global_position=at;boat.rotation.y=0
	else:
		# Preserve the completed boat when shore encloses every launch position.
		var raft:=get_tree().get_first_node_in_group("raft") as Node3D
		for cargo in boat.get_children():
			if cargo.is_in_group("animal_carcass") and raft!=null:cargo.reparent(raft,false);cargo.position=Vector3(.8,.6,.8)
		boat.queue_free();boat=null;ready_to_launch=true

func restore() -> void:
	if _restore_done:return
	_restore_done=true;_restoring=true
	var stored: Variant=Inventory.loaded_meta.get("rowboat",{})
	if stored is Dictionary and stored.get("ready",false)==true:ready_to_launch=true;_restoring=false;return
	if stored is Dictionary and stored.get("p") is Array and stored.p.size()==3:
		var at:=Vector3(float(stored.p[0]),float(stored.p[1]),float(stored.p[2]))
		if at.is_finite() and at.length()<200000:
			boat=BOAT.new();boat.position=at;boat.rotation.y=float(stored.get("yaw",0));get_tree().current_scene.add_child(boat)
			if stored.get("aboard",false)==true or stored.get("traveller_p") is Array:
				while not _world_ready():
					await get_tree().physics_frame
					if not is_inside_tree():return
				if stored.get("aboard",false)==true:boat.board(player,true)
				elif stored.traveller_p.size()==3:
					var position_value:=Vector3(float(stored.traveller_p[0]),float(stored.traveller_p[1]),float(stored.traveller_p[2]))
					if position_value.is_finite() and position_value.length()<200000:player.global_position=position_value;player.velocity=Vector3.ZERO
			_restoring=false;return
	_restoring=false
	if player.raft_boat_built:ready_to_launch=true;launch()

func _world_ready() -> bool:
	if not player.restoration_complete:return false
	var setup:=get_tree().current_scene.get_node_or_null("IslandSetup")
	if setup!=null and not setup.setup_complete:return false
	for island in get_tree().get_nodes_in_group("biome_island"):
		if not island.prepared:return false
	return true

func save_state() -> Dictionary:
	if not _restore_done or _restoring:return Inventory.loaded_meta.get("rowboat",{}).duplicate(true)
	if is_instance_valid(boat):
		var state: Dictionary=boat.save_state();var at:=player.global_position
		state["traveller_p"]=[at.x,at.y,at.z];return state
	return {"ready":true} if ready_to_launch else {}

func _input(event: InputEvent) -> void:
	if menu_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled();close()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		if building:cancel_build()
		if menu_open:close()
