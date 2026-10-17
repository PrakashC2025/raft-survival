extends SceneTree
const TERRAIN:=preload("res://scripts/underwater_terrain.gd")
var checks:=0
var failures:=0
var preview:=false
var recent_meshes: Array[String]=[]
var player: CharacterBody3D
func _initialize() -> void:
	node_added.connect(func(node: Node):
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			recent_meshes.append(str(Engine.get_process_frames())+":"+str(node.get_path()))
			if recent_meshes.size()>12:recent_meshes.pop_front())
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await process_frame
func sample(label: String,count: int=45) -> void:
	var timings: Array[int]=[];var t:=Time.get_ticks_msec()
	var pipelines: Dictionary={}
	for tag in ClassDB.class_get_enum_constants("Performance","Monitor"):
		if tag.begins_with("PIPELINE_COMPILATIONS_"):
			pipelines[tag]=Performance.get_monitor(ClassDB.class_get_integer_constant("Performance",tag))
	for unused in count:
		await process_frame
		var now:=Time.get_ticks_msec();timings.append(now-t)
		if now-t>100:
			print("HITCH SPIKE ",label," process CPU ",Performance.get_monitor(Performance.TIME_PROCESS)*1000," ms; physics CPU ",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000," ms")
			print("HITCH RECENT MESHES ",recent_meshes)
			for tag in pipelines:
				print("HITCH PIPELINE ",tag," +",Performance.get_monitor(ClassDB.class_get_integer_constant("Performance",tag))-float(pipelines[tag]))
		t=now
	timings.sort()
	print("HITCH DIAGNOSTIC ",label,": median ",timings[floori(count/2.0)]," ms; p95 ",timings[floori(count*.95)]," ms; max ",timings[-1]," ms (desktop only)")
func touch(at: Vector2,down: bool,id: int=7) -> void:
	var event:=InputEventScreenTouch.new();event.position=at;event.pressed=down;event.index=id
	var mouse:=InputEventMouseButton.new();mouse.device=InputEvent.DEVICE_ID_EMULATION;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.position=at;mouse.pressed=down
	if down:root.push_input(event,true);root.push_input(mouse,true)
	else:root.push_input(mouse,true);root.push_input(event,true)
func drag(at: Vector2,relative: Vector2,id: int=7) -> void:
	var event:=InputEventScreenDrag.new();event.position=at;event.relative=relative;event.index=id;root.push_input(event,true)
func shot(label: String) -> void:
	if not preview:return
	await frames(3);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/craft-hitch-"+label+".png")==OK,"Rendered "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	create_timer(150).timeout.connect(func():push_error("FAIL: craft/ocean timeout");quit(1))
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	var inv:=root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player") as CharacterBody3D
	var sea:=current_scene.get_node("UnderwaterWorld")
	for unused in 3000:
		await frames(1)
		if sea.prepared and player.restoration_complete and player.get_node("SurvivalAction").hands_prepared and player.get_node("SurvivalServices").ui.cooking_prepared and current_scene.get_node("SpringIsle").prepared and not sea.stream._busy and sea.stream._pending.is_empty():break
	check(sea.prepared and player.restoration_complete,"World finishes normal setup in isolated storage")
	player.set_process(false);player.set_physics_process(false)
	player.get_node("RainSystem").stop_rain();player.get_node("SurvivalProgression").set_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	var hud:=player.get_node("CanvasLayer/SurvivalHUD");hud.toggle_crafting();await frames(6)
	var menu: Control=hud._craft_menu
	check(inv.ITEM_RECIPES.keys().all(func(item):return menu.cards.has(item)) and player.BUILD_RECIPE_NAMES.all(func(item):return menu.cards.has(item)),"Craft contains every bag recipe and supported camp project")
	var supported_only:=true
	for item in inv.RECIPES:
		if menu.cards.has(item) and not player.BUILD_RECIPE_NAMES.has(item):supported_only=false
	check(supported_only,"Camp recipes expose only supported placements, excluding legacy structures")
	check(player.BUILD_RECIPE_NAMES.has("Wall") and player.BUILD_RECIPE_NAMES.has("Roof"),"Walls and roofs remain available in Build")
	var card: Button=menu.cards.Torch
	var origin:=card.get_global_rect().get_center();var before: int=menu._list.scroll_vertical
	touch(origin,true);await frames(1)
	drag(origin+Vector2(0,-110),Vector2(0,-110));await frames(1)
	touch(origin+Vector2(0,-110),false);await frames(4)
	check(menu._list.scroll_vertical>before+50,"Swipe over a product card scrolls the actual craft list")
	check(menu.selected.is_empty(),"Swipe release cannot accidentally select a product")
	await create_timer(.25).timeout
	menu._swipe._velocity=0;menu._list.scroll_vertical=0;await frames(3)
	origin=card.get_global_rect().get_center();touch(origin,true);await frames(1);touch(origin,false);await frames(2)
	check(menu.selected=="Torch" if preview else true,"Ordinary card taps still select on release in the native renderer")
	menu.select_item("Torch");await frames(3)
	var detail: Node=menu._contents.get_child(0);var quantity_label: Label=menu._quantity_label
	menu.quantity=5;menu._refresh_detail();inv.changed.emit();await frames(3)
	check(is_instance_valid(detail) and menu._contents.get_child(0)==detail and menu._quantity_label==quantity_label,"Quantity/inventory updates retain existing detail controls")
	check(quantity_label.text.contains("5") and menu._build.text=="Make ×5","Stable details show the selected batch and totals")
	check(menu._build.get_global_rect().end.y<root.get_visible_rect().size.y,"Craft actions remain visible")
	await shot("craft")
	menu._cancel.pressed.emit();await frames(3)
	check(menu.selected.is_empty() and menu._list.visible,"Cancel returns to the scrollable product list")
	hud._close_crafting();await frames()
	var normal:=TERRAIN.mesh_at(Vector2i(3,2));var incremental:=await TERRAIN.mesh_at_incremental(Vector2i(3,2),self)
	check(normal.surface_get_arrays(0)==incremental.surface_get_arrays(0),"Incremental ocean terrain exactly matches its collision/visual geometry")
	player.global_position=Vector3(320,2,240);sea.stream.request_position(Vector2(320,240));await frames(2)
	player.global_position=Vector3(-240,2,-300);sea.stream.request_position(Vector2(-240,-300))
	for unused in 900:
		await frames(1)
		if not sea.stream._busy and sea.stream._pending.is_empty():break
	check(not sea.stream._busy and sea.stream._pending.is_empty(),"Moving while reef work is pending cancels and completes safely")
	var ocean:=get_first_node_in_group("ocean")
	var veil: CanvasLayer=ocean._under_layer;var skin: ShaderMaterial=ocean._under_mat
	check(is_instance_valid(veil) and skin.shader==preload("res://shaders/underwater_veil.gdshader"),"Dive effect is prepared before the first ocean entry")
	var camera:=Camera3D.new();current_scene.add_child(camera);camera.current=true
	camera.global_position=Vector3(320,3,240);camera.look_at(Vector3(320,0,225));await frames(4)
	camera.global_position.y=-4;player.global_position=Vector3(320,-5,240);player.is_swimming=true
	await sample("first dive and reef streaming")
	check(ocean._under_layer==veil and ocean._under_mat==skin and veil.visible,"Entering water reuses the prepared effect")
	camera.global_position.y=3;await sample("return to surface",80)
	check(not veil.visible,"Returning above the surface hides the underwater tint")
	var raft:=get_first_node_in_group("raft");player.global_position=raft.to_global(Vector3(0,1.05,0));player.is_swimming=false
	player.camera.current=true;camera.queue_free()
	var service:=player.get_node("SurvivalServices");var ui: CanvasLayer=service.ui
	var fire: Node3D=load("res://scenes/cooking_setup.tscn").instantiate();raft.get_node("BuiltPieces").add_child(fire)
	fire.position=Vector3(0,.1,-1);fire.burning=true;fire.fuel=90
	var t:=Time.get_ticks_usec();service.open_cooking(fire)
	print("HITCH DIAGNOSTIC first cooking UI CPU ",(Time.get_ticks_usec()-t)/1000.0," ms")
	await sample("first cooking menu",20)
	var first_card: Control=ui._rows[0].card;var kitchen: Control=ui._body
	await shot("kitchen")
	service.close_menu();service.open_cooking(fire);await frames(2)
	check(ui._body==kitchen and ui._rows[0].card==first_card,"Repeated cooking visits reuse all recipe cards")
	service.close_menu();ui.show_filter();ui.close();service.open_cooking(fire);await frames(2)
	check(ui._body==kitchen and ui._rows[0].card==first_card and ui._boil_button.is_visible_in_tree(),"Kitchen cache restores after switching to another station UI")
	inv.add("Potato",1);t=Time.get_ticks_usec()
	check(service.start_cooking("Cooked Potato"),"Cached cooking UI still starts a validated station job")
	print("HITCH DIAGNOSTIC start cooking CPU ",(Time.get_ticks_usec()-t)/1000.0," ms")
	await sample("cooking animation")
	var job:=fire.get_node("StationJob");job.set_process(false);player.get_node("SurvivalAction").stop()
	var output: int=inv.total("Cooked Potato");job.advance(20)
	check(inv.total("Cooked Potato")==output+1 and not fire.burning,"Cooked food completes once and switches the fire off")
	var action:=player.get_node("SurvivalAction")
	var retained: Node3D=action._cook_pool.view
	action.play("cook",2.0,fire.global_position,"Potato Tomato Stew")
	var bowl:=retained.get_node("PreparationBowl/SlicedMeal")
	check(action._view_tool==retained and bowl.get_node_or_null("Broth")!=null,"A different recipe reuses stirring hands and shows its own broth and slices")
	action.stop();await frames(2)
	check(is_instance_valid(retained) and not retained.visible,"Stopping parks prepared cooking props without leaving them in the hands")
	action.play("cook",2.0,fire.global_position,"Cooked Potato")
	check(action._view_tool==retained and retained.get_node("PreparationBowl/SlicedMeal").get_node_or_null("Broth")==null,"Returning to a dry recipe removes the previous soup contents")
	action.stop()
	current_scene.queue_free();await frames(5)
	print("CRAFT OCEAN HITCH SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
