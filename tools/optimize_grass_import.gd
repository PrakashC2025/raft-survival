@tool
extends EditorScenePostImport
## Post-import optimizer for grass/rs_grass.glb (runs headless and in-editor).
##
## The source asset bundles a full decorative kit (stone, padlock, corner
## cap, plank connector) that the game never uses. This script frees those
## nodes at import time so they are never baked into the .scn or the APK.
##
## Texture sizes are also handled here: every material texture is resized
## (color maps 512, normal/alpha maps 1024) and re-compressed to ETC2 so the
## .scn stays small for mobile.
##
## Edit UNUSED_BASE_NAMES below if the model changes.

## Node base names to drop (suffixes like ".001"/"_001" are stripped before
## matching). Godot also converts glTF dots to underscores ("Plank.Side.
## Connector" imports as "Plank_Side_Connector"), so list both spellings.
const UNUSED_BASE_NAMES := [
	"Stone", "Corner", "Vintage Padlock", "Vintage_Padlock",
	"Plank.Side.Connector", "Plank_Side_Connector",
]

func _post_import(scene: Node) -> Object:
	var doomed: Array[Node] = []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if _is_unused(n.name):
			doomed.append(n)
			continue # do not descend; whole subtree goes
		for c in n.get_children():
			stack.append(c)
	for n in doomed:
		var parent := n.get_parent()
		print("optimize_grass_import: removing unused node '%s'" % n.name)
		parent.remove_child(n)
		n.queue_free()
	return scene

func _is_unused(node_name: StringName) -> bool:
	var regex := RegEx.new()
	regex.compile("[._][0-9]+$")
	var base := regex.sub(String(node_name), "", true)
	return base in UNUSED_BASE_NAMES
