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
	var source: Script = load("res://scripts/inventory.gd")
	var inventory: Node = source.new()
	root.add_child(inventory)
	inventory.call("place_at", 0, "Rope", 1)
	inventory.call("grant_testing_resources")
	for material in ["Wood", "Rope", "Plastic", "Barrel", "Stone", "Metal"]:
		check(inventory.call("total", material) == 2000, material + " starts at 2000")
	check(inventory.call("craft", "Foundation"), "Foundation is affordable with testing materials")
	check(inventory.call("total", "Wood") == 1995, "Building still spends five wood")
	check(inventory.call("craft_item", "Motor Kit"), "Equipment crafting works with testing materials")
	var remaining_wood: int = inventory.call("total", "Wood")
	inventory.call("save_game", {}, "quick")
	inventory.call("new_game_reset", false)
	inventory.call("load_game", "quick")
	inventory.call("grant_testing_resources")
	check(inventory.call("total", "Wood") == remaining_wood, "Continue keeps spent materials without refilling")
	inventory.call("new_game_reset", false)
	inventory.call("grant_testing_resources")
	check(inventory.call("total", "Wood") == 2000, "New Game grants a fresh test supply")
	print("TESTING RESOURCES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
