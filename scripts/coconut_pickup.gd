extends RigidBody3D
class_name CoconutPickup
## A coconut that fell from an island palm. Shaped like a piece of Debris
## (item_name / collected / is_hooked) so the player's existing E-to-collect
## path picks it up with zero special-casing. Physical behavior tuned to a
## real nut: heavy, thuds and stops (no trampolining), CCD so a fast fall
## never tunnels through the terrain trimesh ("coconut went inside the land").

var item_name := "Coconut"
var collected := false
var is_hooked := false          # rope-system compatibility (never hooked)
var travel_start := Vector3.ZERO
var _life := 300.0              # despawn if nobody collects it (longer than apples: food + seed source)

# --- SEA BEHAVIOR: a coconut SINKS (husk fibers are waterlogged) ---
# Debris floats; a nut in salt water slowly submerges and fades out. The old
# zero-gravity rigid body bobbed on the surface like a piece of driftwood.
var _ocean: Node = null
var _sinking := false
var _sink_t := 0.0
const SINK_DELAY := 4.0 # seconds riding the waves before waterlogging starts

func _find_ocean() -> Node:
	if _ocean != null and is_instance_valid(_ocean):
		return _ocean
	_ocean = get_tree().get_first_node_in_group("ocean")
	return _ocean

func _ready() -> void:
	add_to_group("debris")
	collision_layer = 2            # debris layer: aim/pickup raycasts see it
	collision_mask = 1             # collides with terrain/raft/player
	mass = 1.2                     # a real coconut ~1.2-1.5 kg
	linear_damp = 0.2
	angular_damp = 1.5
	continuous_cd = true           # ~12 m/s impact on a thin terrain triangle = tunneling without CCD
	travel_start = global_position
	# THUD, don't bounce: high friction, near-zero restitution.
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	physics_material_override = pm

	var mi := MeshInstance3D.new()
	# REAL KING COCONUT: grass/baked/coconut_single.res — ONE coconut
	# extracted from models/king_coconut.glb by the bake (largest connected
	# shell, real kc_HP1 texture, pivot at the stem top). Rendered through
	# the SAME unlit tint path as the tree's slot bunches so a dropped nut
	# looks exactly like the ones still hanging (uniform tint, no dark-ball
	# PBR cavity shading). Falls back to the procedural sphere only if the
	# bake output is missing.
	var real_mesh: Mesh = null
	if ResourceLoader.exists("res://grass/baked/coconut_single.res"):
		real_mesh = load("res://grass/baked/coconut_single.res") as Mesh
	if real_mesh != null:
		mi.mesh = real_mesh
		# ~11-13 cm nuts — matched to the ON-TREE slots (12 cm bake × 1.05
		# fruit_scale ≈ 12.6 cm) so a dropped nut looks like the same nut
		# that fell (user: drops were "too low, always same size"). Natural
		# per-nut size spread, like a real bunch.
		var nut_s := randf_range(0.9, 1.1)
		mi.scale = Vector3.ONE * nut_s
		# Lift so the nut (not the stem pivot) rests on the ground.
		mi.position = Vector3(0, 0.06 * nut_s, 0)
		var tint := ShaderMaterial.new()
		tint.shader = load("res://shaders/fruit_tint.gdshader")
		tint.set_shader_parameter("ripeness", 1.0)
		tint.set_shader_parameter("unlit", 1.0)
		var bm := real_mesh.surface_get_material(0) as BaseMaterial3D
		if bm != null and bm.albedo_texture != null:
			tint.set_shader_parameter("albedo_tex", bm.albedo_texture)
		mi.material_override = tint
	else:
		var sm := SphereMesh.new()
		# ~10 cm nut — the old 15 cm pickup read "big" next to a 4.65 m palm
		# (user pass 19: "still showing like dropable big"). Matches the 8.5 cm
		# on-tree slot nuts so a drop looks continuous.
		sm.radius = 0.052
		sm.height = 0.10               # slightly squashed — small nut silhouette
		sm.radial_segments = 12
		sm.rings = 8
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		# LINEAR-COLOR RULE (same trap as the sand albedo): a code-set color is
		# used raw in linear space — (0.45,0.33,0.18) displayed as a washed-out
		# PALE TAN that read as "highlighted" on the sand. True dried husk
		# sRGB(0.45,0.33,0.18) -> linear (0.17,0.09,0.028); also matches the
		# on-tree ripe nuts so the drop never looks like a different object.
		m.albedo_color = Color(0.17, 0.09, 0.028)
		m.roughness = 0.92
		mi.material_override = m
	if real_mesh == null:
		mi.scale = Vector3(1.0, 0.92, 1.0)
	add_child(mi)

	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.05
	cs.shape = sp
	add_child(cs)

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0 or global_position.y < -6.0:
		queue_free()
		return
	# --- WATERLOG + SINK: below the water surface for SINK_DELAY s -> fill ---
	# Two water surfaces count: the OCEAN (wave height at this XZ) and the
	# ISLAND POND (a nut rolled into the freshwater pond also waterlogs —
	# the pond is at IslandGenerator.POND_POS, radius POND_R).
	var surface_y := -1e9
	var oc := _find_ocean()
	if oc != null:
		surface_y = float(oc.call("get_height", global_position))
	var ig := get_tree().get_first_node_in_group("island") as Node3D
	if ig != null:
		var pond_local := Vector2(global_position.x, global_position.z) \
			- Vector2(ig.global_position.x, ig.global_position.z)
		var pond_d := pond_local.distance_to(IslandGenerator.POND_POS)
		if pond_d < IslandGenerator.POND_R:
			surface_y = maxf(surface_y, IslandGenerator.pond_water_height())
	if not _sinking:
		if global_position.y + 0.07 < surface_y: # nut center under water
			_sink_t += delta
			if _sink_t > SINK_DELAY:
				_sinking = true
				gravity_scale = 0.35 # waterlogged: heavy, glides down
				linear_damp = 1.2
				angular_damp = 3.0
		else:
			_sink_t = 0.0
	if _sinking:
		# fade while a few cm under, then despawn (nothing collectible down there)
		if global_position.y < surface_y - 0.25:
			queue_free()
