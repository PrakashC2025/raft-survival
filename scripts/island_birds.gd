extends Node3D
## Lightweight gull flock for the home island. Set sketchfab_bird_model to a
## downloaded, licensed Sketchfab GLB to replace the low-poly fallback; the
## orbit/flight behavior stays the same and imported animations are played when
## present.

@export_file("*.glb") var sketchfab_bird_model := ""
@export_range(1, 8, 1) var bird_count := 4
@export var orbit_radius := 10.0
@export var flight_height := 8.5

var _time := 0.0
var _birds: Array[Dictionary] = []
var _imported_scene: PackedScene = null


func _ready() -> void:
	if not sketchfab_bird_model.is_empty() and ResourceLoader.exists(sketchfab_bird_model):
		_imported_scene = load(sketchfab_bird_model) as PackedScene
	for i in range(bird_count):
		var bird := Node3D.new()
		bird.name = "IslandBird_%02d" % i
		bird.add_to_group("no_collision")
		add_child(bird)
		var left_wing: Node3D = null
		if _imported_scene != null:
			var model := _imported_scene.instantiate() as Node3D
			if model != null:
				model.scale = Vector3.ONE * 0.55
				bird.add_child(model)
				for candidate in model.find_children("*", "MeshInstance3D", true, false):
					(candidate as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_play_imported_animation(model)
			else:
				left_wing = _build_cartoon_gull(bird)
		else:
			left_wing = _build_cartoon_gull(bird)
		var phase := TAU * float(i) / float(maxi(bird_count, 1))
		_birds.append({
			"root": bird,
			"left": left_wing,
			"phase": phase,
			"radius": orbit_radius + float(i % 2) * 2.0,
			"speed": 0.10 + float(i % 3) * 0.018,
			"height": flight_height + float(i % 2) * 1.2,
		})


func _build_cartoon_gull(root: Node3D) -> Node3D:
	var pale := _bird_material(Color(0.88, 0.91, 0.88), 0.78)
	var charcoal := _bird_material(Color(0.24, 0.29, 0.31), 0.82)
	var beak_mat := _bird_material(Color(0.9, 0.56, 0.19), 0.72)
	var body := SphereMesh.new()
	body.radius = 0.19
	body.height = 0.3
	body.radial_segments = 10
	body.rings = 6
	_add_bird_mesh(root, body, pale, Transform3D(Basis.IDENTITY.scaled(Vector3(0.78, 0.62, 1.45)), Vector3.ZERO))
	var head := SphereMesh.new()
	head.radius = 0.105
	head.height = 0.18
	head.radial_segments = 8
	head.rings = 5
	_add_bird_mesh(root, head, pale, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.045, -0.235)))
	var beak := PrismMesh.new()
	beak.size = Vector3(0.08, 0.055, 0.14)
	_add_bird_mesh(root, beak, beak_mat, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.025, -0.365)))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.16, 0.028, 0.2)
	_add_bird_mesh(root, tail, charcoal, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.245)))
	var left := _make_wing(root, -1.0, charcoal)
	_make_wing(root, 1.0, charcoal)
	return left


func _make_wing(root: Node3D, side: float, material: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "WingLeft" if side < 0.0 else "WingRight"
	pivot.position = Vector3(side * 0.13, 0.025, 0.0)
	root.add_child(pivot)
	var wing := BoxMesh.new()
	wing.size = Vector3(0.47, 0.035, 0.19)
	var mi := MeshInstance3D.new()
	mi.mesh = wing
	mi.material_override = material
	mi.position = Vector3(side * 0.22, 0.0, 0.025)
	mi.rotation.z = side * -0.08
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	return pivot


func _add_bird_mesh(root: Node3D, mesh: Mesh, material: StandardMaterial3D, xform: Transform3D) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = xform
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)


func _bird_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _play_imported_animation(model: Node3D) -> void:
	for node in model.find_children("*", "AnimationPlayer", true, false):
		var animation_player := node as AnimationPlayer
		for animation_name in animation_player.get_animation_list():
			if str(animation_name).to_lower().find("reset") >= 0:
				continue
			animation_player.play(animation_name)
			return


func _process(delta: float) -> void:
	_time += delta
	for bird_data in _birds:
		var bird := bird_data["root"] as Node3D
		var phase := _time * float(bird_data["speed"]) + float(bird_data["phase"])
		var radius := float(bird_data["radius"])
		var y := float(bird_data["height"]) + sin(phase * 2.0) * 0.48
		bird.position = Vector3(cos(phase) * radius, y, sin(phase) * radius)
		var tangent := Vector3(-sin(phase), cos(phase) * 0.08, cos(phase)).normalized()
		bird.rotation.y = atan2(-tangent.x, -tangent.z)
		var wing := bird_data["left"] as Node3D
		if wing != null and is_instance_valid(wing):
			var flap := sin(_time * 7.2 + float(bird_data["phase"])) * 0.42
			wing.rotation.z = flap
			var other := bird.get_node_or_null("WingRight") as Node3D
			if other != null:
				other.rotation.z = -flap
