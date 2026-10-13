extends RefCounted
## CPU-only geometry calculation. No nodes, renderer or physics calls here.
const TERRAIN := preload("res://scripts/underwater_terrain.gd")
var arrays: Array = []

func build(grid: int, extent: float) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(grid+1):
		for x in range(grid+1):
			var point := Vector2(float(x)/grid-.5,float(z)/grid-.5)*extent*2
			vertices.append(Vector3(point.x,TERRAIN.height_at(point)-6.0,point.y))
			normals.append(TERRAIN.normal_at(point))
			if x<grid and z<grid:
				var index := z*(grid+1)+x
				indices.append_array(PackedInt32Array([index,index+1,index+grid+1,index+1,index+grid+2,index+grid+1]))
	var result: Array = []; result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_INDEX] = indices
	arrays = result
