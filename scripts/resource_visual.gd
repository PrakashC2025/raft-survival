extends RefCounted
## Small recognizable salvage props; meshes/materials are reused after creation.
const MATERIALS := preload("res://scripts/object_materials.gd")
static var _meshes: Dictionary = {}

static func create(item: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Salvage" + item
	match item:
		"Sponge":
			var mesh := SphereMesh.new()
			mesh.radius=0.16;mesh.height=0.23;mesh.radial_segments=16;mesh.rings=8
			var sponge := ShaderMaterial.new()
			sponge.shader=preload("res://shaders/sponge_surface.gdshader")
			_part(root,mesh,sponge,Vector3.ZERO)
			_part(root,mesh,sponge,Vector3(0.07,-0.035,0.04))
		"Rope":
			var rope := MATERIALS.make(MATERIALS.Kind.CLOTH, Color(0.53, 0.40, 0.23), 0.94)
			for layer in range(3):
				_part(root, _torus(), rope, Vector3(0, float(layer) * 0.035, 0))
			_part(root, _box("tie", Vector3(0.045, 0.13, 0.30)),
				MATERIALS.make(MATERIALS.Kind.CLOTH, Color(0.26, 0.20, 0.12)), Vector3(0, 0.025, 0))
		"Plastic":
			var plastic := MATERIALS.make(MATERIALS.Kind.PLASTIC, Color(0.19, 0.38, 0.43), 0.44)
			_part(root, _box("can", Vector3(0.30, 0.30, 0.17)), plastic, Vector3.ZERO)
			for sign_value in [-1.0, 1.0]:
				_part(root, _box("handle_post", Vector3(0.025, 0.07, 0.045)), plastic, Vector3(sign_value * 0.062, 0.18, 0))
			_part(root, _box("handle", Vector3(0.15, 0.025, 0.045)), plastic, Vector3(0, 0.215, 0))
			_part(root, _box("cap", Vector3(0.055, 0.035, 0.055)),
				MATERIALS.make(MATERIALS.Kind.PLASTIC, Color(0.11, 0.13, 0.12), 0.55), Vector3(-0.10, 0.17, 0))
		"Metal":
			var metal := MATERIALS.make(MATERIALS.Kind.METAL, Color(0.40, 0.43, 0.42), 0.48, 0.78)
			_part(root, _box("plate", Vector3(0.37, 0.035, 0.28)), metal, Vector3.ZERO)
			_part(root, _box("edge", Vector3(0.37, 0.14, 0.035)), metal, Vector3(0, 0.052, 0.12))
			_part(root, _box("rib", Vector3(0.035, 0.035, 0.25)), metal, Vector3(-0.11, 0.025, 0))
		_:
			if item.ends_with(" Seed"):
				_part(root, _box("seed_packet", Vector3(0.20, 0.26, 0.05)),
					MATERIALS.make(MATERIALS.Kind.CLOTH, Color(0.67, 0.60, 0.42), 0.93), Vector3.ZERO)
				_part(root, _box("seed_label", Vector3(0.14, 0.10, 0.008)),
					MATERIALS.make(MATERIALS.Kind.CLOTH, Color(0.27, 0.35, 0.16), 0.9), Vector3(0, 0.01, -0.029))
	return root

static func _torus() -> Mesh:
	if not _meshes.has("coil"):
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.09
		mesh.outer_radius = 0.16
		mesh.rings = 16
		mesh.ring_segments = 6
		_meshes["coil"] = mesh
	return _meshes["coil"]

static func _box(key: String, size: Vector3) -> Mesh:
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return _meshes[key]

static func _part(root: Node3D, mesh: Mesh, material: Material, position: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = position
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(part)
