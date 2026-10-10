extends Control
## ============================================================
## MAIN MENU — survival-styled ocean start screen.
## Animated open water behind a clear title and large ocean-coloured buttons.
##   - No saves            -> NEW GAME only
##   - Autosave present    -> CONTINUE (resumes it)
##   - Quick-save present  -> QUICK SAVE (second resume option)
## Each resume button shows the saved in-game day/time.
##
## MOBILE / TOUCH NOTES (this is the part that used to break on the APK):
##   * Buttons fire on PRESS-DOWN, not on release. A phone sends
##     touch -> drag -> drag -> release and the release position is rarely
##     exactly the press position, so press/release matching silently dropped
##     taps. Press-down activation is also what the in-game HUD uses.
##   * Touch is tracked per finger (`index`) so a second thumb resting on the
##     screen can no longer cancel the first one.
##   * Screen touches arrive in VIEWPORT coordinates while the button rects are
##     in this Control's LOCAL space — positions are converted explicitly, so
##     the menu keeps working if it is ever offset, scaled or resized.
##   * Hit rects are rebuilt on demand (resize / before every hit test) instead
##     of only inside _draw(), so the very first tap can never land on an
##     empty rect list.
##   * `main.tscn` is heavy (multi-megabyte island GLBs + sky shaders). It is
##     pre-loaded on a background thread from _ready(), keeping the menu
##     responsive while its files load. Scene setup can take additional time.
##     While it loads the tapped button reads "LOADING…" with a progress bar.
##   * If the game scene cannot be opened the menu shows the reason on screen
##     and unlocks again — a dead, silent menu is what made this look broken.
## ============================================================

const GAME_SCENE := "res://scenes/main.tscn"
const UI_SURFACE := preload("res://scripts/ui_surface.gd")
const SEA_BACKDROP: Shader = preload("res://shaders/menu_sea.gdshader")
var _redraw_seconds := 0.0
var _intro: Control
var _story_pending := false
## A healthy resource request can spend a long time importing/uploading one
## dependency. Elapsed time is information, never proof that loading failed.
const LONG_LOAD_NOTICE_AFTER := 30.0

# button ids in display order
var _buttons: Array = []          # of {id, label, sub}
var _btn_rects: Array = []        # parallel Rect2
var _hover := -1
var _press := -1
var _busy := false
var _t := 0.0
var _vp := Vector2.ZERO
var _title_w := 0.0

# --- touch bookkeeping -------------------------------------------------
var _touch_ids: Array = []        # fingers currently on the screen
# --- background load of the game scene ---------------------------------
## Prepare dependencies first, then request exactly one script at a time.
## Concurrent script/scene requests can deadlock the GDScript preload cache.
const SCRIPT_WARM_PATHS := [
	"res://textures/ui/tools/axe.png",
	"res://textures/ui/tools/pickaxe.png",
	"res://textures/ui/tools/shovel.png",
	"res://textures/ui/tools/paddle.png",
	"res://textures/ui/tools/anchor.png",
	"res://scripts/survival_tools.gd",
	"res://scripts/survival_tool_visual.gd",
	"res://scripts/biome_island.gd",
	"res://scripts/biome_resource.gd",
	"res://shaders/biome_terrain.gdshader",
	"res://shaders/volcanic_lava.gdshader",
	"res://shaders/winter_needles.gdshader",
	"res://scripts/build_socket.gd",
	"res://scripts/object_materials.gd",
	"res://scripts/construction_visual.gd",
	"res://scripts/resource_visual.gd",
	"res://scripts/food_rules.gd",
	"res://scripts/survival_item_visual.gd",
	"res://scripts/produce_visual.gd",
	"res://scripts/food_pickup.gd",
	"res://scripts/vegetation_visual.gd",
	"res://scripts/plant_instance.gd",
	"res://scripts/soil_visual.gd",
	"res://scripts/planter.gd",
	"res://scripts/rope_launcher_visual.gd",
	"res://scripts/sand_footprints.gd",
	"res://scripts/survival_equipment.gd",
	"res://scripts/frame_work_budget.gd",
	"res://scripts/station_job.gd",
	"res://scripts/cargo_crate.gd",
	"res://scripts/storage_box.gd",
	"res://scripts/item_art.gd",
	"res://scripts/ui_icons.gd",
	"res://scripts/storage_slot_ui.gd",
	"res://scripts/survival_service_ui.gd",
	"res://scripts/survival_services.gd",
	"res://scripts/torch_cycle.gd",
	"res://scripts/torch_visual.gd",
	"res://scripts/rope_hand_grip.gd",
	"res://scripts/survival_audio.gd",
	"res://scripts/contact_audio.gd",
	"res://scripts/dive_visual.gd",
	"res://scripts/survival_progression.gd",
	"res://scripts/portable_electronics.gd",
	"res://scripts/survival_animal.gd",
	"res://scripts/island_wildlife.gd",
	"res://scripts/machine_visual.gd",
	"res://scripts/held_arm_pose.gd",
	"res://scripts/survival_action.gd",
	"res://scripts/ground_plot.gd",
	"res://scripts/island_layout.gd",
	"res://scripts/electronics_visual.gd",
	"res://scripts/fishing_rod_visual.gd",
	"res://scripts/smart_roof.gd",
	"res://scripts/construction_audio.gd",
	"res://scripts/player.gd",
	"res://scripts/debris.gd",
	"res://scripts/starter_raft_visual.gd",
	"res://scripts/raft.gd",
	"res://scripts/raft_foam.gd",
	"res://scripts/shark.gd",
	"res://scripts/ocean.gd",
	"res://scripts/debris_spawner.gd",
	"res://scripts/rain_system.gd",
	"res://scripts/crosshair.gd",
	"res://scripts/rope_system.gd",
	"res://scripts/ui_surface.gd",
	"res://scripts/mobile_controls.gd",
	"res://scripts/survival_hud.gd",
	"res://scripts/island_setup.gd",
	"res://scripts/island_grass.gd",
	"res://scripts/island_beacon.gd",
	"res://scripts/island_marker.gd",
	"res://scripts/mobile_performance.gd",
	"res://scripts/ocean_ambience.gd",
	"res://scripts/shark_spawner.gd",
	"res://scripts/wild_plant_target.gd",
	"res://scripts/island_wild_plants.gd",
	"res://scripts/island_mountain.gd",
	"res://scripts/island_landscape.gd",
	"res://scripts/coastal_tree_visual.gd",
	"res://scripts/island_grove.gd",
	"res://scripts/island_destination.gd",
	"res://scripts/island_birds.gd",
	"res://scripts/fish_school.gd",
	"res://shaders/shark_skin.gdshader",
	"res://shaders/undersea_surface.gdshader",
	"res://shaders/sea_plants.gdshader",
	"res://scripts/seabed.gd",
	"res://scripts/sea_fauna_visual.gd",
	"res://scripts/underwater_shoal.gd",
	"res://scripts/dive_creature.gd",
	"res://scripts/underwater_world.gd",
	"res://addons/sky_3d/src/SkyDome.gd",
	"res://addons/sky_3d/src/Sky3D.gd",
	"res://addons/sky_3d/src/TimeOfDay.gd",
]
var _warming_scripts := false
# Models, textures, sounds and shaders have no gameplay scripts. Retain their
# prepared resources before loading scripts in dependency order on one worker.
const MODEL_WARM_PATHS := [
	"res://textures/underwater/kelp.svg",
	"res://models/sand_raftsurvival.glb",
	"res://models/coconut_palm.glb",
	"res://models/realistic_grass.glb",
	"res://models/island_lowpoly_plants.glb",
	"res://models/portable_electronics.glb",
	"res://models/banana_plant.glb",
	"res://models/potato_plant.glb",
	"res://models/tomato_plant.glb",
	"res://models/carrot_plant.glb",
	"res://models/onion_sprout.glb",
	"res://models/onion_young.glb",
	"res://models/onion_growing.glb",
	"res://models/onion_plant.glb",
	"res://models/onion_bulb.glb",
	"res://models/beach_survivor.glb",
	"res://models/survivalist.glb",
	"res://models/human_hand.glb",
	"res://models/survival_bow.glb",
	"res://models/coastal_gull.glb",
	"res://models/coastal_ridge.glb",
	"res://models/coastal_fish.glb",
	"res://models/reef_shark.glb",
	"res://models/sea_turtle.glb",
	"res://models/shore_crab.glb",
	"res://models/wild_boar.glb",
	"res://3d models/Wooded_arrow/cc0_-_wooden_arrow.glb",
	"res://shaders/object_surface.gdshader",
	"res://shaders/debris_weathered.gdshader",
	"res://shaders/meal_surface.gdshader",
	"res://shaders/cooking_steam.gdshader",
	"res://shaders/flower_petals.gdshader",
	"res://shaders/produce_skin.gdshader",
	"res://shaders/sponge_surface.gdshader",
	"res://shaders/palm_leaf.gdshader",
	"res://shaders/palm_bark.gdshader",
	"res://models/kenney_coconut.glb",
	"res://models/kenney_banana.glb",
	"res://audio/chop.ogg",
	"res://audio/pickup_rustle.ogg",
	"res://models/kenney_pot_large.glb",
	"res://shaders/sand_surface.gdshader",
	"res://shaders/soil_surface.gdshader",
	"res://textures/island/sand_diff.jpg",
	"res://shaders/wood_planks.gdshader",
	"res://shaders/rope_fiber.gdshader",
	"res://textures/construction/timber_photographic_atlas.png",
	"res://shaders/sand_footprint.gdshader",
	"res://audio/footstep_wood01.ogg",
	"res://audio/footstep_wood02.ogg",
	"res://audio/footstep_wood03.ogg",
	"res://audio/footstep_gravel.ogg",
	"res://textures/ui/survival_items.png",
	"res://textures/ui/rope_launcher.png",
	"res://textures/ui/advanced_potato.png",
	"res://textures/ui/advanced_tomato.png",
	"res://textures/ui/advanced_banana.png",
	"res://shaders/campfire.gdshader",
	"res://shaders/survivalist.gdshader",
	"res://textures/construction/survivalist_weave.png",
	"res://shaders/build_grid.gdshader",
	"res://models/kenney_log.glb",
	"res://models/kenney_barrel.glb",
	"res://models/kenney_rock_small.glb",
	"res://shaders/raft_timber.gdshader",
	"res://shaders/starter_sail.gdshader",
	"res://audio/rain_ambience.wav",
	"res://shaders/rain_sheltered.gdshader",
	"res://textures/island/sand_nor_gl.jpg",
	"res://textures/island/sand_arm.jpg",
	"res://audio/ocean_ambience.mp3",
	"res://audio/sea_wind.wav",
	"res://audio/foliage_rustle.wav",
	"res://shaders/island_mountain.gdshader",
	"res://textures/island/rock_diff.jpg",
	"res://textures/island/rock_nor_gl.jpg",
	"res://textures/island/rock_arm.jpg",
	"res://textures/ui/coastal_tree_atlas.png",
	"res://addons/sky_3d/assets/thirdparty/textures/moon/MoonMap.png",
	"res://addons/sky_3d/assets/thirdparty/textures/milkyway/Milkyway.jpg",
	"res://addons/sky_3d/assets/thirdparty/textures/milkyway/StarField.jpg",
	"res://addons/sky_3d/assets/textures/noise.jpg",
	"res://addons/sky_3d/assets/textures/noiseClouds.png",
]
var _warm_resources: Array[Resource] = []
const RESOURCE_BATCH_SIZE := 8
var _load_worker: Thread
var _prepare_paths: Array = []
var _prepare_index := 0
var _load_requested := false
var _load_progress := 0.0
var _packed_game: PackedScene = null
var _waiting_to_enter := false    # tapped, waiting for the load to finish
var _wait_seconds := 0.0          # how long the current wait has been going
var _pending_idx := -1            # button that is running (draws LOADING)
var _selected_id := ""            # "new" / "continue" / "quick", applied on go
var _error := ""                  # non-empty -> drawn as a red banner

func _ready() -> void:
	if _is_mobile():
		Engine.max_fps = GameSettings.target_fps
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.name = "OceanBackdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.z_index = -1
	var sea_material := ShaderMaterial.new()
	sea_material.shader = SEA_BACKDROP
	backdrop.material = sea_material
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_buttons.clear()
	if Inventory.has_save("main"):
		_buttons.append({"id": "continue", "label": "CONTINUE",
			"sub": _save_sub("main")})
	if Inventory.has_save("quick"):
		_buttons.append({"id": "quick", "label": "QUICK SAVE",
			"sub": _save_sub("quick")})
	_buttons.append({"id": "new", "label": "NEW GAME", "sub": ""})
	_buttons.append({"id": "settings", "label": "SETTINGS", "sub": ""})
	# Build the hit rects right away: the first tap must never arrive before
	# the first _draw() has run.
	_vp = size / _ui_scale()
	_layout_buttons()
	# Start warming the game scene on a worker thread.
	_request_game_load()
	queue_redraw()


func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") \
		or OS.has_feature("ios") or OS.has_feature("web_android")


func _notification(what: int) -> void:
	# Rotation / split-screen / foldables resize the viewport at runtime.
	if what == NOTIFICATION_RESIZED:
		_vp = size / _ui_scale()
		_layout_buttons()
		queue_redraw()


## Human label for a save slot: "DAY n · hh:mm" from the saved game time.
func _save_sub(slot: String) -> String:
	var info: Dictionary = Inventory.save_info(slot)
	if info.has("game_time"):
		var gt: float = float(info["game_time"])
		var day: int = maxi(1, int(info.get("game_day", 1)))
		var h: int = int(gt) % 24
		var m: int = int((gt - floorf(gt)) * 60.0) % 60
		return "DAY %d  ·  %02d:%02d" % [day, h, m]
	if info.has("saved_at"):
		var stamp: String = Time.get_datetime_string_from_unix_time(int(info["saved_at"]), true)
		if stamp.length() >= 16:
			return "SAVED  " + stamp.substr(0, 16)
	return ""


func _process(delta: float) -> void:
	_t += delta
	_poll_game_load()
	# Heavy script compilation must finish before the film's playback clock starts.
	if _story_pending and not _warming_scripts and _busy:
		_start_story()
	if is_instance_valid(_intro): _intro.set("progress",_load_progress)
	# The tap came in before the background load finished -> go now.
	if _waiting_to_enter:
		_wait_seconds += delta
		if _packed_game != null:
			_waiting_to_enter = false
			_swap_scene(_packed_game)
			return
	if not visible:
		return
	_vp = size / _ui_scale()
	# hover tracking (mouse only — phones have no hover)
	if not _is_mobile():
		_hover = _hit(get_local_mouse_position())
	# Backdrop motion runs in one shader; UI only needs a modest refresh rate.
	_redraw_seconds += delta
	if _redraw_seconds >= 0.1:
		_redraw_seconds = 0.0
		queue_redraw()


# ============================================================
# INPUT — custom buttons (works with mouse and touch)
# ============================================================
func _gui_input(event: InputEvent) -> void:
	if GameSettings.is_open:
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var idx := _hit(mb.position)
	if mb.pressed:
		_press = idx
		# Fire immediately: on a phone the release event can be dropped,
		# reordered or land a few pixels away.
		if idx >= 0:
			_activate(idx)
	else:
		_press = -1
	queue_redraw()
	accept_event()


func _input(event: InputEvent) -> void:
	if is_instance_valid(_intro): return
	if GameSettings.is_open:
		return
	var handled := false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var idx := _hit(_to_local(t.position))
		if t.pressed:
			if not _touch_ids.has(t.index):
				_touch_ids.append(t.index)
			_press = idx
			if idx >= 0:
				_activate(idx)
		else:
			_touch_ids.erase(t.index)
			if _touch_ids.is_empty():
				_press = -1
		handled = true
	elif event is InputEventScreenDrag:
		# Keep the pressed highlight under the finger while it slides.
		var d := event as InputEventScreenDrag
		if _touch_ids.has(d.index):
			_press = _hit(_to_local(d.position))
			handled = true
	elif event is InputEventKey:
		# Keyboard / gamepad / TV-remote fallback: Enter or Space takes the
		# first entry (Continue when a save exists, otherwise New Game).
		var k := event as InputEventKey
		if k.pressed and not k.echo and not _busy and not _buttons.is_empty() \
				and (k.physical_keycode == KEY_ENTER or k.physical_keycode == KEY_KP_ENTER
					or k.physical_keycode == KEY_SPACE):
			_activate(0)
			handled = true
	if handled:
		queue_redraw()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


## Screen-space (viewport) position -> this Control's local space, so the hit
## test is correct even if the menu is ever moved, scaled or rotated.
func _to_local(pos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * pos


func _hit(pos: Vector2) -> int:
	_ensure_layout()
	pos/=_ui_scale()
	for i in range(_btn_rects.size()):
		if (_btn_rects[i] as Rect2).has_point(pos):
			return i
	return -1


## The rects are normally built during _draw(); make sure they exist before
## any hit test so a tap on the very first frame still lands.
func _ensure_layout() -> void:
	if size / _ui_scale() != _vp or _btn_rects.size() != _buttons.size():
		_vp = size / _ui_scale()
		_layout_buttons()


# ============================================================
# RUN / RESUME — start the game without ever dead-ending the menu
# ============================================================
func _activate(btn_idx: int) -> void:
	if btn_idx < 0 or btn_idx >= _buttons.size():
		return
	var action_id := str(_buttons[btn_idx]["id"])
	if action_id == "cancel":
		_cancel_loading()
		return
	if action_id == "settings":
		GameSettings.open()
		return
	if _busy:
		return
	_busy = true
	_pending_idx = btn_idx
	_error = ""
	# Remember the choice; the save slot is only touched once we know the game
	# scene can really be opened (never wipe a save for a transition that fails).
	_selected_id = action_id
	if action_id == "new" and DisplayServer.get_name() != "headless":
		_story_pending = true
		if not _warming_scripts: _start_story()
	if _packed_game == null and not _load_requested:
		_request_game_load()
	if _busy:
		_enter_game()
	queue_redraw()


func _start_story() -> void:
	_story_pending = false
	_intro = load("res://scripts/flooded_world_intro.gd").new() as Control
	add_child(_intro)
	_intro.cancelled.connect(_cancel_loading)


func _apply_selection() -> bool:
	if _selected_id == "continue":
		if Inventory.load_game("main").is_empty():
			_error = Inventory.last_save_error
			return false
	elif _selected_id == "quick":
		if Inventory.load_game("quick").is_empty():
			_error = Inventory.last_save_error
			return false
	elif _selected_id == "new":
		# Keep the on-disk saves until the new world successfully starts saving.
		Inventory.new_game_reset(false)
	_selected_id = ""
	return true


func _enter_game() -> void:
	if _packed_game != null:
		_swap_scene(_packed_game)
		return
	if _load_requested and _error == "":
		# Warm-up still running: keep the button in its LOADING state and swap
		# from _process() the instant the scene lands in memory.
		_waiting_to_enter = true
		_wait_seconds = 0.0
		_buttons.append({"id": "cancel", "label": "CANCEL LOADING", "sub": ""})
		_layout_buttons()
		queue_redraw()
		return
	# A failed request has already unlocked the menu and shown an error.
	if _busy:
		_fail("GAME FILES COULD NOT LOAD · install the updated APK")

## Cancelling the choice does not cancel or duplicate the resource request.
## It can finish warming in the background; no inventory/save changes occurred.
func _cancel_loading() -> void:
	_story_pending = false
	if is_instance_valid(_intro): _intro.queue_free()
	_intro = null
	_busy = false
	_waiting_to_enter = false
	_pending_idx = -1
	_selected_id = ""
	_wait_seconds = 0.0
	_remove_cancel_button()
	queue_redraw()


func _remove_cancel_button() -> void:
	for index in range(_buttons.size() - 1, -1, -1):
		if str(_buttons[index]["id"]) == "cancel":
			_buttons.remove_at(index)
	_press = -1
	_hover = -1
	_layout_buttons()


func _swap_scene(packed: PackedScene) -> void:
	if _story_pending:
		_waiting_to_enter = true
		return
	if is_instance_valid(_intro) and not bool(_intro.get("complete")):
		_waiting_to_enter = true
		return
	# Resolve every dependency BEFORE changing inventory or touching a save.
	if packed == null:
		packed = ResourceLoader.load(GAME_SCENE) as PackedScene
	if packed == null or not packed.can_instantiate():
		_fail("GAME FILES COULD NOT LOAD · install the updated APK")
		return
	var previous_slots: Array = Inventory.slots.duplicate(true)
	var previous_meta: Dictionary = Inventory.loaded_meta.duplicate(true)
	var previous_pickups: Dictionary = Inventory.collected_island_pickups.duplicate(true)
	# Continue needs the same input/save protection during incremental restoration.
	var handoff := load("res://scripts/wake_transition.gd").new() as CanvasLayer
	if _selected_id == "new" and is_instance_valid(_intro):
		handoff.set("arrival_texture", _intro.get("handoff_texture"))
	else:
		handoff.set("resuming", true)
	get_tree().root.add_child(handoff)
	if not _apply_selection():
		if handoff != null: handoff.queue_free()
		_busy = false
		_waiting_to_enter = false
		_remove_cancel_button()
		queue_redraw()
		return
	var err: int = get_tree().change_scene_to_packed(packed)
	if err != OK:
		if handoff != null: handoff.queue_free()
		Inventory.slots = previous_slots
		Inventory.loaded_meta = previous_meta
		Inventory.collected_island_pickups = previous_pickups
		Inventory._recompute()
		Inventory.changed.emit()
		_fail("COULD NOT START GAME  ·  err %d" % err)


## Never leave the player with a menu that ignores every tap: say why it
## failed and unlock the buttons so they can try again.
func _fail(msg: String) -> void:
	_story_pending = false
	if is_instance_valid(_intro): _intro.queue_free()
	_intro = null
	push_error("[MainMenu] " + msg + " (" + GAME_SCENE + ")")
	_error = msg
	_busy = false
	_waiting_to_enter = false
	_pending_idx = -1
	_selected_id = ""
	_remove_cancel_button()
	# Real resource errors unlock retry. An in-progress request is kept; launching
	# another request for the same path would not restart the existing work.
	_load_requested = _load_worker != null and _load_worker.is_started()
	queue_redraw()


## Load on one explicitly joined worker at a time. Godot 4.7.1's threaded
## request API leaks an internal zero-reference token per uncached request.
## Reading resources with ResourceLoader.load on our own worker avoids it
## while retaining serial script compilation and a responsive menu.
func _request_game_load() -> void:
	if _load_requested:
		return
	_load_requested = true
	if not ResourceLoader.exists(GAME_SCENE):
		_fail("MISSING  " + GAME_SCENE)
		return
	_warming_scripts = true
	_prepare_paths = MODEL_WARM_PATHS + SCRIPT_WARM_PATHS
	_warm_resources.clear()
	_prepare_index = 0
	_load_progress = 0.0
	for image in preload("res://scripts/item_art.gd").STATION_IMAGES.values():
		_prepare_paths.append("res://textures/ui/stations/"+str(image)+".png")
	for item in ["solar_torch","walkie_talkie","binoculars","repair_kit"]:
		_prepare_paths.append("res://textures/ui/tools/"+item+".png")
	if ResourceLoader.exists("res://textures/ui/food/recipe_atlas.png"):
		_prepare_paths.append("res://textures/ui/food/recipe_atlas.png")
	else:
		for dish in preload("res://scripts/food_rules.gd").RECIPES:
			_prepare_paths.append("res://textures/ui/food/"+str(dish).to_lower().replace(" ","_")+".png")
	for dish in ["Tumbler","Ocean Water Tumbler","Boiled Water Tumbler","Diving Tank"]:
		_prepare_paths.append("res://textures/ui/food/"+str(dish).to_lower().replace(" ","_")+".png")
	_start_resource_load(str(_prepare_paths[0]))


func _start_resource_load(path: String) -> void:
	var paths: Array = _prepare_paths.slice(_prepare_index, _prepare_index + RESOURCE_BATCH_SIZE) if _warming_scripts else [path]
	_load_worker = Thread.new()
	var error := _load_worker.start(_load_resource_worker.bind(paths))
	if error != OK:
		_load_worker = null
		_warming_scripts = false
		_fail("COULD NOT START LOADING  " + path)


func _load_resource_worker(paths: Array) -> Dictionary:
	# Worker code never accesses the scene tree or gameplay state.
	# Keep dependency/script order, without a frame and thread launch per file.
	var resources: Array[Resource] = []
	var timings: Array = []
	for path: String in paths:
		var started := Time.get_ticks_msec()
		var resource := ResourceLoader.load(path)
		if resource == null: return {"resources": resources, "failed": path, "timings": timings}
		resources.append(resource)
		timings.append([path, Time.get_ticks_msec() - started])
	return {"resources": resources, "failed": "", "timings": timings}


func _poll_game_load() -> void:
	if not _load_requested or _packed_game != null or _load_worker == null:
		return
	if _load_worker.is_alive():
		return
	# Join only after completion; this never blocks a normal render frame.
	var result: Dictionary = _load_worker.wait_to_finish()
	_load_worker = null
	if not str(result.failed).is_empty():
		_warming_scripts = false
		_fail("COULD NOT PREPARE GAME FILES · " + str(result.failed))
		return
	if "--profile-loading" in OS.get_cmdline_user_args():
		for timing in result.timings: print("LOAD RESOURCE ", timing[0], " ", timing[1], " ms")
	var resources: Array = result.resources
	if _warming_scripts:
		_warm_resources.append_array(resources)
		_prepare_index += resources.size()
		_load_progress = 0.60 * float(_prepare_index) / float(_prepare_paths.size())
		if _prepare_index < _prepare_paths.size():
			_start_resource_load(str(_prepare_paths[_prepare_index]))
		else:
			_warming_scripts = false
			_start_resource_load(GAME_SCENE)
		return
	var prepared: Resource = resources[0]
	if prepared is PackedScene:
		_packed_game = prepared
		_load_progress = 1.0
		queue_redraw()
	else:
		_fail(GAME_SCENE + "  IS NOT A SCENE")


func _exit_tree() -> void:
	# Closing the menu/program mid-load must join its owned thread before the
	# script is freed. Cancel Loading keeps it alive to finish in the lobby.
	if _load_worker != null and _load_worker.is_started():
		_load_worker.wait_to_finish()
	_load_worker = null


# ============================================================
# LAYOUT
# ============================================================
func _layout_buttons() -> void:
	_btn_rects.clear()
	var s := _vp
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var landscape:=s.x/s.y>1.3 and s.x>=600
	var short_screen:=landscape and s.y<570
	var bw:=minf(s.x*.38,420) if landscape else minf(s.x-40,420)
	var gap:=8.0 if s.y<570 else 10.0
	var bh:=clampf((s.y*.48-gap*maxi(0,_buttons.size()-1))/maxi(_buttons.size(),1),48,72)
	if short_screen:bh=clampf((s.y-100-gap*maxi(0,_buttons.size()-1))/maxi(_buttons.size(),1),48,68)
	var total_h:=_buttons.size()*bh+gap*maxi(0,_buttons.size()-1)
	var x:=s.x*.065 if landscape else (s.x-bw)*.5
	if short_screen:x=s.x*.54
	var y:=s.y*.42 if landscape else s.y*.39
	if short_screen:y=(s.y-total_h)*.5
	y=minf(y,s.y-total_h-54)
	for i in range(_buttons.size()):
		_btn_rects.append(Rect2(x,y,bw,bh))
		y+=bh+gap


# ============================================================
# DRAW — sky / sun / ocean / title / buttons
# ============================================================
func _draw() -> void:
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*_ui_scale())
	if _vp.x <= 0.0:
		_vp = size / _ui_scale()
	if _vp.x <= 0.0:
		return
	_layout_buttons()
	var s := _vp
	_draw_lobby_scene(s)
	_draw_title(s)
	_draw_buttons(s)
	_draw_error(s)
	_draw_footer(s)

func _ui_scale() -> float:
	return preload("res://scripts/ocean_ui.gd").scale_for(get_viewport())


func _lerp_color(a: Color, b: Color, k: float) -> Color:
	var kk := clampf(k, 0.0, 1.0)
	return Color(a.r + (b.r - a.r) * kk, a.g + (b.g - a.g) * kk,
		a.b + (b.b - a.b) * kk, a.a + (b.a - a.a) * kk)


func _draw_sky(s: Vector2, horizon: float) -> void:
	# banded vertical gradient: deep night navy -> teal -> warm horizon glow
	var top_c := Color(0.008, 0.03, 0.06)
	var mid_c := Color(0.03, 0.12, 0.16)
	var glow_c := Color(0.32, 0.16, 0.1)
	var bands := 30
	var band_h: float = horizon / float(bands)
	for i in range(bands):
		var k: float = float(i) / float(bands)
		var col: Color
		if k < 0.55:
			col = _lerp_color(top_c, mid_c, k / 0.55)
		else:
			col = _lerp_color(mid_c, glow_c, (k - 0.55) / 0.45)
		draw_rect(Rect2(0.0, float(i) * band_h, s.x, band_h + 1.0), col)


func _draw_sun(s: Vector2, horizon: float) -> void:
	# low warm sun with a soft glow, sitting just on the horizon right-of-center
	var cx: float = s.x * 0.72
	var cy: float = horizon - s.y * 0.03
	var sr: float = minf(s.y * 0.085, 84.0)
	# glow rings
	for g in range(6, 0, -1):
		var gr: float = sr * (1.0 + float(g) * 0.34)
		var ga: float = 0.05 + float(6 - g) * 0.008
		draw_circle(Vector2(cx, cy), gr, Color(1.0, 0.62, 0.28, ga))
	draw_circle(Vector2(cx, cy), sr, Color(1.0, 0.8, 0.42, 0.95))
	draw_circle(Vector2(cx, cy), sr * 0.82, Color(1.0, 0.94, 0.72, 1.0))
	# horizontal haze band around the sun line
	draw_rect(Rect2(0.0, cy - sr * 0.7, s.x, sr * 1.6), Color(1.0, 0.55, 0.3, 0.05))


func _draw_ocean(s: Vector2, horizon: float) -> void:
	var depth: float = s.y - horizon
	var bands := 26
	var band_h: float = depth / float(bands)
	for i in range(bands):
		var k: float = float(i) / float(bands)
		var col := _lerp_color(Color(0.03, 0.14, 0.17), Color(0.005, 0.02, 0.035), k)
		draw_rect(Rect2(0.0, horizon + float(i) * band_h, s.x, band_h + 1.0), col)
	# animated wave crest lines (cheap: a few sine polylines)
	var rows := 10
	for r in range(rows):
		var ky: float = float(r) / float(rows)
		var base_y: float = horizon + 6.0 + ky * depth * 0.92
		var amp: float = 2.5 + ky * depth * 0.09
		var speed: float = 1.6 + ky * 0.9
		var alpha: float = 0.34 * (1.0 - ky * 0.72)
		var pts := PackedVector2Array()
		var segs := 26
		for i in range(segs + 1):
			var x: float = s.x * float(i) / float(segs)
			var ph: float = sin(x * 0.018 + _t * speed + float(r) * 1.7)
			var ph2: float = sin(x * 0.007 - _t * speed * 0.6 + float(r))
			pts.append(Vector2(x, base_y + ph * amp + ph2 * amp * 0.6))
		draw_polyline(pts, Color(0.75, 0.95, 1.0, alpha), 1.4, true)
	# sun glint path (soft vertical shimmer under the sun)
	var gx: float = s.x * 0.72
	for k in range(16):
		var gy: float = horizon + 8.0 + float(k) * (depth * 0.8) / 16.0
		var gw: float = 3.0 + float(k) * 1.5
		var ga: float = 0.14 * (1.0 - float(k) / 18.0)
		draw_rect(Rect2(gx - gw * 0.5, gy, gw, 3.0), Color(1.0, 0.9, 0.6, ga))


func _draw_lobby_scene(s: Vector2) -> void:
	if s.x/s.y<1.3:return
	# A distant island and navigation rose are original vector artwork.
	var centre:=Vector2(s.x*.87,s.y*.458)
	var ink:=Color(.07,.23,.28,.65)
	draw_colored_polygon(PackedVector2Array([centre+Vector2(-68,2),centre+Vector2(-44,-8),centre+Vector2(-9,-13),centre+Vector2(23,-7),centre+Vector2(58,2)]),ink)
	var palm:=centre+Vector2(-5,-10)
	draw_polyline(PackedVector2Array([palm,palm+Vector2(4,-22),palm+Vector2(11,-35)]),ink,2,true)
	var crown:=palm+Vector2(11,-35)
	for direction in [Vector2(-22,-2),Vector2(-15,-10),Vector2(14,-12),Vector2(22,-1),Vector2(19,8)]:
		draw_polyline(PackedVector2Array([crown,crown+direction*.55+Vector2(0,-4),crown+direction]),ink,2,true)
	if s.y<570:return
	var rose:=Vector2(s.x*.90,s.y*.82)
	draw_arc(rose,38,0,TAU,48,Color(.68,.90,.89,.18),1,true)
	for index in 8:
		var direction:=Vector2.from_angle(index*TAU/8)
		draw_line(rose+direction*30,rose+direction*36,Color(.68,.90,.89,.35),1,true)
	draw_colored_polygon(PackedVector2Array([rose+Vector2(0,-27),rose+Vector2(7,0),rose+Vector2(0,19),rose+Vector2(-7,0)]),Color(.72,.96,.93,.38))
	_draw_text("N",rose+Vector2(-5,-45),13,Color(.72,.96,.93,.7))

func _draw_title(s: Vector2) -> void:
	var landscape:=s.x/s.y>1.3 and s.x>=600
	var short_screen:=landscape and s.y<570
	var width:=s.x*.42 if landscape else s.x-40
	var fs:=int(clampf(s.y*.095,38,78))
	var font:=ThemeDB.fallback_font
	fs=mini(fs,int(fs*width/maxf(font.get_string_size("OCEAN",HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x,1)))
	var x:=s.x*.065 if landscape else (s.x-font.get_string_size("OCEAN",HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x)*.5
	var y:=s.y*.12+fs*.72
	if short_screen:y=s.y*.25
	var tag:="OPEN WATER · A NEW BEGINNING"
	var tag_size:=12 if short_screen else 13
	var tag_x:=x if landscape else (s.x-font.get_string_size(tag,HORIZONTAL_ALIGNMENT_LEFT,-1,tag_size).x)*.5
	_draw_text(tag,Vector2(tag_x,y-fs-16),tag_size,Color("82d9d3"))
	_draw_text("OCEAN",Vector2(x+2,y+3),fs,Color(0,.03,.06,.35))
	_draw_text("OCEAN",Vector2(x,y),fs,Color("f0fafb"))
	var sub_fs:=int(fs*.64)
	var title_width:=font.get_string_size("SURVIVAL",HORIZONTAL_ALIGNMENT_LEFT,-1,sub_fs).x
	var second_x:=x if landscape else (s.x-title_width)*.5
	_draw_text("SURVIVAL",Vector2(second_x,y+fs*.72),sub_fs,Color("8febe0"))
	_title_w=maxf(title_width,font.get_string_size("OCEAN",HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x)
	var line_y:=y+fs*.94
	var line_x:=x if landscape else s.x*.5-30
	draw_line(Vector2(line_x,line_y),Vector2(line_x+60,line_y),Color("79e1d6"),2,true)
	var caption:="Build a home. Find your horizon."
	var caption_size:=13 if short_screen else 16
	var caption_x:=x if landscape else (s.x-font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,caption_size).x)*.5
	_draw_text(caption,Vector2(caption_x,line_y+29),caption_size,Color("b6d4df"))


func _draw_buttons(_s: Vector2) -> void:
	for i in _btn_rects.size():
		var rect:Rect2=_btn_rects[i]
		var button:Dictionary=_buttons[i]
		var hovered:=i==_hover
		var pressed:=i==_press
		var primary: bool=i==0 and button.id!="settings" and button.id!="cancel"
		var rr:=Rect2(rect.position+Vector2(0,2 if pressed else 0),rect.size)
		var base:=Color("176879") if primary else Color(.035,.13,.19,.88)
		if hovered:base=base.lightened(.12)
		if pressed:base=base.darkened(.10)
		_draw_rounded(Rect2(rr.position+Vector2(0,5),rr.size),14,Color(0,.025,.05,.25))
		_draw_rounded(rr,14,base)
		_draw_rounded(rr,14,Color("72ded5") if primary or hovered else Color(.37,.64,.72,.35),false,1)
		var icon:=rr.position+Vector2(30,rr.size.y*.5)
		_draw_button_icon(icon,17,button.id,Color("c4f3ed") if primary else Color("8fbdcb"))
		var label:String=button.label
		var sub:String=button.sub
		if sub.is_empty():sub={"new":"Begin your voyage","settings":"Make it yours","cancel":"Return to the lobby"}.get(button.id,"")
		var running:=_busy and i==_pending_idx
		if running:
			label="LOADING…";sub="Preparing ocean · %d%%"%roundi(_load_progress*100)
			if _wait_seconds>=LONG_LOAD_NOTICE_AFTER:sub="%d%% · Still loading"%roundi(_load_progress*100)
		var fs:=20 if rr.size.y>=60 else 17
		var label_y:=rr.position.y+rr.size.y*.44 if not sub.is_empty() else rr.position.y+rr.size.y*.5+fs*.35
		_draw_text(label,Vector2(rr.position.x+60,label_y),fs,Color("eef8fa"))
		if not sub.is_empty():_draw_text(sub,Vector2(rr.position.x+60,label_y+20),12,Color("a8ced8"))
		draw_polyline(PackedVector2Array([rr.position+Vector2(rr.size.x-27,rr.size.y*.5-5),rr.position+Vector2(rr.size.x-22,rr.size.y*.5),rr.position+Vector2(rr.size.x-27,rr.size.y*.5+5)]),Color("91d3d5"),2,true)
		if running:
			var bar:=Rect2(rr.position.x+16,rr.end.y-6,rr.size.x-32,2)
			draw_rect(bar,Color(.02,.1,.15,.5))
			draw_rect(Rect2(bar.position,Vector2(bar.size.x*clampf(_load_progress,0,1),2)),Color("64e3d5"))


func _draw_error(s: Vector2) -> void:
	if _error == "":
		return
	var font := ThemeDB.fallback_font
	var fs := 16
	var msg := _error
	var tw: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var max_w: float = s.x * 0.9
	if tw > max_w:
		var keep := int(msg.length() * (max_w / tw)) - 1
		msg = msg.substr(0, maxi(keep, 8)) + "…"
		tw = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2((s.x - tw) * 0.5 - 16.0, s.y * 0.86, tw + 32.0, fs * 2.4)
	_draw_rounded(box, 10.0, Color(0.28, 0.06, 0.05, 0.92))
	_draw_rounded(box, 10.0, Color(0.95, 0.4, 0.35, 0.9), false, 2.0)
	_draw_text(msg, Vector2((s.x - tw) * 0.5, box.position.y + fs * 1.6), fs,
		Color(1.0, 0.85, 0.8, 1.0))


func _draw_button_icon(c: Vector2, r: float, id: String, col: Color) -> void:
	match id:
		"cancel":
			draw_line(c + Vector2(-r * 0.4, -r * 0.4), c + Vector2(r * 0.4, r * 0.4), col, maxf(r * 0.12, 2.0), true)
			draw_line(c + Vector2(r * 0.4, -r * 0.4), c + Vector2(-r * 0.4, r * 0.4), col, maxf(r * 0.12, 2.0), true)
		"settings":
			draw_arc(c, r * 0.42, 0.0, TAU, 24, col, maxf(r * 0.13, 1.5), true)
			draw_arc(c, r * 0.14, 0.0, TAU, 16, col, maxf(r * 0.09, 1.0), true)
			for tooth in range(8):
				var direction := Vector2.from_angle(float(tooth) * TAU / 8.0)
				draw_line(c + direction * r * 0.43, c + direction * r * 0.64, col, maxf(r * 0.16, 2.0), true)
		"continue":
			# play triangle
			var tri := PackedVector2Array([
				c + Vector2(-r * 0.42, -r * 0.55), c + Vector2(-r * 0.42, r * 0.55),
				c + Vector2(r * 0.6, 0.0),
			])
			draw_colored_polygon(tri, col)
		"quick":
			# clock: circle + hands
			draw_arc(c, r * 0.62, 0.0, TAU, 24, col, maxf(r * 0.12, 1.5), true)
			draw_line(c, c + Vector2(0.0, -r * 0.4), col, maxf(r * 0.12, 1.5))
			draw_line(c, c + Vector2(r * 0.26, r * 0.2), col, maxf(r * 0.12, 1.5))
		_:
			# plus = new game
			draw_arc(c, r * 0.62, 0.0, TAU, 24, col, maxf(r * 0.12, 1.5), true)
			draw_line(c + Vector2(-r * 0.3, 0.0), c + Vector2(r * 0.3, 0.0), col, maxf(r * 0.14, 2.0))
			draw_line(c + Vector2(0.0, -r * 0.3), c + Vector2(0.0, r * 0.3), col, maxf(r * 0.14, 2.0))


func _draw_footer(s: Vector2) -> void:
	var foot:="YOUR OCEAN. YOUR STORY."
	var fs:=11 if s.x<700 else 12
	var font:=ThemeDB.fallback_font
	var x:=s.x*.065 if s.x/s.y>1.3 and s.x>=600 else (s.x-font.get_string_size(foot,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x)*.5
	_draw_text(foot,Vector2(x,s.y-22),fs,Color(.65,.83,.87,.75))
	if s.x>=600:
		var version:="v"+str(ProjectSettings.get_setting("application/config/version","1.1.7"))
		_draw_text(version,Vector2(s.x-80,s.y-22),12,Color(.65,.83,.87,.65))


func _draw_text(text: String, top_left: Vector2, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, top_left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_rounded(rect: Rect2, radius: float, color: Color, filled: bool = true, width: float = 1.0) -> void:
	UI_SURFACE.panel(self, rect, radius, color, filled, width)
