extends RefCounted
## Original open clinker hull, ribs, seats and two working oars.
const ART:=preload("res://scripts/machine_visual.gd")
const MAT:=preload("res://scripts/object_materials.gd")
const DETAIL:=preload("res://scripts/hunting_visual.gd")
const SCANS:=preload("res://scripts/hunting_materials.gd")
static var _scene: PackedScene
const ASSEMBLY_PARTS := ["Hull","Interior","Seats","Oars"]
const ASSEMBLY_TASKS := ["Shape and seal the hull","Fit floorboards and ribs","Fasten the seats","Fit oars and launch fittings"]

static func assemble(root: Node3D, progress: float) -> void:
	for index in ASSEMBLY_PARTS.size():
		var part := root.get_node_or_null(ASSEMBLY_PARTS[index]) as Node3D
		if part == null:continue
		if not part.has_meta("assembly_rest"):part.set_meta("assembly_rest",part.position)
		var phase := clampf(progress*4.0-float(index),0.0,1.0)
		part.visible = progress*4.0 >= float(index)
		var rest: Vector3 = part.get_meta("assembly_rest")
		part.position = rest + Vector3(0,0.42,0)*(1.0-smoothstep(0.0,0.85,phase))

static func create() -> Node3D:
	var imported:=(load("res://models/hunting_rowboat.glb") as PackedScene).instantiate() as Node3D
	var boat:=imported.find_child("VictorianRowboat",true,false) as Node3D
	if boat==null:return imported
	boat.get_parent().remove_child(boat);imported.free();return boat

static func create_original() -> Node3D:
	if _scene!=null:return _scene.instantiate() as Node3D
	var root:=Node3D.new();root.name="OpenWoodenRowboat"
	var wood:=SCANS.wood()
	var trim:=wood.duplicate() as ShaderMaterial;trim.set_shader_parameter("base_color",Color(.72,.68,.60))
	var iron:=MAT.make(MAT.Kind.METAL,Color(.16,.17,.16),.7,.58)
	var caulk:=MAT.make(MAT.Kind.WOOD,Color(.075,.064,.047),.96)
	var hull:=Node3D.new();hull.name="Hull";root.add_child(hull)
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for side in [-1,1]:
		var rail_points: Array[Vector3]=[];var rail_radii: Array[Vector2]=[]
		for section in 24:
			var a:=float(section)/24;var b:=float(section+1)/24
			for strake in 7:
				var low:=float(strake)/7;var high:=float(strake+1)/7
				var p:=_hull_point(a,low,side);var q:=_hull_point(b,low,side)
				var r:=_hull_point(a,high,side);var t:=_hull_point(b,high,side)
				for point in ([p,r,q,q,r,t] if side>0 else [p,q,r,q,t,r]):
					surface.set_uv(Vector2(point.z*2,point.y*3));surface.add_vertex(point)
				if strake<6:ART.beam(hull,_hull_point(a,high,side)*Vector3(1.006,1,1),_hull_point(b,high,side)*Vector3(1.006,1,1),.006,caulk)
			rail_points.append(_hull_point(a,1,side));rail_radii.append(Vector2(.027,.024))
			if section==23:rail_points.append(_hull_point(1,1,side));rail_radii.append(Vector2(.027,.024))
		DETAIL.tube(hull,"RoundedGunwale",rail_points,rail_radii,trim,8)
	surface.index();surface.generate_normals()
	# Both the actual interior and exterior of the thin clinker hull are visible.
	ART.part(hull,surface.commit(),Vector3.ZERO,wood,"ClinkerHull")
	ART.beam(hull,Vector3(0,-.2,-1.8),Vector3(0,.56,-1.8),.045,trim)
	ART.beam(hull,Vector3(0,-.2,1.8),Vector3(0,.56,1.8),.045,trim)
	var interior:=Node3D.new();interior.name="Interior";root.add_child(interior)
	var bilge:=SurfaceTool.new();bilge.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section in 14:
		var a:=float(section)/14;var b:=float(section+1)/14
		var points:=[_hull_point(a,0,-1),_hull_point(a,0,1),_hull_point(b,0,-1),_hull_point(a,0,1),_hull_point(b,0,1),_hull_point(b,0,-1)]
		for point in points:bilge.set_uv(Vector2(point.x*3,point.z*3));bilge.add_vertex(point)
	bilge.generate_normals();ART.part(interior,bilge.commit(),Vector3.ZERO,wood,"SealedBilge")
	for plank in range(-3,4):
		var half_length:=1.48-absf(plank)*.15
		ART.box(interior,Vector3(plank*.105,-.12,0),Vector3(.100,.035,half_length*2),wood)
	for section in range(2,14,2):
		var t:=float(section)/16
		for side in [-1,1]:
			var ribs: Array[Vector3]=[];var radii: Array[Vector2]=[]
			for index in 7:
				var point:=_hull_point(t,float(index)/6,side);point.x*=.96
				ribs.append(point);radii.append(Vector2(.020,.026))
			DETAIL.tube(interior,"BentOakRib",ribs,radii,trim,8)
	var seats:=Node3D.new();seats.name="Seats";root.add_child(seats)
	for z in [-.74,.48]:
		for plank in 2:ART.box(seats,Vector3(0,.30,z-.075+plank*.15),Vector3(1.16,.058,.145),wood)
		for side in [-1,1]:
			ART.box(seats,Vector3(side*.49,.245,z),Vector3(.07,.07,.36),trim)
			for offset in [-.1,.1]:
				var nail:=ART.cylinder(seats,Vector3(side*.48,.331,z+offset),.009,.005,iron);nail.name="IronFastener"
	var gear:=Node3D.new();gear.name="Oars";root.add_child(gear)
	for side in [-1,1]:
		ART.cylinder(gear,Vector3(side*.65,.445,.36),.029,.09,iron)
		var lock:=TorusMesh.new();lock.inner_radius=.034;lock.outer_radius=.045;lock.rings=12;lock.ring_segments=6
		var lock_part:=ART.part(gear,lock,Vector3(side*.65,.49,.36),iron,"Oarlock");lock_part.rotation.z=PI/2
		var oar:=Node3D.new();oar.name="OarLeft" if side<0 else "OarRight";oar.position=Vector3(side*.65,.43,.36);gear.add_child(oar)
		DETAIL.tube(oar,"RoundOarShaft",[Vector3(-side*.36,.04,0),Vector3(side*.6,-.13,.17),Vector3(side*1.15,-.26,.24)],[Vector2(.021,.021),Vector2(.026,.026),Vector2(.021,.021)],wood,10)
		DETAIL.tube(oar,"TaperedOarBlade",[Vector3(side*.92,-.21,.21),Vector3(side*1.14,-.27,.26),Vector3(side*1.45,-.35,.31),Vector3(side*1.49,-.36,.32)],[Vector2(.021,.021),Vector2(.086,.018),Vector2(.10,.014),Vector2(.075,.009)],wood,10)
		DETAIL.merge_parts(oar)
	for group in [hull,interior,seats]:DETAIL.merge_parts(group)
	for node in root.find_children("*","Node",true,false):node.owner=root
	_scene=PackedScene.new();_scene.pack(root);root.free();return _scene.instantiate() as Node3D

static func _hull_point(t: float,height: float,side: int) -> Vector3:
	var width:=maxf(.025,pow(sin(t*PI),.65)*.74)
	return Vector3(side*width*lerpf(.45,1,pow(height,.75)),lerpf(-.23,.43,height)+pow(absf(t-.5)*2,3)*.14,-1.8+t*3.6)
