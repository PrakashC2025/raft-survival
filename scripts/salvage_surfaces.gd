extends RefCounted
## Public CC0 maps shared by all salvage; no runtime downloads or per-item copies.
const STEEL_DIFF := preload("res://textures/salvage/steel_diff.jpg")
const STEEL_NORMAL := preload("res://textures/salvage/steel_nor_gl.jpg")
const STEEL_ARM := preload("res://textures/salvage/steel_arm.jpg")
const RUST_DIFF := preload("res://textures/salvage/rust_diff.jpg")
const RUST_NORMAL := preload("res://textures/salvage/rust_nor_gl.jpg")
const RUST_ARM := preload("res://textures/salvage/rust_arm.jpg")

static func apply(material: ShaderMaterial, rusted: bool) -> void:
	material.set_shader_parameter("photo_surface", true)
	material.set_shader_parameter("photo_diff", RUST_DIFF if rusted else STEEL_DIFF)
	material.set_shader_parameter("photo_normal", RUST_NORMAL if rusted else STEEL_NORMAL)
	material.set_shader_parameter("photo_arm", RUST_ARM if rusted else STEEL_ARM)
	material.set_shader_parameter("photo_scale", 2.0 if rusted else 3.0)
