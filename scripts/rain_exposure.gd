extends Node
## Reuse the saved wetness condition; preserve all authored survivor textures.
var actor: Node3D
var _tick := 0.0
var _surfaces: Array[BaseMaterial3D] = []

func _process(delta: float) -> void:
	if not is_instance_valid(actor):actor = get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(actor):return
	_tick += delta
	if _tick < 0.4:return
	_tick = 0.0
	var progress := actor.get_node_or_null("SurvivalProgression")
	if progress == null:return
	_surfaces.clear()
	for path in ["Body/BeachSurvivor", "CamPivot/SpringArm3D/Camera3D/HandPivot"]:
		var root := actor.get_node_or_null(path)
		if root == null:continue
		for child in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if mesh.mesh == null or mesh.is_queued_for_deletion():continue
			for index in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(index) as BaseMaterial3D
				if source == null:continue
				if not source.has_meta("rain_dry_color"):
					var whole_mesh := mesh.material_override==source
					source = source.duplicate() as BaseMaterial3D
					source.set_meta("rain_dry_color", source.albedo_color)
					source.set_meta("rain_dry_roughness", source.roughness)
					if whole_mesh:mesh.material_override=source
					else:mesh.set_surface_override_material(index, source)
				_surfaces.append(source)
	var wet := clampf(float(progress.wetness) / 100.0, 0.0, 1.0)
	for surface in _surfaces:
		var dry: Color = surface.get_meta("rain_dry_color")
		surface.albedo_color = dry * Color(1.0-wet*0.27,1.0-wet*0.24,1.0-wet*0.20,1.0)
		var dry_roughness := float(surface.get_meta("rain_dry_roughness"))
		surface.roughness = lerpf(dry_roughness,minf(dry_roughness,0.24),wet)

func _exit_tree() -> void:
	_surfaces.clear()
	actor=null
