extends Node
## Carry one hunted body; placement and butchering never duplicate its contents.
const UI:=preload("res://scripts/ocean_ui.gd")
const CORPSE:=preload("res://scripts/animal_carcass.gd")
const CONTACT:=preload("res://scripts/contact_audio.gd")
var player: CharacterBody3D
var held: StaticBody3D
var target: StaticBody3D
var menu_open:=false
var pending: Dictionary={}
var _layer: CanvasLayer
var _title: Label
var _status: Label
var _take: Button
var _prepare: Button
var _tick:=0.0
var _view: Node3D
var _hint: Label

func _ready() -> void:
	player=get_parent() as CharacterBody3D
	_layer=CanvasLayer.new();_layer.layer=15;add_child(_layer)
	var shade:=ColorRect.new();shade.color=Color(.015,.025,.03,.85);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_layer.add_child(shade)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_layer.add_child(center)
	var card:=PanelContainer.new();card.theme=UI.theme();card.custom_minimum_size.x=540;card.add_theme_stylebox_override("panel",UI.box(Color("0c2836"),Color("d5b573")));center.add_child(card)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",12);card.add_child(column)
	_title=Label.new();_title.add_theme_font_size_override("font_size",26);column.add_child(_title)
	_status=Label.new();_status.custom_minimum_size=Vector2(500,85);_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(_status)
	_take=Button.new();_take.text="CARRY WHOLE ANIMAL";_take.custom_minimum_size.y=56;column.add_child(_take);_take.pressed.connect(func():var body:=target;close();take(body))
	_prepare=Button.new();_prepare.text="PREPARE MEAT · 2.4 s";_prepare.custom_minimum_size.y=56;column.add_child(_prepare);_prepare.pressed.connect(func():var body:=target;close();prepare(body))
	var close_button:=Button.new();close_button.text="CLOSE";close_button.custom_minimum_size.y=52;column.add_child(close_button);close_button.pressed.connect(close);_layer.hide()
	_hint=Label.new();_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;_hint.add_theme_font_size_override("font_size",17);_hint.add_theme_color_override("font_shadow_color",Color.BLACK);_hint.add_theme_constant_override("shadow_outline_size",3);player.get_node("CanvasLayer").add_child(_hint);_hint.hide()

func busy() -> bool:return not pending.is_empty()
func _blocked() -> bool:
	return Stats.health<=0 or get_tree().paused or GameSettings.is_open or player.build_mode or player.get_node("CanvasLayer/SurvivalHUD").gameplay_input_blocked()
func open(body: StaticBody3D) -> void:
	if _blocked() or not is_instance_valid(body) or body.empty() or player.global_position.distance_to(body.global_position)>5:return
	target=body;menu_open=true;GameSettings.release_gameplay_input();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_title.text="HUNTED "+str(body.species).to_upper();_status.text="Carry the whole animal, place it on land or water, or load it into your rowboat. Prepare its meat here or after bringing it home. Cook raw meat before eating."
	_take.disabled=is_instance_valid(held) or is_instance_valid(player.boat_vehicle);_prepare.disabled=not _can_store(body)
	_layer.show()
	player.play_world_sfx(CONTACT.pick_action("cloth"),-16,body.global_position)
func close() -> void:
	menu_open=false;target=null;_layer.hide();GameSettings.release_gameplay_input()
	if not get_tree().paused and not GameSettings.is_open:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func _can_store(body: StaticBody3D) -> bool:
	var rewards: Dictionary={}
	for entry in body.contents:
		if not entry.is_empty():rewards[entry.item]=int(rewards.get(entry.item,0))+int(entry.count)
	return Inventory.can_exchange({},rewards)

func take(body: StaticBody3D) -> bool:
	if _blocked() or busy() or is_instance_valid(held) or is_instance_valid(player.boat_vehicle) or not is_instance_valid(body) or body.empty() or player.global_position.distance_to(body.global_position)>5:return false
	held=body;held.reparent(get_tree().current_scene,true);held.carried=true;held.floating=false;held.collision_layer=0
	held.get_node("CarcassCaption").hide()
	player.rope_system._force_cancel();player.get_node("SurvivalEquipment").cancel_draw()
	_view=CORPSE.make_visual(held.species);player.get_node("CamPivot/SpringArm3D/Camera3D").add_child(_view);_view.position=Vector3(0,-.65,-1.15);_view.rotation.y=PI/2;_view.scale=Vector3.ONE*(.50 if held.species in ["Boar","Crocodile"] else .85)
	for left in [false,true]:
		var hand:=preload("res://scripts/dive_visual.gd").swim_hand(left);_view.add_child(hand);hand.position=Vector3(0,-.1,.45 if left else -.45);hand.rotation.y=-PI/2
	player.play_action("lift_carcass",1.1,held.global_position);player.play_world_sfx(CONTACT.pick_action("body_impact"),-9,held.global_position)
	player._apply_camera_mode()
	player._queue_save();return true

func _clear_hold() -> void:
	if is_instance_valid(_view):_view.queue_free()
	_view=null
	if is_instance_valid(held):held.carried=false;held.visible=true;held.collision_layer=2;held.get_node("CarcassCaption").show()
	held=null;_hint.hide()
	player._apply_camera_mode()

func load_boat(boat: CharacterBody3D) -> bool:
	if not is_instance_valid(held) or not is_instance_valid(boat):return false
	var cargo:=boat.get_children().filter(func(node):return node.is_in_group("animal_carcass"))
	if cargo.size()>=2:player._hud_toast("BOAT CARGO FULL · PLACE OR PREPARE THIS ANIMAL FIRST");return false
	var body:=held;_clear_hold();body.reparent(boat,false);body.position=Vector3(.30 if cargo.is_empty() else -.30,.24,-.55);body.rotation=Vector3(0,0,0);body.floating=false
	player.play_world_sfx(CONTACT.pick_action("body_impact"),-6,boat.global_position);player._queue_save();return true

func place() -> bool:
	if _blocked() or busy() or not is_instance_valid(held):return false
	var boat:=_aimed_boat()
	if boat!=null:return load_boat(boat)
	var from: Vector3=player.camera.global_position
	var to: Vector3=from-player.camera.global_basis.z*3.4
	var hit:=player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1,[player.get_rid()]))
	var at:=player.global_position-player.global_basis.z*1.5;var support: Node3D
	if not hit.is_empty():
		if Vector3(hit.normal).y<.5:player._hud_toast("AIM AT FLAT GROUND OR OPEN WATER");return false
		at=hit.position;support=hit.collider as Node3D
	else:
		var ground:=player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*2,at+Vector3.DOWN*8,1,[player.get_rid()]))
		if not ground.is_empty():at=ground.position;support=ground.collider as Node3D
	var sea:=get_tree().get_first_node_in_group("ocean") as Node3D
	var water_y: float=float(sea.call("get_height",at)) if sea!=null else 0.0
	var floating:=support==null or at.y<water_y
	if floating:at.y=water_y+.12
	var body:=held;_clear_hold();body.global_position=at;body.rotation=Vector3(0,player.rotation.y+PI/2,0);body.floating=floating
	while support!=null and not support.is_in_group("raft"):support=support.get_parent() as Node3D
	if support!=null:body.reparent(support,true)
	player.play_action("place_carcass",.9,at);player.play_world_sfx(CONTACT.pick_action("water" if floating else "body_impact"),-7,at);player._queue_save();return true

func _aimed_boat() -> CharacterBody3D:
	var node: Node=player.aim_collider if is_instance_valid(player.aim_collider) else null
	while node!=null:
		if node.is_in_group("player_boat") and player.global_position.distance_to((node as Node3D).global_position)<5:return node as CharacterBody3D
		node=node.get_parent()
	return null

func prepare(body: StaticBody3D) -> bool:
	if _blocked() or busy() or not is_instance_valid(body) or body.empty() or player.global_position.distance_to(body.global_position)>5:return false
	if not _can_store(body):player._hud_toast("BAG FULL · ANIMAL AND MEAT KEPT");return false
	pending={"kind":"butcher","body":body,"age":0.0,"duration":2.4,"damage":Stats.damage_revision,"at":player.global_position}
	player.play_action("prepare_animal",2.4,body.global_position);return true

func wrap_meal(item: String) -> bool:
	if _blocked() or busy() or not preload("res://scripts/food_rules.gd").RECIPES.has(item):return false
	if not Inventory.can_exchange({item:1,"Cooking Foil":1},{"Wrapped "+item:1}):return false
	pending={"kind":"wrap","item":item,"age":0.0,"duration":1.6,"damage":Stats.damage_revision,"at":player.global_position}
	player.play_action("wrap_food",1.6,Vector3.ZERO,item);return true

func cancel() -> void:
	if pending.is_empty():return
	pending.clear();player.get_node("SurvivalAction").stop();player._hud_toast("CANCELLED · FOOD AND MATERIALS KEPT")

func on_death() -> void:
	cancel();close()
	if not is_instance_valid(held):return
	var raft:=get_tree().get_first_node_in_group("raft") as Node3D
	var body:=held;_clear_hold()
	if raft!=null:body.reparent(raft,false);body.position=Vector3(.8,.6,.8);body.floating=false

func restore_support(body: StaticBody3D,entry: Dictionary) -> void:
	if not entry.get("local_p") is Array or entry.local_p.size()!=3:return
	for coordinate in entry.local_p:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):return
	var local_position:=Vector3(float(entry.local_p[0]),float(entry.local_p[1]),float(entry.local_p[2]))
	if not local_position.is_finite() or local_position.length()>100:return
	var boats:=player.get_node("BoatBuilding")
	while not player.restoration_complete or not boats._restore_done or boats._restoring:
		await get_tree().physics_frame
		if not is_instance_valid(body) or not is_inside_tree():return
	var support: Node3D=boats.boat if entry.support=="boat" else get_tree().get_first_node_in_group("raft")
	if is_instance_valid(support):body.reparent(support,false);body.position=local_position;body.floating=false

func restore_carried(body: StaticBody3D) -> void:
	var boats:=player.get_node("BoatBuilding")
	while not player.restoration_complete or not boats._restore_done or boats._restoring or not player.get_node("SurvivalAction").hands_prepared:
		await get_tree().physics_frame
		if not is_instance_valid(body) or not is_inside_tree():return
	body.global_position=player.global_position+Vector3(0,0,-1)
	if not is_instance_valid(held) and not is_instance_valid(player.boat_vehicle):take(body)

func _process(delta: float) -> void:
	if menu_open and (not is_instance_valid(target) or Stats.health<=0 or player.global_position.distance_to(target.global_position)>5):close()
	if not pending.is_empty():
		if _blocked() or Stats.damage_revision!=int(pending.damage) or player.global_position.distance_to(pending.at)>.4:cancel()
		else:
			pending.age=float(pending.age)+delta
			if float(pending.age)>=float(pending.duration):_finish()
	if not is_instance_valid(held):return
	player._set_viewmodel_visible(player.cam_mode==0)
	if is_instance_valid(player._third_person_launcher):player._third_person_launcher.hide()
	held.global_transform=Transform3D(player.global_basis*Basis(Vector3.UP,PI/2),player.to_global(Vector3(0,.15,-.9)))
	held.visible=player.cam_mode!=0;_view.visible=player.cam_mode==0
	_hint.text="CARRYING "+str(held.species).to_upper()+" · USE TO PLACE / LOAD BOAT"
	_hint.position=Vector2(16,get_viewport().get_visible_rect().size.y*.57);_hint.show()
	_tick+=delta
	if _tick>.8:player.play_world_sfx(CONTACT.pick_action("cloth"),-23);_tick=0

func _finish() -> void:
	var success:=false
	if pending.kind=="wrap":success=Inventory.try_exchange({str(pending.item):1,"Cooking Foil":1},{"Wrapped "+str(pending.item):1})
	else:
		var body:=pending.body as StaticBody3D
		if is_instance_valid(body) and not body.empty() and player.global_position.distance_to(body.global_position)<=5:
			var rewards: Dictionary={}
			for entry in body.contents:
				if not entry.is_empty():rewards[entry.item]=int(rewards.get(entry.item,0))+int(entry.count)
			success=Inventory.try_exchange({},rewards)
			if success:
				if body==held:_clear_hold()
				body.contents.fill({});body.queue_free()
	pending.clear();player.get_node("SurvivalAction").stop();player.play_world_sfx(CONTACT.pick_action("cloth"),-9)
	player._hud_toast("PREPARED · STORED IN YOUR BAG" if success else "BAG FULL OR MATERIALS CHANGED · ITEMS KEPT");player._queue_save()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:cancel();close()
