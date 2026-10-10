extends SceneTree
## Compile every first-party game script with the normal warnings promoted by
## verify_source.ps1 -StrictWarnings. Player saves stay in isolated storage.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _scan(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for child in dir.get_directories():
		_scan(folder.path_join(child))
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var path := folder.path_join(file)
		var script := load(path) as GDScript
		checks += 1
		if script == null or not script.can_instantiate():
			failures += 1
			push_error("FAIL: script warnings or parse errors: " + path)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):
		quit(2)
		return
	_scan("res://scripts")
	_scan("res://grass")
	print("SCRIPT WARNINGS SMOKE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
