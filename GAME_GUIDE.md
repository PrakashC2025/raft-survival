# Ocean Survival — game, code, and maintenance guide

Last updated: **2026-10-05**. This is the current project handover for the owner and future coding AIs. Read it before changing gameplay. Paths below are relative to this project; `res://` means the Godot project directory and `user://` means Godot's platform-specific saved-data directory. Live source code remains authoritative if a later change makes this guide outdated. Update this guide when changing behavior, constants, architecture, or saved data.

## Owner's requirements and current delivery

The owner plays on Android and wants reliable New Game/Continue, working touch buttons, smooth survival gameplay, foundation placement, a convincing rope launcher with longer reach, temporary supplies for testing building and crafting, and a more natural ocean, trees, grass and environmental sound.

The visual reference the owner confirmed is [Ocean Survival by Candy Mobile](https://play.google.com/store/apps/details?id=com.chris.seasurvival). Use it as direction for ocean survival, crafting, shelter, and a useful handheld hook. The project uses its own code and assets. The current scene remains stylized; it is not a complete reproduction of the reference game's graphics or content.

**Latest build instruction: the owner will build the APK manually. Do not build/export an APK unless asked again.** Earlier APK builds were explicitly requested, but this latest instruction supersedes them. The existing `build/OceanSurvival-updated.apk` predates the latest testing supplies and rope changes. Editing source does not update an APK already installed on a phone.

Current changes and fixes:

- Required island textures are included by the Android export preset, fixing the observed loading failure (threaded status 2, scene error 19).
- New Game and Continue wait for validated game-scene loading, show friendly errors, unlock retry, and avoid destroying a saved game before successful scene entry. Active loads no longer fail just because 90 seconds elapsed: the menu keeps polling, shows a still-loading notice after 30 seconds, and offers Cancel Loading. Cancelling preserves saves/inventory and lets the same request finish warming without entering gameplay.
- Mobile controls track fingers independently, support analog movement, release held actions when interrupted, and integrate inventory, construction, map, crafting, help, pause, settings, and Android Back.
- Foundation placement works with a valid green preview even when optional socket metadata is absent. Invalid placement and missing materials produce feedback.
- Temporary testing inventory grants 2,000 each of Wood, Rope, Plastic, Barrel, Stone, and Metal once per save. Spending and recipe costs still work.
- A procedural handheld rope launcher replaces the old rope item visual. It has a barrel, grip, trigger guard, metal hook, rope reel, crank, and holding hand, plus recoil and first/third person visibility.
- Quick casts start at 20 m; holding charges up to 60 m. Hook flight is arced, follows a locked trajectory, and the braided rope starts at the muzzle.
- Hotbar selection immediately updates the item shown in the hand. Ocean shading has gentler fine ripple contrast.
- Water now has irregular noise-based ripple normals, stronger angle-dependent sky reflection, sun/moon highlights and twilight haze. A lightweight distant-water apron fills the old dark horizon gap.
- Island palms use the supplied textured `models/coconut_palm.glb` on the home and destination islands, preserving its frond geometry/textures with wind animation and trunk-only collision. Grass uses the supplied textured `models/realistic_grass.glb`, normalized to a grounded 0.38 m tuft with color/dryness variation and traveling wind gusts. Procedural foliage remains a fallback.
- Fixed the comma-separated `@export_file` patterns that prevented IslandSetup/IslandGrass from parsing in Godot 4.7.1. Each pattern is now a separate argument. Footprint-manager attachment is deferred until the parent finishes adding scene children, and destination setup checks safely handle a missing completion property.
- Recorded ocean waves are mixed with original generated wind/foliage beds, audible default rain and underwater low-pass filtering. The environment bus is owned and removed by each gameplay scene.
- Island markers clamp both behind-camera and front-but-offscreen targets, including camera-plane edge cases. Diamonds draw around a local origin to avoid collapsed polygons from enormous projected coordinates. The reported unused-parameter, mixed ternary, integer division and shadowed/confusable name warnings are cleaned up.
- The home island now has a smooth original coastal ridge GLB with a layered rock shader and four animated, huntable original gull GLBs. A licensed custom gull model can still be assigned.
- Island terrain shader detail now adds finer sand grain, wind-ripple variation and broken rock strata without replacing the scanned home-island textures.
- Players can scoop Sand from a nearby island surface, equip it from the bag/hotbar, and apply a visible sand top-dressing to a planter. Planter sand state is saved with built pieces while old saves default to no top-dressing.
- Walking on island ground stamps alternating, fading footprint decals from a small reusable pool; raft footsteps remain wood sounds and do not spawn prints.
- Planter coconut trees now use the same supplied textured coconut-palm GLB as island trees, retaining growth stages, fruit sockets, chopping and saved state. Shared surface materials add wood grain, metal patina, stone, cloth and soil detail to untextured construction, equipment, pickups and character parts while preserving imported textures and vertex colors. Rope coils, plastic canisters, bent metal scraps and seed packets have recognizable reusable geometry.
- The menu has an animated dusk sea; HUD, touch controls, crafting, bag and settings use cached matte panels and brass accents. Seed icons show packets and their crops. Island markers hide during modal panels and return when they close. Touch hit areas and action ownership are preserved.
- Default foliage GLBs are preloaded as dependencies of the threaded game-scene load. Palm collision shapes, normalized grass meshes, prop meshes and materials are shared. Debris prewarming yields after each two objects; fading pickups reuse their collected mesh list. Mobile grass visibility adapts without rebuilding the field, and Auto quality keeps expensive cumulus clouds disabled even after recovery.

The 2026-10-03 eight-suite source verification passed **266 checks**: 92 mobile, 17 foundation, 11 testing supplies, 20 rope, 40 environment, 23 island marker, 21 menu loading and 42 survival-loop checks. Coverage includes supplied foliage, collision/quality budgets, saved coconut-tree restoration, modal markers, waits beyond the former 90-second cutoff and safe cancellation for New Game/Continue/Quick Save. Desktop Mobile/D3D12 previews rendered the updated visuals without script/engine errors. A real rendered New Game load completed in about 70 seconds before the timeout fix; the subsequent cancellation/retry probe completed in about 25 seconds. Those are observations on a busy desktop, not a speedup guarantee. Shutdown ObjectDB leak warnings remain (including rapid scene switches). No APK was exported or Android phone tested; these checks do not establish phone FPS or freeze-free gameplay.

## Project and entry points

| Item | Current value or location |
| --- | --- |
| Engine | Godot 4.7.1 stable mono installation; gameplay is GDScript |
| Project | `project.godot`, editor project name RaftSurvival |
| Android display name | Ocean Survival |
| Android package | `com.praka.oceansurvival` |
| Android export | `export_presets.cfg`, preset Android, output `build/OceanSurvival-updated.apk` |
| Android preset version | 1.1.2, version code 5; manual debug-signed APK for ARM64 phone testing |
| Rendering | Mobile renderer; desktop visual validation used D3D12 |
| Physics | Jolt configured in the project |
| Display | Landscape, 1280 × 720 design canvas with responsive scaling |
| Menu | `scenes/main_menu.tscn` with `scripts/main_menu.gd` |
| Gameplay | `scenes/main.tscn` |
| Autoloads | Inventory, Stats, PlantDB, GameSettings |
| Main save | `user://raft_save.json` |
| Quick save | `user://raft_quicksave.json` |
| Settings | `user://settings.cfg` |

Autoloads are shared state, not disposable per-scene copies. Inventory owns items and save entry points; Stats owns survival values; PlantDB describes plants; GameSettings persists preferences and coordinates pause/back behavior. Most gameplay orchestration currently lives in the large `scripts/player.gd`. Before extracting a subsystem, trace its callbacks, signals, frame order, and save dependencies.

The main scene includes the Ocean, Raft, Player, debris spawning, home island setup, distant island destinations, shark spawners, sky/time-of-day nodes, and ambient ocean sound. The player owns its collision/movement body, character model, camera pivot/spring arm/camera, first person hand pivot, RopeSystem, rain effects, and a canvas containing crosshair, mobile controls, survival HUD, and island marker.

The first person hand hierarchy is `CamPivot/SpringArm3D/Camera3D/HandPivot`, with Arm and Fist/HandItem below it. RopeSystem queries the player's actual launcher muzzle rather than a guessed screen point. The third person launcher is a separate visual attached to the player.

## Source file map

| File | Responsibility |
| --- | --- |
| `scripts/main_menu.gd` | Drawn menu, touch/mouse hit testing, save labels, loading, retry, scene entry |
| `scripts/player.gd` | Movement, swimming, camera, interactions, held items, building/editing, crafting, fishing, map/navigation, restoration and saving |
| `scripts/mobile_controls.gd` | Phone joystick/look input, action buttons, finger ownership, modal/input release |
| `scripts/survival_hud.gd` | Survival values, hotbar/bag presentation, touch inventory handling |
| `scripts/game_settings.gd` | Persisted settings and pause/back coordination |
| `scripts/mobile_performance.gd` | Mobile quality profiles, render scale adaptation, shadow/effect limits |
| `scripts/inventory.gd` | Slot storage, recipes, capacity checks, testing grant, JSON save/load |
| `scripts/stats.gd` | Health, hunger, thirst, drain and death |
| `scripts/rope_system.gd` | Charge/cast/reel state, hook trajectory, catches, return/cancellation, rope geometry |
| `scripts/rope_launcher_visual.gd` | Procedural launcher, hand, muzzle marker, and hook meshes |
| `scripts/build_system.gd` | Building support code; inspect live player orchestration before changing |
| `scripts/build_socket.gd` | Socket metadata and attachment support |
| `scripts/raft.gd` | Raft physics/buoyancy and structure context |
| `scripts/raft_foam.gd` | Water-contact foam around the raft |
| `scripts/door.gd` | Door behavior |
| `scripts/debris.gd` / `debris_spawner.gd` | Floating resources and population management |
| `scripts/food_pickup.gd` | Collectible food/resources, collection behavior |
| `scripts/object_materials.gd` / `resource_visual.gd` | Shared surface materials and reusable salvage/seed prop meshes |
| `scripts/ui_surface.gd` | Cached panel styles, tactile controls and settings theme |
| `scripts/ocean.gd` | CPU ocean height sampling used by gameplay |
| `scripts/ocean_ambience.gd` | Ocean sound behavior |
| `scripts/vegetation_visual.gd` | Shared procedural grass tufts/palm fronds and natural foliage materials |
| `scripts/rain_system.gd` | Weather/rain effects |
| `scripts/island_setup.gd` | Island normalization, imported `coconut_palm.glb` placement, collision setup, pickups and foliage preparation |
| `scripts/island_grass.gd` | Batched surface placement and MultiMesh grass (`models/realistic_grass.glb` 24-triangle textured tuft with procedural fallback) |
| `scripts/island_mountain.gd` / `island_birds.gd` | Home-island procedural peak and optional imported gull flock |
| `scripts/sand_footprints.gd` | Pooled, fading island-footprint decals |
| `scripts/island_destination.gd` | Distant island destination behavior |
| `scripts/island_beacon.gd` / `island_marker.gd` | World destination cues and HUD marker |
| `scripts/plant_data.gd` | PlantDB definitions |
| `scripts/planter.gd` / `plant_instance.gd` | Containers, growth, harvest, tree chopping and restoration |
| `scripts/shark.gd` / `shark_spawner.gd` | Shark movement, detection, bites and spawning |
| `scripts/crosshair.gd` / `ui_icons.gd` | Crosshair and shared drawn UI symbols, including the Sand item icon |
| `shaders/main.gdshader` | Ocean vertex waves and fragment shading |
| `shaders/rope_fiber.gdshader` | Rope braid/fiber appearance |
| `shaders/wood_planks.gdshader` | Wooden building appearance |
| `shaders/grass_wind.gdshader` | Grass animation |
| `shaders/palm_leaf.gdshader` / `palm_bark.gdshader` | Frond motion/backlighting and trunk surface detail |
| `shaders/island_terrain.gdshader` | Island terrain material |
| `shaders/island_mountain.gdshader` | Procedural rock color, grain and sediment seams |
| `shaders/sand_surface.gdshader` / `sand_footprint.gdshader` | Handheld/planter sand grain and fading sole depressions |
| `shaders/object_surface.gdshader` / `menu_sea.gdshader` | Original procedural surface detail and animated menu sea |
| `shaders/raft_foam.gdshader` | Raft foam appearance |

Other useful files: `BUILD_ANDROID.md` gives build/install verification instructions; `ASSET_CREDITS.md` documents asset origins and licenses; `tools/verify_source.ps1` checks current source; `tools/verify_android.ps1` checks an exported APK. `DOCUMENTATION.md` contains historical notes and source snapshots and may have older constants/behavior. Use this guide and current source first.

## New Game, Continue, and loading errors

The menu requests `res://scenes/main.tscn` with threaded resource loading, polls status/progress, and retrieves the PackedScene only after a successful status. The scene transition is separate. There is no elapsed-time failure for an in-progress request: a single texture/shader dependency can take longer than 90 seconds on a slow or busy machine. After 30 seconds the progress subtitle says STILL LOADING. Cancel Loading clears the pending New Game/Continue/Quick Save choice and returns to the menu without touching inventory or disk saves; the one resource request keeps warming, and late completion does not enter gameplay. Settings remains accessible during loading. Actual missing/failed resources still show an error and unlock retry.

New Game resets live state only as part of validated entry. It uses `Inventory.new_game_reset(false)` so existing save files survive until gameplay successfully writes the new save. Continue reads the selected saved data and restores inventory/meta before the player restores world state. Failure restores the live inventory snapshot and related metadata rather than leaving a half-reset menu session. Do not add a blocking fallback load on the main thread; that can freeze a phone and repeat the same missing-resource failure.

The reported Android error at about 40% was caused by export exclusions omitting six textures used by an imported island model. Broad patterns `models/sand_raftsurvival_Image_*` and `textures/sand_raftsurvival_*` must not be reintroduced. Dependencies include textures named `16.jpg`, `17.png`, `18.png`, `3.jpg`, `19.png`, and `20.png`; inspect the imported model references for full paths. Those dependency files must be present in the final package. Reduce texture size using import settings when needed, rather than deleting required dependencies from exports.

Status 2 is a failed threaded load and error 19 was the failed scene transition in this incident. The percentage is not a diagnosis. For a new failure inspect the missing-resource/parse error preceding the status and verify the actual APK contents. A passing source run cannot detect an APK exclusion mistake.

An already-open editor previously rewrote the corrected export preset with cached old exclusions. Reload the project/export settings before a manual export after external preset edits, and verify the resulting package. Source configuration and the editor's cached configuration can differ.

## Controls and input ownership

| Action | Desktop control | Mobile behavior |
| --- | --- | --- |
| Move | Arrow keys | Analog left joystick |
| Look | Mouse | Drag look area |
| Jump / swim upward | Space | Jump/up button |
| Sprint | Shift | Sprint button |
| Dive | Ctrl | Dive action when available |
| Interact | E | Context action button |
| Rope charge/cast | Hold Q, release to throw | Hold hook button, release to throw |
| Pull rope | F | Pull action |
| Cancel rope | Right mouse button | Cancel action/context interruption |
| Build mode | B | Build button |
| Select next build piece | Tab | Piece selector |
| Place / confirm | P | PLACE button |
| Turn build piece | R or Y | Rotate controls |
| Pitch build piece | X | Rotation controls |
| Remove/edit removal | Delete | REMOVE action |
| Fine build turn | Shift with R, 15° | Dedicated UI as implemented |
| Hotbar | 1–6 | Tap a hotbar slot |
| Quick save | F5 | Save action in UI |
| Map | M | Bag → MAP |
| Craft | C | Bag → CRAFT |
| Simulate mobile UI | F10 | Developer desktop helper |
| Build debug overlay | F3 | Developer desktop helper |

Do not document WASD as the current movement binding. InputMap in `project.godot` is authoritative. Some rope actions are ensured by RopeSystem; inspect both InputMap and that script when rebinding.

Every touch action has an owning finger. A joystick finger, look finger, and action finger can remain active simultaneously. Release actions on touch release, cancellation, modal opening, focus loss, pause, and scene teardown. Moving outside a held button must not leave a permanent action pressed. Use the existing routing and release helpers instead of creating a global single-finger flag.

Joystick output uses `limit_length(1.0)` so partial displacement yields slower movement. Normalizing every nonzero input would destroy analog control. Avoid synthetic mouse events triggering the same touch action twice. Inventory/UI consumption must prevent accidental world input underneath a menu. Android Back is coordinated centrally to avoid double toggles or leaving movement held.

## Inventory, crafting, and testing supplies

The authoritative inventory is a 30-element slot array. Slots 0–5 are the hotbar; 6–29 are the bag. A slot is `{}` or `{"item": String, "count": int}`. Aggregate `items` values are recomputed for compatibility/display; do not directly mutate totals and expect slots to update.

`Inventory.add(item, amount)` merges stacks then fills available slots and returns the amount that did not fit. World pickups and rope catches must respect this return value. Never delete a world resource whose inventory credit failed. `remove`, `has`, `total`, swapping and dropping helpers keep slot storage and emitted updates consistent.

Item crafting checks both cost and final capacity. The capacity simulation removes ingredients before trying to add the result, so crafting can succeed if consuming an ingredient frees a slot. A failed craft must not spend ingredients. Building costs apply only after placement is valid; construction is not ordinary item crafting.

Normal starter items include Rope and potato/coconut/banana seeds. Seed setup runs before the testing grant.

Temporary testing configuration is in `scripts/inventory.gd`:

```gdscript
const TESTING_RESOURCES_ENABLED := true
const TESTING_RESOURCE_AMOUNT := 2000
const TESTING_RESOURCE_ITEMS := ["Wood", "Rope", "Plastic", "Barrel", "Stone", "Metal"]
const MAX_STACK := 2000 if TESTING_RESOURCES_ENABLED else 99
```

`grant_testing_resources()` tops each listed resource up to 2,000 once. The player's `_ready()` calls it after seed setup. `testing_resources_granted` persists in the save, defaults to false for older saves, and resets for New Game. Continue does not refill resources already spent after the completed grant. If there is insufficient capacity for every grant, the completion flag stays false; it can finish on a later attempt. The grant is finite inventory, not infinite crafting.

To restore normal survival defaults later, set `TESTING_RESOURCES_ENABLED` to false. This restores a 99 stack limit for normal operation and stops grants. It does not silently erase existing saved supplies. If migrating old 2,000 stacks is required, design an explicit capacity-safe migration instead of truncating them. `Inventory.infinite` is a separate development flag and is not how this grant is implemented.

### Construction costs

| Piece | Materials |
| --- | --- |
| Foundation | 5 Wood |
| Wall | 8 Wood, 1 Rope |
| Roof | 8 Wood, 1 Rope |
| Stairs | 6 Wood, 1 Rope |
| Door | 4 Wood, 1 Rope |
| Window | 3 Wood, 1 Plastic |
| PlanterPot | 4 Wood |
| PlanterBox | 6 Wood |
| TreePot | 8 Wood, 1 Rope |

Sixteen pieces are registered: the nine above, Bonfire (8 Wood + 4 Stone), RainCollector (6 Wood + 1 Barrel + 2 Rope), and the five advanced machines described below. Raft Extension remains a legacy recipe/scene rather than a separate active selectable piece.

### Equipment costs

| Item | Materials |
| --- | --- |
| Fishing Rod | 3 Wood, 2 Rope, 1 Plastic |
| Spear | 3 Wood, 2 Stone, 1 Rope |
| Sail Kit | 8 Wood, 4 Rope, 2 Plastic |
| Motor Kit | 10 Wood, 2 Rope, 5 Plastic, 4 Metal |
| Life Vest | 5 Plastic, 2 Rope |

Recipe identifiers, hotbar item names, icons, interaction logic, and saved type names must remain consistent. Item names are case-sensitive strings.

## Movement, interaction, and held items

Player is a CharacterBody3D with raft-relative movement and swimming. Current walk speed is 3, sprint speed 5, and jump velocity 4.5 with gravity 18 (about 0.56 m jump apex). The camera spring arm supports first and third person modes. Swimming compares the player against sampled ocean height, not just a fixed flat plane. The raft contributes horizontal carry while the player is on deck.

Interaction targeting distinguishes nearby pickups, planters, doors, editable construction, fishing, and combat. Typical pickup reach is 5 m, with closer context checks around 2 m; rope aim reaches up to 60 m. Treat ray masks/groups and distance checks as part of the interaction contract. The `debris` group contains both floating rigid bodies and fixed pickups; do not assume every member is a RigidBody3D.

`select_hotbar_slot()` updates `_update_hand_item()` immediately. `_held_visual_item` prevents rebuilding identical visuals when only a stack count changes. On changing items, old child visuals are hidden before deferred freeing so there is no one-frame double model. The old arm and fist boxes are hidden. All equipment now uses the original human-hand GLB under HandItem, including the launcher. Camera switching must synchronize third person held-item visibility.

## Rope launcher and collection state machine

Primary files: `scripts/rope_system.gd`, `scripts/rope_launcher_visual.gd`, `shaders/rope_fiber.gdshader`, and the player's hand/origin helpers.

| Parameter | Current value |
| --- | --- |
| Maximum cast distance | 60 m |
| Quick cast charge | 20 m |
| Charge rate | 50 m/s |
| Throw speed | 42 m/s |
| Reel speed | 18 m/s |
| Unloaded return speed | 45 m/s |

Flow: IDLE (with an independent charging flag) → THROWING → EXTENDED/HOOKED → REELING or RETURNING → IDLE. A short press casts with the quick distance. Holding charges to the cap and displays a CAST metre indicator. Releasing creates the throw; cancellation resets charging/flight and safely releases caught resources. Building or editing also cancels the rope, including a charge that has not launched yet. An empty hook automatically returns after its 0.8 s wait; a catch settles for 0.25 s and automatically reels. Pull/throw while extended can request reeling sooner.

The origin comes from `Player.get_rope_launch_origin()`, selecting the visible launcher marker for first/third person. A fallback origin supports existing hook use when a different hotbar item is active. `LaunchMuzzle` in the launcher is at `(0, 0.08, -0.654)` in model space. Keep this marker aligned when changing the barrel. The loaded hook is hidden while the rope is active and restored when idle.

Aim uses a raycast and a water-plane fallback. At throw time the start, direction and endpoint are locked; turning the camera later cannot steer a launched hook. Near targets may shorten the cast. The endpoint is constrained to the maximum distance from the actual origin; a full-charge open-water throw can travel slightly under 60 m because camera and muzzle origins differ. Do not promise every aim direction produces exactly 60 m.

Flight follows a sine arc over interpolation from the locked start to end. Maximum arc lift is limited to 3 m and scales with flight length. Collision/collection advances in small steps (up to 0.5 m) so fast travel does not skip nearby debris. The hook finishes near water height. Return movement clamps each step to remaining distance to prevent oscillation/overshoot at the hand.

Only compatible floating rigid-body resources can be caught. Caught bodies are frozen/moved with the hook; multiple catches are supported. Reeling credits inventory safely. Overflow, cancellation, invalid targets, or interruption release remaining bodies rather than deleting resources. Preserve body references and collision/freeze restoration when changing this logic.

The launcher is generated in code and uses material-batched geometry: bevelled receiver, steel barrel/bore, sights, grip, trigger guard, brass hardware, helical rope spool/crank and rounded holding hand. `create_launcher(with_hand)` serves both camera modes, and `create_hook()` builds the matching metal hook. There are no copied reference-game assets. The procedural class extends RefCounted and is preloaded rather than relying on a new global class registration.

The line reuses one ImmediateMesh and one ShaderMaterial. It has 12 segments and six radial sides (144 triangles), with a relaxed sag while extended and a tauter line when reeling. UV length follows world distance so the fiber pattern stays consistent across different casts. Launcher and hook are batched by material to keep mesh/draw count small; the smoke test permits at most eight launcher mesh nodes.

Mesh winding matters: Godot front faces here use clockwise triangles. Bevel panels, corners, helical tubing, and line sides need consistent outward normals and vertex order. Incorrect winding previously made the rope reel appear dashed. The fiber shader is cull-disabled for a reliable thin line. Do not replace per-material batching with hundreds of separate node primitives.

The player blends a brief 0.055 m positional kick and small rotational recoil into existing hand sway. Hotbar switches and camera modes must still work during active rope use. Tests cover origins, charging/release, range, arc, catch cancellation, return, visual switching, and build interruption.

## Construction, foundations, and editing

Foundation cells are 2 × 2 m with approximately 0.3 m thickness. The original raft anchor cell is reserved. Cell identity and world transform are separate: store occupancy by canonical raft-local cell, then derive the placement transform. Use the same coordinate conversion for preview, actual placement, support, removal, and restoration.

A support search follows neighboring occupied foundation cells connected back to the raft. Collision/placement validation also considers the candidate's actual footprint, height, orientation, existing pieces, and reserved cells. Walls, roofs and attachments have different support/overlap rules from foundations; do not apply a generic center-distance check to every type.

The placement sequence is: refresh exact preview → validate position/support/overlap → check affordability → spend materials → instantiate/register the real piece → refresh preview again. Invalid placements do not spend resources. Green means valid geometry, but insufficient materials still need a clear message. `_try_build()` reports actual missing materials or the invalid-placement reason.

The fixed P-button bug was an unconditional requirement for socket metadata. A foundation can have a valid green grid preview without a socket object. Socket metadata is optional for this path; do not restore the null-socket rejection. Other attachments can still need sockets according to their own validation.

Actual built pieces are parented under the raft's BuiltPieces context, with unique type-prefixed names. Set their local transform before adding/enabling collision. Collision is initially disabled and enabled after the appropriate deferred/physics step, avoiding an origin collision that pushes the raft/player. Foundation registration updates grid occupancy and buoyancy-related markers. Maintain consistent ordering in build type/name/scene arrays.

Editing uses a snapshot so a moved/rotated piece can be cancelled back to its original transform and registration. Confirmation validates the edited position. Removal checks refund storage capacity. Keep occupancy/socket/support state synchronized on remove, cancel and confirm. Save logic must not serialize an incomplete edit as a permanently missing piece. Test saved structures, not just the placement preview.

## Survival, crafting tools, navigation, and enemies

Stats starts health, hunger and thirst at 100. While actual gameplay is active, hunger drains 0.10 per second and thirst 0.16 per second. Either reaching zero causes 1.5 health damage per second. Menus/test scenes must not keep draining survival values. Stat changes emit signals for the HUD; health reaching zero triggers death handling.

Food interaction consumes the selected inventory item and applies its configured reward. Current coconut rewards include 12 hunger and 28 thirst, banana 30 hunger, and fish 24 hunger. Inspect the whole interaction branch for secondary health bonuses when changing nutrition. A death-screen save is normalized to survivable values, and legacy zero-health Continue handling avoids instantly resuming into a dead game. Preserve these protections when changing respawn rules.

The Fishing Rod starts timed fishing while on raft/shore rather than swimming. Fishing requires open water and takes 4–6.5 active seconds with a 7.5-second cooldown. A completed catch adds one Fish; overflow spawns a world pickup instead of losing the reward. Spear interaction raycasts nearby sharks (current reach 5.2 m and damage 38). Consume/cooldown/target checks belong to the interaction path, not merely the visual animation.

There are three shark spawners in the gameplay scene. Sharks have 70 health, 42 m detection range, 4.1 chase speed, 1.7 patrol speed, 2.6 m bite range, and 12 bite damage. They stalk swimmers and can be repelled/killed using the spear. Life Vest is persistent equipped state and reduces incoming bite damage through the player's handler (current damage multiplier 0.38). It is not a one-use shield. Keep shark and player damage delegation consistent so vest protection is applied once.

Sail Kit and Motor Kit install raft upgrade tiers 1 and 2. Installing the same/lower tier should not waste another kit. Navigation uses the map's selected destination/course and stops near arrival. Current travel speeds are approximately 2.7 and 4.8 m/s for the two tiers, with a 14 m arrival threshold. The raft's state and the player's saved tier must stay aligned. Account for deck movement/carry when changing travel, rather than teleporting only the raft beneath a stationary player.

## Plants and planters

PlantDB definitions live in `scripts/plant_data.gd`. Potato, carrot and tomato grow in the small pot/box, while coconut and banana trees use TreePot. Each plant definition describes supported containers, stage timing, models/visual properties, yields, and chopping/regrowth behavior. The player owns contextual sow/harvest/chop interaction; Planter owns its planted instance; PlantInstance owns growth and fruit state.

Plant stages are SEED, SPROUT, GROWING, MATURE, FALLING, and STUMP. Root crops mature and are dug/harvested. Trees grow, produce individually tracked fruits that can regrow, take repeated chopping hits, fall, drop wood/fruit, and leave a removable stump. Do not turn every harvest into destruction of the whole tree or recreate all fruits whenever one is picked.

Plant saved state includes plant `id`, numeric `stage`, stage `timer`, chopping `health`, and `fruits`. A fruit record stores local position `p` (three values), rotation `r`, elapsed regrowth `e`, and regrowth interval `g`. A planter's state is nested under its building record. If saving during FALLING, the state is normalized to MATURE with health 1 so loading does not need to reconstruct an interrupted fall tween. Restore uses the same safety rule.

Adding a crop means updating PlantDB, seed/item presentation and interactions, compatibility with containers, saved-state defaults, resource yields, and practical tests for sow → grow → harvest → save/load. Adding only a model does not add playable farming.

## Sand gathering and footprints

Press Interact while aiming at a reachable, mostly upward-facing island surface (not palms/grass/beacon) to add one Sand to inventory; gathering has a short cooldown and respects bag overflow. Sand may land in a bag slot, so move it to a hotbar slot to display the sand scoop in first person. Aim at a planter with Sand selected and press Interact to apply one sandy top-dressing; the rough procedural grain material makes the added layer visible. Then select a compatible Seed and interact again to plant as before. Sand is optional, so old planting behavior and existing saves remain valid.

Planter top-dressing is serialized as an optional `sand` boolean on the existing built-piece record. Missing `sand` in legacy records means false. Footprints use 28 reusable PlaneMesh decals, alternate left/right offsets, fade over 22 seconds, and are stamped only when the player's footstep contact belongs to an island. They add no physics bodies and cast no shadows. The island continues using its existing gravel step sample; no footprints are spawned on raft boards or while swimming.

## Islands, debris, and world resources

The scene has a home island and destination islands including ReefIsle, DriftwoodCay, and FarCove. IslandSetup normalizes the source island's scale/height and shoreline, builds collision, prepares pickups and foliage, then starts grass/palm placement. The home island uses a normalized footprint around 36 m, shoreline waterline radius around 11 m, and vertical scale adjustment around 0.62. Inspect scene overrides before changing these values.

Collision preparation is asynchronous/batched. Palm/grass ground queries must wait until collision exists in the physics world. Raycasting in the same frame as creating collision can miss surfaces and place objects under water. Generated pickups use deterministic IDs; collected IDs persist in Inventory and suppress respawning on Continue. Keep IDs stable across ordinary releases or existing saves will regenerate resources.

DebrisSpawner maintains floating resource population and prewarms a useful starting set (current mobile cap 48, prewarm 24). Debris contributes Wood, Rope, Plastic and other resources according to its item configuration. Fixed island pickups may share the `debris` group but should not be frozen/reparented as hookable rigid bodies.

The home scene adds `IslandMountain` and `IslandBirds` as gameplay-detail children that are excluded from scanned-island rescaling. The peak is a deterministic, generated faceted mesh with one matching trimesh collider and a mobile-oriented procedural rock shader; the gull flock defaults to simple non-colliding geometry and can load a licensed imported GLB from its Inspector property. The supplied palm and grass GLBs are bundled; an imported gull is still optional. See `SKETCHFAB_ASSET_INTEGRATION.md` and `ASSET_CREDITS.md` for model origins and import steps.

Grass uses MultiMesh rather than separate nodes for every blade. Mobile allocation is capped at 2,400 instances per field, with batches of 64 ground rays per frame. Visible budgets are 1,600 in Auto/Balanced, 800 in Battery Saver and 2,400 in High; heavier custom meshes may further lower allocation. Quality changes adjust `visible_instance_count` without rebuilding ground queries. Battery Saver uses a 55 m visibility range; other profiles use 100 m. Convert ray-hit world positions into the MultiMesh's local space and preserve the COLOR_0 wind mask.

The default `sketchfab_grass_model` loads `models/realistic_grass.glb`: a 24-triangle tuft of six intersecting textured ribbons. Its alpha-cutout texture is forwarded to the wind shader. When that model path is blank, `natural_tufts` substitutes a shared procedural three-blade mesh for `models/grass_blade.glb`; missing custom models also fall back to procedural tufts when enabled. Blade COLOR.r carries the rooted-to-tip bend mask; INSTANCE_CUSTOM RGBA carries phase, strength, color variation and dryness. The shader creates coherent traveling gusts, slight blade droop, dark roots and leaf backlighting. Tufts shrink over 55–95 m and the field has a 100 m visibility limit to reduce distant foliage cost. Keep MultiMesh custom-data enabled before setting its instance count.

`IslandSetup` replaces the children of existing Palm nodes with the supplied coconut-palm GLB, preserving scene transforms and names. `vegetation_visual.gd` retains textured geometry and bark/collar materials, applying a cached texture-aware wind shader to `leafs`. Planter coconut trees use this GLB at their existing growth-stage heights; generated fronds and bark remain available for untextured fallback palms. Fruit sockets, chopping, growth, IDs and saves keep their existing behavior. The project still mixes scanned/textured, low-poly and procedural assets.

Mobile Auto reduces grass visibility to 65% of its normal budget when render scale falls to 0.66 or lower, restoring it after sustained recovery to 0.78 or higher. Cumulus clouds remain disabled in mobile Auto; only explicit High can restore them. HUD state/layout refresh and menu drawing run at 10 Hz with immediate event redraws; menu loading status is still polled every frame.

## Ocean, sky, rain, and visual rules

`scripts/ocean.gd` computes CPU surface heights used for swimming, floating, and hook/water behavior. `shaders/main.gdshader` moves visible water vertices. Their wave formula, time convention, amplitudes, frequencies, directions, and envelopes must agree. Raft foam also depends on water contact. Changing vertex waves without equivalent CPU math creates visible floating/swimming errors.

The earlier ripple-softening pass was followed by analytic value-noise gradients that break up the directional sine pattern. The first noise layer always runs; the second is skipped in Battery Saver using `surface_detail`. Water reflection is an angle-dependent analytic sky/cloud approximation, not screen-space reflection of trees or structures. Highlights respond to sun/moon direction and twilight haze follows the warm reflected horizon. Physics/vertex wave heights remain unchanged; `world_pos` now includes the existing displacement so view/reflection shading uses the actual surface height. Color values in the ocean shader retain their linear-color/tonemapping assumptions; blindly adding `source_color` annotations can wash out the sea. Inspect the actual rendered result after shader edits.

Ocean creates a `FarWater` child with four broad strips (eight triangles) outside the main detailed plane. The apron has a hole matching the detailed plane, avoiding an overlapping full-screen water pass. It shares the driven ocean material and extends the visible sea toward the camera's far limit. It is cosmetic distant water; detailed interaction/buoyancy still uses the existing Ocean sampler and central wave mesh.

Sky3D/TimeOfDay handles the clock, day/calendar changes, sun/sky appearance, and linked weather. Day duration defaults are supplied by the addon/scene; verify them before changing time progression or saved calendar fields. RainSystem schedules weather and checks overhead cover. Script interval defaults are 6–14 minutes, but **the main scene overrides them to 3–7 minutes, a 65% chance, and 1–2.5-minute duration**. This distinction matters: editing an exported script default may not alter an existing scene override.

First person, third person, underwater rendering, sunrise/noon/night, mobile quality, and raft motion can reveal different visual problems. Prefer changes that fit the existing palette and asset style. When adding realism, retain readable crosshair/controls and budget for mobile geometry, fill rate, shadows, texture memory, and scene load time. Do not claim desktop screenshots prove smooth Android frame rate.

### Environmental audio

`ocean_ambience.gd` keeps the existing credited recorded ocean MP3 as its primary layer. New `audio/sea_wind.wav`, `foliage_rustle.wav` and `rain_ambience.wav` are original procedural stereo sample beds, generated offline by `tools/generate_environment_audio.py` using numpy. They are not field recordings. The wind/rain loops are 16 s and the foliage loop is 12 s, at 22,050 Hz. Filtering and periodic envelopes create gentle gusts/rustling without synthesizing every sample during gameplay. Godot imports the WAVs normally; runtime duplicates the stream to set looping, leaving source resources unmodified.

Each gameplay scene creates one uniquely named `OceanEnvironment_<instance-id>` audio bus feeding Master. Ocean, wind, foliage and rain route through it; the existing settings volume/mute still applies through Master. Cached island positions are sampled every 0.15 s. The shore/foliage mix fades from full strength within 20 m of an island center to zero beyond 65 m. Open water does not play loud close-up leaves. Recorded waves gently fluctuate and become about 5 dB louder near islands.

The active camera's depth below the sampled water blends the environment into a muffled sound, transitioning over depths 0.08–0.85 m. Low-pass cutoff moves from 18 kHz to 850 Hz; wind/foliage also fade underwater. Surfacing restores clear audio. RainSystem now defaults to the generated rain stream, loops it, and fades linear amplitude toward the configurable `rain_volume_db` (default -12 dB). Custom assigned rain streams still work; optional thunder clips remain optional.

`stop_environment()` stops every ambient layer and rain; `_exit_tree()` removes only the scene's own bus. Call this before abrupt test shutdown and allow the dummy audio backend time to flush. Avoid adding effects to Master or leaving buses behind on repeated New Game/Continue transitions.

## Settings and mobile performance

GameSettings stores quality, target FPS, look speed, inverted look, volume and first/third person preference. Defaults: Auto quality, 60 FPS, look speed 1.0, non-inverted look, volume 0.8, first person. Look speed is clamped to 0.3–2.0, volume to 0–1, and FPS to 30 or 60. ConfigFile uses the `game` section in `user://settings.cfg`.

Settings runs while paused, remembers the previous pause/mouse state, releases gameplay input when opening, and restores the prior state when closing. Android Back should close the top relevant overlay/pause state predictably. Backgrounding and closing save the game. Avoid multiple nodes independently toggling pause on the same Back event.

| Quality | Initial 3D render scale | Heavy cumulus clouds | Adaptation |
| --- | --- | --- | --- |
| Auto (0) | 0.82 | Off | Adjusts to the selected FPS budget |
| Battery Saver (1) | 0.65 | Off | Fixed profile |
| Balanced (2) | 0.82 | Off | Fixed profile |
| High (3) | 1.0 | On | Fixed profile |

Auto samples frame time over 1.25 s windows, drops scale in 0.08 steps, recovers more slowly in 0.04 steps, and clamps the minimum to 0.55. The 30/60 FPS setting changes the budget. Canvas UI stays clear while 3D resolution changes. The profile also limits shadows and disables expensive effects such as glow on mobile. Current directional shadow distances differ by profile (60/35/60/90 m); inspect the exact light configuration if adjusting them.

Auto, Balanced and High use 2× MSAA for thin grass/frond edges. Battery Saver disables MSAA and skips the second ocean noise-detail layer; it keeps the natural palette, basic ripples, foliage motion and all sound/gameplay. No screen/depth-texture reflection pass or separate node per grass blade was added. Phone frame pacing still needs actual device verification.

`_last_quality` and `_last_fps` prevent unrelated settings changes (look/audio) from restarting adaptive resolution. Preserve this guard. Preview placement updates are throttled around 30 Hz, but an actual PLACE press must refresh exact validation synchronously. Performance optimizations must not turn a stale green preview into an invalid spend/placement.

## Save format and restoration

Save version is currently 1. `Inventory.save_game(extra, slot)` serializes inventory and merges player/world metadata. `load_game` restores slots, collected pickup IDs and the testing grant flag, then exposes remaining metadata for the player/world restoration. `save_info` reads labels without mutating live inventory.

Main keys:

| Key | Meaning |
| --- | --- |
| `version` | Current format marker, 1 |
| `saved_at` | Unix timestamp |
| `slots` | Array of empty arrays or `[item_name, count]` entries |
| `testing_resources_granted` | Once-per-save temporary resource grant completed |
| `collected_island_pickups` | Stable IDs already collected |
| `active_slot` | Selected hotbar slot |
| `rope_gun_selected` | Optional permanent-launcher equipped state; ownership is unconditional |
| `health`, `hunger`, `thirst` | Survival values |
| `raft_upgrade_tier` | 0, 1 sail, 2 motor |
| `life_vest_equipped` | Persistent protection/equipment flag |
| `game_time`, `game_day` | Sky clock and survival day |
| `calendar_year`, `calendar_month`, `calendar_day` | Calendar state |
| `built` | Built-piece records, including nested planter state |

Each building record has `t` (type string) and `x` (12-float raft-local Transform3D). The order is basis X column's three components, basis Y column's three, basis Z column's three, then origin XYZ. Planters optionally include `plant`. Keep basis order and local coordinates unchanged when evolving the schema. Type identifiers must still resolve to the correct scene after future refactors.

Restoration instantiates pieces with collisions disabled, sets their local transforms, and then re-enables physics after the appropriate deferred step. It recreates foundation grid registration only for foundations and reconstructs socket relationships where possible. A saved wall must not become a foundation occupancy cell. Planters restore after their owning building exists. Do not use a world transform where the file expects raft-local coordinates.

The save is JSON written directly with FileAccess; do not assume transactional backup/atomic replacement is implemented. If hardening saving later, use an explicit compatible temp/backup strategy and test interrupted writes. Current saves focus on inventory, stats, time, upgrades, collected pickup IDs and structures; do not assume every transient hook, debris, enemy, player position or raft navigation state is persisted.

Preserve unknown/optional defaults when adding fields and test an older save with missing fields. Do not clear real saves for diagnosis. Android updates retain app data when package name and signing identity match; uninstalling can remove it. Avoid changing package/signing identity for a routine bug fix. Follow `BUILD_ANDROID.md` for the installed project's current debug-signing workflow.

## Verification without exporting an APK

Run from the project directory in PowerShell using the installed matching Godot executable:

```powershell
$godot = 'C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe'
.\tools\verify_source.ps1 -GodotPath $godot
```

The helper creates `build/source-check-<unique-id>` with a copied project configuration and Windows junctions pointing to the live resource directories. It sets a unique custom user-data directory containing `MobileTests`, so tests do not reset the owner's normal saves. Staging shares source/assets/import cache and is not an independent editable project. **Never recursively delete contents through its junctions; they point to the real project.** If cleaning stages, remove only verified stage files and junction entries using junction-safe operations.

The default suite runs these scripts:

| Test | Current checks | Coverage |
| --- | --- | --- |
| `tests/mobile_smoke.gd` | 93 | Scene/menu flow, touch routing, held actions, UI, inventory, construction, climbing, save/pause/settings |
| `tests/foundation_smoke.gd` | 17 | Keyboard/mobile foundation placement, transforms, costs, optional socket metadata, saved structures |
| `tests/testing_resources_smoke.gd` | 11 | 2,000 grants, stack handling, spend, New Game, once-per-save persistence |
| `tests/rope_smoke.gd` | 20 | Launcher/muzzle, touch charging, quick/long cast, arc/range, rope geometry, catch release, return, camera/hotbar/build interactions |
| `tests/environment_smoke.gd` | 41 | Environmental sound, imported foliage/textures, shared trunk collision, mobile grass budgets/recovery, saved planter coconut restoration, Auto cloud recovery, mountain/birds/footprints/sand, water/AA profiles, audio cleanup and menu preloading |
| `tests/island_marker_smoke.gd` | 23 | Front/offscreen/behind targets, camera-plane/extreme projection, edge styles, arrival fade, tiny viewport and modal hide/restore; can also run natively to check real polygon drawing |
| `tests/menu_loading_smoke.gd` | 21 | Simulated 120-second active loads, cancellation for all three save choices, repeated presses, untouched saves/inventory, late completion and retry |

| `tests/survival_loop_smoke.gd` | 42 | Real stair ascent/descent/rotation, jump apex, construction and saved prop state, farming, cooking, rain, birds, bow release/cancellation and capacity-safe rewards |

Logs are `build/source-<test_name>.log` and the matching `-console.log`. The helper captures both engine logs and console output, including shutdown errors after the engine closes its log. It requires a successful process exit, a checks/zero-failures summary, and no SCRIPT ERROR, ERROR, or FAIL text. Godot file logs may still be shared with an open process, so the helper reads with FileShare.ReadWrite. New assets may need the normal editor import before testing. Keep tests guarded against running on the real user-data path.

For a focused rerun:

```powershell
.\tools\verify_source.ps1 -GodotPath $godot -Tests @('rope_smoke.gd')
```

Tests simulate frame/input timing intentionally. Some scripts disable physics or survival drain to make a specific assertion deterministic. Preserve test frame boundaries and input release cleanup when editing them. A headless run checks logic and scene loading but not final rendered geometry or actual phone performance.

The scene-based tests stop ocean playback before shutdown to let the dummy audio backend release its stream. The rapid scene-switch mobile suite can still report RefCounted ObjectDB warnings at engine exit despite all assertions passing. These warnings are not a failed scene load, but they are not evidence of clean long-session memory behavior either; investigate with profiling if working on lifecycle/memory usage.

### Visual review

`tests/rope_visual_preview.gd` captures first person, casting, and third person from an isolated source-test project. It uses the real main scene and forces mobile UI/profile. Current captures:

- `build/rope-launcher-first-person.png`
- `build/rope-launcher-casting.png`
- `build/rope-launcher-third-person.png`

Use the unique staged project from source verification, a hidden/offscreen native Godot process, the Mobile renderer, and a 1280 × 720 window to run this script. Use `Start-Process -WindowStyle Hidden` if launching it through PowerShell. Check the PNGs and `build/rope-visual.log` for shader/mesh errors. These are desktop-rendered previews; obtain phone evidence separately before promising a frame rate.

## Manual Android export and package checking

Only export when the owner asks or does it themselves. `BUILD_ANDROID.md` has the full workflow. Reload editor export settings to avoid restoring stale exclusions, retain necessary imported scene textures, and use Godot 4.7.1 with matching Android templates/SDK/JDK and the existing signing key.

On 2026-10-02 the editor-written preset had reverted to version code 3 and the old required-texture exclusions. It was corrected again to version code 5/name 1.1.2, the updated APK output path, and exclusions for build/tests/tools without excluding required island textures. Close and reopen the project before manual editor export, then check the exclusion field and version in Project → Export. No APK was rebuilt as part of this settings correction.

When an APK has already been exported, verify that package rather than relying on the source suite:

```powershell
.\tools\verify_android.ps1 -ApkPath .\build\OceanSurvival-updated.apk -GodotPath $godot
```

This extracts packaged data and runs mobile/foundation verification in isolated test storage. It currently covers those two suites, not automatically the new rope/testing-resources suites. Do not claim the final APK includes or passes a source change until checking a freshly built package. Build outputs, test files and asset-download tools are intentionally excluded from production exports.

An installation attempt without an attached authorized Android device cannot confirm gameplay on that phone. For on-device testing, check New Game/Continue to full scene entry, joystick+look+held hook together, every visible button, build/craft/edit/remove, inventory drag, pause/back/background, settings, and saved structures after restarting. Check frame pacing in Auto/Battery/Balanced and realistic longer play, not just an empty scene at startup.

## How future AIs should make changes

1. Read this guide, `AGENTS.md`, the latest owner messages, and the relevant live files. Check working-tree changes and preserve unrelated work. The most recent owner instruction defines the task scope.
2. Trace the actual scene/input/save call path for the requested behavior. Search names with `rg`; large player/HUD scripts have related logic in several sections.
3. Make the smallest coherent change that addresses the request. Do not silently alter testing defaults, recipes, package identity, signing, controls, or save semantics.
4. Keep UI descriptions consistent with behavior. Update first/third person, touch/keyboard, save/load, and capacity/error feedback paths affected by the change.
5. Run the meaningful affected source suites in isolated data storage. Render-check visual changes. Verify a real APK only after one is authorized/exported; use phone evidence for performance claims.
6. Update this guide and any affected build/asset notes. Tell the owner what changed, what passed, and what remains unverified. Do not export simply because code changed.

### Adding a construction piece

Create the scene/collision/socket setup, register its type/name/scene consistently in the player, add the exact recipe, icon/selector presentation and preview rules, define support/occupancy behavior, and confirm unique saved type resolution. Test valid/invalid placement, affordability, edits/removal/refunds, and save/load. Do not append an entry to only one of parallel build arrays.

### Adding a craftable handheld item

Add the exact spaced item identifier to ITEM_RECIPES and relevant icons, hand visual, interaction/context hint, hotbar selection, capacity-safe rewards/costs, and saved compatibility. If it uses a projectile or new held action, route touch ownership/release and camera-mode origin through existing helpers. Test switching away mid-action and loading a save with the new item.

### Changing graphics or ocean behavior

For cosmetic ocean changes prefer fragment/material tuning when physics should remain the same. For vertex wave changes update CPU sampling and dependent foam/contact math together. Batch repeated mesh instances/materials, cap mobile populations, and compare all quality profiles. Keep launch-muzzle position and triangle winding correct for launcher changes.

### Changing saved data

Add optional fields with backwards-compatible defaults and isolate tests. For renamed item/build identifiers provide a migration. For stack-limit changes account for old large stacks and limited slots. For a new schema version define detection/migration/failure behavior before writing it. Never use the owner's actual save as a resettable test fixture.

## Known limits and remaining polish

- Current 2,000 resource supplies are intentionally temporary testing defaults; normal survival balance needs that flag disabled when the owner requests it.
- Shared surface detail, recognizable resource props, textured palms/grass and revised UI improve realism. Existing low-poly and procedural geometry remains; this is not a complete photogrammetry asset replacement. Phone testing is required to assess freezes and frame pacing.
- Source logic and desktop Mobile-renderer screenshots passed; Android FPS, thermals and device-specific controls still require the owner's phone testing.
- The older APK in `build` does not contain all latest source changes. The owner currently controls exporting.
- Legacy scene/recipe entries are not necessarily active features; check the player registry and interactions before promising them.
- Save files do not persist every transient world object/navigation state. If the owner asks for stronger world persistence, implement and test it explicitly.
- The guide describes the source on its update date. Future changes must refresh it; historical documentation snapshots can be stale.

## Asset provenance and generated work

Read `ASSET_CREDITS.md` for downloaded model/audio/texture origins and licensing details. Existing project assets include documented Kenney/Quaternius and other credited sources; do not invent permissions for files not documented there. The rope launcher/hook/hand meshes and fiber shader added in this update are original procedural project code. No art was copied from the reference game's Play Store listing.

`tests/realism_visual_preview.gd` is an isolated-data desktop preview that captures `build/realism-{menu,hud,inventory,crafting,settings,island,objects}.png`. Pass `-- --menu-only` for the menu alone. Run against a source-test staging project with normal Godot imports. New surface/UI detail is original shader/geometry code and adds no external textures; all required existing island and foliage textures must remain included in exports.

This guide deliberately documents contracts, files, constants and dependencies rather than embedding full copies of every script. Open the linked project files for exact functions; duplicated source snapshots rapidly become inaccurate after fixes.

The latest environment previews are generated by `tests/environment_visual_preview.gd` using isolated test storage and the desktop Mobile/D3D12 renderer. It checks grass custom-data readback in the real renderer (the headless dummy renderer cannot read that buffer), then captures `build/environment-raft.png`, `environment-island.png`, `environment-grass.png` and `environment-sunset.png`. Sound checks verify transitions/looping/routing; they do not establish listening quality on a phone speaker/headphones. Shader and audio API details were checked against the official [Godot spatial shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html), [AudioStreamWAV](https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html), and [audio filter reference](https://docs.godotengine.org/en/stable/classes/class_audioeffectfilter.html).

## Farming, hunting, cooking and weather update (2026-10-03)

Build Mode NEXT/Q now cycles eleven pieces. Existing indexes 0–8 stay unchanged; Bonfire and RainCollector are appended. Bonfire costs 8 Wood + 4 Stone; RainCollector costs 6 Wood + 1 Barrel + 2 Rope. Raft/foundation top sockets accept both. Roof top sockets also accept them and the three planters. Six quick building icons stay unchanged; the selected caption now covers all eleven pieces.

New Game includes 4 Carrot Seed and 4 Tomato Seed in the bag. Equip a seed and use HAND/E on an empty pot/box. Potato takes 60 active seconds to mature and carrot/tomato 80 at full growth speed. Harvest yields 2–4 food and 2 replacement seeds, checking capacity for the complete reward. Planters start at 75% moisture, dry by 0.2 percentage points per active second, and grow at one quarter speed below 15%. Exposed rain restores 5 points per second; equipping Water and using the planter restores 75 points. The planter boxes now have actual walls and visible soil rather than solid cuboids.

Craft Bow (5 Wood + 3 Rope) and Arrow (1 Wood + 1 Stone each). Equip Bow, hold HAND/E to draw for up to 1.1 seconds, then release. One arrow is used per shot, with gravity, a 4-second lifetime and a maximum of 12 active projectiles. Opening a panel, pausing, changing equipment or building cancels a draw without firing. Four animated gull GLBs circle the home island, fall when hit and drop Raw Bird. Each bird repopulates after 100–180 active seconds. A nearby four-fish shoal uses the original fish GLB, with no collision bodies or shadows.

Fishing requires a clear downward ray to open ocean 2–28 m away, while on shore/raft. A float and sagging line show the cast. Catch delay is 4–6.5 active seconds with a 7.5-second cooldown. Swimming or changing equipment cancels fishing. Full bags drop caught fish nearby. Raw Fish restores 10 hunger; Cooked Fish 40, Roast Bird 38, Baked Potato 30, Carrot 14, Tomato 18, and raw Potato 10. Water restores 35 thirst.

Bonfire starts with 180 seconds of fuel. Equip Wood and use it for another 90 seconds, up to 900. Equip Fish, Raw Bird or Potato and use a lit fire to cook for 12 active seconds. Raw food stays in inventory until a capacity-safe exchange succeeds; full bags never lose an ingredient. Exposed rain extinguishes fire; a solid overhead roof shelters it. RainCollector gathers one Water per 20 exposed rain seconds, up to twelve. Use it to transfer water to the bag, then drink it or water crops.

The scene sets an 18-minute active day. Rain checks every 3–7 active minutes, with a 65% chance and 1–2.5-minute duration. TimeOfDay now accumulates processed delta, preventing a daylight jump after pause. Rain duration also uses active delta. Optional save metadata weather stores raining, remaining and next_check. Planter built-piece records add optional moisture, defaulting to 0.75 for old saves. Fire/collector records add optional survival dictionaries for fuel/burning/cook/item and water/seconds. Existing transforms, type strings, inventory and save versions remain compatible.

Stairs now have twelve 22 cm visual treads and one continuous walkable collider that meets the landing top. Floor snap is 0.32 m; maximum curb step is 0.30 m with clearance/landing checks. Land jump velocity is 4.5 with gravity 18 (about 0.56 m apex), water jump 2.8 and held swim-up speed 2.0. Existing stair sockets/transforms are retained.

First-person equipment now uses the original human-hand GLB; old arm/fist boxes are hidden. New fish, gull, hand, bow and coastal ridge GLBs are original CC0 modeled assets, generated offline by tools/generate_survival_models.gd and merged by material. Gull wing pivots remain animated. See models/ORIGINAL_SURVIVAL_ASSETS_LICENSE.md. The supplied textured palm/grass remain under their separately recorded licenses. These original models are not photographic scans.

scripts/survival_equipment.gd owns bow cancellation, arrow physics and fishing visuals. scripts/campfire.gd and rain_collector.gd own prop state/use. tests/survival_loop_smoke.gd is included in tools/verify_source.ps1; it checks movement, real construction, saved state, farming, weather, food capacity and equipment. tests/survival_visual_preview.gd captures build/survival-{crafting,hand-fish,bow,island,garden-fire,rain}.png in isolated storage, plus controls/bag screenshots. The verbose desktop inventory label is now shown only when debug_building is enabled.


### Contextual touch interface (2026-10-03)

The joystick is hidden at rest and appears while the player touches the bottom-left movement zone; that zone remains fixed so other touches still look around. RUN appears during movement; DIVE/CLIMB require swimming and a nearby ledge respectively. CAST is available in normal play and equips the permanent gun; RECALL requires an active hook. USE appears for nearby usable objects or usable equipped food, water, fishing rod or bow, with EAT/DRINK/FISH/DRAW/PLANT/HARVEST captions. Planter/plant/door actions require actual interaction reach. BUILD appears near the raft, nearby editable support, or while building/editing; placement/rotation/next/removal appear only in their modes. Jump, bag, pause and help remain discoverable essentials. Held actions release when context vanishes; all gameplay art hides during modal panels and redraws when the panel closes.

MAP and CRAFT are tabs inside the bag, above the inventory grid, instead of persistent gameplay buttons. Desktop M/C shortcuts still work. The bag has a larger header to keep those tabs separate from drag slots, close and Quick Save. Existing finger ownership and inventory drag behavior remain intact.

New games begin with four Carrot Seed and four Tomato Seed in the bag. Existing saves can find four of each in separately identified home-island seed caches. These cache IDs do not change the twelve legacy pickup IDs, and collected caches use the existing persistent pickup record. Only newly authored GLBs are CC0; supplied palm/grass keep their recorded licenses.


### Scene-load preparation workaround

A subsequent fresh mobile recheck reproduced an intermittent threaded scene-loading stall after the eight-suite pass. The menu now prepares and retains its 30 gameplay script dependencies on the main thread, one per frame, before starting the background scene request. The menu renders first and can accept cancellation while preparation continues; the status poll waits for preparation to finish instead of treating an unstarted request as a missing resource. Progress reserves the first 15 percent for preparation. New Game/Continue still only modify player data after successful resource loading. This avoids overlapping script/scene preload work on loader threads; the engine issue is a probable explanation rather than a traced engine backtrace: https://github.com/godotengine/godot/issues/120827. After this workaround, the 92 mobile and 21 loading checks were rerun successfully in fresh isolated storage. Individual script preparation can still cause a short frame delay on a slow device. Real-phone loading/performance remains unverified.

The final desktop Mobile/D3D12 menu-only preview also completed the actual background scene load with all 30 script dependencies prepared, with no engine/script errors (build/menu-prepared-render.log). The final survival preview produced all eight captures without engine/script errors; controls returned after modal panels closed. These checks used isolated storage and do not verify a phone or exported APK.


### Reported pause error, warnings and startup hitches (2026-10-03)

Fixed SurvivalHUD's Pause → Quit null viewport error by consuming the pointer before changing scenes. Death keyboard/pointer exits follow the same order, and a guarded input helper tolerates a HUD already detached from its viewport. The mobile regression now clicks the real pause-menu Quit button through viewport routing instead of invoking Quit directly; it verifies the main menu and saved progress.

IslandGrass uses explicit floating-point ratios with floori for triangle budgets, removing the INTEGER_DIVISION warning without disabling it. Player's fishing_ocean local no longer shadows the ocean field. Palm import/visual preparation now yields between trees, with scene-owned temporary templates and teardown checks. Android grass generation yields after 16 terrain queries per island (desktop remains 64); density ceilings, shared shapes and quality switching stay intact. Pickups wait for the actual island setup controller, including the home island's sibling controller, so an early mountain collider cannot cause seeds to miss the terrain. The environment regression checks both home crop caches.

Current targeted verification passed 197 checks: 93 mobile, 41 environment, 42 survival-loop and 21 menu-loading. Godot's isolated editor scan completed without reported errors. Existing saves and the once-per-save testing materials remain unchanged. No APK was exported and phone FPS is unverified. For the owner's Xiaomi 11 Lite-class phone, start Battery Saver at 30 FPS, then try Balanced only after the installed APK is stable. Re-export source changes manually; an older APK will retain older code.

The 41 environment checks also passed with INTEGER_DIVISION, SHADOWED_VARIABLE and SHADOWED_VARIABLE_BASE_CLASS promoted to errors in the isolated test project's override.cfg; the original test override was restored afterward. The owner project's warnings were not suppressed. Strict-check logs are build/source-strict-warnings.log and -console.log. One shutdown-only ObjectDB leak warning remains; there were no script/engine ERROR lines in these checks.

### Bag and equipment artwork (2026-10-05)

The bag, hotbar, drag ghost, resource pills and crafting cards now share original textured item artwork through `scripts/item_art.gd` and `textures/ui/survival_items.png`. The sheet contains 29 resource/food/equipment/seed icons and a canvas backpack. Long equipment uses tight UV silhouettes to avoid sampling neighboring objects. Unknown items retain the existing vector fallback. This changes inventory images only; held 3D equipment is unchanged.

The bag has larger inset slots, a muted canvas-colored panel with seams, readable item captions and upper-right quantity badges. Selection, drag/swap, Quick Save, map/craft tabs and authoritative slots keep their existing routing and saved identifiers. The original generated-art provenance and generation prompt are recorded in `textures/ui/ARTWORK.md`; the atlas is a referenced import dependency for manual Android exports. No export preset changes are needed. `tests/inventory_art_preview.gd` renders the actual HUD in isolated MobileTests storage without loading the world, producing `build/inventory-art-{bag,craft,hotbar}.png`.

### Bow hunting controls (2026-10-05)

Equipping Bow now exposes separate AIM and SHOOT touch buttons, including when out of arrows. Tap AIM to toggle a 48-degree camera zoom and 55% look sensitivity, then drag the view to aim. Hold SHOOT to draw (1.1 seconds to full power), release to fire one arrow; arrows can remain in bag slots. The center reticle adds precision ticks, draw progress and an ammunition count/instruction. SHOOT touch-down starts drawing immediately and keeps the existing owned `interact` action held. Canceled touches or dragging off SHOOT cancel the draw without firing; normal releases fire. Empty ammo shows CRAFT ARROWS FIRST.

Aiming clears and restores the prior FOV on input reset, bag/map/craft/help/settings/pause, focus loss, equipment change or build mode. First/third-person mode remains selected. The bow's SHOOT action takes priority over nearby sand, planter, door, pickup and double-edit interactions; CLIMB retains its dedicated control. Hunting help explains crafting, selecting the Bow, aiming, leading birds, shooting and collecting/cooking their drops. Aim state is transient and adds no save fields. Existing desktop E hold/release remains supported.

Final targeted source verification: 93 mobile checks and 53 survival-loop checks passed (146 total). Added hunting checks exercise AIM touch/cancel, real camera FOV/look sensitivity, owned SHOOT draw/cancel, no-ammo discoverability, modal/equipment restoration and an actual flying-arrow ray hitting a gull Area3D. Desktop Mobile renderer previews verify presentation only; no phone test or APK export was performed.

### Rope launcher identification and ocean-themed bag tabs (2026-10-05)

Rope in hotbar slots 0–5 now displays an original realistic rope-launcher image and the bag's equipped row caption reads Rope Gun. The CAST button uses the same image, making the held launcher recognizable. Bag storage slots, crafting costs and resource pills still display coiled rope as the material. `scripts/item_art.gd` selects this presentation without renaming Rope in inventory or saves, adding a recipe or changing quantities. Launcher geometry, launch muzzle, casting and first/third-person behavior stay unchanged.

MAP and CRAFT inside the bag now use weathered teal/wood plates, brass rims/rivets and wave etching. MAP has a folded chart with island contours, dotted course and compass, plus ISLAND CHART; CRAFT has crossed salvage tools with rope-wrapped wood and steel, plus SURVIVAL GEAR. Their original hit rectangles and touch routing are retained. Original art provenance and the exact ImageGen launcher prompt are in `textures/ui/ARTWORK.md`. The referenced PNG imports with the project for the owner's manual export.
Verification for the rope-gun image and nautical tabs: 93 mobile checks and 20 rope checks passed (113 total); the actual HUD bag/crafting/hotbar previews rendered with no script/engine errors. No APK was exported and phone appearance/performance was not tested.

### Permanent rope gun (2026-10-05)

The rope gun is now always-owned player equipment outside the 30 draggable inventory slots. CAST is always visible in normal play and equips the launcher before charging; desktop Q also equips it. Selecting another hotbar item still equips that item, while CAST returns to the gun. Rope materials can be moved or spent without removing the gun, and equipping it never occupies/displaces a slot, including with a full bag. Inventory Rope pictures remain coils; the bag footer shows a fixed Rope Gun / Permanent badge outside the drag grid. This supersedes the earlier hotbar Rope Gun picture mapping.

Player owns `rope_gun_selected`, and inventory changes preserve that equipment selection. CAST cancels an active bow draw/aim before switching. First/third-person launcher visuals and muzzle origins are retained. Saves add optional `rope_gun_selected` for the equipped state; ownership is unconditional for both New Game and Continue. Missing fields on legacy saves preserve the previous hotbar selection while providing the gun through CAST. No existing slot/material/recipe identifiers or quantities change, and testing supplies remain 2,000 once per save.
Permanent-equipment verification passed 173 checks: 27 rope, 93 mobile and 53 survival-loop checks, using isolated test storage. Coverage includes spent rope, inventory dragging, full-bag preservation, new/legacy save restoration and bow/touch switching. The actual bag renderer preview showed the fixed permanent badge without script/engine errors. No APK was exported or phone tested.

## Advanced mission, water, electricity and wildlife update (2026-10-05)

Read ADVANCED_SURVIVAL.md for the level requirements, machine recipes/use, controls, simulation rates and remaining scope. This source update adds six saved activity-based mission levels, fuel-fired seawater distillation, wind generation/battery storage, electric lamps, powered water purification and SOS transmission. Advanced recipes unlock at levels 2–5; existing base crafting and owned equipment remain usable. Testing supplies do not advance missions.

Player creates SurvivalProgression and IslandWildlife children. Progression records successful inventory crafts and confirmed construction, and machines record actual water collection, generated power and radio transmission. Progression is optional saved metadata under progression; wildlife uses optional wildlife with stable island/index IDs. The population manager retains loaded records before asynchronous terrain placement finishes, preventing an early save from erasing delayed wildlife state. New machinery uses ordinary built-piece survival dictionaries and the existing support/transform/restore paths. Build identifiers 0–10 remain unchanged; WaterPurifier, WindGenerator, ElectricLamp, ElectricPurifier and RescueRadio append indexes 11–15. The existing six quick construction icons remain; NEXT/Q cycles all sixteen.

Conditions add underwater oxygen/drowning, stamina-driven sprint/swim exhaustion and wetness. Bandage restores 25 health; Diving Tank unlocks at level 4, equips once, and slows oxygen loss. Both have real crafting/use and hand visuals. Mission status and condition values appear in the existing HUD without taking touch ownership. UI updates retain the existing throttling. Gameplay pause stops the new systems; full inventory preserves finished water and cooking ingredients.

Original wild_boar.glb, sea_turtle.glb and shore_crab.glb add four bounded wildlife actors per island; nearby AI flees, boars retaliate when injured, lit fires repel approach and storms stop roaming. Distant actors suspend movement after 65 m. Both spear and bow use real collision damage. Raw Meat/Raw Crab cook into 45/28-hunger meals. Animal health and 240-second respawn timers restore through optional saved state. Original reef_shark.glb replaces the earlier cone-fin/sphere shark visuals while retaining attack, spear, collision and health behaviour. Original raw_meat.glb, cooked_meat.glb and diving_tank.glb identify the new pickups/held equipment correctly. These are original modeled assets, not photographic scans. See models/ORIGINAL_SURVIVAL_ASSETS_LICENSE.md and ASSET_CREDITS.md.

Machine bodies have shared cached meshes/materials, 1 Hz simulation and no shadowed dynamic lights. Nearby rotor animation and animal physics are bounded by visibility distance. This is an implemented survival expansion, not all 106 feature categories from the pasted full-game design. ADVANCED_SURVIVAL.md lists the remaining terrain, biome, ecology, NPC, medical and art-production systems accurately. No APK is exported by this source update; the owner builds it manually.

## Flooded world, torch and rain storage (2026-10-05)

Current solo-survivor behavior and controls are detailed in ADVANCED_SURVIVAL.md. New Game uses scripts/flooded_world_intro.gd over the loading menu: four photographic story frames, 20 seconds, SKIP STORY and BACK TO MENU. Continue bypasses it. The menu preserves selection/cancellation and saves until a successful transition. Headless menu checks bypass presentation; native preview checks exercise the atlas renderer. The 95-percent flood is narrative context. NPC survivors and underwater cities are future scope.

Torch is the tenth portable crafting card (2 Wood, 1 Rope). Equip from the hotbar and LIGHT within 3 m of a lit campfire; 1 Wood gives 180 held seconds. PUT OUT extinguishes. Swimming or exposed rain extinguishes; solid roofs shelter. Both camera views retain their normal visuals. The progression child is now Node3D to own shadowless torch light, third-person torch and cached spatial fire audio. Optional progression.torch_fuel restores to zero for old saves. Exposed rain increases wetness; held fire speeds drying.

RainCollector capacity is now 12 saved portions; collection remains 20 exposed rain seconds each, and transfer remains capacity safe. Water surface fill follows saved contents. IslandBirds.flight_position retains hunt dictionary keys/state but uses staggered shore/sea journeys rather than fixed circles. Population stays bounded. Original cached survival_audio.gd fire crackle is synthesized, while ocean and movement recordings retain their existing provenance. Native item thumbnails and the generated opening atlas are in textures/ui; their creation notes are in textures/ui/FLOODED_WORLD_ART.md.

Final 2026-10-05 source verification: nine isolated suites passed 350 checks (27 rope, 11 supplies, 93 mobile, 17 foundation, 41 environment, 23 marker, 21 menu, 53 survival loop and 64 advanced survival). A subsequent touch-opening check is recorded with the final validation. Tests include all five machine previews, exact construction costs and real Continue restoration. This is source verification, not phone or APK verification.

### Narrated opening, dawn handoff and timber raft (2026-10-05 latest)

The opening now uses four prerecorded English narration clips, spoken by the installed Windows Microsoft David Desktop synthesizer, with original generated approach/impact effects and the existing licensed ocean recording. It is synthetic narration, not a human voice actor. Each shot lasts at least its audio length plus 0.85 seconds (minimum 5 s), so the roughly 26-second story finishes its words before changing shots. Buttons use the ocean UI theme and are positioned in _ready before first input. Existing volume/mute applies to the Master bus.

On successful New Game entry after the cinematic, scripts/wake_transition.gd carries the final raft image in a temporary root CanvasLayer above the new scene. It waits for the player and initial frames, fades through black into dawn gameplay over two seconds, holds player movement/HUD/survival drain, then restores them. Failure/cancellation removes the overlay and preserves the existing menu/save rollback. Continue bypasses both cinematic and dawn override, restoring its saved time. No persisted cinematic flag is added.

The starter raft's old box mesh is hidden while its 2x2 m physics, grid/support sockets and buoyancy remain. scripts/starter_raft_visual.gd supplies nine batched rounded logs, two cross-poles, visible rope lashings and a small ragged cloth on a mast. The cloth is visual only; navigation still requires the existing Sail Kit/Motor Kit. Sail Kit hides the display rig and installs its functioning upgrade visual. Foundation decks use the shared generated weathered timber texture through wood_planks.gdshader; logs use raft_timber.gdshader with cut-end rings. Imported-resource shader parameters are static and geometry is built once per raft, not per frame. Required island export textures remain untouched.

Latest complete verification: all ten isolated source suites passed 367 checks (the nine-suite 350 plus 17 cinematic/raft checks). Desktop Mobile/D3D12 previews covered four story shots, the rounded starter raft, foundation surfaces, crafting and wildlife. A native New Game → touch Skip → dawn handoff → playable controls probe also passed. These checks do not prove Android FPS, a fresh APK, or complete photorealism of every existing asset. No APK was exported.


Story arrival now explicitly uses first person to match the cinematic hands/raft shot; CAMERA still switches to third person normally. Continue retains the usual camera setting. The final focused source check covers this arrival and both camera/touch modes.

## Complete narration, hand grip and distant island groves (2026-10-05)

The New Game intro now reads the full displayed text in all four shots, using four locally recorded synthesized voice clips. Shot progression requires AudioStreamPlayer.finished and the minimum shot duration; a slow loading frame cannot skip narration. Wrapped captions display complete paragraphs. Native full-play verification covers all four clip starts and finishes, followed by dawn handoff and released movement. The art remains four photographic-style shots with pan/fades, rather than an animated 3D film.

The third-person rope launcher now follows BeachSurvivor's animated Wrist.R, including wrist orientation, through rope_hand_grip.gd. Imported armature scale is removed from the weapon transform. First-person skin geometry forms a wrapped pistol grip and connected forearm in one batch; hook launch origins continue using the actual visible muzzle. The permanent gun and its no-drop inventory rules are unchanged. The decorative cloth is at the raft's aft edge so it no longer blocks the initial held-gun view.

New worlds use island_layout.gd: Home Isle (280,-560), Reef Isle (-820,570), Driftwood Cay (-1000,-820), Far Cove (1380,950), in X/Z metres. Their starting distances are approximately 626, 999, 1293 and 1675 metres. Optional saved island_layout=1 retains this layout on Continue; missing layout on an existing nonempty legacy save selects 0 and retains its original scene coordinates. New games select 1. Existing resource IDs, built raft-local transforms, navigation speeds and actual owner saves are preserved.

Each island adds CoastalGrove: two harvestable bananas, two harvestable coconuts and four textured coastal broadleaf/shade trees. Banana planter visuals also use the new curved textured leaves and pseudostem. Existing coconut palms keep the supplied textured GLB. Original meshes/materials share one 1254-square atlas; foliage culls at 120 metres, decorative bark at 240 metres. Eight grove trees per island are created over separate frames after terrain collision is ready; new groves are excluded from island scan rescaling/material replacement/collision cooking. Decorative shade trees have simple trunk colliders. Plant interaction/growth updates sleep beyond 85 metres and elapsed fruit regrowth catches up on return. Shadow casting is disabled for new textured leaf geometry.

Optional saved island_groves is keyed by stable scene island name, then tree name. It stores existing PlantInstance state (stage, chopping health, fruit slots and regrowth) and a removed tombstone after stump removal. Saves merge incompletely initialized groves with prior records so early saving cannot discard delayed trees. Distant fruit elapsed time is included when saving. No normal user data was reset.

Verification: the full isolated suite passed 394 checks; final focused checks added legacy-location and removed-tree assertions, bringing the combined current coverage to 396 checks (world_visual_smoke 28, cinematic_raft_smoke 18; remaining suites unchanged). Native Mobile-renderer previews inspected both hand views and leaf/bark textures. Full native intro played all four voice clips to completion and reached playable dawn. The full-story native shutdown reported one ObjectDB warning; the final world visual preview closed without engine errors. These checks do not establish phone FPS, thermals or touch behavior on a real Android device. No APK was built; export manually after editor resource imports refresh.

New asset prompt/provenance: textures/ui/COASTAL_TREE_ART.md. Current previews: build/updated-gun-hand-first-person.png, updated-gun-hand-third-person.png, updated-island-trees.png and updated-banana-texture.png.
