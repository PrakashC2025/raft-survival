# Island surface assets

Downloaded unchanged from Poly Haven on 2026-10-07. Both material sets are
[CC0](https://polyhaven.com/license), free for redistribution and commercial games.

- [Rock Boulder Cracked](https://polyhaven.com/a/rock_boulder_cracked):
  photographed by Dimitrios Savva, processed by Dario Barresi.
  `rock_diff.jpg`, `rock_nor_gl.jpg`, `rock_arm.jpg`.
- [Aerial Beach 01](https://polyhaven.com/a/aerial_beach_01): Rob Tuytel.
  `sand_diff.jpg`, `sand_nor_gl.jpg`, `sand_arm.jpg`.

Original 1024-square JPG downloads: `https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/<asset>/<asset>_<map>_1k.jpg`.
Maps are diffuse, OpenGL normal, and packed AO/roughness/metalness.
The retained Godot imports use mipmaps, 1024 maximum size, and high quality
BPTC/ASTC compression; normal maps explicitly enable normal compression.

Verified MD5 fingerprints:

| File | MD5 |
| --- | --- |
| rock_diff.jpg | 2eee29ef1257ce79569e4be0b76cd1ad |
| rock_nor_gl.jpg | 1185717651f6fa2db0face12425d0a74 |
| rock_arm.jpg | 1df2fc6b4e792f7101831e7f87f920c8 |
| sand_diff.jpg | 0ec8483b18d960f2152dae2a64806b3d |
| sand_nor_gl.jpg | f6810f845aefe51dccf4c4ac6f2ab05a |
| sand_arm.jpg | a0c97e3288d97cb7127fe589ca7bdcd8 |

The weathered ridge and rounded shoreline boulder geometry are original project
assets/code, shared across islands. Added trees reuse original coastal-tree
geometry/atlas; supplied coconut palms and grass retain their existing individual
licenses in ASSET_CREDITS.md. No paid assets were added.

The ocean normal texture is original procedural FastNoiseLite content, generated
once as a shared 256-square seamless NoiseTexture2D. Each island contributes one
32-square floating-point terrain-height mask for approximate shallows and foam.
These are rendering approximations, not transparent water or a simulation of surf.
