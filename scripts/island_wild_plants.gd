extends Node3D
## Shared owner-supplied meshes, individually clearable ground and crop-safe regrowth.
const KIT := preload("res://models/island_lowpoly_plants.glb")
const TARGET := preload("res://scripts/wild_plant_target.gd")
const VARIANTS := ["CanopyA", "CanopyB", "ShrubA", "ShrubB", "TallGrass", "WildFlowers", "CloverA", "CloverB"]
const PLANT_COUNT := 44
const MAX_RECORDS := 64 # includes the existing palms and non-fruit grove trees
const TREE_COUNT := 10
const MASK_SIZE := 64
const FRAME_WORK_BUDGET := preload("res://scripts/frame_work_budget.gd")
static var meshes: Array[Mesh] = []
var records: Array[Dictionary] = []
var batches: Array[MultiMeshInstance3D] = []
var targets: Array[StaticBody3D] = []
var prepared := false
var radius := 15.0
var _tick := 0.0
var _cooldown := 0.0
var _crop_signature := ""
var _mask_dirty := true
var _mask: ImageTexture
var _mask_image: Image
var _crop_points: Array[Vector3] = []

func _ready() -> void:
	add_to_group("island_wild_plants")

func island_node() -> Node3D:
	return get_parent().get_parent() as Node3D

static func _prepare_meshes() -> void:
	if not meshes.is_empty(): return
	var source := KIT.instantiate()
	for label in VARIANTS:
		var part := source.find_child(label, true, false) as MeshInstance3D
		meshes.append(part.mesh if part != null else null)
	meshes[5]=preload("res://scripts/flower_visual.gd").meadow_mesh()
	source.free()

func prepare() -> void:
	_prepare_meshes()
	var island := island_node()
	radius = 28.0 if island.name=="SpringIsle" else (15.0 if island.name == "Island" else 9.0)
	var saved: Variant = Inventory.loaded_meta.get("wild_plants", {}).get(str(island.name), {})
	if saved is Dictionary and saved.get("records") is Array:
		_restore_records(saved.records)
	if records.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(island.get("pickup_seed")) + 48013
		var rays := 0
		for attempt in range(512):
			# Keep the landing beach and a central footpath open.
			var at := Vector3(rng.randf_range(-radius * 0.76, radius * 0.76), 0,
				rng.randf_range(-radius * 0.64, radius * 0.15))
			var tree := attempt < 128 and records.size() < TREE_COUNT
			if absf(at.x) < (1.35 if tree else 0.8): continue
			var from := to_global(at)
			var hit := get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(Vector3(from.x,26,from.z),Vector3(from.x,-28,from.z),1))
			rays += 1
			if not hit.is_empty() and Vector3(hit.position).y >= 0.48 and Vector3(hit.normal).y >= 0.72:
				at = to_local(Vector3(hit.position))
				var spaced := true
				for other in records:
					var separation := 1.75 if tree else (0.7 if int(other.kind)<2 else 0.65)
					if _flat_distance(at, other.at) < separation: spaced = false; break
				if spaced and _terrain_hit(hit.collider):
					var kind := rng.randi_range(0,1) if tree else rng.randi_range(2,7)
					if not tree and records.size() in [TREE_COUNT,TREE_COUNT+1]:kind=5
					records.append({"at":at,"kind":kind,"yaw":rng.randf()*TAU,"size":rng.randf_range(0.82,1.14),
						"growth":1.0,"wait":0.0,"health":4 if tree else 1,"cycle":0})
			# Four islands prepare concurrently; bound all terrain-query work.
			if FRAME_WORK_BUDGET.exhausted() or rays >= 16:
				rays = 0
				await get_tree().process_frame
				if not is_inside_tree(): return
			if records.size() >= PLANT_COUNT: break
	_register_existing_trees()
	_create_batches()
	_snapshot_crops()
	for index in records.size():
		_create_target(index)
		if _crop_at(records[index].at, int(records[index].kind) < 2):
			records[index].growth = 0.0
			records[index].cycle = maxi(1,int(records[index].cycle))
			records[index].wait = _delay(records[index])
		_sync(index)
		if FRAME_WORK_BUDGET.exhausted(4):
			await get_tree().process_frame
			if not is_inside_tree(): return
	prepared = true
	_refresh_clearings()
	var performance := get_tree().get_first_node_in_group("mobile_performance")
	if performance != null: performance.call("refresh_foliage")

func _existing_trees() -> Array[Node3D]:
	var trees: Array[Node3D] = []
	for child in island_node().get_children():
		if child is Node3D and child.name.begins_with("Palm"): trees.append(child)
	var grove := island_node().get_node_or_null("CoastalGrove")
	if grove != null:
		for child in grove.get_children():
			if child is Node3D and child.name.begins_with("WildTree"): trees.append(child)
	return trees

func _register_existing_trees() -> void:
	for tree in _existing_trees():
		var key := str(island_node().get_path_to(tree))
		var found := false
		for entry in records:
			if entry.get("external", "") == key: found=true;break
		if found or records.size()>=MAX_RECORDS: continue
		records.append({"at":to_local(tree.global_position),"kind":0,"yaw":0.0,"size":1.0,
			"growth":1.0,"wait":0.0,"health":4,"cycle":0,"external":key})

func _original_tree(entry: Dictionary) -> Node3D:
	var key := str(entry.get("external",""))
	if key.is_empty(): return null
	# Only known authored palms / non-fruit grove roots can be addressed by save data.
	for tree in _existing_trees():
		if str(island_node().get_path_to(tree)) == key: return tree
	return null

func _terrain_hit(body: Node) -> bool:
	var current := body
	while current != null and current != island_node():
		if current.is_in_group("plant") or current.is_in_group("ground_plot") or current.is_in_group("wild_plant") \
				or current.name.begins_with("Palm") or current.name == "IslandMountain" or current.name == "CoastalGrove": return false
		current = current.get_parent()
	return current == island_node()

func _create_batches() -> void:
	for kind in VARIANTS.size():
		var batch := MultiMeshInstance3D.new()
		batch.name = VARIANTS[kind]
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = meshes[kind]
		batch.multimesh.instance_count = records.size()
		batch.multimesh.custom_aabb = AABB(Vector3(-radius-5,-4,-radius-5),Vector3(radius*2+10,30,radius*2+10))
		for index in records.size():
			batch.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), records[index].at))
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.visibility_range_end = 110.0
		batch.visibility_range_end_margin = 8.0
		batch.set_meta("interactive_foliage", true)
		batch.add_to_group("island_landscape_foliage")
		add_child(batch)
		batches.append(batch)

func _create_target(index: int) -> void:
	var target := TARGET.new()
	target.name = "WildPlant%d" % index
	target.garden = self
	target.plant_index = index
	target.collision_mask = 0
	target.add_to_group("wild_plant")
	var shape := CollisionShape3D.new()
	if int(records[index].kind) < 2:
		var trunk := CapsuleShape3D.new()
		trunk.radius = 0.16
		trunk.height = 2.4
		shape.shape = trunk
		shape.position.y = 1.2
	else:
		var bush := CylinderShape3D.new()
		bush.radius = 0.38
		bush.height = 0.55
		shape.shape = bush
		shape.position.y = 0.275
	target.add_child(shape)
	add_child(target)
	targets.append(target)
	var original := _original_tree(records[index])
	if original != null:
		for body in original.find_children("*","StaticBody3D",true,false):
			body.set_script(TARGET)
			body.garden = self
			body.plant_index = index
			body.add_to_group("wild_plant")

func _sync(index: int) -> void:
	var entry := records[index]
	var growth := float(entry.growth)
	var visible_size := float(entry.size) * (lerpf(0.12,1.0,growth) if growth > 0.0 else 0.0)
	var transform_value := Transform3D(Basis(Vector3.UP,float(entry.yaw)).scaled(Vector3.ONE*visible_size),entry.at)
	var original := _original_tree(entry)
	var original_visible := original != null and int(entry.cycle)==0 and growth>0.0
	if original != null:
		original.visible = original_visible
		for body in original.find_children("*","StaticBody3D",true,false): body.collision_layer=1 if original_visible else 0
	for kind in batches.size():
		batches[kind].multimesh.set_instance_transform(index, transform_value if kind == int(entry.kind) and not original_visible
			else Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),entry.at))
	var target := targets[index]
	target.position = entry.at
	target.scale = Vector3.ONE * maxf(visible_size,0.001)
	# Shrubs are selectable but do not stop walking. Only visible trunks are solid.
	target.collision_layer = (3 if int(entry.kind)<2 else 2) if growth>0.0 and not original_visible else 0
	_mask_dirty = true

func _process(delta: float) -> void:
	if not prepared: return
	_cooldown = maxf(0.0,_cooldown-delta)
	if Input.is_action_pressed("interact") and _cooldown <= 0.0:
		var actor := get_tree().get_first_node_in_group("player") as Node3D
		if _can_use(actor):
			var target: Variant = actor.get("aim_collider")
			if is_instance_valid(target) and target.get_script() == TARGET and target.garden == self:
				collect(target.plant_index,actor)
	_tick += delta
	if _tick < 1.0: return
	var elapsed := _tick
	_tick = 0.0
	advance(elapsed)

func _can_use(actor: Node3D) -> bool:
	if actor == null or actor.get("build_mode") == true or actor.get("_editing") != null \
			or actor.get("aim_valid") != true or float(actor.get("aim_distance")) > 3.5: return false
	var hud := actor.get_node_or_null("CanvasLayer/SurvivalHUD")
	return hud == null or not hud.call("gameplay_input_blocked")

func caption(index: int) -> String:
	var entry := records[index]
	if int(entry.kind) < 2: return "CHOP %d/4" % (5-int(entry.health))
	return "GATHER PLANT"

func collect(index: int, actor: Node3D,animate: bool=true) -> bool:
	if index < 0 or index >= records.size() or not _can_use(actor) or _cooldown > 0.0: return false
	var aimed: Variant = actor.get("aim_collider")
	if not is_instance_valid(aimed) or aimed.get_script()!=TARGET or aimed.garden!=self \
			or aimed.plant_index!=index or float(records[index].growth) <= 0.0: return false
	var entry := records[index]
	var tree := int(entry.kind) < 2
	var rewards := {"Wood":4} if tree else {"Rope":1}
	var damage := 2 if tree and actor.get("active_item")=="Axe" and Inventory.has("Axe",1) else 1
	if int(entry.health) <= damage and not Inventory.try_exchange({},rewards):
		actor.call("_hud_toast","BAG FULL · CLEAR SPACE TO COLLECT")
		_cooldown = 0.8
		return false
	_cooldown = 0.8 if tree else 0.35
	if animate:actor.call("play_action","chop" if tree else "grab",0.65,to_global(entry.at))
	if tree:actor.call("play_world_sfx",preload("res://audio/chop.ogg"),-9.0)
	entry.health = int(entry.health)-damage
	if int(entry.health) <= 0:
		entry.growth = 0.0
		entry.wait = _delay(entry)
		entry.cycle = int(entry.cycle)+1
		entry.health = 4 if tree else 1
		_sync(index)
		_refresh_clearings()
		actor.call("_hud_toast","TREE CLEARED · +4 WOOD" if tree else "PLANT GATHERED · +1 ROPE")
	actor.call("_queue_save")
	return true

func _delay(entry: Dictionary) -> float:
	return 360.0 if int(entry.kind)<2 else 180.0

func _snapshot_crops() -> void:
	_crop_points.clear()
	for plot in get_tree().get_nodes_in_group("ground_plot"):
		if plot.is_queued_for_deletion() or not plot.has_plant(): continue
		_crop_points.append(plot.global_position)

func _crop_at(local_point: Vector3, tree: bool) -> bool:
	var at := to_global(local_point)
	for point in _crop_points:
		if _flat_distance(at,point) < (2.0 if tree else 1.15): return true
	return false

static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func blocks_crop(world_point: Vector3) -> bool:
	for entry in records:
		if float(entry.growth)>0.0 and _flat_distance(to_global(entry.at),world_point)<(2.0 if int(entry.kind)<2 else 1.15): return true
	return false

func _space_occupied(index: int) -> bool:
	var entry := records[index]
	var at := to_global(entry.at)
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5 if int(entry.kind)<2 else 0.35
	query.shape = sphere
	query.transform.origin = at+Vector3.UP*0.7
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for target in targets: exclude.append(target.get_rid())
	query.exclude = exclude
	for hit in get_world_3d().direct_space_state.intersect_shape(query,16):
		if not _terrain_hit(hit.collider): return true
	return false

func advance(elapsed: float) -> void:
	if not prepared or elapsed <= 0.0: return
	_snapshot_crops()
	for index in records.size():
		var entry := records[index]
		var tree := int(entry.kind)<2
		if _crop_at(entry.at,tree):
			if float(entry.growth)>0.0: entry.growth=0.0;entry.cycle=maxi(1,int(entry.cycle));_sync(index)
			entry.wait = _delay(entry)
			continue
		if float(entry.growth)>=1.0: continue
		var remaining := elapsed
		if float(entry.wait)>0.0:
			var previous_wait := float(entry.wait)
			entry.wait = maxf(0.0,previous_wait-elapsed)
			if float(entry.wait)>0.0: continue
			remaining = maxf(0.0,elapsed-previous_wait)
		if float(entry.growth)==0.0:
			if _space_occupied(index): entry.wait=5.0;continue
			var rng := RandomNumberGenerator.new()
			rng.seed = int(island_node().get("pickup_seed"))+index*7919+int(entry.cycle)*131
			entry.kind = rng.randi_range(0,1) if tree else rng.randi_range(2,7)
			entry.health = 4 if tree else 1
			entry.growth = 0.01
		entry.growth = minf(1.0,float(entry.growth)+remaining/(180.0 if tree else 75.0))
		_sync(index)
	_refresh_clearings()

func save_state() -> Dictionary:
	var output: Array = []
	for entry in records:
		var record := entry.duplicate()
		var at: Vector3 = record.at
		record.at = [at.x,at.y,at.z]
		output.append(record)
	return {"version":1,"records":output}

func _restore_records(saved: Array) -> void:
	for value in saved.slice(0,MAX_RECORDS):
		if not value is Dictionary or not value.get("at") is Array or value.at.size()!=3: continue
		var at := Vector3(float(value.at[0]),float(value.at[1]),float(value.at[2]))
		var limit := radius+12.0 if value.has("external") else radius
		if not at.is_finite() or absf(at.x)>limit or absf(at.z)>limit or absf(at.y)>30: continue
		var entry := {"at":at,"kind":clampi(int(value.get("kind",2)),0,7),"cycle":maxi(0,int(value.get("cycle",0)))}
		for field in ["growth","wait","size","yaw"]:
			var number := float(value.get(field,1.0 if field in ["growth","size"] else 0.0))
			entry[field] = number if is_finite(number) else 0.0
		entry.growth = clampf(entry.growth,0,1)
		entry.wait = clampf(entry.wait,0,360)
		entry.size = clampf(entry.size,0.82,1.14)
		entry.health = clampi(int(value.get("health",4 if int(entry.kind)<2 else 1)),1,4 if int(entry.kind)<2 else 1)
		if value.has("external"): entry.external=str(value.external)
		records.append(entry)

func _refresh_clearings() -> void:
	var circles: Array[Vector3] = []
	var signature := ""
	for plot in get_tree().get_nodes_in_group("ground_plot"):
		if plot.get_parent()!=island_node() or plot.is_queued_for_deletion() or not plot.has_plant(): continue
		var at := to_local(plot.global_position)
		circles.append(Vector3(at.x,at.z,0.95))
		signature += str(plot.get_instance_id())+":"
	if signature != _crop_signature: _mask_dirty=true;_crop_signature=signature
	if _mask_dirty:
		for entry in records:
			if float(entry.growth)<=0.0: circles.append(Vector3(entry.at.x,entry.at.z,1.05 if int(entry.kind)<2 else 0.8))
		var image := Image.create(MASK_SIZE,MASK_SIZE,false,Image.FORMAT_R8)
		image.fill(Color.BLACK)
		var extent := radius+1.0
		for circle in circles:
			var center := Vector2(circle.x,circle.y)/extent*0.5*MASK_SIZE+Vector2.ONE*MASK_SIZE*0.5
			var pixels := circle.z/extent*0.5*MASK_SIZE
			for y in range(maxi(0,floori(center.y-pixels)),mini(MASK_SIZE,ceili(center.y+pixels)+1)):
				for x in range(maxi(0,floori(center.x-pixels)),mini(MASK_SIZE,ceili(center.x+pixels)+1)):
					if Vector2(x+0.5,y+0.5).distance_to(center)<=pixels: image.set_pixel(x,y,Color.WHITE)
		_mask_image = image
		if _mask == null: _mask=ImageTexture.create_from_image(image)
		else: _mask.update(image)
		_mask_dirty=false
	# Grass may finish scattering after this controller, so bind lazily as well.
	for field in get_tree().get_nodes_in_group("island_grass_field"):
		if not island_node().is_ancestor_of(field): continue
		var material := field.material_override as ShaderMaterial
		if material==null or material.get_shader_parameter("use_clearance_mask")==true: continue
		material.set_shader_parameter("clearance_mask",_mask)
		material.set_shader_parameter("clearance_bounds",Vector4(global_position.x,global_position.z,radius+1.0,radius+1.0))
		material.set_shader_parameter("use_clearance_mask",true)
