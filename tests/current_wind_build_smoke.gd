extends SceneTree
var checks:=0
var failures:=0
var player: CharacterBody3D
var raft: Node3D
var built: Node3D
var preview:=false
func _initialize() -> void:
	create_timer(180).timeout.connect(func():push_error("FAIL: current/wind/build timeout");quit(1))
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=3) -> void:
	for unused in count:await physics_frame
	await process_frame
func piece(kind: String, at: Vector3) -> Node3D:
	var node: Node3D=player.build_pieces[player.BUILD_RECIPE_NAMES.find(kind)].instantiate()
	node.name=kind+"_WindCheck_"+str(node.get_instance_id());node.position=at;built.add_child(node);node.add_to_group("build_surface")
	if kind=="Foundation":player.call("_grid_register",Vector2i(roundi(at.x/2),roundi(at.z/2)),node)
	return node
func aim(kind: String, target: Vector3, support: Node3D) -> Dictionary:
	player.call("select_piece_for_build",player.BUILD_RECIPE_NAMES.find(kind))
	player.aim_valid=true;player.aim_collider=support;player.aim_point=raft.to_global(target);player.aim_normal=Vector3.UP
	player._placement_ray_override={"origin":player.aim_point+Vector3.UP*3.0,"direction":Vector3.DOWN}
	return player.call("_resolve_placement",kind,player.aim_point)
func shot(name: String, eye: Vector3, target: Vector3) -> void:
	if not preview:return
	var camera:=Camera3D.new();current_scene.add_child(camera);camera.global_position=raft.to_global(eye);camera.look_at(raft.to_global(target));camera.current=true
	await frames(18);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://../"+name+".png")==OK,"Saved desktop view: "+name)
	camera.queue_free()
func run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	var inv:=root.get_node("Inventory");inv.new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");built=raft.get_node("BuiltPieces")
	await frames(150);player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false);raft.rotation=Vector3.ZERO
	var spawner:=current_scene.get_node("DebrisSpawner");spawner.set_process(false)
	for unused in 12:
		spawner._spawn_upstream()
		var debris:Node3D=spawner._active[-1]
		check((debris.global_position-spawner._origin()).dot(spawner._direction)<=-50.0,"A fresh arrival starts in the distant current")
	var distant:Node3D=spawner._active[-1];var start:Vector3=distant.global_position
	await frames(120)
	check((distant.global_position-start).dot(spawner._direction)>0.10 and distant.linear_velocity.length()<1.0,"Distant loot approaches through actual slow physics motion")
	check(spawner._active.size()<=48,"Expanded approach retains the phone physics budget")
	for yaw in [0.0,0.65]:
		raft.rotation.y=yaw;await frames()
		for rotation in [0.0,PI/2.0,PI]:
			player.call("select_piece_for_build",0);player.build_rotation=rotation
			var target:Vector3=player.call("_grid_to_world",Vector2i(1,1));target.y=player.call("_get_structural_deck_y")
			player.aim_valid=false;player.aim_collider=null;player.aim_point=target+Vector3.DOWN*3
			player._placement_ray_override={"origin":target+Vector3.UP*3,"direction":Vector3.DOWN}
			var plan:Dictionary=player.call("_resolve_placement","Foundation",player.aim_point)
			check(plan.get("valid",false) and plan.get("cell")==Vector2i(1,1),"Empty sea cell snaps to its connected neighbour after raft/foundation rotation")
	raft.rotation=Vector3.ZERO
	var stair:=piece("Stairs",Vector3(0,.25,-1));await frames()
	var correct:=aim("Foundation",Vector3(2,.15,0),stair)
	check(correct.get("valid",false),"Hitting a stair does not falsely reject an empty adjacent foundation cell")
	stair.call("restore_survival_state",{})
	check(is_equal_approx(stair.run,2.8) and is_equal_approx(stair.get_node("BuildSockets/Socket_Top").position.z,3.0),"Legacy stacked stairs preserve their original landing on Continue")
	stair.call("restore_survival_state",{"run":2.4})
	check(is_equal_approx(stair.get_node("CollisionLanding").position.z,2.5),"New compact stairs restore their shorter collision geometry")
	stair.queue_free();await frames()
	for kind in ["Screw","Wire","Motor"]:
		check(kind in load("res://scripts/survival_hud.gd").CRAFT_ORDER,"Electrical component is offered in crafting: "+kind)
	for unused in 6:check(inv.craft_item("Screw"),"Metal crafts a real screw")
	for unused in 4:check(inv.craft_item("Wire"),"Metal and insulation craft a wire")
	check(inv.craft_item("Motor") and inv.craft_item("Battery"),"Craft motor from screws/wire and craft the storage battery")
	player.get_node("SurvivalProgression").level=3
	check(inv.can_afford("WindGenerator"),"All six DIY turbine ingredients can be crafted and assembled")
	var screws:int=inv.total("Screw");var wire:int=inv.total("Wire")
	check(inv.craft("WindGenerator") and inv.total("Screw")==screws-4 and inv.total("Wire")==wire-2 and inv.total("Motor")==0,"Assembly spends each electrical component exactly once")
	var deck:Node3D
	for cell in range(1,6):deck=piece("Foundation",Vector3(cell*2,0,0))
	await frames();var open:=aim("WindGenerator",Vector3(10,.15,0),deck)
	check(open.get("valid",false),"Full-scale turbine can be built on an exposed supported foundation")
	inv.add("WindGenerator",1);player.build_valid=true;player._ghost_transform=open.transform;player._ghost_support=open.support
	player._begin_build_action()
	var action:=player.get_node("SurvivalAction");action.set_process(false);action._process(.3)
	check(player._pending_build.get("seconds",0)==6.0 and action.kind=="assemble_electronics","Electrical construction owns six-second visible component assembly in build mode")
	player._tick_build_action(5.8)
	check(inv.total("WindGenerator")==1 and not player._pending_build.is_empty(),"Generator assembly retains materials until its final placement")
	player.build_mode=false;player._tick_build_action(.1)
	check(inv.total("WindGenerator")==1 and player._pending_build.is_empty(),"Cancelling electrical assembly returns to building without spending the kit")
	var roof:=piece("Roof",Vector3(10,2.725,0));await frames()
	check(not aim("WindGenerator",Vector3(10,.15,0),deck).get("valid",false),"Placement rejects a rotor intersecting the ceiling")
	roof.queue_free();await frames()
	var generator:=piece("WindGenerator",Vector3(10,.5,0));generator.set_process(false)
	var consumer:=piece("ElectricPurifier",Vector3(8,.5,0));consumer.set_process(false)
	generator.advance(10.0);check(generator.charge>5.0,"Wind charges the physical storage battery")
	generator._rotor_speed=0.0;generator._process(1.0)
	check(generator._rotor_speed>0.0 and generator._rotor_speed<1.0,"Blades accelerate gradually rather than instantly spinning")
	var speed:float=generator._rotor_speed;generator.interact_survival(player);generator._process(.2)
	check(not generator.enabled and generator._rotor_speed<speed,"Brake switch reaches by hand and blades slow down")
	var charge:float=generator.charge;consumer.advance(1.0)
	check(consumer.seconds>0 and generator.charge<charge,"Stored energy powers the purifier with the rotor braked")
	check(not consumer.request_power(-1.0),"Invalid power requests cannot add energy")
	var saved:Dictionary=generator.save_survival_state();generator.charge=0;generator.restore_survival_state(saved)
	check(is_equal_approx(generator.charge,saved.charge) and not generator.enabled,"Battery charge and brake switch survive restoration")
	if player.build_mode:player.call("_toggle_build")
	player._placement_ray_override={};player.get_node("Body").hide();player.get_node("CanvasLayer").hide();player.get_node("RainSystem").stop_rain();player.camera.get_node("HandPivot").hide()
	var clock:=current_scene.get_node("Sky3D/TimeOfDay");clock.pause();clock.current_time=10.0;current_scene.get_node("OceanAtmosphere")._process(1.0)
	generator.enabled=true;generator.charge=78.0;generator._refresh_label();generator.set_process(true);consumer._refresh_label()
	await shot("diy-wind-generator",Vector3(8.3,2.2,-2.7),Vector3(10,1.45,0))
	if preview:
		clock.current_time=21.0;current_scene.get_node("OceanAtmosphere")._process(1.0)
		var ocean:=get_first_node_in_group("ocean");ocean._process(1.0)
		var moon:Vector3=ocean._mat.get_shader_parameter("moon_dir")
		var facing:=Vector3(moon.x,0,moon.z).normalized()
		await shot("night-moon-ocean",Vector3(0,2.2,0),facing*100.0+Vector3(0,30.0,0))
	current_scene.queue_free();current_scene=null
	player=null;raft=null;built=null
	await frames(5)
	print("CURRENT WIND BUILD: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
