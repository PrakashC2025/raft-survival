extends RefCounted
## Deterministic seabed shared by render meshes, collisions and marine life.
const TILE := 48.0
const STEPS := 16
const CELL := TILE / STEPS
const MIN_SEABED_DEPTH := 14.0
const MARINE_CEILING := -6.0

static func height_at(p: Vector2) -> float:
	var reef := p - Vector2(140, 80)
	var harbour := p - Vector2(-100, -180)
	var city := p - Vector2(-650, -480)
	var trench := p - Vector2(-370, -500)
	var shelf := -38.0 + 31.0 * exp(-reef.length_squared() / 24000.0)
	shelf += 17.0 * exp(-p.length_squared() / 12000.0)
	shelf += 9.0 * exp(-harbour.length_squared() / 10000.0)
	shelf -= 15.0 * exp(-city.length_squared() / 80000.0)
	shelf -= 34.0 * exp(-trench.length_squared() / 17000.0)
	var channel := reef.x - sin(reef.y * .035) * 9.0
	var banks := 2.8 * (1.0 - exp(-channel * channel / 65.0)) * exp(-reef.length_squared() / 9000.0)
	var relief := sin(p.x * .027 + cos(p.y * .018)) * 1.6 + cos(p.y * .031 - p.x * .011) * 1.2
	# Tall kelp and the rock arch need several metres of clear water above
	# their tops, including the trough of a moving ocean wave.
	return minf(-MIN_SEABED_DEPTH, shelf + banks + relief)

static func surface_height(p: Vector2) -> float:
	var cell := p / CELL
	var base := Vector2(floorf(cell.x), floorf(cell.y))
	var f := cell - base
	var point := base * CELL
	var a := height_at(point)
	var b := height_at(point + Vector2(CELL, 0))
	var c := height_at(point + Vector2(0, CELL))
	if f.x + f.y <= 1.0: return a + (b-a)*f.x + (c-a)*f.y
	var d := height_at(point + Vector2.ONE*CELL)
	return d + (c-d)*(1.0-f.x) + (b-d)*(1.0-f.y)

static func normal_at(p: Vector2) -> Vector3:
	return Vector3(height_at(p-Vector2(.3,0))-height_at(p+Vector2(.3,0)), .6,
		height_at(p-Vector2(0,.3))-height_at(p+Vector2(0,.3))).normalized()

static func mesh_at(tile: Vector2i) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var origin := Vector2(tile)*TILE
	for z in STEPS+1:
		for x in STEPS+1:
			var point := origin + Vector2(x,z)*CELL
			vertices.append(Vector3(x*CELL, height_at(point), z*CELL))
			normals.append(normal_at(point)); uv.append(point*.25)
			if x<STEPS and z<STEPS:
				var a := z*(STEPS+1)+x
				indices.append_array(PackedInt32Array([a,a+1,a+STEPS+1,a+1,a+STEPS+2,a+STEPS+1]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
