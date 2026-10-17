extends SceneTree
## Real world, boat, input, inventory and save transactions with isolated storage.
const SAVE := preload("res://scripts/save_storage.gd")
var checks := 0
var failures := 0
var player: CharacterBody3D
var salvage: Node
var inv: Node
var hud: Control
var preview := false

func _initialize() -> void:call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if value:print("PASS: "+message)
	else:failures += 1;push_error("FAIL: "+message)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func clear_bag() -> void:
	for index in inv.SLOT_COUNT:inv.slots[index] = {}
	inv._recompute();inv.changed.emit()
func aim_cache() -> void:
	player.aim_valid = true;player.aim_collider = salvage.cache;player.aim_point = salvage.cache.global_position;player.aim_distance = 3.0
func near_cache() -> void:
	player.global_position = salvage.cache.global_position+Vector3(2.8,.6,0)
	player.is_swimming = true
	aim_cache()
func press_use() -> void:
	# UI actions are polled on the process frame, including when physics catches up in a slow render.
	await process_frame
	var mobile:=player.get_node("CanvasLayer/MobileControls")
	mobile.force_show=true;mobile.show()
	mobile._on_use_down()
	check(Input.is_action_just_pressed("interact"),"Mobile USE reaches the normal process-frame action poll")
	player._poll_gameplay_actions()
	mobile._release_action("interact")
func touch(here: Vector2) -> void:
	var event := InputEventScreenTouch.new();event.index = 27;event.position = here;event.pressed = true;hud._handle_modal_pointer(event)
	event.pressed = false;hud._handle_modal_pointer(event)
func picture(label: String) -> void:
	if not preview:return
	await frames(8)
	await RenderingServer.frame_post_draw
	# The script is outside its junction stage; save into the actual project build directory.
	var path: String = get_script().resource_path.get_base_dir().get_base_dir().path_join("build/ocean-salvage-"+label+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"Saved "+label+" renderer preview")

func run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview = "--preview" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280,720)
	inv = root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled = false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player = get_first_node_in_group("player")
	for unused in 3000:
		await frames(1)
		if player.restoration_complete and player.get_node("SurvivalAction").hands_prepared and player.get_node("OceanSalvage")._restored:break
	check(player.restoration_complete,"World restoration completes before expedition starts")
	player.set_process(false);player.set_physics_process(false)
	for child in ["SurvivalProgression","SurvivalEquipment","SurvivalAction","SurvivalServices","BoatBuilding","OceanSalvage"]:player.get_node(child).set_process(false)
	for animal in get_nodes_in_group("huntable_animal")+get_nodes_in_group("shark"):animal.set_physics_process(false)
	var raft := get_first_node_in_group("raft") as Node3D
	raft.set_physics_process(false)
	player.get_node("RainSystem").stop_rain()
	salvage = player.get_node("OceanSalvage");hud = player.get_node("CanvasLayer/SurvivalHUD")
	check(not is_instance_valid(salvage.cache) and salvage.next_arrival>0,"No new cargo appears on top of the player at loading")
	var wait_before: float = salvage.next_arrival
	hud._bag_open = true;salvage._process(.4)
	check(salvage.next_arrival==wait_before,"Browsing the bag does not advance cargo arrival")
	hud._bag_open = false;salvage._process(.4)
	check(is_equal_approx(salvage.next_arrival,wait_before-.4),"Arrival counts active game time")
	check(salvage.spawn_cache(),"A supply cache enters real open water")
	if not is_instance_valid(salvage.cache):quit(1);return
	var electronics:=player.get_node("PortableElectronics")
	electronics.set_process(false)
	inv.add("Walkie Talkie",1);player.active_item="Walkie Talkie"
	electronics.installed["Walkie Talkie"]=true;electronics.enabled["Walkie Talkie"]=true;electronics.charge["Walkie Talkie"]=90;electronics.clear_fault("Walkie Talkie")
	electronics.use();electronics._process(2.5)
	check(hud._toast.contains("DRIFT CARGO") and hud._toast.contains("CHECK MAP"),"A real powered radio exchange reports the active cargo")
	player.active_item="";electronics._process(0)
	var cache := salvage.cache as StaticBody3D
	cache.set_physics_process(false)
	check(player.global_position.distance_to(cache.global_position)>=84,"Cargo enters outside the immediate play area")
	check(not salvage.spawn_cache() and get_nodes_in_group("drift_cache").size()==1,"Only one expedition cargo can exist")
	check(cache.collision_layer==2 and cache.get_meta("arrival_radius")==4.0,"Cargo is a reachable interaction target with a close sailing arrival")
	check(salvage.radio_report().contains("DRIFT CARGO") and salvage.radio_report().contains("CHECK MAP"),"A radio report refers to actual cargo and a plotted location")
	check(salvage.water_clear(cache.global_position),"The cargo footprint has actual water depth and obstacle clearance")
	var first_at: Vector3 = cache.global_position
	var before: Vector3 = cache.global_position;cache._physics_process(.5)
	check(cache.global_position.z>before.z and absf(cache.global_position.x-before.x)<.01,"Cargo follows the same current direction as driftwood")
	var sea := get_first_node_in_group("ocean") as Node3D
	check(absf(cache.global_position.y-float(sea.call("get_height",cache.global_position))-.10)<.3,"Cargo floats against the moving ocean sampler")
	check(cache.visual.rotation.length()<.25,"Wave slope produces bounded pitch and roll")
	var hold := StaticBody3D.new();var collision := CollisionShape3D.new();var block := BoxShape3D.new();block.size = Vector3(4,4,4);collision.shape = block;hold.add_child(collision);hold.position = cache.global_position;current_scene.add_child(hold);await frames()
	check(not salvage.water_clear(cache.global_position),"A solid hull or beach footprint blocks cargo drift")
	hold.queue_free();await frames()
	hud.toggle_map();await frames()
	check(hud._map_markers.any(func(marker):return marker.node==cache),"MAP includes the actual supply cache")
	check(hud._map_log_rect.has_area() and not hud._map_log_rect.intersects(hud._map_close_rect),"Recovery log and map close retain distinct touch targets")
	await picture("map")
	for viewport_size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,720),Vector2i(1920,1080)]:
		root.size = viewport_size;await frames();hud._compute_layout()
		check(hud._map_panel_rect.encloses(hud._map_log_rect) and not hud._map_log_rect.intersects(hud._map_area_rect),"Log control remains in the header at "+str(viewport_size))
	root.size = Vector2i(1280,720);await frames()
	raft.set_upgrade_tier(1);hud._selected_island = cache;hud._start_selected_course()
	check(raft.has_active_course() and Vector2(raft._course_target.x-cache.global_position.x,raft._course_target.z-cache.global_position.z).length()<.01,"Selecting cargo sets the actual vessel course")
	check(raft._arrival_radius==4,"Cargo course stops within recovery reach instead of island distance")
	raft.clear_course()
	near_cache();clear_bag()
	check(player.interaction_caption()=="RECOVER CARGO" and player.can_interact_now(),"USE identifies reachable cargo")
	for index in inv.SLOT_COUNT:inv.slots[index] = {"item":"Wood","count":inv.MAX_STACK}
	inv._recompute();inv.changed.emit()
	var full: Array = inv.slots.duplicate(true)
	check(not salvage.start_recovery(cache) and inv.slots==full and cache.available,"Full bags preserve all inventory and the sealed manifest")
	clear_bag()
	check(salvage.start_recovery(cache),"Recovery begins only in actual reach")
	salvage.advance_recovery(1.0)
	check(inv.total("Wrapped Cooked Fish")==0 and cache.available,"Rewards are withheld until the action completes")
	player.global_position.x += 2;salvage.advance_recovery(.1)
	check(not salvage.busy() and cache.available,"Walking or swimming away cancels without losing cargo")
	near_cache();salvage.start_recovery(cache);root.get_node("Stats").change_health(-1);salvage.advance_recovery(.1)
	check(not salvage.busy() and cache.available,"Damage interrupts recovery safely")
	salvage.start_recovery(cache);salvage._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not salvage.busy() and cache.available,"Backgrounding releases the unfinished cargo action")
	salvage.start_recovery(cache);hud._bag_open = true;salvage.advance_recovery(.1);hud._bag_open = false
	check(not salvage.busy() and cache.available,"Opening a modal stops recovery")
	# Capacity can change while the hands are busy: recheck at the commit frame.
	salvage.start_recovery(cache)
	for index in inv.SLOT_COUNT:inv.slots[index] = {"item":"Wood","count":inv.MAX_STACK}
	inv._recompute();salvage.advance_recovery(3.1)
	check(cache.available and not salvage.busy() and inv.total("Water")==0,"A newly full bag causes no partial reward or lost cache")
	clear_bag()
	# An actual boat supports recovery without disembarking or eating the selected food.
	var boats := player.get_node("BoatBuilding")
	boats.ready_to_launch = true
	check(boats.launch(),"Completed rowboat launches for the expedition")
	var boat := boats.boat as CharacterBody3D
	boat.set_physics_process(false);boat.global_position = cache.global_position+Vector3(3,0,0)
	player.global_position = boat.global_position+Vector3.UP*.6
	check(boat.board(player),"Player boards the real rowboat beside the cargo")
	boat.advance_transition(1.0);await frames();aim_cache()
	player.active_item = "Spear"
	await press_use()
	check(salvage.busy() and player.boat_vehicle==boat and boat.driver==player,"USE from the boat recovers cargo without leaving the seat")
	check(player.boat_consumption_active() and player.get_node("SurvivalServices").busy(),"Recovery owns hands and suppresses rowing/other actions")
	player.get_node("SurvivalAction")._process(.1)
	check(is_instance_valid(player.get_node("SurvivalAction")._view_tool) and player.get_node("SurvivalAction")._view_tool.get_child_count()==2 and not player._hand_item.visible,"Two working hands hide the equipped weapon during recovery")
	var unfinished: Dictionary = salvage.save_state()
	check(not unfinished.cache.is_empty() and not unfinished.has("pending"),"An interrupted save stores sealed cargo rather than free progress")
	salvage.advance_recovery(3.1)
	check(inv.total("Wrapped Cooked Fish")==2 and inv.total("Water")==2 and inv.total("Cooking Foil")==2,"The fixed galley manifest transfers once in one transaction")
	check(salvage.recovered==1 and salvage.catalog==[0] and not is_instance_valid(salvage.cache),"Successful recovery records one note and removes its cache")
	salvage.advance_recovery(10)
	check(inv.total("Wrapped Cooked Fish")==2 and salvage.recovered==1,"Repeated completion cannot duplicate supplies")
	check(salvage.next_arrival>=300 and salvage.next_arrival<=480,"The next cache waits five to eight active minutes")
	boat._release_driver();player.is_swimming = true
	check(player._write_save("quick"),"New expedition metadata writes through the actual authenticated save")
	var saved := SAVE.read(inv.QUICK_SAVE_PATH)
	check(int(saved.ocean_salvage.recovered)==1 and saved.ocean_salvage.catalog.size()==1 and int(saved.ocean_salvage.catalog[0])==0 and saved.slots.size()==30,"Saved journal and inventory retain their compatible shape")
	salvage.restore_state(saved.ocean_salvage)
	check(salvage.recovered==1 and not is_instance_valid(salvage.cache),"Continue after collection does not regenerate the old cargo")
	check(salvage.spawn_cache() and salvage.cache.cargo_kind==1,"Next cargo advances to repairs rather than rerolling the same reward")
	cache = salvage.cache;cache.set_physics_process(false)
	var sealed: Dictionary = salvage.save_state()
	salvage.restore_state(sealed);cache = salvage.cache;cache.set_physics_process(false)
	check(cache.cargo_kind==1 and cache.global_position.distance_to(Vector3(sealed.cache.p[0],sealed.cache.p[1],sealed.cache.p[2]))<.05,"Reload preserves the exact cache type and horizontal position")
	check(player._write_save("quick") and SAVE.read(inv.QUICK_SAVE_PATH).ocean_salvage.cache.kind==1,"A sealed cache survives a real save round trip")
	var invalid: Dictionary = sealed.duplicate(true);invalid.cache.p[0] = "bad"
	check(not SAVE._valid_salvage(invalid),"Save validation rejects malformed cargo coordinates")
	salvage.restore_state(invalid)
	check(not is_instance_valid(salvage.cache),"Defensive restore rejects malformed cargo")
	salvage.restore_state({"catalog":[0,0,1,99],"next_arrival":NAN,"serial":"bad"})
	check(salvage.catalog==[0,1] and salvage.next_arrival==90 and salvage.serial==0,"Bad optional metadata cannot create invalid timers or duplicate notes")
	salvage.restore_state({})
	check(salvage.recovered==0 and salvage.next_arrival==90 and SAVE._valid_salvage({}),"Older saves need no expedition fields")
	# A finishing storm makes a natural opportunity; an existing cache never gets replaced.
	var rain := player.get_node("RainSystem")
	rain.start_rain(40);salvage._process(.1);rain.stop_rain();salvage._process(.1)
	check(salvage.next_arrival<=45,"A passing storm brings the next salvage opportunity closer")
	# Unlock every field note with the real capacity-safe action.
	for kind in 4:
		if is_instance_valid(salvage.cache):salvage.cache.free();salvage.cache = null
		salvage._create(kind,player.global_position+Vector3(3,0,0),0)
		cache = salvage.cache;cache.set_physics_process(false);near_cache();clear_bag()
		check(salvage.start_recovery(cache),"Themed cargo %d starts"%kind)
		salvage.advance_recovery(3.1)
		check(salvage.catalog.has(kind),"Themed cargo %d unlocks its field note"%kind)
	check(salvage.catalog.size()==4 and salvage.journal_caption().contains("4/4"),"All four cargo types give a completed exploration collection")
	hud.toggle_map();await frames();touch(hud._map_log_rect.get_center());await frames()
	check(salvage.menu_open and hud.gameplay_input_blocked(),"A real map touch opens the journal and owns gameplay input")
	check(root.get_visible_rect().encloses(salvage._journal_panel.get_global_rect()),"The scrollable journal stays within the landscape screen")
	await picture("journal")
	hud.handle_back();await frames()
	check(not salvage.menu_open and not player.get_node("SurvivalServices").is_modal(),"Back releases journal ownership without changing rewards")
	root.size = Vector2i(960,540);await frames();salvage.open_journal();await frames()
	check(root.get_visible_rect().encloses(salvage._journal_panel.get_global_rect()),"The recovery journal scrolls on a small phone layout")
	await picture("journal-small");salvage.close_journal();root.size = Vector2i(1280,720)
	# Render a nearby real cargo case against the actual ocean.
	player.global_position = first_at+Vector3(0,2.2,7)
	player.active_item="";player._update_hand_item();player.get_node("SurvivalAction").stop()
	salvage._create(1,first_at,.4)
	cache = salvage.cache;cache.set_physics_process(false)
	player.cam_mode = 0;player._apply_camera_mode()
	current_scene.get_node("Sky3D").current_time=12
	current_scene.get_node("Sky3D/TimeOfDay/Timer").stop()
	var camera := player.camera as Camera3D
	camera.look_at(cache.global_position+Vector3.UP*.7)
	await picture("cargo")
	current_scene.get_node("OceanAmbience").stop_environment();current_scene.queue_free();await frames(25)
	print("OCEAN SALVAGE SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
