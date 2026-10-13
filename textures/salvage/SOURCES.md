# Free coastal and salvage surface refresh — 2026-10-13

All three material sets below use **CC0 1.0**, permitting commercial use,
modification and redistribution. No account, email, purchase or runtime service
is required. Licenses: [ambientCG](https://docs.ambientcg.com/license/),
[Poly Haven](https://polyhaven.com/license),
[CC0 legal text](https://creativecommons.org/publicdomain/zero/1.0/legalcode).

- [Metal 038](https://ambientcg.com/view?id=Metal038), ambientCG / Lennart Demes:
  scratched steel for tool heads, screws and motor parts. Public source ZIP:
  `https://ambientcg.com/get?file=Metal038_1K-JPG.zip`.
  `steel_diff.jpg`, `steel_nor_gl.jpg` use the supplied Color and NormalGL maps.
  `steel_arm.jpg` packs white AO, supplied Roughness and Metalness channels.
- [Rusty Metal 02](https://polyhaven.com/a/rusty_metal_02), Rob Tuytel:
  weathered painted steel for floating Metal, barrel hoops and worn equipment.
  Retained unchanged as `rust_diff.jpg`, `rust_nor_gl.jpg`, `rust_arm.jpg`.
- [Coast Sand 01](https://polyhaven.com/a/coast_sand_01), Rob Tuytel:
  pebble-strewn damp coastal sand for the submerged seabed, retained unchanged
  at `../underwater/coast_{diff,nor_gl,arm}.jpg`. Visible grain repeats every 12m;
  the asset's original photographed tile represents about 15m.

Poly Haven public source pattern:
`https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/<asset>/<asset>_<map>_1k.jpg`.

All nine retained maps are 1024x1024. They share cached resources with mipmaps,
VRAM compression and Android ASTC variants; no extra geometry, displacement,
particles, lights or shadow passes are added. Original downloads remain in the
ignored preparation directory, outside exports. SHA256s and source links for
every retained map are in `source_manifest.json`. Offline preparation uses
`tools/prepare_free_surfaces.py` and `tools/configure_free_surface_imports.py`.
Object-space projection samples one diffuse, normal and packed ARM map per
metal fragment, reconstructing the normal's blue channel for compressed maps.
Other authored model textures retain their own source licenses.
