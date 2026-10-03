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

const TREE_POT_SCENE: PackedScene = preload("res://models/kenney_pot_large.glb")
const SAND_SURFACE_SHADER: Shader = preload("res://shaders/sand_surface.gdshader")

var planted_id: String = ""
var sand_applied := false
var _plant: PlantInstance = null
var _slot: Node3D = null
var _sand_layer: MeshInstance3D = null


func _ready() -> void:
	add_to_group("build_surface")
	add_to_group("planter")
	_build_visual()


func _build_visual() -> void:
	if planter_category == PlanterCategory.TREE_POT:
		_build_tree_pot_visual()
	else:
		_build_box_visual()

	var soil := MeshInstance3D.new()
	if planter_category == PlanterCategory.TREE_POT:
		var cylinder_soil := CylinderMesh.new()
		cylinder_soil.top_radius = box_size.x * 0.34
		cylinder_soil.bottom_radius = cylinder_soil.top_radius
		cylinder_soil.height = box_size.y * 0.06
		cylinder_soil.radial_segments = 16
		soil.mesh = cylinder_soil
		soil.position = Vector3(0.0, box_size.y * 0.30, 0.0)
	else:
		var box_soil := BoxMesh.new()
		box_soil.size = Vector3(box_size.x * 0.82, box_size.y * 0.2, box_size.z * 0.82)
		soil.mesh = box_soil
		soil.position = Vector3(0.0, box_size.y * 0.4, 0.0)
	var soil_material := StandardMaterial3D.new()
	soil_material.albedo_color = soil_color
	soil_material.roughness = 0.96
	soil.material_override = soil_material
	add_child(soil)

	_slot = Node3D.new()
	_slot.name = "PlantSlot"
	var soil_top := box_size.y * (0.33 if planter_category == PlanterCategory.TREE_POT else 0.5)
	_slot.position = Vector3(0.0, soil_top, 0.0)
	add_child(_slot)


func _build_box_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = wood_color
	material.roughness = 0.88
	mesh_instance.material_override = material
	add_child(mesh_instance)


func _build_tree_pot_visual() -> void:
	var pot := TREE_POT_SCENE.instantiate() as Node3D
	if pot == null:
		_build_box_visual()
		return
	pot.name = "TreePotModel"
	add_child(pot)
	var bounds := _node_local_aabb(pot)
	if bounds.size.x <= 0.001 or bounds.size.y <= 0.001 or bounds.size.z <= 0.001:
		pot.queue_free()
		_build_box_visual()
		return
	# Preserve the pot's proportions; only fit its footprint to the collision
	# box. Stretching the shallow CC0 model vertically made it look like a
	# distorted bucket. The soil disk sits just below its natural rim instead.
	var target_xz := Vector2(box_size.x * 0.92, box_size.z * 0.92)
	var uniform_scale := minf(target_xz.x / bounds.size.x, target_xz.y / bounds.size.z)
	pot.scale = Vector3.ONE * uniform_scale
	pot.position = -bounds.get_center() * uniform_scale


func _node_local_aabb(root: Node3D) -> AABB:
	var found := false
	var lower := Vector3.ZERO
	var upper := Vector3.ZERO
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var relative := mesh_instance.transform
		var ancestor := mesh_instance.get_parent()
		while ancestor != null and ancestor != root:
			if ancestor is Node3D:
				relative = (ancestor as Node3D).transform * relative
			ancestor = ancestor.get_parent()
		if ancestor != root:
			continue
		var mesh_bounds := mesh_instance.mesh.get_aabb()
		for corner in range(8):
			var point: Vector3 = relative * mesh_bounds.get_endpoint(corner)
			if not found:
				lower = point
				upper = point
				found = true
			else:
				lower = lower.min(point)
				upper = upper.max(point)
	return AABB(lower, upper - lower) if found else AABB()


## A scoop of gathered beach sand is an optional top-dressing resource. It
## changes the visible soil surface without changing legacy planting rules.
func add_sand() -> bool:
	if sand_applied:
		return false
	sand_applied = true
	_build_sand_layer()
	return true


func has_sand() -> bool:
	return sand_applied


func restore_sand_state(applied: bool) -> void:
	sand_applied = applied
	if sand_applied:
		_build_sand_layer()


func _build_sand_layer() -> void:
	if not sand_applied:
		return
	if _sand_layer != null and is_instance_valid(_sand_layer):
		_sand_layer.queue_free()
	_sand_layer = MeshInstance3D.new()
	_sand_layer.name = "AppliedBeachSand"
	if planter_category == PlanterCategory.TREE_POT:
		var disk := CylinderMesh.new()
		disk.top_radius = box_size.x * 0.30
		disk.bottom_radius = disk.top_radius
		disk.height = 0.012
		disk.radial_segments = 20
		_sand_layer.mesh = disk
		_sand_layer.position.y = box_size.y * 0.33 + 0.006
	else:
		var layer := BoxMesh.new()
		layer.size = Vector3(box_size.x * 0.78, 0.012, box_size.z * 0.78)
		_sand_layer.mesh = layer
		_sand_layer.position.y = box_size.y * 0.5 + 0.006
	var material := ShaderMaterial.new()
	material.shader = SAND_SURFACE_SHADER
	material.set_shader_parameter("sand_color", Color(0.73, 0.56, 0.34, 1.0))
	material.set_shader_parameter("grain_scale", 31.0)
	_sand_layer.material_override = material
	_sand_layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sand_layer)


func category_name() -> String:
	match planter_category:
		PlanterCategory.POT:
			return "pot"
		PlanterCategory.BOX:
			return "box"
		_:
			return "tree_pot"


## Runtime handle to the PlantDB autoload. Resolved via /root instead of the
## compile-time global identifier so this class_name script parses cleanly even
## when the editor has not yet reloaded a newly-added autoload from
## project.godot (avoids "Identifier \"PlantDB\" not declared").
func _plant_db() -> Node:
	return get_node_or_null("/root/PlantDB")


## Called by the player when using a matching seed item on this planter.
func plant_seed(id: String) -> bool:
	if _plant != null and is_instance_valid(_plant):
		return false
	var db: Node = _plant_db()
	if db == null:
		return false
	var def: Dictionary = db.get_def(id)
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


func save_plant_state() -> Dictionary:
	if not has_plant() or not _plant.has_method("save_state"):
		return {}
	var state: Variant = _plant.call("save_state")
	return state if state is Dictionary else {}


func restore_plant_state(state: Dictionary) -> void:
	var plant_id: String = str(state.get("id", ""))
	if plant_id.is_empty() or has_plant() or not plant_seed(plant_id):
		return
	if _plant != null and _plant.has_method("restore_state"):
		_plant.call("restore_state", state)
