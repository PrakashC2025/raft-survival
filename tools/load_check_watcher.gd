extends Node
## Root-level watcher for the menu-load check — survives the scene change
## and reports when the game scene (name == "Main") is live with terrain.

var _frames := 0
var _done := false

func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames > 3600:
		push_error("LOADCHECK FAIL: load never completed (60 s)")
		print("LOADCHECK FAILED")
		_done = true
		get_tree().quit(1)
		return
	var cs := get_tree().current_scene
	if cs != null and cs.name == "Main":
		_done = true
		var island := cs.get_node_or_null("Island")
		var gen_ok := island != null and island.get_node_or_null("Terrain") != null
		print("LOADCHECK: game scene reached after %d frames; island terrain = %s" % [_frames, gen_ok])
		print("LOADCHECK PASSED" if gen_ok else "LOADCHECK FAIL: island missing")
		get_tree().quit(0 if gen_ok else 1)
