extends Node3D
const BUDGET:=preload("res://scripts/frame_work_budget.gd")
const ART:=preload("res://scripts/machine_visual.gd")
const CREATURE:=preload("res://scripts/dive_creature.gd")
const GRID:=64
const EXTENT:=2100.0
const SITES:=[{"id":"SunkenHarbour","label":"Sunken Harbour","at":Vector2(-100,-180)}, {"id":"DeepCity","label":"Deep City","at":Vector2(-650,-480)}, {"id":"ReefGarden","label":"Reef Garden","at":Vector2(140,80)}]
var prepared:=false
var _saved: Dictionary={}
var _player: Node3D
var _hands: Node3D
var _hands_visible:=false
var _swim_time:=0.0
var _ground_material: ShaderMaterial
var _ruin_material: ShaderMaterial
var _kelp_material: ShaderMaterial
var _ruin_builder: SurfaceTool
static var _kelp_mesh: ArrayMesh

func _ready() -> void:
	add_to_group("underwater_world")
	_saved=Inventory.loaded_meta.get("underwater_creatures",{}).duplicate(true)
	call_deferred("_prepare")

static func height_at(p: Vector2) -> float:return -34.0+sin(p.x*.009)*1.5+cos(p.y*.008)*1.3
static func surface_height(p: Vector2) -> float:
	var cell:=(p/float(EXTENT*2)+Vector2.ONE*.5)*GRID
	var base:=Vector2(floorf(cell.x),floorf(cell.y));var f:=cell-base
	var point:=(base/GRID-Vector2.ONE*.5)*EXTENT*2;var step:=EXTENT*2/GRID
	var a:=height_at(point);var b:=height_at(point+Vector2(step,0));var c:=height_at(point+Vector2(0,step))
	if f.x+f.y<=1:return a+(b-a)*f.x+(c-a)*f.y
	var d:=height_at(point+Vector2.ONE*step);return d+(c-d)*(1-f.x)+(b-d)*(1-f.y)

func _prepare() -> void:
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var indices:=PackedInt32Array()
	for z in range(GRID+1):
		for x in range(GRID+1):
			var p:=Vector2(float(x)/GRID-.5,float(z)/GRID-.5)*EXTENT*2
			vertices.append(Vector3(p.x,height_at(p),p.y));normals.append(Vector3.UP)
			if x<GRID and z<GRID:
				var a:=z*(GRID+1)+x;indices.append_array(PackedInt32Array([a,a+1,a+GRID+1,a+1,a+GRID+2,a+GRID+1]))
			if BUDGET.exhausted():await get_tree().process_frame;if not is_inside_tree():return
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_ground_material=ShaderMaterial.new();_ground_material.shader=preload("res://shaders/undersea_surface.gdshader")
	_ground_material.set_shader_parameter("surface_texture",preload("res://textures/island/sand_diff.jpg"))
	_ground_material.set_shader_parameter("surface_normal",preload("res://textures/island/sand_nor_gl.jpg"))
	_ruin_material=_ground_material.duplicate() as ShaderMaterial;_ruin_material.set_shader_parameter("masonry",true)
	_ruin_material.set_shader_parameter("surface_texture",preload("res://textures/island/rock_diff.jpg"));_ruin_material.set_shader_parameter("surface_normal",preload("res://textures/island/rock_nor_gl.jpg"))
	var floor_visual:=ART.part(self,mesh,Vector3.ZERO,_ground_material,"OceanSandFloor");floor_visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await get_tree().process_frame
	if not is_inside_tree():return
	var ground:=preload("res://scripts/seabed.gd").new();ground.name="CollectibleSeabed";add_child(ground)
	var collider:=CollisionShape3D.new();collider.shape=mesh.create_trimesh_shape();ground.add_child(collider)
	_kelp_material=ShaderMaterial.new();_kelp_material.shader=preload("res://shaders/sea_plants.gdshader")
	_kelp_material.set_shader_parameter("leaf_texture",preload("res://textures/underwater/kelp.svg"))
	for site in SITES:
		var marker:=Node3D.new();marker.name=site.id;marker.position=Vector3(site.at.x,0,site.at.y);marker.add_to_group("dive_site");marker.set_meta("map_label",site.label);marker.set_meta("biome","underwater");marker.set_meta("arrival_radius",18.0);add_child(marker)
		await _site(site)
		if not is_inside_tree():return
	prepared=true;_player=get_tree().get_first_node_in_group("player") as Node3D
	if _player!=null:
		_hands=Node3D.new();_hands.name="SwimmingHands";_player.camera.add_child(_hands)
		_hands.add_child(preload("res://scripts/dive_visual.gd").swim_hand(true));_hands.add_child(preload("res://scripts/dive_visual.gd").swim_hand(false));_hands.hide()

func _site(site: Dictionary) -> void:
	var centre:Vector2=site.at
	if site.id!="ReefGarden":
		for building in 9:
			var p:=centre+Vector2((building%3-1)*13,(floori(float(building)/3)-1)*14)
			var h:=surface_height(p)
			var shell:=Node3D.new();shell.name="RuinedHouse%s%d"%[site.id,building];shell.position=Vector3(p.x,h,p.y);add_child(shell)
			_ruin_builder=SurfaceTool.new();_ruin_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Window/door openings and broken tops are real geometry, not boxes.
			for side in 4:
				var wall:=Node3D.new();wall.rotation.y=side*PI/2;shell.add_child(wall)
				for column in 3:
					var height:=3.0+float(posmod(building*7+side*3+column,4))*.7
					_solid(wall,Vector3(-3+column*3,height*.5,3.3),Vector3(.7,height,.45))
				if side!=0:_solid(wall,Vector3(0,.50,3.3),Vector3(6.7,1,.45))
				_solid(wall,Vector3(0,2.9,3.3),Vector3(6.7,.42,.45))
			var masonry:=ART.part(shell,_ruin_builder.commit(),Vector3.ZERO,_ruin_material,"BrokenWalls")
			masonry.visibility_range_end=180;masonry.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ruin_builder=null
			for rubble in 5:
				var rock:=ART.part(shell,preload("res://scripts/island_landscape.gd")._rock_mesh(),Vector3(sin(rubble*2.4)*4,.3,cos(rubble*2.4)*4),_ruin_material,"BrokenMasonry")
				rock.scale=Vector3(.75,.4,.8);rock.rotation=Vector3(.2,rubble*.8,.3);rock.visibility_range_end=180
			await get_tree().process_frame
			if not is_inside_tree():return
	var meadow:=MultiMeshInstance3D.new();meadow.name="SeaGrass"+str(site.id)
	var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=_kelp();batch.instance_count=80
	var rng:=RandomNumberGenerator.new();rng.seed=int(centre.x*13+centre.y*19)+31887
	for index in 80:
		var p:=centre+Vector2(rng.randf_range(-25,25),rng.randf_range(-25,25));var size:=rng.randf_range(.45,1.4)
		batch.set_instance_transform(index,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*size),Vector3(p.x,surface_height(p),p.y)))
	meadow.multimesh=batch;meadow.material_override=_kelp_material;meadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;meadow.visibility_range_end=150;add_child(meadow)
	var shoal:=preload("res://scripts/underwater_shoal.gd").new();shoal.name="FishSchool"+str(site.id);shoal.position=Vector3(centre.x,surface_height(centre)+7,centre.y);add_child(shoal)
	for index in 10:
		var creature:=CREATURE.new();creature.species="Fish" if index<6 else ("Crab" if index<8 else ("Turtle" if index==8 else "Ray"));creature.creature_id=str(site.id)+":"+str(index)
		var p:=centre+Vector2(cos(index*2.4)*18,sin(index*2.4)*18)
		if index<6:
			creature.school_centre=shoal.position;creature.school_offset=Vector3((index%3-1)*1.1,(index%2)*.25,-floorf(float(index)/3)*.85)
			p=centre+Vector2(creature.school_offset.x,9+creature.school_offset.z)
		creature.position=Vector3(p.x,surface_height(p)+(.22 if creature.species=="Crab" else 3.5+index*.2),p.y);creature.home=creature.position;add_child(creature)
		if _saved.get(creature.creature_id) is Dictionary:creature.restore_state(_saved[creature.creature_id])
		await get_tree().process_frame
		if not is_inside_tree():return

func _solid(parent: Node3D,at: Vector3,size: Vector3) -> void:
	var block:=BoxMesh.new();block.size=size
	_ruin_builder.append_from(block,0,parent.transform*Transform3D(Basis.IDENTITY,at))
	var body:=StaticBody3D.new();body.position=at;parent.add_child(body)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape)

static func _kelp() -> ArrayMesh:
	if _kelp_mesh!=null:return _kelp_mesh
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for stalk in 7:
		var angle:=stalk*2.4
		var reach:=1.1+float(stalk%3)*.4
		for segment in 10:
			var t:=float(segment)/10;var next:=float(segment+1)/10
			var a:=Vector3(cos(angle)*t*t*.65,t*reach,sin(angle)*t*t*.65)
			var b:=Vector3(cos(angle)*next*next*.65,next*reach,sin(angle)*next*next*.65)
			var width:=sin(t*PI)*.14;var tip_width:=sin(next*PI)*.14
			var side:=Vector3(cos(angle+PI/2),0,sin(angle+PI/2))
			var points:=[a-side*width,a+side*width,b-side*tip_width,a+side*width,b+side*tip_width,b-side*tip_width]
			var uv:=[Vector2(0,t),Vector2(1,t),Vector2(0,next),Vector2(1,t),Vector2(1,next),Vector2(0,next)]
			for vertex in 6:surface.set_uv(uv[vertex]);surface.add_vertex(points[vertex])
	surface.generate_normals();_kelp_mesh=surface.commit();return _kelp_mesh

func _process(delta: float) -> void:
	if _player==null or not is_instance_valid(_hands):return
	_swim_time+=delta
	var hud:=_player.get_node_or_null("CanvasLayer/SurvivalHUD")
	var swimming:bool=_player.is_swimming and _player.cam_mode==0 and _player.get_node("SurvivalAction").kind.is_empty() and not _player.build_mode and Stats.health>0 and not GameSettings.is_open and not (hud!=null and hud.call("gameplay_input_blocked"))
	_hands.visible=swimming
	if swimming:
		for index in 2:
			var hand:=_hands.get_child(index) as Node3D;var phase:=_swim_time*3.8+index*PI
			hand.visible=index==0 or str(_player.active_item).is_empty()
			hand.position=Vector3((-1 if index==0 else 1)*(.25+.08*cos(phase)),-.28+.07*sin(phase),-.45-.26*maxf(0,sin(phase)))
			hand.rotation=Vector3(.35+sin(phase)*.24,0,(-1 if index==0 else 1)*(.15+.22*cos(phase)))
	var hide_fist:=swimming and str(_player.active_item).is_empty()
	if hide_fist!=_hands_visible:_hands_visible=hide_fist;_player.call("_apply_camera_mode");_player._fist_node.visible=not hide_fist and _player.cam_mode==0

func save_state() -> Dictionary:
	var data:=_saved.duplicate(true)
	for child in get_children():
		if child.is_in_group("dive_creature"):data[child.creature_id]=child.save_state()
	return data

func _exit_tree() -> void:
	if is_instance_valid(_hands):_hands.queue_free()
