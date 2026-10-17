extends "res://scripts/food_pickup.gd"
## One spent inventory spear becomes one recoverable world spear.
var flying:=true
var launch_velocity:=Vector3.ZERO
var damage:=58.0
var actor: CharacterBody3D
var _age:=0.0
var _gravity:=9.8

func _ready() -> void:
	item_name="Spear";amount=1
	super._ready()
	add_to_group("recoverable_spear")
	if flying:remove_from_group("debris");collision_layer=0
	_gravity=2.4 if global_position.y<-.6 else 9.8

func _make_visual() -> Node3D:
	return preload("res://scripts/hunting_visual.gd").spear()

func _physics_process(delta: float) -> void:
	if not flying:return
	_age+=delta
	# Use the launch medium's arc throughout the flight, matching the reticle
	# solution even when a spear thrown from the raft crosses the waterline.
	var gravity_value:=_gravity
	var after:=global_position+launch_velocity*delta+Vector3.DOWN*gravity_value*.5*delta*delta
	launch_velocity+=Vector3.DOWN*gravity_value*delta
	var exclude: Array[RID]=[get_rid()]
	if is_instance_valid(actor):exclude.append(actor.get_rid())
	# A spear already embedded in an animal must not shield it from later hits.
	for other in get_tree().get_nodes_in_group("recoverable_spear"):
		if other!=self:exclude.append(other.get_rid())
	var query:=PhysicsRayQueryParameters3D.create(global_position,after,3,exclude)
	query.collide_with_areas=true;query.hit_from_inside=true
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position=hit.position
		var target:=hit.collider as Node
		if target.has_method("take_projectile_damage"):target.call("take_projectile_damage",damage,actor)
		elif target.has_method("take_damage"):target.call("take_damage",damage,actor)
		settle()
	else:
		global_position=after
		if launch_velocity.length_squared()>.01:look_at(after+launch_velocity,Vector3.RIGHT if absf(launch_velocity.normalized().y)>.98 else Vector3.UP)
		if _age>6.0:settle()

func settle() -> void:
	flying=false;add_to_group("debris");set_deferred("collision_layer",2)
	if is_instance_valid(actor):actor.call("_queue_save")

func _process(delta: float) -> void:
	if not flying:super._process(delta)

func save_state() -> Dictionary:
	return {"p":[global_position.x,global_position.y,global_position.z],"yaw":global_rotation.y}
