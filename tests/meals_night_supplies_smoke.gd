extends SceneTree
const ART:=preload("res://scripts/item_art.gd")
const RULES:=preload("res://scripts/food_rules.gd")
var checks:=0
var failures:=0
var preview:=false
var player: Node3D
var raft: Node3D
var spawner: Node3D
func _initialize() -> void:
	create_timer(110).timeout.connect(func():push_error("FAIL: meals/night/supplies timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count: int=4) -> void:
	for unused in count:await process_frame
func distance_xz(a: Vector3,b: Vector3) -> float:
	var offset:=a-b;offset.y=0;return offset.length()
func clear_stream() -> void:
	for d in spawner._active:if is_instance_valid(d):d.queue_free()
	spawner._active.clear();await frames()
func save_shot(label: String) -> Image:
	await frames(12);await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	check(picture.save_png("C:/GodotProjects/raft-survival/build/"+label+".png")==OK,"Rendered "+label)
	return picture
func food_gallery() -> void:
	var layer:=CanvasLayer.new();layer.layer=120;root.add_child(layer)
	var background:=ColorRect.new();background.color=Color("0d1922");background.size=Vector2(root.size);layer.add_child(background)
	var heading:=Label.new();heading.text="CAMP KITCHEN  /  18 DISTINCT RECIPES";heading.position=Vector2(26,10);heading.add_theme_font_size_override("font_size",22);layer.add_child(heading)
	var index:=0
	for dish in RULES.RECIPES:
		var at:=Vector2(12+(index%6)*210,46+floorf(index/6.0)*222)
		var picture:=TextureRect.new();picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.texture=ART.food_texture(dish);picture.position=at;picture.size=Vector2(196,175);layer.add_child(picture)
		var name:=Label.new();name.text=dish;name.position=at+Vector2(0,175);name.size=Vector2(196,40);name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;name.add_theme_font_size_override("font_size",15);layer.add_child(name)
		index+=1
	await save_shot("recipe-food-gallery");layer.queue_free();await frames()
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args();root.size=Vector2i(1280,720)
	var hashes: Array=[]
	var shared: Texture2D
	for dish in RULES.RECIPES:
		var texture:=ART.food_texture(dish) as AtlasTexture
		check(texture!=null,"Recipe consumes its photographic picture: "+dish)
		if texture==null:continue
		if shared==null:shared=texture.atlas
		check(texture.atlas==shared and abs(texture.get_width()-texture.get_height())<=1,"Shared atlas, undistorted square cutout: "+dish)
		var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(texture.get_image().get_data());hashes.append(hashing.finish().hex_encode())
	check(hashes.size()==18 and hashes.all(func(h):return hashes.count(h)==1),"All eighteen food regions have different pixels")
	check(shared!=null and shared.get_image().detect_alpha()!=Image.ALPHA_NONE,"Food artwork has actual transparent cutouts")
	check(ART.food_texture("Baked Potato")==ART.food_texture("Cooked Potato"),"Legacy potato uses the correct food picture")
	check(ART.food_texture("Tumbler")!=null and ART.food_texture("Diving Tank")!=null,"Water and diving icons remain available")
	root.get_node("Inventory").call("new_game_reset",true);root.get_node("Stats").enabled=false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed
	player=get_first_node_in_group("player");raft=get_first_node_in_group("raft");spawner=current_scene.get_node("DebrisSpawner")
	player.set_process(false);player.set_physics_process(false);raft.set_physics_process(false);await frames(180)
	player.set_process(false);player.set_physics_process(false);spawner.set_process(false)
	player.get_node("RopeSystem").set_physics_process(false);player.get_node("RainSystem").call("stop_rain")
	player.get_node("SurvivalAction").set_process(false);player.get_node("SurvivalProgression").set_process(false)
	check(spawner.max_debris<=48 and spawner.prewarm_count<=24,"Mobile supply retains bounded physics/startup budgets")
	check(spawner._near_count()>=8,"Loading populates existing supplies from casting range to the far lane")
	await clear_stream();spawner._spawn_serial=0
	var supplied: Dictionary={}
	for unused in 48:
		spawner.call("_spawn_upstream");var d: Node3D=spawner._active[-1];supplied[d.item_name]=true
	var essentials:=true
	for kind in ["Wood","Rope","Plastic","Metal","Stone","Soil","Barrel"]:essentials=essentials and supplied.has(kind)
	check(essentials,"Real stream guarantees every essential building/soil material")
	check(spawner._near_count()==0,"Runtime arrivals enter beyond casting range instead of appearing nearby")
	check(spawner._active.size()==spawner.max_debris,"Repeated spawn attempts respect the physical body cap")
	var anchor: Node3D=spawner._active[0];anchor.is_hooked=true;anchor.freeze=true;anchor.global_position=raft.global_position+Vector3(200,0,0)
	var stale: Node3D=spawner._active[1];stale.global_position=raft.global_position+Vector3(100,0,0);spawner.call("_cleanup")
	check(not anchor._is_fading_out,"Recycling preserves hooked/frozen catches")
	check(stale._is_fading_out,"Distant debris fades to release supply capacity")
	stale.call("_physics_process",4.1);spawner.call("_cleanup");await frames()
	var before: int=spawner._active.size();spawner.call("_process",5.0)
	check(spawner._active.size()==before+1,"Freed capacity receives fresh supplies")
	var original_player:=player.global_position;player.global_position+=Vector3(120,0,120)
	check(distance_xz(spawner.call("_origin"),raft.global_position)<.01,"Island exploration keeps supplies anchored to the raft")
	player.global_position=original_player
	var original_raft:=raft.global_position;raft.global_position+=Vector3(160,0,0);await physics_frame;await frames(2);spawner.call("_cleanup")
	var old_stream_fades:=true
	for d in spawner._active:if is_instance_valid(d) and d!=anchor:old_stream_fades=old_stream_fades and d._is_fading_out
	check(old_stream_fades and not anchor._is_fading_out,"Sailing recycles distant corridor and preserves rope catches")
	raft.global_position=original_raft;await physics_frame;await clear_stream();spawner._spawn_serial=0
	await spawner._prewarm()
	var sky:=current_scene.get_node("Sky3D") as WorldEnvironment
	var clock:=sky.get_node("TimeOfDay");var atmosphere:=current_scene.get_node("OceanAtmosphere")
	clock.call("pause");clock.set_process(false);clock.set("current_time",0.0);atmosphere.set_process(false);atmosphere.call("_process",1.0)
	check(sky.environment.ambient_light_energy>=.33 and sky.get_node("FillLight").light_energy>=.11,"Night illuminates shaded salvage")
	check(not sky.environment.fog_enabled and not sky.environment.volumetric_fog_enabled,"Mobile night retains clear air")
	if preview:
		await food_gallery()
		var fire:=load("res://scenes/bonfire.tscn").instantiate() as Node3D
		raft.get_node("BuiltPieces").add_child(fire);fire.position=Vector3(0,.3,4);fire.set_process(false)
		var service:=player.get_node("SurvivalServices");service.call("open_cooking",fire)
		await save_shot("recipe-camp-kitchen");service.call("close_menu");fire.queue_free()
		for child in player.get_children():if child is CanvasLayer:child.visible=false
		player.hide() # This external inspection camera should not show the avatar.
		player.camera.get_node("HandPivot").hide()
		var camera:=Camera3D.new();current_scene.add_child(camera);camera.current=true;camera.fov=75;camera.far=4000
		camera.global_position=raft.global_position+Vector3(0,2.2,1.5);camera.look_at(camera.global_position+Vector3(0,-.12,-1)*100)
		for i in 7:
			var d: Node3D=spawner._active[i];d.freeze=true;d.set_physics_process(false);d._is_fading_in=false;d.call("_set_visual_alpha",1.0)
			var point:=raft.global_position+Vector3((i-3)*1.5,0,-6-abs(i-3)*.35)
			point.y=float(get_first_node_in_group("ocean").get_height(point))+float(d.freeboard);d.global_position=point
		for quality in [1,2]:
			root.get_node("GameSettings").call("update_setting","quality",quality);atmosphere.call("_process",1.0)
			var image:=await save_shot("night-supplies-quality-%d"%quality);var light:=0.0
			var center:=Vector2i(camera.unproject_position(spawner._active[0].global_position))
			for x in range(-8,9):
				for y in range(-8,9):
					var pixel:=center+Vector2i(x,y)
					if Rect2i(Vector2i.ZERO,image.get_size()).has_point(pixel):light=maxf(light,image.get_pixelv(pixel).r)
			check(light>.13,"Weathered wood is visibly illuminated on mobile quality %d"%quality)
	print("MEALS NIGHT SUPPLIES SMOKE: %d checks, %d failures"%[checks,failures])
	current_scene.get_node("OceanAmbience").call("stop_environment");current_scene.queue_free();await frames(25);quit(0 if failures==0 else 1)
