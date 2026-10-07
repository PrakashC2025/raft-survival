extends SceneTree
var checks := 0
var failures := 0
var player: Node3D
var raft: Node3D
var built: Node3D
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else: failures += 1; push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count: await physics_frame
func piece(kind: String, pos: Vector3) -> Node3D:
	var result: Node3D = player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	result.name = kind+"_Check"
	result.position = pos
	built.add_child(result)
	return result
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	var inventory := root.get_node("Inventory")
	inventory.call("new_game_reset",true)
	root.get_node("Stats").enabled = false
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false)
	player.get_node("RopeSystem").set_physics_process(false)
	await frames(100)
	for crop_id in ["Tomato","Potato"]:
		var pot := piece("PlanterPot",Vector3(4,0.35,4)) as Node3D
		check(pot.plant_seed(crop_id),crop_id+" seed uses existing planter logic")
		var plant: Node3D=pot._plant
		plant.set_process(false)
		plant.restore_state({"id":crop_id,"stage":1,"timer":0})
		var model: Node3D = plant._container.get_node_or_null(crop_id+"PlantModel")
		check(model!=null,crop_id+" sprout uses textured 3D crop model")
		var meshes: Array[Node] = model.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()<=6,crop_id+" model has at most six shared surfaces")
		var leaf := model.find_child("TomatoLeaf*",true,false) as MeshInstance3D
		check(leaf!=null and (leaf.get_active_material(0) as BaseMaterial3D).albedo_texture!=null,crop_id+" leaf vein texture survived import")
		for part in meshes:
			if str(part.name).begins_with("Tomato_") or part.name in ["Flower","PotatoFlower"]:
				check(not part.visible,"Sprout hides fruit and flowers: "+str(part.name))
		plant.restore_state({"id":crop_id,"stage":3,"timer":0})
		model=plant._container.get_node(crop_id+"PlantModel")
		check(is_equal_approx(plant._grow,1.0),crop_id+" mature growth restores normally")
		if crop_id=="Potato":
			var tubers := model.find_child("PotatoTuber*",true,false) as MeshInstance3D
			var local_bounds: AABB=tubers.mesh.get_aabb()
			check(local_bounds.end.y<0,"Potatoes are attached underneath the soil-line root")
			var count: int=inventory.call("total","Potato")
			plant.call("_do_dig")
			check(plant._harvesting,"Harvest starts the root reveal once")
			var pending: Dictionary=plant._pending_dig_drop.duplicate()
			plant.call("_do_dig")
			check(plant._pending_dig_drop==pending,"Repeated grab cannot duplicate potato rewards")
			await create_timer(0.55).timeout
			check(plant._container.position.y>0.35 and plant._container.scale.x>0.9,"Pulled plant shows full-size potatoes above the soil")
			await create_timer(1.4).timeout
			check(not pot.has_plant() and int(inventory.call("total","Potato"))>count,"Reveal collects produce and frees planter")
		pot.queue_free();await frames()
	var wall := piece("Wall",Vector3(4,1.4,3))
	var roof := piece("Roof",Vector3(4,2.725,4))
	player.global_position=raft.to_global(Vector3(4,0.9,4.7))
	player.aim_valid=true;player.aim_collider=wall;player.aim_point=wall.to_global(Vector3(0,0,0.15));player.aim_normal=wall.global_basis.z
	await frames()
	check(player.call("_resolve_wall_torch").valid,"Torch mounts on a clear solid wall face")
	inventory.call("add","Torch",1)
	player.active_item="Torch"
	var progress:=player.get_node("SurvivalProgression")
	progress.set_process(false);progress.torch_fuel=150.0
	var owned: int=inventory.call("total","Torch")
	progress.call("use_torch")
	var mounted:=built.find_child("WallTorch_*",false,false) as Node3D
	check(mounted!=null and int(inventory.call("total","Torch"))==owned-1,"Mount transfers an owned torch without charging a second recipe")
	check(mounted.burning and mounted.fuel==150.0 and progress.torch_fuel==0.0,"Mount transfers flame and remaining fuel")
	check((mounted.get("_light") as OmniLight3D).visible,"Mounted torch gives real warm light at night")
	raft.get_node("ConstructionBatch").call("refresh")
	var flame: MeshInstance3D = mounted.get("_visual").get_node("TorchFlames").get_child(0)
	check(flame.visible and flame.material_override is ShaderMaterial,"Timber batching preserves animated torch flame material")
	check(not player.call("_resolve_wall_torch").valid,"Duplicate mount at the same location is rejected")
	var saved: Array=player.call("_serialize_built_pieces")
	var torch_saved: Dictionary={}
	for entry in saved:
		if entry.t=="WallTorch":torch_saved=entry
	check(not torch_saved.is_empty() and torch_saved.survival.burning,"Wall torch saves as its own type, rather than a wall")
	mounted.set_process(false)
	var rain:=player.get_node("RainSystem")
	rain.call("start_rain",20.0)
	mounted.call("_process",0.5)
	check(mounted.burning,"Roof protects the mounted flame from rain")
	roof.queue_free();await frames()
	mounted.call("_process",0.5)
	check(not mounted.burning and mounted.fuel>0.0,"Exposed rain extinguishes flame while preserving unburnt fuel")
	rain.call("stop_rain")
	mounted.call("restore_survival_state",torch_saved.survival)
	check(mounted.burning and mounted.fuel==150.0,"Mounted light/fuel restores from saved state")
	player.active_item=""
	mounted.call("interact_survival",player)
	check(int(inventory.call("total","Torch"))==owned and progress.torch_fuel==150.0,"Taking wall torch returns inventory item and its flame")
	await frames()
	inventory.loaded_meta["built"]=[torch_saved]
	player.call("_restore_built_pieces")
	await frames()
	var restored:=built.find_child("WallTorch_*",false,false) as Node3D
	check(restored!=null and restored.burning and restored.fuel>149.0,"Continue rebuilds the mounted torch with its saved flame and fuel")
	progress.torch_fuel=0.0
	inventory.call("remove","Torch",int(inventory.call("total","Torch")))
	inventory.call("add","Stone",60000)
	var remaining: float=restored.fuel
	player.active_item=""
	restored.call("interact_survival",player)
	check(not restored.is_queued_for_deletion() and restored.fuel==remaining,"Full bag leaves wall torch and fuel intact")
	var avatar:=player.get_node("Body/BeachSurvivor") as Node3D
	check(avatar.transform.basis.z.normalized().dot(Vector3.FORWARD)>0.99,"Survivor's authored +Z front now faces movement -Z")
	player.call("equip_rope_gun");player.cam_mode=1;player.call("_apply_camera_mode")
	player.camera.global_rotation=Vector3(-0.18,0.6,0)
	var launcher: Node3D=player._third_person_launcher
	var grip:=launcher.get_node("AnimatedHandGrip")
	var rig: Skeleton3D=grip.get("skeleton")
	var pose:=rig.get_node("HeldArmPose")
	pose.call("_process_modification")
	var wrist_pos: Vector3=(rig.global_transform*rig.get_bone_global_pose(rig.find_bone("Wrist.R"))).origin
	check(player.to_local(wrist_pos).z < -0.10,"Holding pose brings the animated wrist in front of the torso")
	grip.call("_process",0.0)
	check((-launcher.global_basis.z.normalized()).dot(-player.camera.global_basis.z.normalized())>0.999,"Animated third-person hand holds barrel along camera aim")
	print("CROP TORCH SMOKE: %d checks, %d failures"%[checks,failures])
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free()
	for unused in range(25):await process_frame
	quit(0 if failures==0 else 1)
