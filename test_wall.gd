extends SceneTree

# End-to-end test: place a Foundation through the real build flow (_try_build),
# then resolve Wall placements against the placed foundation.

func _initialize() -> void:
	call_deferred("_run_test")

func _aim_at(player: Node, pt: Vector3, normal: Vector3 = Vector3.UP) -> void:
	player.camera.global_position = pt + Vector3(0, 4, 0)
	player.camera.look_at(pt - Vector3(0, 1, 0))
	player.aim_valid = true
	player.aim_point = pt
	player.aim_normal = normal
	player.aim_collider = null
	player.aim_distance = 4.0

func _run_test() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var player: CharacterBody3D = root.get_node("Main/Player")
	var raft: Node3D = player._get_raft_node()

	# ---- 1) Place a Foundation at cell (1,0) via the REAL build system ----
	player.build_mode = true
	player.selected_piece_index = player.BUILD_RECIPE_NAMES.find("Foundation")
	player._spawn_ghost()
	# Aim at the raft east edge (cell (1,0) is east of the raft)
	var raft_flat: Transform3D = player._get_flat_support_transform(raft)
	_aim_at(player, raft_flat * Vector3(0.9, 0.15, 0))
	var fres: Dictionary = player._resolve_placement("Foundation", player.aim_point)
	print("FOUNDATION resolve: valid=", fres.get("valid", "?"), " cell=", str(fres.get("cell", "?")), " reason=", str(player._diag.get("invalid_reason", "")))
	if fres.get("valid", false):
		player._ghost_target_socket = fres.get("socket", null)
		player._ghost_cell = fres.get("cell", Vector2i(999999, 999999))
		player._ghost_transform = fres["transform"]
		player.build_valid = true
		player._try_build()
		print("FOUNDATION placed. BuiltPieces children: ", raft.get_node_or_null("BuiltPieces").get_child_count())
		await physics_frame
		await physics_frame
	else:
		print("FOUNDATION placement failed — aborting.")
		quit()
		return

	# Find the placed foundation
	var found: Node3D = null
	var bp: Node3D = raft.get_node_or_null("BuiltPieces")
	for c in bp.get_children():
		if c.name.begins_with("Foundation"):
			found = c
			break
	print("Placed foundation at ", found.global_position, " in group=", found.is_in_group("build_surface"))

	# ---- 2) Now resolve WALL placements on the placed foundation ----
	var flat: Transform3D = player._get_flat_support_transform(found)

	player.selected_piece_index = player.BUILD_RECIPE_NAMES.find("Wall")

	# 2a) North edge midpoint — resolve AND place through the real flow
	_aim_at(player, flat * Vector3(0, 0.15, 1))
	player.aim_collider = found
	var r1: Dictionary = player._resolve_placement("Wall", player.aim_point)
	print("WALL @ foundation North edge -> valid=", r1.get("valid", "?"), " reason=", str(player._diag.get("invalid_reason", "")), " ratio=", str(player._diag.get("footprint_ratio", -1)), " center=", str(player._diag.get("center_supported", "?")), " support=", str(player._diag.get("wall_foundation", "?")))
	if r1.get("valid", false):
		player._ghost_target_socket = null
		player._ghost_cell = Vector2i(999999, 999999)
		player._ghost_transform = r1["transform"]
		player.build_valid = true
		player._try_build()
		var placed_wall: Node3D = null
		for c in bp.get_children():
			if c.name.begins_with("Wall"):
				placed_wall = c
				break
		print("WALL PLACED on foundation: pos=", placed_wall.global_position if placed_wall else null)

	# 2b) East edge midpoint
	_aim_at(player, flat * Vector3(1, 0.15, 0))
	player.aim_collider = found
	var r2: Dictionary = player._resolve_placement("Wall", player.aim_point)
	print("WALL @ foundation East edge -> valid=", r2.get("valid", "?"), " reason=", str(player._diag.get("invalid_reason", "")), " ratio=", str(player._diag.get("footprint_ratio", -1)))

	# 2c) Corner
	_aim_at(player, flat * Vector3(0.85, 0.15, 1))
	player.aim_collider = found
	var r3: Dictionary = player._resolve_placement("Wall", player.aim_point)
	print("WALL @ foundation NE corner -> valid=", r3.get("valid", "?"), " reason=", str(player._diag.get("invalid_reason", "")), " ratio=", str(player._diag.get("footprint_ratio", -1)), " edge=", str(player._diag.get("wall_edge", "")))

	# 2d) Center (should snap to nearest edge)
	_aim_at(player, flat * Vector3(0, 0.15, 0))
	player.aim_collider = found
	var r4: Dictionary = player._resolve_placement("Wall", player.aim_point)
	print("WALL @ foundation center -> valid=", r4.get("valid", "?"), " reason=", str(player._diag.get("invalid_reason", "")), " edge=", str(player._diag.get("wall_edge", "")))

	# 2e) Aim at the ocean 6m beyond the foundation (should be RED at crosshair)
	_aim_at(player, flat * Vector3(0, 0.15, 7))
	player.aim_collider = null
	var r5: Dictionary = player._resolve_placement("Wall", player.aim_point)
	print("WALL @ ocean 6m beyond -> valid=", r5.get("valid", "?"), " reason=", str(player._diag.get("invalid_reason", "")))

	quit()