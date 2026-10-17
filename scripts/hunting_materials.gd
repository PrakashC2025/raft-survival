extends RefCounted
## Shared original material artwork; no per-animal textures or lights.
static var _cache: Dictionary={}
static func skin(kind: String) -> ShaderMaterial:
	if _cache.has(kind):return _cache[kind] as ShaderMaterial
	var material:=ShaderMaterial.new()
	material.shader=preload("res://shaders/hunting_surface.gdshader")
	material.set_shader_parameter("material_atlas",preload("res://textures/wildlife/hunting_materials_v1.png"))
	match kind:
		"Boar":
			material.set_shader_parameter("tile",Vector2(.5,0));material.set_shader_parameter("texture_scale",2.4)
			material.set_shader_parameter("tint",Color(.80,.77,.72));material.set_shader_parameter("surface_roughness",.97)
		"Octopus":
			material.set_shader_parameter("tile",Vector2(0,.5));material.set_shader_parameter("texture_scale",1.5)
			material.set_shader_parameter("tint",Color(.83,.81,.73));material.set_shader_parameter("surface_roughness",.64)
		_:
			material.set_shader_parameter("texture_scale",2.3);material.set_shader_parameter("belly_light",.5)
	_cache[kind]=material
	return material
static func wood() -> ShaderMaterial:
	if _cache.has("Wood"):return _cache.Wood as ShaderMaterial
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/rowboat_wood.gdshader")
	material.set_shader_parameter("material_atlas",preload("res://textures/wildlife/hunting_materials_v1.png"))
	_cache.Wood=material;return material
