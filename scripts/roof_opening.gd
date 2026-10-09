extends StaticBody3D
## Adjacent ceiling panels form one narrow, continuous stairwell. The tile
## and stair transforms remain the save format's authoritative geometry.
const TIMBER := preload("res://scripts/construction_visual.gd")
const HALF_WIDTH := 0.70
const START := 0.35
const END := 2.50
var _tick := 0.0
var _signature := 0
var _cut_root: Node3D
static var _meshes: Dictionary = {}

static func panels(tile: Transform3D, flights: Array[Transform3D], runs: Array[float] = []) -> Array[Rect2]:
	var result: Array[Rect2] = [Rect2(-1,-1,2,2)]
	for flight_index in flights.size():
		var flight := flights[flight_index]
		var run := runs[flight_index] if flight_index<runs.size() else 2.4
		var relative := tile.affine_inverse()*flight
		if absf(relative.origin.y + 2.475) > 0.3: continue
		var lower := Vector2(INF,INF)
		var upper := Vector2(-INF,-INF)
		for x in [-HALF_WIDTH,HALF_WIDTH]:
			for z in [START*run/2.4,run+0.1]:
				var p: Vector3 = relative*Vector3(x,0,z)
				lower=lower.min(Vector2(p.x,p.z)); upper=upper.max(Vector2(p.x,p.z))
		var opening := Rect2(lower,upper-lower)
		var remaining: Array[Rect2] = []
		for rect in result:
			var cut := rect.intersection(opening)
			if not cut.has_area(): remaining.append(rect); continue
			for section in [Rect2(rect.position,Vector2(cut.position.x-rect.position.x,rect.size.y)),
				Rect2(Vector2(cut.end.x,rect.position.y),Vector2(rect.end.x-cut.end.x,rect.size.y)),
				Rect2(Vector2(cut.position.x,rect.position.y),Vector2(cut.size.x,cut.position.y-rect.position.y)),
				Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,rect.end.y-cut.end.y))]:
				if section.size.x>0.015 and section.size.y>0.015: remaining.append(section)
		result=remaining
	return result

func _ready() -> void:
	call_deferred("refresh", false)

func _process(delta: float) -> void:
	_tick+=delta
	if _tick<0.15:return
	_tick=0.0
	refresh(false)

func refresh(force_scan: bool = true) -> void:
	if get_parent()==null or get_parent().name!="BuiltPieces":return
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.get("_editing") == self: return
	var container := get_parent()
	if container.get_meta("restoring",false): return
	# Every ceiling shares this render-frame snapshot instead of rescanning all
	# structures independently. Explicit refresh still immediately sees edits.
	var frame := Engine.get_process_frames()
	if force_scan or int(container.get_meta("roof_flight_frame",-1)) != frame:
		var snapshot: Array[Transform3D] = []
		var lengths: Array[float] = []
		for piece in container.get_children():
			if piece is Node3D and piece.name.begins_with("Stairs") and not piece.is_queued_for_deletion():
				snapshot.append(piece.transform)
				lengths.append(piece.run)
		container.set_meta("roof_flight_frame",frame)
		container.set_meta("roof_flights",snapshot)
		container.set_meta("roof_runs",lengths)
	var flights: Array[Transform3D] = container.get_meta("roof_flights")
	var runs: Array[float] = container.get_meta("roof_runs")
	var next_signature := hash([transform,flights,runs])
	if next_signature==_signature:return
	_signature=next_signature
	var sections:=panels(transform,flights,runs)
	var cut := sections.size()!=1 or sections[0]!=Rect2(-1,-1,2,2)
	if is_instance_valid(_cut_root):
		remove_child(_cut_root);_cut_root.queue_free()
	_cut_root=null
	for child in get_children():
		if child.has_meta("stair_cut"):
			child.disabled=true;remove_child(child);child.queue_free()
		elif child is CollisionShape3D:child.set_deferred("disabled",cut)
		elif child is GeometryInstance3D or child.name=="TimberDetails":
			child.visible=not cut
			child.set_meta("stair_hidden",cut)
	if cut:
		_cut_root=Node3D.new();_cut_root.name="StairwellPanels";add_child(_cut_root)
		for rect in sections:
			var dimensions:=Vector3(rect.size.x,0.15,rect.size.y)
			var centre:=Vector3(rect.get_center().x,0,rect.get_center().y)
			var collision:=CollisionShape3D.new()
			var shape:=BoxShape3D.new();shape.size=dimensions
			collision.shape=shape;collision.position=centre
			collision.name="StairwellCollision_%d"%get_child_count()
			collision.set_meta("stair_cut",true);add_child(collision)
			var visual:=MeshInstance3D.new()
			if not _meshes.has(dimensions):_meshes[dimensions]=TIMBER.panel(dimensions,false)
			visual.mesh=_meshes[dimensions];visual.position=centre;_cut_root.add_child(visual)
	set_meta("geometry_revision",next_signature)
