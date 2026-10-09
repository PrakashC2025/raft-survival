extends SceneTree

var checks := 0
var failures := 0
var player: Node3D
var raft: Node3D
var built: Node3D
var inv: Node
const VEGETATION := preload("res://scripts/vegetation_visual.gd")
class RopeStack extends RigidBody3D:
	var item_name := "Soil"
	var amount := 5
	var collected := false
	var is_hooked := true
	func set_pickup_amount(value: int) -> void:amount=value

func _initialize() -> void:
	create_timer(150).timeout.connect(func(): push_error("FAIL: edit/tree fixture timed out"); quit(1))
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func frames(count: int = 3) -> void:
	for unused in count: await physics_frame
	await process_frame

func fixture(kind: String, at: Vector3, yaw: float = 0.0) -> Node3D:
	var piece: Node3D = player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	piece.name = "%s_EditTest_%d" % [kind,piece.get_instance_id()]
	piece.transform = Transform3D(Basis(Vector3.UP,yaw),at)
	built.add_child(piece)
	piece.add_to_group("build_surface")
	if kind == "Foundation": player.call("_grid_register",Vector2i(roundi(at.x/2),roundi(at.z/2)),piece)
	return piece

func aim(at: Vector3, support: Node3D) -> void:
	var world: Vector3 = raft.to_global(at)
	player.global_position = world + Vector3(0,1,3)
	player.camera.global_position = world + Vector3(0,3,3)
	player.camera.look_at(world)
	player.aim_valid = support != null
	player.aim_collider = support
	player.aim_point = world
	player.aim_normal = Vector3.UP
	player.aim_distance = 3.0

func start(piece: Node3D) -> void:
	player.call("_start_edit",piece)
	check(player._editing == piece, str(piece.name) + " enters edit mode")

func place_mobile() -> void:
	var controls: Control = player.get_node("CanvasLayer/MobileControls")
	controls.force_show = true
	controls.call("_update_visibility")
	controls.call("_apply_viewport_size")
	controls.set("_mode","init")
	controls.call("_sync_mode")
	var button: Button = controls.get("_btn_place")
	check(button.visible, "Touch PLACE is available while editing")
	var down := InputEventScreenTouch.new()
	down.index = 7; down.pressed = true; down.position = button.get_global_rect().get_center()
	root.push_input(down,true)
	player.call("_poll_gameplay_actions")
	var up := down.duplicate() as InputEventScreenTouch
	up.pressed = false
	root.push_input(up,true)
	check(not Input.is_action_pressed("place_build"),"Touch PLACE releases ownership")

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	Input.use_accumulated_input = false
	root.size = Vector2i(1280,720)
	inv = root.get_node("Inventory")
	inv.call("new_game_reset",true)
	root.get_node("Stats").enabled = false
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	player = get_first_node_in_group("player")
	raft = get_first_node_in_group("raft")
	built = raft.get_node("BuiltPieces")
	player.set_process(false); player.set_physics_process(false)
	raft.set_physics_process(false)
	await frames(4)
	raft.rotation = Vector3(0,0.4,0)
	await frames()
	var handoff := root.get_node_or_null("WakeHandoff")
	if handoff != null: handoff.queue_free()
	await frames()
	var supplies: Dictionary = inv.items.duplicate()
	var first := fixture("Foundation",Vector3(2,0,0))
	var other := fixture("Foundation",Vector3(0,0,2))
	await frames()
	# No normal-build ghost exists: edit must still work and optional sockets stay optional.
	check(player.ghost == null and not player.build_mode,"Editing starts from normal play without a build ghost")
	start(first)
	await frames()
	aim(Vector3(-2,0.15,0),raft)
	player.call("_update_edit_follow")
	check(player._edit_valid,"Foundation can move to a free supported cell")
	place_mobile()
	check(player._editing == null and player._grid_occupancy.get(Vector2i(-1,0)) == first,"Touch PLACE commits the moved foundation")
	check(not player._grid_occupancy.has(Vector2i(1,0)),"Old foundation cell is released")
	await frames()
	check(not first.get_node("CollisionShape3D").disabled,"Placed foundation restores solid collision")
	start(first)
	await frames()
	aim(Vector3(0,0.15,2),other)
	player.call("_update_edit_follow")
	check(not player._edit_valid,"Occupied foundation shows an invalid edit preview")
	player.call("_confirm_edit")
	check(player._editing == first,"Invalid PLACE keeps the piece selected")
	# Cancelling must follow raft movement, and a save during dragging records its committed location.
	var original: Transform3D = player._edit_original_local_transform
	var saved: Array = player.call("_serialize_built_pieces")
	check(saved.any(func(entry: Dictionary):return entry.t=="Foundation" and entry.x[9]==original.origin.x and entry.x[11]==original.origin.z),"Saving during edit keeps the original committed foundation alongside the starter extension")
	raft.position.x += 1.0
	await frames()
	player.call("_cancel_edit")
	check(first.transform.is_equal_approx(original),"Cancel restores raft-local position after sailing")
	check(player._grid_occupancy.get(Vector2i(-1,0)) == first,"Cancel restores original occupancy")
	await frames()
	var wall := fixture("Wall",Vector3(0,1.4,-1))
	await frames()
	start(wall)
	await frames()
	aim(Vector3(0,0.15,0.9),raft)
	player.call("_update_edit_follow")
	check(player._edit_valid,"Wall can move using normal edge placement")
	player.call("_confirm_edit")
	check(player._editing == null and wall.position.z > 0.8,"Wall PLACE commits on the chosen edge")
	await frames()
	start(wall)
	await frames()
	aim(Vector3(0,0.15,0.9),raft)
	player.call("_update_edit_follow")
	check(player._edit_valid,"A wall can be placed back at its own original spot")
	player.call("_confirm_edit")
	var half := fixture("HalfWall",Vector3(-2,0.775,-1))
	await frames()
	start(half)
	await frames()
	aim(Vector3(-2,0.15,0.9),first)
	player.call("_confirm_edit")
	check(player._editing == null and absf(half.position.y-0.775)<0.02,"Half-wall relocation preserves its half height")
	if player._editing != null: player.call("_cancel_edit")
	await frames()
	var roof := fixture("Roof",Vector3(0,2.725,0))
	await frames()
	start(roof)
	await frames(6)
	check(roof.get_node("CollisionShape3D").disabled,"Roof refresh cannot re-enable the dragged roof collider")
	aim(Vector3(0,2.65,1),wall)
	player.call("_update_edit_follow")
	check(player._edit_valid,"Roof can return to a supported ceiling position")
	var count_before := built.get_child_count()
	player.call("_confirm_edit")
	check(player._editing == null and built.get_child_count() == count_before,"Roof edit moves exactly one tile")
	await frames()
	var pot := fixture("PlanterPot",Vector3(0,0.35,2))
	await frames()
	pot.call("plant_seed","Potato")
	var crop = pot.get("_plant")
	start(pot)
	await frames()
	aim(roof.position+Vector3.UP*0.075,roof)
	player.call("_update_edit_follow")
	check(player._edit_valid,"Pot can move onto a roof top")
	player.call("_confirm_edit")
	check(player._editing == null and pot.position.y > 2.8,"Pot PLACE commits on the roof")
	check(pot.get("_plant") == crop,"Moving a pot preserves the planted crop")
	await frames()
	start(pot)
	await frames()
	aim(Vector3(10,0,10),null)
	player.call("_confirm_edit")
	check(player._editing == pot and not player._edit_valid,"Pot placement over ocean stays red and cannot commit")
	player.call("_cancel_edit")
	check(pot.position.y > 2.8,"Cancel returns the pot to its roof")
	await frames()
	check(inv.items == supplies,"Moving and cancelling pieces spends no construction materials")
	# Deleting while the red preview covers another foundation must leave that tile registered.
	start(first)
	await frames()
	aim(Vector3(0,0.15,2),other)
	player.call("_update_edit_follow")
	player.call("_remove_editing")
	await frames()
	check(player._grid_occupancy.get(Vector2i(0,1)) == other,"Removing a red preview preserves the foundation underneath")
	await _controls()
	await _building_hands()
	await _soil_feedback()
	await _debris_visuals()
	await _trees()
	print("EDIT TREE SMOKE: %d checks, %d failures" % [checks,failures])
	current_scene.queue_free()
	for unused in 25:await process_frame
	quit(0 if failures == 0 else 1)

func _controls() -> void:
	var controls: Control = player.get_node("CanvasLayer/MobileControls")
	var hud: Control = player.get_node("CanvasLayer/SurvivalHUD")
	hud.visible = true
	player.call("select_hotbar_slot",1)
	controls.call("_sync_mode")
	check(not controls._btn_rope.visible,"Selecting food hides the rope CAST shortcut")
	hud.call("_compute_layout")
	var gun_rect: Rect2 = hud.get("_rope_slot_rect")
	check(gun_rect.position.x < hud._hotbar_rects[0].position.x and gun_rect.size.x >= 54,"Permanent gun occupies the first comfortable quick slot")
	check(hud.call("claims_touch",gun_rect.get_center()),"Gun quick slot owns touches without moving the camera")
	var before: Array = inv.slots.duplicate(true)
	var tap := InputEventScreenTouch.new()
	tap.index=9;tap.pressed=true;tap.position=gun_rect.get_center()
	root.push_input(tap,true)
	tap.pressed=false;root.push_input(tap,true)
	controls.call("_sync_mode")
	check(player.rope_gun_selected and controls._btn_rope.visible,"First quick slot equips the gun and reveals CAST")
	check(inv.slots == before and inv.slots.size() == 30,"Gun quick slot does not occupy or displace bag items")
	for viewport_size in [Vector2i(1280,720),Vector2i(960,540),Vector2i(800,450)]:
		root.size=viewport_size
		await process_frame
		controls.call("_apply_viewport_size")
		hud.call("_compute_layout")
		var fits := true
		for button: Button in controls._all_buttons:
			var rect := button.get_global_rect()
			fits = fits and Rect2(Vector2.ZERO,controls.size).encloses(rect) and rect.size.x >= 54
		check(fits,"All touch targets fit and stay at least 54px at "+str(viewport_size))
		for mode in ["normal","build","edit"]:
			var buttons: Array = [controls._btn_jump,controls._btn_rope,controls._btn_use,controls._btn_aim,controls._btn_edit,controls._btn_dive,controls._btn_recall,controls._btn_run,controls._btn_build,controls._btn_help]
			if mode != "normal": buttons=[controls._btn_place,controls._btn_rotate,controls._btn_build,controls._btn_help,controls._btn_next if mode=="build" else controls._btn_remove]
			var separate := true
			for i in buttons.size():
				for j in range(i+1,buttons.size()):
					separate = separate and not buttons[i].get_global_rect().intersects(buttons[j].get_global_rect())
			check(separate,"Touch targets do not overlap in "+mode+" at "+str(viewport_size))
	root.size=Vector2i(1280,720)
	await process_frame
	controls.call("_apply_viewport_size")
	if OS.get_cmdline_user_args().has("--preview"):
		player.global_position=raft.global_position+Vector3(0,1.05,0)
		player.camera.global_position=raft.global_position+Vector3(0,2.2,1.0)
		player.camera.look_at(raft.global_position+Vector3(0,0,-5))
		player.aim_valid=false;player.aim_collider=null
		controls.call("_sync_mode")
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://../phone-controls-preview.png")==OK,"Desktop phone controls screenshot saved")

func _building_hands() -> void:
	var action: Node = player.get("_action")
	inv.call("place_at",5,"Tomato",1)
	player.call("select_hotbar_slot",5)
	action.call("_process",0.0)
	var original_hand: Node3D = player._hand_item
	player.selected_piece_index=player.BUILD_RECIPE_NAMES.find("Foundation")
	player.call("_toggle_build")
	check(action.kind=="build" and action._construction_idle and not original_hand.visible,"Build mode replaces selected food immediately")
	check(is_instance_valid(action._left_tool) and action._view_tool.get_node_or_null("ConstructionTimber")!=null,"Construction has a hammer and separate left-hand timber")
	player.cam_mode=1;action.call("_process",0.0)
	check(action._tool.visible and action._left_tool.visible and not action._held.visible,"Third person shows construction tools without food")
	player.active_item="Torch"
	player.get_node("SurvivalProgression").call("_process",0.0)
	check(not player.get_node("SurvivalProgression").get("_third_torch").visible,"Construction also hides a third-person torch")
	player.active_item="Tomato"
	player.cam_mode=0;action.call("_process",0.0)
	await frames()
	aim(Vector3(2,0.15,0),raft)
	player.call("_update_build_preview")
	if not player.build_valid:print("ASSEMBLY INVALID ",player._diag)
	check(player.build_valid,"Assembly regression begins from a green foundation preview")
	var expected: Vector3=raft.to_local(player._ghost_transform.origin)
	var count_before:=built.get_child_count()
	var wood_before: int=inv.call("total","Wood")
	player.call("_begin_build_action")
	# Sky aim can have no raw collider although the placement resolver found support.
	check(not player._pending_build.is_empty() and is_instance_valid(player._pending_build.collider),"Assembly locks resolved support")
	player.camera.rotate_y(1.4)
	player.is_swimming=true
	player.call("_tick_build_action",0.8)
	player.is_swimming=false
	check(built.get_child_count()==count_before+1 and int(inv.call("total","Wood"))==wood_before-5,"Turning the camera or briefly touching water cannot cancel green placement")
	var placed: Node3D=built.get_child(built.get_child_count()-1)
	check(placed.position.distance_to(expected)<0.02,"Assembly commits the original green spot")
	action.call("_process",1.0)
	check(action._construction_idle and not original_hand.visible,"Finishing assembly retains construction hands without a food flash")
	if OS.get_cmdline_user_args().has("--preview"):
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://../construction-hands-preview.png")==OK,"Construction hands screenshot saved")
	player.call("_toggle_build")
	check(player.active_item=="Tomato" and player._hand_item==original_hand and original_hand.visible and action.kind.is_empty(),"Leaving build mode restores the previously held item")
	action.call("play","eat",1.0,Vector3.ZERO)
	player.call("_toggle_build")
	check(action.kind=="build" and not original_hand.visible,"Construction immediately replaces an unfinished eating animation")
	await frames()
	aim(Vector3(0,0.15,-2),raft);player.call("_update_build_preview")
	player.call("_begin_build_action")
	check(not player._pending_build.is_empty(),"Exit-during-assembly regression starts a real pending build")
	player.call("_toggle_build")
	check(action.kind.is_empty() and original_hand.visible,"Leaving during assembly immediately restores the held item")
	player.call("_tick_build_action",0.01)
	var produce: Script=load("res://scripts/produce_visual.gd")
	for item in ["Potato","Tomato","Banana"]:
		var one: Node3D=produce.create(item)
		var two: Node3D=produce.create(item)
		check(one.get_child(0).mesh==two.get_child(0).mesh and one.get_child(0).material_override==two.get_child(0).material_override,"Detailed "+item+" meshes and skin are shared")
		one.free();two.free()
	if OS.get_cmdline_user_args().has("--preview"):await _produce_preview(produce)

func _produce_preview(produce: Script) -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(256,256);viewport.transparent_bg=true;viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color(0,0,0,0)
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=0.55
	environment.environment=settings;viewport.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-25,0);light.light_energy=1.8;viewport.add_child(light)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.37
	camera.position=Vector3(0.12,0.17,0.42);camera.look_at(Vector3.ZERO);camera.current=true
	var canvas:=CanvasLayer.new();root.add_child(canvas)
	var panel:=ColorRect.new();panel.color=Color(0.055,0.075,0.09);panel.size=Vector2(840,320);panel.position=Vector2(220,170);canvas.add_child(panel)
	var index:=0
	for item in ["Potato","Tomato","Banana"]:
		var model: Node3D=produce.create(item);viewport.add_child(model)
		for unused in 5:await process_frame
		await RenderingServer.frame_post_draw
		var picture:=viewport.get_texture().get_image()
		check(picture.save_png("res://textures/ui/advanced_"+item.to_lower()+".png")==OK,item+" model icon rendered")
		var art:=TextureRect.new();art.texture=ImageTexture.create_from_image(picture);art.position=Vector2(232+index*276,182);art.size=Vector2(256,256);canvas.add_child(art)
		var label:=Label.new();label.text=item.to_upper();label.position=Vector2(320+index*276,452);canvas.add_child(label)
		model.queue_free();await process_frame;index+=1
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://../produce-preview.png")==OK,"Produce render comparison saved")
	canvas.queue_free();viewport.queue_free()

func _soil_feedback() -> void:
	var hud: Control=player.get_node("CanvasLayer/SurvivalHUD")
	var controls: Control=player.get_node("CanvasLayer/MobileControls")
	check(inv.total("Soil")==2000 and inv.testing_soil_granted,"New Game grants 2000 testing Soil")
	inv.remove("Soil",10);inv.grant_testing_resources()
	check(inv.total("Soil")==1990,"Testing Soil does not refill after spending")
	inv.save_game({},"quick");inv.load_game("quick")
	check(inv.testing_soil_granted and inv.total("Soil")==1990,"Continue preserves the one-time Soil grant")
	inv.remove("Soil",1990);inv.testing_soil_granted=false;inv.testing_soil_revision=0
	var wood_before: int=inv.total("Wood")
	inv.grant_testing_resources()
	check(inv.total("Soil")==2000 and inv.total("Wood")==wood_before,"Older saves gain Soil without refilling spent Wood")
	var spawner: Node=current_scene.get_node("DebrisSpawner")
	check("Soil" in spawner.ITEM_POOL,"Random ocean debris includes Soil")
	player.global_position=Vector3(1000,10,1000)
	player.camera.global_position=player.global_position+Vector3(0,1,1)
	player.camera.look_at(player.global_position+Vector3(0,0,-4))
	player.select_hotbar_slot(4);player.aim_collider=null;player.aim_valid=false
	controls.call("_sync_mode")
	check(not controls._btn_use.visible,"No action button is shown for an unusable item in empty space")
	var debris: RigidBody3D=load("res://scenes/debris.tscn").instantiate()
	debris.item_name="Soil";current_scene.add_child(debris);debris.freeze=true
	debris.global_position=player.global_position+Vector3(0,0,-1)
	player.aim_collider=debris;player.aim_valid=true;player.aim_distance=1.0
	controls.call("_sync_mode")
	check(controls._btn_use.visible and controls.call("_button_caption",controls._btn_use)=="COLLECT" and controls.call("_button_icon_kind",controls._btn_use)=="hand","Debris shows COLLECT with a hand icon")
	check(controls._btn_use.get_global_rect().get_center().x<root.size.x*0.5 and controls._btn_use.size.x>=120,"Large collect/action button is on the left")
	player._collect_debris(debris)
	check(hud._pickup_active.item=="Soil" and hud._pickup_active.amount==1,"Collected Soil appears with its actual name and count")
	inv.pickup_received.emit("Wood",2)
	check(hud._pickup_active.item=="Soil" and hud._pickup_queue.size()==1,"New collections queue one by one")
	hud.call("_process",1.7)
	check(hud._pickup_active.item=="Wood" and hud._pickup_active.amount==2,"Next collection displays its own item and count")
	var rope: Node=player.get_node("RopeSystem")
	rope.set("_state",4);controls.call("_sync_mode")
	check(not controls._btn_recall.visible and not controls._btn_rope.visible,"Automatic return shows neither RECALL nor another CAST")
	rope.call("_force_cancel")
	var stack:=RopeStack.new()
	current_scene.add_child(stack)
	var soil_before: int=inv.total("Soil")
	rope.call("_collect_one",stack)
	check(inv.total("Soil")==soil_before+5 and stack.collected,"Rope collects the entire stack instead of deleting all but one item")
	var old_slots: Array=inv.slots.duplicate(true)
	for index in 30:inv.slots[index]={"item":"Stone","count":2000}
	inv.slots[0]={"item":"Soil","count":1998};inv.call("_recompute")
	var partial:=RopeStack.new();current_scene.add_child(partial)
	rope.call("_collect_one",partial)
	check(inv.total("Soil")==2000 and partial.amount==3 and not partial.collected and not partial.is_hooked,"A nearly full bag keeps the three uncollected Soil on the released rope stack")
	check(hud._pickup_queue.back().amount==2,"Partial rope collection reports only the two accepted Soil")
	partial.queue_free();inv.slots=old_slots;inv.call("_recompute");inv.changed.emit()
	await frames()
	if OS.get_cmdline_user_args().has("--preview"):
		var target: RigidBody3D=load("res://scenes/debris.tscn").instantiate()
		target.item_name="Plastic";current_scene.add_child(target);target.freeze=true;target.global_position=player.global_position+Vector3(0,0,-1)
		player.aim_collider=target;player.aim_valid=true;player.aim_distance=1.0
		controls.set("_move_id",8);controls.call("_sync_mode")
		controls.set("_base",controls.get("_dock"));controls.set("_knob",controls.get("_dock")+Vector2(0,-25))
		hud.show_toast("");hud._pickup_queue.clear();hud._pickup_active={};hud.show_pickup("Soil",1)
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://../collection-controls-preview.png")==OK,"Left collect control, human icons and pickup feed screenshot saved")
		controls.call("reset_input");target.queue_free()

func _debris_visuals() -> void:
	var samples: Array[Node3D]=[]
	for item in ["Wood","Rope","Plastic","Barrel","Stone","Metal","Soil","Sponge","Potato Seed","Coconut Seed","Banana Seed"]:
		var debris: Node3D=load("res://scenes/debris.tscn").instantiate()
		debris.item_name=item;current_scene.add_child(debris)
		debris.freeze=true;debris.set_physics_process(false);debris.call("_set_visual_alpha",1.0)
		var visual: Node3D=debris.get("_model_visual")
		check(is_instance_valid(visual) and visual.find_children("*","MeshInstance3D",true,false).size()>0,"Floating "+item+" has a recognizable detailed model")
		if item in ["Wood","Barrel"]:
			var body:=visual.get_child(0) as MeshInstance3D
			var arrays:=body.mesh.surface_get_arrays(0)
			var normal:Vector3=(arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[260]
			print("SALVAGE NORMAL ",item," ",normal)
			check(normal.x>0.5,"Smooth "+item+" surface normals face outward")
		if item in ["Wood","Barrel","Plastic","Rope","Metal","Soil","Stone"]:
			var body:=visual.get_child(0) as MeshInstance3D
			check(body.material_override==null and body.get_active_material(0).shader==preload("res://shaders/debris_weathered.gdshader"),item+" visibly uses its weathered surface")
		samples.append(debris)
	if OS.get_cmdline_user_args().has("--preview"):
		var viewport:=SubViewport.new();viewport.size=Vector2i(256,176);viewport.transparent_bg=true;viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var environment:=WorldEnvironment.new();var settings:=Environment.new()
		settings.background_mode=Environment.BG_COLOR;settings.background_color=Color(0,0,0,0)
		settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=0.6
		environment.environment=settings;viewport.add_child(environment)
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-25,0);light.light_energy=1.4;viewport.add_child(light)
		var camera:=Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.85
		camera.position=Vector3(0.75,0.65,1.1);camera.look_at(Vector3.ZERO);camera.current=true
		var canvas:=CanvasLayer.new();root.add_child(canvas)
		var panel:=ColorRect.new();panel.color=Color(0.055,0.075,0.09);panel.size=Vector2(1152,664);panel.position=Vector2(64,28);canvas.add_child(panel)
		var title:=Label.new();title.text="FLOATING SALVAGE  |  WEATHERED SURFACES & SHARED MODELS";title.position=Vector2(84,40);canvas.add_child(title)
		for index in samples.size():
			var debris:=samples[index];debris.reparent(viewport);debris.transform=Transform3D.IDENTITY
			for unused in 4:await process_frame
			await RenderingServer.frame_post_draw
			var art:=TextureRect.new();art.texture=ImageTexture.create_from_image(viewport.get_texture().get_image())
			art.position=Vector2(80+(index%4)*282,72+floori(index/4.0)*204);art.size=Vector2(256,176);canvas.add_child(art)
			var label:=Label.new();label.text=str(debris.item_name).to_upper().trim_suffix(" SEED");label.position=art.position+Vector2(88,172);canvas.add_child(label)
			debris.hide();debris.reparent(current_scene)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://../floating-debris-preview.png")==OK,"All floating debris comparison screenshot saved")
		canvas.queue_free();viewport.queue_free()
	for debris in samples:debris.queue_free()
	await frames()

func _trees() -> void:
	var mature: Node3D = load("res://scripts/plant_instance.gd").new()
	mature.plant_id = "Coconut"
	current_scene.add_child(mature)
	mature.position = Vector3(80,5,0)
	mature.restore_state({"id":"Coconut","stage":3,"health":5,"fruits":[{"p":[0.5,2.3,0],"e":70.0,"g":70.0}]})
	mature.set_process(false)
	var height := VEGETATION.local_bounds(mature).size.y
	print("Mature planted coconut height: ",height)
	check(height > 6.5 and height < 8.0,"Adult coconut stands several times taller than the 1.8m player")
	check(mature._col_shape.shape.size.y > 5.3,"Adult coconut has a matching tall trunk collider")
	check(mature._fruits[0].pos.y > 4.5 and mature._fruits[0].elapsed == 70.0,"Legacy fruit moves into the taller crown and keeps its ripeness")
	var saved: Dictionary = mature.save_state()
	mature.restore_state(saved)
	check(mature._fruits[0].pos.y == saved.fruits[0].p[1],"New coconut saves preserve fruit socket positions")
	var seed: Node3D = load("res://scripts/plant_instance.gd").new()
	seed.plant_id = "Coconut"
	current_scene.add_child(seed)
	seed.position = Vector3(77,5,0)
	seed.set_process(false)
	check(VEGETATION.local_bounds(seed).size.y < 1.5,"A newly planted coconut starts as a small seedling")
	seed._process(15.0)
	check(VEGETATION.local_bounds(seed).size.y > 1.5,"Coconut grows continuously from its seedling size")
	seed.restore_state({"id":"Coconut","stage":0,"timer":0.0,"health":5})
	for frame in range(900):
		var ready: bool = current_scene.get_node("IslandSetup").setup_complete
		if ready and frame > 150: break
		await physics_frame
	var count := 0
	var tall := true
	for island in get_nodes_in_group("island"):
		for palm in island.get_children():
			if not str(palm.name).begins_with("Palm"): continue
			var actual_height: float = VEGETATION.local_bounds(palm).size.y * palm.global_basis.get_scale().y
			if actual_height < 5.8 or actual_height > 8.6: print("PALM HEIGHT ",island.name,"/",palm.name," ",actual_height," scale ",palm.global_basis.get_scale())
			tall = tall and actual_height > 5.8 and actual_height < 8.6
			count += 1
	check(count == 31 and tall,"All 31 island coconut palms have adult 6 to 8.4m proportions")
	if OS.get_cmdline_user_args().has("--preview"):
		await _preview(mature,seed)

func _preview(_mature: Node3D, _seed: Node3D) -> void:
	player.get_node("CanvasLayer").hide()
	player.global_position = Vector3(75,5.9,0)
	player._body_visual.visible = true
	player._body_visual.rotation.y = 0.0
	player.camera.current = false
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new(); plane.size = Vector2(25,25)
	ground.mesh = plane
	var mat := StandardMaterial3D.new();mat.albedo_color=Color(0.56,0.45,0.29)
	ground.material_override=mat
	current_scene.add_child(ground);ground.position=Vector3(78,5,0)
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.position=Vector3(78,9,16)
	camera.look_at(Vector3(78,8,0))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12.0;camera.current=true
	var label := Label.new()
	label.text="COCONUT SCALE CHECK   |   Survivor 1.8 m   |   Seedling -> Adult ~7.2 m"
	label.position=Vector2(24,24)
	root.add_child(label)
	for unused in 12: await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	check(picture.save_png("res://../coconut-scale-preview.png") == OK,"Desktop tree comparison screenshot saved")
