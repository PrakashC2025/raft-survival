extends Node
## Original action-specific key poses. Two-bone IK uses these after the gait;
## the first-person tool uses matching, smaller motions without camera shake.
const GRIP := preload("res://scripts/rope_hand_grip.gd")
const ART := preload("res://scripts/machine_visual.gd")
const MAT := preload("res://scripts/object_materials.gd")
const FOOD := preload("res://scripts/survival_item_visual.gd")
const FOLEY := {"bite": preload("res://audio/action_bite.wav"), "sip": preload("res://audio/contact/drink_sip.wav"),
	"water":preload("res://audio/action_stir.wav"), "earth":preload("res://audio/contact/sand2.wav"), "anchor":preload("res://audio/contact/cloth.wav"),
	"stir": preload("res://audio/action_stir.wav")}
const FIRE_KINDS := ["ignite_fire","snuff_fire","torch_light","torch_off","torch_mount","fire"]
const ELECTRONIC := preload("res://scripts/electronics_visual.gd")
const CONTACT := preload("res://scripts/contact_audio.gd")
var _repair_device: Node3D
var _repair_wire: Node3D
var _repair_right: Node3D
var _repair_left: Node3D
var _repair_item := ""
var _fire_right: Node3D
var _fire_left: Node3D
var _torch_first: Node3D
var _torch_third: Node3D
var _sparks: Node3D
var kind := ""
var _fish_contact := false
var _mouth_rig: Skeleton3D
var _mouth_bone := -1
var elapsed := 0.0
var duration := 0.0
var target := Vector3.ZERO
var player: Node3D
var _tool: Node3D
var _view_tool: Node3D
var _left_tool: Node3D
var _construction_idle := false
var _held: Node3D
var _held_item := ""
var _label: Label
var _bar: ProgressBar
var _panel: VBoxContainer
var _food_first: Node3D
var _food_third: Node3D
var _pickup_first: Node3D
var _pickup_third: Node3D
var _sound: AudioStreamPlayer
var _cues_played := 0
var _cue_times: Array[float] = []
var _cue_sound := ""
var _foley_count := 0
var _anchor_raising := false
var hands_prepared := false
var _cook_pool: Dictionary={}
static var _spoon_mesh: SphereMesh
var _warm_view: SubViewport
var _garden_whole: Array[Node3D]=[]
var _garden_cut: Array[Node3D]=[]
var _garden_seeds: Array[Node3D]=[]
var _garden_right: Node3D
const LABELS := {"cast":"CASTING LINE", "reel":"REELING IN", "chop":"CHOPPING TIMBER",
	"prepare_seed":"CUTTING FOOD · SAVING SEEDS","unpack":"OPENING RARE SUPPLIES",
	"harvest":"PULLING ROOTS", "pick":"PICKING FRUIT", "grab":"COLLECTED",
	"scoop":"GATHERING EARTH", "plant":"PLANTING SEED", "water":"WATERING SOIL",
	"build":"ASSEMBLING", "craft":"CRAFTED", "eat":"EATING", "drink":"DRINKING",
	"bandage":"BANDAGING", "strike":"SPEAR THRUST", "bow":"RELEASING ARROW", "door":"OPENING", "install":"FITTING EQUIPMENT",
	"hook":"LAUNCHING HOOK", "fire":"TENDING FIRE", "fill":"FILLING CAN", "take_fish":"UNHOOKING FISH",
	"battery":"REPLACING BATTERY", "radio":"RADIO TRANSMISSION", "look":"RAISING BINOCULARS",
	"brake":"TURBINE BRAKE",
	"shake":"RESEATING LOOSE CONTACT", "repair":"REPAIRING EQUIPMENT", "assemble_electronics":"ASSEMBLING EQUIPMENT",
	"solar":"RAISING SOLAR PANEL", "switch":"POWER SWITCH", "cook":"PREPARING FOOD",
	"mine":"MINING DEPOSIT", "dig":"DIGGING EARTH", "paddle":"ROWING", "anchor":"HANDLING ANCHOR","pump":"PUMPING AIR",
	"ignite_fire":"STRIKING STONES", "snuff_fire":"PUTTING OUT FIRE", "torch_light":"LIGHTING TORCH", "torch_off":"SNUFFING TORCH", "torch_mount":"MOUNTING TORCH"}

func _ready() -> void:
	player=get_parent() as Node3D
	_panel=VBoxContainer.new();_panel.name="ActionFeedback"
	_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left=-155;_panel.offset_right=155;_panel.offset_top=88;_panel.offset_bottom=124
	_label=Label.new();_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size",18)
	_label.add_theme_color_override("font_shadow_color",Color(0,0,0,0.95));_label.add_theme_constant_override("shadow_outline_size",3)
	_bar=ProgressBar.new();_bar.custom_minimum_size=Vector2(310,8);_bar.show_percentage=false;_bar.max_value=1.0
	_panel.add_child(_label);_panel.add_child(_bar)
	player.get_node("CanvasLayer").add_child(_panel);_panel.hide()
	get_viewport().size_changed.connect(_fit_feedback)
	_warm_hands.call_deferred()
	_sound=AudioStreamPlayer.new();_sound.name="ActionFoley";_sound.bus=&"Master";add_child(_sound)
	# Install the modifier even when the launcher is not selected.
	for candidate in player.get_node("Body").find_children("*","Skeleton3D",true,false):
		var rig := candidate as Skeleton3D
		if rig.find_bone("Wrist.R")<0: continue
		if rig.get_node_or_null("HeldArmPose")==null:
			var modifier := preload("res://scripts/held_arm_pose.gd").new()
			modifier.name="HeldArmPose";modifier.player=player
			modifier.upper=rig.find_bone("UpperArm.R");modifier.lower=rig.find_bone("LowerArm.R");modifier.wrist=rig.find_bone("Wrist.R")
			rig.add_child(modifier)
		break

func _warm_hands() -> void:
	# Let the deferred phone profile select MSAA before compiling its variants.
	await get_tree().process_frame
	if not is_inside_tree():return
	# Compile the small imported hand/material variants offscreen during setup.
	# The original meshes stay shared; first swimming/cooking no longer pays this cost.
	_warm_view=SubViewport.new();_warm_view.name="ActionMeshWarmup"
	_warm_view.size=Vector2i(32,32);_warm_view.own_world_3d=true
	_warm_view.msaa_3d=get_viewport().msaa_3d
	_warm_view.use_hdr_2d=get_viewport().use_hdr_2d
	_warm_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(_warm_view)
	var scene:=get_tree().current_scene
	if scene!=null:
		var sky:=scene.get_node_or_null("Sky3D") as WorldEnvironment
		if sky!=null:
			var environment:=WorldEnvironment.new();environment.environment=sky.environment;_warm_view.add_child(environment)
		for source in scene.find_children("*","DirectionalLight3D",true,false):
			# Identical lights/ambient/MSAA avoid compiling a second variant on use.
			var light:=source.duplicate() as DirectionalLight3D
			_warm_view.add_child(light);light.global_transform=source.global_transform
	var camera:=Camera3D.new();_warm_view.add_child(camera);camera.position=Vector3(0,0,1);camera.current=true
	var veil:=ColorRect.new();veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tint:=ShaderMaterial.new();tint.shader=preload("res://shaders/underwater_veil.gdshader")
	tint.set_shader_parameter("top_col",Color(0,.1,.2,.1));tint.set_shader_parameter("bottom_col",Color(0,.1,.2,.1))
	veil.material=tint;_warm_view.add_child(veil)
	for stage in 3:
		var sample:=Node3D.new();_warm_view.add_child(sample)
		if stage==0:
			for left in [false,true]:sample.add_child(preload("res://scripts/dive_visual.gd").swim_hand(left))
		elif stage==1:
			var hand:=preload("res://models/human_hand.glb").instantiate() as Node3D
			MAT.apply_model(hand,MAT.Kind.SKIN);sample.add_child(hand)
			var left:=hand.duplicate() as Node3D;left.scale.x=-1;sample.add_child(left)
		else:
			var station:=Node3D.new();sample.add_child(station)
			var warm_job:=preload("res://scripts/station_job.gd").new();station.add_child(warm_job)
			warm_job.set_process(false);warm_job._make_cooking_visual()
			sample.add_child(_make_tool("cook"))
			# Slice every recipe during loading, then reuse its shared mesh in play.
			for dish in preload("res://scripts/food_rules.gd").RECIPES:
				var food:=FOOD.create(dish);sample.add_child(food)
				await get_tree().process_frame
				await get_tree().process_frame
				if not is_inside_tree():return
				sample.remove_child(food);food.queue_free()
		for unused in 2:
			await get_tree().process_frame
			if not is_inside_tree():return
		_warm_view.remove_child(sample);sample.queue_free()
	_warm_view.queue_free()
	# Prepare the actual first/third-person props once, then park them hidden.
	play("cook",2.0,Vector3.ZERO,"Cooked Potato")
	_cook_pool={"tool":_tool,"view":_view_tool,"left":_left_tool,"dish":"Cooked Potato"}
	stop()
	for unused in 2:
		await get_tree().process_frame
		if not is_inside_tree():return
	hands_prepared=true

func play(action: String, seconds: float, at: Vector3, food_item: String="") -> void:
	if not LABELS.has(action):return
	_construction_idle = false
	kind=action;duration=maxf(seconds,0.15);elapsed=0;target=at
	_fish_contact=false
	_panel.offset_top=180 if action in ["repair","assemble_electronics"] else 88
	_panel.offset_bottom=_panel.offset_top+36
	if action=="anchor":
		var raft:=get_tree().get_first_node_in_group("raft")
		_anchor_raising=raft!=null and raft.get("anchored")==true
	_label.text=LABELS[action];_bar.value=0;_panel.show()
	_clear_tools()
	_cues_played=0;_cue_times.clear();_cue_sound=""
	match action:
		"prepare_seed":_cue_times.assign([.30,.48,.72]);_cue_sound="cloth"
		"unpack":_cue_times.assign([.25,.60]);_cue_sound="cloth"
		"eat":_cue_times.assign([0.36,0.63]);_cue_sound="bite"
		"drink":_cue_times.assign([0.28]);_cue_sound="sip"
		"take_fish":_cue_times.assign([.40]);_cue_sound="cloth"
		"cook":_cue_times.assign([0.30,0.58,0.78]);_cue_sound="stir"
		"paddle":_cue_times.assign([0.44]);_cue_sound="water"
		"dig":_cue_times.assign([0.57]);_cue_sound="earth"
		"anchor":_cue_times.assign([0.57]);_cue_sound="anchor"
		"strike":_cue_times.assign([0.57]);_cue_sound="water" if player.is_swimming else "cloth"
		"pump":_cue_times.assign([.10,.23,.36,.49,.62,.75,.88]);_cue_sound="cloth"
		"ignite_fire":_cue_times.assign([.30,.49,.68]);_cue_sound="stone_contact"
		"torch_light","torch_off","torch_mount":_cue_times.assign([.70]);_cue_sound="cloth"
		"snuff_fire":_cue_times.assign([.70]);_cue_sound="earth"
		"brake":_cue_times.assign([.48]);_cue_sound="cloth"
		"build":_cue_times.assign([.25,.75]);_cue_sound="hammer"
		"shake":_cue_times.assign([.1875,.3125,.4375,.5625,.6875]);_cue_sound="metal"
		"repair","assemble_electronics":_cue_times.assign([.16,.36,.46,.58,.70,.82]);_cue_sound="repair_contact"
		"grab","pick","plant","harvest","scoop","bandage","install":_cue_times.assign([0.40]);_cue_sound="cloth"
	if action=="cook" and not _cook_pool.is_empty():
		_tool=_cook_pool.tool;_view_tool=_cook_pool.view;_left_tool=_cook_pool.left
		var dish:=food_item if not food_item.is_empty() else "Cooked Potato"
		if dish!=_cook_pool.dish:
			for bowl in [_left_tool,_view_tool.get_node("PreparationBowl")]:
				var old: Node=bowl.get_node("SlicedMeal");bowl.remove_child(old);old.queue_free()
				var contents:=preload("res://scripts/meal_visual.gd").create(dish);contents.position.y=.042;bowl.add_child(contents)
			_cook_pool.dish=dish
		_fit_feedback();return
	if action in ["eat","drink","fill"]:
		_make_consumption(food_item if not food_item.is_empty() else str(player.get("active_item")))
	if action in ["chop","build","craft","scoop","cook","mine","dig","paddle","anchor","pump"]:
		_tool=_make_tool(action)
		player.add_child(_tool);GRIP.attach(_tool,player.get_node("Body"))
		_tool.get_node("AnimatedHandGrip").set("grip_offset",Vector3.ZERO)
		_tool.get_node("AnimatedHandGrip").set("animated_tool",true)
		if action == "build":
			_left_tool = Node3D.new();_left_tool.name="ConstructionTimber"
			ART.box(_left_tool,Vector3(0,0,-0.08),Vector3(0.12,0.07,0.44),MAT.make(MAT.Kind.WOOD,Color(0.47,0.29,0.12),0.9))
			player.add_child(_left_tool);GRIP.attach(_left_tool,player.get_node("Body"))
			var grip := _left_tool.get_node("AnimatedHandGrip")
			grip.set("wrist",grip.get("skeleton").find_bone("Wrist.L"))
			grip.set("animated_tool",true)
		if action=="cook":
			_left_tool=FOOD.create(food_item if not food_item.is_empty() else "Cooked Potato");_left_tool.name="PreparationBowl";player.add_child(_left_tool)
			GRIP.attach(_left_tool,player.get_node("Body"))
			var grip:=_left_tool.get_node("AnimatedHandGrip")
			grip.set("wrist",grip.get("skeleton").find_bone("Wrist.L"));grip.set("grip_offset",Vector3.ZERO);grip.set("animated_tool",true)
	if action in ["chop","build","craft","scoop","cook","grab","pick","harvest","plant","door","brake","mine","dig","paddle","anchor","pump","strike","take_fish"]:
		_view_tool=_make_tool(action) if action in ["chop","build","craft","scoop","cook","mine","dig","paddle","anchor","pump","strike"] else Node3D.new()
		var hand := preload("res://models/human_hand.glb").instantiate() as Node3D
		MAT.apply_model(hand,MAT.Kind.SKIN);_view_tool.add_child(hand)
		if action=="take_fish":hand.scale.x=-1.0
		if action in ["harvest","build","craft","plant","cook","pump","strike"]:
			var left := hand.duplicate() as Node3D
			left.scale.x=-1.0;left.position.x=-0.36;left.position.z=-0.08
			if action=="cook":left.position=Vector3(-.18,-.23,.015);left.rotation.x=.30
			_view_tool.add_child(left)
		if action == "build":
			var timber := ART.box(_view_tool,Vector3(-0.36,-0.02,-0.10),Vector3(0.12,0.07,0.44),MAT.make(MAT.Kind.WOOD,Color(0.47,0.29,0.12),0.9))
			timber.name="ConstructionTimber"
		if action=="cook":
			var bowl:=FOOD.create(food_item if not food_item.is_empty() else "Cooked Potato");bowl.name="PreparationBowl";bowl.position=Vector3(-.16,-.20,-.10);_view_tool.add_child(bowl)
		player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot/Fist").add_child(_view_tool)
		_view_tool.scale=Vector3.ONE*0.85
	if action in ["grab","pick","harvest","take_fish"] and not food_item.is_empty():
		_pickup_first=_pickup_visual(food_item);_pickup_first.position=Vector3(0,-.01,-.19);_view_tool.add_child(_pickup_first);_pickup_first.hide()
		_tool=Node3D.new();_tool.name="CollectedItem";player.add_child(_tool)
		_pickup_third=_pickup_visual(food_item);_tool.add_child(_pickup_third);_pickup_third.hide()
		GRIP.attach(_tool,player.get_node("Body"))
		_tool.get_node("AnimatedHandGrip").set("grip_offset",Vector3.ZERO)
		_tool.get_node("AnimatedHandGrip").set("animated_tool",true)
		if action=="take_fish":
			var fish_grip:=_tool.get_node("AnimatedHandGrip")
			fish_grip.set("wrist",fish_grip.get("skeleton").find_bone("Wrist.L"))

	if action in FIRE_KINDS:_make_fire_props(action)
	if action in ["prepare_seed","unpack"]:_make_garden_props(food_item)
	if action in ["repair","assemble_electronics"]:_make_repair_props(food_item)
	_fit_feedback()

func _fit_feedback() -> void:
	if not is_instance_valid(_panel):return
	var scale:=preload("res://scripts/ocean_ui.gd").scale_for(get_viewport())
	var view:=get_viewport().get_visible_rect().size/scale
	var width:=minf(390,view.x-32)
	_panel.scale=Vector2.ONE*scale;_panel.size=Vector2(width,44)
	_panel.position=Vector2((view.x-width)*.5,view.y*.5+(112 if kind in ["repair","assemble_electronics"] else 76))*scale
	_bar.custom_minimum_size.x=width

func _make_garden_props(item: String) -> void:
	_view_tool=Node3D.new();_view_tool.name="SeedPreparationHands"
	player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot/Fist").add_child(_view_tool)
	for is_left in [false,true]:
		var holder:=Node3D.new();_view_tool.add_child(holder)
		if not is_left:_garden_right=holder
		var hand:=preload("res://models/human_hand.glb").instantiate() as Node3D
		MAT.apply_model(hand,MAT.Kind.SKIN);hand.set_meta("first_person_hand",true)
		if is_left:hand.scale.x=-1;hand.position=Vector3(-.33,-.11,-.08)
		holder.add_child(hand)
	_tool=_make_tool("prepare_seed");player.add_child(_tool);GRIP.attach(_tool,player.get_node("Body"));_tool.get_node("AnimatedHandGrip").set("animated_tool",true)
	var knife:=_make_tool("prepare_seed");knife.position=Vector3(.025,-.04,-.13);_garden_right.add_child(knife)
	if kind=="unpack":knife.hide();_tool.hide()
	var crop:=preload("res://scripts/garden_items.gd").box_crop(item) if kind=="unpack" else item
	var first:=Node3D.new();first.position=Vector3(-.24,-.13,-.27);_view_tool.add_child(first)
	_left_tool=Node3D.new();player.add_child(_left_tool);GRIP.attach(_left_tool,player.get_node("Body"))
	var grip:=_left_tool.get_node("AnimatedHandGrip");grip.set("wrist",grip.get("skeleton").find_bone("Wrist.L"));grip.set("animated_tool",true);grip.set("grip_offset",Vector3.ZERO)
	for holder in [first,_left_tool]:
		if kind=="prepare_seed":ART.timber_box(holder,Vector3(0,-.067,0),Vector3(.27,.016,.17))
		var whole:=FOOD.create(item);holder.add_child(whole);_garden_whole.append(whole)
		var cut:=preload("res://scripts/garden_visual.gd").produce(crop if kind=="unpack" else "Sliced "+crop);holder.add_child(cut);cut.hide();_garden_cut.append(cut)
		var seeds:=preload("res://scripts/garden_visual.gd").seeds(crop,kind!="unpack");seeds.position=Vector3(.09,.045,-.04);holder.add_child(seeds);seeds.hide();_garden_seeds.append(seeds)

func _make_repair_props(item: String) -> void:
	_repair_item=item
	_view_tool=Node3D.new();_view_tool.name="EquipmentRepairHands"
	player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot/Fist").add_child(_view_tool)
	for is_left in [false,true]:
		var holder:=Node3D.new();holder.name="LeftRepairHand" if is_left else "RightRepairHand";_view_tool.add_child(holder)
		var hand:=preload("res://models/human_hand.glb").instantiate() as Node3D
		MAT.apply_model(hand,MAT.Kind.SKIN);hand.set_meta("first_person_hand",true)
		if is_left:hand.scale.x=-1
		holder.add_child(hand)
		if is_left:_repair_left=holder
		else:
			_repair_right=holder;holder.add_child(ELECTRONIC.screwdriver())
	_repair_device=ELECTRONIC.create(item) if item in ["Solar Torch","Walkie Talkie","Binoculars"] else ELECTRONIC.repair_kit()
	if item in ["WindGenerator","ElectricPurifier"]:_repair_device.free();_repair_device=ART.component("Motor")
	elif item=="RescueRadio":_repair_device.free();_repair_device=ELECTRONIC.create("Walkie Talkie")
	_repair_device.name="OpenedEquipment";_repair_device.position=Vector3(.05,.02,-.14);_repair_left.add_child(_repair_device)
	_repair_wire=ART.component("Wire");_repair_wire.name="ReplacementWire";_repair_wire.scale=Vector3.ONE*.25
	_repair_wire.position=Vector3(0,-.06,.08);_repair_device.add_child(_repair_wire)
	_tool=ELECTRONIC.screwdriver();player.add_child(_tool);GRIP.attach(_tool,player.get_node("Body"))
	_tool.get_node("AnimatedHandGrip").set("animated_tool",true);_tool.get_node("AnimatedHandGrip").set("grip_offset",Vector3.ZERO)
	_left_tool=_repair_device.duplicate();player.add_child(_left_tool);GRIP.attach(_left_tool,player.get_node("Body"))
	var follower:=_left_tool.get_node("AnimatedHandGrip");follower.set("wrist",follower.get("skeleton").find_bone("Wrist.L"));follower.set("animated_tool",true);follower.set("grip_offset",Vector3(0,0,-.12))
	_advance_repair_feedback(0)

func _advance_repair_feedback(t: float) -> void:
	var opening:=smoothstep(.08,.19,t)*(1-smoothstep(.73,.85,t))
	var turn:=sin(t*TAU*8)*smoothstep(.19,.29,t)*(1-smoothstep(.65,.76,t))
	if is_instance_valid(_repair_left):_repair_left.position=Vector3(-.28,-.08,-.05);_repair_left.rotation=Vector3(.15,-.12,.05)
	if is_instance_valid(_repair_right):
		_repair_right.position=Vector3(.05,-.15,.025).lerp(Vector3(.01,-.10+.018*turn,.02),opening)
		_repair_right.rotation=Vector3(.25+.15*opening,.60*opening,.28*turn)
	for device in [_repair_device,_left_tool]:
		if not is_instance_valid(device):continue
		var cover:=device.find_child("BatteryCover",true,false) as Node3D
		if cover!=null:cover.rotation.x=-1.15*opening;cover.position.z=.049+.055*opening
		var wire:=device.find_child("ReplacementWire",true,false) as Node3D
		if wire!=null:wire.visible=t>.30 and t<.72;wire.position.z=.08+.04*sin(smoothstep(.30,.68,t)*PI)
	_label.text=("OPENING CASING" if t<.20 else "RECONNECTING WIRES" if t<.50 else "TIGHTENING CONTACTS" if t<.73 else "CLOSING & TESTING")+" · "+_repair_item.to_upper()

func _fire_prop(action: String) -> Node3D:
	if action=="fire":return _pickup_visual("Wood")
	if action.begins_with("torch_"):
		return preload("res://scripts/torch_visual.gd").new()
	if action=="ignite_fire":return _pickup_visual("Stone")
	return _pickup_visual("Sand")

func _make_fire_props(action: String) -> void:
	_view_tool=Node3D.new();_view_tool.name="FireHands"
	player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot/Fist").add_child(_view_tool)
	for is_left in [false,true]:
		var grip:=Node3D.new();grip.name="LeftFireHand" if is_left else "RightFireHand";_view_tool.add_child(grip)
		var hand:=preload("res://models/human_hand.glb").instantiate() as Node3D
		MAT.apply_model(hand,MAT.Kind.SKIN);hand.set_meta("first_person_hand",true)
		if is_left:hand.scale.x=-1
		if is_left and action=="torch_off":hand.rotation.x=1.1
		grip.add_child(hand)
		if is_left:_fire_left=grip
		else:_fire_right=grip
		if is_left and action=="torch_off":
			var cap:=ART.cylinder(grip,Vector3(.12,.05,-.20),.09,.06,MAT.make(MAT.Kind.CLOTH,Color(.22,.17,.11),.95))
			cap.name="SnuffingCloth"
		if not is_left or action=="ignite_fire":
			var prop:=_fire_prop(action);prop.position=Vector3(0,-.02,-.18);grip.add_child(prop)
			if action.begins_with("torch_"):_torch_first=prop
	_tool=_fire_prop(action);_tool.name="FireActionRightProp";player.add_child(_tool)
	GRIP.attach(_tool,player.get_node("Body"));_tool.get_node("AnimatedHandGrip").set("animated_tool",true)
	_tool.get_node("AnimatedHandGrip").set("grip_offset",Vector3(0,0,-.18) if action=="ignite_fire" else Vector3.ZERO)
	if action.begins_with("torch_"):_torch_third=_tool
	if action=="ignite_fire":
		_left_tool=_fire_prop(action);_left_tool.name="FireActionLeftStone";player.add_child(_left_tool)
		GRIP.attach(_left_tool,player.get_node("Body"))
		var follower:=_left_tool.get_node("AnimatedHandGrip")
		follower.set("wrist",follower.get("skeleton").find_bone("Wrist.L"));follower.set("animated_tool",true);follower.set("grip_offset",Vector3(0,0,-.18))
		_sparks=Node3D.new();_sparks.name="StoneContactSparks";_view_tool.add_child(_sparks)
		var glow:=StandardMaterial3D.new();glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;glow.albedo_color=Color(1,.74,.23);glow.emission_enabled=true;glow.emission=Color(1,.45,.04)
		for index in 6:
			ART.box(_sparks,Vector3.ZERO,Vector3(.005,.005,.013),glow)
		_sparks.hide()
	elif action=="torch_off":
		_left_tool=Node3D.new();_left_tool.name="ThirdPersonSnuffingCloth";player.add_child(_left_tool)
		ART.cylinder(_left_tool,Vector3(0,.04,-.06),.08,.06,MAT.make(MAT.Kind.CLOTH,Color(.22,.17,.11),.95))
		GRIP.attach(_left_tool,player.get_node("Body"))
		var follower:=_left_tool.get_node("AnimatedHandGrip")
		follower.set("wrist",follower.get("skeleton").find_bone("Wrist.L"));follower.set("animated_tool",true);follower.set("grip_offset",Vector3.ZERO)
	_advance_fire_feedback(0)

func _advance_fire_feedback(t: float) -> void:
	var reach:=smoothstep(.04,.20,t)*(1-smoothstep(.80,1.0,t))
	var strike:=0.0
	for contact in [.30,.49,.68]:strike=maxf(strike,maxf(0,1-absf(t-contact)/.08))
	if is_instance_valid(_fire_right):
		_fire_right.position=Vector3(-.02-.19*strike,-.05-.07*reach,-.10*reach) if kind=="ignite_fire" else Vector3(-.05,-.04-.10*reach,-.18*reach)
		_fire_right.rotation=Vector3(-.30+.55*strike,0,-.35*strike) if kind=="ignite_fire" else Vector3(.40*reach,0,-.12*reach)
	if is_instance_valid(_fire_left):
		_fire_left.position=Vector3(-.33,-.15,-.11) if kind=="ignite_fire" else Vector3(-.32+.22*reach,.05+.19*reach,-.21*reach)
		_fire_left.rotation.z=.16*reach
	var lit: bool=player.get_node("SurvivalProgression").is_held_lit()
	for torch in [_torch_first,_torch_third]:
		if is_instance_valid(torch):
			torch.call("set_burning",lit);torch.visible=kind!="torch_mount" or t<.70
	if is_instance_valid(_sparks):
		var age:=10.0
		for contact in [.30,.49,.68]:
			if t>=contact:age=minf(age,(t-contact)*duration)
		_sparks.visible=age<.12
		if _sparks.visible:
			for index in _sparks.get_child_count():
				var spark:=_sparks.get_child(index) as Node3D
				var heading:=float(index)*TAU/6
				spark.position=Vector3(-.25,-.15,-.27)+Vector3(cos(heading)*age*.7,age*.6-4.9*age*age,sin(heading)*age*.5)
				spark.scale=Vector3.ONE*(1-age/.12)

func _pickup_visual(item: String) -> Node3D:
	if item in ["Torch","Burning Torch"]:return preload("res://scripts/torch_visual.gd").new()
	if item in ["Wood","Rope","Plastic","Metal","Stone","Barrel","Soil","Sponge","WindGenerator","ElectricLamp"]:
		var salvage:=preload("res://scripts/resource_visual.gd").create(item);salvage.scale=Vector3.ONE*.40;return salvage
	return FOOD.create(item.trim_suffix(" Seed"))

func _make_consumption(item: String) -> void:
	# These props survive Inventory.changed clearing the last selected item.
	_tool=Node3D.new();_tool.name="ConsumedFood";player.add_child(_tool)
	_food_third=FOOD.create(item);_tool.add_child(_food_third)
	GRIP.attach(_tool,player.get_node("Body"))
	_tool.get_node("AnimatedHandGrip").set("grip_offset",Vector3.ZERO)
	_tool.get_node("AnimatedHandGrip").set("animated_tool",true)
	_tool.get_node("AnimatedHandGrip").set("palm_clearance",0.0)
	if kind=="drink":
		_mouth_rig=_tool.get_node("AnimatedHandGrip").get("skeleton") as Skeleton3D
		if _mouth_rig!=null:_mouth_bone=_mouth_rig.find_bone("Head")
		_food_third.position.x=-.045
	_view_tool=Node3D.new();_view_tool.name="EatingHands"
	var hand:=preload("res://models/human_hand.glb").instantiate() as Node3D
	MAT.apply_model(hand,MAT.Kind.SKIN);hand.position=Vector3(.01,-.045,-.02);_view_tool.add_child(hand)
	_food_first=FOOD.create(item);_food_first.position=Vector3(0,-.01,-.22);_view_tool.add_child(_food_first)
	player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot/Fist").add_child(_view_tool)

func _advance_feedback() -> void:
	var progress:=clampf(elapsed/maxf(duration,.01),0,1)
	if kind=="take_fish" and progress>=.40 and not _fish_contact:
		if not player.call("take_fishing_catch"):
			player.call("_hud_toast","FISH STAYS ON THE LINE · FREE BAG SPACE AND TRY AGAIN")
			stop();return
		_fish_contact=true
	for whole in _garden_whole:if is_instance_valid(whole):whole.visible=progress<.48
	for cut in _garden_cut:if is_instance_valid(cut):cut.visible=progress>=.48
	for seeds in _garden_seeds:if is_instance_valid(seeds):seeds.visible=progress>=.70
	if is_instance_valid(_garden_right):
		var reach:=smoothstep(.04,.18,progress)*(1-smoothstep(.82,1.,progress))
		var contact:=0.0
		for strike in [.30,.48,.62]:contact=maxf(contact,maxf(0,1-absf(progress-strike)/.07))
		_garden_right.position=Vector3(-.24,.035-.11*contact,.05)*reach
		_garden_right.rotation=Vector3(-.10*contact,0,-.08*reach)
	if kind in FIRE_KINDS:_advance_fire_feedback(progress)
	if kind in ["repair","assemble_electronics"]:_advance_repair_feedback(progress)
	for prop in [_pickup_first,_pickup_third]:
		if is_instance_valid(prop):prop.visible=progress>=(.40 if kind=="take_fish" else .38) and progress<.94
		if is_instance_valid(prop) and kind=="take_fish":
			var settle:=smoothstep(.44,.82,progress)
			prop.rotation=Vector3(sin(elapsed*17)*.10*(1-settle),0,PI/2*(1-settle))
	var played_this_frame:=false
	while _cues_played<_cue_times.size() and progress>=_cue_times[_cues_played]:
		_cues_played+=1
		# Avoid bursting stale sounds after a long frame or an app resume.
		if not played_this_frame and (progress-_cue_times[_cues_played-1])*duration<.08:
			var contact:=_cue_sound
			if contact=="repair_contact":contact="casing" if _cues_played in [1,6] else "cloth" if _cues_played==2 else "metal"
			if contact=="stone_contact":contact="stone"
			_sound.stream=CONTACT.pick(contact) if CONTACT.BANK.has(contact) else FOLEY[contact]
			_sound.volume_db=-18 if contact in ["cloth","metal","casing"] else -12
			_sound.pitch_scale=randf_range(.98,1.02);_sound.play()
			_foley_count+=1;played_this_frame=true
	if kind=="eat":
		var food_scale:=1.0-.08*float(_cues_played)
		for food in [_food_first,_food_third]:
			if is_instance_valid(food):food.scale=Vector3.ONE*food_scale
	if kind in ["eat","drink"]:
		var lift:=smoothstep(.04,.26 if kind=="drink" else .30,progress)*(1.0-smoothstep(.84 if kind=="drink" else .72,.99 if kind=="drink" else .96,progress))
		for food in [_food_first,_food_third]:
			if is_instance_valid(food):food.rotation.x=(-.25 if kind=="eat" else 1.05)*lift
			if kind=="drink" and is_instance_valid(food):
				var water:=food.get_node_or_null("DrinkingWater") as Node3D
				if water!=null:
					water.position.y=.065-.040*smoothstep(.28,.79,progress)
					# The liquid surface remains level while the vessel tilts.
					water.rotation.x=-1.20*lift

func stop() -> void:
	_construction_idle = false
	kind="";_panel.hide();_clear_tools()
	if is_instance_valid(player.get("_hand_item")):player.get("_hand_item").visible=true
	if is_instance_valid(player.get("_third_person_launcher")):player.get("_third_person_launcher").visible=int(player.get("cam_mode"))==1 and not player.call("movement_owns_hands")

func _clear_tools() -> void:
	_garden_whole.clear();_garden_cut.clear();_garden_seeds.clear()
	_garden_right=null
	if is_instance_valid(_sound):_sound.stop()
	for tool in [_tool,_view_tool,_left_tool]:
		if is_instance_valid(tool):
			tool.hide()
			if tool not in _cook_pool.values():tool.queue_free()
	_tool=null;_view_tool=null;_left_tool=null
	_food_first=null;_food_third=null
	_pickup_first=null;_pickup_third=null
	_fire_right=null;_fire_left=null;_torch_first=null;_torch_third=null;_sparks=null
	_repair_device=null;_repair_wire=null;_repair_right=null;_repair_left=null
	_repair_item=""

func _process(delta: float) -> void:
	if kind=="take_fish" and (str(player.get("active_item"))!="Fishing Rod" or player.get("is_swimming") or player.get("build_mode")):stop()
	if kind=="take_fish" and not _fish_contact:target=player.get_node("SurvivalEquipment").call("catch_position")
	var construction: bool = bool(player.get("build_mode")) or is_instance_valid(player.get("_editing"))
	if (construction and kind not in ["","build","assemble_electronics"]) or (not construction and kind=="build"):stop()
	if _construction_idle and not construction: stop()
	if not kind.is_empty() and not _construction_idle:
		elapsed+=delta
		_advance_feedback()
		_bar.value=clampf(elapsed/duration,0,1)
		if elapsed>=duration:stop()
	if construction and kind.is_empty():
		play("build",0.75,Vector3.ZERO)
		_construction_idle = true
		elapsed = 0.35
		_panel.hide()
	_sync_held()
	var first := int(player.get("cam_mode"))==0
	var free_hands: bool = player.call("movement_owns_hands")
	if is_instance_valid(_tool):_tool.visible=not first and (kind!="torch_mount" or elapsed/duration<.70)
	if is_instance_valid(_left_tool):_left_tool.visible=not first
	if is_instance_valid(_view_tool):
		_view_tool.visible=first
		var pose := sample_pose()
		_view_tool.position=pose.view_pos;_view_tool.rotation=pose.view_rot
	var hand := player.get("_hand_item") as Node3D
	if is_instance_valid(hand):hand.visible=(not is_instance_valid(_view_tool) or kind=="take_fish") and not (free_hands and bool(player.get("is_swimming")))
	if is_instance_valid(_held):_held.visible=not first and (not is_instance_valid(_tool) or kind=="take_fish") and not construction and not free_hands
	if is_instance_valid(player.get("_third_person_launcher")):
		var action_hides_launcher := kind in FIRE_KINDS or kind in ["chop","build","craft","scoop","grab","pick","harvest","plant","eat","drink","cook","prepare_seed","unpack","mine","dig","paddle","anchor"]
		player.get("_third_person_launcher").visible=not first and not free_hands and not action_hides_launcher and str(player.get("active_item"))=="Rope"

func _sync_held() -> void:
	var item := str(player.get("active_item"))
	if item==_held_item:return
	_held_item=item
	if is_instance_valid(_held):_held.hide();_held.queue_free()
	_held=null
	if item in ["","Rope","Torch","Burning Torch"]:return
	var hand := player.get("_hand_item") as Node3D
	if not is_instance_valid(hand):_held_item="";return
	_held=Node3D.new();_held.name="ThirdPersonHeldItem";player.add_child(_held)
	for child in hand.get_children():
		if child is Node3D and not child.has_meta("first_person_hand") and not str(child.name).begins_with("HumanHand") and child.visible and not child.is_queued_for_deletion():
			_held.add_child(child.duplicate())
	GRIP.attach(_held,player.get_node("Body"))
	_held.get_node("AnimatedHandGrip").set("grip_offset",_item_grip(item))
	_held.get_node("AnimatedHandGrip").set("animated_tool",true)
	# Bulky food sits against the palm; handles pass between curled fingers.
	_held.get_node("AnimatedHandGrip").set("palm_clearance",0.065 if item in ["Stone","Coconut","Banana","Fish","Cooked Fish","Tomato","Potato","Baked Potato","Onion"] else 0.0)

func _item_grip(item: String) -> Vector3:
	if item in preload("res://scripts/survival_tool_visual.gd").ITEMS:return Vector3.ZERO
	match item:
		"Fishing Rod":return Vector3(0,0.02,0.015)
		"Water":return Vector3(0,-0.005,-0.20)
		"Wood","Metal","Spear","Sail Kit":return Vector3(0,-0.01,-0.04)
		"Plastic":return Vector3(0.02,0.01,-0.25)
		"Carrot","Tomato","Potato","Baked Potato","Onion","Bandage":return Vector3(0,0,-0.2)
		"Stone":return Vector3(0,-0.02,-0.19)
		"Sand","Soil":return Vector3(0,-0.04,-0.22)
		"Barrel":return Vector3(0,-0.08,-0.22)
		"Motor Kit","Life Vest":return Vector3(0,0.1,-0.26)
		_:return Vector3(0,-0.02,-0.27)

func sample_pose() -> Dictionary:
	var t := clampf(elapsed/maxf(duration,0.01),0,1)
	var weight := smoothstep(0.0,0.12,t)*(1.0-smoothstep(0.85,1.0,t)) if not kind.is_empty() else 0.0
	var right := Vector3(0.30,0.20,-0.36)
	var left := Vector3(-0.25,0.14,-0.35)
	var view_pos := Vector3.ZERO
	var view_rot := Vector3.ZERO
	var torso := Vector3.ZERO
	if kind.is_empty() and str(player.get("active_item"))=="Fishing Rod" and player.get("_fishing_catch"):
		# A raised tip supports the fish below it; the line cannot lift from below.
		return {"right":Vector3(.27,.32,-.32),"left":Vector3(-.12,.18,-.33),"weight":1.0,"torso":Vector3.ZERO,"view_pos":Vector3(0,.08,0),"view_rot":Vector3(.60,0,0)}
	match kind:
		"take_fish":
			var reach:=smoothstep(.04,.34,t)
			var pull:=smoothstep(.44,.78,t)
			var local_catch:=player.global_transform.affine_inverse()*target
			right=Vector3(.27,.32,-.32)
			left=Vector3(-.25,.12,-.30).lerp(local_catch,reach).lerp(Vector3(-.16,.20,-.32),pull)
			view_rot=Vector3(.60,0,-.12*pull)
			view_pos=Vector3(-.34,-.10,.02)
			if is_instance_valid(_view_tool):
				var view_contact:=(_view_tool.get_parent() as Node3D).to_local(target)-Basis.from_euler(view_rot)*_pickup_first.position*.85
				view_pos=view_pos.lerp(view_contact,reach).lerp(Vector3(-.24,-.14,.12),pull)
		"prepare_seed","unpack":
			var reach:=smoothstep(.04,.18,t)*(1.-smoothstep(.85,1.,t))
			var cut:=maxf(0,sin(t*TAU*3.))*reach if t<.62 else 0.
			right=Vector3(.18,.18,-.32).lerp(Vector3(-.02,.12,-.42),reach);right.y-=cut*.07
			left=Vector3(-.14,.10,-.39);torso.x=.055*reach
			view_pos=Vector3(-.08*reach,-.04*cut,-.08*reach);view_rot=Vector3(.15*cut,0,-.16*reach)
		"shake":
			var jiggle:=sin(t*TAU*4)*smoothstep(.10,.25,t)*(1-smoothstep(.70,.90,t))
			right=Vector3(.14,.34+jiggle*.09,-.31);left=Vector3(-.05,.24,-.34)
			view_pos=Vector3(-.10,.08+jiggle*.045,.035);view_rot=Vector3(jiggle*.23,0,jiggle*.12)
		"repair","assemble_electronics":
			var turn:=sin(t*TAU*8)*smoothstep(.20,.30,t)*(1-smoothstep(.65,.76,t))
			right=Vector3(.08,.16,-.40)+Vector3(0,.022*turn,-.015*turn);left=Vector3(-.10,.13,-.43)
			view_pos=Vector3(-.04,.23,-.12);torso.x=.10
		"ignite_fire":
			var strike:=0.0
			for contact in [.30,.49,.68]:strike=maxf(strike,maxf(0,1-absf(t-contact)/.08))
			right=Vector3(.24,.06,-.42).lerp(Vector3(-.03,-.02,-.51),strike)
			left=Vector3(-.12,-.03,-.52);torso.x=.16*weight
			view_pos=Vector3(-.03,-.12,-.12)
		"torch_light","torch_mount":
			var reach:=smoothstep(.04,.50,t)*(1-smoothstep(.73,.98,t))
			right=Vector3(.20,.12,-.32).lerp(Vector3(.10,-.09 if kind=="torch_light" else .38,-.68),reach)
			left=Vector3(-.18,.12,-.30).lerp(Vector3(-.03,.11,-.44),reach)
			view_pos=Vector3(-.10,-.12 if kind=="torch_light" else .10,-.28)*reach
			view_rot.x=.52*reach if kind=="torch_light" else -.15*reach;torso.x=.12*reach
		"torch_off","snuff_fire":
			var close:=smoothstep(.10,.65,t)*(1-smoothstep(.74,.98,t))
			right=Vector3(.16,.12,-.42);left=Vector3(-.18,.14,-.35).lerp(Vector3(.10,.38,-.43),close)
			view_pos=Vector3(-.12,.08,-.12)*close;view_rot.z=.10*close
		"fill":
			var dip:=sin(t*PI)
			right=Vector3(.19,-.15-dip*.35,-.45);left=Vector3(-.17,-.15,-.38)
			view_pos=Vector3(-.05,-.25*dip,-.15*dip);view_rot.x=.4*dip;torso.x=.25*dip
		"battery":
			var pull := sin(t*PI)
			right=Vector3(0.13,0.24,-0.31)
			left=Vector3(-0.05,0.18,-0.31).lerp(Vector3(-0.20,0.05,-0.15),pull)
			view_pos=Vector3(-0.12,0.07,0.08);view_rot=Vector3(-0.25,0.12,0.18*pull)
		"radio","look","solar","switch":
			var lift := sin(t*PI)
			right=Vector3(0.17,0.22,-0.32).lerp(Vector3(0.11,0.57,-0.22),lift)
			left=Vector3(-0.17,0.25,-0.31)
			view_pos=Vector3(-0.08*lift,0.16*lift,0.09*lift);view_rot.x=-0.20*lift
		"chop","mine":
			var hit := smoothstep(0.32,0.57,t)
			right=Vector3(0.34,0.58,-0.08).lerp(Vector3(0.18,-0.12,-0.59),hit)
			left=Vector3(-0.23,0.34,-0.24).lerp(Vector3(-0.08,-0.08,-0.47),hit)
			view_rot=Vector3(-0.65+hit*1.05,0.0,-0.26+hit*0.40)
			view_pos=Vector3(0,0.14-hit*0.23,hit*-0.16)
			torso=Vector3(hit*0.10,0.10-hit*0.18,0)
		"harvest":
			var pull := smoothstep(0.20,0.60,t)
			right=Vector3(0.15,-0.46,-0.51).lerp(Vector3(0.14,0.12,-0.32),pull)
			left=Vector3(-0.15,-0.46,-0.51).lerp(Vector3(-0.14,0.12,-0.32),pull)
			view_pos=Vector3(-0.06,-0.20+pull*0.23,-0.16+pull*0.1);view_rot.x=0.28-pull*0.34
			torso.x=(1-pull)*0.28
		"grab","pick":
			var reach:=smoothstep(.0,.32,t)*(1.0-smoothstep(.42,.86,t))
			var pull:=smoothstep(.42,.86,t)*(1.0-smoothstep(.9,1.0,t))
			right=Vector3(.18,.20 if kind=="pick" else -.05,-.35-reach*.24).lerp(Vector3(.14,.27,-.26),pull)
			left=Vector3(-0.28,-0.16,-0.08)
			view_pos=Vector3(-.09*reach-.04*pull,-.07*reach+.10*pull,-.23*reach+.03*pull);view_rot=Vector3(.16*pull,0,.12*reach-.14*pull)
		"door","brake":
			var reach:=sin(t*PI)
			right=Vector3(.18,-.05,-.35-reach*.24);left=Vector3(-.28,-.16,-.08)
			view_pos=Vector3(-.09*reach,-.07*reach,-.23*reach);view_rot.z=.12*reach
		"scoop","plant":
			var dig := sin(t*PI)
			right=Vector3(0.16,-0.14-dig*0.28,-0.43);left=Vector3(-0.18,-0.19,-0.33)
			view_pos=Vector3(-0.05,-0.16*dig,-0.09*dig);view_rot.x=0.30*dig;torso.x=0.20*dig
		"build","craft","install":
			var tap := sin(t*PI*4)
			right=Vector3(0.18,0.18+maxf(tap,0)*0.20,-0.50);left=Vector3(-0.18,0,-0.48)
			view_rot.x=-0.35*maxf(tap,0);view_pos=Vector3(-0.03,maxf(tap,0)*0.06,-0.09)
		"cast":
			var release := smoothstep(0.25,0.62,t)
			right=Vector3(0.32,0.48,0.09).lerp(Vector3(0.19,0.22,-0.56),release)
			left=Vector3(-0.18,0.07,-0.33)
			view_rot.x=-0.55+release*0.72;view_pos.y=0.08*(1-release)
		"reel":
			var crank := t*TAU*3.0
			right=Vector3(0.24,0.27,-0.42);left=Vector3(-0.08+cos(crank)*0.05,0.08+sin(crank)*0.05,-0.34)
			view_rot.x=lerpf(-.12,.60,smoothstep(.20,.85,t))+sin(crank)*.025;view_pos.y=.035
		"eat":
			var lift := smoothstep(.04,.30,t)*(1.0-smoothstep(.72,.96,t))
			var bite := sin(smoothstep(.32,.69,t)*PI*4.0)*.012*lift
			right=Vector3(.25,.15,-.35).lerp(Vector3(.08,.42,-.20),lift)
			right.y+=bite;left=Vector3(-.18,.12,-.30)
			view_pos=Vector3(-.22*lift,.27*lift+bite,.11*lift)
			view_rot=Vector3(.30*lift,0,-.10*lift)
			torso.x=-.035*lift
		"drink":
			var lift:=smoothstep(.04,.26,t)*(1.0-smoothstep(.84,.99,t))
			view_rot=Vector3(.15*lift,0,0)
			right=Vector3(.25,.15,-.35)
			left=Vector3(-.18,.12,-.30)
			if is_instance_valid(_mouth_rig) and _mouth_bone>=0:
				var head:=_mouth_rig.global_transform*_mouth_rig.get_bone_global_pose(_mouth_bone)
				var mouth:=player.to_local(head.origin)+Vector3(0,-.015,-.075)
				var grip_basis:=player.global_basis.inverse()*(player.get_node("Body") as Node3D).global_basis.orthonormalized()*Basis.from_euler(view_rot)
				var rim:=grip_basis*(_food_third.position+Basis.from_euler(Vector3(1.05*lift,0,0))*Vector3(0,.095,0))*.8
				var wrist_pose:=_mouth_rig.global_transform*_mouth_rig.get_bone_global_pose(_mouth_rig.find_bone("Wrist.R"))
				var palm_offset:=player.global_basis.inverse()*wrist_pose.basis*Vector3(0,.00085,0)
				right=right.lerp(mouth-rim-palm_offset,lift)
			if is_instance_valid(_view_tool):
				var centre: Vector3=player.get("camera").to_global(Vector3(-.04,-.12,-.17))
				var contact:=(_view_tool.get_parent() as Node3D).to_local(centre)-Basis.from_euler(view_rot)*_food_first.position
				view_pos=contact*lift
		"cook":
			var reach:=smoothstep(.04,.22,t)*(1.0-smoothstep(.80,.97,t))
			var angle:=t*TAU*2.5
			right=Vector3(.03,.30,-.36)+Vector3(cos(angle)*.04,0,sin(angle)*.035)*reach
			left=Vector3(-.12,.09,-.42);torso.x=.07*reach
			view_pos=Vector3(-.22+cos(angle)*.035,.12,sin(angle)*.025)*reach
			view_rot=Vector3(.08,.08*sin(angle),-.08*cos(angle))*reach
		"dig":
			var drive:=smoothstep(.20,.57,t);var lift:=smoothstep(.60,.84,t)
			right=Vector3(.25,.35,-.30).lerp(Vector3(.14,-.30,-.52),drive).lerp(Vector3(.23,.12,-.27),lift)
			left=Vector3(-.14,.07,-.39);torso.x=.22*drive*(1.0-lift)
			view_pos=Vector3(-.05,-.19*drive+.18*lift,-.15*drive);view_rot.x=-.8+drive*1.9-lift*.7
		"paddle":
			var dip:=smoothstep(.18,.43,t);var pull:=smoothstep(.43,.78,t)
			right=Vector3(.29,.29,-.52).lerp(Vector3(.40,-.28,-.57),dip).lerp(Vector3(.46,.03,.02),pull)
			left=Vector3(-.05,.20,-.43);torso=Vector3(.07*dip,.12*sin(t*PI),0)
			view_pos=Vector3(.10,-.10*dip,-.10+.24*pull);view_rot=Vector3(-1.8+.48*pull,0,.20*dip)
		"anchor":
			var lower:=smoothstep(.18,.65,t)
			if _anchor_raising:lower=1.0-lower
			right=Vector3(.24,.24,-.34).lerp(Vector3(.24,-.30,-.48),lower);left=Vector3(-.17,.13,-.40)
			view_pos=Vector3(0,-.25*lower,-.15*lower);view_rot.x=.24*lower;torso.x=.15*lower
		"water":
			right=Vector3(0.15,-0.15,-0.50);view_rot.z=-0.85*sin(t*PI);view_pos.z=-0.14
		"bandage":
			right=Vector3(-0.06,0,-0.27);left=Vector3(-0.20,0.12,-0.32)
			view_rot.z=sin(t*TAU*2)*0.22;view_pos.x=-0.16
		"strike","bow":
			var thrust:=smoothstep(.22,.57,t)*(1-smoothstep(.62,.93,t))
			right=Vector3(.28,.13,-.23-.44*thrust);left=Vector3(-.17,.16,-.42-.10*thrust)
			view_pos=Vector3(-.05*thrust,.025*thrust,-.38*thrust);view_rot.x=.08-.12*thrust
		"pump":
			var pump:=sin(t*TAU*7)*.5+.5
			right=Vector3(.08,.03+pump*.23,-.43);left=Vector3(-.10,.03+pump*.23,-.43)
			view_pos=Vector3(-.18,-.07+pump*.10,-.12);torso.x=.10*(1-pump)
		"hook":
			var recoil := sin(t*PI)
			right=Vector3(0.29,0.22,-0.36+recoil*0.08)
			left=Vector3(-0.25,0.12,-0.25)
			view_pos.z=recoil*0.09;view_rot.x=-recoil*0.1
		"fire":
			var reach := sin(t*PI)
			right=Vector3(0.12,-0.08,-0.28-reach*0.21);left=Vector3(-0.15,-0.07,-0.30)
			view_pos=Vector3(-0.04,-0.10*reach,-0.14*reach);view_rot.z=0.18*reach
	return {"right":right,"left":left,"weight":weight,"torso":torso*weight,"view_pos":view_pos*weight,"view_rot":view_rot*weight}

func _make_tool(action: String) -> Node3D:
	if action=="prepare_seed":
		var knife:=Node3D.new();knife.name="SalvagedKitchenKnife"
		ART.timber_box(knife,Vector3(0,0,-.09),Vector3(.024,.029,.14))
		var blade:=ART.box(knife,Vector3(0,0,-.22),Vector3(.007,.045,.15),MAT.make(MAT.Kind.METAL,Color(.43,.46,.44),.62,.6));blade.rotation.x=-.10
		return knife
	var item:=str(player.get("active_item"))
	if action=="strike":
		var spear:=Node3D.new();spear.name="HuntingSpear"
		var hand:=player.get("_hand_item") as Node3D
		for child in hand.get_children():
			if child is Node3D and not child.has_meta("first_person_hand") and not str(child.name).begins_with("HumanHand") and not child.is_queued_for_deletion():spear.add_child(child.duplicate())
		return spear
	if (action=="chop" and item=="Axe") or (action=="scoop" and item=="Shovel") or action in ["mine","dig","paddle","anchor"]:
		return preload("res://scripts/survival_tool_visual.gd").create(item)
	var root := Node3D.new();root.name="ActionTool"
	var wood := MAT.make(MAT.Kind.WOOD,Color(0.32,0.21,0.10),0.9)
	var stone := MAT.make(MAT.Kind.STONE,Color(0.25,0.28,0.27),0.95)
	if action=="pump":
		ART.cylinder(root,Vector3(0,.025,0),.035,.30,stone)
		ART.box(root,Vector3(0,.20,0),Vector3(.22,.025,.025),wood)
		ART.box(root,Vector3(0,-.14,0),Vector3(.18,.025,.10),wood)
		return root
	if action=="cook":
		var handle:=ART.cylinder(root,Vector3(-.05,-.10,-.06),.012,.28,wood);handle.rotation=Vector3(.32,0,-.40)
		if _spoon_mesh==null:
			_spoon_mesh=SphereMesh.new();_spoon_mesh.radius=.045;_spoon_mesh.height=.025;_spoon_mesh.radial_segments=12;_spoon_mesh.rings=6
		var spoon:=_spoon_mesh
		var scoop:=MeshInstance3D.new();scoop.mesh=spoon;scoop.material_override=wood;scoop.position=Vector3(-.11,-.24,-.10);scoop.scale.z=1.45;root.add_child(scoop)
		return root
	ART.cylinder(root,Vector3(0,0.15,0),0.023,0.52,wood)
	if action=="chop":
		var head := ART.box(root,Vector3(0.05,0.35,0),Vector3(0.20,0.13,0.055),stone)
		head.rotation.z=-0.22
	elif action=="scoop":
		ART.box(root,Vector3(0,0.35,0),Vector3(0.16,0.14,0.03),stone)
	else:
		ART.box(root,Vector3(0,0.35,0),Vector3(0.17,0.09,0.07),wood)
	var knot := MeshInstance3D.new();knot.mesh=preload("res://scripts/construction_visual.gd").rope_knot();knot.position.y=0.32
	root.add_child(knot)
	return root

func _exit_tree() -> void:
	if is_instance_valid(_panel):_panel.queue_free()
	if is_instance_valid(_held):_held.queue_free()
	_clear_tools()
