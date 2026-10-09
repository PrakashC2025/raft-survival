extends Node3D
const RULES := preload("res://scripts/food_rules.gd")
var job: Dictionary = {}
var _label: Label3D
var _can: Node3D
var _drops: Array[MeshInstance3D] = []
var _visual_tick := 0.0
var _insert := 0.0
var _insert_from := Vector3.ZERO
var _pan: Node3D
var _meal: Node3D
var _bubbles: Array[MeshInstance3D]=[]
var _food_material: StandardMaterial3D
var _sizzle: AudioStreamPlayer3D
var _cooking_active := false
var _steam: Node3D
var _meal_item := ""
var _slice_material: ShaderMaterial
func _ready() -> void:
	_label=Label3D.new();_label.position.y=1.1;_label.font_size=24;_label.pixel_size=.003;_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;_label.visibility_range_end=8;add_child(_label)
	_can=preload("res://scripts/survival_item_visual.gd").create("Can")
	_can.position=Vector3(.25,.2,0);_can.rotation.z=-0.35;add_child(_can)
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.25,.65,.9);material.roughness=.25
	var mesh:=SphereMesh.new();mesh.radius=.014;mesh.height=.04;mesh.radial_segments=6;mesh.rings=3
	for unused in 4:
		var drop:=MeshInstance3D.new();drop.mesh=mesh;drop.material_override=material;drop.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(drop);_drops.append(drop)
	_sync_visual()
func _process(delta: float) -> void:
	advance(delta)
func advance(delta: float) -> void:
	if job.is_empty():return
	if _insert>0:
		_insert=maxf(0.0,_insert-delta)
		_can.position=_insert_from.lerp(Vector3(.25,.2,0),smoothstep(0,1,1.0-_insert/.65))
	var station:=get_parent()
	var can_run:=true
	if job.kind in ["cook","boil"]:can_run=station.get("burning")==true and float(station.get("fuel"))>0.0
	if can_run:job.remaining=maxf(0.0,float(job.remaining)-delta)
	_visual_tick+=delta
	if _visual_tick>=0.1:_visual_tick=0;_sync_visual()
	if float(job.remaining)<=0.0:
		var actor:=get_tree().get_first_node_in_group("player")
		if actor!=null:actor.get_node("SurvivalServices").call("finish_station_job",self)
func _sync_visual() -> void:
	var active:=not job.is_empty()
	_label.visible=active
	_can.visible=active and job.kind=="filter"
	if active:_label.text=("FILTERING" if job.kind=="filter" else ("BOILING WATER" if job.kind=="boil" else str(job.item).to_upper()))+" · %ds"%ceili(float(job.remaining))
	for index in _drops.size():
		var drop:=_drops[index];drop.visible=active and job.kind=="filter"
		if drop.visible:drop.position=Vector3(.18,.45-fmod(Time.get_ticks_msec()/1000.0*.6+index*.12,.48),0)
	_sync_cooking(active and job.kind in ["cook","boil"])

func _make_cooking_visual() -> void:
	_pan=preload("res://scripts/survival_item_visual.gd").create_pan();_pan.position.y=.55;add_child(_pan)
	var existing:=get_parent().get_node_or_null("CookingPan") as Node3D
	if existing!=null:_pan.position=existing.position;_pan.hide()
	_meal=Node3D.new();_meal.name="SimmeringFood";_meal.position=_pan.position;add_child(_meal)
	_food_material=StandardMaterial3D.new();_food_material.roughness=.35
	_steam=Node3D.new();_steam.name="PotSteam";_steam.position=_pan.position+Vector3.UP*.24;add_child(_steam)
	var steam_mesh:=QuadMesh.new();steam_mesh.size=Vector2(.18,.40)
	var steam_skin:=ShaderMaterial.new();steam_skin.shader=preload("res://shaders/cooking_steam.gdshader")
	for index in 3:
		var ribbon:=MeshInstance3D.new();ribbon.mesh=steam_mesh;ribbon.material_override=steam_skin;ribbon.rotation.y=index*TAU/3;ribbon.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;_steam.add_child(ribbon)
	var bubble_mesh:=SphereMesh.new();bubble_mesh.radius=.018;bubble_mesh.height=.023;bubble_mesh.radial_segments=6;bubble_mesh.rings=3
	for index in 5:
		var bubble:=MeshInstance3D.new();bubble.mesh=bubble_mesh;bubble.material_override=_food_material;bubble.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;_meal.add_child(bubble);_bubbles.append(bubble)
	_sizzle=AudioStreamPlayer3D.new();_sizzle.name="CookingSizzle";_sizzle.max_distance=12;_sizzle.unit_size=2;_sizzle.volume_db=-20
	var stream:=preload("res://audio/action_sizzle.wav").duplicate() as AudioStreamWAV
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=66150;_sizzle.stream=stream;add_child(_sizzle)

func _sync_cooking(cooking: bool) -> void:
	if _pan==null:
		if not cooking:return
		_make_cooking_visual()
	if cooking and _meal_item!=str(job.item):
		var old:=_meal.get_node_or_null("SlicedMeal")
		if old!=null:_meal.remove_child(old);old.queue_free()
		var contents: Node3D=preload("res://scripts/survival_item_visual.gd").create("Ocean Water Tumbler") if job.kind=="boil" else preload("res://scripts/meal_visual.gd").create(str(job.item),.247,0,true)
		contents.name="SlicedMeal";contents.position.y=.05 if job.kind=="boil" else .026;_meal.add_child(contents);_meal_item=str(job.item)
		var slices:=contents.get_node_or_null("SlicedIngredients") as MeshInstance3D
		_slice_material=slices.material_override if slices!=null else null
		_food_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if job.kind=="boil" else BaseMaterial3D.TRANSPARENCY_DISABLED
	_pan.visible=cooking and get_parent().get_node_or_null("CookingPan")==null
	_meal.visible=cooking
	_cooking_active=cooking and get_parent().get("burning")==true and float(get_parent().get("fuel"))>0
	var camera:=get_viewport().get_camera_3d()
	var near:=camera!=null and camera.global_position.distance_squared_to(global_position)<144
	_steam.visible=_cooking_active and near
	if _cooking_active and near:
		if not _sizzle.playing:_sizzle.play()
	elif _sizzle.playing:_sizzle.stop()
	if not cooking:return
	var progress:=1.0-float(job.remaining)/float(job.duration)
	_food_material.albedo_color=Color(.56,.72,.78,.40) if job.kind=="boil" else Color(.68,.39,.16).lerp(Color(.34,.16,.055),progress)
	if _slice_material!=null:_slice_material.set_shader_parameter("cooked",progress)
	if not _cooking_active:_label.text="FIRE OUT · "+str(job.item).to_upper()
	for index in _bubbles.size():
		var bubble:=_bubbles[index];bubble.visible=_cooking_active and near
		if not bubble.visible:continue
		var phase:=fposmod((float(job.duration)-float(job.remaining))*1.3+index*.21,1.0)
		var angle:=index*2.4
		var spread:=.045 if job.kind=="boil" else .13
		bubble.position=Vector3(cos(angle)*spread,(.117 if job.kind=="boil" else .033)+sin(phase*PI)*.012,sin(angle)*spread)
		bubble.scale=Vector3.ONE*(.3+sin(phase*PI)*.7)
func save_job() -> Dictionary:return job.duplicate(true)
func begin_insertion(from: Vector3) -> void:
	_insert_from=to_local(from);_insert=.65;_can.position=_insert_from
func restore_job(data: Dictionary) -> void:
	var kind:=str(data.get("kind",""));var item:=str(data.get("item",""))
	var seconds: Variant=data.get("remaining",0)
	if kind not in ["cook","filter","boil"] or (kind=="cook" and not RULES.RECIPES.has(item)) or (kind=="filter" and item!="Clean Water Can") or (kind=="boil" and item!="Boiled Water Tumbler"):return
	if not (seconds is int or seconds is float) or not is_finite(float(seconds)):return
	var duration:=5.0 if kind=="filter" else (8.0 if kind=="boil" else float(RULES.RECIPES[item].seconds))
	job={"kind":kind,"item":item,"remaining":clampf(float(seconds),0,duration),"duration":duration}
	_sync_visual()
