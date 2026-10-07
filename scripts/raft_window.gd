extends StaticBody3D
## Permanent open timber frame. Old shutter state is accepted when loading.
const TIMBER := preload("res://scripts/construction_visual.gd")

func _ready() -> void:
	for part in find_children("*", "MeshInstance3D", true, false):
		if part.mesh is BoxMesh:
			part.mesh = TIMBER.rounded_timber(part.mesh.size, 2.0)
	$Bottom.mesh = TIMBER.panel(Vector3(2,1.18,0.22),true,2.0,5)
	for side in [$Left,$Right]:
		side.mesh=TIMBER.panel(Vector3(0.48,0.87,0.24),true,2.0,2)
	for x in [-0.84,0.84]:
		for y in [-0.82,1.025]:
			var binding := MeshInstance3D.new()
			binding.mesh = TIMBER.rope_loop(Vector2(0.13,0.15),1)
			binding.position = Vector3(x,y,0)
			add_child(binding)

func save_survival_state() -> Dictionary:
	return {"open": true}

func restore_survival_state(_data: Dictionary) -> void:
	pass # Legacy windows restore as open frames, without a blocking sash.
