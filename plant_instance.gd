extends StaticBody3D
class_name PlantInstance

## Generic growing-plant node. Works for every entry in PlantDB — nothing
## here is specific to potato/coconut/banana; all the differences come from
## the Dictionary returned by PlantDB.get_def(id).
##
## Stages: SEED -> SPROUT -> GROWING -> MATURE
##   ROOT plants:  MATURE = ready to dig (hold E). Digging removes the plant.
##   FRUIT_TREE:   MATURE = trunk+canopy grown; individual fruit slots cycle
##                 empty -> ripening -> ready on their own timers. Tap E near
##                 a ready fruit to pick it (tree stays). Aim at the trunk and
##                 hold E to chop the tree down for wood (tree is removed).

enum Stage { SEED, SPROUT, GROWING, MATURE }

@export var plant_id: String = ""

var _def: Dictionary = {}
var _stage: int = Stage.SEED
var _stage_timer: float = 0.0

var _visual: Node3D = null
var _col_shape: CollisionShape3D = null

# One entry per fruit slot:
# {"pos": Vector3 (local), "state": "empty"/"ripening"/"ready", "timer": float, "marker": MeshInstance3D}
var _fruits: Array = []

# Hold-to-harvest state (chop / dig)
var _holding: bool = false
var _hold_progress: float = 0.0
var _hold_target: float = 1.0
var _hold_kind: String = ""
var _chop_hits_done: int = 0

var _player: Node3D = null
var _progress_ui: Control = null
var _progress_bar: ColorRect = null
var _prompt_label: Label = null


func _ready() -> void:
	add_to_group("plant")
	collision_layer = 1
	collision_mask = 0
	_def = PlantDB.get_def(plant_id)
	if _def.is_empty():
		push_warning("[Plant] Unknown plant_id: " + plant_id)
		queue_free()
		return
	_col_shape = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)
	_col_shape.shape = shape
	_col_shape.position = Vector3(0, 0.25, 0)
	add_child(_col_shape)
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_rebuild_visual()
	_build_progress_ui()


func _stage_time(idx: int) -> float:
	var arr: Array = _def.get("grow_stage_time", [15.0, 25.0, 20.0])
	if idx < 0 or idx >= arr.size():
		return 20.0
	return float(arr[idx])


func _process(delta: float) -> void:
	if _stage != Stage.MATURE:
		_stage_timer += delta
		var needed: float = _stage_time(_stage)
		if _stage_timer >= needed:
			_stage_timer = 0.0
			_stage += 1
			_rebuild_visual()
			_play_grow_pop()
	elif _def.get("category", "") == PlantDB.Category.FRUIT_TREE:
		_update_fruits(delta)
	_update_interaction(delta)


# ============================================================
# VISUALS
# ============================================================
func _rebuild_visual() -> void:
	for c in _visual.get_children():
		c.queue_free()
	_fruits.clear()
	var cat: String = _def.get("category", "")
	var scale_by_stage := {Stage.SEED: 0.08, Stage.SPROUT: 0.32, Stage.GROWING: 0.65, Stage.MATURE: 1.0}
	var s: float = scale_by_stage.get(_stage, 1.0)

	if cat == PlantDB.Category.ROOT:
		_build_root_visual(s)
	else:
		_build_tree_visual(s)

	if _stage == Stage.MATURE and cat == PlantDB.Category.FRUIT_TREE:
		_init_fruit_slots()


func _build_root_visual(s: float) -> void:
	var leaf_col: Color = _def.get("leaf_color", Color(0.25, 0.55, 0.2))
	var n := clampi(3 + int(s * 3.0), 2, 6)
	for i in n:
		var blade := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.015 * maxf(s, 0.3)
		cyl.bottom_radius = 0.03 * maxf(s, 0.3)
		cyl.height = 0.35 * s + 0.05
		blade.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = leaf_col.lightened(randf() * 0.12)
		blade.material_override = mat
		var ang: float = float(i) / float(n) * TAU
		blade.position = Vector3(cos(ang) * 0.06 * s, cyl.height * 0.5, sin(ang) * 0.06 * s)
		blade.rotation = Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
		_visual.add_child(blade)


func _build_tree_visual(s: float) -> void:
	var trunk_h: float = float(_def.get("trunk_height", 2.2)) * s
	var trunk_r: float = float(_def.get("trunk_radius", 0.13))
	var canopy_r: float = float(_def.get("canopy_radius", 0.9)) * s

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
	_visual.add_child(trunk)

	if _stage >= Stage.GROWING:
		var canopy := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = maxf(canopy_r, 0.05)
		sph.height = sph.radius * 2.0
		canopy.mesh = sph
		canopy.position = Vector3(0, trunk_h + canopy_r * 0.6, 0)
		canopy.name = "Canopy"
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = _def.get("canopy_color", Color(0.2, 0.5, 0.2))
		canopy.material_override = cmat
		_visual.add_child(canopy)

	if _col_shape != null and _col_shape.shape is BoxShape3D:
		var box := _col_shape.shape as BoxShape3D
		box.size = Vector3(maxf(canopy_r * 1.6, 0.4), maxf(trunk_h + canopy_r, 0.5), maxf(canopy_r * 1.6, 0.4))
		_col_shape.position = Vector3(0, box.size.y * 0.5, 0)


func _init_fruit_slots() -> void:
	var canopy: Node3D = _visual.get_node_or_null("Canopy")
	if canopy == null:
		return
	var count: int = int(_def.get("fruit_count", 4))
	var canopy_r: float = float(_def.get("canopy_radius", 0.9))
	for i in count:
		var ang: float = float(i) / float(count) * TAU
		var local_pos: Vector3 = canopy.position + Vector3(cos(ang) * canopy_r * 0.75, -canopy_r * 0.15, sin(ang) * canopy_r * 0.75)
		_fruits.append({
			"pos": local_pos,
			"state": "ripening",
			"timer": randf_range(0.0, float(_def.get("fruit_regrow_time", 60.0)) * 0.5),
			"marker": null,
		})
	_refresh_fruit_meshes()


func _refresh_fruit_meshes() -> void:
	for f in _fruits:
		var m = f.get("marker")
		if m != null and is_instance_valid(m):
			m.queue_free()
		f["marker"] = null
	var fruit_r: float = float(_def.get("fruit_radius", 0.1))
	var fruit_col: Color = _def.get("fruit_color", Color(0.8, 0.6, 0.2))
	for f in _fruits:
		if f["state"] != "ready":
			continue
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = fruit_r
		sph.height = fruit_r * 2.0
		mi.mesh = sph
		mi.position = f["pos"]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = fruit_col
		mat.emission_enabled = true
		mat.emission = fruit_col * 0.25
		mi.material_override = mat
		_visual.add_child(mi)
		f["marker"] = mi


func _update_fruits(delta: float) -> void:
	var regrow: float = float(_def.get("fruit_regrow_time", 60.0))
	var changed := false
	for f in _fruits:
		if f["state"] == "ready":
			continue
		f["timer"] = float(f["timer"]) + delta
		if f["timer"] >= regrow:
			f["timer"] = 0.0
			f["state"] = "ready"
			changed = true
	if changed:
		_refresh_fruit_meshes()


func _play_grow_pop() -> void:
	var tw := create_tween()
	_visual.scale = Vector3.ONE * 1.15
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK)


# ============================================================
# INTERACTION (self-managed — no player.gd changes needed for this part)
# ============================================================
func _get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
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
	return dist != null and float(dist) <= 3.0


func _nearest_ready_fruit(aim_local: Vector3) -> Dictionary:
	var best: float = INF
	var best_f = null
	for f in _fruits:
		if f["state"] != "ready":
			continue
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

	var aim_point = p.get("aim_point")
	var aim_local: Vector3 = global_transform.affine_inverse() * (aim_point as Vector3)
	var cat: String = _def.get("category", "")

	if cat == PlantDB.Category.FRUIT_TREE and _stage == Stage.MATURE:
		var near := _nearest_ready_fruit(aim_local)
		if float(near.get("dist", INF)) <= 0.35:
			_show_prompt("E — Pick " + str(_def.get("display_name", "Fruit")))
			if Input.is_action_just_pressed("interact"):
				_pick_fruit(near["fruit"])
			return

	if cat == PlantDB.Category.ROOT:
		if _stage != Stage.MATURE:
			_show_prompt("Growing...")
			return
		_show_prompt("Hold E — Dig up " + str(_def.get("display_name", "Plant")))
		_run_hold("dig", float(_def.get("dig_time", 1.5)), delta)
		return

	if cat == PlantDB.Category.FRUIT_TREE:
		if _stage != Stage.MATURE:
			_show_prompt("Growing...")
			return
		_show_prompt("Hold E — Chop for Wood")
		_run_hold("chop", 0.9, delta)
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
		if kind == "dig":
			_finish_dig()
		else:
			_finish_chop_hit()


func _cancel_hold() -> void:
	_holding = false
	_hold_kind = ""
	_hold_progress = 0.0
	if _progress_bar != null:
		_progress_bar.size.x = 0.0


func _pick_fruit(fruit) -> void:
	if fruit == null:
		return
	fruit["state"] = "empty"
	fruit["timer"] = 0.0
	var m = fruit.get("marker")
	if m != null and is_instance_valid(m):
		m.queue_free()
	fruit["marker"] = null
	var yield_item: String = _def.get("yield_item", "")
	var amt: int = randi_range(int(_def.get("yield_min", 1)), int(_def.get("yield_max", 1)))
	if yield_item != "":
		Inventory.add(yield_item, amt)
	_play_grow_pop()


func _finish_dig() -> void:
	_cancel_hold()
	var yield_item: String = _def.get("yield_item", "")
	var amt: int = randi_range(int(_def.get("yield_min", 1)), int(_def.get("yield_max", 1)))
	if yield_item != "":
		Inventory.add(yield_item, amt)
	var planter := get_parent().get_parent() as Planter
	if planter != null and planter.has_method("clear_plant"):
		planter.call("clear_plant")
	if _progress_ui != null:
		_progress_ui.queue_free()
	queue_free()


func _finish_chop_hit() -> void:
	_chop_hits_done += 1
	_play_grow_pop()
	var required: int = int(_def.get("chop_hits_required", 4))
	if _chop_hits_done >= required:
		var wood: int = int(_def.get("wood_yield", 6))
		Inventory.add("Wood", wood)
		var planter := get_parent().get_parent() as Planter
		if planter != null and planter.has_method("clear_plant"):
			planter.call("clear_plant")
		if _progress_ui != null:
			_progress_ui.queue_free()
		queue_free()
