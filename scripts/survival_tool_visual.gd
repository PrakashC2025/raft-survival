extends RefCounted
## Original tools, in metres. Shared meshes/materials keep equips inexpensive.
const ART := preload("res://scripts/machine_visual.gd")
const MAT := preload("res://scripts/object_materials.gd")
const ITEMS := ["Axe", "Pickaxe", "Shovel", "Paddle", "Anchor"]
static var _cache: Dictionary = {}
static var _materials: Dictionary = {}

static func material(kind: String) -> Material:
	if not _materials.has(kind):
		_materials[kind] = MAT.make(MAT.Kind.WOOD if kind == "wood" else MAT.Kind.METAL,
			Color(.38,.24,.11) if kind == "wood" else Color(.38,.42,.43), .82 if kind == "wood" else .38, 0.0 if kind == "wood" else .75)
	return _materials[kind]

static func create(item: String) -> Node3D:
	var root := Node3D.new()
	root.name = item.replace(" ", "") + "Tool"
	if item not in ITEMS: return root
	var wood := material("wood")
	var metal := material("metal")
	if item == "Anchor":
		ART.cylinder(root,Vector3(0,.12,0),.022,.48,metal)
		var ring := TorusMesh.new();ring.inner_radius=.040;ring.outer_radius=.060;ring.rings=16;ring.ring_segments=8
		var eye := ART.part(root,ring,Vector3(0,.39,0),metal,"RopeEye");eye.rotation.x=PI/2
		ART.box(root,Vector3(0,.20,0),Vector3(.35,.035,.035),metal)
		for side in [-1.0,1.0]:
			var fluke := ART.box(root,Vector3(side*.11,-.08,0),Vector3(.24,.035,.09),metal)
			fluke.rotation.z=side*.60
			_blade(root,"anchor",PackedVector2Array([Vector2(-.055,0),Vector2(.055,0),Vector2(.0,.12)]),.025,Vector3(side*.20,-.01,0),metal)
		return root
	var length := 1.20 if item == "Paddle" else (.90 if item == "Shovel" else .58)
	ART.cylinder(root,Vector3(0,length*.20,0),.021,length,wood)
	for index in range(5):
		var grip_wrap := TorusMesh.new();grip_wrap.inner_radius=.020;grip_wrap.outer_radius=.024;grip_wrap.rings=12;grip_wrap.ring_segments=6
		ART.part(root,grip_wrap,Vector3(0,-.035+index*.014,0),metal,"GripWrap")
	match item:
		"Axe":
			_blade(root,"axe",PackedVector2Array([Vector2(-.06,.0),Vector2(.10,-.02),Vector2(.24,-.10),Vector2(.27,.10),Vector2(.10,.13),Vector2(-.06,.11)]),.052,Vector3(0,.34,0),metal)
			ART.box(root,Vector3(-.065,.39,0),Vector3(.06,.08,.07),metal)
		"Pickaxe":
			_blade(root,"pick",PackedVector2Array([Vector2(-.32,-.09),Vector2(-.13,.065),Vector2(.12,.065),Vector2(.32,-.09),Vector2(.12,.015),Vector2(-.13,.015)]),.045,Vector3(0,.38,0),metal)
		"Shovel":
			_blade(root,"shovel",PackedVector2Array([Vector2(-.095,.13),Vector2(.095,.13),Vector2(.105,-.08),Vector2(0,-.16),Vector2(-.105,-.08)]),.018,Vector3(0,.67,0),metal)
			ART.cylinder(root,Vector3(0,.52,0),.026,.16,metal)
		"Paddle":
			_blade(root,"paddle",PackedVector2Array([Vector2(-.025,0),Vector2(.10,.15),Vector2(.12,.45),Vector2(.07,.51),Vector2(-.07,.51),Vector2(-.12,.45),Vector2(-.10,.15)]),.025,Vector3(0,.70,0),wood)
	return root

static func _blade(root: Node3D,key: String,outline: PackedVector2Array,depth: float,at: Vector3,mat: Material) -> void:
	if not _cache.has(key):
		var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var indices := Geometry2D.triangulate_polygon(outline)
		for face in [-1.0,1.0]:
			for triangle in range(0,indices.size(),3):
				for corner in ([0,1,2] if face < 0 else [2,1,0]):
					var point := outline[indices[triangle+corner]]
					surface.add_vertex(Vector3(point.x,point.y,face*depth*.5))
		for index in outline.size():
			var a := outline[index];var b := outline[(index+1)%outline.size()]
			for point in [Vector3(a.x,a.y,-depth*.5),Vector3(a.x,a.y,depth*.5),Vector3(b.x,b.y,depth*.5),
					Vector3(a.x,a.y,-depth*.5),Vector3(b.x,b.y,depth*.5),Vector3(b.x,b.y,-depth*.5)]:surface.add_vertex(point)
		surface.generate_normals();_cache[key]=surface.commit()
	ART.part(root,_cache[key],at,mat,"ForgedBlade")
