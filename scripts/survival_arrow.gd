extends Node3D
var velocity := Vector3.ZERO
var shooter: CollisionObject3D
var lifetime := 0.0

func _ready() -> void:
	var visual := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.015
	shaft.bottom_radius = 0.015
	shaft.height = 0.8
	visual.mesh = shaft
	visual.rotation.x = PI / 2.0
	add_child(visual)

func _physics_process(delta: float) -> void:
	lifetime += delta
	if lifetime > 6.0:
		queue_free()
		return
	velocity.y -= 9.8 * delta
	var next := global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, 1)
	if is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		if hit.collider.has_method("hit"):
			hit.collider.hit()
		queue_free()
		return
	global_position = next
	if velocity.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP)
