extends Node3D
## Two additive destinations. Setup yields under the shared 2 ms frame budget.
## Static indexed terrain/collision, shared rocks/trees, no smoke/fog/particles.
@export_enum("volcano","winter","spring") var biome := "volcano"
@export var pickup_seed := 48117
const GRID := 52
const RADIUS := 44.0
const BUDGET := preload("res://scripts/frame_work_budget.gd")
const RESOURCE := preload("res://scripts/biome_resource.gd")
const ART := preload("res://scripts/machine_visual.gd")
static var _pine_mesh: ArrayMesh
static var _pine_material: ShaderMaterial
var prepared := false
var _tick := 0.0
var winter_exposure := 0.0
var _status: Label
var _player: Node3D
var _lava_light: OmniLight3D

func _enter_tree() -> void:
	add_to_group("island")
	add_to_group("biome_island")
	set_meta("map_label",{"volcano":"Volcano Isle","winter":"Winter Isle","spring":"Spring Isle"}.get(biome,"Island"))
	set_meta("biome",biome)
	set_meta("arrival_radius",52.0)

func _ready() -> void:
	var beacon := Node3D.new();beacon.name="IslandBeacon";beacon.add_to_group("island_beacon");beacon.position=Vector3(0,14,0);add_child(beacon)
	winter_exposure=clampf(float(Inventory.loaded_meta.get("winter_exposure",0)),0,240) if biome=="winter" else 0.0
	call_deferred("_prepare")

func height_at(point: Vector2) -> float:
	var angle := atan2(point.y,point.x)
	var irregular := 1.0+sin(angle*3.0+.4)*.045+sin(angle*7.0)*.025
	var r := point.length()/(RADIUS*irregular)
	if r>=1.0:return -4.0
	var shore := -4.0+smoothstep(1.0,.69,r)*5.6
	var relief := (sin(point.x*.38+sin(point.y*.23))*sin(point.y*.29))*.34*smoothstep(.98,.55,r)
	if biome=="volcano":
		# Broad walkable outer cone; recessed crater with a continuous solid floor.
		var cone := maxf(0.0,1.0-absf(r-.285)/.48)*16.8
		var crater := smoothstep(.18,.285,r)*4.0
		if r<.285:cone=12.8+crater
		cone+=(sin(angle*5.0+.6)*.75+sin(angle*9.0)*.45)*smoothstep(.65,.28,r)*smoothstep(.16,.25,r)
		return shore+cone+relief
	if biome=="spring":return shore+smoothstep(.85,.25,r)*2.2+relief*.5
	var hill := smoothstep(.80,.18,r)*8.0
	var ridge := exp(-pow((point.x+5.0)/12.0,2)-pow((point.y-2.0)/22.0,2))*9.0
	return shore+hill+ridge+relief

func surface_height(point: Vector2) -> float:
	# Interpolate the same indexed triangles used for collision and rendering.
	var grid:Vector2=(point/88.0+Vector2.ONE*.5)*GRID
	var cell:=Vector2(floorf(grid.x),floorf(grid.y));var f:=grid-cell
	var p:Vector2=(cell/GRID-Vector2.ONE*.5)*88.0;var step:=88.0/GRID
	var h00:=height_at(p);var h10:=height_at(p+Vector2(step,0));var h01:=height_at(p+Vector2(0,step))
	if f.x+f.y<=1:return h00+(h10-h00)*f.x+(h01-h00)*f.y
	var h11:=height_at(p+Vector2.ONE*step)
	return h11+(h01-h11)*(1.0-f.x)+(h10-h11)*(1.0-f.y)

func _prepare() -> void:
	await get_tree().process_frame
	if not is_inside_tree():return
	var vertices := PackedVector3Array();var normals := PackedVector3Array();var uv := PackedVector2Array();var indices := PackedInt32Array()
	for z in range(GRID+1):
		for x in range(GRID+1):
			var p := Vector2((float(x)/GRID*2-1)*RADIUS,(float(z)/GRID*2-1)*RADIUS)
			vertices.append(Vector3(p.x,height_at(p),p.y))
			var dx := height_at(p+Vector2(.3,0))-height_at(p-Vector2(.3,0))
			var dz := height_at(p+Vector2(0,.3))-height_at(p-Vector2(0,.3))
			normals.append(Vector3(-dx,.6,-dz).normalized());uv.append(p*.1)
			if x<GRID and z<GRID:
				var a := z*(GRID+1)+x
				indices.append_array(PackedInt32Array([a,a+1,a+GRID+1,a+1,a+GRID+2,a+GRID+1]))
			if BUDGET.exhausted():
				await get_tree().process_frame
				if not is_inside_tree():return
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new();material.shader=preload("res://shaders/biome_terrain.gdshader")
	material.set_shader_parameter("winter",biome=="winter")
	material.set_shader_parameter("spring",biome=="spring")
	material.set_shader_parameter("rock_albedo",preload("res://textures/island/rock_diff.jpg"))
	material.set_shader_parameter("rock_normal",preload("res://textures/island/rock_nor_gl.jpg"))
	material.set_shader_parameter("rock_arm",preload("res://textures/island/rock_arm.jpg"))
	ART.part(self,mesh,Vector3.ZERO,material,"BiomeTerrain")
	await get_tree().process_frame
	if not is_inside_tree():return
	var ground := StaticBody3D.new();ground.name="BiomeGround";ground.add_to_group("island_ground");add_child(ground)
	var collision := CollisionShape3D.new();collision.name="CollisionShape3D";collision.shape=mesh.create_trimesh_shape();ground.add_child(collision)
	# Height mask uses the same surface, without hundreds of terrain raycasts.
	var image := Image.create(32,32,false,Image.FORMAT_RF)
	for z in 32:
		for x in 32:image.set_pixel(x,z,Color(height_at(Vector2((float(x)+.5)/32*88-44,(float(z)+.5)/32*88-44)),0,0))
	var ocean := get_tree().get_first_node_in_group("ocean")
	if ocean!=null:ocean.call("register_island_shore",self,ImageTexture.create_from_image(image),RADIUS)
	if biome=="volcano":_lava()
	await _resources()
	if not is_inside_tree():return
	if biome=="spring":
		var setup:=Node3D.new();setup.name="IslandSetup";add_child(setup)
		var wild:=preload("res://scripts/island_wild_plants.gd").new();wild.name="WildPlants";setup.add_child(wild)
		await wild.prepare()
		if not is_inside_tree():return
		var grove:=preload("res://scripts/island_grove.gd").new();grove.name="CoastalGrove";add_child(grove)
	if biome=="winter":_ice_outcrops()
	prepared=true
	_player=get_tree().get_first_node_in_group("player") as Node3D
	if _player!=null:
		_status=Label.new();_status.name="BiomeStatus"+str(name);_status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP);_status.offset_left=-260;_status.offset_right=260;_status.offset_top=118;_status.offset_bottom=150
		_status.add_theme_font_size_override("font_size",18);_status.add_theme_color_override("font_shadow_color",Color.BLACK);_status.add_theme_constant_override("shadow_outline_size",3)
		_status.mouse_filter=Control.MOUSE_FILTER_IGNORE;_player.get_node("CanvasLayer").add_child(_status);_status.hide()

func _lava() -> void:
	var material := ShaderMaterial.new();material.shader=preload("res://shaders/volcanic_lava.gdshader")
	var pool := CylinderMesh.new();pool.top_radius=7.5;pool.bottom_radius=7.5;pool.height=.12;pool.radial_segments=48
	ART.part(self,pool,Vector3(0,14.90,0),material,"CraterLava")
	_lava_light=OmniLight3D.new();_lava_light.name="LavaGlow";_lava_light.position=Vector3(0,16,0)
	_lava_light.light_color=Color(1,.19,.025);_lava_light.light_energy=1.2;_lava_light.omni_range=14;_lava_light.shadow_enabled=false;_lava_light.hide();add_child(_lava_light)
	# A narrow channel follows the cone instead of floating above a flat plane.
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 64:
		var a := lava_path(float(index)/64);var b := lava_path(float(index+1)/64)
		var side := (b-a).normalized().orthogonal()*.42
		for point in [a-side,a+side,b-side,a+side,b+side,b-side]:
			surface.add_vertex(Vector3(point.x,surface_height(point)+.075,point.y))
	surface.generate_normals();ART.part(self,surface.commit(),Vector3.ZERO,material,"LavaChannel")

func lava_path(t: float) -> Vector2:
	var angle := 2.4+sin(t*5.0)*.12
	return Vector2(cos(angle),sin(angle))*lerpf(11.5,30.0,t)

func is_lava(point: Vector3) -> bool:
	if biome!="volcano":return false
	var p := Vector2(point.x,point.z)
	if p.length()<7.5:return point.y<17.0
	var t := clampf((p.length()-11.5)/18.5,0,1)
	return p.distance_to(lava_path(t))<.65 and point.y<height_at(p)+2.4

func _resources() -> void:
	var rock := preload("res://scripts/island_landscape.gd")._rock_mesh()
	var mat:Material=get_node("BiomeTerrain").material_override if biome=="volcano" else preload("res://scripts/island_mountain.gd").rock_material()
	var rng := RandomNumberGenerator.new();rng.seed=81223 if biome=="winter" else 91323
	for index in range(20 if biome=="winter" else 12):
		var tree := biome=="winter" and index>=6
		var angle := float(index)*2.39996;var radius := rng.randf_range(20,33)
		var point := Vector2(cos(angle),sin(angle))*radius
		if biome=="volcano" and point.distance_to(lava_path(clampf((radius-11.5)/18.5,0,1)))<1.5:point=point.rotated(.35)
		var node := RESOURCE.new();node.name=("Spruce" if tree else "Mineral")+str(index);node.resource_id=str(name)+":"+str(index)
		node.required_tool="Axe" if tree else "Pickaxe";node.rewards={"Wood":6} if tree else {"Stone":4,"Metal":2 if biome=="volcano" else 1}
		node.position=Vector3(point.x,surface_height(point),point.y)
		var visual := Node3D.new();visual.name="ResourceVisual";node.add_child(visual);node.visual=visual
		var shape := CollisionShape3D.new()
		if tree:
			var trunk := ART.cylinder(visual,Vector3(0,2.1,0),.13,4.2,preload("res://scripts/survival_tool_visual.gd").material("wood"));trunk.name="SpruceTrunk";trunk.visibility_range_end=240
			var needles:=ART.part(visual,_pine(),Vector3.ZERO,_pine_material,"SnowyNeedles")
			needles.visibility_range_end=160;needles.visibility_range_end_margin=15;needles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var capsule := CylinderShape3D.new();capsule.radius=.22;capsule.height=4.5;shape.shape=capsule;shape.position.y=2.25
		else:
			var stone := ART.part(visual,rock,Vector3(0,.5,0),mat,"OreRock");stone.scale=Vector3(1.0,.85,.95)*rng.randf_range(.8,1.3);stone.visibility_range_end=220
			for seam in 4:
				var metal := ART.box(visual,Vector3(sin(seam*2.1)*.42,.76+seam*.035,cos(seam*2.1)*.39),Vector3(.34,.035,.07),preload("res://scripts/survival_tool_visual.gd").material("metal"));metal.rotation.y=seam*2.1;metal.visibility_range_end=220
			var sphere := SphereShape3D.new();sphere.radius=.85;shape.shape=sphere;shape.position.y=.52
		node.add_child(shape);add_child(node)
		await get_tree().process_frame
		if not is_inside_tree():return

static func _pine() -> ArrayMesh:
	if _pine_mesh!=null:return _pine_mesh
	_pine_material=ShaderMaterial.new();_pine_material.shader=preload("res://shaders/winter_needles.gdshader")
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Many narrow drooping branch sprays, irregular tips and layered silhouette.
	for layer in 9:
		var y := 1.1+layer*.48;var reach := 1.55*(1.0-float(layer)/10)
		for branch in 9:
			var angle := branch*TAU/9+layer*.53
			var start := Vector3(0,y+.26,0);var direction := Vector3(cos(angle),0,sin(angle));var side := direction.cross(Vector3.UP)
			var tip := direction*reach+Vector3(0,y-.25,0)
			for spray in 3:
				var mid := start.lerp(tip,float(spray+1)/4);var width := reach*.20*(1.0-float(spray)*.20)
				for vertex in [start,mid+side*width,tip,start,tip,mid-side*width,mid+side*width,mid+Vector3.UP*.24,tip,mid-side*width,tip,mid+Vector3.UP*.24]:surface.add_vertex(vertex)
	surface.generate_normals();_pine_mesh=surface.commit();return _pine_mesh

func _ice_outcrops() -> void:
	# Grounded, faceted blue ice amongst the snowy rocks; shared opaque material.
	var ice:=StandardMaterial3D.new();ice.albedo_color=Color(.22,.46,.61);ice.roughness=.24;ice.metallic=.05
	for index in 8:
		var p:=Vector2(cos(index*2.4),sin(index*2.4))*lerpf(13,24,float(index)/8)
		var rock:=ART.part(self,preload("res://scripts/island_landscape.gd")._rock_mesh(),Vector3(p.x,surface_height(p),p.y),ice,"GlacialIce%d"%index)
		rock.scale=Vector3(1.4,2.6,1.2);rock.rotation.y=index*.8;rock.visibility_range_end=160

func _process(delta: float) -> void:
	_tick+=delta
	if _tick<.5 or not prepared or _player==null:return
	var step := minf(_tick,1.0);_tick=0
	if biome=="winter":
		for resource in get_children():
			if resource.has_method("advance_tree"):resource.call("advance_tree",step)
	var local := to_local(_player.global_position)
	var near := Vector2(local.x,local.z).length()<RADIUS and local.y>0 and local.y<35
	if is_instance_valid(_lava_light):_lava_light.visible=local.length_squared()<80.0*80.0
	var hud := _player.get_node_or_null("CanvasLayer/SurvivalHUD")
	var blocked:bool = GameSettings.is_open or Stats.health<=0 or (hud!=null and hud.call("gameplay_input_blocked"))
	if _status!=null:_status.visible=near and not blocked
	if not near or blocked:
		if biome=="winter" and not blocked:winter_exposure=maxf(0,winter_exposure-step*3)
		return
	if biome=="volcano":
		var danger := is_lava(local)
		if _status!=null:_status.text="LAVA - STEP BACK" if danger else "VOLCANO ISLE - WATCH FOR LAVA";_status.modulate=Color(1,.64,.34)
		if danger and Stats.enabled:Stats.change_health(-10.0*step)
	elif biome=="winter":
		var warm:bool = _player.get_node("SurvivalProgression").call("is_held_lit")
		for fire in get_tree().get_nodes_in_group("campfire"):
			if fire.get("burning")==true and _player.global_position.distance_squared_to(fire.global_position)<36:warm=true;break
		winter_exposure=clampf(winter_exposure+(-4.0 if warm else 1.0)*step,0,240)
		if _status!=null:_status.text="WARMING UP" if warm else ("COLD - WARM UP AT A FIRE" if winter_exposure>=60 else "WINTER ISLE - KEEP A TORCH OR FIRE READY");_status.modulate=Color(.68,.85,1)
		if winter_exposure>=180 and Stats.enabled:Stats.change_health(-.3*step)
	elif _status!=null:
		_status.text="SPRING ISLE · CLEAR A PATCH AND PLANT YOUR CROPS";_status.modulate=Color(.75,.95,.57)

func _exit_tree() -> void:
	if is_instance_valid(_status):_status.queue_free()
