# Camp crafting pictures

These five transparent 256 x 256 PNGs are original renders of the actual game's equipment. Each has its own scene and image, rather than sharing a generic icon.

| Picture | Geometry source |
| --- | --- |
| bonfire.png | scenes/bonfire.tscn, scripts/campfire.gd |
| rain_collector.png | scenes/rain_collector.tscn, scripts/rain_collector.gd |
| sand_filter.png | scripts/sand_filter_visual.gd |
| cooking_setup.png | scenes/cooking_setup.tscn, scripts/cooking_setup.gd |
| wind_generator.png | scripts/machine_visual.gd, wooden DIY turbine |

The turbine picture uses `tools/render_camp_icons.ps1 -WindOnly`, which invokes `tools/render_food_icons.gd --wind-generator`, then `tools/import_food_icons.ps1 -IconFolder stations`. Its timber mast, pitched blades, salvaged motor, bolts, wiring and battery geometry are original CC0 project work. The mast and blade meshes reuse the project's original photographic timber atlas and rounded timber geometry.

Render with `tools/render_camp_icons.ps1`, which uses `tools/render_food_icons.gd --stations` and isolated game data. Original project geometry, surface shaders and flame artwork are CC0 1.0; no pictures are downloaded. Existing reused materials/assets retain their credits in ASSET_CREDITS.md. Imports are created in a small separate project, not by scanning the junction-based game staging directories.
