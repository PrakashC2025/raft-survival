extends SceneTree
## Real HUD input, material-safe selection and discoverable camp recipes.
var guide: Script
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var hud: Control
var inv: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)

func frames(count: int=4) -> void:
	for unused in count:await process_frame

func tap(at: Vector2,index: int=44) -> void:
	var touch:=InputEventScreenTouch.new();touch.index=index;touch.position=at;touch.pressed=true
	root.push_input(touch,true)
	var mouse:=InputEventMouseButton.new();mouse.device=-1;mouse.position=at;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true
	root.push_input(mouse,true);mouse.pressed=false;root.push_input(mouse,true)
	touch.pressed=false;root.push_input(touch,true)

func shot(label: String) -> void:
	if not preview:return
	hud.queue_redraw();await frames(8);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/item-clarity-"+label+".png")==OK,"Rendered "+label)

func open_bag(index: int) -> void:
	if not hud._bag_open:tap(hud._bag_rect.get_center())
	tap(hud._bag_slot_rects[index].get_center())

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	create_timer(150).timeout.connect(func():push_error("FAIL: item clarity timeout");quit(1))
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	guide=load("res://scripts/item_guide.gd")
	inv=root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player") as CharacterBody3D
	for unused in 2400:
		await process_frame
		if player.restoration_complete and player.get_node("SurvivalAction").hands_prepared:break
	check(player.restoration_complete,"Real world restores with isolated test saves")
	player.set_process(false);player.set_physics_process(false)
	player.build_mode=false;player.is_swimming=false
	var controls: Control=player.get_node("CanvasLayer/MobileControls")
	controls.force_show=true;controls.call("_update_visibility");controls.call("_sync_mode")
	hud=player.get_node("CanvasLayer/SurvivalHUD");hud.visible=true;hud.call("_compute_layout")
	var progress:=player.get_node("SurvivalProgression");progress.set_process(false);progress.level=1;progress.events.clear()
	for index in inv.SLOT_COUNT:inv.slots[index]={}
	for entry in [[0,"Wood",9],[1,"Axe",1],[6,"Spear",3],[7,"Raw Meat",4],[8,"Boiled Water Tumbler",2],[9,"Metal",18],[10,"Rope",20],[11,"Axe",2],[12,"Plastic",20],[13,"Stone",20],[14,"Cooked Fish",2],[15,"Diving Tank",1]]:
		inv.place_at(entry[0],entry[1],entry[2])
	player.select_hotbar_slot(0)
	var counts: Dictionary=inv.items.duplicate()
	open_bag(6)
	check(hud._inspect_slot==6 and hud._bag_open,"A touch and Android mouse replay inspect exactly one item")
	check(hud.call("_bag_hold_slot")==2,"Holding a bag tool chooses an empty shortcut first")
	await shot("backpack")
	for resolution in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(960,540),Vector2i(1280,960)]:
		root.size=resolution;await frames();hud.call("_compute_layout");controls.call("_apply_viewport_size")
		var clear: bool=hud._bag_slot_rects.size()==30 and Rect2(Vector2.ZERO,hud.size).encloses(hud._panel_rect)
		for cell: Rect2 in hud._bag_slot_rects:
			clear=clear and hud._panel_rect.encloses(cell) and not cell.intersects(hud._bag_detail_rect)
		check(clear,"Thirty named slots and reading pane fit at %s"%resolution)
		check(hud._bag_use_rect.size.y>=48 and hud._bag_equip_rect.size.y>=48 and not hud._bag_use_rect.intersects(hud._bag_equip_rect),"Separate usable action targets at %s"%resolution)
		if resolution==Vector2i(960,540):await shot("small-backpack")
	root.size=Vector2i(1280,720);await frames();hud.call("_compute_layout")
	tap(hud._bag_equip_rect.get_center())
	check(player.active_item=="Spear" and player.active_slot_index==2 and not hud._bag_open,"One Hold tap equips the selected tool and closes the bag")
	check(inv.slot_item(0)=="Wood" and inv.slot_empty(6) and inv.items==counts,"Holding preserves every item and the previous shortcut")
	open_bag(11);var same_item: Array=inv.slots.duplicate(true)
	tap(hud._bag_equip_rect.get_center())
	check(player.active_slot_index==1 and inv.slots==same_item,"An already available tool uses its shortcut without moving either stack")
	for entry in [[3,"Pickaxe",1],[4,"Shovel",1],[5,"Fishing Rod",1],[6,"Life Vest",1]]:inv.place_at(entry[0],entry[1],entry[2])
	player.select_hotbar_slot(2);open_bag(6);counts=inv.items.duplicate()
	tap(hud._bag_equip_rect.get_center())
	check(player.active_item=="Life Vest" and inv.slot_item(6)=="Spear" and inv.items==counts,"A full shortcut row swaps both stacks safely without loss")
	open_bag(7)
	check(guide.nutrition("Raw Meat").contains("Health -10") and guide.quick_action("Raw Meat").contains("costs health"),"Raw-food damage is visible before consumption")
	check(guide.nutrition("Boiled Water Tumbler").contains("Water +65"),"Drinks show their actual configured benefit")
	await shot("food-details")
	open_bag(15);var tank_before: int=inv.total("Diving Tank")
	tap(hud._bag_use_rect.get_center())
	check(progress.diving_tank and inv.total("Diving Tank")==tank_before-1,"Equip Now fits one owned air tank through the normal action")
	open_bag(9);counts=inv.items.duplicate();tap(hud._bag_use_rect.get_center());await frames(8)
	var menu: Control=hud._craft_menu
	check(hud._craft_open and paused and menu._search.text=="Metal","A material opens recipes using it directly")
	check(menu.cards.Axe.visible and not menu.cards["Fishing Rod"].visible,"Material search includes recipe costs and hides unrelated products")
	check(inv.items==counts,"Searching and inspecting recipes spend no materials")
	menu._search.grab_focus()
	for code in [KEY_M,KEY_C]:
		var key:=InputEventKey.new();key.keycode=code;key.unicode=code;key.pressed=true
		root.push_input(key,true);key.pressed=false;root.push_input(key,true)
	check(hud._craft_open and not hud._map_open,"Typing shortcut letters into search keeps the recipe menu open")
	menu._search.release_focus();menu._search.text="";menu.call("_refresh_cards")
	menu._category.select(1);menu.call("_refresh_cards")
	check(menu.cards.Axe.visible and not menu.cards.Bandage.visible,"Tool category shows tools without unrelated recipes")
	menu._category.select(4);menu.call("_refresh_cards")
	check(menu.cards.SeedDryingTray.visible and menu.cards.PlanterPot.visible and not menu.cards.Axe.visible,"Garden category leads directly to useful planting equipment")
	menu._category.select(0);menu._ready_only.button_pressed=true;menu.call("_refresh_cards")
	check(menu.cards.Axe.visible and not menu.cards.RescueRadio.visible,"Ready to make hides mission-locked projects")
	var unlocked_before: int=progress.level
	menu.call("select_item","RescueRadio")
	check(menu._build.disabled and progress.level==unlocked_before,"Viewing a locked recipe cannot bypass mission progression")
	menu._ready_only.button_pressed=false;menu.call("_refresh_cards");menu.call("select_item","Spear")
	await shot("crafting")
	for resolution in [Vector2i(960,540),Vector2i(1600,720),Vector2i(1280,960)]:
		root.size=resolution;await frames(8)
		var visible_rect:=menu.get_viewport_rect()
		check(visible_rect.grow(1).encloses(menu._sheet.get_global_rect()) and menu._build.get_global_rect().end.y<=visible_rect.end.y,"Search and confirmation fit at %s"%resolution)
		if resolution==Vector2i(960,540):await shot("small-crafting")
	root.size=Vector2i(1280,720);await frames();hud.call("_close_crafting")
	check(hud.call("_mission_recipe")=="Fishing Rod","Mission identifies the next real recipe")
	hud.call("_compute_layout");tap(hud._mission_rect.get_center());await frames()
	check(hud._craft_open and hud._craft_menu.selected=="Fishing Rod","One mission tap opens its recipe without crafting")
	hud.call("_close_crafting");progress.events["craft:Fishing Rod"]=1;progress.events["craft:Spear"]=1
	tap(hud._mission_rect.get_center());await frames()
	check(hud._craft_menu.selected=="Bonfire" and hud._craft_menu.cards.has("Bonfire"),"Camp-building mission opens the supported structure recipe")
	var before: Dictionary=inv.items.duplicate()
	tap(hud._craft_menu._build.get_global_rect().get_center());await frames()
	check(player.build_mode and player.BUILD_RECIPE_NAMES[player.selected_piece_index]=="Bonfire" and inv.items==before,"Place enters the correct preview and charges only after valid placement")
	player.build_mode=false;player.call("_update_build_preview");player.select_hotbar_slot(1)
	var pickup: Node3D=load("res://scripts/food_pickup.gd").new();pickup.item_name="Metal";current_scene.add_child(pickup)
	player.aim_valid=true;player.aim_collider=pickup;player.aim_distance=2
	check(hud.call("_aimed_item_label")=="Metal","Actual aimed pickup has a readable item identity")
	player.aim_distance=20
	check(hud.call("_aimed_item_label")=="","Unreachable targets do not show a nearby identification")
	player.aim_distance=2;hud._focus_label=hud.call("_aimed_item_label");hud.call("_compute_layout")
	await shot("gameplay")
	player.aim_valid=false;player.aim_collider=null;pickup.queue_free()
	hud._focus_label="";hud.call("_compute_layout")
	for button in controls._all_buttons:
		if button.visible:check(not hud._held_card_rect.intersects(button.get_global_rect()),"Held-item instructions leave %s clear"%button.name)
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();await frames(30)
	print("ITEM CLARITY SMOKE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
