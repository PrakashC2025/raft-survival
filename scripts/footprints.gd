extends MultiMeshInstance3D
## ============================================================
## FOOTPRINTS IN THE SAND — ring-buffer decal stamps.
## Every step the player takes on the island's terrain leaves a footprint:
## a dark pressed-sand sole quad laid flat on the ground (raycast to follow
## dune contours). Prints near the waterline are wetter (darker) and get
## washed away rapidly by incoming waves. Dry prints fade slowly with wind.
##
## Mobile friendly: ONE MultiMeshInstance3D (a single draw call, no shadows,
## depth-draw-off multiply blend) holds every print; old prints are reused
## ring-buffer style. Placement is driven by island_generator (which owns the
## player reference and terrain) calling try_stamp() while the player walks.
## ============================================================

const MAX_PRINTS := 96            ## ring buffer size (one draw call)
const STEP_INTERVAL := 0.85       ## meters of travel between prints
const FADE_TIME := 25.0           ## seconds until a print fully fades (dry)
const WASH_FADE_TIME := 3.0       ## seconds until a print fades near waterline
const SOLE_SIZE := Vector2(0.30, 0.14) ## real bare-foot print (about size 42)
const WASH_HEIGHT := 0.45         ## terrain height at which waves wash prints

var _mesh := QuadMesh.new()
var _mm := MultiMesh.new()
var _head := 0                    ## next slot to write (ring buffer)
var _ages := PackedFloat32Array() ## seconds since each print was stamped
var _wetness := PackedFloat32Array() ## per-print wetness (0 dry, 1 saturated)
var _last_pos := Vector3.ZERO
var _last_dir := Vector3.FORWARD
var _travel := 0.0                ## accumulated distance since the last print
var _which_foot := 0              ## 0 right / 1 left — alternating offset
var _terrain: Node3D = null       ## Island node (provides terrain raycast world)

func _ready() -> void:
	visible = false # nothing until the first print
	_mesh.size = SOLE_SIZE
	_mesh.orientation = PlaneMesh.FACE_Y
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = _mesh
	_mm.instance_count = MAX_PRINTS # zero-initialized transforms = degenerate
	multimesh = _mm
	_ages.resize(MAX_PRINTS)
	_wetness.resize(MAX_PRINTS)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fm := ShaderMaterial.new()
	if ResourceLoader.exists("res://shaders/footprint.gdshader"):
		fm.shader = load("res://shaders/footprint.gdshader")
		fm.set_shader_parameter("print_strength", 0.55)
	material_override = fm
	add_to_group("no_collision")

## Called by island_generator once the terrain exists.
func setup(terrain_root: Node3D) -> void:
	_terrain = terrain_root

## Feed the player position every physics frame; stamps when enough
## distance has accumulated and the ground underfoot is sand.
func track(player: Node3D, ground_normal_y: float, terrain_h: float) -> void:
	if player == null:
		return
	var p := player.global_position
	var moved := Vector3(p.x - _last_pos.x, 0.0, p.z - _last_pos.z)
	if moved.length_squared() > 0.0001:
		_last_dir = moved.normalized()
		_travel += moved.length()
		_last_pos = p
	if _travel < STEP_INTERVAL:
		return
	_travel = 0.0
	# Slope check — no prints on cliffs.
	if ground_normal_y < 0.72:
		return
	# Only stamp on sand — use island_generator's sand detection if available
	var ig := get_tree().get_first_node_in_group("island") as Node3D
	if ig != null:
		var origin := Vector2(ig.global_position.x, ig.global_position.z)
		if not IslandGenerator.is_sand_at(Vector2(p.x, p.z), origin):
			return
	# Wetness from terrain height: below WASH_HEIGHT starts getting wet,
	# waterline (y=0) = fully wet.
	var wet := clampf((WASH_HEIGHT - terrain_h) / (WASH_HEIGHT + 0.15), 0.0, 1.0)
	_stamp(p, wet)

func _stamp(at: Vector3, wet: float) -> void:
	var i := _head
	_head = (_head + 1) % MAX_PRINTS
	# Raycast straight down from just above the feet so the print hugs the
	# dune surface (the generator supplies the world).
	var hit_h := _ground_height_at(Vector2(at.x, at.z))
	if hit_h == INF:
		return
	var fb := Basis(Vector3.UP, atan2(_last_dir.x, _last_dir.z))
	# Alternate feet: a small sideways offset makes a believable gait.
	var side := _last_dir.cross(Vector3.UP).normalized()
	var step_off := side * 0.09 * (1.0 if _which_foot == 0 else -1.0)
	_which_foot = 1 - _which_foot
	var pos := Vector3(at.x, hit_h + 0.02, at.z) + step_off
	var xform := Transform3D(fb, pos)
	_mm.set_instance_transform(i, xform)
	_mm.set_instance_color(i, Color(1.0, wet, 1.0, 1.0)) # G = wetness
	_ages[i] = 0.0
	_wetness[i] = wet
	visible = true

func _ground_height_at(world_xz: Vector2) -> float:
	# Use the scene tree's physics world directly — works whether or not
	# _terrain has been set by island_generator.
	var w3d := get_world_3d()
	if w3d == null:
		return INF
	var space := w3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(world_xz.x, 30.0, world_xz.y),
		Vector3(world_xz.x, -14.0, world_xz.y))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return INF
	return (hit.position as Vector3).y

func _process(delta: float) -> void:
	if not visible:
		return
	# Fade: rewrite alpha through instance color (cheap at 96 instances).
	# Wet prints near the waterline fade FAST (waves wash them away),
	# dry prints fade slowly (wind erosion).
	var all_gone := true
	for i in MAX_PRINTS:
		if _ages[i] >= FADE_TIME:
			continue
		_ages[i] += delta
		# Wetness-driven fade speed: wet prints wash away in WASH_FADE_TIME,
		# dry prints last FADE_TIME. Linear interpolation between the two.
		var wet: float = _wetness[i]
		var fade_speed: float = lerp(1.0 / FADE_TIME, 1.0 / WASH_FADE_TIME, wet * wet)
		var k: float = 1.0 - clampf(_ages[i] * fade_speed, 0.0, 1.0)
		if k > 0.0:
			all_gone = false
			var c := _mm.get_instance_color(i)
			_mm.set_instance_color(i, Color(c.r, c.g, c.b, k))
	if all_gone:
		visible = false
