extends Node
## Original action-specific key poses. Two-bone IK uses these after the gait;
## the first-person tool uses matching, smaller motions without camera shake.
const GRIP := preload("res://scripts/rope_hand_grip.gd")
const ART := preload("res://scripts/machine_visual.gd")
const MAT := preload("res://scripts/object_materials.gd")
var kind := ""
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
const LABELS := {"cast":"CASTING LINE", "reel":"REELING IN", "chop":"CHOPPING TIMBER",
	"harvest":"PULLING ROOTS", "pick":"PICKING FRUIT", "grab":"COLLECTED",
	"scoop":"GATHERING EARTH", "plant":"PLANTING SEED", "water":"WATERING SOIL",
	"build":"ASSEMBLING", "craft":"CRAFTED", "eat":"EATING", "drink":"DRINKING",
	"bandage":"BANDAGING", "strike":"SPEAR THRUST", "bow":"RELEASING ARROW", "door":"OPENING", "install":"FITTING EQUIPMENT",
	"hook":"LAUNCHING HOOK", "fire":"TENDING FIRE", "fill":"FILLING CAN",
	"battery":"REPLACING BATTERY", "radio":"RADIO TRANSMISSION", "look":"RAISING BINOCULARS",
	"solar":"RAISING SOLAR PANEL", "switch":"POWER SWITCH"}

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

func play(action: String, seconds: float, at: Vector3) -> void:
	if not LABELS.has(action):return
	_construction_idle = false
	kind=action;duration=maxf(seconds,0.15);elapsed=0;target=at
	_label.text=LABELS[action];_bar.value=0;_panel.show()
	_clear_tools()
	if action in ["chop","build","craft","scoop"]:
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
	if action in ["chop","build","craft","scoop","grab","pick","harvest","plant","door"]:
		_view_tool=_make_tool(action) if action in ["chop","build","craft","scoop"] else Node3D.new()
		var hand := preload("res://models/human_hand.glb").instantiate() as Node3D
		MAT.apply_model(hand,MAT.Kind.SKIN);_view_tool.add_child(hand)
		if action in ["harvest","build","craft","plant"]:
			var left := hand.duplicate() as Node3D
			left.scale.x=-1.0;left.position.x=-0.36;left.position.z=-0.08
			_view_tool.add_child(left)
		if action == "build":
			var timber := ART.box(_view_tool,Vector3(-0.36,-0.02,-0.10),Vector3(0.12,0.07,0.44),MAT.make(MAT.Kind.WOOD,Color(0.47,0.29,0.12),0.9))
			timber.name="ConstructionTimber"
		player.get_node("CamPivot/SpringArm3D/Camera3D/HandPivot/Fist").add_child(_view_tool)
		_view_tool.scale=Vector3.ONE*0.85

func stop() -> void:
	_construction_idle = false
	kind="";_panel.hide();_clear_tools()
	if is_instance_valid(player.get("_hand_item")):player.get("_hand_item").visible=true
	if is_instance_valid(player.get("_third_person_launcher")):player.get("_third_person_launcher").visible=int(player.get("cam_mode"))==1

func _clear_tools() -> void:
	for tool in [_tool,_view_tool,_left_tool]:
		if is_instance_valid(tool): tool.hide();tool.queue_free()
	_tool=null;_view_tool=null;_left_tool=null

func _process(delta: float) -> void:
	var construction: bool = bool(player.get("build_mode")) or is_instance_valid(player.get("_editing"))
	if (construction and kind not in ["","build"]) or (not construction and kind=="build"):stop()
	if _construction_idle and not construction: stop()
	if not kind.is_empty() and not _construction_idle:
		elapsed+=delta
		_bar.value=clampf(elapsed/duration,0,1)
		if elapsed>=duration:stop()
	if construction and kind.is_empty():
		play("build",0.75,Vector3.ZERO)
		_construction_idle = true
		elapsed = 0.35
		_panel.hide()
	_sync_held()
	var first := int(player.get("cam_mode"))==0
	if is_instance_valid(_tool):_tool.visible=not first
	if is_instance_valid(_left_tool):_left_tool.visible=not first
	if is_instance_valid(_view_tool):
		_view_tool.visible=first
		var pose := sample_pose()
		_view_tool.position=pose.view_pos;_view_tool.rotation=pose.view_rot
	var hand := player.get("_hand_item") as Node3D
	if is_instance_valid(hand):hand.visible=not is_instance_valid(_view_tool)
	if is_instance_valid(_held):_held.visible=not first and not is_instance_valid(_tool) and not construction
	if is_instance_valid(player.get("_third_person_launcher")) and kind in ["chop","build","craft","scoop","grab","pick","harvest","plant"]:
		player.get("_third_person_launcher").visible=false

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
	match kind:
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
		"chop":
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
		"grab","pick","door":
			var reach := sin(t*PI)
			right=Vector3(0.18,0.20 if kind=="pick" else -0.05,-0.35-reach*0.24)
			left=Vector3(-0.28,-0.16,-0.08)
			view_pos=Vector3(-0.09*reach,-0.07*reach,-0.23*reach);view_rot.z=0.12*reach
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
			view_rot.x=-0.12+sin(crank)*0.025;view_pos.y=0.035
		"eat","drink":
			var lift := sin(t*PI)
			right=Vector3(0.20,0.1,-0.35).lerp(Vector3(0.11,0.65,-0.17),lift)
			view_pos=Vector3(-0.14*lift,0.20*lift,0.14*lift);view_rot.x=-0.7*lift
		"water":
			right=Vector3(0.15,-0.15,-0.50);view_rot.z=-0.85*sin(t*PI);view_pos.z=-0.14
		"bandage":
			right=Vector3(-0.06,0,-0.27);left=Vector3(-0.20,0.12,-0.32)
			view_rot.z=sin(t*TAU*2)*0.22;view_pos.x=-0.16
		"strike","bow":
			right=Vector3(0.22,0.16,-0.3-sin(t*PI)*0.3);left=Vector3(-0.23,0.23,-0.45)
			view_pos.z=-sin(t*PI)*0.25
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
	var root := Node3D.new();root.name="ActionTool"
	var wood := MAT.make(MAT.Kind.WOOD,Color(0.32,0.21,0.10),0.9)
	var stone := MAT.make(MAT.Kind.STONE,Color(0.25,0.28,0.27),0.95)
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
