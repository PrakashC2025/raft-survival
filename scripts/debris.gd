extends RigidBody3D
class_name Debris

# ---- Identity (kept so Inventory can collect it) ----
@export var item_name := "Wood"

# ---- Ocean current (assigned by the spawner so all debris share a stream) ----
@export var current_direction: Vector3 = Vector3(0, 0, 1)
@export var current_speed: float = 1.2

# ---- Floating profile ----
@export var freeboard: float = 0.15
@export var buoyancy: float = 8.0
@export var max_vertical_speed: float = 2.0

# World position where this piece was spawned; the spawner uses it to
# measure how far downstream it has travelled before despawning.
var travel_start: Vector3 = Vector3.ZERO
var collected: bool = false
var is_hooked: bool = false

var mass_kg: float = 2.0
var ocean: Ocean = null

var _wander_seed: float = 0.0
var _side_drift: float = 0.0
var _speed_variation: float = 1.0
var _rot_speed: float = 0.0

# Fade in/out
var _fade_timer: float = 0.0
var _fade_duration: float = 1.5
var _is_fading_in: bool = true
var _is_fading_out: bool = false
var _fade_material: StandardMaterial3D = null

const BUOY_DAMPING: float = 3.0

# Each entry controls how "floaty" that item looks (rides higher/lower).
const ITEM_PROFILES := {
	"Wood":    {"mass": 2.0, "freeboard": 0.20, "color": Color(0.85, 0.65, 0.35)},
	"Rope":    {"mass": 1.0, "freeboard": 0.05, "color": Color(0.75, 0.60, 0.35)},
	"Plastic": {"mass": 0.6, "freeboard": 0.25, "color": Color(0.3, 0.7, 1.0)},
	"Barrel":  {"mass": 6.0, "freeboard": 0.30, "color": Color(0.70, 0.45, 0.20)},
	"Stone":   {"mass": 4.0, "freeboard": 0.10, "color": Color(0.65, 0.65, 0.65)},
	"Metal":   {"mass": 5.0, "freeboard": 0.15, "color": Color(0.80, 0.80, 0.85)},
}

func _ready() -> void:
	add_to_group("debris")
	ocean = get_tree().get_first_node_in_group("ocean")
	if ocean == null:
		ocean = get_node_or_null("%Ocean")

	_wander_seed = randf() * 1000.0
	_side_drift = randf_range(-0.3, 0.3)
	_speed_variation = randf_range(0.9, 1.0)
	_rot_speed = randf_range(-1.0, 1.0)

	_apply_profile()

	mass = mass_kg
	linear_damp = 2.5
	angular_damp = 3.0
	gravity_scale = 0.0   # buoyancy fully controls vertical motion

	# Sit on a dedicated layer so the pickup RayCast can detect debris
	# specifically. IMPORTANT: this only works if the Reach RayCast3D's
	# Collision Mask (Inspector) has bit 2 enabled — see the note above.
	collision_layer = 2
	# Keep default mask (1) so it still physically collides with the raft/player.
	collision_mask = 1

	# Snap onto the real wave height where it spawned.
	if ocean != null:
		global_position.y = float(ocean.get_height(global_position)) + freeboard

func start_fade_out() -> void:
	_is_fading_out = true
	_fade_timer = 0.0

func is_fade_done() -> bool:
	return _is_fading_out and _fade_timer >= _fade_duration

func _apply_profile() -> void:
	if ITEM_PROFILES.has(item_name):
		var prof = ITEM_PROFILES[item_name]
		mass_kg = prof["mass"]
		freeboard = prof["freeboard"]
		# Apply colour to the mesh so different debris is visually distinct
		var mesh_inst := get_node_or_null("MeshInstance3D")
		if mesh_inst and mesh_inst.get_surface_override_material(0) == null:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = prof["color"]
			mat.emission_enabled = true
			mat.emission = prof["color"] * 0.3
			mat.emission_energy_multiplier = 0.4
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.0
			mesh_inst.set_surface_override_material(0, mat)
			_fade_material = mat

func _physics_process(delta: float) -> void:
	# Skip all buoyancy/current math while the rope system is holding this
	# piece (freeze == true) — it has no effect on a frozen body today since
	# nothing currently un-freezes and re-releases debris, but computing
	# target velocities on a body that can't move is wasted work, and this
	# guard makes that assumption explicit instead of silently relying on
	# RigidBody3D's frozen state to absorb it.
	if freeze or is_hooked or collected:
		return
	if ocean == null:
		return

	var water_y: float = float(ocean.get_height(global_position))

	# ---- Vertical buoyancy: rest at the surface, follow the waves gently ----
	var rest_y: float = water_y + freeboard
	var y_error: float = rest_y - global_position.y
	linear_velocity.y += (buoyancy * y_error - BUOY_DAMPING * linear_velocity.y) * delta
	linear_velocity.y = clamp(linear_velocity.y, -max_vertical_speed, max_vertical_speed)

	# ---- Horizontal current: one dominant direction + small variation ----
	var dir: Vector3 = Vector3(current_direction.x, 0.0, current_direction.z).normalized()
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x).normalized()
	var target_velocity: Vector3 = dir * current_speed * _speed_variation + side * _side_drift
	var k: float = 1.0 - exp(-3.0 * delta)
	linear_velocity.x = lerpf(linear_velocity.x, target_velocity.x, k)
	linear_velocity.z = lerpf(linear_velocity.z, target_velocity.z, k)

	# ---- Gentle natural tumble ----
	var t: float = Time.get_ticks_msec() / 1000.0 + _wander_seed
	angular_velocity = Vector3(sin(t * 0.5) * 0.2, _rot_speed, cos(t * 0.4) * 0.2)

	# ---- Fade in on spawn ----
	if _is_fading_in and _fade_material != null:
		_fade_timer += delta
		var alpha: float = clampf(_fade_timer / _fade_duration, 0.0, 1.0)
		_fade_material.albedo_color.a = alpha
		if alpha >= 1.0:
			_is_fading_in = false

	# ---- Fade out before despawn ----
	if _is_fading_out and _fade_material != null:
		_fade_timer += delta
		var alpha: float = clampf(1.0 - _fade_timer / _fade_duration, 0.0, 1.0)
		_fade_material.albedo_color.a = alpha
