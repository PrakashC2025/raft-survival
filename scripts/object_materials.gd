extends RefCounted
## Shared original material detail; imported textured art keeps its textures.
enum Kind { WOOD, METAL, STONE, CLOTH, PLASTIC, SKIN, FOOD, SOIL }
const SURFACE: Shader = preload("res://shaders/object_surface.gdshader")
static var _materials: Dictionary = {}

static func make(kind: int, color: Color, roughness: float = 0.8, metallic: float = 0.0) -> ShaderMaterial:
	var key := "%d:%s:%.3f:%.3f" % [kind, color.to_html(true), roughness, metallic]
	var existing: ShaderMaterial = _materials.get(key)
	if existing != null:
		return existing
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("surface_kind", kind)
	material.set_shader_parameter("surface_roughness", roughness)
	material.set_shader_parameter("surface_metallic", metallic)
	if kind == Kind.METAL:
		preload("res://scripts/salvage_surfaces.gd").apply(material, false)
	_materials[key] = material
	return material

static func worn(kind: int, color: Color, roughness: float = 0.85, metallic: float = 0.0) -> ShaderMaterial:
	var key:="worn:%d:%s:%.3f:%.3f"%[kind,color.to_html(true),roughness,metallic]
	if not _materials.has(key):
		var material:=make(kind,color,roughness,metallic).duplicate() as ShaderMaterial
		material.set_shader_parameter("surface_wear",0.9)
		if kind == Kind.METAL:
			preload("res://scripts/salvage_surfaces.gd").apply(material, true)
		_materials[key]=material
	return _materials[key]

static func kind_for_item(item: String) -> int:
	match item:
		"Wood", "Barrel", "Spear", "Fishing Rod", "Bow", "Arrow": return Kind.WOOD
		"Metal", "Motor Kit": return Kind.METAL
		"Stone": return Kind.STONE
		"Rope", "Sail Kit", "Life Vest": return Kind.CLOTH
		"Plastic": return Kind.PLASTIC
	return Kind.FOOD

static func apply_model(root: Node3D, default_kind: int) -> void:
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface in range(instance.mesh.get_surface_count()):
			var original := instance.get_active_material(surface) as BaseMaterial3D
			if original == null or original.albedo_texture != null or original.cull_mode == BaseMaterial3D.CULL_DISABLED:
				continue
			var kind := default_kind
			var label := (str(instance.name) + original.resource_name).to_lower()
			if label.contains("metal") or label.contains("band"):
				kind = Kind.METAL
			instance.set_surface_override_material(surface,
				make(kind, original.albedo_color, original.roughness, original.metallic))
