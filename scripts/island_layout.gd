extends RefCounted
## Legacy saves retain their resource coordinates; new voyages have open sea.
const POSITIONS := {"Island": Vector2(280,-560), "ReefIsle": Vector2(-820,570), "DriftwoodCay": Vector2(-1000,-820), "FarCove": Vector2(1380,950)}
static func version(meta: Dictionary) -> int:
	return int(meta.get("island_layout",1 if meta.is_empty() else 0))
static func apply(island: Node3D, meta: Dictionary) -> void:
	if version(meta) == 1 and POSITIONS.has(str(island.name)):
		var point: Vector2 = POSITIONS[str(island.name)]
		island.position.x = point.x
		island.position.z = point.y
