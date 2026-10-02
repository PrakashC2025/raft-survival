extends SceneTree
## Bake the island grass field headlessly:
##   Godot_console.exe --headless --path . --script tools/bake_grass_field.gd
## Loads scenes/main.tscn, waits for IslandGrass to finish its raycast
## rebuild (island_generator builds the collider in an earlier phase),
## then quits. island_grass.gd saves res://grass/island_grass_baked.tres
## itself when running headless.

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	if ps == null:
		push_error("bake_grass_field: cannot load scenes/main.tscn")
		quit(1)
		return
	var scene := ps.instantiate()
	root.add_child(scene)
	_poll()

func _poll() -> void:
	var waited := 0.0
	var grass: Node3D = null
	while waited < 300.0:
		await process_frame
		waited += 1.0 / 60.0
		if grass == null:
			var island := root.get_node_or_null("Main/Island")
			if island != null:
				grass = island.get_node_or_null("IslandGrass") as Node3D
		if grass != null:
			for c in grass.get_children():
				if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh != null:
					var mm: MultiMesh = (c as MultiMeshInstance3D).multimesh
					if mm.instance_count > 0:
						print("[bake_grass_field] DONE: %d clumps" % mm.instance_count)
						quit(0)
						return
	print("[bake_grass_field] TIMEOUT: grass field never filled (300 s)")
	quit(1)
