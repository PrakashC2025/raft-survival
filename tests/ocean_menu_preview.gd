extends SceneTree
var checks:=0
var failures:=0
var preview:=false
func _initialize() -> void:
	create_timer(60).timeout.connect(func():push_error("FAIL: ocean menu timeout");quit(1))
	call_deferred("_run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok:print("PASS: "+label)
	else:failures+=1;push_error("FAIL: "+label)
func frames() -> void:
	for unused in 5:await process_frame
func shot(label: String) -> void:
	if not preview:return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/ocean-"+label+".png")==OK,"Rendered "+label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	preview="--preview" in OS.get_cmdline_user_args()
	var inv:=root.get_node("Inventory")
	inv.call("new_game_reset",true);inv.call("save_game",{},"main");inv.call("save_game",{},"quick")
	root.get_node("Stats").enabled=false
	var fixture:=load(get_script().resource_path.get_base_dir().path_join("menu_loading_fixture.gd"))
	var menu=fixture.new();root.add_child(menu);current_scene=menu
	var settings:=root.get_node("GameSettings")
	for dimensions in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844),Vector2i(360,640)]:
		root.size=dimensions;await frames();menu.call("_layout_buttons")
		var viewport:=root.get_visible_rect()
		var previous:=Rect2()
		for rect: Rect2 in menu._btn_rects:
			var scale_factor: float=menu.call("_ui_scale")
			check(viewport.encloses(Rect2(rect.position*scale_factor,rect.size*scale_factor)) and rect.size.y>=48,"Lobby button fits "+str(dimensions))
			check(not previous.intersects(rect),"Lobby buttons stay separated "+str(dimensions));previous=rect
		await shot("lobby-%dx%d"%[dimensions.x,dimensions.y])
		settings.call("open");await frames()
		var panel:=settings.get("_panel") as Control
		var tabs:=panel.find_child("SettingsTabs",true,false) as TabContainer
		check(viewport.encloses(panel.get_global_rect()),"Settings panel fits "+str(dimensions))
		for index in 4:
			tabs.current_tab=index;await frames()
			var done:=panel.find_child("SettingsDone",true,false) as Button
			check(viewport.encloses(done.get_global_rect()) and done.size.y>=48,"Done stays accessible in tab %d at %s"%[index,dimensions])
			check(tabs.size.y>=64,"Settings content scrolls within the panel")
			if index==0 or (index==1 and dimensions!=Vector2i(360,640)):await shot("settings-%d-%dx%d"%[index,dimensions.x,dimensions.y])
		settings.call("close");await frames()
		check(not paused,"Closing settings resumes the lobby")
	print("OCEAN MENU: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
