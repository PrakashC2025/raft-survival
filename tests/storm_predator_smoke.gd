extends SceneTree
var checks := 0
var failures := 0
var preview := false
var player: CharacterBody3D
var raft: Node3D
var rain: Node3D
var progress: Node
var inventory: Node

class Catch extends RigidBody3D:
	var is_hooked := true
	var item_name := "Wood"
	var freeboard := 0.15

func _initialize() -> void:
	create_timer(180).timeout.connect(func():push_error("FAIL: storm/predator timeout");quit(1))
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:print("PASS: "+label)
	else:failures += 1;push_error("FAIL: "+label)

func frames(count: int = 4) -> void:
	for unused in count:await physics_frame
	await process_frame

func shot(label: String) -> void:
	if not preview:return
	await frames(12);await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/storm-"+label+".png")==OK,"Rendered "+label)

func floor_at(parent: Node3D, at: Vector3) -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new();box.size = Vector3(3,0.2,3);collision.shape = box
	floor_body.add_child(collision);parent.add_child(floor_body);floor_body.position = at
	return floor_body

func rope_probe() -> void:
	var rope := player.get_node("RopeSystem")
	rope.set_physics_process(false)
	player.global_position = raft.to_global(Vector3(0,1.03,0));player.is_swimming = false
	await frames()
	check(rope.can_cast_from_raft(),"Actual raft support enables the launcher")
	player.equip_rope_gun()
	var controls := player.get_node("CanvasLayer/MobileControls")
	controls.force_show = true;controls.call("_update_visibility");controls.call("_sync_mode")
	check(controls._btn_rope.visible,"Mobile CAST is available on the raft")
	controls.call("_on_cast_down");rope.call("_handle_idle",0.01)
	check(rope._is_charging,"A mobile cast starts on the raft")
	player.is_swimming = true;rope.call("_physics_process",0.01);controls.call("_sync_mode")
	check(not rope._is_charging and not controls._btn_rope.visible and not Input.is_action_pressed("rope_throw"),"Entering water cancels charging, hides CAST and releases the held touch action")
	rope.call("_throw_hook")
	check(rope._state==0,"Direct cast release cannot launch while swimming")
	player.is_swimming = false;player.global_position = raft.global_position+Vector3(8,1,0)
	await frames()
	check(not rope.can_cast_from_raft(),"Standing near the raft without support cannot enable the gun")
	var island_floor := floor_at(current_scene,player.global_position+Vector3.DOWN)
	await frames()
	check(not rope.can_cast_from_raft(),"Dry island ground cannot enable a raft-only gun")
	island_floor.queue_free()
	var upper := floor_at(raft.get_node("BuiltPieces"),Vector3(0,3,0))
	player.global_position = raft.to_global(Vector3(0,4.03,0));await frames()
	check(rope.can_cast_from_raft(),"Constructed upper raft floors also permit casting")
	rope.call("_throw_hook")
	var debris := Catch.new();debris.freeze = true;current_scene.add_child(debris)
	debris.global_position = raft.global_position+Vector3(4,0,0)
	rope._hooked_debris.append(debris)
	var before: Array = inventory.slots.duplicate(true)
	player.is_swimming = true;rope.call("_physics_process",0.01)
	check(rope._state==0 and not debris.freeze and not debris.is_hooked and inventory.slots==before,"Falling overboard releases the caught resource without spending or crediting inventory")
	debris.queue_free();upper.queue_free();Input.action_release("rope_throw")
	player.is_swimming = false;player.global_position = raft.to_global(Vector3(0,1.03,0));await frames()

func weather_probe() -> void:
	player.camera.current = true
	player.camera.global_position = raft.to_global(Vector3(0,2.2,0.8));player.camera.look_at(raft.global_position+Vector3(0,3,-24))
	var sky := current_scene.get_node("Sky3D")
	var atmosphere := current_scene.get_node("OceanAtmosphere")
	atmosphere.set_process(false)
	sky.get_node("TimeOfDay").current_time = 12.0
	rain.stop_rain();rain.call("_update_weather",rain.cloud_clear_seconds+1.0);rain.call("_update_intensity",rain.fade_time+1.0);atmosphere.call("_process",0.6)
	var dry_sun: float = sky.sun_energy
	await shot("clear-sky")
	rain.approach_rain(120)
	check(not rain.is_raining() and rain.sky_storm_strength()==0.0,"A weather front starts with clear sky and no premature rain")
	var previous_cloud: float=rain.sky_storm_strength()
	rain.call("_update_weather",1.0/60.0)
	check(rain.sky_storm_strength()-previous_cloud<.001,"Cloud changes are bounded smoothly at a real physics-frame interval")
	rain.call("_update_weather",15.0);atmosphere.call("_process",.6)
	check(not rain.is_raining() and rain.sky_storm_strength()>.2 and rain.sky_storm_strength()<.4,"Cloud banks build for fifteen seconds before drops start")
	await shot("front-approaching")
	var front_state: Dictionary=rain.save_weather_state()
	var maximum_step:=0.0
	for unused in 1800:
		var before_strength: float=rain.sky_storm_strength()
		rain.call("_update_weather",1.0/60.0)
		maximum_step=maxf(maximum_step,rain.sky_storm_strength()-before_strength)
	check(maximum_step<.001,"The entire cloud buildup has no abrupt intensity step at 60 Hz")
	rain.restore_weather_state(front_state)
	check(not rain.is_raining() and is_equal_approx(rain._cloud_cover,float(front_state.cloud_cover)) and rain._pending_duration==120.0,"Continue retains a partly approaching front instead of jumping to another sky")
	rain.call("_update_weather",20.0);atmosphere.call("_process",.6)
	await shot("front-overcast")
	rain.call("_update_weather",10.0);rain.call("_update_intensity",1.0);atmosphere.call("_process",.6)
	check(rain.is_raining() and rain._intensity<.1 and rain.sky_storm_strength()>.99,"The overcast sky precedes a gradual drizzle-to-rain ramp")
	rain.call("_update_intensity",rain.fade_time+1.0);atmosphere.call("_process",.6)
	var material: ShaderMaterial = sky.get_node("SkyDome").sky_material
	check(float(material.get_shader_parameter("storm_amount"))>.99 and sky.sun_energy<dry_sun*.3,"Storm clouds and direct sunlight change together on mobile sky profiles")
	check(rain.particle_amount>=650 and rain.rain_area_size.x<=22,"A dense nearby rain volume replaces the sparse 48-metre box")
	check(rain._rain_process_mat.emission_box_extents.y<=.25 and rain._particles.position.y>=5.0,"Rain enters from above instead of wasting drops born below the sea")
	check(rain.fall_speed<=10.0 and rain._rain_process_mat.gravity==Vector3.ZERO and -rain._rain_process_mat.direction.y*rain._rain_process_mat.initial_velocity_max<=10.0,"Drops remain within realistic terminal speed rather than accelerating without drag")
	check(not sky.environment.fog_enabled and not sky.environment.volumetric_fog_enabled,"Storms retain the phone no-fog policy")
	progress.wetness = 0;progress._tick = 0;progress.call("_process",1.0)
	check(progress.wetness>0,"Exposed rain wets the actual survivor condition")
	progress.wetness = 100
	var wet_visual := rain.get_node("WetSurvivorRain")
	wet_visual.call("_process",0.5)
	check(not wet_visual._surfaces.is_empty() and wet_visual._surfaces[0].roughness<.25,"Wet clothing and skin retain their textures with a visible wet sheen")
	var dry_color: Color = wet_visual._surfaces[0].get_meta("rain_dry_color")
	check(wet_visual._surfaces[0].albedo_color.r<dry_color.r,"Wet survivor surfaces darken instead of only changing an invisible stat")
	rain.call("_process",0.01)
	if preview:await create_timer(rain._particles.lifetime+0.2).timeout
	await shot("rain-first-person")
	if preview:
		sky.current_time = 18.0;atmosphere.call("_process",0.6);rain.call("_update_intensity",0.0);await shot("rain-evening")
		sky.current_time = 0.0;atmosphere.call("_process",0.6);rain.call("_update_intensity",0.0);await shot("rain-night")
		sky.current_time = 12.0;atmosphere.call("_process",0.6);rain.call("_update_intensity",0.0)
	player.cam_mode = 1;player.call("_apply_camera_mode")
	var camera := Camera3D.new();current_scene.add_child(camera)
	camera.global_position = raft.to_global(Vector3(2.8,2.1,-3.5));camera.look_at(player.global_position);camera.current = true
	await shot("wet-survivor")
	camera.queue_free();player.cam_mode = 0;player.call("_apply_camera_mode");player.camera.current = true
	var roof := floor_at(raft.get_node("BuiltPieces"),Vector3(0,3.5,0));roof.add_to_group("build_surface");await frames()
	var wet_before: float = progress.wetness
	progress._tick = 0;progress.call("_process",1.0)
	check(progress.wetness<wet_before,"Real roof cover stops wetting and lets the survivor dry")
	rain._cover_timer = 0;rain.call("_process",0.01)
	check(rain._covered and float(rain._overlay.material.get_shader_parameter("exposure"))==0,"Shelter removes view-edge rain droplets")
	await shot("sheltered-rain")
	player.camera.global_position = Vector3(0,-3,-12);rain.call("_process",0.01)
	check(rain._camera_submerged and not rain._particles.emitting,"Rain drops stop and clear below the actual waterline")
	roof.queue_free();rain.stop_rain();rain.call("_update_weather",1.0);atmosphere.call("_process",.6)
	check(rain.sky_storm_strength()>.95,"Clouds linger after rain stops instead of snapping to a sunny sky")
	player.camera.global_position=raft.to_global(Vector3(0,2.2,.8));player.camera.look_at(raft.global_position+Vector3(0,3,-24))
	rain.call("_update_weather",31.5);rain.call("_update_intensity",rain.fade_time+1.0);atmosphere.call("_process",.6)
	check(rain.sky_storm_strength()>.4 and rain.sky_storm_strength()<.6,"Clearing takes over a minute and passes through a partly cloudy sky")
	await shot("clearing-midway")
	rain.call("_update_weather",rain.cloud_clear_seconds);atmosphere.call("_process",.6)
	check(is_equal_approx(sky.sun_energy,dry_sun) and float(material.get_shader_parameter("storm_amount"))==0,"The clear sky and original sunlight return after rain")
	rain.restore_weather_state({"raining":true,"remaining":30.0})
	check(rain.sky_storm_strength()==1.0 and rain.is_raining(),"Older active-rain saves restore under overcast sky without new mandatory keys")
	rain.stop_rain();rain.call("_update_weather",rain.cloud_clear_seconds+1.0);rain.call("_update_intensity",rain.fade_time+1.0)
	rain.restore_weather_state({"cloud_cover":"invalid","front_remaining":NAN})
	check(rain._cloud_cover==0.0 and rain._front_remaining==0.0,"Malformed weather values cannot poison physics or sky uniforms")
	progress.wetness = 0;wet_visual.call("_process",0.5)
	check(wet_visual._surfaces[0].albedo_color==dry_color,"Drying restores the authored survivor colour")

func predator_probe() -> void:
	var shark := get_nodes_in_group("shark")[0] as CharacterBody3D
	var spawner := shark.get_parent()
	var stats := root.get_node("Stats");stats.reset();progress.level = 1
	player.global_position = raft.global_position+Vector3(14,-0.6,-18);player.is_swimming = true
	shark.global_position = player.global_position+Vector3(6,0,0)
	shark._encounter = 0;shark._encounter_cooldown = 0;shark._swimmer_time = 21;spawner._cooldown = 0
	shark.call("_physics_process",0.1)
	check(shark._encounter>40 and shark._warning_time>3 and not shark.can_attack(player),"A level-one swimmer gets a circling warning before a timed encounter")
	check(not spawner.allow_encounter(get_nodes_in_group("shark")[1]),"A shared rest interval prevents both sharks attacking together")
	shark.global_position = player.global_position+Vector3(1.8,0,0);shark._warning_time = 0
	var before: float = stats.health;shark.call("_physics_process",0.01)
	check(stats.health==before-12 and shark._encounter==0,"After warning the shark reaches the swimmer, bites once, and disengages")
	shark._encounter = 30;shark._warning_time = 0;shark._bite_timer = 0
	player.is_swimming = false;shark.call("_physics_process",0.01)
	check(shark._encounter==0 and not shark.can_attack(player),"Climbing out immediately ends the shark encounter")
	player.is_swimming = true;shark._encounter = 30;shark.take_damage(1,player)
	check(shark._encounter==0 and shark._encounter_cooldown>=60,"A defensive spear hit repels an attacking shark")
	shark._encounter = 30;shark._warning_time = 0
	player.global_position = Vector3(30,-1,-25);shark.global_position = player.global_position+Vector3(2,0,0)
	var wall := StaticBody3D.new();var collider := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size = Vector3(.2,4,4);collider.shape = shape;wall.add_child(collider);current_scene.add_child(wall);wall.global_position = player.global_position+Vector3.RIGHT
	await frames()
	check(not shark.call("_clear_bite",player),"Solid walls and hulls prevent shark bites through cover")
	wall.queue_free();player.is_swimming = false

func boat_probe() -> void:
	var boats := player.get_node("BoatBuilding")
	player.global_position = raft.to_global(Vector3(0,1.03,0))
	var workshop: Node3D = load("res://scenes/boat_workshop.tscn").instantiate()
	raft.get_node("BuiltPieces").add_child(workshop);workshop.position = Vector3(0,.6,-.5)
	inventory.add("Screw",4)
	player.is_swimming = true
	check(not boats.start_build(workshop),"Workshop cannot start construction while the owner is swimming")
	player.is_swimming = false;boats.open(workshop)
	check(boats.start_build(workshop),"Dry workshop assembly starts normally")
	boats.set_process(false);boats.call("_process",1.6);boats.call("_refresh")
	check(boats._assembly.get_node("Hull").visible and boats._assembly.get_node("Interior").visible and not boats._assembly.get_node("Seats").visible,"Actual boat and preview assemble in the correct physical order")
	var ui: CanvasLayer = boats.get("_layer")
	check(ui.status.text.contains("2 / 4") and ui.status.text.contains("floorboards"),"Workshop identifies the current task and remaining assembly time")
	await shot("boat-assembly")
	for size_value in [Vector2i(960,540),Vector2i(1600,720),Vector2i(1280,960)]:
		root.size = size_value;await frames();ui.fit();await frames()
		check(ui.panel.get_global_rect().end.y<=root.get_visible_rect().size.y and ui.close_button.get_global_rect().end.y<=root.get_visible_rect().size.y,"Assembly task and Cancel remain inside viewport "+str(size_value))
	root.size = Vector2i(1280,720)
	var before: Array = inventory.slots.duplicate(true)
	get_tree_pause_test(boats)
	check(not boats.building and inventory.slots==before,"Pausing cancels unfinished assembly without consuming materials")
	boats.close()

func get_tree_pause_test(boats: Node) -> void:
	paused = true
	paused = false
	boats.call("_refresh")

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview = "--preview" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280,720)
	inventory = root.get_node("Inventory");inventory.new_game_reset(true)
	root.get_node("Stats").enabled = false
	change_scene_to_file("res://scenes/main.tscn");await scene_changed;await frames(35)
	player = get_first_node_in_group("player");raft = get_first_node_in_group("raft")
	player.set_physics_process(false);player.set_process(false);raft.set_physics_process(false)
	rain = player.get_node("RainSystem");rain.set_process(false)
	progress = player.get_node("SurvivalProgression");progress.set_process(false)
	player.get_node("SurvivalAction").stop()
	for shark in get_nodes_in_group("shark"):shark.set_physics_process(false)
	await rope_probe();await weather_probe();await predator_probe();await boat_probe()
	current_scene.get_node("OceanAmbience").stop_environment()
	print("STORM PREDATOR SMOKE: %d checks, %d failures"%[checks,failures])
	await create_timer(.1).timeout;current_scene.queue_free();await frames(25)
	quit(0 if failures==0 else 1)
