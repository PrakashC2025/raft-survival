extends SceneTree
var checks:=0
var failures:=0
var player: Node3D
var raft: Node3D
var inv: Node
var tools: Node
var controls: Control
var preview:=false
func _initialize() -> void:
	create_timer(120).timeout.connect(func():push_error("FAIL: held tools/garden timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=4) -> void:
	for unused in count:await process_frame
func tap(button: Button) -> void:
	var touch:=InputEventScreenTouch.new();touch.index=31;touch.position=button.get_global_rect().get_center();touch.pressed=true
	root.push_input(touch,true);touch.pressed=false;root.push_input(touch,true)
	await frames()
func shot(label: String) -> void:
	if not preview:return
	await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/held-tools-"+label+".png")==OK,"Rendered "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	inv=root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft")
	player.set_process(false);player.set_physics_process(false);player.get_node("RopeSystem").set_physics_process(false);raft.set_physics_process(false)
	await frames(120)
	player.get_node("RainSystem").stop_rain();player.global_position=raft.to_global(Vector3(0,1.1,0))
	tools=player.get_node("PortableElectronics");tools.set_process(false)
	controls=player.get_node("CanvasLayer/MobileControls");controls.force_show=true;controls._update_visibility()
	inv.add("ElectricLamp",1);inv.craft_item("Battery",3);player.get_node("SurvivalServices").equip_owned("ElectricLamp")
	tools._process(.12);await frames()
	check(tools._mount.visible and tools._cover.visible,"LED exposes mount and battery-cover buttons")
	await tap(tools._cover);tools._process(.12);await frames()
	check(tools.cover_open and controls._look_id==-1 and controls._button_touches.is_empty(),"Mobile cover tap opens without camera drag or stuck touch")
	check(tools._remove.visible and tools._replace.visible,"Open cover reveals separate Remove and Insert/Replace actions")
	controls._sync_mode();check(not controls._btn_use.visible,"LED light-on action hides while its battery compartment is open")
	await shot("led-cover")
	await tap(tools._remove);tools._process(1.9)
	check(not tools.installed.ElectricLamp and not tools.enabled.ElectricLamp,"Remove LED battery button stores the cell and powers off")
	tools._process(.12);await tap(tools._cover);tools._process(.12);await frames();await tap(tools._replace);tools._process(.8)
	var cell:=player._hand_item.find_child("AnimatedBattery",true,false) as Node3D
	var cover:=player._hand_item.find_child("BatteryCover",true,false) as Node3D
	check(tools.installed.ElectricLamp and cell.visible and cover.position.z>.105,"Insert LED button animates its actual battery and correct cover origin")
	tools._process(1.1);tools._process(.12);await tap(tools._power);tools._process(.12)
	check(tools.led.visible and tools.led.omni_range>=12,"LED power button restores useful light reach")
	await tap(tools._mount)
	check(player.build_mode and player.BUILD_RECIPE_NAMES[player.selected_piece_index]=="ElectricLamp","Mobile Mount LED button enters real placement mode")
	player._toggle_build();controls.force_show=false;controls._update_visibility()
	var alt:=InputEventKey.new();alt.physical_keycode=KEY_ALT;alt.pressed=true;tools._input(alt)
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Desktop Alt opens cursor access to tool buttons")
	alt.pressed=false;tools._input(alt)
	check(not tools._desktop_cursor and (not preview or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED),"Alt release restores desktop camera control")
	var wood: int=inv.total("Wood");var rope: int=inv.total("Rope");var sticks: int=inv.total("Torch")
	check(inv.craft_item("Torch",5) and inv.total("Torch")==sticks+5 and inv.total("Wood")==wood-10 and inv.total("Rope")==rope-5,"Batch of five torches spends exact total ingredients")
	var slots: Array=inv.slots.duplicate(true)
	for index in inv.slots.size():inv.slots[index]={"item":"Stone","count":inv.MAX_STACK}
	inv._recompute();var before: Array=inv.slots.duplicate(true)
	check(not inv.craft_item("Torch",5) and inv.slots==before,"Failed batch leaves a full inventory untouched")
	inv.slots=slots;inv._recompute();inv.changed.emit()
	var hud:=player.get_node("CanvasLayer/SurvivalHUD");hud.toggle_crafting();hud._craft_menu.select_item("Torch");hud._craft_menu.quantity=5;hud._craft_menu._refresh_detail();await frames()
	check(hud._craft_menu._build.text=="Build ×5","Craft confirmation clearly shows chosen quantity")
	tools._process(.12)
	check(hud._craft_menu._build.get_global_rect().end.y<=root.get_visible_rect().size.y,"Craft Build and Cancel remain inside the visible screen")
	await shot("craft-quantity")
	var batch_before: int=inv.total("Torch");hud._craft_menu._build.pressed.emit();await frames()
	check(inv.total("Torch")==batch_before+5 and not hud._craft_open,"Quantity confirmation builds the selected batch through the real HUD callback")
	var progress:=player.get_node("SurvivalProgression");progress.set_process(false)
	var actions:=player.get_node("FireActions");actions.set_process(false)
	var pose:=player.get_node("SurvivalAction");pose.set_process(false)
	var built:=raft.get_node("BuiltPieces")
	var wall: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find("Wall")].instantiate();wall.position=Vector3(1,1.4,0);built.add_child(wall)
	player.get_node("SurvivalServices").equip_owned("Torch");pose.stop();progress.torch_end_time=preload("res://scripts/torch_cycle.gd").next_dawn(player);progress.torch_fuel=100;progress.legacy_torch=true
	player.aim_valid=true;player.aim_collider=wall;player.aim_point=wall.to_global(Vector3(0,0,.15));player.aim_normal=wall.global_basis.z;player.aim_distance=1
	check(player.mount_held_torch(),"Lit torch transfers to a clear wall")
	var mounted:=built.find_child("WallTorch_*",false,false) as Node3D;mounted.set_process(false)
	# A newly selected spare can borrow the mounted flame without removing it.
	progress.extinguish_torch();player.get_node("SurvivalServices").equip_owned("Torch");pose.stop();player.aim_collider=mounted;player.aim_point=mounted.global_position
	check(player.interaction_caption()=="LIGHT TORCH" and actions.start("torch_light",mounted),"Unlit stick can light from another mounted burning stick")
	actions._process(1);actions._process(.4);pose.stop();progress._process(.01)
	check(progress.is_held_lit() and mounted.burning and not mounted.is_queued_for_deletion(),"Lighting uses the mounted flame without taking the source")
	var deadline: float=progress.torch_end_time;var total_before: int=inv.total("Torch")+inv.total("Burning Torch")
	player.aim_collider=wall;player.aim_point=wall.to_global(Vector3(-.74,0,.15));player.aim_normal=wall.global_basis.z
	check(player.mount_held_torch() and progress.is_held_lit() and progress.torch_end_time==deadline,"Mounting equips and lights the next spare with the same expiry")
	check(inv.total("Torch")+inv.total("Burning Torch")==total_before-1,"Torch relay consumes exactly the one mounted stick")
	player.get_node("SurvivalServices").equip_owned("Torch");player.aim_point=wall.to_global(Vector3(.74,0,.15))
	check(player.mount_held_torch() and progress.torch_fuel>0 and inv.has("Burning Torch",1),"Mounting an unlit spare preserves the separately stored burning stick")
	player.get_node("SurvivalServices").equip_owned("Burning Torch");progress._process(.1)
	check(progress.is_held_lit(),"Returning to the stored burning stick restores its flame")
	progress.extinguish_torch();player.active_item="";mounted.interact_survival(player);await frames();progress._process(1.1)
	check(progress.is_held_lit() and progress.torch_fuel>1 and progress._torch_light.visible,"Taking a lit wall stick stays burning beyond the next second")
	check(progress._torch_light.omni_range>=12,"Hand torch casts light across a larger raft")
	var shelter: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find("Roof")].instantiate();shelter.position=Vector3(0,2.725,0);built.add_child(shelter);await frames()
	var rain:=player.get_node("RainSystem");rain.start_rain(20);progress._tick=0;progress._process(.5)
	check(progress.is_held_lit(),"Rain cannot extinguish a retrieved torch beneath a real roof")
	rain.stop_rain();shelter.queue_free();await frames()
	inv.remove("Torch",inv.total("Torch"));player.aim_valid=true;player.aim_collider=wall;player.aim_point=wall.to_global(Vector3(0,0,.15));player.aim_normal=wall.global_basis.z
	check(player.mount_held_torch() and inv.total("Burning Torch")==0 and progress.torch_fuel==0 and not progress.is_held_lit(),"Final stick mounts once and leaves no phantom held flame")
	var pot: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find("TreePot")].instantiate();pot.position=Vector3(0,.55,2);built.add_child(pot);pot.set_process(false)
	check(pot.box_size.x>=1.3 and pot.plant_seed("Coconut"),"Wider supported tree pot accepts a coconut")
	var plant: Node3D=pot._plant;plant.set_process(false)
	tools._process(.12);pose.stop()
	var garden_camera:=Camera3D.new();current_scene.add_child(garden_camera);garden_camera.current=true
	var heights: Array[float]=[]
	for stage in 4:
		plant.restore_state({"id":"Coconut","stage":stage,"timer":0});await frames()
		var bounds: AABB=preload("res://scripts/vegetation_visual.gd").local_bounds(plant._container)
		heights.append(bounds.size.y*plant._grow)
		check(stage==3 or plant._fruits.is_empty(),"Coconut stage %d has no premature fruit"%stage)
		garden_camera.global_position=pot.global_position+(Vector3(2,1.1,2.4) if stage<2 else Vector3(6,4,8));garden_camera.look_at(pot.global_position+Vector3.UP*(.35 if stage<2 else 2.5))
		await shot("coconut-stage-%d"%stage)
	check(heights[0]<.5 and heights[1]>heights[0] and heights[2]>heights[1] and heights[3]>6,"Coconut grows from a small shoot through young tree to adult height")
	var palm:=plant._container.get_node("CoconutPalm") as Node3D
	var trunk:=palm.find_child("Tree_0_Trunk",true,false) as MeshInstance3D
	var vertices: PackedVector3Array=trunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX];var relative: Transform3D=plant._container.global_transform.affine_inverse()*trunk.global_transform
	var low:=INF;for vertex in vertices:low=minf(low,(relative*vertex).y)
	var sum:=Vector3.ZERO;var n:=0
	for vertex in vertices:
		var at: Vector3=relative*vertex
		if at.y<low+.02:sum+=at;n+=1
	var base: Vector3=sum/float(maxi(n,1))
	check(Vector2(base.x,base.z).length()<.04 and absf(base.y)<.03,"Adult curved palm remains rooted at the centre of the soil")
	for fruit in plant._fruits:fruit.elapsed=fruit.regrow
	plant._update_fruits(0);var coconut_before: int=inv.total("Coconut");plant._pick_fruit(plant._fruits[0]);await create_timer(1.5).timeout
	var fallen: Node3D
	for item in get_nodes_in_group("debris"):
		if item.get("item_name")=="Coconut" and item.get_parent()==raft:fallen=item;break
	check(fallen!=null and not fallen.falling and inv.total("Coconut")==coconut_before,"Picked coconut falls onto the raft and waits for collection")
	if fallen!=null:player._collect_debris(fallen)
	check(inv.total("Coconut")==coconut_before+1,"Fallen coconut can be collected into the normal bag")
	var flock:=current_scene.get_node("OceanBirds");var bird: Node3D=flock._birds[0].root;var at_before: Vector3=bird.global_position;flock._physics_process(1)
	check(flock._birds.size()==2 and bird.visible and bird.global_position.distance_to(raft.global_position)<35 and bird.global_position.distance_to(at_before)>.2,"Two visible animated gulls fly close enough to see from the raft")
	flock.hit_bird(0);check(flock._birds[0].state=="falling","Sea gulls retain the existing hunt and falling pickup flow")
	var dome:=current_scene.get_node("Sky3D/SkyDome");dome.wind_speed=0;var cloud_before: Vector2=dome._panorama_cloud_position
	await create_timer(.4).timeout
	check(dome._panorama_cloud_position.distance_to(cloud_before)>.002,"Clouds advance during real gameplay frames even in still wind")
	current_scene.get_node("OceanAmbience").stop_environment();current_scene.queue_free();await frames(25)
	print("HELD TOOLS GARDEN SMOKE: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
