extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames(count:int=3) -> void:
	for unused in count:await physics_frame
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	var settings:=root.get_node("GameSettings")
	check(settings.call("mobile_effects_profile"),"Test is exercising the phone effects policy")
	if not settings.call("mobile_effects_profile"):quit(2);return
	root.get_node("Inventory").call("new_game_reset",true)
	change_scene_to_file("res://scenes/main.tscn");await scene_changed;await frames(8)
	var sky:=current_scene.get_node("Sky3D")
	var dome:=sky.get_node("SkyDome")
	var clock:=sky.get_node("TimeOfDay")
	var env:Environment=sky.environment
	var atmosphere:=current_scene.get_node("OceanAtmosphere")
	var rain:=current_scene.get_node("Player/RainSystem")
	check(atmosphere.get_node_or_null("MorningSeaMist")==null,"Mobile creates no rectangular sea smoke/mist emitter")
	check(not env.fog_enabled and not env.volumetric_fog_enabled,"Mobile starts with both environment fog modes disabled")
	check(not bool(dome.get("fog_visible")) and not bool(sky.get("fog_enabled")),"Mobile starts with Sky3D screen fog disabled")
	clock.set_process(false)
	for quality in range(4):
		settings.call("update_setting","quality",quality)
		for hour in [6.0,12.0,21.0]:
			clock.set("current_time",hour);atmosphere.call("_process",0.6)
			check(not env.fog_enabled and not env.volumetric_fog_enabled and env.fog_density==0.0 and not bool(dome.get("fog_visible")),"Phone air stays clear at quality %d, hour %d"%[quality,hour])
		rain.call("start_rain",30.0);rain.call("_update_intensity",5.0)
		check(rain.call("is_raining") and rain._particles.emitting,"Rain still works on phone quality %d"%quality)
		check(not env.fog_enabled and not env.volumetric_fog_enabled and not bool(dome.get("fog_visible")) and float(dome.get("fog_density"))==0.0,"Storms cannot re-enable fog on phone quality %d"%quality)
		rain.call("stop_rain");rain.call("_process",5.0)
		check(not bool(dome.get("fog_visible")) and env.fog_density==0.0,"Ending rain leaves phone fog disabled at quality %d"%quality)
	current_scene.get_node("OceanAmbience").call("stop_environment")
	current_scene.queue_free();await frames(25)
	print("MOBILE CLEAR AIR SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
