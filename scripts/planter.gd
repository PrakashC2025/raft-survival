extends StaticBody3D
class_name Planter

## PlanterPot / PlanterBox / TreePot â€” one script, three .tscn variants.
## The CollisionShape3D and BuildSockets/Socket_Base live in each .tscn
## (like foundation.tscn / wall.tscn) so the existing build system's
## socket + overlap checks work unmodified. This script only builds the
## decorative mesh + soil + the slot the plant grows in.
##
## IMPORTANT: keep `box_size` below equal to the CollisionShape3D's
## BoxShape3D size set in the .tscn file â€” they are not auto-synced.

enum PlanterCategory { POT, BOX, TREE_POT }

@export var planter_category: PlanterCategory = PlanterCategory.POT
@export var box_size: Vector3 = Vector3(0.5, 0.35, 0.5)
@export var wood_color: Color = Color(0.55, 0.38, 0.2)
@export var soil_color: Color = Color(0.32, 0.22, 0.14)

const TREE_POT_SCENE: PackedScene = preload("res://models/kenney_pot_large.glb")
const SAND_SURFACE_SHADER: Shader = preload("res://shaders/sand_surface.gdshader")
const OBJECT_MATERIALS := preload("res://scripts/object_materials.gd")

var planted_id: String = ""
var sand_applied := false
var moisture := 0.75
var _moisture_tick := 0.0

func water_soil() -> bool:
	if moisture >= 0.95:
		return false
	moisture = minf(1.0, moisture + 0.75)
	return true

func growth_factor() -> float:
	return 0.25 if moisture < 0.15 else 1.0

func _process(delta: float) -> void:
	if get_parent() != null and get_parent().name == "BuildPreviewRoot":
		return
	_moisture_tick += delta
	if _moisture_tick < 1.0:
		return
	var elapsed := _moisture_tick
	_moisture_tick = 0.0
	moisture = maxf(0.0, moisture - elapsed * 0.002)
	if _soil != null:
		(_soil.material_override as ShaderMaterial).set_shader_parameter("moisture",moisture)
	var rain := get_tree().get_first_node_in_group("rain_system")
	if rain != null and bool(rain.get("_is_raining")):
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * (box_size.y + 0.1), global_position + Vector3.UP * 8.0, 1, [get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			moisture = minf(1.0, moisture + elapsed * 0.05)
var _soil: MeshInstance3D
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

	var round_bed := planter_category == PlanterCategory.TREE_POT
	var soil_size := Vector2(box_size.x,box_size.z)*(0.66 if round_bed else 0.82)
	_soil=preload("res://scripts/soil_visual.gd").create(soil_size,round_bed,soil_color)
	_soil.position.y=box_size.y*(0.33 if round_bed else 0.49)
	add_child(_soil)

	_slot = Node3D.new()
	_slot.name = "PlantSlot"
	var soil_top := box_size.y * (0.33 if planter_category == PlanterCategory.TREE_POT else 0.5)
	_slot.position = Vector3(0.0, soil_top, 0.0)
	add_child(_slot)


func _build_box_visual() -> void:
	var thickness := minf(0.045, box_size.x * 0.1)
	var sizes := [Vector3(box_size.x, thickness, box_size.z), Vector3(thickness, box_size.y, box_size.z), Vector3(thickness, box_size.y, box_size.z), Vector3(box_size.x, box_size.y, thickness), Vector3(box_size.x, box_size.y, thickness)]
	var centers := [Vector3(0, -box_size.y * 0.5 + thickness * 0.5, 0), Vector3(-box_size.x * 0.5 + thickness * 0.5, 0, 0), Vector3(box_size.x * 0.5 - thickness * 0.5, 0, 0), Vector3(0, 0, -box_size.z * 0.5 + thickness * 0.5), Vector3(0, 0, box_size.z * 0.5 - thickness * 0.5)]
	for index in range(5):
		var mesh_instance := MeshInstance3D.new()
		var wall := BoxMesh.new()
		wall.size = sizes[index]
		mesh_instance.mesh = preload("res://scripts/construction_visual.gd").box(wall.size,wood_color)
		mesh_instance.position = centers[index]
		add_child(mesh_instance)


func _build_tree_pot_visual() -> void:
	for index in 20:
		var angle := TAU*index/20.0
		var stave := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size=Vector3(box_size.x*0.128,box_size.y*0.9,0.045)
		stave.mesh=preload("res://scripts/construction_visual.gd").rounded_timber(shape.size,1.0)
		stave.position=Vector3(sin(angle)*box_size.x*0.38,0,cos(angle)*box_size.z*0.38)
		stave.rotation.y=angle
		add_child(stave)
	for height in [-0.30,0.26]:
		var band := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius=box_size.x*0.38;ring.outer_radius=ring.inner_radius+0.018
		ring.rings=24;ring.ring_segments=6
		band.mesh=ring;band.position.y=box_size.y*height
		band.material_override=preload("res://scripts/construction_visual.gd")._rope_material()
		add_child(band)


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
## down â€” the slot becomes free again.
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
