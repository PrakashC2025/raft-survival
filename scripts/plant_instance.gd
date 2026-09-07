extends StaticBody3D
class_name PlantInstance

## Generic growing-plant node. Works for every entry in PlantDB — nothing
## here is specific to potato/coconut/banana; all the differences come from
## the Dictionary returned by PlantDB.get_def(id).
##
## Stages: SEED -> SPROUT -> GROWING -> MATURE
##   ROOT plants:  MATURE = ready to dig (hold E). Digging removes the plant.
##   FRUIT_TREE:   MATURE = trunk+canopy grown; fruit slots then progress
##                 bud -> small -> growing -> ripe on their own timers. Tap E
##                 near a ripe fruit to pick THAT fruit (tree stays, slot
##                 regrows). Aim at the trunk and hold E to chop; when the
##                 tree runs out of health it falls over and becomes a STUMP.
##
## Growth is not a static model swap: every stage is built from parts whose
## container scale animates continuously through the stage, so the plant
## visibly grows rather than popping. Trees get a gentle wind sway.

enum Stage { SEED, SPROUT, GROWING, MATURE, FALLING, STUMP }

const CAT_ROOT := "ROOT"
const CAT_FRUIT := "FRUIT_TREE"
# Height fraction reached at the END of each stage (indexed by Stage.SEED..MATURE)
const STAGE_FRAC := [0.06, 0.22, 0.55, 1.0]

@export var plant_id: String = ""

var _def: Dictionary = {}
var _db: Node = null
var _stage: int = Stage.SEED
var _stage_timer: float = 0.0
var _grow: float = STAGE_FRAC[0]   # current visual growth scale (continuous)

var _visual: Node3D = null
var _container: Node3D = null      # scaled stage content (whole-plant growth)
var _col_shape: CollisionShape3D = null

# Deterministic per-plant variation (stable for the life of the plant)
var _rng := RandomNumberGenerator.new()
var _hvar: float = 1.0             # height variation 0.93..1.07
var _wind_phase: float = 0.0
var _wind_phase2: float = 0.0
var _wind_freq: float = 1.0

# One entry per fruit slot:
# {"pos": Vector3 (local), "elapsed": float, "regrow": float, "mesh": MeshInstance3D}
var _fruits: Array = []

# Hold-to-harvest state (chop / dig / stump removal)
var _holding: bool = false
var _hold_progress: float = 0.0
var _hold_target: float = 1.0
var _hold_kind: String = ""
var _health: int = 0
var _fell_axis: Vector3 = Vector3.FORWARD

# Small debris chips (wood/soil) flying briefly after hits
var _chips: Array = []

var _player: Node3D = null
var _progress_ui: Control = null
var _progress_bar: ColorRect = null
var _prompt_label: Label = null
var _anim_t: float = 0.0


func _ready() -> void:
	add_to_group("plant")
	collision_layer = 1
	collision_mask = 0
	# Resolve the PlantDB autoload at RUNTIME (/root) rather than by the global
	# identifier: class_name scripts are parsed before autoload names exist in
	# a freshly-loaded editor, which used to raise "PlantDB not declared".
	_db = get_node_or_null("/root/PlantDB")
	if _db == null:
		push_warning("[Plant] PlantDB autoload missing")
		queue_free()
		return
	_def = _db.get_def(plant_id)
	if _def.is_empty():
		push_warning("[Plant] Unknown plant_id: " + plant_id)
		queue_free()
		return
	# Deterministic variation: same plant always looks the same, different
	# plants of the same type differ slightly.
	_rng.seed = int(get_instance_id())
	_hvar = 1.0 + _rng.randf_range(-0.07, 0.07)
	_wind_phase = _rng.randf_range(0.0, TAU)
	_wind_phase2 = _rng.randf_range(0.0, TAU)
	_wind_freq = _rng.randf_range(0.9, 1.3)
	_health = int(_def.get("chop_hits_required", 4))

	_col_shape = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)
	_col_shape.shape = shape
	_col_shape.position = Vector3(0, 0.25, 0)
	add_child(_col_shape)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_container = Node3D.new()
	_container.name = "StageMesh"
	_visual.add_child(_container)
	_grow = STAGE_FRAC[Stage.SEED]
	_container.scale = Vector3(_grow, _grow, _grow)
	_rebuild_visual()
	_build_progress_ui()


# ============================================================
# GROWTH
# ============================================================
func _stage_time(idx: int) -> float:
	var arr: Array = _def.get("grow_stage_time", [15.0, 25.0, 20.0])
	if idx < 0 or idx >= arr.size():
		return 20.0
	return float(arr[idx])


func _process(delta: float) -> void:
	_anim_t += delta
	_update_chips(delta)

	if _stage == Stage.FALLING or _stage == Stage.STUMP:
		_update_interaction(delta)
		return

	# --- Continuous growth: advance the stage timer and, while not mature,
	#     keep the container scale interpolating through the stage so the
	#     plant grows smoothly instead of popping between models.
	if _stage < Stage.MATURE:
		_stage_timer += delta
		var needed: float = _stage_time(_stage)
		if _stage_timer >= needed:
			_stage_timer = 0.0
			_stage += 1
			_rebuild_visual()
			_grow = STAGE_FRAC[clampi(_stage, 0, 3)]
			_container.scale = Vector3(_grow, _grow, _grow)
			_play_grow_pop()
		else:
			var from: float = STAGE_FRAC[_stage]
			var to: float = STAGE_FRAC[clampi(_stage + 1, 0, 3)]
			_grow = lerpf(from, to, clampf(_stage_timer / needed, 0.0, 1.0))
			_container.scale = Vector3(_grow, _grow, _grow)
	elif _def.get("category", "") == CAT_FRUIT:
		_update_fruits(delta)

	_update_wind(delta)
	_update_interaction(delta)


func _update_wind(_delta: float) -> void:
	if _stage == Stage.FALLING or _stage == Stage.STUMP:
		return
	var t := _anim_t
	# Gentle irregular sway — stronger for tall plants. Base sway is small so
	# the plant feels alive without looking storm-tossed.
	var height_amp: float = 0.02 + minf(0.035, float(_def.get("trunk_height", 0.6)) * 0.012 * _hvar)
	var rot_z := sin(t * _wind_freq + _wind_phase) * height_amp \
		+ sin(t * _wind_freq * 0.53 + _wind_phase2) * height_amp * 0.5
	var rot_x := sin(t * _wind_freq * 0.71 + _wind_phase2) * height_amp * 0.35
	_visual.rotation = Vector3(rot_x, 0.0, rot_z)
	_visual.rotation.y = 0.0


# ============================================================
# VISUALS
# ============================================================
func _rebuild_visual() -> void:
	for c in _container.get_children():
		c.queue_free()
	_fruits.clear()
	var cat: String = _def.get("category", "")
	if _stage >= Stage.FALLING:
		return
	if _stage == Stage.STUMP:
		_build_stump_visual()
		return
	if cat == CAT_ROOT:
		_build_root_visual(_stage)
	else:
		_build_tree_visual(_stage)
	if _stage == Stage.MATURE and cat == CAT_FRUIT:
		_init_fruit_slots()


func _grow_y(v: float) -> float:
	# bakes in per-plant height variation
	return v * _hvar


func _root_leaf_count(stage: int) -> int:
	match stage:
		Stage.SPROUT:
			return 3
		Stage.GROWING:
			return 5
		Stage.MATURE:
			return 7
		_:
			return 0


func _build_root_visual(stage: int) -> void:
	# SEED: a tiny seed bump half-sunk in the soil (no above-ground leaves).
	if stage == Stage.SEED:
		var seed_mesh := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.035
		sph.height = sph.radius * 2.0
		seed_mesh.mesh = sph
		seed_mesh.position = Vector3(0, 0.015, 0)
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.42, 0.32, 0.16)
		seed_mesh.material_override = smat
		_container.add_child(seed_mesh)
		return

	var leaf_col: Color = _def.get("leaf_color", Color(0.25, 0.55, 0.2))
	# Mature potato foliage reads slightly brighter/yellower = harvest-ready.
	if stage == Stage.MATURE:
		leaf_col = leaf_col.lightened(0.08)
	var n := _root_leaf_count(stage)
	var blade_h: float = 0.42 * _hvar
	for i in n:
		var blade := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.012
		cyl.bottom_radius = 0.028
		cyl.height = blade_h
		blade.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = leaf_col.lightened(_rng.randf_range(0.0, 0.12))
		blade.material_override = mat
		var ang: float = float(i) / float(n) * TAU + _rng.randf_range(-0.3, 0.3)
		var r: float = _rng.randf_range(0.03, 0.07)
		blade.position = Vector3(cos(ang) * r, blade_h * 0.5, sin(ang) * r)
		blade.rotation = Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35))
		_container.add_child(blade)
	# Mature ready cue: two tiny pale tuber bumps at the base.
	if stage == Stage.MATURE:
		for k in 2:
			var bump := MeshInstance3D.new()
			var bs := SphereMesh.new()
			bs.radius = 0.022
			bs.height = 0.044
			bump.mesh = bs
			var a: float = TAU * 0.5 * float(k) + 0.7
			bump.position = Vector3(cos(a) * 0.045, 0.012, sin(a) * 0.045)
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color(0.55, 0.44, 0.26)
			bump.material_override = bmat
			_container.add_child(bump)


func _build_tree_visual(stage: int) -> void:
	var trunk_h: float = _grow_y(float(_def.get("trunk_height", 2.2)))
	var trunk_r: float = float(_def.get("trunk_radius", 0.13))
	var canopy_r: float = _grow_y(float(_def.get("canopy_radius", 0.9)))

	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = trunk_r * 0.8
	cyl.bottom_radius = trunk_r
	cyl.height = maxf(trunk_h, 0.05)
	trunk.mesh = cyl
	trunk.position = Vector3(0, cyl.height * 0.5, 0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = _def.get("trunk_color", Color(0.5, 0.36, 0.2))
	trunk.material_override = tmat
	_container.add_child(trunk)

	if stage >= Stage.GROWING:
		var canopy := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = maxf(canopy_r, 0.05)
		sph.height = sph.radius * 2.0
		canopy.mesh = sph
		canopy.position = Vector3(0, trunk_h + canopy_r * 0.55, 0)
		canopy.name = "Canopy"
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = _def.get("canopy_color", Color(0.2, 0.5, 0.2))
		canopy.material_override = cmat
		_container.add_child(canopy)

	_update_collision()


func _update_collision() -> void:
	if _col_shape == null or not (_col_shape.shape is BoxShape3D):
		return
	var box := _col_shape.shape as BoxShape3D
	if _stage == Stage.STUMP:
		box.size = Vector3(0.4, 0.3, 0.4)
		_col_shape.position = Vector3(0, 0.15, 0)
		return
	var trunk_h: float = _grow_y(float(_def.get("trunk_height", 2.2)))
	var canopy_r: float = _grow_y(float(_def.get("canopy_radius", 0.9)))
	box.size = Vector3(maxf(canopy_r * 1.5, 0.4), maxf(trunk_h + canopy_r, 0.5), maxf(canopy_r * 1.5, 0.4))
	_col_shape.position = Vector3(0, box.size.y * 0.5, 0)


func _build_stump_visual() -> void:
	var trunk_r: float = float(_def.get("trunk_radius", 0.13))
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = trunk_r * 0.95
	cyl.bottom_radius = trunk_r * 1.25
	cyl.height = 0.3
	base.mesh = cyl
	base.position = Vector3(0, 0.15, 0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = _def.get("trunk_color", Color(0.5, 0.36, 0.2)).darkened(0.15)
	base.material_override = tmat
	_container.add_child(base)
	# Fresh lighter cut surface on top.
	var cap := MeshInstance3D.new()
	var capm := CylinderMesh.new()
	capm.top_radius = trunk_r * 0.8
	capm.bottom_radius = trunk_r * 0.9
	capm.height = 0.03
	cap.mesh = capm
	cap.position = Vector3(0, 0.3, 0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.68, 0.55, 0.36)
	cap.material_override = cmat
	_container.add_child(cap)
	_update_collision()


# ============================================================
# FRUITS — per-slot progression: bud -> small -> growing -> ripe
# ============================================================
func _init_fruit_slots() -> void:
	var canopy: Node3D = _container.get_node_or_null("Canopy")
	if canopy == null:
		return
	var count: int = int(_def.get("fruit_count", 4))
	var canopy_r: float = _grow_y(float(_def.get("canopy_radius", 0.9)))
	var regrow: float = float(_def.get("fruit_regrow_time", 60.0))
	for i in count:
		var ang: float = float(i) / float(count) * TAU + _rng.randf_range(-0.25, 0.25)
		var jitter: float = _rng.randf_range(0.62, 0.82)
		var local_pos: Vector3 = canopy.position \
			+ Vector3(cos(ang) * canopy_r * jitter, -canopy_r * _rng.randf_range(0.1, 0.25), sin(ang) * canopy_r * jitter)
		# Staggered start so fruits reach ripeness at different times.
		var slot_regrow: float = regrow * _rng.randf_range(0.9, 1.1)
		_fruits.append({
			"pos": local_pos,
			"elapsed": _rng.randf_range(0.0, regrow * 0.5),
			"regrow": slot_regrow,
			"mesh": null,
		})


func _fruit_green() -> Color:
	# Young fruit is green regardless of its ripe color.
	return Color(0.3, 0.45, 0.22)


func _update_fruits(delta: float) -> void:
	for f in _fruits:
		f["elapsed"] = float(f["elapsed"]) + delta
		var regrow: float = float(f["regrow"])
		var prog: float = clampf(float(f["elapsed"]) / regrow, 0.0, 1.0)
		var m: MeshInstance3D = f.get("mesh")
		if prog < 0.06:
			if m != null and is_instance_valid(m):
				m.queue_free()
				f["mesh"] = null
			continue
		if m == null or not is_instance_valid(m):
			m = _make_fruit_mesh()
			f["mesh"] = m
			_container.add_child(m)
		m.position = f["pos"]
		var ripe_col: Color = _def.get("fruit_color", Color(0.8, 0.6, 0.2))
		var size_t := prog * prog * (3.0 - 2.0 * prog)  # smoothstep ease
		m.scale = Vector3.ONE * (0.35 + 0.65 * size_t)
		# Color drifts from green toward the ripe fruit color as it matures.
		var color_t: float = clampf((prog - 0.15) / 0.85, 0.0, 1.0)
		var mat: StandardMaterial3D = m.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = _fruit_green().lerp(ripe_col, color_t)
			mat.emission = (ripe_col * 0.18) * color_t
		m.visible = true


func _make_fruit_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	var fruit_r: float = float(_def.get("fruit_radius", 0.1))
	sph.radius = fruit_r
	sph.height = fruit_r * 2.0
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _fruit_green()
	mat.emission_enabled = true
	mat.emission = Color(0, 0, 0)
	mi.material_override = mat
	return mi


# ============================================================
# SMALL EFFECTS
# ============================================================
func _play_grow_pop() -> void:
	# Gentle settle bump on stage change so growth reads as alive, not a pop.
	var tw := create_tween()
	var base: Vector3 = Vector3(_grow, _grow, _grow)
	_container.scale = base * 1.12
	tw.tween_property(_container, "scale", base, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spawn_chips(color: Color, count: int, spread: float) -> void:
	if count <= 0:
		return
	for i in count:
		var chip := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.03, 0.03, 0.03) * _rng.randf_range(0.6, 1.4)
		chip.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.lightened(_rng.randf_range(-0.08, 0.1))
		chip.material_override = mat
		chip.position = Vector3(0, 0.4, 0)
		add_child(chip)
		var vel := Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(1.2, 2.2), _rng.randf_range(-spread, spread))
		_chips.append({"node": chip, "vel": vel, "life": _rng.randf_range(0.35, 0.6)})


func _update_chips(delta: float) -> void:
	var keep: Array = []
	for c in _chips:
		var node: Node3D = c["node"]
		if node == null or not is_instance_valid(node):
			continue
		c["life"] = float(c["life"]) - delta
		if float(c["life"]) <= 0.0:
			node.queue_free()
			continue
		c["vel"] = Vector3(c["vel"]) + Vector3(0, -9.0, 0) * delta
		node.position += Vector3(c["vel"]) * delta
		node.rotation.y += delta * 6.0
		keep.append(c)
	_chips = keep


# ============================================================
# INTERACTION (self-managed — uses the player's center crosshair raycast)
# ============================================================
func _get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _build_progress_ui() -> void:
	var p := _get_player()
	if p == null:
		return
	var canvas: Node = p.get_node_or_null("CanvasLayer")
	if canvas == null:
		return
	_progress_ui = Control.new()
	_progress_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_progress_ui.visible = false
	canvas.add_child(_progress_ui)

	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.4)
	back.size = Vector2(180, 14)
	_progress_ui.add_child(back)

	_progress_bar = ColorRect.new()
	_progress_bar.color = Color(0.4, 0.9, 0.4, 0.9)
	_progress_bar.size = Vector2(0, 14)
	_progress_ui.add_child(_progress_bar)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_progress_ui.add_child(_prompt_label)

	var vp := p.get_viewport().get_visible_rect().size
	back.position = Vector2(vp.x * 0.5 - 90.0, vp.y * 0.62)
	_progress_bar.position = back.position
	_prompt_label.position = Vector2(back.position.x, back.position.y - 22.0)


func _is_player_aiming_here() -> bool:
	var p := _get_player()
	if p == null:
		return false
	if p.get("build_mode") == true or p.get("_editing") != null:
		return false
	if p.get("aim_valid") != true:
		return false
	if p.get("aim_collider") != self:
		return false
	var dist = p.get("aim_distance")
	return dist != null and float(dist) <= 3.5


func _aim_local() -> Vector3:
	var p := _get_player()
	if p == null:
		return Vector3.ZERO
	var aim_point: Variant = p.get("aim_point")
	if aim_point is Vector3:
		return global_transform.affine_inverse() * (aim_point as Vector3)
	return Vector3.ZERO


# The exact fruit the crosshair points at = the ripe fruit whose position is
# nearest to the raycast hit point on the plant (within reach).
func _nearest_ripe_fruit() -> Dictionary:
	var aim_local := _aim_local()
	var best: float = 0.55
	var best_f = null
	for f in _fruits:
		var regrow: float = float(f["regrow"])
		if float(f["elapsed"]) < regrow:
			continue  # not ripe yet
		var d: float = (f["pos"] - aim_local).length()
		if d < best:
			best = d
			best_f = f
	return {"dist": best, "fruit": best_f}


func _update_interaction(delta: float) -> void:
	var p := _get_player()
	if p == null:
		return
	var aiming: bool = _is_player_aiming_here()
	if not aiming:
		if _holding:
			_cancel_hold()
		if _progress_ui != null:
			_progress_ui.visible = false
		return

	var cat: String = _def.get("category", "")

	# Stump: hold E to clear it and free the planter for a new seed.
	if _stage == Stage.STUMP:
		_show_prompt("Hold E — Remove Stump")
		_run_hold("stump", 0.6, delta)
		return

	if _stage == Stage.FALLING:
		return

	if cat == CAT_FRUIT and _stage == Stage.MATURE:
		var near := _nearest_ripe_fruit()
		if near["fruit"] != null:
			_show_prompt("E — Pick " + str(_def.get("display_name", "Fruit")))
			if Input.is_action_just_pressed("interact"):
				_pick_fruit(near["fruit"])
			return
		_show_prompt("Hold E — Chop for Wood")
		_run_hold("chop", 0.9, delta)
		return

	if cat == CAT_ROOT:
		if _stage != Stage.MATURE:
			_show_prompt("Growing...")
			return
		_show_prompt("Hold E — Dig up " + str(_def.get("display_name", "Plant")))
		_run_hold("dig", float(_def.get("dig_time", 1.5)), delta)
		return

	if cat == CAT_FRUIT:
		_show_prompt("Growing...")
		return


func _show_prompt(text: String) -> void:
	if _progress_ui == null:
		return
	_progress_ui.visible = true
	_prompt_label.text = text


func _run_hold(kind: String, per_hit_time: float, delta: float) -> void:
	if not Input.is_action_pressed("interact"):
		if _holding:
			_cancel_hold()
		return
	if not _holding or _hold_kind != kind:
		_holding = true
		_hold_kind = kind
		_hold_progress = 0.0
		_hold_target = per_hit_time
	_hold_progress += delta
	if _progress_bar != null:
		_progress_bar.size.x = 180.0 * clampf(_hold_progress / _hold_target, 0.0, 1.0)
	if _hold_progress >= _hold_target:
		_hold_progress = 0.0
		match kind:
			"dig":
				_do_dig()
			"chop":
				_do_chop_hit()
			"stump":
				_do_remove_stump()


func _cancel_hold() -> void:
	_holding = false
	_hold_kind = ""
	_hold_progress = 0.0
	if _progress_bar != null:
		_progress_bar.size.x = 0.0


# ============================================================
# HARVEST — fruit pick
# ============================================================
func _pick_fruit(fruit) -> void:
	if fruit == null:
		return
	fruit["elapsed"] = 0.0
	var m = fruit.get("mesh")
	if m != null and is_instance_valid(m):
		m.queue_free()
	fruit["mesh"] = null
	var yield_item: String = _def.get("yield_item", "")
	var amt: int = randi_range(int(_def.get("yield_min", 1)), int(_def.get("yield_max", 1)))
	if yield_item != "":
		Inventory.add(yield_item, amt)
	_spawn_chips(_def.get("fruit_color", Color(0.8, 0.6, 0.2)), 3, 0.25)


# ============================================================
# HARVEST — root crop dig (plant shrinks back, planter freed)
# ============================================================
func _do_dig() -> void:
	_cancel_hold()
	var tw := create_tween()
	tw.tween_property(_container, "scale", Vector3.ONE * 0.04, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_finish_dig)


func _finish_dig() -> void:
	var yield_item: String = _def.get("yield_item", "")
	var amt: int = randi_range(int(_def.get("yield_min", 1)), int(_def.get("yield_max", 1)))
	if yield_item != "":
		Inventory.add(yield_item, amt)
	_spawn_chips(Color(0.32, 0.22, 0.14), 4, 0.35)
	var planter := get_parent().get_parent() as Planter
	if planter != null and planter.has_method("clear_plant"):
		planter.call("clear_plant")
	if _progress_ui != null:
		_progress_ui.queue_free()
	queue_free()


# ============================================================
# CUTTING — health-based, configurable via PlantDB
# ============================================================
func _do_chop_hit() -> void:
	_health -= 1
	var trunk_col: Color = _def.get("trunk_color", Color(0.5, 0.36, 0.2))
	_spawn_chips(trunk_col.lightened(0.15), 4, 0.3)
	# Small trunk reaction so the hit visibly registers (no camera shake).
	if is_instance_valid(_container):
		var tw := create_tween()
		_container.rotation.z += 0.06
		tw.tween_property(_container, "rotation:z", 0.0, 0.18)
	if _health <= 0:
		_start_fall()


func _start_fall() -> void:
	_cancel_hold()
	_stage = Stage.FALLING
	# Fall away from the player.
	var p := _get_player()
	var away := Vector3.FORWARD
	if p != null:
		var d: Vector3 = global_position - p.global_position
		if d.length() > 0.1:
			away = Vector3(d.x, 0.0, d.z).normalized()
	_fell_axis = Vector3(away.z, 0.0, -away.x).normalized()
	_visual.rotation = Vector3.ZERO
	var tw := create_tween()
	var target_ang: float = PI * 0.5 * 0.95
	tw.tween_method(_apply_fall, 0.0, target_ang, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_finish_fell)


func _apply_fall(a: float) -> void:
	_visual.rotation = Vector3.ZERO
	_visual.rotate(_fell_axis, a)


func _finish_fell() -> void:
	# Resources drop (configurable per plant in PlantDB.fell_drops).
	var drops: Array = _def.get("fell_drops", [])
	for d in drops:
		if not (d is Array) or d.size() < 3:
			continue
		var item_name: String = str(d[0])
		var amt: int = randi_range(int(d[1]), int(d[2]))
		if amt > 0:
			Inventory.add(item_name, amt)
	_spawn_chips(_def.get("trunk_color", Color(0.5, 0.36, 0.2)).darkened(0.1), 6, 0.5)
	_stage = Stage.STUMP
	for c in _container.get_children():
		c.queue_free()
	_fruits.clear()
	_build_stump_visual()
	_container.scale = Vector3.ONE
	_visual.rotation = Vector3.ZERO


func _do_remove_stump() -> void:
	_cancel_hold()
	var planter := get_parent().get_parent() as Planter
	if planter != null and planter.has_method("clear_plant"):
		planter.call("clear_plant")
	if _progress_ui != null:
		_progress_ui.queue_free()
	queue_free()
