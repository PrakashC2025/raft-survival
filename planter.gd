extends StaticBody3D
class_name Planter

## PlanterPot / PlanterBox / TreePot — one script, three .tscn variants.
## The CollisionShape3D and BuildSockets/Socket_Base live in each .tscn
## (like foundation.tscn / wall.tscn) so the existing build system's
## socket + overlap checks work unmodified. This script only builds the
## decorative mesh + soil + the slot the plant grows in.
##
## IMPORTANT: keep `box_size` below equal to the CollisionShape3D's
## BoxShape3D size set in the .tscn file — they are not auto-synced.

enum PlanterCategory { POT, BOX, TREE_POT }

@export var planter_category: PlanterCategory = PlanterCategory.POT
@export var box_size: Vector3 = Vector3(0.5, 0.35, 0.5)
@export var wood_color: Color = Color(0.55, 0.38, 0.2)
@export var soil_color: Color = Color(0.32, 0.22, 0.14)

var planted_id: String = ""
var _plant: PlantInstance = null
var _slot: Node3D = null


func _ready() -> void:
	add_to_group("build_surface")
	add_to_group("planter")
	_build_visual()


func _build_visual() -> void:
	var mesh_inst := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mesh_inst.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = wood_color
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	var soil := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(box_size.x * 0.82, box_size.y * 0.2, box_size.z * 0.82)
	soil.mesh = sm
	soil.position = Vector3(0, box_size.y * 0.4, 0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = soil_color
	soil.material_override = smat
	add_child(soil)

	_slot = Node3D.new()
	_slot.name = "PlantSlot"
	_slot.position = Vector3(0, box_size.y * 0.5, 0)
	add_child(_slot)


func category_name() -> String:
	match planter_category:
		PlanterCategory.POT:
			return "pot"
		PlanterCategory.BOX:
			return "box"
		_:
			return "tree_pot"


## Called by the player when using a matching seed item on this planter.
func plant_seed(id: String) -> bool:
	if _plant != null and is_instance_valid(_plant):
		return false
	var def: Dictionary = PlantDB.get_def(id)
	if def.is_empty():
		return false
	var cats: Array = def.get("planter_categories", [])
	if not cats.has(category_name()):
		return false
	var p := PlantInstance.new()
	p.plant_id = id
	_slot.add_child(p)
	_plant = p
	planted_id = id
	return true


func has_plant() -> bool:
	return _plant != null and is_instance_valid(_plant)


## Called by PlantInstance once a root crop is dug up or a tree is chopped
## down — the slot becomes free again.
func clear_plant() -> void:
	_plant = null
	planted_id = ""
