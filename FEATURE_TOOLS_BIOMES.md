# Survival tools and climate islands — 2026-10-09

This update extends the existing game. Existing construction indexes, inventories, four island coordinates/resource IDs and normal player saves are preserved. The owner exports the APK manually.

## Research and implementation choices

| Developer source | Relevant design | Applied here |
|---|---|---|
| [Raft official press kit](https://www.raft-game.com/presskit.html) | Hook gathering, crafting, expanding the raft, anchoring and underwater exploration form a connected survival loop. | Keep the existing rope gun and upgrades; add reusable anchoring and manual rowing so early navigation has a useful tool loop. |
| [Grounded official game overview](https://grounded.obsidian.net/game), [feature board](https://grounded.obsidian.net/feature-board) | Craftable tools support gathering/exploration; named tool types include axes, hammers and shovels. | Add distinct chopping, mining and digging tools with visible costs, valid targets, feedback and useful harvesting improvements. |
| [Unknown Worlds Buddy System update](https://unknownworlds.com/en/news/subnautica-2-buddy-system-update) | Clearer target signals, hover information, readable recipe materials and explanations of blocked building actions. | Keep the existing HAVE/NEED recipe confirmation and only expose tool use for valid, reachable interactions. Preserve materials on failed actions. |

The implementations and balance below are project-specific choices informed by these loops. Tool geometry and animations are original work, with the project's existing art style and shared materials.

## Tools and controls

Open **Bag → Craft**, select a tool, review HAVE/NEED and **CONFIRM CRAFT**. Choose **HOLD ITEM**, then use **HAND/E** at a valid target. First-person hands and the third-person rig show the selected tool and its work motion. Existing bare-hand plant gathering/chopping remains available.

| Tool | Cost | Behaviour |
|---|---|---|
| Axe | 3 Wood, 2 Metal, 1 Rope | Two chopping damage rather than one. Planted-tree/stump work takes 60% of the usual hold time. Cuts new spruce and existing island trees. |
| Pickaxe | 3 Wood, 3 Metal, 1 Rope | Four impacts exhaust a marked deposit. Volcano rewards 4 Stone + 2 Metal; winter rewards 4 Stone + 1 Metal. |
| Shovel | 2 Wood, 2 Metal, 1 Rope | Three Soil on higher island ground, or three Sand on lower beaches. Root harvesting takes 60% of the usual hold time. |
| Paddle | 4 Wood, 2 Plastic, 1 Rope | Stand on the raft and look toward travel. Water contact spends 6 stamina and adds directional momentum; drag slows the raft. A sail is not required. |
| Anchor | 4 Metal, 4 Stone, 4 Rope | Reusable DROP/RAISE action aboard. Stops horizontal travel and cancels a course; raft bobbing continues. Raise before sailing or rowing. |

Portable work takes 0.85 seconds; rowing takes 1.1 seconds. Contact occurs at 57% of the action. Changing held tool, losing target/reach, taking damage, opening a blocking panel, pausing or losing app focus cancels unfinished work. A full bag preserves the last resource hit and its reward. The existing 30-slot inventory and permanent rope gun are retained.

## Islands and survival rules

- **Volcano Isle**, X/Z `(-1500,900)`: dark textured rock, uneven crater rim, animated lava pool/channel and twelve finite mineral deposits. Lava deals 10 health/second while in contact; it does not damage a player merely standing elsewhere on the island. The channel follows the actual terrain triangles.
- **Winter Isle**, X/Z `(1100,-1300)`: snow, exposed slopes, six deposits and fourteen wind-animated spruce trees. Axe felling awards six Wood. Cold warns at 60 active seconds and damages health slowly after 180 seconds. Hold a burning torch or stand within 6m of a burning campfire to warm up. Leaving reduces cold exposure.
- Clear land and plant ordinary produce without a pot, using the existing agriculture system. A felled spruce waits six active minutes before beginning a 30-second growth cycle. Seeded crops protect their clearing until removed/harvested; a growing tree has no blocking collider and waits when the player occupies its trunk.
- All six destinations fit on the map; volcano/winter markers have distinct colours. Sailing stops 52m from the new island centres, and a rowed hull stops before entering their land.

The new terrain is built in cooperative batches under the shared 2ms setup budget. Each terrain has 2809 vertices/5408 triangles. Spruce share one mesh and cull at 160m, deposits cull at 220m and lava uses one nearby shadowless light. No smoke/fog/particle emitters are added. Ocean strips share the dense patch's border vertices; distant normals smooth out the coarse reflections. Camera far distance is 4000m so remote islands remain visible.

## Saves and compatibility

Version 1 remains readable. Optional fields: `raft_anchored`, `biome_resources`, `biome_tree_growth`, `winter_exposure`. Stable resource IDs use island name and index. Partial/depleted deposits, forest wait/growth and cold restore on Continue; absent fields use defaults. Save creation retains loaded entries while background island setup is unfinished. Save validation rejects malformed records. Real player storage is not used by tests. Testing grants of 2000 materials and Soil remain unchanged.

## Manual checks

1. Craft each tool and confirm its icon/cost. Hold it in both camera views. Try mining/chopping, switch tools mid-swing and open the bag; cancelled swings must not award resources. Fill the bag and check that the final deposit hit is preserved.
2. Paddle on the starting raft without a sail. Change viewing direction and row again. Try from land: it must not move the raft. Drop the anchor, try rowing/sailing, raise it and try again.
3. Install a Sail Kit and select each new island on the map. Walk on its terrain, collect minerals and save/Continue after partial mining. Exhausted deposits must stay empty.
4. On volcano terrain, approach lava carefully and check the warning/damage. Other rock remains safe. Inspect the moving pool/channel in daylight and at night.
5. In winter, fell a spruce, plant a potato in its clearing and let it grow. Natural spruce must wait for that clearing to become empty. Check cold warning, warming beside a fire/held burning torch and recovery after leaving.
6. On the actual phone, check New Game/Continue, looking/walking, touch release, both camera views and the island approaches at Battery Saver/30 FPS. Source/desktop checks cannot establish phone FPS or thermals.

## Verification tools

Validation on 2026-10-09: **526 checks across 10 isolated source suites**, plus **94 checks in the Mobile/D3D12 desktop preview**, passed with zero failures and no script/engine errors. The source suites cover tools/biomes (94), island visuals (87), wild plants (65), farming/actions (46), raft/cinematic (39), foundations (17), mobile controls (91), menu loading (21), construction/weather (39) and fresh-install loading (27). Five tool-icon renders also passed. Crafting, the six-destination map, volcano, winter and both mining camera views were inspected. Physical-phone FPS, thermals and touch feel remain unverified. No APK was built, and owner saves were untouched.

`tools/verify_tools_biomes.ps1` uses isolated data and runs tools/biomes, terrain, wild plants, farming/action poses, raft, foundations, mobile controls, menu/loading and weather checks. First-install loading runs in its own fresh preferences directory. No junction tree is recursively deleted.

`tools/preview_survival_update.ps1 -TestScript survival_tools_biomes_smoke.gd` runs Mobile/D3D12 with isolated saves. Outputs are `build/tools-biomes-volcano.png`, `tools-biomes-winter.png`, `tools-biomes-map.png`, `tools-biomes-crafting.png`, `tools-biomes-mining-first-person.png` and `tools-biomes-mining-third-person.png`. `tools/render_food_icons.gd -- --tools` renders five tool icons; `tools/import_food_icons.ps1 -IconFolder tools` imports only these PNGs in a tiny project.

## Source and asset manifest for this update

Created:

- `scripts/survival_tools.gd`, `survival_tool_visual.gd`: validated contact actions and original shared tool models.
- `scripts/biome_island.gd`, `biome_resource.gd`: terrain, climate, deposits, tree felling/regrowth and crop priority.
- `shaders/biome_terrain.gdshader`, `volcanic_lava.gdshader`, `winter_needles.gdshader`: basalt/snow, lava flow and snowy wind-blown foliage.
- `textures/ui/tools/axe.png`, `pickaxe.png`, `shovel.png`, `paddle.png`, `anchor.png` and their Godot `.import` settings: pictures of the actual game tools.
- `tests/survival_tools_biomes_smoke.gd`, `tools/verify_tools_biomes.ps1`, this document.

Modified:

- `scenes/main.tscn`: two additive island nodes and camera range.
- `scripts/inventory.gd`: five recipes.
- `scripts/player.gd`: tool dispatch/holding, contextual actions, safe navigation arrival, crop space and saved state.
- `scripts/raft.gd`: paddle momentum, anchor, shoreline movement guard and deployed anchor/rope visuals.
- `scripts/survival_action.gd`: mining/digging/rowing/anchor key poses, tool props and sound cues; reversed raising motion.
- `scripts/plant_instance.gd`, `island_wild_plants.gd`, `wild_plant_target.gd`: useful Axe/Shovel bonuses and timed axe contact while retaining ordinary gathering.
- `scripts/island_wildlife.gd`: keep tropical animal spawning on the existing tropical islands.
- `scripts/survival_hud.gd`, `item_art.gd`: recipes, tool pictures/help and six-destination chart.
- `scripts/ocean.gd`, `shaders/main.gdshader`: six shore masks, matching water border vertices and calmer distant normals.
- `scripts/main_menu.gd`: warm the added scripts, shaders and five pictures before entering play.
- `scripts/save_storage.gd`: validation of optional new metadata.
- `tests/island_visual_smoke.gd`, `loading_performance_smoke.gd`: retain original shore slots beside new masks; account for cached generated food images.
- `tools/render_food_icons.gd`, `import_food_icons.ps1`, `preview_survival_update.ps1`: reusable tool-icon rendering/import and isolated desktop preview.
- `GAME_GUIDE.md`, `ASSET_CREDITS.md`: current behaviour, architecture, provenance and compatibility.

Ignored `build/` contains regenerated verification logs/screenshots and temporary local test launchers. No APK was built or exported.
