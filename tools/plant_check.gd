extends Node
## Planted-plant growth check for every real-model plant (Coconut + Apple):
## forces every stage, verifies the REAL baked meshes are used, sway/frond
## overrides where expected, fruit anchoring, and the apple natural-fall.
## Run (real autoloads):
##   godot --path . res://tools/plant_check_scene.tscn

var _fails := 0

func _ready() -> void:
	await get_tree().process_frame
	if get_node_or_null("/root/PlantDB") == null:
		_fail("PlantDB autoload missing")
		_finish()
		return
	_check_coconut()
	await _check_apple()
	_finish()

func _check_coconut() -> void:
	var p := PlantInstance.new()
	p.plant_id = "Coconut"
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	if p._growth.is_empty():
		_fail("coconut: growth variants not loaded")
	else:
		_ok("coconut: growth variants loaded: %d stages" % p._growth.size())
	var expect_surfaces := {PlantInstance.Stage.SPROUT: 1, PlantInstance.Stage.GROWING: 5, PlantInstance.Stage.MATURE: 5}
	for st in [PlantInstance.Stage.SPROUT, PlantInstance.Stage.GROWING, PlantInstance.Stage.MATURE]:
		p._stage = st
		p._rebuild_visual()
		var mi := _newest_mi(p._container)
		if mi == null:
			_fail("coconut stage %d: no MeshInstance3D built" % st)
			continue
		if mi.mesh == null or mi.mesh != p._growth.get(st):
			_fail("coconut stage %d: stale/incorrect mesh displayed" % st)
			continue
		var want: int = expect_surfaces[st]
		if mi.mesh.get_surface_count() != want:
			_fail("coconut stage %d: %d surfaces (want %d)" % [st, mi.mesh.get_surface_count(), want])
		else:
			_ok("coconut stage %d: real mesh, %d surfaces, top=%.2f m" % [st, mi.mesh.get_surface_count(), _top(mi.mesh)])
		if st != PlantInstance.Stage.SPROUT and not _has_shader_override(mi):
			_fail("coconut stage %d: no sway ShaderMaterial override on fronds" % st)
		elif st != PlantInstance.Stage.SPROUT:
			_ok("coconut stage %d: frond sway override present" % st)
	if p._fruits.is_empty():
		_fail("coconut mature: no fruit slots")
	else:
		var low := false
		for f in p._fruits:
			if (f["pos"] as Vector3).y < p._tree_top * 0.4:
				low = true
		if low:
			_fail("coconut: fruit ring positioned too low")
		else:
			_ok("coconut: %d fruit slots hang under the crown" % p._fruits.size())
	var box := p._col_shape.shape as BoxShape3D
	if box != null and box.size.y >= p._tree_top * 0.9:
		_ok("coconut: collision %.1f m matches the model" % box.size.y)
	else:
		_fail("coconut: collision box not sized from the real model")
	p.queue_free()

func _check_apple() -> void:
	await get_tree().process_frame
	var p := PlantInstance.new()
	p.plant_id = "Apple"
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	if p._growth.is_empty():
		_fail("apple: growth variant not loaded")
		p.queue_free()
		return
	_ok("apple: growth variant loaded")
	for st in [PlantInstance.Stage.SPROUT, PlantInstance.Stage.GROWING, PlantInstance.Stage.MATURE]:
		p._stage = st
		p._rebuild_visual()
		var mi := _newest_mi(p._container)
		if mi == null or mi.mesh != p._growth.get(st):
			_fail("apple stage %d: wrong mesh displayed" % st)
			continue
		if mi.mesh.get_surface_count() != 3: # bark + leaves + fruiting twigs
			_fail("apple stage %d: %d surfaces (want 3)" % [st, mi.mesh.get_surface_count()])
		else:
			_ok("apple stage %d: real mesh, 3 surfaces, scale %.2f" % [st, p._container.scale.x])
	# Mature: real apple mesh + slots in the crown.
	p._stage = PlantInstance.Stage.MATURE
	p._rebuild_visual()
	if p._fruits.is_empty():
		_fail("apple mature: no fruit slots")
	else:
		var in_crown := 0
		for f in p._fruits:
			var pos: Vector3 = f["pos"]
			if pos.y > p._tree_top * 0.4:
				in_crown += 1
		if in_crown == p._fruits.size():
			_ok("apple: %d fruit slots scattered in the crown" % p._fruits.size())
		else:
			_fail("apple: fruit outside the crown (%d/%d ok)" % [in_crown, p._fruits.size()])
	# Force-ripe one slot and trigger the natural fall.
	var f0: Dictionary = p._fruits[0]
	f0["elapsed"] = float(f0["regrow"]) + float(p._def.get("fruit_fall_delay", 20.0)) + 0.1
	f0["fall_at"] = float(f0["elapsed"]) - 0.05
	var before := get_tree().get_nodes_in_group("debris").size()
	p._update_fruits(0.016)
	await get_tree().process_frame
	var after := get_tree().get_nodes_in_group("debris").size()
	if after > before:
		_ok("apple natural fall: ripe apple dropped as a collectible pickup")
	else:
		_fail("apple natural fall: no ApplePickup spawned")
	p.queue_free()

func _newest_mi(n: Node) -> MeshInstance3D:
	var found: MeshInstance3D = null
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		found = n
	for c in n.get_children():
		var r := _newest_mi(c)
		if r != null:
			found = r
	return found

func _has_shader_override(mi: MeshInstance3D) -> bool:
	for s in mi.mesh.get_surface_count():
		if mi.get_surface_override_material(s) is ShaderMaterial:
			return true
	return false

func _top(m: Mesh) -> float:
	var aabb := m.get_aabb()
	return aabb.position.y + aabb.size.y

func _ok(msg: String) -> void:
	print("PLANTCHECK ok: " + msg)

func _fail(msg: String) -> void:
	_fails += 1
	printerr("PLANTCHECK FAIL: " + msg)

func _finish() -> void:
	if _fails == 0:
		print("PLANTCHECK PASSED")
		get_tree().quit(0)
	else:
		printerr("PLANTCHECK FAILED (%d)" % _fails)
		get_tree().quit(1)
