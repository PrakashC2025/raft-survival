extends Node
## Bow charge/release shares the owned HAND action on touch and E on desktop.
const CONTACT_AUDIO:=preload("res://scripts/contact_audio.gd")
const FISH_REEL_DURATION := 0.6
var player: CharacterBody3D
var draw_time := 0.0
var drawing := false
var _draw_item := ""
var aiming := false
var _normal_fov := 75.0
var cooldown := 0.0
var _arrows: Array[Dictionary] = []
var _arrow_mesh: Node3D
var _arrow_material: StandardMaterial3D
var _bobber: MeshInstance3D
var _line: MeshInstance3D
var _cast_target := Vector3.ZERO
var _cast_age := 0.0
var _cast_start := Vector3.ZERO
var _catch_visual: Node3D
var _cast_clock := 0.0
var _cast_splash_played:=false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_parent() as CharacterBody3D
	_arrow_mesh = preload("res://scripts/survival_arrow_visual.gd").create()
	_arrow_material = StandardMaterial3D.new()
	_arrow_material.albedo_color = Color(0.40, 0.24, 0.10)
	_arrow_material.roughness = 0.9
	call_deferred("_restore_spears")


func begin_draw() -> void:
	var salvage:=player.get_node_or_null("OceanSalvage")
	if salvage!=null and (salvage.busy() or salvage.aimed_cache()!=null):return
	if cooldown > 0.0 or drawing:
		return
	var cargo:=player.get_node_or_null("HuntingCargo")
	if cargo!=null and (cargo.busy() or is_instance_valid(cargo.held)):return
	if player.active_item not in ["Bow","Spear"]:return
	if player.active_item=="Spear":
		var tools:=player.get_node("SurvivalTools")
		if tools.cooldown>0 or not tools.pending.is_empty() or tools.blocked():return
	if not Inventory.has("Spear" if player.active_item=="Spear" else "Arrow", 1):
		player.call("_hud_toast", "CRAFT ARROWS FIRST")
		return
	drawing = true
	draw_time = 0.0
	_draw_item=player.active_item

func cancel_draw() -> void:
	drawing = false
	draw_time = 0.0
	_draw_item=""

func get_draw_fraction() -> float:
	return clampf(draw_time / 1.1, 0.0, 1.0) if drawing else 0.0

func toggle_aim() -> void:
	var hud := player.get_node_or_null("CanvasLayer/SurvivalHUD")
	if player.get("active_item") not in ["Bow","Spear"] or player.get("build_mode") or get_tree().paused \
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
	var blocked := get_tree().paused or is_instance_valid(player.get("boat_vehicle")) or (hud != null and bool(hud.call("gameplay_input_blocked")))
	var cargo:=player.get_node_or_null("HuntingCargo")
	blocked=blocked or (cargo!=null and (cargo.busy() or is_instance_valid(cargo.held)))
	var salvage:=player.get_node_or_null("OceanSalvage")
	blocked=blocked or (salvage!=null and (salvage.busy() or salvage.aimed_cache()!=null))
	if blocked or player.get("active_item") not in ["Bow","Spear"] or player.get("build_mode"):
		set_aiming(false)
	if drawing:
		if player.get("active_item") not in ["Bow","Spear"] or (not _draw_item.is_empty() and player.active_item!=_draw_item) or blocked or player.get("build_mode"):
			cancel_draw()
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
			var end := node.global_position + velocity * delta + Vector3.DOWN * 4.9 * delta * delta
			velocity += Vector3.DOWN * 9.8 * delta
			arrow["velocity"] = velocity
			var query := PhysicsRayQueryParameters3D.create(node.global_position, end, 3, [player.get_rid()])
			query.collide_with_areas = true
			query.hit_from_inside = true
			var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				var target: Node = hit["collider"]
				if target.is_in_group("huntable_bird"):
					var flock: Node = target.get_meta("flock")
					if flock.call("hit_bird", int(target.get_meta("bird_index"))):
						player.call("_hud_toast", "BIRD HIT  •  COLLECT IT WHERE IT LANDS")
				elif target.has_method("take_projectile_damage"):
					target.call("take_projectile_damage",30.0,player)
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
	_draw_item=""
	if player.active_item=="Spear":
		var tools:=player.get_node("SurvivalTools")
		if fraction<.18 and tools.can_use():tools.use();return
		_throw_spear(fraction);return
	if cooldown>0 or player.get("active_item")!="Bow" or Stats.health<=0 or _arrows.size() >= 12:
		return
	if not Inventory.try_exchange({"Arrow":1},{}):return
	cooldown=.55
	player.call("play_action","bow",0.45)
	var root := Node3D.new()
	root.name = "FlyingArrow"
	root.add_child(_arrow_mesh.duplicate())
	get_tree().current_scene.add_child(root)
	var shot:=shot_solution(fraction)
	root.global_position = shot.origin
	_arrows.append({"node": root, "velocity": shot.velocity, "life": 4.0})
	player.call("_queue_save")

func shot_solution(fraction: float) -> Dictionary:
	var camera:=player.camera as Camera3D
	var screen:=camera.get_viewport().get_visible_rect().size*.5
	var reticle:=player.get_node_or_null("CanvasLayer/Crosshair")
	if reticle!=null:screen.y+=float(reticle.get("aim_vertical_offset"))
	var from:=camera.project_ray_origin(screen)
	var direction:=camera.project_ray_normal(screen)
	var origin:=camera.to_global(Vector3(.14,-.12,-.55)) if player.cam_mode==0 else player.to_global(Vector3(.27,.32,-.5))
	var query:=PhysicsRayQueryParameters3D.create(from,from+direction*70.0,3,[player.get_rid()]);query.collide_with_areas=true
	var hit:=player.get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3=hit.position if not hit.is_empty() else from+direction*35.0
	var bird: Area3D=null
	var best:=INF
	for candidate in get_tree().get_nodes_in_group("huntable_bird"):
		var area:=candidate as Area3D
		if area==null or area.collision_layer==0 or not area.is_visible_in_tree():continue
		var offset:=area.global_position-from
		var along:=offset.dot(direction)
		if along<1 or along>60:continue
		var error: float=(offset-direction*along).length()
		if error>maxf(.38,along*.012) or error>=best:continue
		var clear:=PhysicsRayQueryParameters3D.create(from,area.global_position,1,[player.get_rid()])
		if not player.get_world_3d().direct_space_state.intersect_ray(clear).is_empty():continue
		best=error;bird=area
	var spear: bool=player.active_item=="Spear"
	var submerged: bool=origin.y<-.6
	var speed:=lerpf(16.0,26.0,fraction) if spear else lerpf(26.0,48.0,fraction)
	if spear and bird==null:
		best=INF
		for candidate in get_tree().get_nodes_in_group("huntable_animal"):
			var animal:=candidate as Node3D
			if animal==null or not animal.is_visible_in_tree() or animal.collision_layer==0:continue
			var centre:=animal.global_position+Vector3.UP*(.25 if animal.get("species") in ["Boar","Crocodile"] else 0.0)
			var along: float=(centre-from).dot(direction)
			var error: float=((centre-from)-direction*along).length()
			if along<1 or along>40 or error>maxf(.45,along*.018) or error>=best:continue
			var clear:=PhysicsRayQueryParameters3D.create(from,centre,1,[player.get_rid()])
			if not player.get_world_3d().direct_space_state.intersect_ray(clear).is_empty():continue
			best=error;target=centre
			if animal is CharacterBody3D:target+=(animal as CharacterBody3D).velocity*minf(origin.distance_to(target)/speed,1.5)
	if bird!=null:
		target=bird.global_position
		var flock:=bird.get_meta("flock") as Node
		if flock!=null and flock.has_method("bird_velocity"):
			target+=Vector3(flock.call("bird_velocity",int(bird.get_meta("bird_index"))))*minf(origin.distance_to(target)/speed,1.5)
	return {"origin":origin,"target":target,"velocity":ballistic_velocity(target-origin,speed,2.4 if spear and submerged else 9.8)}

static func ballistic_velocity(offset: Vector3,speed: float,gravity_value: float=9.8) -> Vector3:
	var flat:=Vector3(offset.x,0,offset.z)
	var distance_value:=flat.length()
	if distance_value<.01:return offset.normalized()*speed
	var squared:=speed*speed
	var discriminant:=squared*squared-gravity_value*(gravity_value*distance_value*distance_value+2.0*offset.y*squared)
	if discriminant<0:return offset.normalized()*speed
	var angle:=atan((squared-sqrt(discriminant))/(gravity_value*distance_value))
	return flat.normalized()*cos(angle)*speed+Vector3.UP*sin(angle)*speed

func _throw_spear(fraction: float) -> void:
	if cooldown>0 or Stats.health<=0 or save_spears().size()>=24:return
	var shot:=shot_solution(fraction)
	if not Inventory.try_exchange({"Spear":1},{}):return
	var spear:=preload("res://scripts/thrown_spear.gd").new()
	spear.actor=player;spear.launch_velocity=shot.velocity;spear.damage=lerpf(42.0,65.0,fraction)
	spear.position=shot.origin;get_tree().current_scene.add_child(spear)
	if spear.launch_velocity.length_squared()>.01:spear.look_at(spear.global_position+spear.launch_velocity)
	cooldown=.85;player.call("play_action","throw_spear",.55)
	player.call("_queue_save")

func save_spears() -> Array:
	var result: Array=[]
	for spear in get_tree().get_nodes_in_group("recoverable_spear"):
		if not spear.is_queued_for_deletion() and not spear.collected:result.append(spear.save_state())
	return result

func _restore_spears() -> void:
	for record in Inventory.loaded_meta.get("thrown_spears",[]).slice(0,24):
		if not record is Dictionary or not record.get("p") is Array or record.p.size()!=3:continue
		var at:=Vector3(float(record.p[0]),float(record.p[1]),float(record.p[2]))
		if not at.is_finite() or at.length()>200000:continue
		var spear:=preload("res://scripts/thrown_spear.gd").new();spear.flying=false;spear.actor=player
		spear.position=at;spear.rotation.y=float(record.get("yaw",0));get_tree().current_scene.add_child(spear)

func show_cast(target: Vector3) -> void:
	_cast_target = target
	_cast_age=0.0
	_cast_splash_played=false
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
	elif not _cast_splash_played:
		_cast_splash_played=true
		player.call("play_world_sfx",CONTACT_AUDIO.pick_action("water"),-13.0,at)
	var remaining := float(player.get("_fishing_time_remaining"))
	if remaining<FISH_REEL_DURATION or pending:
		var hook := catch_position()+Vector3.UP*.18
		at=at.lerp(hook,smoothstep(0.0,1.0,1.0-remaining/FISH_REEL_DURATION)) if not pending else hook
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
