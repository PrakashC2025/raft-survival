extends SceneTree
var checks:=0
var failures:=0
var preview:=false
var player: CharacterBody3D
var raft: Node3D
var built: Node3D
func _initialize() -> void:
	create_timer(150).timeout.connect(func():push_error("FAIL: salvage power/net timeout");quit(1))
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=4) -> void:
	for unused in count:await physics_frame
	await process_frame
func piece(kind: String, at: Vector3) -> Node3D:
	var node: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	node.name=kind+"_SalvageTest_"+str(node.get_instance_id());node.position=at;built.add_child(node);return node
func blocker(at: Vector3, shape_size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=shape_size;collider.shape=shape;body.add_child(collider)
	current_scene.add_child(body);body.global_position=at;return body
func aim(kind: String, point: Vector3, target: Node3D, normal: Vector3=Vector3.UP) -> Dictionary:
	player.aim_valid=true;player.aim_collider=target;player.aim_point=point;player.aim_normal=normal;player.build_rotation=0
	return player._resolve_placement(kind,point)
func shot(name: String) -> void:
	if not preview:return
	await frames(12);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://../"+name+".png")==OK,"Saved preview: "+name)
func picture(kind: String, filename: String) -> void:
	if not preview:return
	var view:=SubViewport.new();view.size=Vector2i(320,320);view.own_world_3d=true;view.transparent_bg=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color(.65,.74,.8);settings.ambient_light_energy=.65;environment.environment=settings;view.add_child(environment)
	var model: Node3D=preload("res://scripts/fishing_net_visual.gd").create() if kind=="FishingNet" else preload("res://scripts/machine_visual.gd").create(kind) if kind!="Torch" else preload("res://scripts/torch_visual.gd").new()
	view.add_child(model)
	if kind=="Torch":model.set_burning(true)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,155,0);light.light_energy=1.8;view.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;view.add_child(camera)
	var center:=Vector3(0,.80,0) if kind=="WindGenerator" else Vector3(0,-.30,0) if kind=="FishingNet" else Vector3(0,.20,0) if kind=="Torch" else Vector3.ZERO
	camera.size=3.1 if kind=="WindGenerator" else 1.8 if kind=="FishingNet" else 1.1 if kind=="Torch" else 1.05
	camera.position=center+Vector3(2,1.0,-3);camera.look_at(center);camera.current=true
	await frames(15);await RenderingServer.frame_post_draw
	var rendered:=view.get_texture().get_image()
	var path:="res://textures/ui/stations/"+filename+".png"
	check(rendered.save_png(path)==OK,"Rendered original model icon: "+kind)
	preload("res://scripts/item_art.gd")._pictures["station:"+kind]=ImageTexture.create_from_image(rendered)
	view.queue_free();await frames()
func run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	var inv:=root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	await frames(160);player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false);raft.rotation=Vector3.ZERO
	var spawner:=current_scene.get_node("DebrisSpawner");spawner.set_process(false)
	check(not spawner.SUPPLY_CYCLE.has("Barrel") and not spawner.SALVAGE_POOL.has("WindGenerator") and not spawner.ITEM_POOL.has("Barrel") and not spawner.ITEM_POOL.has("WindGenerator"),"New salvage contains no complete barrels or generators")
	check(spawner.SALVAGE_POOL.has("ElectricLamp") and spawner.SALVAGE_POOL.has("Wire") and spawner.SALVAGE_POOL.has("Motor"),"LED and electrical parts wash up as salvage")
	var metal: int=inv.total("Metal");var barrels: int=inv.total("Barrel")
	check(inv.craft_item("Barrel") and inv.total("Barrel")==barrels+1 and inv.total("Metal")==metal-2,"Crafting a barrel consumes its bands and produces one barrel")
	check(inv.RECIPES.FishingNet=={"Wood":4,"Rope":6,"Stone":2},"Net has an explicit weighted-rope recipe")
	var generator:=piece("WindGenerator",Vector3(8,.5,0));generator.set_process(false);await frames()
	check(generator.exposed(),"An open turbine has airflow")
	generator.advance(10);check(generator.charge>0,"Open wind charges its battery")
	var ceiling:=blocker(generator.global_position+Vector3(0,1.2,0),Vector3(4,.12,4));await frames()
	var stored: float=generator.charge;generator.advance(5);generator._process(1)
	check(not generator._wind_exposed and generator.charge==stored and generator._rotor_speed==0,"Indoor ceiling blocks both rotor and charging")
	ceiling.queue_free();await frames()
	var rain:=get_first_node_in_group("rain_system");var wind: Vector2=rain.wind_direction
	var direction:=Vector3(wind.x,0,wind.y).normalized()
	var wall:=blocker(generator.global_position+Vector3.UP*1.7+direction*1.3,Vector3(1.1,1.8,1.1));await frames()
	check(not generator.exposed(),"A wall beside the fan obstructs airflow")
	wall.queue_free();await frames();check(generator.exposed(),"Clearing the wall restores airflow")
	var lamp:=piece("ElectricLamp",Vector3(8,.5,2));lamp.set_process(false);lamp.enabled=true;lamp.automatic_night=false;generator.charge=0;lamp.advance(60)
	check(lamp._light.visible and lamp.led_battery<100,"Mounted LED runs from its battery without generator power")
	lamp.led_battery=.01;lamp.advance(1);check(lamp.led_battery==0 and not lamp._light.visible,"An empty LED battery switches its light off")
	generator.charge=120;lamp.advance(10);check(lamp.led_battery==0 and generator.charge==120,"Nearby equipment never receives wireless electricity")
	inv.add("Wire",4);player.active_item="Wire";player.global_position=generator.global_position+Vector3(0,.4,2)
	var wiring: Node=player._power_wiring();player.aim_valid=true;player.aim_collider=generator;player.aim_point=generator.global_position;wiring.use()
	player.aim_collider=lamp;player.aim_point=lamp.global_position;var wires: int=inv.total("Wire");wiring.use()
	check(lamp.wired_source==generator.machine_id and inv.total("Wire")==wires-1 and lamp._cable.visible,"Connecting real terminals spends one Wire and displays a cable")
	lamp.advance(10);check(lamp.led_battery>0 and generator.charge<120,"A wired generator recharges the LED battery")
	var saved: Dictionary=lamp.save_survival_state();lamp.led_battery=0;lamp.restore_survival_state(saved)
	check(is_equal_approx(lamp.led_battery,saved.led_battery),"Mounted LED battery survives save restoration")
	check(lamp.wired_source==saved.wired_source and generator.machine_id==generator.save_survival_state().machine_id,"Stable terminal identity and cable connection survive restoration")
	var electronics:=player.get_node("PortableElectronics");electronics.set_process(false);inv.add("ElectricLamp",1);player.active_item="ElectricLamp";player.rope_gun_selected=false;player._update_hand_item()
	electronics.enabled.ElectricLamp=true;electronics.charge.ElectricLamp=20;electronics.advance_power(60,480,true)
	check(electronics.charge.ElectricLamp<20 and electronics.working("ElectricLamp"),"Held LED drains its cell and does not pretend to have a solar panel")
	electronics.charge.ElectricLamp=.01;electronics.advance_power(1,480,false)
	check(not electronics.working("ElectricLamp") and not electronics.enabled.ElectricLamp,"Held LED shuts off when its cell drains")
	var timber:=piece("Wall",Vector3(0,1.475,-1));player.global_position=raft.to_global(Vector3(0,.9,1.5));await frames()
	var spot:=timber.to_global(Vector3(0,-.2,.15));var mount:=aim("ElectricLamp",spot,timber,Vector3.BACK)
	check(mount.get("valid",false) and (mount.transform.basis.z as Vector3).dot(Vector3.BACK)<0,"LED wall placement faces its lens into the room")
	electronics.charge.ElectricLamp=37.5;electronics.enabled.ElectricLamp=true;electronics.faults.ElectricLamp=""
	player.selected_piece_index=player.BUILD_RECIPE_NAMES.find("ElectricLamp");player.build_valid=true;player._ghost_transform=mount.transform;player._ghost_support=mount.support
	var led_count: int=inv.total("ElectricLamp");player._try_build();await frames()
	var mounted_led: Node3D
	for candidate in built.get_children():
		if candidate.name.begins_with("ElectricLamp_") and candidate!=lamp:mounted_led=candidate
	check(mounted_led!=null and inv.total("ElectricLamp")==led_count-1 and is_equal_approx(mounted_led.led_battery,37.5) and mounted_led._light.visible,"Mounting the recovered LED preserves its battery and working light")
	if mounted_led!=null:
		mounted_led.set_process(false);mounted_led.led_battery=29.25;player._editing=mounted_led;player._remove_editing();await frames()
	check(inv.total("ElectricLamp")==led_count and is_equal_approx(electronics.charge.ElectricLamp,29.25) and electronics.enabled.ElectricLamp,"Returning the LED to the bag preserves its remaining charge and power switch")
	inv.add("Torch",2);player.active_item="Torch";player._update_hand_item();player.aim_valid=false
	var torches: int=inv.total("Torch");var fire:=player.get_node("FireActions")
	check(not fire.start("torch_mount") and inv.total("Torch")==torches and player._hand_item.visible,"Invalid wall mounting keeps the held torch and inventory")
	aim("WallTorch",spot,timber,Vector3.BACK);check(fire.start("torch_mount"),"Clear timber starts contact-timed torch mounting")
	player.aim_valid=false;player.aim_collider=null
	check(fire._commit() and inv.total("Torch")==torches-1,"Looking away during mounting keeps the locked wall spot")
	fire.cancel();check(player._hand_item.visible,"Finishing or cancelling restores held visuals")
	var net_spot:=aim("FishingNet",raft.to_global(Vector3(1,.15,0)),raft)
	check(net_spot.get("valid",false),"Net snaps to a free outer raft edge")
	var net:=piece("FishingNet",Vector3.ZERO);net.global_transform=net_spot.transform;net.set_process(false);await frames()
	check(player._find_editable_target(net)==net,"The built net can enter the existing edit and remove flow")
	check(net.in_water(),"The hanging basket reaches the ocean")
	var school:=current_scene.get_node("RaftFish");school.set_process(false);school._fish[0].global_position=net.to_global(Vector3(0,-.6,0))
	net.advance(35);check(net.fish==1 and not school._fish[0].visible,"The net catches a nearby swimming fish after its wait")
	var fish_before: int=inv.total("Fish");net.interact_survival(player)
	check(net.fish==0 and inv.total("Fish")==fish_before+1,"Collecting transfers the actual catch into the bag")
	net.fish=1;player.active_item="ElectricLamp";player.aim_valid=true;player.aim_collider=net;player.aim_point=net.global_position;player.aim_distance=1.0
	check(player.interaction_caption()=="COLLECT FISH","A held LED keeps the useful collection action available")
	net.fish=2;net.seconds=12;var net_state: Dictionary=net.save_survival_state();net.fish=0;net.restore_survival_state(net_state)
	check(net.fish==2 and net.seconds==12 and not net.empty(),"Catch and waiting progress survive saves and prevent destructive removal")
	var original: Array=inv.slots.duplicate(true)
	for index in inv.slots.size():inv.slots[index]={"item":"Metal","count":inv.MAX_STACK}
	inv._recompute();net.interact_survival(player);check(net.fish==2,"A full bag leaves both fish safely in the net")
	inv.slots=original;inv._recompute();inv.changed.emit()
	var deck:=piece("Foundation",Vector3(2,0,0));await frames()
	check(not aim("FishingNet",raft.to_global(Vector3(1,.15,0)),raft).get("valid",false),"An adjacent foundation prevents hanging a net inside the deck")
	deck.queue_free();player.active_item="Rope";player._update_hand_item();await frames()
	await picture("WindGenerator","wind_generator")
	await picture("FishingNet","fishing_net")
	await picture("ElectricLamp","salvaged_led")
	await picture("Torch","hand_torch")
	var hud:=player.get_node("CanvasLayer/SurvivalHUD");hud.toggle_crafting();await frames()
	var menu: Control=hud._craft_menu
	check(menu.cards.size()==hud.CRAFT_ORDER.size()+3 and menu._list.get_v_scroll_bar().max_value>menu._list.size.y,"All products are in one vertical scrolling list")
	menu.select_item("Barrel");await frames();check(menu._build.text=="Build" and menu._cancel.text=="Cancel","Selected product shows Build and Cancel")
	await shot("salvage-craft-desktop")
	root.size=Vector2i(390,844);await frames(12);menu._fit();await frames()
	check(menu._compact and not menu._list.visible and menu._detail.visible,"Phone opens a readable product detail view")
	check(menu._build.get_global_rect().size.y*root.get_stretch_transform().get_scale().y>=48,"Phone Build button keeps a physical 48-pixel touch target")
	await shot("salvage-craft-mobile")
	menu.select_item("FishingNet");await shot("salvage-net-mobile")
	menu._cancel.pressed.emit();await frames();check(menu.selected.is_empty() and menu._list.visible,"Cancel returns to the scrollable list")
	menu.select_item("Barrel");var before: int=inv.total("Barrel");menu._build.pressed.emit();await frames()
	check(not hud._craft_open and inv.total("Barrel")==before+1 and hud._toast.contains("ADDED TO BAG"),"Build spends once, closes the menu and shows clear success feedback")
	player.get_node("SurvivalAction").stop();player.get_node("CanvasLayer/MobileControls").force_show=true
	player.active_item="ElectricLamp";player._update_hand_item();electronics.charge.ElectricLamp=60;electronics.enabled.ElectricLamp=true;electronics._process(.12);await frames()
	check(electronics._panel.visible and electronics._mount.visible and not electronics._solar_button.visible and electronics.led.visible,"Held LED shows battery, power and mounting controls with a working light")
	check(electronics._power.get_global_rect().size.y*root.get_stretch_transform().get_scale().y>=44,"Portable power button remains a usable phone touch target")
	check(electronics._mount.get_global_rect().end.x<=root.get_visible_rect().size.x,"Portable mounting button stays fully inside a narrow phone screen")
	await shot("salvage-led-mobile")
	root.size=Vector2i(1280,720)
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();current_scene=null;player=null;raft=null;built=null
	await frames(8)
	print("SALVAGE POWER NET: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
