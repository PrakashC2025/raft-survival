extends Node3D
## Island beacon MARKER — intentionally has NO visuals and NO light.
## (The old glowing pillar + OmniLight at the island center was removed:
## a survival castaway should not have a lighthouse.) This node exists only
## to register the island's arrival point in the "island_beacon" group so
## island_marker.gd (HUD direction diamond + distance) can find it.
##
## Position is set by island_generator.gd `_place_beacon_and_grass()`.

func _ready() -> void:
	add_to_group("island_beacon")
