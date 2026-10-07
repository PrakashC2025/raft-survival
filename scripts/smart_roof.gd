extends RefCounted
## Room detection uses raft-local metres, so a moving/yawing raft keeps its grid.
## A bounded flood fill proves enclosure; missing deck/open edges never count as
## walls. A wall or adjacent supported ceiling may support a single tile. Large/open rooms use the existing
## socket solver instead. Costs are charged for every new tile as one transaction.
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
const MAX_ROOM_TILES := 64
const HEIGHT := 2.725 # preserved 0.30 m foundation + 2.50 m wall + half roof

static func plan(raft: Node3D, world_aim: Vector3) -> Dictionary:
	if raft == null or not world_aim.is_finite():
		return {}
	var pieces := raft.get_node_or_null("BuiltPieces")
	if pieces == null:
		return {}
	var decks := {Vector2i.ZERO: true}
	var edges := {}
	var roofs := {}
	var stair_openings := {}
	var supports := {}
	for child in pieces.get_children():
		if not child is Node3D or child.is_queued_for_deletion():
			continue
		if child.name.begins_with("WallTorch"): continue
		if child.name.begins_with("Stairs") and absf(child.position.y-0.25)<0.25:
			# Preserve the stairwell rather than putting a ceiling through a head.
			for step in range(12):
				var flight: Vector3=child.transform*Vector3(0,0,(step+0.5)*0.25)
				stair_openings[Vector2i(roundi(flight.x/2.0),roundi(flight.z/2.0))]=true
		var local: Vector3 = child.position
		if not local.is_finite():
			continue
		var cell := Vector2i(roundi(local.x / 2.0), roundi(local.z / 2.0))
		if child.name.begins_with("Foundation") and absf(local.y) < 0.2:
			decks[cell] = true
		elif child.name.begins_with("Roof") and absf(local.y - HEIGHT) < 0.25:
			roofs[cell] = true
		elif (child.name.begins_with("Wall") or child.name.begins_with("Door") or child.name.begins_with("Window")) and absf(local.y - 1.4) < 0.2:
			var edge := Vector2i(roundi(local.x), roundi(local.z))
			# A wall must sit on an actual grid edge with its long axis along it.
			var axis: Vector3 = child.basis.x.normalized()
			if (absi(edge.x) % 2 == 0 and absi(edge.y) % 2 == 1 and absf(axis.x) > 0.95) or (absi(edge.y) % 2 == 0 and absi(edge.x) % 2 == 1 and absf(axis.z) > 0.95):
				edges[edge] = true
				supports[edge] = child
	var aim: Vector3 = raft.to_local(world_aim)
	var start := Vector2i(roundi(aim.x / 2.0), roundi(aim.z / 2.0))
	if not decks.has(start):
		# A wall hit lies exactly between two cells. Prefer nearby supported deck
		# instead of requiring a precise hit on the floor inside the room.
		var best := 2.3
		for candidate: Vector2i in decks:
			var distance := Vector2(aim.x-candidate.x*2.0,aim.z-candidate.y*2.0).length()
			if distance < best:
				best = distance
				start = candidate
		if not decks.has(start): return {}
	# At a shared wall, choose the inside (more surrounding walls) over the
	# outside. Resolve both candidates without altering the saved deck grid.
	var best_score := -1
	for candidate: Vector2i in decks:
		if absf(aim.x-candidate.x*2.0)>1.06 or absf(aim.z-candidate.y*2.0)>1.06: continue
		var score := 0
		for direction in DIRECTIONS:
			if edges.has(candidate*2+direction): score += 1
		if score > best_score:
			best_score = score
			start = candidate
	var queue: Array[Vector2i] = [start]
	var visited := {start: true}
	var enclosed := true
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for direction in DIRECTIONS:
			var edge: Vector2i = cell * 2 + direction
			if edges.has(edge):
				continue
			var next: Vector2i = cell + direction
			if not decks.has(next):
				enclosed = false
				continue
			if not visited.has(next):
				if visited.size() >= MAX_ROOM_TILES:
					return {}
				visited[next] = true
				queue.append(next)
	var supporting_edges: Array[Vector2i] = []
	for direction in DIRECTIONS:
		if edges.has(start * 2 + direction):
			supporting_edges.append(direction)
	if not enclosed:
		if roofs.has(start) and maxf(absf(aim.x-start.x*2.0),absf(aim.z-start.y*2.0))>0.55:
			var closest := INF
			var extension := start
			for direction in DIRECTIONS:
				var next: Vector2i = start+direction
				var distance := Vector2(aim.x-next.x*2.0,aim.z-next.y*2.0).length_squared()
				if decks.has(next) and not roofs.has(next) and distance<closest:
					closest=distance
					extension=next
			start=extension
		var supported := not supporting_edges.is_empty()
		for direction in DIRECTIONS:
			if roofs.has(start+direction): supported = true
		if not supported:
			return {}
		queue = [start]
	var transforms: Array[Transform3D] = []
	var cells: Array[Vector2i] = []
	for cell in queue:
		if roofs.has(cell) or stair_openings.has(cell):
			continue
		cells.append(cell)
		transforms.append(raft.global_transform * Transform3D(Basis.IDENTITY, Vector3(cell.x * 2.0, HEIGHT, cell.y * 2.0)))
	if transforms.is_empty():
		if stair_openings.has(start): return {"stair_opening":true}
		return {"occupied": true}
	var support: Node3D
	for direction in supporting_edges:
		if supports.has(start * 2 + direction):
			support = supports[start * 2 + direction]
			break
	if support == null and not supports.is_empty():
		support = supports.values()[0]
	return {"cells": cells, "transforms": transforms, "support": support, "room": enclosed}
