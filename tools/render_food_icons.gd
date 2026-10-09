extends SceneTree
## Render the actual original cooked dishes into transparent menu/inventory art.
const RULES:=preload("res://scripts/food_rules.gd")
func _initialize() -> void:call_deferred("_render")
func _render() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(256,256);viewport.transparent_bg=true;viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(0,0,0,0)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color(.83,.88,1);environment.environment.ambient_light_energy=.62
	viewport.add_child(environment)
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-48,-35,0);key.light_energy=1.5;viewport.add_child(key)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-30,135,0);fill.light_energy=.45;viewport.add_child(fill)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.33;viewport.add_child(camera)
	camera.position=Vector3(.28,.31,.36);camera.look_at(Vector3(0,.01,0));camera.current=true
	DirAccess.make_dir_recursive_absolute("C:/GodotProjects/raft-survival/textures/ui/food")
	var tools_mode := "--tools" in OS.get_cmdline_user_args()
	var diving_mode := "--diving" in OS.get_cmdline_user_args()
	var stations_mode := "--stations" in OS.get_cmdline_user_args()
	var wind_mode := "--wind-generator" in OS.get_cmdline_user_args()
	var electronics_mode := "--electronics" in OS.get_cmdline_user_args()
	if wind_mode: stations_mode=true
	if stations_mode:DirAccess.make_dir_recursive_absolute("C:/GodotProjects/raft-survival/textures/ui/stations")
	if tools_mode:DirAccess.make_dir_recursive_absolute("C:/GodotProjects/raft-survival/textures/ui/tools")
	if electronics_mode:DirAccess.make_dir_recursive_absolute("C:/GodotProjects/raft-survival/textures/ui/tools")
	var count:=0
	var items: Array=preload("res://scripts/survival_tool_visual.gd").ITEMS if tools_mode else RULES.RECIPES.keys()+["Tumbler","Ocean Water Tumbler","Boiled Water Tumbler"]
	if diving_mode:items=["Diving Tank"]
	if "--camp-recipes" in OS.get_cmdline_user_args():items=["Grilled Fish and Onion","Coconut Fish Stew","Crab Tomato Broth"]
	if stations_mode:items=["Bonfire","Rain Collector","Sand Filter","Cooking Setup"]
	if wind_mode:items=["Wind Generator"]
	if electronics_mode:items=["Solar Torch","Walkie Talkie","Binoculars","Repair Kit"]
	for dish in items:
		var food:=preload("res://scripts/survival_tool_visual.gd").create(dish) if tools_mode else preload("res://scripts/survival_item_visual.gd").create(dish)
		var preview_root: Node3D
		if stations_mode:
			food.free()
			preview_root=Node3D.new();preview_root.name="BuildPreviewRoot";viewport.add_child(preview_root)
			if dish=="Wind Generator":food=preload("res://scripts/machine_visual.gd").create("WindGenerator")
			elif dish=="Sand Filter":food=preload("res://scripts/sand_filter_visual.gd").create()
			else:
				var scene_path: String={"Bonfire":"bonfire","Rain Collector":"rain_collector","Cooking Setup":"cooking_setup"}[dish]
				food=load("res://scenes/"+scene_path+".tscn").instantiate()
			preview_root.add_child(food)
			if dish in ["Bonfire","Cooking Setup"]:food.get("_flames").show()
			if dish=="Rain Collector":food.call("restore_survival_state",{"water":6})
			camera.size=1.85 if dish in ["Sand Filter","Cooking Setup"] else 1.28
			var center:=Vector3(0,.30 if dish=="Bonfire" else .03,0)
			camera.position=center+Vector3(1.8,1.6,2.2);camera.look_at(center)
			if wind_mode:
				camera.size=3.05;camera.position=Vector3(2,2.1,-3);camera.look_at(Vector3(0,1.05,0))
		if diving_mode:
			food.free();food=preload("res://scripts/dive_visual.gd").tank();camera.size=.8
			camera.position=Vector3(.5,.3,.8);camera.look_at(Vector3(0,.03,0))
		if tools_mode:
			camera.size=1.8 if dish=="Paddle" else 1.15
			food.rotation.z=-.45
			camera.position=Vector3(.8,.65,2);viewport.add_child(food);camera.look_at(Vector3(.10,.35,0))
		elif not stations_mode:viewport.add_child(food)
		if electronics_mode:
			food.get_parent().remove_child(food);food.free()
			food=preload("res://scripts/electronics_visual.gd").repair_kit() if dish=="Repair Kit" else preload("res://scripts/electronics_visual.gd").create(dish)
			viewport.add_child(food)
			var bounds:=AABB();var found:=false
			for child in food.find_children("*","MeshInstance3D",true,false):
				if not child.visible:continue
				var mesh:=child as MeshInstance3D;var shape:=mesh.transform*mesh.get_aabb()
				bounds=bounds.merge(shape) if found else shape;found=true
			var centre:=bounds.get_center();camera.size=maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))*1.4
			camera.position=centre+Vector3(.25,.12,.7);camera.look_at(centre)
		for unused in 6:await process_frame
		await RenderingServer.frame_post_draw
		var path:="C:/GodotProjects/raft-survival/textures/ui/"+("stations/" if stations_mode else ("tools/" if tools_mode or electronics_mode else "food/"))+str(dish).to_lower().replace(" ","_")+".png"
		if viewport.get_texture().get_image().save_png(path)!=OK:push_error("Cannot save "+path);quit(1);return
		food.get_parent().remove_child(food);food.free();count+=1
		if preview_root!=null:preview_root.queue_free()
	viewport.queue_free();await process_frame
	print("FOOD ART: %d checks, 0 failures"%count);quit(0)
