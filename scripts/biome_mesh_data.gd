extends RefCounted
## Pure CPU data; rendering, colliders and nodes stay on the main thread.
var arrays: Array=[]
var shore_bytes:=PackedByteArray()
static func height_at(point: Vector2,biome: String,radius: float) -> float:
	var angle:=atan2(point.y,point.x)
	var irregular:=1.0+sin(angle*3.0+.4)*.045+sin(angle*7.0)*.025
	var r:=point.length()/(radius*irregular)
	if r>=1.0:return -4.0
	var shore:=-4.0+smoothstep(1.0,.69,r)*5.6
	var relief:=(sin(point.x*.38+sin(point.y*.23))*sin(point.y*.29))*.34*smoothstep(.98,.55,r)
	if biome=="volcano":
		var cone:=maxf(0.0,1.0-absf(r-.285)/.48)*16.8
		var crater:=smoothstep(.18,.285,r)*4.0
		if r<.285:cone=12.8+crater
		cone+=(sin(angle*5.0+.6)*.75+sin(angle*9.0)*.45)*smoothstep(.65,.28,r)*smoothstep(.16,.25,r)
		return shore+cone+relief
	if biome=="spring":return shore+smoothstep(.85,.25,r)*2.2+relief*.5
	var hill:=smoothstep(.80,.18,r)*8.0
	var ridge:=exp(-pow((point.x+5.0)/12.0,2)-pow((point.y-2.0)/22.0,2))*9.0
	return shore+hill+ridge+relief
func build(biome: String,grid: int,radius: float) -> void:
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	var uv:=PackedVector2Array();var indices:=PackedInt32Array()
	for z in range(grid+1):
		for x in range(grid+1):
			var point:=Vector2((float(x)/grid*2-1)*radius,(float(z)/grid*2-1)*radius)
			vertices.append(Vector3(point.x,height_at(point,biome,radius),point.y))
			var dx:=height_at(point+Vector2(.3,0),biome,radius)-height_at(point-Vector2(.3,0),biome,radius)
			var dz:=height_at(point+Vector2(0,.3),biome,radius)-height_at(point-Vector2(0,.3),biome,radius)
			normals.append(Vector3(-dx,.6,-dz).normalized());uv.append(point*.1)
			if x<grid and z<grid:
				var index:=z*(grid+1)+x
				indices.append_array(PackedInt32Array([index,index+1,index+grid+1,index+1,index+grid+2,index+grid+1]))
	var result:=[];result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX]=vertices;result[Mesh.ARRAY_NORMAL]=normals
	result[Mesh.ARRAY_TEX_UV]=uv;result[Mesh.ARRAY_INDEX]=indices;arrays=result
	var shore:=PackedFloat32Array()
	for z in 32:
		for x in 32:shore.append(height_at(Vector2((float(x)+.5)/32*88-44,(float(z)+.5)/32*88-44),biome,radius))
	shore_bytes=shore.to_byte_array()
