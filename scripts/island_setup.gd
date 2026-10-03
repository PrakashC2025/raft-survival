extends Node3D
## Island setup helper (parts 7.2 + 7.3 of the guide, automated).
## - Generates a TrimeshShape3D + StaticBody3D for the imported island glb
##   (the editor's "Mesh -> Create Trimesh Static Body" can't run headlessly,
##   so we create the identical thing at runtime).
## - Applies the island_terrain.gdshader material per surface so the island
##   reads as real grass + sand (the glb only carries near-white base colors
##   from the Blender vertex-paint workflow).
## - For sand_raftsurvival.glb (a ~283 m Sketchfab beach scan): rescales the
##   import to the old 24 m island footprint (structure + color from the
##   scan, size the palms/grass/beacon are tuned for) and keeps its own
##   textured sand material instead of the flat-color shader override.
## - Snaps each top-level PalmTree instance down onto the terrain (excluding
##   the palms' own collision bodies so nobody stands on their own trunk).
## - Rebuilds the grass one frame later, once the island collider exists.

const TERRAIN_SHADER_PATH := "res://shaders/island_terrain.gdshader"
const VEGETATION_VISUAL := preload("res://scripts/vegetation_visual.gd")
## Footprint the imported beach scan is normalised to (metres, widest X/Z axis).
## The raw scan is ~284 m of dunes that reach 46 m above its own water line, so
## it has to be shrunk hard to read as a small island next to the raft. 36 m
## gives a real islet: ~32 m of sand at the water line rising ~3 m to a dune
## crown — big enough that the palms and the grass field are visible from the
## raft instead of disappearing into a flat sand bank.
const ISLAND_TARGET_SIZE := 36.0
## Where the scan's own water line sits in its local (post-import) frame.
## Measured from the mesh: the beach ring is widest at y ~ 11 and the scan is
## cut off at y = 4.18, so putting y = 11 on the live sea surface sinks ~0.5 m
## of skirt under the waves (hides the cut rim) and leaves a ~3 m dune crown.
## The old value of 0.0 left the whole island floating half a metre ABOVE the
## water — the "flying saucer" look.
const SCAN_WATER_LINE := 11.0
## Vertical squash applied on top of the uniform footprint scale. The scan's
## dunes are alpine-steep; flattening them to ~62% reads as a beach islet
## instead of a sand cone and keeps the crown near the palms' canopy height.
const ISLAND_VERTICAL_SQUASH := 0.62

@export var island_root: NodePath = ^"../Island"
@export var generate_collision := true
@export var snap_palms := true
@export var apply_terrain_material := true

var _terrain_mats: Array[ShaderMaterial] = []
var _island_node: Node3D = null
var setup_complete := false

func _ready() -> void:
	var island := get_node_or_null(island_root) as Node3D
	if island != null and _is_sketchfab_island(island):
		# Rescale BEFORE collision/snap/grass so everything sees final geometry.
		_normalize_sketchfab_island(island)
	if generate_collision:
		# Cooking a scan mesh can be expensive on mobile. Yield between generated
		# bodies so the startup work does not pile up in a single frame.
		await _create_island_collision()
	if apply_terrain_material:
		_apply_terrain_materials()
	_apply_palm_visuals()
	if snap_palms:
		if generate_collision:
			# Freshly created colliders only enter the physics space after a
			# step — wait one physics frame or every palm ray misses.
			await get_tree().physics_frame
		_snap_palm_trees()
	if generate_collision:
		# IslandGrass raycasts against the collider we just generated, but its
		# own _ready ran earlier in tree order — rebuild it after physics has
		# registered the new body (a plain process frame is too early).
		await get_tree().physics_frame
		await get_tree().physics_frame
		var grass := get_node_or_null(island_root_path().path_join("IslandGrass"))
		if grass != null and grass.has_method("rebuild"):
			grass.call("rebuild")
	setup_complete = true

func _process(_delta: float) -> void:
	# Keep the terrain shader's water line on the live wave surface so the wet
	# sand band breathes with the waves instead of freezing at spawn height.
	if _terrain_mats.is_empty():
		return
	var oc := get_tree().get_first_node_in_group("ocean")
	if oc == null or _island_node == null:
		return
	var wl := float(oc.call("get_height", _island_node.global_position))
	for m in _terrain_mats:
		if m != null and is_instance_valid(m):
			m.set_shader_parameter("water_line", wl)

func island_root_path() -> String:
	var p := String(island_root)
	return p if not p.is_empty() else "../Island"

func _apply_palm_visuals() -> void:
	var island := get_node_or_null(island_root) as Node3D
	if island == null:
		return
	for child in island.get_children():
		if child is Node3D and child.name.begins_with("Palm"):
			VEGETATION_VISUAL.apply_palm(child as Node3D)

func _create_island_collision() -> void:
	var island := get_node_or_null(island_root) as Node3D
	if island == null:
		push_warning("IslandSetup: island_root not set/found")
		return
	island.add_to_group("island")
	for mi in island.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst.mesh == null or not mesh_inst.visible:
			continue
		if _is_collision_skipped(mesh_inst, island):
			continue
		# Only skip this mesh when its own generated collision body exists. A
		# sibling body for another mesh must not suppress this mesh's collider.
		var body_name := mesh_inst.name + "_Body"
		if mesh_inst.get_parent().get_node_or_null(body_name) is StaticBody3D:
			continue
		var body := StaticBody3D.new()
		body.name = body_name
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		shape.shape = mesh_inst.mesh.create_trimesh_shape()
		body.add_child(shape)
		mesh_inst.get_parent().add_child(body)
		# Match the visual transform so the collider hugs the mesh exactly
		body.global_transform = mesh_inst.global_transform
		print("[IslandSetup] collision generated for ", mesh_inst.name)
		await get_tree().physics_frame

## Generated visuals flagged no_collision (beacon pillar/glow) are skipped for
## BOTH collision generation and material overrides.
func _is_collision_skipped(mesh_inst: MeshInstance3D, island: Node3D) -> bool:
	var n: Node = mesh_inst
	while n != null and n != island:
		if n.is_in_group("no_collision"):
			return true
		# Palm fronds are visual-only; colliding with their flat surfaces is
		# expensive and confusing when the player walks near the canopy.
		if n is MeshInstance3D and n.name.findn("leaf") >= 0:
			return true
		n = n.get_parent()
	return false

## True for the scanned beach import. Some GLB conversions rename the
## original Sketchfab nodes, so the large source-mesh footprint is the stable
## fallback signal.
func _is_sketchfab_island(island: Node3D) -> bool:
	for node in island.find_children("*", "Node3D", true, false):
		if node.name.begins_with("Sketchfab"):
			return true
	for candidate in island.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			var size := mesh_instance.mesh.get_aabb().size
			if maxf(size.x, size.z) >= 100.0:
				return true
	return false

## Gameplay nodes placed in main.tscn must never be rescaled with the scan.
func _is_gameplay_node(node: Node) -> bool:
	var n := node.name
	return n.begins_with("Palm") or n.begins_with("IslandGrass") \
			or n.begins_with("IslandBeacon") or n.begins_with("IslandMountain") \
			or n.begins_with("IslandBirds")

func _is_gameplay_descendant(node: Node, island: Node3D) -> bool:
	var current := node
	while current != null and current != island:
		if _is_gameplay_node(current):
			return true
		current = current.get_parent()
	return false

## The scan spans ~284 m of dunes reaching 46 m above its own water line — far
## bigger than a gameplay island. Scale every imported root down so the widest
## mesh's XZ footprint matches ISLAND_TARGET_SIZE, then drop the whole island so
## the scan's water line rides the live sea surface (the mesh continues ~22 m
## below that line, so without this lift the island stays mostly submerged and
## reads as a flat, tree-less sand bank). Stray props (raft/shell debris) that
## would shrink into sub-decimeter specks are hidden.
func _normalize_sketchfab_island(island: Node3D) -> void:
	var max_extent := 0.0
	for mi in island.find_children("*", "MeshInstance3D", true, false):
		if _is_gameplay_descendant(mi, island):
			continue
		if mi.mesh != null:
			var s := (mi as MeshInstance3D).mesh.get_aabb().size
			max_extent = maxf(max_extent, maxf(s.x, s.z))
	if max_extent <= 0.0:
		return
	var k := ISLAND_TARGET_SIZE / max_extent
	var kv := k * ISLAND_VERTICAL_SQUASH
	for child in island.get_children():
		# Scale ONLY the scan's mesh wrapper — gameplay nodes (palms, grass
		# field, beacon) keep their real-world sizes and offsets.
		if child is Node3D and not _is_gameplay_node(child):
			(child as Node3D).scale = Vector3(k, kv, k)
	# Drop the island so the scan's own water line sits on the real sea surface.
	var water_y := _water_height_at(island.global_position)
	island.global_position.y = water_y - kv * SCAN_WATER_LINE
	for mi in island.find_children("*", "MeshInstance3D", true, false):
		if _is_gameplay_descendant(mi, island):
			continue
		if mi.mesh != null:
			var s := (mi as MeshInstance3D).mesh.get_aabb().size
			if maxf(s.x, s.z) * k < 1.0:
				(mi as MeshInstance3D).visible = false
	print("[IslandSetup] beach scan rescaled x%.4f -> %d m footprint, shoreline at y=%.2f"
			% [k, int(ISLAND_TARGET_SIZE), island.global_position.y])


## Live sea-surface height (world Y) at a position; 0.0 if the ocean has not
## registered itself in the "ocean" group yet.
func _water_height_at(world_pos: Vector3) -> float:
	var oc := get_tree().get_first_node_in_group("ocean")
	if oc != null and oc.has_method("get_height"):
		return float(oc.call("get_height", world_pos))
	return 0.0

## Replace the glb's near-white placeholder materials with the terrain shader.
## Surfaces are matched by imported surface name (IslandGrass / Sand from the
## glb materials); with unknown names, the first surface is treated as the
## grassy mound and the rest as sand rings. Both materials share the same
## shader and are kept so _process can push the live water line into them.
func _apply_terrain_materials() -> void:
	var island := get_node_or_null(island_root) as Node3D
	if island == null:
		return
	_island_node = island
	if _is_sketchfab_island(island):
		# The scan carries its own textured sand material — keep it.
		return
	if not ResourceLoader.exists(TERRAIN_SHADER_PATH):
		push_warning("IslandSetup: %s missing — island keeps its glb materials" % TERRAIN_SHADER_PATH)
		return
	var shader := load(TERRAIN_SHADER_PATH) as Shader
	if shader == null:
		return
	# Grass surface: the glb's vertex paint IS the albedo (green plateau, tan
	# shore edge) — keep base_color white so the paint shows through.
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = shader
	grass_mat.set_shader_parameter("base_color", Color(1.0, 1.0, 1.0))
	grass_mat.set_shader_parameter("paint_boost", 1.18)
	grass_mat.set_shader_parameter("detail_scale", 20.0)
	grass_mat.set_shader_parameter("sand_glint", 0.0)
	# Sand surface: paint is plain white — the sand tint comes from base_color.
	var sand_mat := ShaderMaterial.new()
	sand_mat.shader = shader
	sand_mat.set_shader_parameter("base_color", Color(0.87, 0.77, 0.55))
	sand_mat.set_shader_parameter("paint_boost", 1.0)
	sand_mat.set_shader_parameter("detail_scale", 26.0)
	sand_mat.set_shader_parameter("detail_strength", 0.12)
	_terrain_mats = [grass_mat, sand_mat]
	for mi in island.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst.mesh == null or _is_collision_skipped(mesh_inst, island):
			continue
		# ONLY the terrain glb gets the ground material — never the palm
		# trees (their own trunk/leaf materials must survive) or any other
		# generated visuals.
		if not _is_terrain_mesh(mesh_inst, island):
			continue
		var mesh := mesh_inst.mesh
		var touched := false
		for s in mesh.get_surface_count():
			var sname := ""
			if mesh is ArrayMesh:
				sname = (mesh as ArrayMesh).surface_get_name(s)
			var apply_here := true
			var mat := sand_mat
			if sname.findn("grass") >= 0:
				mat = grass_mat
			elif sname.findn("sand") >= 0:
				pass  # keep sand_mat default
			elif sname.is_empty():
				# Unnamed surfaces: first = mound (grass), others = sand ring.
				mat = grass_mat if s == 0 else sand_mat
			else:
				apply_here = false  # unknown named surface: keep its glb material
			if apply_here:
				mesh_inst.set_surface_override_material(s, mat)
				touched = true
		if touched:
			print("[IslandSetup] terrain material applied to ", mesh_inst.name)

## True only for the imported terrain mesh (named Island_Terrain in the glb).
## Anything under a Palm* node or the IslandGrass field is excluded so their
## own materials are never overridden.
func _is_terrain_mesh(mesh_inst: MeshInstance3D, island: Node3D) -> bool:
	if mesh_inst.name.findn("Terrain") >= 0:
		return true
	var n: Node = mesh_inst
	while n != null and n != island:
		var pname := n.name
		if pname.begins_with("Palm") or pname.begins_with("IslandGrass") \
				or pname.begins_with("IslandBeacon"):
			return false
		n = n.get_parent()
	# Fallback for renamed imports: a MeshInstance3D whose surfaces carry the
	# glb's IslandGrass/Sand material names.
	var mesh := mesh_inst.mesh
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_name(s) != "":
			return true
	return false

func _snap_palm_trees() -> void:
	var island := get_node_or_null(island_root) as Node3D
	if island == null:
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	# Only top-level palm instances (children of Island), never the PalmTree
	# mesh wrapper nodes inside each glb instance.
	var palms: Array[Node3D] = []
	for palm in island.get_children():
		if palm is Node3D and palm.name.begins_with("Palm"):
			palms.append(palm)
	if palms.is_empty():
		return
	# Exclude every palm's own collision bodies, otherwise a palm lands on
	# top of its own (pre-move) trunk collider.
	var exclude: Array[RID] = []
	for palm in palms:
		for body in palm.find_children("*", "StaticBody3D", true, false):
			exclude.append((body as CollisionObject3D).get_rid())
	# Long probe: the island crown now rises ~3 m and palms are authored a
	# little above the sand, so a short ±5/±10 ray can start *below* a dune
	# crest and miss the ground entirely (palm left floating / buried).
	for palm in palms:
		var from: Vector3 = palm.global_position + Vector3.UP * 16.0
		var to: Vector3 = palm.global_position + Vector3.DOWN * 16.0
		var q := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			push_warning("IslandSetup: no ground found under %s" % palm.name)
			continue
		palm.global_position = hit["position"]
		print("[IslandSetup] %s snapped to ground y=%.2f" % [palm.name, hit["position"].y])
