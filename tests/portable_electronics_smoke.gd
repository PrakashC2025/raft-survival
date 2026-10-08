extends SceneTree
var checks:=0
var failures:=0
var player: Node3D
var tools: Node
var inventory: Node
func _initialize() -> void:
	create_timer(60).timeout.connect(func():push_error("FAIL: electronics timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
func hold(item: String) -> void:
	for index in inventory.slots.size():
		if inventory.call("slot_item",index)==item:
			if index!=0:inventory.call("swap_slots",index,0)
			player.call("select_hotbar_slot",0)
			break
	for child in player._hand_item.get_children():
		if child.is_queued_for_deletion():child.free()
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	inventory=root.get_node("Inventory");inventory.call("new_game_reset",true)
	root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player")
	player.set_process(false);player.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	get_first_node_in_group("raft").set_physics_process(false)
	tools=player.get_node("PortableElectronics");tools.set_process(false)
	await frames(80)
	for item in ["Solar Torch","Binoculars","Walkie Talkie","Battery"]:
		check(inventory.call("craft_item",item) and inventory.call("has",item,1),item+" is craftable through the existing transactional inventory")
		hold(item)
		if item!="Battery":
			check(player._hand_item.find_child({"Solar Torch":"SolarTorch","Binoculars":"Binoculars","Walkie Talkie":"WalkieTalkie"}[item],true,false)!=null,item+" uses the owner's textured 3D model")
			check(player.can_interact_now(),item+" enables the Use button")
	hold("Binoculars")
	var original_fov: float=player.camera.fov
	tools.call("use")
	check(tools.zoomed and player.camera.fov==18.0,"Binocular Use zooms the actual world view")
	check(player.interaction_caption()=="LOWER","Use offers to lower the binoculars")
	tools.call("use")
	check(not tools.zoomed and player.camera.fov==original_fov,"Lowering binoculars restores the original camera")
	tools.call("use");hold("Solar Torch");tools.call("_process",0.0)
	check(not tools.zoomed and player.camera.fov==original_fov,"Changing items releases binocular zoom")
	tools.call("toggle_power");tools.call("_process",0.0)
	check(tools.beam.visible and tools.beam is SpotLight3D and tools.beam.spot_range==32.0,"Solar flashlight gives a real forward light beam")
	check(tools._audio.stream==load("res://scripts/survival_audio.gd").electronic_stream("switch"),"Flashlight switch plays its cached click sound")
	tools.call("toggle_power");tools.call("_process",0.0)
	check(not tools.beam.visible,"Flashlight switches fully off")
	hold("Walkie Talkie")
	tools.call("toggle_power")
	tools.call("advance_power",1440.0*29,1440.0,false)
	check(absf(float(tools.charge["Walkie Talkie"])-100.0/30.0)<0.001 and tools.enabled["Walkie Talkie"],"Radio remains on after 29 game days with one day of charge left")
	tools.call("advance_power",1440.0,1440.0,false)
	check(float(tools.charge["Walkie Talkie"])<0.001 and not tools.enabled["Walkie Talkie"],"Radio battery fully drains after 30 game days on")
	tools.charge["Walkie Talkie"]=0.0
	tools.call("advance_power",120.0,1440.0,true)
	check(tools.charge["Walkie Talkie"]==50.0,"Two minutes of direct sun charges half the radio battery")
	tools.enabled["Walkie Talkie"]=true
	tools.call("advance_power",120.0,1440.0,true)
	check(tools.charge["Walkie Talkie"]==100.0,"Four minutes fully charges the radio without simultaneous battery drain")
	tools.enabled["Walkie Talkie"]=false
	tools.call("advance_power",1440.0*40,1440.0,false)
	check(tools.charge["Walkie Talkie"]==100.0,"The side power switch preserves battery while off")
	tools.call("toggle_cover")
	check(tools.cover_open,"Battery cover can be opened")
	tools.charge["Walkie Talkie"]=12.0
	var spare_before: int=inventory.call("total","Battery")
	check(tools.call("battery_action","replace"),"A spare charged battery replaces the installed cell")
	check(tools.charge["Walkie Talkie"]==100.0 and inventory.call("total","Battery")==spare_before-1 and inventory.call("total","Used Battery")==1,"Replacement atomically stores the old cell and spends one spare")
	check(tools.battery_animation==1.8 and not tools.enabled["Walkie Talkie"],"Replacing starts the hand animation with power switched off")
	check(player.get_node("SurvivalAction").kind=="battery","Battery replacement runs the registered two-hand animation")
	tools.call("_process",0.8)
	var cell:=player._hand_item.find_child("AnimatedBattery",true,false) as Node3D
	var cover:=player._hand_item.find_child("BatteryCover",true,false) as Node3D
	check(cell.visible and cell.position.z>0.1 and absf(cell.rotation.z)>0.1,"Battery visibly slides out and turns between the hands")
	check(cover.position.z>0.049 and cover.rotation.x<0.0,"Physical cover opens during the battery animation")
	tools.call("_process",1.1)
	check(tools.battery_animation==0.0 and not tools.cover_open and not cell.visible,"Battery animation finishes and closes the compartment")
	tools.call("toggle_cover")
	check(tools.call("battery_action","remove") and not tools.installed["Walkie Talkie"],"Battery can be removed and stored in inventory")
	tools.call("_process",1.9)
	tools.call("toggle_power")
	check(not tools.enabled["Walkie Talkie"],"Radio cannot power on without a battery")
	tools.call("toggle_cover")
	check(tools.call("battery_action","replace"),"A stored battery can be inserted again")
	tools.call("_process",1.9)
	tools.charge["Walkie Talkie"]=100.0
	tools.call("toggle_power");tools.call("use")
	check(tools._reply>0.0 and tools._radio_cooldown>0,"Radio sends a signal and schedules a received reply")
	check(tools._audio.stream==load("res://scripts/survival_audio.gd").electronic_stream("radio_send"),"Transmission plays radio chirps and static")
	tools.call("_process",2.5)
	check(tools._reply==0.0 and tools._audio.stream==load("res://scripts/survival_audio.gd").electronic_stream("radio_receive"),"Radio receives an audible location response")
	var screen:=player._hand_item.find_child("RadioScreen",true,false) as Label3D
	check(screen!=null and screen.text.contains("CH16") and screen.text.contains("%"),"Walkie-talkie physical screen shows channel and battery level")
	check(player._hand_item.find_child("SidePowerButton",true,false)!=null and tools._power.text.contains("POWER"),"Radio has a visible side power key and a touch power control")
	tools.charge["Walkie Talkie"]=37.0
	check(player.call("_write_save","quick"),"Portable tool state writes through normal isolated saving")
	check(inventory.call("load_game","quick") and inventory.loaded_meta.electronics.charge["Walkie Talkie"]==37.0,"Saved battery charge round-trips without refilling")
	tools.call("restore_state",inventory.loaded_meta.electronics)
	check(tools.installed["Walkie Talkie"] and tools.enabled["Walkie Talkie"] and tools.charge["Walkie Talkie"]==37.0,"Installed battery and power switch restore together")
	player.build_mode=true;tools.call("use")
	check(tools._reply==0.0,"Building blocks radio gameplay input")
	player.build_mode=false
	if OS.get_cmdline_user_args().has("--preview"):
		hold("Walkie Talkie")
		tools.set_process(true)
		player.cam_mode=0;player.call("_apply_camera_mode")
		for unused in 60:await process_frame
		root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/portable-electronics-preview.png")
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();await frames(25)
	print("PORTABLE ELECTRONICS SMOKE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
