extends Node
## Menu-load check: boots the REAL main menu, presses the first button
## (Continue if a save exists, else New Game), waits for the threaded
## loading screen to finish, and verifies the game scene came up with the
## island built. The WATCHER is parented to the tree root so it survives
## the scene change (the load itself replaces the current scene).
##   godot --headless --path . res://tools/load_check_scene.tscn

var _frames := 0
var _started := false
var _done := false

func _ready() -> void:
	# The scene-change replaces this node's tree position, so move the
	# watcher under root and let a fresh menu instance be the current scene.
	var watcher := Node.new()
	watcher.name = "LoadCheckWatcher"
	watcher.set_script(null)
	get_tree().root.add_child.call_deferred(watcher)
	# Run the drive logic from the watcher (needs to persist).
	watcher.set_meta("frames", 0)
	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	if menu_scene == null:
		push_error("LOADCHECK FAIL: main_menu.tscn missing")
		get_tree().quit(1)
		return
	var menu: Control = menu_scene.instantiate()
	add_child(menu)
	print("LOADCHECK: menu up, buttons=", menu._buttons.size())
	if menu._buttons.is_empty():
		push_error("LOADCHECK FAIL: menu rendered no buttons")
		get_tree().quit(1)
		return
	print("LOADCHECK: activated '%s' — waiting for threaded load" % menu._buttons[0]["id"])
	menu._activate(0, Vector2.ZERO)
	_started = true
	# Watch from a node OUTSIDE the current scene.
	var drive := preload("res://tools/load_check_watcher.gd").new()
	get_tree().root.add_child.call_deferred(drive)

func _exit_tree() -> void:
	pass # scene replaced — the root-level watcher takes over reporting
