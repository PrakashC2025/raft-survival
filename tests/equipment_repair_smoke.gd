extends SceneTree
var checks:=0
var failures:=0
var player: CharacterBody3D
var tools: Node
var repairs: Node
var action: Node
var inventory: Node
var preview:=false
func _initialize() -> void:
	create_timer(140).timeout.connect(func():push_error("FAIL: equipment repair timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=5) -> void:
	for unused in count:await process_frame
func hold(item: String) -> void:
	player.get_node("SurvivalServices").equip_owned(item)
func shot(name2: String) -> void:
	if not preview:return
	await frames(12);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/equipment-"+name2+".png")==OK,"Rendered "+name2)
func pose_at(seconds: float) -> void:
	action.elapsed=seconds;action.call("_advance_feedback");action.call("_process",0.0)
func pointer(at: Vector2) -> void:
	var finger:=InputEventScreenTouch.new();finger.index=22;finger.position=at;finger.pressed=true;root.push_input(finger,true)
	var mouse:=InputEventMouseButton.new();mouse.device=-1;mouse.position=at;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true;root.push_input(mouse,true)
	mouse.pressed=false;root.push_input(mouse,true);finger.pressed=false;root.push_input(finger,true)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inventory=root.get_node("Inventory");inventory.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");player.set_process(false);player.set_physics_process(false)
	get_first_node_in_group("raft").set_physics_process(false);player.get_node("RopeSystem").set_physics_process(false)
	tools=player.get_node("PortableElectronics");repairs=player.get_node("EquipmentRepairs");action=player.get_node("SurvivalAction")
	tools.set_process(false);repairs.set_process(false);action.set_process(false)
	tools.solar=false;tools._solar_tick=-10000.0
	await frames(150)
	for item in ["Walkie Talkie","Solar Torch","Binoculars","Repair Kit","Wire","Wire","Wire","Wire","Screw","Screw","Motor"]:
		check(inventory.craft_item(item),"Crafted testing "+item+" transactionally")
	for item in ["Walkie Talkie","Solar Torch","Binoculars"]:
		hold(item);await frames()
		check(player._hand_item.find_child("OldClothTape",true,false)!=null and player._hand_item.find_child("ChippedCasing",true,false)!=null,item+" has physical worn tape and chipped casing")
	var pool: Array=load("res://scripts/debris_spawner.gd").SALVAGE_POOL
	check(not pool.has("ElectricLamp") and pool.has("Solar Torch") and pool.has("Walkie Talkie"),"No new lamps wash up; weathered handheld electronics do")
	check(not player.get_node("CanvasLayer/SurvivalHUD").CRAFT_ORDER.has("ElectricLamp") and not inventory.can_afford("ElectricLamp"),"New lamp crafting is removed")
	var progress:=player.get_node("SurvivalProgression");progress.level=3;progress.events={}
	progress.record("build:WindGenerator");progress.record("power")
	check(progress.level==4,"Wind chapter completes without requiring the removed lamp")
	hold("Solar Torch");tools.enabled["Solar Torch"]=true;tools.charge["Solar Torch"]=45.0
	tools.develop_fault("Solar Torch","contact");tools._flicker=.6
	var first: bool=tools.working("Solar Torch");tools._flicker=.65
	check(first!=tools.working("Solar Torch"),"A loose contact visibly flickers before failing")
	tools._process(1.0)
	check(not tools.beam.visible and tools._shake_button.visible and player.interaction_caption()=="SHAKE","Broken torch loses its beam and offers Shake")
	var wood: int=inventory.total("Wood");var wire: int=inventory.total("Wire")
	check(repairs.start("shake",tools,"Solar Torch"),"Shake starts on a held damaged torch")
	check(action.kind=="shake" and repairs.busy(),"Shake owns a registered hand action")
	pose_at(.45);var left: Dictionary=action.sample_pose();pose_at(.56)
	check((left.view_rot as Vector3).distance_to(action.sample_pose().view_rot)>.02,"Shake changes device rotation between key poses")
	repairs._process(1.20);repairs._process(.21);tools._process(0)
	check(tools.fault_for("Solar Torch").is_empty() and tools.beam.visible,"Contact commits at the end of shaking and restores the real beam")
	check(inventory.total("Wire")==wire and inventory.total("Wood")==wood and tools.charge["Solar Torch"]<=45.0,"Shaking uses no parts and does not refill a battery")
	action.stop()
	tools.develop_fault("Solar Torch","wiring");tools._process(1.0)
	check(not repairs.start("shake",tools,"Solar Torch"),"Shaking cannot repair damaged wiring")
	var saved:Dictionary=tools.save_state();tools.clear_fault("Solar Torch");tools.restore_state(saved)
	check(tools.fault_for("Solar Torch")=="wiring" and tools.charge["Solar Torch"]<=45.0,"Faults save and restore without resetting charge")
	tools.use();tools._process(0);await frames()
	check(repairs.menu_open and repairs._details.text.contains("Repair Kit") and repairs._details.text.contains("Wire: HAVE") and repairs._details.text.contains("Plastic: HAVE"),"Repair opens a readable tool and HAVE / NEED parts menu")
	check(player.get_node("CanvasLayer/SurvivalHUD").gameplay_input_blocked(),"Repair menu blocks gameplay and releases touch ownership")
	await shot("repair-menu")
	inventory.remove("Repair Kit",1);repairs.call("_refresh")
	check(repairs._repair.disabled and not repairs.start("repair",tools,"Solar Torch"),"Missing reusable repair tools disable repair without spending parts")
	inventory.add("Repair Kit",1);repairs.call("_refresh")
	if preview:
		await frames(10);pointer(repairs._repair.get_global_rect().get_center());await frames()
		check(repairs.busy() and repairs.pending.kind=="repair" and inventory.total("Wire")==wire,"Actual touch with emulated mouse replay starts one repair without an early spend")
		repairs.cancel();repairs.open(tools,"Solar Torch")
	repairs.close()
	var kit: int=inventory.total("Repair Kit");var plastic: int=inventory.total("Plastic")
	check(repairs.start("repair",tools,"Solar Torch"),"Repair begins only with the correct reusable tool and parts")
	tools._process(0)
	check(inventory.total("Wire")==wire and repairs.pending.time==0,"Repair spends nothing when clicked")
	pose_at(2.8)
	var cover:=action._repair_device.find_child("BatteryCover",true,false) as Node3D
	check(action._view_tool.find_child("SalvagedScrewdriver",true,false)!=null and action._view_tool.find_child("ReplacementWire",true,false)!=null and cover.rotation.x<-.7,"Repair visibly opens the case with a screwdriver and replacement wire")
	await shot("repair-first")
	player.cam_mode=1;player.call("_apply_camera_mode");pose_at(2.8);await shot("repair-third")
	check(action._left_tool.visible and action._tool.visible,"Third-person repair holds the opened component and screwdriver")
	player.cam_mode=0;player.call("_apply_camera_mode")
	repairs._process(2.0);root.get_node("Stats").damage_revision+=1;repairs._process(.1)
	check(not repairs.busy() and tools.fault_for("Solar Torch")=="wiring" and inventory.total("Wire")==wire,"Damage cancels before contact without consuming parts")
	check(repairs.start("repair",tools,"Solar Torch"),"Interrupted repair can restart")
	repairs._process(5.11)
	check(tools.fault_for("Solar Torch").is_empty() and inventory.total("Wire")==wire-1 and inventory.total("Plastic")==plastic-1 and inventory.total("Repair Kit")==kit,"Finish consumes one wire and plastic, retains the tool, and restores the torch")
	repairs._process(1.0);action.stop()
	tools.charge["Solar Torch"]=0.0;tools.develop_fault("Solar Torch","contact")
	repairs.start("shake",tools,"Solar Torch");repairs._process(1.20);repairs._process(.3)
	check(not tools.working("Solar Torch") and tools.charge["Solar Torch"]==0,"Repairing a contact cannot charge an empty battery")
	action.stop();tools.clear_fault("Solar Torch")
	hold("Walkie Talkie");tools.enabled["Walkie Talkie"]=true;tools.develop_fault("Walkie Talkie","wiring")
	tools.use();check(repairs.menu_open and not tools._reply>0 and repairs.repair_cost(tools,"Walkie Talkie")=={"Wire":2,"Screw":1},"Failed radio shows its own two-wire/screw recipe instead of transmitting")
	repairs.close();tools.clear_fault("Walkie Talkie")
	for item in ["Wire","Wire","Screw","Screw"]:inventory.craft_item(item)
	var machine:=load("res://scenes/wind_generator.tscn").instantiate() as Node3D;current_scene.add_child(machine)
	machine.global_position=player.global_position+Vector3(2,0,0);machine.set_process(false);machine.charge=65.0
	machine.develop_fault("motor");var state: Dictionary=machine.save_survival_state()
	machine.restore_survival_state(state)
	check(machine.fault=="motor" and machine.charge==65 and repairs.repair_cost(machine,"WindGenerator").get("Motor",0)==1,"Seized generator saves its fault and requires a replacement motor")
	machine.advance(10);check(machine.charge==65,"Broken wind wiring or motor cannot generate power")
	machine.interact_survival(player);check(repairs.menu_open and machine.interaction_caption()=="REPAIR","Aim/use on a failed machine opens its Repair menu")
	repairs.close();wire=inventory.total("Wire");var motor: int=inventory.total("Motor")
	check(repairs.start("repair",machine,"WindGenerator"),"Generator service starts within reach")
	repairs._process(5.11)
	check(machine.fault.is_empty() and inventory.total("Motor")==motor-1 and inventory.total("Wire")==wire-2 and machine.charge==65,"Generator repair uses its own parts, preserves stored energy and restores power")
	repairs._process(1.0);action.stop();machine.queue_free()
	var before: int=inventory.total("Solar Torch");var metal: int=inventory.total("Metal")
	var hud:=player.get_node("CanvasLayer/SurvivalHUD");hud._craft_open=true
	hud.call("_craft_item","Solar Torch")
	check(repairs.busy() and action.kind=="assemble_electronics" and not hud._craft_open and inventory.total("Solar Torch")==before,"Craft confirmation closes the menu and starts visible assembly before granting the product")
	pose_at(2.5);await shot("assembly")
	repairs._process(5.11);repairs._process(1.0);action.stop()
	check(inventory.total("Solar Torch")==before+1 and inventory.total("Metal")==metal-2,"Assembly commits recipe and result together at final contact")
	tools.restore_state({"charge":{"Solar Torch":28},"installed":{},"enabled":{}})
	check(tools.fault_for("Solar Torch").is_empty() and tools.charge["Solar Torch"]==28,"Legacy electronics saves remain valid")
	if preview:
		hold("Walkie Talkie");tools._process(.1);await shot("worn-radio")
	current_scene.get_node("OceanAmbience").stop_environment();current_scene.queue_free();current_scene=null;await frames(8)
	print("EQUIPMENT REPAIR: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
