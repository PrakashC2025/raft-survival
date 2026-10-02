extends Node3D
## Small original islands with collision generated from exactly the rendered mesh.
const LOCATIONS := [Vector3(110, 0, -100), Vector3(-130, 0, -160), Vector3(180, 0, 120)]
const TITLES := ["Palm Refuge", "Iron Cay", "Last Signal"]
var director: Node
var visited: Array = []
var harvested: Dictionary = {}
var survivors: Array[Node3D] = []

func _ready() -> void:
	for i in range(LOCATIONS.size()):
		var island := make_island(LOCATIONS[i], TITLES[i])
		survivors.append(island)
		for j in range(5):
			var tree := PlantInstance.new()
			tree.plant_id = "Coconut"
			tree.start_stage = 3
			var angle := float(j) * TAU / 5.0
			tree.position = Vector3(cos(angle) * 9.0, 2.5, sin(angle) * 9.0)
			island.add_child(tree)
		for j in range(4):
			var rock := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.6
			mesh.height = 0.8
			rock.mesh = mesh
			var imported := preload("res://scripts/mobile_assets.gd").make("rock-a", 1.2)
			if imported != null:
				rock.mesh = null
				rock.add_child(imported)
			rock.position = Vector3(-5 + j * 2, 2.8, 4)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.18, 0.22, 0.24)
			rock.material_override = material
			island.add_child(rock)
			rock.set_meta("resource_id", "%d_%d" % [i, j])
			rock.add_to_group("survival_resource")
		var label := Label3D.new()
		label.text = TITLES[i]
		label.position = Vector3(0, 7, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 52
		island.add_child(label)

func make_island(at: Vector3, title: String) -> Node3D:
	var island := Node3D.new()
	island.name = title.replace(" ", "")
	island.position = at
	island.add_to_group("island")
	add_child(island)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [Vector2(0, 2.5), Vector2(14, 2.5), Vector2(20, 0.5), Vector2(27, -5)]
	for ring in range(3):
		for i in range(48):
			var a := TAU * float(i) / 48.0
			var b := TAU * float(i + 1) / 48.0
			var p := Vector3(cos(a) * rings[ring].x, rings[ring].y, sin(a) * rings[ring].x)
			var q := Vector3(cos(b) * rings[ring].x, rings[ring].y, sin(b) * rings[ring].x)
			var r := Vector3(cos(a) * rings[ring + 1].x, rings[ring + 1].y, sin(a) * rings[ring + 1].x)
			var s := Vector3(cos(b) * rings[ring + 1].x, rings[ring + 1].y, sin(b) * rings[ring + 1].x)
			for vertex in [p, r, q, q, r, s]:
				st.set_uv(Vector2(vertex.x, vertex.z) * 0.1)
				st.add_vertex(vertex)
	st.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.52, 0.43, 0.26)
	material.roughness = 1.0
	terrain.material_override = material
	island.add_child(terrain)
	terrain.create_trimesh_collision()
	return island

func tick(player: Node3D) -> void:
	for i in range(LOCATIONS.size()):
		if player.global_position.distance_to(LOCATIONS[i]) < 22.0 and not visited.has(i):
			visited.append(i)
			director.call("_say", "Discovered " + TITLES[i])
			director.call("_checkpoint")

func gather(player: Node3D) -> String:
	for node in get_tree().get_nodes_in_group("survival_resource"):
		var id: String = node.get_meta("resource_id", "")
		if player.global_position.distance_to(node.global_position) < 3.0 and not harvested.has(id):
			if Inventory.try_exchange({}, {"Metal": 3, "Stone": 3}):
				harvested[id] = true
				node.hide()
				return "Collected metal ore and stone."
			return "Make room in your bag."
	return "Stand near dark ore rocks on an outlying island."

