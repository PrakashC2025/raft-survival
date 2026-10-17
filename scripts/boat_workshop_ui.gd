extends CanvasLayer
## Original boatwright screen: inspect the boat, check supplies, assemble, launch.
const UI:=preload("res://scripts/ocean_ui.gd")
const GOLD:=Color("dfbd78")
const FADED:=Color("91aebb")
class ItemPicture extends Control:
	var item:=""
	func _draw() -> void:
		preload("res://scripts/ui_icons.gd").item_icon(self,item,size*.5,20)
var service: Node
var panel: PanelContainer
var status: Label
var build_button: Button
var launch_button: Button
var close_button: Button
var progress: ProgressBar
var stage: Label
var material_rows: Dictionary={}
var kit_label: Label
var steps: Array[Label]=[]
var preview: SubViewport
var model: Node3D
var _tick:=0.0

func label(text_value: String,font_size: int=18,color: Color=UI.TEXT) -> Label:
	var node:=Label.new();node.text=text_value;node.add_theme_font_size_override("font_size",font_size);node.add_theme_color_override("font_color",color)
	return node

func card(parent: Node,color: Color=Color("102b38")) -> PanelContainer:
	var node:=PanelContainer.new();node.add_theme_stylebox_override("panel",UI.box(color,Color("294752"),12));parent.add_child(node);return node

func _ready() -> void:
	layer=14
	var shade:=ColorRect.new();shade.color=Color(.01,.025,.035,.90);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	panel=PanelContainer.new();panel.theme=UI.theme();panel.add_theme_stylebox_override("panel",UI.box(Color("091e2a"),Color("789194"),20));add_child(panel)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);panel.add_child(column)
	var header:=HBoxContainer.new();column.add_child(header)
	var titles:=VBoxContainer.new();titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(titles)
	titles.add_child(label("OCEAN SURVIVAL  /  BOAT WORKSHOP",14,GOLD));titles.add_child(label("Build your way beyond the raft",28))
	var badge:=label("ROWBOAT  /  01",15,FADED);header.add_child(badge)
	var timeline:=HBoxContainer.new();timeline.add_theme_constant_override("separation",12);column.add_child(timeline)
	for caption in ["01   PLAN","02   ASSEMBLE","03   LAUNCH"]:
		var step:=label(caption,16);step.size_flags_horizontal=Control.SIZE_EXPAND_FILL;step.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var step_card:=card(timeline);var step_style:=UI.box(Color("102b38"),Color("294752"),8);step_style.set_content_margin_all(8);step_card.add_theme_stylebox_override("panel",step_style);step_card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;step_card.add_child(step);steps.append(step)
	var body:=HBoxContainer.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",20);column.add_child(body)
	var left:=VBoxContainer.new();left.custom_minimum_size.x=490;left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(left)
	var preview_card:=card(left,Color("102f3d"));preview_card.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var preview_column:=VBoxContainer.new();preview_card.add_child(preview_column)
	preview_column.add_child(label("WOODEN ROWBOAT",22,GOLD))
	var host:=SubViewportContainer.new();host.stretch=true;host.custom_minimum_size=Vector2(450,210);host.size_flags_vertical=Control.SIZE_EXPAND_FILL;host.mouse_filter=Control.MOUSE_FILTER_IGNORE;preview_column.add_child(host)
	preview=SubViewport.new();preview.size=Vector2i(450,240);preview.own_world_3d=true;preview.transparent_bg=true;preview.render_target_update_mode=SubViewport.UPDATE_DISABLED;host.add_child(preview)
	model=preload("res://scripts/rowboat_visual.gd").create();preview.add_child(model);model.rotation.y=-.75
	var camera:=Camera3D.new();preview.add_child(camera);camera.position=Vector3(3.8,3.5,5);camera.look_at(Vector3(0,.15,0));camera.fov=30;camera.current=true
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("102f3d")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color(.75,.86,1);environment.environment.ambient_light_energy=.8;preview.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.light_color=Color(1,.87,.68);sun.light_energy=1.8;preview.add_child(sun)
	var turn:=HBoxContainer.new();preview_column.add_child(turn)
	for direction in [-1,1]:
		var button:=Button.new();button.text="TURN LEFT" if direction<0 else "TURN RIGHT";button.custom_minimum_size=Vector2(0,44);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;turn.add_child(button)
		button.pressed.connect(func():model.rotation.y+=float(direction)*PI/4;preview.render_target_update_mode=SubViewport.UPDATE_ONCE)
	left.add_child(label("2 oars   /   1 seat   /   4.6 m/s",17,FADED))
	var right:=VBoxContainer.new();right.custom_minimum_size.x=440;right.add_theme_constant_override("separation",6);body.add_child(right)
	right.add_child(label("MATERIALS  /  OWNED : REQUIRED",18,GOLD))
	for item in ["Wood","Rope","Screw"]:
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);var row_card:=card(right);var row_style:=UI.box(Color("102b38"),Color("294752"),8);row_style.set_content_margin_all(7);row_card.add_theme_stylebox_override("panel",row_style);row_card.add_child(row)
		var picture:=ItemPicture.new();picture.item=item;picture.custom_minimum_size=Vector2(40,28);picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(picture)
		var name_label:=label(item,18);name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(name_label)
		var count:=label("",18);row.add_child(count);material_rows[item]=count
	kit_label=label("",15,FADED);right.add_child(kit_label)
	stage=label("READY TO ASSEMBLE",17,GOLD);right.add_child(stage)
	progress=ProgressBar.new();progress.custom_minimum_size.y=9;progress.max_value=1;progress.show_percentage=false;right.add_child(progress)
	status=label("",16,FADED);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size=Vector2(425,44);right.add_child(status)
	build_button=Button.new();build_button.name="BuildRowboat";build_button.custom_minimum_size.y=54;right.add_child(build_button);build_button.pressed.connect(func():service.start_build(service.workshop))
	launch_button=Button.new();launch_button.name="LaunchRowboat";launch_button.custom_minimum_size.y=54;right.add_child(launch_button)
	launch_button.pressed.connect(func():
		if is_instance_valid(service.boat):
			service.close();service.boat.board(service.player)
		else:service.launch())
	var footer:=HBoxContainer.new();column.add_child(footer)
	var tip:=label("Steer with the joystick or arrow keys. MAP sets a course.\nTake food and clean water for the trip.",14,FADED);tip.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(tip)
	close_button=Button.new();close_button.text="CLOSE";close_button.custom_minimum_size=Vector2(190,48);footer.add_child(close_button);close_button.pressed.connect(func():service.close())
	get_viewport().size_changed.connect(fit);fit();hide()

func fit() -> void:
	if panel==null:return
	var view:=get_viewport().get_visible_rect().size
	var factor:=minf((view.x-32)/1120.0,(view.y-32)/650.0)
	panel.size=Vector2(1120,650);panel.scale=Vector2.ONE*factor;panel.position=(view-panel.size*factor)*.5

func refresh() -> void:
	var kit:=Inventory.has("Rowboat Kit",1)
	var cost: Dictionary=Inventory.ITEM_RECIPES["Rowboat Kit"]
	var complete: bool=service.ready_to_launch or is_instance_valid(service.boat)
	for item in material_rows:
		var count: Label=material_rows[item];var owned:=Inventory.total(item);var needed:=int(cost[item])
		count.text="%d / %d"%[owned,needed];count.modulate=UI.AQUA if owned>=needed or kit or complete else Color("f69479")
	kit_label.text="ROWBOAT KIT AVAILABLE · replaces all materials" if kit else "Or assemble using 1 crafted Rowboat Kit."
	progress.value=clampf(service.elapsed/service.DURATION,0,1) if service.building else (1.0 if complete else 0.0)
	var active_step:=2 if complete else (1 if service.building else 0)
	for index in steps.size():steps[index].modulate=GOLD if index==active_step else (UI.AQUA if index<active_step else FADED)
	stage.text="ASSEMBLING · %d%%"%roundi(progress.value*100) if service.building else ("READY FOR THE WATER" if complete else "PLAN YOUR NEXT VOYAGE")
	build_button.visible=not complete;build_button.disabled=service.building or not Inventory.can_exchange({"Rowboat Kit":1} if kit else cost,{})
	build_button.text="ASSEMBLING..." if service.building else ("ASSEMBLE USING KIT · 5.5 s" if kit else "BUILD ROWBOAT · 5.5 s")
	launch_button.visible=complete;launch_button.disabled=not complete;launch_button.text="BOARD ROWBOAT" if is_instance_valid(service.boat) else "LAUNCH BESIDE RAFT"
	close_button.text="CANCEL BUILD" if service.building else "CLOSE"
	if service.building:
		var part_index := mini(3,floori(progress.value*4.0))
		status.text="%d / 4 · %s\n%.1f s left · Cancel keeps your materials."%[part_index+1,preload("res://scripts/rowboat_visual.gd").ASSEMBLY_TASKS[part_index],maxf(0.0,service.DURATION-service.elapsed)]
	elif is_instance_valid(service.boat):
		var distance_value: float=service.player.global_position.distance_to(service.boat.global_position)
		status.text="Your boat is afloat · %d m away.\nApproach it to board, or locate it on MAP."%roundi(distance_value)
		launch_button.disabled=distance_value>4.5
	elif complete:status.text="Assembly complete. Launch into clear water beside your raft."
	elif build_button.disabled:status.text="Gather the missing materials shown in red.\nScrews are crafted from Metal in CRAFT."
	else:status.text="Supplies ready. Build here, then launch.\nMaterials are used only when assembly finishes."
	if service.building:
		preload("res://scripts/rowboat_visual.gd").assemble(model,progress.value)
	else:
		preload("res://scripts/rowboat_visual.gd").assemble(model,1.0)

func _process(delta: float) -> void:
	var should_render: bool=visible and service.menu_open
	preview.render_target_update_mode=SubViewport.UPDATE_ALWAYS if should_render else SubViewport.UPDATE_DISABLED
	if not should_render:return
	_tick+=delta
	if _tick>=.1:_tick=0;refresh()
