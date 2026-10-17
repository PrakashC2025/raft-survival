extends RefCounted
## Original articulated wildlife with tapered anatomy and shared material artwork.
const ART:=preload("res://scripts/machine_visual.gd")
const SURFACE:=preload("res://scripts/object_materials.gd")
const SCANS:=preload("res://scripts/hunting_materials.gd")
static var _animals: Dictionary={}

static func spear() -> Node3D:
	var root:=Node3D.new();root.name="StoneTippedSpear"
	var wood:=SURFACE.make(SURFACE.Kind.WOOD,Color(.36,.23,.10),.92)
	var shaft:=ART.cylinder(root,Vector3(0,0,.04),.022,1.52,wood);shaft.rotation.x=PI/2
	var stone:=SURFACE.make(SURFACE.Kind.STONE,Color(.43,.46,.44),.85)
	var tip:=SurfaceTool.new();tip.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners:=[Vector3(-.065,0,-.65),Vector3(0,.028,-.65),Vector3(.065,0,-.65),Vector3(0,-.028,-.65)]
	for side in 4:
		for point in [corners[side],Vector3(0,0,-.94),corners[(side+1)%4]]:tip.add_vertex(point)
	tip.generate_normals();ART.part(root,tip.commit(),Vector3.ZERO,stone,"FlakedStoneTip")
	var rope:=SURFACE.make(SURFACE.Kind.CLOTH,Color(.65,.54,.33),.95)
	for ring in 5:
		var binding:=ART.cylinder(root,Vector3(0,0,-.58-ring*.018),.030,.013,rope);binding.rotation.x=PI/2
	return root

static func _ellipsoid(root: Node3D,at: Vector3,size: Vector3,material: Material,label: String) -> MeshInstance3D:
	var mesh:=SphereMesh.new();mesh.radius=1;mesh.height=2;mesh.radial_segments=20;mesh.rings=12
	var part:=ART.part(root,mesh,at,material,label);part.scale=size;return part

static func _solid(color: Color,roughness: float=.8) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=roughness;return material

static func _joint(root: Node3D,label: String,at: Vector3) -> Node3D:
	var joint:=Node3D.new();joint.name=label;joint.position=at;root.add_child(joint);return joint

static func tube(root: Node3D,label: String,points: Array[Vector3],radii: Array[Vector2],material: Material,sides: int=14) -> MeshInstance3D:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES);surface.set_smooth_group(0)
	var rings: Array[PackedVector3Array]=[]
	for index in points.size():
		var tangent: Vector3=(points[mini(index+1,points.size()-1)]-points[maxi(0,index-1)]).normalized()
		var right:=tangent.cross(Vector3.UP if absf(tangent.y)<.95 else Vector3.FORWARD).normalized()
		var up:=right.cross(tangent).normalized()
		var ring:=PackedVector3Array()
		for side in sides:
			var angle:=side*TAU/sides;ring.append(points[index]+right*cos(angle)*radii[index].x+up*sin(angle)*radii[index].y)
		rings.append(ring)
	for index in range(points.size()-1):
		for side in sides:
			var next: int=(side+1)%sides
			for point in [rings[index][side],rings[index+1][side],rings[index][next],rings[index][next],rings[index+1][side],rings[index+1][next]]:surface.add_vertex(point)
	for side in sides:
		var next: int=(side+1)%sides
		for point in [points[0],rings[0][side],rings[0][next],points[-1],rings[-1][next],rings[-1][side]]:surface.add_vertex(point)
	surface.index();surface.generate_normals()
	return ART.part(root,surface.commit(),Vector3.ZERO,material,label)

static func _ridge(root: Node3D,at: Vector3,size: Vector3,material: Material) -> void:
	var mesh:=SurfaceTool.new();mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a:=at+Vector3(-size.x,0,-size.z);var b:=at+Vector3(size.x,0,-size.z)
	var c:=at+Vector3(0,0,size.z);var tip:=at+Vector3(0,size.y,-size.z*.2)
	for point in [a,tip,b,b,tip,c,c,tip,a]:mesh.add_vertex(point)
	mesh.generate_normals();ART.part(root,mesh.commit(),Vector3.ZERO,material,"DorsalScute")

static func _finish(root: Node3D,key: String) -> Node3D:
	_merge_tree(root)
	for node in root.find_children("*","Node",true,false):node.owner=root
	var scene:=PackedScene.new();scene.pack(root);_animals[key]=scene;root.free()
	return scene.instantiate() as Node3D

static func _merge_tree(root: Node3D) -> void:
	for child in root.get_children():
		if child is Node3D and not child is MeshInstance3D:_merge_tree(child)
	merge_parts(root)

static func crocodile() -> Node3D:
	if _animals.has("Crocodile"):return (_animals.Crocodile as PackedScene).instantiate() as Node3D
	var root:=Node3D.new();root.name="CrocodileModel"
	var skin:=SCANS.skin("Crocodile");var dark:=_solid(Color(.045,.038,.022));var ivory:=_solid(Color(.63,.59,.41))
	tube(root,"MuscularTrunk",[Vector3(0,.23,-.73),Vector3(0,.25,-.5),Vector3(0,.25,-.22),Vector3(0,.23,.15),Vector3(0,.21,.5),Vector3(0,.2,.77)],[Vector2(.16,.12),Vector2(.29,.17),Vector2(.36,.19),Vector2(.35,.17),Vector2(.25,.14),Vector2(.16,.11)],skin,22)
	tube(root,"LowerJaw",[Vector3(0,.19,-1.39),Vector3(0,.18,-1.19),Vector3(0,.18,-.94),Vector3(0,.2,-.6)],[Vector2(.09,.022),Vector2(.13,.034),Vector2(.19,.043),Vector2(.22,.05)],skin,18)
	var jaw:=_joint(root,"UpperJaw",Vector3(0,.27,-.57))
	tube(jaw,"TaperedSkull",[Vector3(0,-.018,-.83),Vector3(0,-.01,-.65),Vector3(0,.0,-.38),Vector3(0,.02,-.14),Vector3(0,0,.09)],[Vector2(.10,.032),Vector2(.13,.038),Vector2(.19,.052),Vector2(.23,.093),Vector2(.16,.09)],skin,22)
	var amber:=_solid(Color(.47,.40,.14),.3)
	for side in [-1,1]:
		_ellipsoid(jaw,Vector3(side*.187,.073,-.15),Vector3(.055,.043,.075),skin,"EyeRidge")
		_ellipsoid(jaw,Vector3(side*.222,.084,-.18),Vector3(.021,.019,.026),amber,"AmberEye")
		_ellipsoid(jaw,Vector3(side*.234,.085,-.188),Vector3(.006,.014,.01),dark,"VerticalPupil")
		_ellipsoid(jaw,Vector3(side*.075,.018,-.77),Vector3(.015,.007,.021),dark,"Nostril")
		for index in 9:
			var t:=float(index)/8;var z:=lerpf(-.76,-.18,t);var x:=lerpf(.09,.215,t)
			tube(jaw,"InterlockingTeeth",[Vector3(side*x,-.035,z),Vector3(side*x,-.069,z)],[Vector2(.009,.009),Vector2(.001,.001)],ivory,5)
		for index in 2:
			var leg:=_joint(root,"Leg_%d_%d"%[side,index],Vector3(side*.25,.18,-.39+index*.93))
			tube(leg,"SplayedLimb",[Vector3.ZERO,Vector3(side*.19,-.025,.12),Vector3(side*.25,-.10,.10),Vector3(side*.34,-.14,-.04)],[Vector2(.10,.09),Vector2(.085,.07),Vector2(.055,.052),Vector2(.07,.035)],skin)
			for toe in 4:
				var base:=Vector3(side*.34+(toe-1.5)*.035,-.145,-.045)
				tube(leg,"Toe",[base,base+Vector3((toe-1.5)*.018,-.004,-.12)],[Vector2(.016,.016),Vector2(.007,.007)],skin,6)
				_ellipsoid(leg,base+Vector3((toe-1.5)*.018,0,-.13),Vector3(.009,.009,.026),ivory,"Claw")
	var tail:=_joint(root,"TailFin",Vector3(0,.2,.71))
	tube(tail,"TailBase",[Vector3.ZERO,Vector3(0,-.015,.28),Vector3(0,-.045,.57)],[Vector2(.19,.13),Vector2(.16,.115),Vector2(.115,.095)],skin,18)
	var middle:=_joint(tail,"TailMiddle",Vector3(0,-.045,.57))
	tube(middle,"TailMiddleSkin",[Vector3.ZERO,Vector3(0,-.015,.26),Vector3(0,-.025,.52)],[Vector2(.115,.095),Vector2(.075,.078),Vector2(.04,.055)],skin)
	var tip:=_joint(middle,"TailTip",Vector3(0,-.025,.52))
	tube(tip,"WhipTip",[Vector3.ZERO,Vector3(0,.012,.22),Vector3(0,.04,.46)],[Vector2(.04,.055),Vector2(.018,.031),Vector2(.002,.004)],skin,10)
	for row in 5:
		for scute in 11:
			var x: float=(row-2)*.105;var z: float=-.46+scute*.102
			_ridge(root,Vector3(x,.407-absf(x)*.16-absf(z)*.055,z),Vector3(.037,.027 if row%2==0 else .04,.042),skin)
	for group in [tail,middle,tip]:
		for index in 5:
			_ridge(group,Vector3(0,.10-index*.01,.06+index*.09),Vector3(.018,.055-index*.005,.04),skin)
	return _finish(root,"Crocodile")

static func boar() -> Node3D:
	if _animals.has("Boar"):return (_animals.Boar as PackedScene).instantiate() as Node3D
	var root:=Node3D.new();root.name="WildBoarModel";var fur:=SCANS.skin("Boar")
	var horn:=_solid(Color(.56,.52,.39));var black:=_solid(Color(.022,.018,.012),.45);var snout:=_solid(Color(.18,.135,.10))
	tube(root,"BarrelAndShoulders",[Vector3(0,.69,-.55),Vector3(0,.72,-.32),Vector3(0,.67,.02),Vector3(0,.62,.38),Vector3(0,.6,.69)],[Vector2(.26,.31),Vector2(.35,.42),Vector2(.34,.37),Vector2(.28,.30),Vector2(.10,.20)],fur,24)
	tube(root,"WedgeHead",[Vector3(0,.57,-1.02),Vector3(0,.61,-.88),Vector3(0,.69,-.64),Vector3(0,.73,-.43)],[Vector2(.10,.08),Vector2(.13,.13),Vector2(.20,.23),Vector2(.23,.25)],fur,18)
	_ellipsoid(root,Vector3(0,.57,-1.025),Vector3(.107,.078,.028),snout,"LeatherySnout")
	for side in [-1,1]:
		_ellipsoid(root,Vector3(side*.046,.577,-1.05),Vector3(.018,.013,.005),black,"Nostril")
		_ellipsoid(root,Vector3(side*.169,.79,-.741),Vector3(.023,.019,.025),black,"SmallEye")
		tube(root,"CurvedTusk",[Vector3(side*.13,.52,-.85),Vector3(side*.19,.54,-.9),Vector3(side*.205,.62,-.92)],[Vector2(.028,.028),Vector2(.021,.021),Vector2(.001,.001)],horn,8)
		var ear:=_joint(root,"Ear_%d"%side,Vector3(side*.14,.86,-.53))
		_ridge(ear,Vector3.ZERO,Vector3(.085,.20,.10),fur);ear.rotation.z=-side*.25
		for index in 2:
			var leg:=_joint(root,"Leg_%d_%d"%[side,index],Vector3(side*.22,.55,-.35+index*.83))
			tube(leg,"UpperLeg",[Vector3.ZERO,Vector3(0,-.16,.025),Vector3(0,-.29,.06)],[Vector2(.105,.12),Vector2(.075,.08),Vector2(.046,.05)],fur)
			var knee:=_joint(leg,"Knee",Vector3(0,-.29,.06))
			tube(knee,"LowerLeg",[Vector3.ZERO,Vector3(0,-.13,-.035),Vector3(0,-.23,-.04)],[Vector2(.046,.05),Vector2(.032,.037),Vector2(.033,.037)],fur,10)
			for hoof in [-1,1]:_ellipsoid(knee,Vector3(hoof*.024,-.24,-.06),Vector3(.025,.038,.06),black,"SplitHoof")
	for index in 15:
		var z: float=-.47+index*.064
		_ridge(root,Vector3(0,1.08-maxf(0,z+.1)*.36,z),Vector3(.035,.065+sin(index*.9)*.015,.055),fur)
	tube(root,"CurledTail",[Vector3(0,.64,.62),Vector3(0,.68,.82),Vector3(.07,.73,.87),Vector3(.11,.78,.81),Vector3(.07,.8,.77)],[Vector2(.025,.025),Vector2(.022,.022),Vector2(.018,.018),Vector2(.013,.013),Vector2(.005,.005)],fur,8)
	return _finish(root,"Boar")

static func octopus() -> Node3D:
	if _animals.has("Octopus"):return (_animals.Octopus as PackedScene).instantiate() as Node3D
	var root:=Node3D.new();root.name="ReefOctopus";var skin:=SCANS.skin("Octopus")
	_ellipsoid(root,Vector3(0,.29,.16),Vector3(.235,.31,.31),skin,"PearShapedMantle")
	_ellipsoid(root,Vector3(0,.13,-.07),Vector3(.25,.125,.24),skin,"ArmWeb")
	var iris:=_solid(Color(.47,.38,.23),.3);var pupil:=_solid(Color(.012,.015,.014),.22)
	var sucker:=_solid(Color(.48,.40,.30),.78)
	for side in [-1,1]:
		_ellipsoid(root,Vector3(side*.205,.21,-.13),Vector3(.047,.037,.043),skin,"EyeFold")
		_ellipsoid(root,Vector3(side*.24,.22,-.15),Vector3(.023,.026,.026),iris,"Eye")
		_ellipsoid(root,Vector3(side*.258,.22,-.16),Vector3(.01,.006,.02),pupil,"HorizontalPupil")
	for index in 8:
		var arm:=_joint(root,"Leg_Tentacle%d"%index,Vector3.ZERO);arm.rotation.y=index*TAU/8
		var points: Array[Vector3]=[];var radii: Array[Vector2]=[]
		for segment in 15:
			var t:=float(segment)/14
			points.append(Vector3(sin(t*4.7+index*.35)*t*.22,.105-t*.11+pow(maxf(0,t-.7),2)*1.1,.12+t*.70-pow(maxf(0,t-.8),2)*2.5))
			var radius:=.072*pow(1-t,1.2)+.004;radii.append(Vector2(radius,radius*.8))
		tube(arm,"CurvedTaperedArm",points,radii,skin,10)
		for row in [-1,1]:
			for cup in 8:
				var t:=float(cup+2)/12;var centre: Vector3=points[mini(13,cup+2)]+Vector3(row*.025*(1-t),-.038*(1-t),0)
				var ring:=TorusMesh.new();ring.inner_radius=.007*(1-t)+.002;ring.outer_radius=.015*(1-t)+.003;ring.rings=8;ring.ring_segments=6
				ART.part(arm,ring,centre,sucker,"SuctionCup")
	return _finish(root,"Octopus")

static func merge_parts(group: Node3D) -> void:
	var batches: Dictionary={}
	for child in group.get_children():
		if not child is MeshInstance3D:continue
		var part:=child as MeshInstance3D
		var material:=part.material_override
		var key:=material.get_instance_id() if material!=null else 0
		if not batches.has(key):
			var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key]={"surface":surface,"material":material}
		for index in part.mesh.get_surface_count():batches[key].surface.append_from(part.mesh,index,part.transform)
		part.free()
	for data in batches.values():
		var mesh:=MeshInstance3D.new();mesh.mesh=data.surface.commit();mesh.material_override=data.material
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;group.add_child(mesh)
