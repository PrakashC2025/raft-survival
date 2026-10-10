extends SceneTree
## Cancel and destroy the actual menu while its background job is owned.
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	var inventory := root.get_node("Inventory")
	inventory.new_game_reset(true)
	var before: Array = inventory.slots.duplicate(true)
	var menu := load("res://scripts/main_menu.gd").new() as Control
	root.add_child(menu)
	current_scene = menu
	var worker := menu.get("_load_worker") as Thread
	check(worker != null and worker.is_started(), "The actual menu owns its background job")
	menu.call("_activate", 0)
	check(menu.get("_busy") and menu.get("_waiting_to_enter"), "New Game waits for prepared resources")
	menu.call("_cancel_loading")
	check(not menu.get("_busy") and not menu.get("_waiting_to_enter"), "Cancel releases the choice immediately")
	check(menu.get("_load_worker") == worker and worker.is_started(), "Cancel retains the single background job")
	check(inventory.slots == before, "Cancel does not change inventory")
	menu.queue_free()
	await process_frame
	check(not is_instance_valid(menu), "Closing the loading menu releases the node")
	check(not worker.is_started(), "Menu teardown joins the worker before its script is freed")
	print("MENU WORKER SMOKE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
