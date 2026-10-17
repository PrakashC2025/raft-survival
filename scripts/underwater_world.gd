extends Node3D
const MESH_DATA:=preload("res://scripts/underwater_mesh_data.gd")
const ART:=preload("res://scripts/machine_visual.gd")
const CREATURE:=preload("res://scripts/dive_creature.gd")
const TERRAIN:=preload("res://scripts/underwater_terrain.gd")
const REEF:=preload("res://scripts/underwater_reef_visual.gd")
const GRID:=64
const EXTENT:=2100.0
const SITES:=[{"id":"SunkenHarbour","label":"Sunken Harbour","at":Vector2(-100,-180)}, {"id":"DeepCity","label":"Deep City","at":Vector2(-650,-480)}, {"id":"ReefGarden","label":"Reef Garden","at":Vector2(140,80)}]
var resource_state: Dictionary={}
var stream: Node3D
var _lighting_tick:=0.0
var _shafts: Array[MeshInstance3D]=[]
var _accent_material: ShaderMaterial
var _accents: Array[MultiMeshInstance3D]=[]
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
var _mesh_task := -1
var _mesh_data: RefCounted
static var _kelp_mesh: ArrayMesh

func _ready() -> void:
	add_to_group("underwater_world")
	_saved=Inventory.loaded_meta.get("underwater_creatures",{}).duplicate(true)
	resource_state=Inventory.loaded_meta.get("underwater_resources",{}).duplicate(true)
	call_deferred("_prepare")

static func height_at(point: Vector2) -> float:return TERRAIN.height_at(point)
static func surface_height(point: Vector2) -> float:return TERRAIN.surface_height(point)

func _prepare() -> void:
	_mesh_data = MESH_DATA.new()
	_mesh_task = WorkerThreadPool.add_task(_mesh_data.build.bind(GRID,EXTENT),false,"Ocean floor geometry")
	while not WorkerThreadPool.is_task_completed(_mesh_task):
		await get_tree().process_frame
		if not is_inside_tree():return
	WorkerThreadPool.wait_for_task_completion(_mesh_task)
	_mesh_task = -1
	var arrays: Array = _mesh_data.arrays
	_mesh_data = null
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_ground_material=ShaderMaterial.new();_ground_material.shader=preload("res://shaders/undersea_surface.gdshader")
	_ground_material.set_shader_parameter("surface_texture",preload("res://textures/underwater/coast_diff.jpg"))
	_ground_material.set_shader_parameter("surface_normal",preload("res://textures/underwater/coast_nor_gl.jpg"))
	_ground_material.set_shader_parameter("surface_arm",preload("res://textures/underwater/coast_arm.jpg"))
	_ground_material.set_shader_parameter("surface_scale",1.0/12.0)
	_ruin_material=_ground_material.duplicate() as ShaderMaterial;_ruin_material.set_shader_parameter("masonry",true)
	_ruin_material.set_shader_parameter("surface_scale",0.32)
	_ruin_material.set_shader_parameter("surface_texture",preload("res://textures/island/rock_diff.jpg"));_ruin_material.set_shader_parameter("surface_normal",preload("res://textures/island/rock_nor_gl.jpg"))
	_ruin_material.set_shader_parameter("surface_arm",preload("res://textures/island/rock_arm.jpg"))
	var floor_visual:=ART.part(self,mesh,Vector3.ZERO,_ground_material.duplicate(),"OceanSandFloor");floor_visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await get_tree().process_frame
	if not is_inside_tree():return
	var ground:=preload("res://scripts/seabed.gd").new();ground.name="CollectibleSeabed";add_child(ground)
	var collider:=CollisionShape3D.new();collider.shape=mesh.create_trimesh_shape();ground.add_child(collider)
	_kelp_material=ShaderMaterial.new();_kelp_material.shader=preload("res://shaders/sea_plants.gdshader")
	_kelp_material.set_shader_parameter("leaf_texture",preload("res://textures/underwater/kelp.svg"))
	stream=preload("res://scripts/underwater_stream.gd").new();stream.name="ReefStream";stream.world=self;stream.ground=ground;add_child(stream)
	_make_reef_passages()
	_make_reef_accents()
	for site in SITES:
		var marker:=Node3D.new();marker.name=site.id;marker.position=Vector3(site.at.x,0,site.at.y);marker.add_to_group("dive_site");marker.set_meta("map_label",site.label);marker.set_meta("biome","underwater");marker.set_meta("arrival_radius",18.0);add_child(marker)
		await _site(site)
		if not is_inside_tree():return
	await _extra_marine_life()
	if not is_inside_tree():return
	prepared=true;_player=get_tree().get_first_node_in_group("player") as Node3D
	if _player!=null:
		var open_school:=preload("res://scripts/underwater_shoal.gd").new()
		open_school.name="OpenOceanFish";open_school.follow_diver=true
		open_school.position=_player.global_position+Vector3(0,-4,-10)
		open_school._centre=Vector3.ZERO;open_school._target=Vector3.ZERO
		add_child(open_school)
		_hands=Node3D.new();_hands.name="SwimmingHands";_player.camera.add_child(_hands)
		_hands.add_child(preload("res://scripts/dive_visual.gd").swim_hand(true));_hands.add_child(preload("res://scripts/dive_visual.gd").swim_hand(false));_hands.hide()

func _extra_marine_life() -> void:
	# Keep the original thirty IDs/order intact; append twenty bounded actors.
	var habitats:=[{"id":"NearRaft","at":Vector2(10,-22),"count":8}]
	for site in SITES:habitats.append({"id":str(site.id)+"Extra","at":site.at,"count":4})
	for habitat in habitats:
		for index in int(habitat.count):
			var creature:=CREATURE.new()
			creature.species=["Grouper","Octopus","Fish","Turtle"][index%4]
			creature.creature_id=str(habitat.id)+":"+str(index)
			var centre: Vector2=habitat.at
			var point:=centre+Vector2(cos(index*2.4)*8,sin(index*2.4)*8)
			var depth:=surface_height(point)
			creature.position=Vector3(point.x,depth+(.35 if creature.species=="Octopus" else 5.0),point.y)
			creature.home=creature.position;creature.school_centre=creature.position
			add_child(creature)
			if _saved.get(creature.creature_id) is Dictionary:creature.restore_state(_saved[creature.creature_id])
			await get_tree().process_frame
			if not is_inside_tree():return

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
	var shoal:=preload("res://scripts/underwater_shoal.gd").new();shoal.name="FishSchool"+str(site.id);shoal.position=Vector3(centre.x,minf(TERRAIN.MARINE_CEILING-1.5,surface_height(centre)+7),centre.y);add_child(shoal)
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
	_update_light(delta)
	if _player==null or not is_instance_valid(_hands):return
	_swim_time+=delta
	var hud:=_player.get_node_or_null("CanvasLayer/SurvivalHUD")
	var swimming:bool=_player.is_swimming and _player.cam_mode==0 and _player.get_node("SurvivalAction").kind.is_empty() and not _player.build_mode and Stats.health>0 and not GameSettings.is_open and not (hud!=null and hud.call("gameplay_input_blocked"))
	var cargo:=_player.get_node_or_null("HuntingCargo")
	var carrying: bool=cargo!=null and is_instance_valid(cargo.held)
	_hands.visible=swimming and not carrying
	if swimming:
		for index in 2:
			var hand:=_hands.get_child(index) as Node3D;var phase:=_swim_time*3.8+index*PI
			hand.visible=index==0 or _player.call("movement_owns_hands")
			hand.position=Vector3((-1 if index==0 else 1)*(.25+.08*cos(phase)),-.28+.07*sin(phase),-.45-.26*maxf(0,sin(phase)))
			hand.rotation=Vector3(.35+sin(phase)*.24,0,(-1 if index==0 else 1)*(.15+.22*cos(phase)))
	var hide_fist: bool=swimming and _player.call("movement_owns_hands")
	if hide_fist!=_hands_visible:_hands_visible=hide_fist;_player.call("_apply_camera_mode");_player._fist_node.visible=not hide_fist and _player.cam_mode==0

func save_state() -> Dictionary:
	var data:=_saved.duplicate(true)
	for child in get_children():
		if child.is_in_group("dive_creature"):data[child.creature_id]=child.save_state()
	return data

func _exit_tree() -> void:
	# Join only the bounded CPU task before releasing its result/loader.
	if _mesh_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_mesh_task)
		_mesh_task = -1
	_mesh_data = null
	if is_instance_valid(_hands):_hands.queue_free()

func _make_reef_passages() -> void:
	var reef := Node3D.new();reef.name="ReefRockPassages";add_child(reef)
	# Buried irregular rock faces and an arch with a genuine open swim passage.
	for index in 12:
		var p := Vector2(140,80)+Vector2(-17.0+sin(index*2.4)*6.0,-30.0+index*5.3)
		if p.distance_squared_to(Vector2(130,82))<81:continue
		_reef_rock(reef,p,Vector3(3.0+index%3,2.5+index%4,2.8),.4,index*.8)
	var centre := Vector2(130,82)
	_reef_rock(reef,centre+Vector2(-4,0),Vector3(2.7,4.0,3.4),2.0,.2)
	_reef_rock(reef,centre+Vector2(4,0),Vector3(2.4,4.2,3.2),2.0,-.3)
	var arch := ART.part(reef,REEF.mesh("Arch"),Vector3(centre.x,surface_height(centre),centre.y),_ruin_material,"NaturalReefArch")
	arch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;arch.visibility_range_end=160
	for section in 12:
		var angle := (section+.5)*PI/12
		var body := StaticBody3D.new();body.position=arch.position+Vector3(cos(angle)*4.5,.5+sin(angle)*4.5,0)
		body.rotation.z=angle+PI/2;reef.add_child(body)
		var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(1.5,1.6,4.2);shape.shape=box;body.add_child(shape)
	# A rocky overhang beside the deep trench; its mouth stays open.
	var cave := Vector2(-345,-475)
	for side in [-1,1]:_reef_rock(reef,cave+Vector2(side*6,0),Vector3(3,5,7),2.2,side*.15)
	_reef_rock(reef,cave,Vector3(9,2,8),7.3,.12)
	for index in 4:
		var beam := MeshInstance3D.new();beam.name="FilteredSunlight%d"%index
		var quad := QuadMesh.new();quad.size=Vector2(5+index,16)
		beam.mesh=quad;beam.position=Vector3(140+(index-1.5)*9,-12,70+index*7)
		var material := ShaderMaterial.new();material.shader=preload("res://shaders/underwater_sunshaft.gdshader")
		material.set_shader_parameter("phase",float(index)*1.4);beam.material_override=material
		beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;beam.visibility_range_end=75
		add_child(beam);_shafts.append(beam)

func _reef_rock(parent: Node3D, point: Vector2, size: Vector3, lift: float, yaw: float) -> void:
	var rock := ART.part(parent,preload("res://scripts/island_landscape.gd")._rock_mesh(),Vector3(point.x,surface_height(point)+lift,point.y),_ruin_material,"ErodedReefRock")
	rock.scale=size;rock.rotation.y=yaw;rock.visibility_range_end=160;rock.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new();body.transform=rock.transform;parent.add_child(body)
	var shape := CollisionShape3D.new();shape.shape=rock.mesh.create_convex_shape(true,false);body.add_child(shape)

func _update_light(delta: float) -> void:
	_lighting_tick+=delta
	if _lighting_tick<.25 or _ground_material==null or _kelp_material==null:return
	_lighting_tick=0
	var ocean := get_tree().get_first_node_in_group("ocean")
	if ocean==null:return
	var daylight := 1.0-float(ocean._last_night)
	for material in [_ground_material,_ruin_material,get_node("OceanSandFloor").material_override]:
		material.set_shader_parameter("daylight",daylight);material.set_shader_parameter("sea_clock",float(ocean._time)*float(ocean.wave_speed))
	_kelp_material.set_shader_parameter("daylight",daylight)
	if stream!=null:stream.call("update_light",daylight)
	for index in _shafts.size():
		_shafts[index].visible=GameSettings.quality!=1 or index<2
		_shafts[index].material_override.set_shader_parameter("daylight",daylight)
	if _accent_material!=null:_accent_material.set_shader_parameter("daylight",daylight)
	for draw in _accents:
		draw.multimesh.visible_instance_count=floori(float(draw.multimesh.instance_count)*.5) if GameSettings.quality in [0,1] else draw.multimesh.instance_count

func save_resources() -> Dictionary:return resource_state.duplicate(true)

func _make_reef_accents() -> void:
	var material := ShaderMaterial.new();material.shader=preload("res://shaders/underwater_organism.gdshader")
	_accent_material=material
	var rng := RandomNumberGenerator.new();rng.seed=901387
	for kind in ["Sponge","BranchCoral","FanCoral","BrainCoral","Urchin","Shell","Pebble"]:
		var batch := MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.use_colors=true
		if kind=="Pebble":
			var pebble := SphereMesh.new();pebble.radius=1;pebble.height=2;pebble.radial_segments=6;pebble.rings=3;batch.mesh=pebble
		else:batch.mesh=REEF.mesh(kind)
		batch.instance_count=90 if kind=="Pebble" else 18
		for index in batch.instance_count:
			var side := -1.0 if index%2==0 else 1.0
			var z := rng.randf_range(73,108)
			var channel := 140+sin((z-80)*.035)*9
			var point := Vector2(channel+side*rng.randf_range(5.0,15.0),z)
			var size := rng.randf_range(.5,1.3)
			var scale_value := Vector3.ONE*size
			if kind=="Pebble":scale_value=Vector3(rng.randf_range(.03,.16),rng.randf_range(.02,.09),rng.randf_range(.03,.15))
			batch.set_instance_transform(index,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(scale_value),Vector3(point.x,surface_height(point)+(.025 if kind=="Pebble" else 0.0),point.y)))
			batch.set_instance_color(index,Color(rng.randf_range(.55,.8),rng.randf_range(.53,.75),rng.randf_range(.45,.7)) if kind=="Pebble" else Color.WHITE)
		var draw := MultiMeshInstance3D.new();draw.name="ReefAccent"+kind;draw.multimesh=batch;draw.material_override=material
		draw.visibility_range_end=65;draw.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(draw);_accents.append(draw)
