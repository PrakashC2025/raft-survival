extends SceneTree
## Render the real weather/sea components without loading unrelated game assets.
var checks := 0
var failures := 0
var rain: Node3D
var atmosphere: Node3D
var sky: WorldEnvironment
var camera: Camera3D

class Observer extends CharacterBody3D:
	var is_swimming := false
	var boat_vehicle: Node3D
	var ocean: Node3D

func _initialize() -> void:
	create_timer(120).timeout.connect(func():push_error("FAIL: weather render timeout");quit(1))
	call_deferred("_run")

func check(ok: bool, caption: String) -> void:
	checks += 1
	if ok:print("PASS: "+caption)
	else:failures += 1;push_error("FAIL: "+caption)

func frames(count: int = 12) -> void:
	for unused in count:await process_frame
	await RenderingServer.frame_post_draw

func shot(caption: String) -> Image:
	await frames()
	var result := root.get_texture().get_image()
	check(result.save_png("C:/GodotProjects/raft-survival/build/weather-"+caption+".png")==OK,"Rendered "+caption)
	return result

func advance_weather(seconds: float) -> void:
	rain.call("_update_weather",seconds)
	rain.call("_update_intensity",seconds)
	atmosphere.call("_process",.6)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests") or DisplayServer.get_name()=="headless":quit(2);return
	root.size = Vector2i(1280,720)
	root.get_node("Stats").enabled = false
	var world := Node3D.new();root.add_child(world);current_scene = world
	sky = load("res://addons/sky_3d/src/Sky3D.gd").new();sky.name="Sky3D";world.add_child(sky)
	sky.sun_energy=1.5;sky.current_time=12.0
	var fill := DirectionalLight3D.new();fill.name="FillLight";fill.rotation_degrees=Vector3(-50,0,0);fill.light_energy=.32;world.add_child(fill)
	var ocean: MeshInstance3D = load("res://scripts/ocean.gd").new();ocean.name="Ocean"
	var water := ShaderMaterial.new();water.shader=load("res://shaders/main.gdshader")
	var plane := PlaneMesh.new();plane.size=Vector2(800,800);plane.material=water;ocean.mesh=plane;world.add_child(ocean)
	var observer := Observer.new();observer.name="WeatherObserver";observer.ocean=ocean
	var pivot := Node3D.new();pivot.name="CamPivot";pivot.position.y=2.2;observer.add_child(pivot)
	var arm := SpringArm3D.new();arm.name="SpringArm3D";arm.spring_length=0;pivot.add_child(arm)
	camera=Camera3D.new();camera.name="Camera3D";camera.far=4000;camera.fov=70;arm.add_child(camera)
	world.add_child(observer);observer.add_to_group("player");camera.current=true
	rain=load("res://scripts/rain_system.gd").new();rain.name="RainSystem";rain.enable_lightning=false;observer.add_child(rain)
	atmosphere=load("res://scripts/ocean_atmosphere.gd").new();atmosphere.name="OceanAtmosphere";world.add_child(atmosphere)
	await frames(30);rain.set_process(false);atmosphere.set_process(false)
	var clock := sky.get_node("TimeOfDay");clock.get_node("Timer").stop()
	var material: ShaderMaterial=sky.get_node("SkyDome").sky_material
	material.set_shader_parameter("cumulus_visible",false);material.set_shader_parameter("fast_radiance_enabled",true)
	check(camera.global_position.y>float(ocean.call("get_height",camera.global_position))+1.0,"Weather camera stays above the moving waterline")
	advance_weather(0);await shot("clear")
	rain.approach_rain(120);advance_weather(15);await shot("approaching")
	advance_weather(20);await shot("overcast-before-rain")
	advance_weather(10);advance_weather(rain.fade_time+1)
	rain._particles.emitting=false;rain._particles.restart()
	await create_timer(rain._particles.lifetime+.2).timeout
	var dry: Image=await shot("storm-clouds")
	rain._particles.emitting=true
	await create_timer(rain._particles.lifetime+.3).timeout
	var wet: Image=await shot("steady-rain")
	var visible_drop_pixels:=0
	for y in range(50,300):
		for x in range(80,1200):
			var before:=dry.get_pixel(x,y);var after:=wet.get_pixel(x,y)
			if after.r+after.g+after.b-before.r-before.g-before.b>.08:visible_drop_pixels+=1
	check(visible_drop_pixels>200,"Real steady rain produces visible streaks across the sky (%d pixels)"%visible_drop_pixels)
	check(not sky.environment.fog_enabled and not sky.environment.volumetric_fog_enabled,"The rendered storm retains clear mobile air")
	sky.current_time=0;await frames();rain.call("_update_intensity",0);atmosphere.call("_process",.6)
	check(float(rain._rain_mat.get_shader_parameter("rain_light"))<.2,"Night rain responds to available daylight")
	await shot("night-rain")
	sky.current_time=12;await frames();rain.call("_update_intensity",0);rain.stop_rain();advance_weather(32.5);await shot("clearing")
	advance_weather(65);await shot("clear-again")
	check(rain.sky_storm_strength()==0 and rain._intensity==0,"The rendered front clears completely without a reset")
	rain._audio.stop();print("WEATHER RENDER SMOKE: %d checks, %d failures"%[checks,failures])
	await create_timer(.1).timeout;world.queue_free()
	for unused in 20:await process_frame
	quit(0 if failures==0 else 1)
