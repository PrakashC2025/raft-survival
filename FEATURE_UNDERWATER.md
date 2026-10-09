# Diving, swimming and water contact — 2026-10-09

This extends the existing game, retains version-1 saves and does not export an APK.

## Playing

- Crafting starts with **Hand Fire Torch, Bonfire and Handmade Air Tank**. Their identifiers remain Torch, Bonfire and Diving Tank. Light the handheld torch at a burning bonfire; existing dawn/rain rules remain.
- The plastic tank costs **8 Plastic + 3 Rope + 2 Metal** and is available at level 1. Select it and EQUIP. It supplies **180 active underwater seconds**; surface before breath runs out. With empty hands on dry land/deck, REFILL AIR starts a **six-second manual pump**. Moving away, entering water, damage, menus, pause or lost focus cancels unfinished pumping. AIR m:ss appears beside breath/stamina; low air blinks. The canister, straps and hose appear on the back, with a matching inventory picture.
- Look up/down while moving forward to swim in that direction. JUMP swims up; DIVE/Ctrl swims down. Maximum depth is 70 m. First person alternates hand strokes; third person uses a forward lean, alternating arm recovery, elbow bend and flutter kicks. Collision remains upright.
- Aim a spear at a fish/crab/turtle/ray and HUNT. Damage commits at 57% of the thrust; changing equipment/target/reach, damage or a modal cancels an unfinished hit. Fish/rays give Fish, crabs give Raw Crab, turtles give Raw Meat. A full bag preserves the animal. Catches regenerate after 600 active seconds. Existing bow collisions also deliver damage.
- Aim at the real ocean sand floor to COLLECT SAND. A shovel gives three sand at contact, with capacity protection.
- The map lists **seven islands and three diving sites**. The cyan player arrow follows position and direction; selection uses the nearest marker and labels avoid overlap. Spring Isle (600,1100) has flowers, clearable owner-kit plants, regrowing trees and planted-crop priority. Winter gains blue ice outcrops. Dive sites: Sunken Harbour (-100,-180), Deep City (-650,-480), Reef Garden (140,80). Their markers accept sailing courses. Original four island placements and Volcano/Winter coordinates remain.
- Sharks patrol around 110 m from the raft and avoid close swimmers outside encounters. Levels 1–5 cannot be bitten. At level 6, after 25 seconds swimming and the initial 210–360-second cooldown, nearby sharks have an 8% encounter chance per 30-second check. Encounters last up to nine seconds, end after one bite and share a three-minute spawner cooldown. Falling in water alone starts no attack. Vest protection remains.
- Raft centre freeboard is **4.5 cm**, settling response 9/second, with 3.5–8.5 cm bounds above its sampled supporting crest. Log undersides remain immersed. Expansion probes, leveling and synchronized wave time remain. Debris current is **0.32 m/s**, with bounded variation, small side drift and restrained rotation. Hooked reeling remains unchanged.

## Rendering and saves

The 4,200 m square floor uses 4,225 vertices/8,192 triangles. Two submerged neighbourhoods contain 18 broken building frames with real openings/collision and one merged wall draw per building. Three shared batches render 240 curved, veined kelp tufts. Three nearby instanced schools add 72 background fish; 30 huntable fish/crab/turtle/ray actors animate tails, legs, flippers or fins. Distant AI stops past 100 m; shoals update at 10 Hz nearby. Setup yields through the shared frame budget.

Existing CC0 scans texture sand/masonry. Surface shaders add caustics and distance tint. A deep-water background prevents sky/stars leaking through the underwater horizon and restores the sky on surfacing. Tint stays behind readable HUD. Mobile environment fog/smoke remains disabled. These are original modeled visuals in the existing art style; source checks do not establish film-quality graphics or phone FPS.

Optional `progression.air_tank_seconds` is finite and bounded 0–180; older equipped tanks receive a full charge. `underwater_creatures` maps stable site/index IDs to finite health and 0–600 respawn values. Fields remain optional and validated for old saves. Saving retains delayed world records. Verification preserves actual player saves.

New scripts: `dive_visual.gd`, `seabed.gd`, `dive_creature.gd`, `sea_fauna_visual.gd`, `underwater_shoal.gd`, `underwater_world.gd`. Shaders: `shark_skin.gdshader`, `undersea_surface.gdshader`, `sea_plants.gdshader`. Art: `textures/underwater/kelp.svg`, `textures/ui/food/diving_tank.png`. Main scene, biome island, ocean, player, action/tools, progression, HUD, spawner, loader and save validator integrate these. Asset provenance is in ASSET_CREDITS.md.

## Verification

`tools/verify_underwater_update.ps1` passed **556 checks across 12 isolated source suites**. `tools/preview_survival_update.ps1 -TestScript underwater_expansion_smoke.gd` passed **71 checks** with the Mobile/D3D12 desktop renderer. Screenshots were inspected. Preview files: `build/underwater-{map,spear,ruins,reef,swimmer,spring,craft,raft-waterline,shark}.png`.

On the owner's manually exported phone build, check New Game/Continue, walking/turning, both swim camera modes, touch release, surfacing, air refill/cancellation, low-air visibility, spear reach/full bags, saved catch timers, crop clearing priority, map heading/courses, raft water contact and drift speed. Desktop/headless checks do not establish phone FPS, thermals or APK packaging.
