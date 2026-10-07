extends RefCounted
## Original earth geometry: irregular seedbed, clods, grit and embedded twigs.
## One cached mesh per pot size; one draw call and no particles/physics.
static var _meshes: Dictionary = {}
const SHADER := preload("res://shaders/soil_surface.gdshader")
static func create(size: Vector2, round_bed: bool, color: Color) -> MeshInstance3D:
	var key := "%s:%s" % [size,round_bed]
	if not _meshes.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rng := RandomNumberGenerator.new()
		rng.seed = 72481
		var points: Array[Vector3] = []
		var steps := 16
		for z in range(steps+1):
			for x in range(steps+1):
				var uv := Vector2(float(x)/steps,float(z)/steps)
				var xy := (uv-Vector2.ONE*0.5)*size
				if round_bed:
					var square := uv*2.0-Vector2.ONE
					xy = Vector2(square.x*sqrt(1.0-square.y*square.y*0.5),square.y*sqrt(1.0-square.x*square.x*0.5))*size*0.5
				points.append(Vector3(xy.x,rng.randf_range(-0.007,0.008),xy.y))
		for z in steps:
			for x in steps:
				var i := z*(steps+1)+x
				for index in [i,i+1,i+steps+1,i+1,i+steps+2,i+steps+1]:
					surface.set_color(Color.WHITE*rng.randf_range(0.85,1.12))
					surface.add_vertex(points[index])
		# Low clods make the silhouette visibly uneven, even without shader detail.
		# Index the seedbed before appending indexed primitives; otherwise only
		# the clods are referenced by the resulting index buffer.
		surface.index()
		var lump := SphereMesh.new()
		lump.radius=0.015; lump.height=0.032; lump.radial_segments=6; lump.rings=3
		for unused in 28:
			var xy := Vector2(rng.randf_range(-0.42,0.42),rng.randf_range(-0.42,0.42))
			if round_bed and xy.length()>0.40: continue
			surface.append_from(lump,0,Transform3D(Basis.IDENTITY.scaled(Vector3(rng.randf_range(0.6,1.4),0.6,1.0)),Vector3(xy.x*size.x,0.002,xy.y*size.y)))
		var twig := CylinderMesh.new()
		twig.top_radius=0.0015;twig.bottom_radius=0.002;twig.height=0.035;twig.radial_segments=5
		for unused in 6:
			var at := Vector3(rng.randf_range(-0.25,0.25)*size.x,0.004,rng.randf_range(-0.25,0.25)*size.y)
			surface.append_from(twig,0,Transform3D(Basis(Vector3.UP,rng.randf()*TAU)*Basis(Vector3.RIGHT,PI/2),at))
		surface.generate_normals()
		var raw := surface.commit()
		var arrays := raw.surface_get_arrays(0)
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		for index in colors.size():
			if colors[index].r<0.01:colors[index]=Color(0.83,0.80,0.73)
		arrays[Mesh.ARRAY_COLOR]=colors
		var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_meshes[key]=mesh
	var result := MeshInstance3D.new()
	result.name="LivingSoil"
	result.mesh=_meshes[key]
	var mat := ShaderMaterial.new()
	mat.shader=SHADER;mat.set_shader_parameter("earth_color",color)
	mat.set_shader_parameter("earth_grain",preload("res://textures/island/sand_diff.jpg"))
	result.material_override=mat
	return result
