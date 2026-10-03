extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var inventory := root.get_node("Inventory")
	root.get_node("Stats").set("enabled", false)
	inventory.call("new_game_reset", true)
	inventory.call("save_game", {}, "main")
	var saved_bytes := FileAccess.get_file_as_bytes("user://raft_save.json")
	var old_slots: Array = inventory.get("slots").duplicate(true)
	# Load the fixture after autoloads are registered; extending the menu in the
	# startup script would compile its GameSettings references too early.
	var fixture_script := load(get_script().resource_path.get_base_dir().path_join("menu_loading_fixture.gd"))
	for choice in ["new", "continue", "quick"]:
		var menu = fixture_script.new()
		root.add_child(menu)
		menu.set_process(false)
		menu._buttons = [{"id": choice, "label": choice, "sub": ""},
			{"id": "settings", "label": "SETTINGS", "sub": ""}]
		menu.call("_activate", 0)
		menu.call("_process", 120.0)
		check(menu._waiting_to_enter and menu._busy and menu._error.is_empty(),
			choice + " keeps waiting for a healthy request beyond the old 90-second cutoff")
		check(menu._selected_id == choice and menu._buttons.size() == 3,
			choice + " retains its selection and offers Cancel Loading")
		menu.call("_activate", 0)
		check(menu._buttons.size() == 3, "Repeated " + choice + " presses do not duplicate the request or Cancel button")
		menu.call("_activate", 2)
		check(not menu._busy and not menu._waiting_to_enter and menu._selected_id.is_empty()
			and menu._buttons.size() == 2 and menu._load_requested,
			"Cancel " + choice + " returns to the menu and keeps one background request")
		check(inventory.get("slots") == old_slots and FileAccess.get_file_as_bytes("user://raft_save.json") == saved_bytes,
			"Cancel " + choice + " preserves inventory and the existing save")
		var packed := PackedScene.new()
		var fixture := Node.new()
		packed.pack(fixture)
		fixture.free()
		menu._packed_game = packed
		menu.call("_process", 0.016)
		check(menu.entered.is_empty(), "Late completion after cancelling " + choice + " does not enter gameplay")
		menu.call("_activate", 0)
		check(menu.entered == [choice], "Retry " + choice + " uses the completed scene and the new selection")
		menu.free()
	print("MENU LOADING SMOKE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
