# Survival update — source delivery and testing

The existing game is extended in place. Full working code is saved in the files listed below. The owner builds the APK manually. Normal player saves and the once-per-save 2,000-material testing grant are preserved.

Loading/stutter follow-up: model/assets/scripts now prepare sequentially in the background; Continue restores its buildings/crops/socket links across render frames with input and partial-save protection. Shared roof scans, dry-weather rain scanning, crop snapshots and bounded grass setup reduce repeated work during movement. Ocean wave evaluation and deck probes are batched without changing the sampled waves/freeboard; swimming-climb searches reject distant decks cheaply and hidden desktop touch controls skip mode scans. Fresh phones start at 30 FPS; existing preferences are preserved. Details and profiling instructions are in `GAME_GUIDE.md` under Loading and movement stalls.

Edit/control follow-up: moved pieces use the regular placement rules, with original-position saves/cancel and one-tile roof relocation. Assembly keeps its original raft-relative aim and actual support. Construction shows hammer plus timber and restores the prior held item afterward. The permanent rope gun occupies its own first quick slot; CAST is contextual. Larger touch targets and a visible joystick improve phone controls. Adult coconut palms now stand 6–8.4 m; crop growth/fruit ripeness survive old saves. Potato, tomato and banana have original shared geometry, procedural skin and matching rendered icons. See `GAME_GUIDE.md` for details.

Follow-up files: `scripts/produce_visual.gd`, `shaders/produce_skin.gdshader`, `textures/ui/advanced_potato.png`, `advanced_tomato.png`, `advanced_banana.png`, `tests/edit_tree_smoke.gd`, and `tools/verify_edit_tree.ps1`; changes also touch Player, SmartRoof, RoofOpening, SurvivalAction, SurvivalHUD, MobileControls, PlantData/PlantInstance, VegetationVisual, IslandSetup, FoodPickup, ItemArt and menu warm paths. Manual checks: move and replace each piece, cancel after sailing, assemble while turning, switch camera/build modes with food selected, tap the first gun slot, and compare seedlings/adult palms beside the survivor.

Soil/control/debris follow-up also changes Inventory, Debris, DebrisSpawner, ResourceVisual, UiIcons and RopeSystem, and adds `shaders/debris_weathered.gdshader`. Soil appears randomly in floating sacks and remains gatherable on higher island ground. Optional `testing_soil_granted` grants 2,000 Soil once to new/existing saves without refilling other supplies. A large left-side contextual action shows COLLECT/OPEN/CLOSE/EAT/etc. with meaningful pictograms; unready targets hide it. Mobile RECALL is removed and CAST hides during automatic return. Accepted pickups queue icon/name/count messages one by one; rope stacks/overflow retain all unaccepted items. Gravity is 9.81 m/s², with automatic reeling poses and existing swept collision. All floating salvage receives shared detailed geometry and weathered materials; logs/barrels reuse the original timber atlas and starter seeds look like produce. Test manual pickup/reeling with a nearly full bag, spending Soil then continuing, and collection labels while switching targets.

Follow-up tools also include `tools/verify_controls_debris.ps1` and `tools/import_produce_icons.ps1`. The latter imports only the three rendered produce PNGs and preserves their resource paths for source checks; an editor import performs the same normal asset preparation.

Final follow-up validation: 250 checks passed in the final six-suite source run; the earlier eight-suite construction/control run passed 399 checks, with overlap (487 distinct checks across 11 suites). The final Mobile/D3D12 desktop preview passed 110 checks without script/engine errors. Controls, construction hands, produce, every floating salvage model and coconut/player scale screenshots were inspected. Floating object waterlines now partially submerge the objects. No APK export or real-phone test was performed; normal saves remain untouched.

## Current controls and behavior

1. **Medkit:** craft for 4 Rope + 2 Plastic or find an island medical cache. Equip/Use from hotbar or bag. Stay still for 1.5 seconds: one heals 50 of 100 maximum health, clamped. Movement, damage, item change or a conflicting panel cancels without spending. Icon/count, hand pose, sound and progress are connected.
2. **Water cans:** craft Can for 1 Metal. Aim down at reachable, unobstructed ocean and Use for two seconds. Dirty Water Can gives +12 thirst/-8 health if drunk. Aim at SandFilter/WaterPurifier/ElectricPurifier with dirty water, open the prompt and INSERT & FILTER. Five seconds of insertion/dripping progress produces Clean Water Can, which restores thirst fully. Drinking or cooking with it returns Can. Existing Water items/machine generation remain compatible.
3. **Cooking:** aim at a lit Bonfire or Cooking Setup, then CLICK TO COOK. All 15 recipes show HAVE / NEED colors, duration and effects. Wood refuels the fire. Cooking Setup costs 8 Wood + 4 Stone + 2 Metal. Ingredients are spent once; jobs pause without fire and resume after save/load. Finished meals enter inventory or a collectible overflow bag. Four extra dishes are **Roasted Carrot, Cooked Onion, Tropical Fruit Stew and Root Vegetable Soup**; existing bird/meat/crab meals are also retained.
4. **Stats:** hunger .10/s, thirst .16/s, health .003/s in the active game. Sprint multiplies by 1.6, swimming by 2. Empty hunger or thirst adds 1.5 health damage/s. Percent displays interpolate, low warnings blink, and a pool of four labels shows meaningful deltas. Modal panels hide transient popups. `scripts/food_rules.gd` is the only food-effects/recipe table: raw food gives small nutrition and health damage; cooked meals restore substantially more and heal. Soup is +45 hunger/+30 thirst/+15 health. Baked Potato remains a legacy alias.
5. **Storage/death:** craft/place Storage Box for 6 Wood + 2 Rope + 1 Metal on a supported raft/deck. It owns 24 saved slots. Drag or tap stacks between its grid and all 30 player slots. Touch keeps one owning finger. Back/Close/distance exits. Death empties backpack/hotbar into a floating bag at the death position; placed storage stays safe. Nonempty boxes and unfinished stations cannot be dismantled. Respawning does not refill testing supplies.
6. **Burning Torch:** craft Torch for 2 Wood + 1 Rope. Aim at a lit sheltered Bonfire/Cooking Setup to LIGHT TORCH: one becomes and equips Burning Torch. It has animated flame geometry, hand motion and real warm light. Aim at a solid wall to PLACE TORCH with a green/red ghost. Mount/take transfers the item and deadline. Next dawn (06:00 on the monotonic survival clock) converts portable Burning Torch to Torch; mounted fire turns off and returns Torch when taken. Rain/swimming extinguish too. Relight at a fire. Old saved fuel migrates to next dawn. Unlit held torches emit no light.
7. **Validation/performance:** SurvivalServices validates ownership, equipment, range, modal state, station validity, recipes and storage indices before inventory transactions. Outputs commit once; full inventories preserve inputs or drop finished rewards. Saves retain authenticated AES envelope `RAFT-AES256-1`, payload version 1, atomic replacement and backup recovery. Validation rejects unsupported versions, bad nested types, nonfinite numbers and oversized/deep records before restoration. Stats/stacks clamp. This local game has no multiplayer authority server. Fixed flame/drip geometry is reused, progress/station text is sampled at 10Hz, tool visual references are cached, and built fires/wall torches/electric lamps share six nearest lights plus held light/flashlight. No additional per-frame particle spawning is introduced.

### Island plants and supplied electronics

All islands use the supplied lowpoly plant kit: eight shared MultiMesh variants, up to 44 added plants and 64 total saved records including original palms/grove trees. Small wild plants yield 1 Rope; trees take four hits and give 4 Wood. Full bags preserve the final plant/tree. Clear the complete crop footprint before planting: 1.15m for small plants, 2m around trees. Wild plants cannot replace a growing cultivated crop. Small plants wait 180 active seconds, then grow over 75; trees wait 360, then grow over 180. Harvested empty soil can regrow wild plants again. One 64-square mask clears decorative grass. Battery Saver preserves visible interactive trunks at 55m; decorative grass retains its separate adaptive budget.

The supplied electronic models provide Solar Torch (2 Metal + 2 Plastic), Binoculars (2 Metal + 3 Plastic), Walkie Talkie (4 Metal + 3 Plastic + 1 Rope). Battery costs 1 Metal + 1 Plastic. Use toggles flashlight, zooms binoculars to 18 degrees, or powers/transmits the radio. POWER, OPEN COVER, REMOVE and INSERT/REPLACE controls accompany the visible radio screen/side key and 1.8-second cover/cell/hand animation. Radio on lasts 30 game days (43,200 active seconds with the default 24-minute day); off saves power. Flashlight battery lasts 1,800 active seconds. Direct dry sunlight on an exposed held panel powers and fully charges it in 240 active seconds. Backpacks, roofs, rain, night and swimming prevent charging. Full removed cells return Battery; partial/spent cells return Used Battery, which reinserts empty for solar charging. Radio sends/receives original beeps/static with a local simulated island/location reply; it is not network voice chat. Continue restores charge/power without refilling.

Carrot and onion use the owner's supplied Blender geometry through prepared GLBs; banana uses the supplied FBX. Potato, carrot, onion, tomato, coconut and banana remain edible/replantable produce. Pots require real roof/foundation tops and reject ocean; direct island agriculture needs no pot. Roof rain masks, rotated-foundation red previews, one continuous stair opening, crafting confirmation, larger Use and clear mobile air are retained.

## Architecture and saved state

Player owns SurvivalServices and its UI, PortableElectronics, SurvivalProgression and SurvivalAction. Inventory remains the authoritative 30-slot inventory and recipe/transaction system. Stats remains the stat autoload. StorageBox extends CargoCrate; CookingSetup extends Campfire; GroundPlot extends Planter. IslandLandscape waits for terrain readiness before preparing WildPlants in bounded 16-ray batches. New build indexes append; earlier indexes are unchanged.

Optional payload fields: `survival_services: {version:1,drops:[{p,contents}]}`, `electronics`, `wild_plants`, `progression.torch_end_time`, built `survival.contents`, built `station_job`, and the earlier `ground_crops`. Missing fields preserve old-save behavior. Station jobs validate recipe names/durations; storage validates and clamps each entry; wild records use finite bounded positions and whitelisted existing tree paths. No tests access the owner's ordinary `user://` directory.

## File manifest

These are the source files changed/created across this continued update, including the preceding shelter/farming fixes requested in this chat. Raw owner assets are inputs and remain intact. Generated Godot import caches, isolated test directories, logs and screenshots are verification outputs, not source replacements.

### New gameplay files

- `scripts/food_rules.gd` — raw and cooked values, ingredients, times.
- `scripts/survival_services.gd` — validated commands, actions, transfers, death/overflow drops, light budget.
- `scripts/survival_service_ui.gd` — cooking/filter/storage panels, progress, pooled delta labels.
- `scripts/storage_slot_ui.gd` — mouse/touch drag/drop and tap transfer.
- `scripts/storage_box.gd`, `scenes/storage_box.tscn` — saved 24-slot box/30-slot loot bag.
- `scripts/cooking_setup.gd`, `scenes/cooking_setup.tscn` — extended campfire station.
- `scripts/station_job.gd` — saved timed station jobs and reused can/drips.
- `scripts/survival_item_visual.gd` — medkit/can/meal props.
- `scripts/torch_cycle.gd` — shared next-dawn calculation.
- `scripts/island_wild_plants.gd`, `scripts/wild_plant_target.gd` — interactive kit plants and saved clearings.
- `scripts/portable_electronics.gd`, `scripts/electronics_visual.gd` — portable tools, batteries, power, screen and controls.
- `scripts/ground_plot.gd` — pot-free island crops.
- `scripts/roof_opening.gd` — one derived stair opening with matching collision.
- `scripts/frame_work_budget.gd` — render-frame setup budgets with a shared interactive lane and a fair 0.5 ms allowance for each grass field.
- Godot-generated script identity files: `scripts/cooking_setup.gd.uid`, `electronics_visual.gd.uid`, `food_rules.gd.uid`, `ground_plot.gd.uid`, `island_wild_plants.gd.uid`, `portable_electronics.gd.uid`, `roof_opening.gd.uid`, `station_job.gd.uid`, `storage_box.gd.uid`, `storage_slot_ui.gd.uid`, `survival_item_visual.gd.uid`, `survival_service_ui.gd.uid`, `survival_services.gd.uid`, `torch_cycle.gd.uid`, `wild_plant_target.gd.uid`.

### Updated existing source

- `scripts/player.gd` — integration, use/placement/aim, death, held visuals, compatible restoration.
- `scripts/inventory.gd` — recipes, aliases and capacity-safe operations.
- `scripts/save_storage.gd` — version/type/depth/size/numeric validation before restore.
- `scripts/stats.gd` — effort drain, clamping, damage revision and delta signal.
- `scripts/survival_hud.gd` — craft confirmation, percentages/smoothing, use options, modal/Back routing.
- `scripts/mobile_controls.gd` — larger Use target and input coordination.
- `scripts/main_menu.gd`, `scripts/wake_transition.gd` — ordered background preparation and protected New Game/Continue handoff.
- `scripts/island_grass.gd` — wait for terrain and spread sampling/MultiMesh filling across render frames.
- `scripts/ocean.gd`, `scripts/raft.gd` — typed/batched wave sampling, safe crest reuse and one compound raft movement per rendered wave frame.
- `scripts/debris.gd`, `scripts/debris_spawner.gd` — one velocity commit per physics tick and consistent phone limits in desktop mobile profiling.
- `scripts/survival_action.gd` — registered tool/can/battery hand poses and held-item visibility.
- `scripts/survival_audio.gd` — original cached electronics sounds.
- `scripts/survival_equipment.gd` — free the imported arrow template, duplicate per projectile, correct camera path and spend ammunition once; other concurrent equipment changes are retained.
- `scripts/survival_progression.gd`, `scripts/wall_torch.gd` — light/ghost, Burning Torch, saved dawn deadlines.
- `scripts/campfire.gd`, `scripts/survival_machine.gd` — station prompts/jobs and shared light budget.
- `scripts/food_pickup.gd`, `scripts/island_destination.gd` — props, medical caches and crop supplies.
- `scripts/island_grove.gd`, `scripts/island_landscape.gd` — stable original tree roots and plant-kit integration.
- `scripts/island_wildlife.gd` — deferred teardown validity checks.
- `scripts/mobile_performance.gd` — interactive foliage stays visible; lighter Auto rendering and 30 Hz physics at the phone's 30 FPS setting.
- `scripts/game_settings.gd`, `scripts/ocean_atmosphere.gd` — mobile clear-air policy and fresh-phone 30 FPS default with saved choices preserved.
- `scripts/plant_data.gd`, `scripts/plant_instance.gd` — supplied growth models, produce planting/harvest/countdowns.
- `scripts/item_art.gd`, `scripts/ui_icons.gd` — actual produce and new tool/medical/can/meal icons.
- `scripts/raft_construction_batch.gd`, `scripts/smart_roof.gd`, `scripts/rain_system.gd`, `scenes/roof.tscn` — invalid ghost colors, stair ceiling and shelter masks.
- `shaders/grass_wind.gdshader` — shared clearing mask.

### Prepared assets and preparation tools

- `models/island_lowpoly_plants.glb`, `models/island_lowpoly_plants.source.json`, `models/island_lowpoly_plants_OwnerLowpolyLeafAtlas.png`, `models/island_lowpoly_plants_bark.jpg`.
- `models/portable_electronics.glb`, `models/portable_electronics.source.json` and retained exported atlas PNGs: `portable_electronics_5436236cfb7e48a5b306fc9287de2fd2_RGB_TextureAltas_02.png`, `portable_electronics_65237da6bd1f4c1b907d41609571c1ad_RGB_TextureAltas_01.png`, `portable_electronics_6847f70a5621435b80cd3f851d1931db_A_TextureAltas_03.png` (all under models).
- `models/banana_plant.glb`, `models/banana_plant.source.json`.
- `models/carrot_plant.glb`, `models/carrot_plant.source.json`.
- `models/onion_sprout.glb`, `models/onion_young.glb`, `models/onion_growing.glb`, `models/onion_plant.glb`, `models/onion_bulb.glb`, `models/onion_plant.source.json`.
- `textures/ui/advanced_onion.png`, `textures/ui/ARTWORK.md`.
- `tools/prepare_island_plants.py`, `tools/prepare_electronics.py`, `tools/prepare_banana_model.py`, `tools/prepare_carrot_model.py`, `tools/prepare_onion_model.py`.
- Raw-import exclusion files: `3d models/lopoly_plants/.gdignore`, `3d models/Electronic_tools/.gdignore`, `3d models/banana tree/.gdignore`, `3d models/carrot/.gdignore`, `3d models/Onion/.gdignore`.
- `.gitignore`, `ASSET_CREDITS.md`, `GAME_GUIDE.md`, `FEATURE_UPDATE.md`.

### Verification files

- New: `tests/survival_services_smoke.gd`, `tests/portable_electronics_smoke.gd`, `tests/island_wild_plants_smoke.gd`, `tests/shelter_farming_ui_smoke.gd`, `tests/planter_onion_smoke.gd`, `tests/mobile_clear_air_smoke.gd`.
- Their Godot identity files: `tests/survival_services_smoke.gd.uid`, `tests/portable_electronics_smoke.gd.uid`, `tests/island_wild_plants_smoke.gd.uid`, `tests/shelter_farming_ui_smoke.gd.uid`, `tests/planter_onion_smoke.gd.uid`, `tests/mobile_clear_air_smoke.gd.uid`.
- Updated: `tests/advanced_survival_smoke.gd`, `tests/survival_loop_smoke.gd`, `tests/crop_torch_smoke.gd`, `tests/island_visual_smoke.gd`, `tests/construction_weather_smoke.gd`, `tests/foundation_smoke.gd`, `tests/world_visual_smoke.gd`, `tools/verify_source.ps1`.
- `tools/verify_survival_update.ps1` runs all eighteen affected suites with the mobile clear-air policy and isolated storage. Invoke with PowerShell; pass `-GodotPath` if the engine is installed elsewhere.
- `tools/preview_survival_update.ps1` creates a separate isolated desktop Mobile/D3D12 run and captures cooking/storage previews. It requires Windows D3D12 support and does not export an APK.
- `tests/loading_performance_smoke.gd` and `tools/verify_loading_update.ps1` — real loader/120-piece Continue stress fixture, original-wave equivalence, actual walking/looking with visible phone controls, frame diagnostics and transition regressions. Existing environment, island-visual and wild-plant waits now use render frames for their setup conditions. `tools/preview_survival_update.ps1 -TestScript loading_performance_smoke.gd -TimeoutSeconds 240` runs the same fixture with the Mobile/D3D12 desktop renderer and saves `build/loading-gameplay-preview.png`.
- `tests/mobile_smoke.gd` — remove an accidentally duplicated test block, use SceneTree's pause property, and wait for the real loading handoff before touch/pause/Back checks; Continue must release the player into playable physics.

## Manual checklist — all seven requested sections

Use a separate test save. In the editor play the main scene; export Android manually only when ready. Check physical phone controls after exporting.

1. **Medkit:** craft/find two, verify stack/icon/count; lower health; Use while still and verify +50/clamp after 1.5s. Repeat while moving and after damage: item stays, progress/animation stop. Full health should refuse waste.
2. **Can:** aim away/behind a solid wall: filling refuses. Aim near ocean and finish the two-second dip. Drink dirty water and verify damage plus returned Can. Insert another into each filter type; verify motion/drips/progress and one clean can after five seconds. Drink for full thirst, verify Can return. Save/reload a filtering job.
3. **Cooking:** try Bonfire and Cooking Setup. Scroll to every recipe; missing amounts must be red/disabled, sufficient amounts green/enabled. Cook the eight requested dishes and four listed extras. Check raw banana/vegetables/fish vs cooked effects. Refuel/let fire expire; job pauses. Reload midway; reward arrives once. Fill every inventory slot before completion; recover the output bag. Clean-water recipes return their empty can.
4. **Stats:** compare idle/sprint/swim drains; empty hunger/thirst should damage health. Eat a potato, soup and drink water: verify values, smooth displays and brief delta popups. At 25% or less verify blinking warning. Confirm title menu does not drain stats.
5. **Storage/death:** place a box on supported deck; drag both directions, merge/swap, tap on mobile, and try two fingers. Back closes it. Save/reload contents. Put valued tools in the box, carry other items, die: hotbar/backpack empty and loot bag at the death spot, box unchanged. Respawn and recover the bag. Nonempty box dismantling must refuse.
6. **Torch:** find Torch in crafting and confirm its cost. Unlit Torch gives no light. Aim at a lit Bonfire/Cooking Setup and light it. Verify Burning Torch icon/hand flames/light in both camera views. Aim at wall: green valid/red blocked ghost and PLACE TORCH; mount/take should transfer one item. Save/reload. Advance through next dawn: flame goes out, unlit Torch can be relit. Test rain/swimming extinguishing and roof protection.
7. **Performance/saves:** place several fires/lamps/torches; confirm the six built-light budget and no per-frame particle spawning. Repeatedly press use/cook/transfer: no duplicates or lost inputs. Test full bags. With isolated copies only, damage nested save fields/version and verify graceful rejection/backup recovery. Reopen an old save. Check Android FPS/thermals/touch separately; source tests cannot prove these.

Additional: chop/gather a complete island patch, plant a crop and wait beyond wild regrowth: the crop must remain alone. Harvest it and wait for a small wild seedling. Reload the clearing. Craft all electronics; test zoom restore, flashlight light/sound, radio reply, power off, battery cover/remove/replace, screen percentage, shade/night/rain blocking charge and four minutes in direct sunlight. Confirm rooftop/foundation pots reject ocean and stair holes; inspect mobile rain indoors and clear air.

## Verification record

Before the loading follow-up, isolated source verification passed **929 checks across 18 suites**, with zero failures or script/engine errors: survival services 85, electronics 42, wild plants 65, action/farming 46, mobile 93, survival loop 53, advanced survival 64, crops/torch 37, shelter/farming/UI 89, planter/onion 51, island visuals 87, environment 41, testing supplies 11, mobile clear air 28, construction/weather 39, foundation 17, visual construction 53 and world visuals 28. Logs are in `build/source-*-console.log`; normal saves were not used. Subsequent loading validation is recorded in `GAME_GUIDE.md`.

The final desktop Mobile/D3D12 cooking/storage run passed all **85 checks** and exited cleanly without script or engine errors. The cooking and storage screenshots were visually inspected. Desktop previews include `build/cooking-recipes-preview.png`, `storage-box-preview.png`, `portable-electronics-preview.png` and `island-wild-plants-preview.png`. No APK was built/exported and physical phone behavior/performance remains unverified.

The subsequent loading/movement work passed **593 checks across 13 isolated source suites** and a separate **27-check Mobile/D3D12 loading/gameplay preview**. `GAME_GUIDE.md` records suite counts, the captured preview, and performance limits. Large-raft stress measurements still include slow frames; successful source checks do not establish phone FPS or zero hangs. Existing player saves and the once-per-save testing grant were preserved; the owner still exports the APK manually.
