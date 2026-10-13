extends Node3D
## Small deterministic tiles with shared geometry/materials and bounded physics.
const TERRAIN := preload("res://scripts/underwater_terrain.gd")
const REEF := preload("res://scripts/underwater_reef_visual.gd")
const BUDGET := preload("res://scripts/frame_work_budget.gd")
const LOOT := preload("res://scripts/underwater_loot.gd")
var world: Node3D
var ground: StaticBody3D
var chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _centre := Vector2i(99999,99999)
var _radius := 1
var _active_quality := -1
var _busy := false
var _refresh := 0.0
var _coral: ShaderMaterial
var _plants: ShaderMaterial
var _kelp: ShaderMaterial
var _far: ShaderMaterial
var _player: Node3D

func _ready() -> void:
	_player=get_tree().get_first_node_in_group("player") as Node3D
	_coral=ShaderMaterial.new();_coral.shader=preload("res://shaders/underwater_organism.gdshader")
	_plants=world._kelp_material
	_kelp=_plants.duplicate() as ShaderMaterial
	_kelp.set_shader_parameter("leaf_colour",Color(.64,.61,.31))
	_far=world.get_node("OceanSandFloor").material_override
	GameSettings.changed.connect(_quality_changed)
	_quality_changed()

func _quality_changed() -> void:
	if _active_quality!=GameSettings.quality:
		_active_quality=GameSettings.quality
		for chunk in chunks.values():
			var shape: CollisionShape3D=chunk.get_meta("collision") if chunk.has_meta("collision") else null
			if is_instance_valid(shape):shape.queue_free()
			chunk.queue_free()
		chunks.clear();_pending.clear()
	_radius=[1,1,2,2,3][GameSettings.quality]
	_centre=Vector2i(99999,99999)
	_refresh=1.0

func _process(delta: float) -> void:
	_refresh+=delta
	if _refresh>=.2 and is_instance_valid(_player):
		_refresh=0
		request_position(Vector2(_player.global_position.x,_player.global_position.z))
	if not _busy and not _pending.is_empty():
		_busy=true;call_deferred("_build_next")

func request_position(point: Vector2) -> void:
	var centre := Vector2i(floori(point.x/TERRAIN.TILE),floori(point.y/TERRAIN.TILE))
	if centre==_centre:return
	_centre=centre;_far.set_shader_parameter("stream_cut",0.0);_pending.clear()
	var wanted: Array[Vector2i]=[]
	for z in range(-_radius,_radius+1):
		for x in range(-_radius,_radius+1):
			var tile := centre+Vector2i(x,z)
			if absi(tile.x)>43 or absi(tile.y)>43:continue
			wanted.append(tile)
			if not chunks.has(tile):_pending.append(tile)
	for tile in chunks.keys():
		if tile in wanted:continue
		var chunk: Node3D=chunks[tile]
		var collision: CollisionShape3D=chunk.get_meta("collision") if chunk.has_meta("collision") else null
		if is_instance_valid(collision):collision.queue_free()
		chunk.queue_free();chunks.erase(tile)
	_pending.sort_custom(func(a: Vector2i,b: Vector2i):return Vector2(a-centre).length_squared()<Vector2(b-centre).length_squared())

func ready_at(point: Vector2) -> bool:
	var tile := Vector2i(floori(point.x/TERRAIN.TILE),floori(point.y/TERRAIN.TILE))
	return chunks.has(tile) and bool(chunks[tile].get_meta("complete",false))

func _build_next() -> void:
	if _pending.is_empty():_busy=false;return
	var tile: Vector2i = _pending.pop_front()
	var chunk := Node3D.new();chunk.name="ReefTile_%d_%d"%[tile.x,tile.y]
	chunk.position=Vector3(tile.x*TERRAIN.TILE,0,tile.y*TERRAIN.TILE);add_child(chunk)
	chunk.set_meta("collision",null);chunk.set_meta("complete",false);chunks[tile]=chunk
	var mesh := await TERRAIN.mesh_at_incremental(tile,get_tree())
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():_busy=false;return
	var floor_visual := MeshInstance3D.new();floor_visual.name="SandDetail";floor_visual.mesh=mesh
	floor_visual.material_override=world._ground_material;floor_visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;chunk.add_child(floor_visual)
	await get_tree().process_frame
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():_busy=false;return
	var collision := CollisionShape3D.new();collision.shape=mesh.create_trimesh_shape();collision.position=chunk.position;ground.add_child(collision)
	chunk.set_meta("collision",collision);chunk.set_meta("complete",false);chunks[tile]=chunk
	await get_tree().process_frame
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():_busy=false;return
	var rng := RandomNumberGenerator.new();rng.seed=tile.x*73856093^tile.y*19349663^68127
	var budget: int = [18,12,26,36,48][GameSettings.quality]
	var reef_tile := (Vector2(tile)+Vector2.ONE*.5)*TERRAIN.TILE-Vector2(140,80)
	# Six to nine draw calls per tile; plants have GPU sway, no plant scripts.
	for kind in ["Grass","Kelp","Sponge","BranchCoral","FanCoral","BrainCoral","Urchin","Shell","Rock"]:
		var count: int = budget if kind=="Grass" else (maxi(3,floori(float(budget)/3)) if kind=="Kelp" else (6 if kind=="Rock" else 3))
		if reef_tile.length_squared()<14400:
			if kind=="Grass":count*=4
			elif kind=="Kelp":count*=2
		var batch := MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.use_colors=true
		batch.mesh=preload("res://scripts/island_landscape.gd")._rock_mesh() if kind=="Rock" else REEF.mesh(kind)
		batch.instance_count=count
		var placed := 0
		for index in count:
			var local := Vector2(rng.randf_range(1,47),rng.randf_range(1,47));var point := Vector2(chunk.position.x,chunk.position.z)+local
			var channel := point.x-140-sin((point.y-80)*.035)*9
			var at_reef := point.distance_squared_to(Vector2(140,80))<8100
			if at_reef and absf(channel)<4.0 and kind!="Shell":continue
			var h := TERRAIN.surface_height(point)
			if h < -58 and kind in ["Kelp","Grass","Sponge","FanCoral"]:continue
			var scale_value := rng.randf_range(.65,1.45)
			var size := Vector3.ONE*scale_value
			if kind=="Rock":size=Vector3(rng.randf_range(.8,3.8),rng.randf_range(.7,2.8),rng.randf_range(.8,3.0))
			if kind=="Kelp":size=Vector3(scale_value,rng.randf_range(.65,1.55),scale_value)
			var at := Vector3(local.x,h+(size.y*.15 if kind=="Rock" else -.025),local.y)
			batch.set_instance_transform(placed,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(size),at))
			batch.set_instance_color(placed,Color(rng.randf_range(.75,1),rng.randf_range(.85,1),rng.randf_range(.72,1)))
			placed+=1
			if BUDGET.exhausted(1,&"reef_stream",24,1500):
				await get_tree().process_frame
				if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():_busy=false;return
		batch.visible_instance_count=placed
		var draw := MultiMeshInstance3D.new();draw.name=kind+"Batch";draw.multimesh=batch
		draw.material_override=world._ruin_material if kind=="Rock" else (_kelp if kind=="Kelp" else (_plants if kind=="Grass" else _coral))
		draw.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		draw.visibility_range_end=110 if kind in ["Rock","Kelp"] else (55 if GameSettings.quality==1 else 85)
		chunk.add_child(draw)
		if BUDGET.exhausted(16,&"reef_stream",32,2000):
			await get_tree().process_frame
			if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():_busy=false;return
	_make_loot(chunk,tile,rng)
	chunk.set_meta("complete",true);_busy=false
	if _pending.is_empty():
		_far.set_shader_parameter("stream_center",(Vector2(_centre)+Vector2.ONE*.5)*TERRAIN.TILE)
		_far.set_shader_parameter("stream_cut",_radius*TERRAIN.TILE-1.0)

func _make_loot(chunk: Node3D, tile: Vector2i, rng: RandomNumberGenerator) -> void:
	var selector := posmod(tile.x*31+tile.y*17,7)
	var kinds := ["Sponge","Driftwood","Scrap","Shell","Container","Scrap","Rock"]
	var rewards := [{"Sponge":2},{"Wood":3},{"Metal":2},{"Stone":2},{"Wire":1,"Screw":2,"Metal":2},{"Plastic":2},{"Stone":3}]
	var loot := LOOT.new();loot.name="Gatherable";loot.resource_id="reef:%d:%d"%[tile.x,tile.y]
	loot.rewards=rewards[selector];loot.caption="SEARCH SUNKEN BOX" if selector==4 else "COLLECT "+str(loot.rewards.keys()[0]).to_upper()
	if posmod(tile.x*67+tile.y*37,23)==0:
		selector=4;loot.rewards={"Motor":1,"Battery":1,"Wire":2};loot.caption="SEARCH RARE SALVAGE CASE"
	loot.owner_world=world
	var point := Vector2(chunk.position.x,chunk.position.z)+Vector2(rng.randf_range(5,43),rng.randf_range(5,43))
	loot.position=Vector3(point.x-chunk.position.x,TERRAIN.surface_height(point),point.y-chunk.position.z)
	var draw := MeshInstance3D.new();draw.name="Salvage";draw.mesh=preload("res://scripts/island_landscape.gd")._rock_mesh() if selector==6 else REEF.mesh(kinds[selector]);draw.material_override=world._ruin_material if selector==6 else _coral
	if selector==6:draw.scale=Vector3(.4,.3,.4)
	draw.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;loot.add_child(draw)
	var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(1,.8,1);shape.shape=box;shape.position.y=.35;loot.add_child(shape)
	chunk.add_child(loot)

func update_light(daylight: float) -> void:
	_coral.set_shader_parameter("daylight",daylight);_kelp.set_shader_parameter("daylight",daylight)

func _exit_tree() -> void:
	# Collision shapes live on the shared collectible floor, not their tile node.
	for chunk in chunks.values():
		var shape: CollisionShape3D=chunk.get_meta("collision") if chunk.has_meta("collision") else null
		if is_instance_valid(shape):shape.queue_free()
