extends Node3D
const RULES := preload("res://scripts/food_rules.gd")
var job: Dictionary = {}
var _label: Label3D
var _can: Node3D
var _drops: Array[MeshInstance3D] = []
var _visual_tick := 0.0
var _insert := 0.0
var _insert_from := Vector3.ZERO
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
	if job.kind=="cook":can_run=station.get("burning")==true and float(station.get("fuel"))>0.0
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
	if active:_label.text=("FILTERING" if job.kind=="filter" else str(job.item).to_upper())+" · %ds"%ceili(float(job.remaining))
	for index in _drops.size():
		var drop:=_drops[index];drop.visible=active and job.kind=="filter"
		if drop.visible:drop.position=Vector3(.18,.45-fmod(Time.get_ticks_msec()/1000.0*.6+index*.12,.48),0)
func save_job() -> Dictionary:return job.duplicate(true)
func begin_insertion(from: Vector3) -> void:
	_insert_from=to_local(from);_insert=.65;_can.position=_insert_from
func restore_job(data: Dictionary) -> void:
	var kind:=str(data.get("kind",""));var item:=str(data.get("item",""))
	var seconds: Variant=data.get("remaining",0)
	if kind not in ["cook","filter"] or (kind=="cook" and not RULES.RECIPES.has(item)) or (kind=="filter" and item!="Clean Water Can"):return
	if not (seconds is int or seconds is float) or not is_finite(float(seconds)):return
	var duration:=5.0 if kind=="filter" else float(RULES.RECIPES[item].seconds)
	job={"kind":kind,"item":item,"remaining":clampf(float(seconds),0,duration),"duration":duration}
	_sync_visual()
