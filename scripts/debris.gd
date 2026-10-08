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
var _model_visual: Node3D = null

const BUOY_DAMPING: float = 3.0
const WOOD_LOG_SCENE: PackedScene = preload("res://models/kenney_log.glb")
const BARREL_SCENE: PackedScene = preload("res://models/kenney_barrel.glb")
const STONE_SCENE: PackedScene = preload("res://models/kenney_rock_small.glb")
const COCONUT_SCENE: PackedScene = preload("res://models/kenney_coconut.glb")
const OBJECT_MATERIALS := preload("res://scripts/object_materials.gd")
const RESOURCE_VISUAL := preload("res://scripts/resource_visual.gd")
var _visual_geometry: Array[GeometryInstance3D] = []

# Each entry controls how "floaty" that item looks (rides higher/lower).
const ITEM_PROFILES := {
	"Wood":    {"mass": 2.0, "freeboard": 0.07, "color": Color(0.85, 0.65, 0.35)},
	"Rope":    {"mass": 1.0, "freeboard": 0.01, "color": Color(0.75, 0.60, 0.35)},
	"Plastic": {"mass": 0.6, "freeboard": 0.08, "color": Color(0.3, 0.7, 1.0)},
	"Barrel":  {"mass": 6.0, "freeboard": 0.08, "color": Color(0.70, 0.45, 0.20)},
	"Stone":   {"mass": 4.0, "freeboard": 0.10, "color": Color(0.65, 0.65, 0.65)},
	"Sponge":  {"mass": 0.3, "freeboard": 0.09, "color": Color(0.53,0.41,0.17)},
	"Metal":   {"mass": 5.0, "freeboard": 0.02, "color": Color(0.80, 0.80, 0.85)},
	"Soil":    {"mass": 1.5, "freeboard": 0.08, "color": Color(0.32,0.22,0.12)},
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
	if is_instance_valid(_model_visual):RESOURCE_VISUAL.weather(_model_visual,item_name)

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
	# Stop the spawn fade and restart the timer for despawning. The timer must
	# run even for items without a profile material (for example, seed debris),
	# otherwise those objects never become eligible for cleanup.
	_is_fading_in = false
	_is_fading_out = true
	_fade_timer = 0.0

func is_fade_done() -> bool:
	return _is_fading_out and _fade_timer >= _fade_duration

func _apply_profile() -> void:
	if not ITEM_PROFILES.has(item_name):
		if item_name.ends_with(" Seed"):
			var crop:=item_name.trim_suffix(" Seed")
			if crop in ["Potato","Tomato","Banana"]:
				freeboard=0.025
				_model_visual=preload("res://scripts/produce_visual.gd").create(crop)
				_model_visual.scale=Vector3.ONE*1.7;add_child(_model_visual)
			elif crop=="Coconut":
				freeboard=0.10
				_model_visual=_create_model_visual(COCONUT_SCENE,0.42)
			else:
				_model_visual = RESOURCE_VISUAL.create(item_name)
				add_child(_model_visual)
			(get_node("MeshInstance3D") as MeshInstance3D).visible = false
			_cache_visual_geometry()
			_set_visual_alpha(0.0)
		return
	var profile: Dictionary = ITEM_PROFILES[item_name]
	mass_kg = float(profile["mass"])
	freeboard = float(profile["freeboard"])
	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	var model_scene: PackedScene = null
	var target_size := 0.0
	match item_name:
		"Wood":
			model_scene = WOOD_LOG_SCENE
			target_size = 0.86
			_set_collision_box_size(Vector3(0.32, 0.24, 0.9))
		"Barrel":
			model_scene = BARREL_SCENE
			target_size = 0.5
			_set_collision_box_size(Vector3(0.46, 0.44, 0.46))

	if model_scene != null and mesh_instance != null:
		_model_visual = _create_model_visual(model_scene, target_size)
		if _model_visual != null:
			mesh_instance.visible = false
			_cache_visual_geometry()
			_set_visual_alpha(0.0)
			return
	if item_name in ["Rope", "Plastic", "Metal", "Sponge", "Soil", "Stone"] and mesh_instance != null:
		_model_visual = RESOURCE_VISUAL.create(item_name)
		add_child(_model_visual)
		mesh_instance.visible = false
		_cache_visual_geometry()
		_set_visual_alpha(0.0)
		return

	# Keep a simple tinted fallback for item types without a dedicated model.
	if mesh_instance != null and mesh_instance.get_surface_override_material(0) == null:
		var material := StandardMaterial3D.new()
		material.albedo_color = profile["color"]
		material.roughness = 0.82
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.0
		mesh_instance.set_surface_override_material(0, material)
		_fade_material = material


func _set_collision_box_size(size: Vector3) -> void:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not (collision_shape.shape is BoxShape3D):
		return
	# Shape resources may be shared by instances of debris.tscn. Duplicate before
	# resizing so one barrel cannot silently change every log's collider.
	var box := collision_shape.shape.duplicate() as BoxShape3D
	box.size = size
	collision_shape.shape = box


func _create_model_visual(scene: PackedScene, desired_max_size: float) -> Node3D:
	var model := scene.instantiate() as Node3D
	if model == null:
		return null
	model.name = "AssetVisual"
	add_child(model)
	var bounds := _node_local_aabb(model)
	var largest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if largest <= 0.001:
		model.queue_free()
		return null
	var model_scale: float = desired_max_size / largest
	model.scale = Vector3.ONE * model_scale
	model.position = -bounds.get_center() * model_scale
	OBJECT_MATERIALS.apply_model(model, OBJECT_MATERIALS.kind_for_item(item_name))
	return model


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


func _set_visual_alpha(alpha: float) -> void:
	var clamped_alpha := clampf(alpha, 0.0, 1.0)
	if _model_visual != null and is_instance_valid(_model_visual):
		_model_visual.visible = clamped_alpha > 0.001
		for geometry in _visual_geometry:
			geometry.transparency = 1.0 - clamped_alpha
	elif _fade_material != null:
		_fade_material.albedo_color.a = clamped_alpha


func _cache_visual_geometry() -> void:
	_visual_geometry.clear()
	for node in _model_visual.find_children("*", "GeometryInstance3D", true, false):
		_visual_geometry.append(node as GeometryInstance3D)

func _physics_process(delta: float) -> void:
	# Skip all buoyancy/current math while the rope system is holding this
	# piece (freeze == true) — it has no effect on a frozen body today since
	# nothing currently un-freezes and re-releases debris, but computing
	# target velocities on a body that can't move is wasted work, and this
	# guard makes that assumption explicit instead of silently relying on
	# RigidBody3D's frozen state to absorb it.
	if freeze or is_hooked or collected:
		return
	if ocean != null:
		var water_y: float = float(ocean.get_height(global_position))
		var drift_velocity := linear_velocity

		# ---- Vertical buoyancy: rest at the surface, follow the waves gently ----
		var rest_y: float = water_y + freeboard
		var y_error: float = rest_y - global_position.y
		drift_velocity.y += (buoyancy * y_error - BUOY_DAMPING * drift_velocity.y) * delta
		drift_velocity.y = clampf(drift_velocity.y, -max_vertical_speed, max_vertical_speed)

		# ---- Horizontal current: one dominant direction + small variation ----
		var dir: Vector3 = Vector3(current_direction.x, 0.0, current_direction.z).normalized()
		var side: Vector3 = Vector3(-dir.z, 0.0, dir.x).normalized()
		var target_velocity: Vector3 = dir * current_speed * _speed_variation + side * _side_drift
		var k: float = 1.0 - exp(-3.0 * delta)
		drift_velocity.x = lerpf(drift_velocity.x, target_velocity.x, k)
		drift_velocity.z = lerpf(drift_velocity.z, target_velocity.z, k)
		# Commit once rather than synchronizing the physics body four times.
		linear_velocity = drift_velocity

		# ---- Gentle natural tumble ----
		var t: float = Time.get_ticks_msec() / 1000.0 + _wander_seed
		angular_velocity = Vector3(sin(t * 0.5) * 0.2, _rot_speed, cos(t * 0.4) * 0.2)

	# ---- Fade in on spawn ----
	# Advance the timer regardless of whether this item has a fade material.
	# Seed items do not use ITEM_PROFILES, but still need to finish their
	# lifecycle normally.
	if _is_fading_in:
		_fade_timer += delta
		_set_visual_alpha(clampf(_fade_timer / _fade_duration, 0.0, 1.0))
		if _fade_timer >= _fade_duration:
			_is_fading_in = false
			_fade_timer = 0.0
	elif _is_fading_out:
		# ---- Fade out before despawn ----
		_fade_timer += delta
		_set_visual_alpha(clampf(1.0 - _fade_timer / _fade_duration, 0.0, 1.0))
