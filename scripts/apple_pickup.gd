extends RigidBody3D
class_name ApplePickup
## A ripe apple that dropped from an apple tree. Deliberately shaped like a
## piece of Debris (item_name / collected / is_hooked) so the player's
## existing E-to-collect path picks it up with zero special-casing.
## The mesh is the REAL scanned apple baked from apple_tree.glb
## (grass/baked/apple_single.res, ~340 tris) — many can exist at once.

var item_name := "Apple"
var collected := false
var is_hooked := false          # rope-system compatibility (never hooked)
var travel_start := Vector3.ZERO
var _life := 120.0              # despawn if nobody collects it

func _ready() -> void:
	add_to_group("debris")
	collision_layer = 2            # debris layer: aim/pickup raycasts see it
	collision_mask = 1             # collides with terrain/raft/player
	mass = 0.15
	linear_damp = 0.4
	angular_damp = 2.0
	travel_start = global_position

	var mi := MeshInstance3D.new()
	if ResourceLoader.exists("res://grass/baked/apple_single.res"):
		mi.mesh = load("res://grass/baked/apple_single.res")
	# The baked apple hangs BELOW its stem pivot — lift it so the fruit
	# (not the stem) rests on the ground under the sphere collider.
	mi.position = Vector3(0, 0.07, 0)
	add_child(mi)

	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.075 # hugs the 15 cm fruit (the 5 cm sphere let it half-sink)
	cs.shape = sp
	add_child(cs)

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0 or global_position.y < -6.0:
		queue_free()
