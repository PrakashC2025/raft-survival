extends "res://scripts/cargo_crate.gd"
signal contents_changed
var contents: Array = []
@export var capacity := 24
@export var loot_bag := false
func _ready() -> void:
	if not loot_bag:super._ready()
	else:_make_bag()
	contents.resize(capacity)
	for index in capacity:
		if not contents[index] is Dictionary:contents[index]={}
	add_to_group("storage_box")
	if not loot_bag:add_to_group("build_surface")
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
func interaction_caption() -> String:return "OPEN LOOT BAG" if loot_bag else "OPEN STORAGE"
func empty() -> bool:
	for entry in contents:
		if not entry.is_empty():return false
	return true
func save_survival_state() -> Dictionary:return {"version":1,"contents":contents.duplicate(true)}
func restore_survival_state(data: Dictionary) -> void:
	var saved: Variant=data.get("contents",[])
	if not saved is Array:return
	for index in capacity:
		contents[index]={}
		if index>=saved.size() or not saved[index] is Dictionary:continue
		var entry: Dictionary=saved[index]
		var item:=str(entry.get("item",""))
		var amount: Variant=entry.get("count",0)
		if item.is_empty() or item.length()>80 or not (amount is int or amount is float) or not is_finite(float(amount)):continue
		var count_value:=clampi(int(amount),0,Inventory.MAX_STACK)
		if count_value>0:contents[index]={"item":Inventory.canonical_item(item),"count":count_value}
	contents_changed.emit()
