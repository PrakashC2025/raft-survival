extends Node
## Bow charge/release shares the owned HAND action on touch and E on desktop.
var player: CharacterBody3D
var draw_time := 0.0
var drawing := false
var aiming := false
var _normal_fov := 75.0
var cooldown := 0.0
var _arrows: Array[Dictionary] = []
var _arrow_glb: PackedScene = preload("res://3d models/Wooded_arrow/cc0_-_wooden_arrow.glb")
var _arrow_mesh: Node3D
var _arrow_material: StandardMaterial3D
var _bobber: MeshInstance3D
var _line: MeshInstance3D
var _cast_target := Vector3.ZERO
var _cast_age := 0.0
var _cast_start := Vector3.ZERO
var _catch_visual: Node3D
var _cast_clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_parent() as CharacterBody3D
	_arrow_mesh = _arrow_glb.instantiate() as Node3D
	_arrow_material = StandardMaterial3D.new()
	_arrow_material.albedo_color = Color(0.40, 0.24, 0.10)
	_arrow_material.roughness = 0.9

func begin_draw() -> void:
	if cooldown > 0.0 or drawing:
		return
	if not Inventory.has("Arrow", 1):
		player.call("_hud_toast", "CRAFT ARROWS FIRST")
		return
	drawing = true
	draw_time = 0.0

func cancel_draw() -> void:
	drawing = false
	draw_time = 0.0

func get_draw_fraction() -> float:
	return clampf(draw_time / 1.1, 0.0, 1.0) if drawing else 0.0

func toggle_aim() -> void:
	var hud := player.get_node_or_null("CanvasLayer/SurvivalHUD")
	if player.get("active_item") != "Bow" or player.get("build_mode") or get_tree().paused \
			or GameSettings.is_open or (hud != null and bool(hud.call("gameplay_input_blocked"))):
		return
	set_aiming(not aiming)

func set_aiming(enabled: bool) -> void:
	if aiming == enabled:
		return
	var camera := player.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	if enabled:
		_normal_fov = camera.fov
		camera.fov = minf(_normal_fov, 48.0)
	else:
		camera.fov = _normal_fov
	aiming = enabled

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		set_aiming(false)
		drawing = false

func _physics_process(delta: float) -> void:
	if get_tree().paused or GameSettings.is_open:
		drawing = false
		set_aiming(false)
		return
	cooldown = maxf(0.0, cooldown - delta)
	var hud := player.get_node_or_null("CanvasLayer/SurvivalHUD")
	var blocked := get_tree().paused or (hud != null and bool(hud.call("gameplay_input_blocked")))
	if blocked or player.get("active_item") != "Bow" or player.get("build_mode"):
		set_aiming(false)
	if drawing:
		if player.get("active_item") != "Bow" or blocked or player.get("build_mode"):
			drawing = false
		elif Input.is_action_pressed("interact"):
			draw_time = minf(1.1, draw_time + delta)
		else:
			_fire()
	_update_cast()
	_cast_clock+=delta
	for i in range(_arrows.size() - 1, -1, -1):
			var arrow: Dictionary = _arrows[i]
			var node := arrow["node"] as Node3D
			arrow["life"] = float(arrow["life"]) - delta
			var velocity: Vector3 = arrow["velocity"]
			velocity += Vector3.DOWN * 9.8 * delta
			arrow["velocity"] = velocity
			var end := node.global_position + velocity * delta
			var query := PhysicsRayQueryParameters3D.create(node.global_position, end, 3, [player.get_rid()])
			query.collide_with_areas = true
			var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				var target: Node = hit["collider"]
				if target.is_in_group("huntable_bird"):
					var flock: Node = target.get_meta("flock")
					if flock.call("hit_bird", int(target.get_meta("bird_index"))):
						player.call("_hud_toast", "BIRD HIT  •  COLLECT IT WHERE IT LANDS")
				elif target.has_method("take_damage"):
					target.call("take_damage", 30.0, player)
				node.queue_free()
				_arrows.remove_at(i)
				continue
			node.global_position = end
			if velocity.length_squared() > 0.1:
				node.look_at(end + velocity, Vector3.UP)
			if float(arrow["life"]) <= 0.0 or end.y < -3.0:
				node.queue_free()
				_arrows.remove_at(i)

func _fire() -> void:
	var fraction := get_draw_fraction()
	drawing = false
	if cooldown>0 or player.get("active_item")!="Bow" or Stats.health<=0 or _arrows.size() >= 12:
		return
	if not Inventory.try_exchange({"Arrow":1},{}):return
	cooldown=.55
	player.call("play_action","bow",0.45)
	var camera := player.get_node("CamPivot/SpringArm3D/Camera3D") as Camera3D
	var root := Node3D.new()
	root.name = "FlyingArrow"
	root.add_child(_arrow_mesh.duplicate())
	get_tree().current_scene.add_child(root)
	root.global_position = camera.global_position - camera.global_basis.z * 0.35
	_arrows.append({"node": root, "velocity": -camera.global_basis.z * lerpf(18.0, 38.0, fraction), "life": 4.0})
	player.call("_queue_save")

func show_cast(target: Vector3) -> void:
	_cast_target = target
	_cast_age=0.0
	_cast_start=player.call("get_fishing_rod_tip")
	if _bobber == null:
		_bobber = MeshInstance3D.new()
		_bobber.name = "FishingFloat"
		var shape := SphereMesh.new()
		shape.radius = 0.045
		shape.height = 0.12
		shape.radial_segments = 12
		shape.rings = 6
		_bobber.mesh = shape
		var float_material := StandardMaterial3D.new()
		float_material.albedo_color = Color(0.72, 0.23, 0.07)
		_bobber.material_override = float_material
		_bobber.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(_bobber)
		_line = MeshInstance3D.new()
		_line.name = "FishingLine"
		var line_material := StandardMaterial3D.new()
		line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line_material.albedo_color = Color(0.65, 0.68, 0.59)
		_line.material_override = line_material
		_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(_line)
	_update_cast()

func _update_cast() -> void:
	var pending: bool = player.get("_fishing_catch")
	if _bobber==null and pending and player.get("active_item")=="Fishing Rod":
		show_cast(player.global_position)
		return
	if _bobber == null:
		return
	var casting: bool = player.get("active_item") == "Fishing Rod" and (float(player.get("_fishing_time_remaining")) > 0.0 or pending) and not player.get("is_swimming") and not player.get("build_mode")
	_bobber.visible = casting and not pending
	_line.visible = casting
	if not casting:
		if is_instance_valid(_catch_visual):_catch_visual.visible=false
		return
	_cast_age+=get_physics_process_delta_time()
	var ocean := get_tree().current_scene.get_node_or_null("Ocean")
	var at := _cast_target
	if ocean != null:
		at.y = float(ocean.call("get_height", at)) + 0.03
	var from: Vector3=player.call("get_fishing_rod_tip")
	var flight := clampf(_cast_age/0.7,0,1)
	if flight<1:
		at=_cast_start.lerp(at,flight)+Vector3.UP*sin(flight*PI)*1.2
	var remaining := float(player.get("_fishing_time_remaining"))
	if remaining<1.2 or pending:
		var hook := catch_position()+Vector3.UP*.18
		at=at.lerp(hook,smoothstep(0.0,1.0,1.0-remaining/1.2)) if not pending else hook
		if not is_instance_valid(_catch_visual):
			_catch_visual=preload("res://scripts/survival_item_visual.gd").create("Fish")
			get_tree().current_scene.add_child(_catch_visual)
		var struggle := sin(_cast_clock*18.0)*pow(maxf(0.0,sin(_cast_clock*2.3)),2.0)
		_catch_visual.visible=true
		_catch_visual.global_position=at+Vector3.DOWN*.18+Vector3(struggle*.018,absf(struggle)*.028,0)
		_catch_visual.rotation=Vector3(struggle*.25,sin(_cast_clock*9.0)*.12,PI/2+struggle*.18)
	_bobber.global_position = at
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(9):
		var t := float(i) / 8.0
		surface.add_vertex(from.lerp(at, t) + Vector3.DOWN * sin(t * PI) * 0.15)
	_line.mesh = surface.commit()

func catch_position() -> Vector3:
	if int(player.get("cam_mode"))==0:
		return (player.get("camera") as Camera3D).to_global(Vector3(-.05,-.22,-.58))
	return player.to_global(Vector3(-.05,.34,-.50))

func _exit_tree() -> void:
	if is_instance_valid(_arrow_mesh):_arrow_mesh.free()
	if is_instance_valid(_catch_visual):_catch_visual.queue_free()
	if is_instance_valid(_bobber):
		_bobber.queue_free()
	if is_instance_valid(_line):
		_line.queue_free()
	for arrow in _arrows:
		if is_instance_valid(arrow["node"]):
			arrow["node"].queue_free()
