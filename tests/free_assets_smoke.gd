extends SceneTree
const SURFACES := preload("res://scripts/salvage_surfaces.gd")
const MATERIALS := preload("res://scripts/object_materials.gd")
const TERRAIN := preload("res://scripts/underwater_terrain.gd")
var checks := 0
var failures := 0
var preview := false
var world: Node3D

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else: failures += 1; push_error("FAIL: " + label)
func frames(count: int) -> void:
	for unused in count: await physics_frame
func photo(label: String) -> void:
	if not preview: return
	await frames(8); await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/GodotProjects/raft-survival/build/free-assets-"+label+".png")==OK,"Rendered " + label)

func _run() -> void:
	if not OS.get_user_data_dir().contains("MobileTests"): quit(2); return
	preview = "--preview" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280,720)
	root.get_node("Stats").set("enabled",false)
	world = Node3D.new(); root.add_child(world)
	for texture: Texture2D in [SURFACES.STEEL_DIFF,SURFACES.STEEL_NORMAL,SURFACES.STEEL_ARM,SURFACES.RUST_DIFF,SURFACES.RUST_NORMAL,SURFACES.RUST_ARM,preload("res://textures/underwater/coast_diff.jpg"),preload("res://textures/underwater/coast_nor_gl.jpg"),preload("res://textures/underwater/coast_arm.jpg")]:
		check(texture.get_size()==Vector2(1024,1024),"Shared CC0 map is bounded to 1K: "+texture.resource_path.get_file())
	var steel := MATERIALS.make(MATERIALS.Kind.METAL,Color(.4,.43,.42),.48,.78)
	var rust := MATERIALS.worn(MATERIALS.Kind.METAL,Color(.4,.43,.42),.8,.7)
	check(steel.get_shader_parameter("photo_diff")==SURFACES.STEEL_DIFF and rust.get_shader_parameter("photo_diff")==SURFACES.RUST_DIFF,"Clean and worn metal select their correct licensed maps")
	check(steel==MATERIALS.make(MATERIALS.Kind.METAL,Color(.4,.43,.42),.48,.78),"Small props reuse material and texture resources")
	var bodies: Array[Node3D] = []
	for item in ["Metal","Plastic","Rope","Soil","Stone","Wood","Barrel","Motor","Screw","Battery","Solar Torch","Walkie Talkie","Tomato"]:
		var body := preload("res://scenes/debris.tscn").instantiate() as RigidBody3D
		body.set("item_name",item); body.freeze=true; body.position=Vector3(bodies.size()*3.0,0,0)
		world.add_child(body); bodies.append(body)
		var visual := body.get("_model_visual") as Node3D
		var bounds: AABB = body.call("_node_local_aabb",visual)
		bounds=visual.transform*bounds
		var collider := body.get_node("CollisionShape3D") as CollisionShape3D
		var shape := collider.shape as BoxShape3D
		check(collider.position.distance_to(bounds.get_center())<.001 and shape.size.distance_to(bounds.size+Vector3.ONE*.02)<.001,"Pickup collider follows visible "+item+" size and offset")
	await frames(3)
	var physics := world.get_world_3d().direct_space_state
	var actual_hits := true
	var outside_hits := false
	for body in bodies:
		var collider := body.get_node("CollisionShape3D") as CollisionShape3D
		var centre := collider.global_position
		var ray := PhysicsRayQueryParameters3D.create(centre+Vector3.UP*2,centre-Vector3.UP*2,2)
		var hit := physics.intersect_ray(ray)
		actual_hits=actual_hits and not hit.is_empty() and hit.collider==body
		var outside := centre+Vector3.RIGHT*((collider.shape as BoxShape3D).size.x*.5+.04)
		ray=PhysicsRayQueryParameters3D.create(outside+Vector3.UP*2,outside-Vector3.UP*2,2)
		outside_hits=outside_hits or not physics.intersect_ray(ray).is_empty()
	check(actual_hits,"Real pickup rays still find every resized salvage body")
	check(not outside_hits,"Pickup rays reject the empty space outside fitted colliders")
	check(bodies[0].get_node("CollisionShape3D").shape!=bodies[1].get_node("CollisionShape3D").shape,"Resizing one item cannot mutate another item's collider")
	var avatar := preload("res://models/mixamo_survivor.glb").instantiate() as Node3D
	world.add_child(avatar)
	var rig := avatar.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var animator := avatar.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
	var yaw_valid := true
	for name_value in ["TurnLeft","TurnRight"]:
		var found := false
		for clip_name in animator.get_animation_list():
			if not str(clip_name).ends_with(name_value): continue
			var clip := animator.get_animation(clip_name)
			for track in clip.get_track_count():
				if clip.track_get_type(track)!=Animation.TYPE_ROTATION_3D or str(clip.track_get_path(track).get_subname(0))!="Hips": continue
				found=true
				for key in clip.track_get_key_count(track):
					var rotation_value: Quaternion=clip.track_get_key_value(track,key)
					var relative := rotation_value*rig.get_bone_rest(rig.find_bone("Hips")).basis.get_rotation_quaternion().inverse()
					yaw_valid=yaw_valid and absf(relative.y)<.001
		yaw_valid=yaw_valid and found
	check(yaw_valid,"Both imported turn clips leave actor yaw under gameplay control")
	check(rig.find_bone("Ring2.R")>=0 and rig.find_bone("Ring2.L")>=0,"Both new human ring fingers are available to the contact rig")
	avatar.queue_free()
	if preview: await _render()
	world.queue_free(); await frames(8)
	print("FREE ASSETS: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)

func _render() -> void:
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(.10,.22,.30)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color(.75,.83,.94)
	environment.environment.ambient_light_energy=.7
	world.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,-35,0); sun.light_energy=1.5; world.add_child(sun)
	var camera := Camera3D.new(); camera.fov=40; world.add_child(camera); camera.current=true
	# Actual debris models at their gameplay scale, grouped for a material close-up.
	for index in 5:
		var body := world.get_child(index) as RigidBody3D
		body.position=Vector3((index-2)*.65,.18,0)
	camera.position=Vector3(.2,1.65,2.8); camera.look_at(Vector3(0,.05,0))
	for item in world.get_children():
		if item is RigidBody3D: item.call("_set_visual_alpha",1.0)
	await photo("salvage")
	for item in world.get_children():
		if item is RigidBody3D: item.hide()
	var turbine := preload("res://scripts/machine_visual.gd").create("WindGenerator")
	world.add_child(turbine)
	camera.position=Vector3(3,2.2,4.5);camera.look_at(Vector3(0,1.0,0))
	await photo("equipment")
	turbine.queue_free(); await frames(2)
	var tile := MeshInstance3D.new();tile.mesh=TERRAIN.mesh_at(Vector2i(3,1));tile.position=Vector3(144,0,48)
	var sand := ShaderMaterial.new();sand.shader=preload("res://shaders/undersea_surface.gdshader")
	sand.set_shader_parameter("surface_texture",preload("res://textures/underwater/coast_diff.jpg"))
	sand.set_shader_parameter("surface_normal",preload("res://textures/underwater/coast_nor_gl.jpg"))
	sand.set_shader_parameter("surface_arm",preload("res://textures/underwater/coast_arm.jpg"))
	sand.set_shader_parameter("surface_scale",1.0/12.0); tile.material_override=sand;world.add_child(tile)
	var point:=Vector2(152,60);var level:=TERRAIN.surface_height(point)
	camera.position=Vector3(point.x,level+2.8,point.y);camera.look_at(Vector3(point.x,level,point.y-4))
	await photo("seabed")
