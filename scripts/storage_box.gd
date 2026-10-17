extends "res://scripts/cargo_crate.gd"
signal contents_changed

var contents: Array = []
@export var capacity := 20
@export var loot_bag := false
var locked := false
var _lid_pivot: Node3D
var _key: Node3D
var _motion: Tween

func _ready() -> void:
	if loot_bag:
		_make_bag()
	else:
		_make_lockbox()
	contents.resize(capacity)
	for index in capacity:
		if not contents[index] is Dictionary: contents[index]={}
	add_to_group("storage_box")
	if not loot_bag: add_to_group("build_surface")

func _make_lockbox() -> void:
	var wood := preload("res://scripts/object_materials.gd").make(0,Color(.32,.18,.095))
	var inner := preload("res://scripts/object_materials.gd").make(0,Color(.095,.055,.03))
	var iron := preload("res://scripts/object_materials.gd").make(1,Color(.25,.27,.25))
	_add_box(self,"Bottom",Vector3(1.35,.12,.82),Vector3(0,-.25,0),wood)
	_add_box(self,"Front",Vector3(1.35,.48,.10),Vector3(0,.04,-.36),wood)
	_add_box(self,"Back",Vector3(1.35,.48,.10),Vector3(0,.04,.36),wood)
	_add_box(self,"Left",Vector3(.10,.48,.62),Vector3(-.625,.04,0),wood)
	_add_box(self,"Right",Vector3(.10,.48,.62),Vector3(.625,.04,0),wood)
	_add_box(self,"DarkInterior",Vector3(1.15,.025,.57),Vector3(0,-.17,0),inner)
	# A separate pivot lets the lid swing clear of the square 20-slot inventory.
	_lid_pivot=Node3D.new();_lid_pivot.name="HingedLid";_lid_pivot.position=Vector3(0,.29,.36);add_child(_lid_pivot)
	_add_box(_lid_pivot,"LidBoard",Vector3(1.48,.12,.92),Vector3(0,0,-.39),wood)
	for x in [-.54,.54]:
		_add_box(_lid_pivot,"Hinge",Vector3(.10,.16,.08),Vector3(x,-.02,.02),iron)
		_add_box(self,"WeatheredIronBand",Vector3(.075,.51,.84),Vector3(x*.83,.04,0),iron)
	# Front has a visible iron hasp, keyhole and a small built-in turning key.
	_add_box(self,"LockPlate",Vector3(.20,.24,.035),Vector3(0,.02,-.424),iron)
	_add_box(self,"Keyhole",Vector3(.045,.11,.012),Vector3(0,.02,-.448),inner)
	_key=Node3D.new();_key.name="TurningKey";_key.position=Vector3(0,.09,-.48);add_child(_key)
	_add_box(_key,"KeyShaft",Vector3(.025,.14,.025),Vector3(0,0,0),iron)
	_add_box(_key,"KeyBow",Vector3(.11,.065,.03),Vector3(0,.08,0),iron)
	for x in [-.54,.54]:
		for y in [-.14,.22]:
			_add_box(self,"OldScrew",Vector3(.045,.045,.025),Vector3(x,y,-.424),iron)
	var collision:=get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision!=null and collision.shape is BoxShape3D:
		var shape:=collision.shape.duplicate() as BoxShape3D;shape.size=Vector3(1.58,.78,.98);collision.shape=shape

func _add_box(parent: Node3D,label: String,size: Vector3,at: Vector3,material: Material) -> MeshInstance3D:
	var box:=BoxMesh.new();box.size=size
	var mesh:=MeshInstance3D.new();mesh.name=label;mesh.mesh=box;mesh.material_override=material;mesh.position=at
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;parent.add_child(mesh)
	return mesh

func _make_bag() -> void:
	var visual:=MeshInstance3D.new()
	var bag:=CapsuleMesh.new();bag.radius=0.26;bag.height=0.64;bag.radial_segments=12;bag.rings=4
	visual.mesh=bag;visual.rotation.z=PI/2;visual.scale=Vector3(1,1,0.65)
	visual.material_override=preload("res://scripts/object_materials.gd").make(2,Color(0.28,0.32,0.19))
	add_child(visual)
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.7,.5,.5);collider.shape=shape;add_child(collider)
	collision_layer=2;collision_mask=0

func interact_survival(actor: Node) -> void:
	actor.get_node("SurvivalServices").call("open_storage",self)
func interaction_caption() -> String: return "OPEN LOOT BAG" if loot_bag else ("UNLOCK STORAGE" if locked else "OPEN STORAGE")
func empty() -> bool:
	for entry in contents:
		if not entry.is_empty():return false
	return true

func animate_open() -> void: _animate_lid(0.0 if locked else -1.12,.38)
func animate_close() -> void: _animate_lid(0.0,.32)
func animate_unlock() -> void:
	locked=false
	if _motion!=null and _motion.is_valid():_motion.kill()
	if _key!=null:
		_motion=create_tween();_motion.tween_property(_key,"rotation:z",PI*.42,.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_motion.tween_property(_key,"rotation:z",0.0,.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_motion.tween_callback(func(): _animate_lid(-1.12,.38))
	else: locked=false

func set_locked(value: bool) -> void:
	locked=value
	if value:animate_close()
	else:animate_open()

func _animate_lid(target: float,duration: float) -> void:
	if _lid_pivot==null:return
	if _motion!=null and _motion.is_valid():_motion.kill()
	_motion=create_tween();_motion.tween_property(_lid_pivot,"rotation:x",target,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func save_survival_state() -> Dictionary:return {"version":2,"contents":contents.duplicate(true),"locked":locked}
func restore_survival_state(data: Dictionary) -> void:
	var saved: Variant=data.get("contents",[])
	if not saved is Array:return
	# Preserve legacy 24-slot boxes and 30-slot death bags without truncation.
	capacity=maxi(capacity,mini(saved.size(),30 if loot_bag else 24))
	contents.resize(capacity)
	for index in capacity:
		contents[index]={}
		if index>=saved.size() or not saved[index] is Dictionary:continue
		var entry: Dictionary=saved[index]
		var item:=str(entry.get("item",""));var amount: Variant=entry.get("count",0)
		if item.is_empty() or item.length()>80 or not (amount is int or amount is float) or not is_finite(float(amount)):continue
		var count_value:=clampi(int(amount),0,Inventory.MAX_STACK)
		if count_value>0:contents[index]={"item":Inventory.canonical_item(item),"count":count_value}
	locked=bool(data.get("locked",false))
	contents_changed.emit()
