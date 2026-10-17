extends SceneTree
var checks:=0
var failures:=0
var player: CharacterBody3D
const CONTACT:=preload("res://scripts/contact_audio.gd")
func _initialize() -> void:
	create_timer(150).timeout.connect(func():push_error("FAIL: contact audio timeout");quit(1))
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int) -> void:
	for unused in count:await physics_frame
	await process_frame
func ground(parent: Node3D) -> void:
	var body:=StaticBody3D.new();parent.add_child(body)
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(40,1,40)
	collider.shape=box;body.add_child(collider);body.position.y=-.5
func run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	root.get_node("Inventory").new_game_reset(true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed;await frames(150)
	player=get_first_node_in_group("player");player.set_process(false)
	var raft:=get_first_node_in_group("raft");raft.set_physics_process(false)
	var deck:=Node3D.new();current_scene.add_child(deck);deck.position=Vector3(0,200,0);ground(deck)
	player.global_position=Vector3(0,201.0,0);player.velocity=Vector3.ZERO;await frames(20)
	check(player.is_on_floor(),"Real player settles on a supported dry surface")
	var before:int=player._footfall_count
	var start:Vector3=player.global_position
	Input.action_press("move_forward");await frames(60);Input.action_release("move_forward")
	var walking:int=player._footfall_count-before
	var expected_contacts:=floori(player.global_position.distance_to(start)*2.0/player.SURVIVOR_WALK_STRIDE_M)
	check(walking>=2 and absi(walking-expected_contacts)<=1,"Actual walking produces contacts at measured stride distance")
	check(player._footstep_surface=="wood" and CONTACT.BANK.wood.has(player._footstep_audio.stream),"Wood deck uses recorded timber contacts")
	check(player._survivor_animation.ends_with("Walk") and not player._body_visual.visible,"First-person walking advances the same hidden body gait")
	await frames(25);before=player._footfall_count;await frames(40)
	check(player._footfall_count==before and not player._gait_active,"Stopping stays silent and resets the contact clock")
	var wall:=StaticBody3D.new();current_scene.add_child(wall);wall.global_position=player.global_position+Vector3(0,0,-.65)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(4,3,.6);collision.shape=shape;wall.add_child(collision)
	Input.action_press("move_forward");await frames(15);before=player._footfall_count;await frames(30);Input.action_release("move_forward")
	check(player._footfall_count==before and player._gait_speed<.65,"Pushing into an actual wall does not make footsteps or walking bob")
	wall.queue_free();await frames(3)
	var sprint_start:=player.global_position
	Input.action_press("sprint");Input.action_press("move_forward");await frames(60)
	Input.action_release("move_forward");Input.action_release("sprint")
	var sprint_expected:=floori(player.global_position.distance_to(sprint_start)*2.0/player.SURVIVOR_RUN_STRIDE_M)
	check(player._footfall_count-before>=2 and absi(player._footfall_count-before-sprint_expected)<=1,"Real sprint contacts follow the measured running stride")
	await frames(20);player.set_physics_process(false)
	before=player._footfall_count;player._advance_gait(.8,5.0,true,true)
	check(player._footfall_count-before<=1,"A stalled frame cannot replay missed footsteps")
	player._advance_gait(.2,3.0,false,false);before=player._footfall_count
	for unused in 30:player._advance_gait(.016,3.0,false,false)
	check(player._footfall_count==before and player._gait_speed==0,"Airborne and swimming movement cannot make ground contacts")
	for biome in ["winter","volcano","spring",""]:
		deck.add_to_group("island");deck.set_meta("biome",biome)
		player.global_position=Vector3(0,200.9,0);await frames(3)
		var expected:String={"winter":"snow","volcano":"stone","spring":"sand","":"sand"}[biome]
		check(player._ground_surface()==expected,"Ground probe selects the real "+expected+" surface")
	deck.remove_from_group("island")
	for surface in ["wood","sand","snow","stone","grass","metal","casing"]:
		var previous:AudioStream=null
		var varied:=true
		for unused in 12:
			var sample:AudioStream=CONTACT.pick(surface)
			if sample==previous:varied=false
			previous=sample
		check(varied,"Consecutive "+surface+" contacts do not repeat the same recording")
	var manifest:Array=JSON.parse_string(FileAccess.get_file_as_string("res://audio/contact/source_manifest.json"))
	var immediate:=true
	for entry in manifest:
		if float(entry.contact_onset_ms)>.5 or not ResourceLoader.exists(entry.file):immediate=false
	check(immediate and manifest.size()==22,"All 22 imported contact recordings have at most 0.5 ms leading padding")
	var action:=player.get_node("SurvivalAction");action.set_process(false)
	for kind in ["build","repair","shake"]:
		player.play_action(kind,6.0 if kind=="repair" else 1.4,Vector3.ZERO,"Solar Torch")
		var played:int=action._foley_count
		action.elapsed=float(action.duration)*float(action._cue_times[0])-.002;action._advance_feedback()
		check(action._foley_count==played,"No "+kind+" sound precedes visible contact")
		action.elapsed+=.004;action._advance_feedback()
		check(action._foley_count==played+1 and action._sound.stream is AudioStreamWAV,"Recorded "+kind+" sound starts on contact")
		played=action._foley_count;action.elapsed=float(action.duration);action._advance_feedback()
		check(action._foley_count==played,"Long frames skip stale "+kind+" sounds without a burst")
		action.stop()
	var tree:Node3D=load("res://scripts/plant_instance.gd").new();tree.plant_id="Coconut";current_scene.add_child(tree);tree.set_process(false);tree._health=10
	Input.action_press("interact");tree._run_hold("chop",1.0,.56)
	check(tree._health==10,"Chopping produces no damage or impact before the downstroke")
	tree._run_hold("chop",1.0,.02)
	check(tree._health==9 and player._interaction_audio.stream==tree.CHOP_SOUND,"Tree damage and recorded impact commit together on axe contact")
	tree._run_hold("chop",1.0,.20)
	check(tree._health==9,"A single swing cannot hit the same tree twice")
	Input.action_release("interact");tree._run_hold("chop",1.0,.1);action.stop()
	current_scene.get_node("OceanAmbience").stop_environment();current_scene.queue_free();current_scene=null;await frames(8)
	print("CONTACT AUDIO: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
