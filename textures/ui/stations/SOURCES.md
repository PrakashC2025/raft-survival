# Camp crafting pictures

These nine transparent PNGs are original renders of the actual game's equipment. The original four camp pictures are 256 x 256; the updated turbine, net, LED and torch pictures are 320 x 320; the seed tray is 160 x 160. Each has its own scene and image, rather than sharing a generic icon.

| Picture | Geometry source |
| --- | --- |
| bonfire.png | scenes/bonfire.tscn, scripts/campfire.gd |
| rain_collector.png | scenes/rain_collector.tscn, scripts/rain_collector.gd |
| sand_filter.png | scripts/sand_filter_visual.gd |
| cooking_setup.png | scenes/cooking_setup.tscn, scripts/cooking_setup.gd |
| wind_generator.png | scripts/machine_visual.gd, wooden DIY turbine |
| fishing_net.png | scripts/fishing_net_visual.gd, timber booms and weighted woven rope basket |
| salvaged_led.png | scripts/machine_visual.gd, cracked work light and exposed board |
| hand_torch.png | scripts/torch_visual.gd, photographic timber shaft, charred rag and flame shader |
| seed_drying_tray.png | scripts/seed_drying_tray.gd, timber tray and dried garden seeds; 160 x 160 |

The seed tray picture uses the garden-cycle native preview. Its preparation and shared-material provenance are recorded in `textures/ui/garden/SOURCES.md`; the eight preceding camp pictures retain their existing render instructions below.

The latest turbine, net, LED and torch pictures use `tools/preview_survival_update.ps1 -TestScript salvage_power_net_smoke.gd -SilentAudio`, which renders their actual models into transparent SubViewports with isolated saved data, then `tools/import_food_icons.ps1 -IconFolder stations`. The older turbine-only renderer remains available as `tools/render_camp_icons.ps1 -WindOnly`, invoking `tools/render_food_icons.gd --wind-generator`. The equipment geometry is original CC0 project work. Generator and torch timber reuse the project's original photographic timber atlas and rounded timber geometry. Metal, cloth and flame shaders retain the project's existing credits.

Render with `tools/render_camp_icons.ps1`, which uses `tools/render_food_icons.gd --stations` and isolated game data. Original project geometry, surface shaders and flame artwork are CC0 1.0; no pictures are downloaded. Existing reused materials/assets retain their credits in ASSET_CREDITS.md. Imports are created in a small separate project, not by scanning the junction-based game staging directories.
