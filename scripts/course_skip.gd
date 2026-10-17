extends RefCounted
## Find clear water on the existing approach; leave a visible sailing leg.
const APPROACH_SECONDS:=10.0
const MIN_APPROACH:=36.0
const MIN_SKIPPED:=24.0

static func approach_distance(vehicle: Node3D) -> float:
	return maxf(MIN_APPROACH,float(vehicle.call("get_navigation_speed"))*APPROACH_SECONDS)

static func aboard(vehicle: Node3D,actor: CharacterBody3D) -> bool:
	if not is_instance_valid(vehicle) or not is_instance_valid(actor) or actor.is_swimming:return false
	if vehicle.is_in_group("player_boat"):
		return vehicle.get("driver")==actor and str(vehicle.get("transition_kind")).is_empty()
	if is_instance_valid(actor.get("boat_vehicle")):return false
	var ray:=PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*.1,actor.global_position+Vector3.DOWN*1.8,1,[actor.get_rid()])
	var hit:=actor.get_world_3d().direct_space_state.intersect_ray(ray)
	var support:=hit.get("collider") as Node
	return support!=null and (support==vehicle or vehicle.is_ancestor_of(support))

static func can_skip(vehicle: Node3D,arrival: float) -> bool:
	return bool(vehicle.call("has_active_course")) and float(vehicle.call("get_course_distance"))>arrival+approach_distance(vehicle)+MIN_SKIPPED

static func landing(vehicle: Node3D,target: Vector3,arrival: float) -> Vector3:
	if not target.is_finite():return Vector3.INF
	var actor:=vehicle.get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not aboard(vehicle,actor):return Vector3.INF
	var outward:=vehicle.global_position-target;outward.y=0
	var distance:=outward.length()
	if distance<=arrival+approach_distance(vehicle)+MIN_SKIPPED:return Vector3.INF
	outward/=distance
	var bounds:=AABB()
	var have_bounds:=false
	var excluded: Array[RID]=[actor.get_rid()]
	if vehicle is CollisionObject3D:excluded.append(vehicle.get_rid())
	for body in vehicle.find_children("*","CollisionObject3D",true,false):
		if not body is Area3D:excluded.append(body.get_rid())
	for collider in vehicle.find_children("*","CollisionShape3D",true,false):
		if collider.disabled or collider.shape==null or collider.get_parent() is Area3D:continue
		var owner_body:=collider.get_parent() as CollisionObject3D
		if owner_body==null or owner_body.collision_layer&1==0:continue
		var relative: Transform3D=vehicle.global_transform.affine_inverse()*collider.global_transform
		var local_bounds: AABB=relative*collider.shape.get_debug_mesh().get_aabb()
		bounds=bounds.merge(local_bounds) if have_bounds else local_bounds;have_bounds=true
	if not have_bounds:return Vector3.INF
	var box:=BoxShape3D.new();box.size=bounds.size+Vector3(1.2,.4,1.2)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=box;query.collision_mask=1;query.exclude=excluded
	var ocean:=vehicle.get_tree().get_first_node_in_group("ocean") as Node3D
	for extra in [0.0,8.0,16.0,28.0,44.0,64.0]:
		var radius:=arrival+approach_distance(vehicle)+float(extra)
		if radius>distance-MIN_SKIPPED:continue
		var at:=target+outward*radius
		at.y=vehicle.global_position.y
		if ocean!=null:
			at.y=float(ocean.call("get_height",at))+.03
			if vehicle.has_method("_deck_crest"):
				vehicle.call("_refresh_deck_samples")
				at.y=float(vehicle.call("_deck_crest",ocean,at,vehicle.global_basis))+float(vehicle.get("float_height"))
		query.transform=Transform3D(vehicle.global_basis,at)*Transform3D(Basis.IDENTITY,bounds.get_center())
		if not vehicle.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():continue
		# Check the first few metres of continued sailing as well as the landing.
		query.motion=-outward*8
		var sweep:=vehicle.get_world_3d().direct_space_state.cast_motion(query)
		if sweep.size()!=2 or sweep[0]<.999:continue
		var clear:=true
		for corner in [Vector2.ZERO,Vector2(-.5,-.5),Vector2(-.5,.5),Vector2(.5,-.5),Vector2(.5,.5)]:
			var probe:=query.transform.origin+vehicle.global_basis*Vector3(corner.x*box.size.x,0,corner.y*box.size.z)
			var sea_y:=float(ocean.call("get_height",probe)) if ocean!=null else 0.0
			var ray:=PhysicsRayQueryParameters3D.create(Vector3(probe.x,sea_y+2,probe.z),Vector3(probe.x,sea_y-1.4,probe.z),1,excluded)
			if not vehicle.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():clear=false;break
		if clear:return at
	return Vector3.INF
