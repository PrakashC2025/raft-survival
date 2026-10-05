extends RefCounted
## Original generated inventory artwork. Regions follow the rendered objects,
## rather than blindly slicing the sheet and clipping long weapons or leaves.
const ATLAS := preload("res://textures/ui/survival_items.png")
const ROPE_LAUNCHER := preload("res://textures/ui/rope_launcher.png")
const REGIONS := {
	"Wood": Rect2(0.000, 0.002, 0.207, 0.176),
	"Rope": Rect2(0.210, 0.014, 0.190, 0.163),
	"Plastic": Rect2(0.424, 0.000, 0.160, 0.178),
	"Metal": Rect2(0.604, 0.014, 0.201, 0.162),
	"Barrel": Rect2(0.843, 0.005, 0.142, 0.175),
	"Stone": Rect2(0.003, 0.183, 0.191, 0.143),
	"Sand": Rect2(0.197, 0.187, 0.208, 0.150),
	"Coconut": Rect2(0.415, 0.183, 0.178, 0.155),
	"Banana": Rect2(0.606, 0.178, 0.187, 0.154),
	"Fish": Rect2(0.805, 0.193, 0.195, 0.135),
	"Cooked Fish": Rect2(0.004, 0.364, 0.219, 0.125),
	"Bow": Rect2(0.214, 0.331, 0.193, 0.185),
	"Arrow": Rect2(0.405, 0.340, 0.205, 0.173),
	"Water": Rect2(0.668, 0.331, 0.092, 0.183),
	"Carrot": Rect2(0.796, 0.307, 0.204, 0.208),
	"Tomato": Rect2(0.014, 0.507, 0.177, 0.145),
	"Potato": Rect2(0.217, 0.513, 0.170, 0.139),
	"Baked Potato": Rect2(0.418, 0.515, 0.175, 0.136),
	"Raw Bird": Rect2(0.601, 0.512, 0.190, 0.142),
	"Roast Bird": Rect2(0.802, 0.520, 0.196, 0.133),
	"Spear": Rect2(0.010, 0.643, 0.205, 0.174),
	"Fishing Rod": Rect2(0.199, 0.640, 0.231, 0.177),
	"Sail Kit": Rect2(0.403, 0.641, 0.202, 0.178),
	"Motor Kit": Rect2(0.626, 0.644, 0.158, 0.176),
	"Life Vest": Rect2(0.827, 0.642, 0.154, 0.171),
	"Carrot Seed": Rect2(0.035, 0.819, 0.140, 0.179),
	"Tomato Seed": Rect2(0.235, 0.819, 0.131, 0.179),
	"Potato Seed": Rect2(0.432, 0.819, 0.137, 0.179),
	"Coconut Seed": Rect2(0.630, 0.819, 0.137, 0.179),
	"Backpack": Rect2(0.808, 0.816, 0.164, 0.182),
}
# A diagonal rod and rolled sail occupy neighboring sheet cells. Tight UV
# silhouettes keep their extremities without sampling the adjacent object.
static var _outlines := {
	"Spear": PackedVector2Array([Vector2(0.010, 0.805), Vector2(0.151, 0.679), Vector2(0.159, 0.660), Vector2(0.204, 0.643), Vector2(0.215, 0.649), Vector2(0.191, 0.687), Vector2(0.050, 0.808), Vector2(0.022, 0.817)]),
	"Fishing Rod": PackedVector2Array([Vector2(0.199, 0.796), Vector2(0.384, 0.665), Vector2(0.430, 0.638), Vector2(0.431, 0.651), Vector2(0.375, 0.697), Vector2(0.362, 0.752), Vector2(0.337, 0.783), Vector2(0.298, 0.807), Vector2(0.264, 0.794), Vector2(0.210, 0.817)]),
	"Sail Kit": PackedVector2Array([Vector2(0.403, 0.796), Vector2(0.419, 0.725), Vector2(0.576, 0.643), Vector2(0.599, 0.638), Vector2(0.609, 0.819), Vector2(0.403, 0.819)]),
}

static func draw(canvas: CanvasItem, item: String, center: Vector2, radius: float) -> bool:
	if item == "Rope Gun":
		var size := ROPE_LAUNCHER.get_size()
		var extent := size * (radius * 2.0 / maxf(size.x, size.y))
		canvas.draw_texture_rect(ROPE_LAUNCHER, Rect2(center - extent * 0.5, extent), false)
		return true
	if not REGIONS.has(item):
		return false
	var normalized: Rect2 = REGIONS[item]
	var pixels := Rect2(normalized.position * ATLAS.get_size(), normalized.size * ATLAS.get_size())
	var extent := pixels.size * (radius * 2.0 / maxf(pixels.size.x, pixels.size.y))
	if _outlines.has(item):
		var uvs: PackedVector2Array = _outlines[item]
		var points := PackedVector2Array()
		for uv in uvs:
			points.append(center - extent * 0.5 + ((uv - normalized.position) / normalized.size) * extent)
		canvas.draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, ATLAS)
		return true
	canvas.draw_texture_rect_region(ATLAS, Rect2(center - extent * 0.5, extent), pixels)
	return true

static func slot_icon(item: String, _slot: int) -> String:
	# Inventory Rope is a material. The permanent launcher has its own control.
	return item
