extends SceneTree
var checks := 0
var failures := 0
const SAVE := preload("res://scripts/save_storage.gd")
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if value:print("PASS: "+message)
	else:failures+=1;push_error("FAIL: "+message)
func run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"):quit(2);return
	var inv:=root.get_node("Inventory")
	var state:=load("res://scripts/ocean_salvage.gd").new() as Node
	var sealed:={"next_arrival":21.5,"serial":2,"recovered":1,"catalog":[0],"last_note":0,"cache":{"kind":1,"p":[100.0,.1,-60.0],"yaw":.5}}
	inv.loaded_meta={"ocean_salvage":sealed.duplicate(true)}
	var snapshot: Dictionary=state.save_state()
	check(snapshot==sealed,"Quitting before the expedition restores keeps all loaded cargo metadata")
	snapshot.cache.p[0]=150
	check(inv.loaded_meta.ocean_salvage.cache.p[0]==100,"The restoration save snapshot is independent of loaded data")
	inv.loaded_meta={}
	check(state.save_state().is_empty(),"An older save needs no placeholder expedition data")
	inv.loaded_meta={"ocean_salvage":"invalid"}
	check(state.save_state().is_empty(),"An invalid loaded object cannot become saved cargo")
	check(SAVE._valid_salvage(sealed),"The complete optional expedition envelope is valid")
	for field in ["next_arrival","serial","recovered","last_note"]:
		var invalid_number: Dictionary=sealed.duplicate(true);invalid_number[field]=NAN
		check(not SAVE._valid_salvage(invalid_number),"Non-finite "+field+" is rejected")
	var bad: Dictionary=sealed.duplicate(true);bad.cache.kind=4
	check(not SAVE._valid_salvage(bad),"Unknown cargo types cannot enter a save")
	bad=sealed.duplicate(true);bad.catalog=[0,1,2,3,0]
	check(not SAVE._valid_salvage(bad),"Catalog size remains bounded")
	bad=sealed.duplicate(true);bad.cache.p[0]=200001
	check(not SAVE._valid_salvage(bad),"Out-of-world cargo coordinates are rejected")
	inv.loaded_meta.clear();state.free()
	print("OCEAN SALVAGE STATE SMOKE: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
