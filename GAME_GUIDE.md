# Ocean Survival — game, code, and maintenance guide

Last updated: **2026-10-09**. This is the current project handover for the owner and future coding AIs. Read it before changing gameplay. Paths below are relative to this project; `res://` means the Godot project directory and `user://` means Godot's platform-specific saved-data directory. Live source code remains authoritative if a later change makes this guide outdated. Update this guide when changing behavior, constants, architecture, or saved data.

## Owner's requirements and current delivery

### Worn salvage, repairs, dry shelters and contact sounds (2026-10-09)

Current source/menu is **1.1.7**, Android **version code 10 / name 1.1.7**. Restart Godot before manual export to refresh cached presets. No APK is exported. Normal saves and once-per-save testing supplies remain intact.

New lamps are removed from crafting, debris pools and the wind-power chapter requirement. Existing saved lamps and owned recovered lamp kits remain usable for save compatibility. Rare debris now includes the owner's textured Solar Torch, Walkie Talkie and Binoculars on scrap floats. Their imported albedo textures are retained under a shared worn-casing shader, physical cloth tape and chipped edges. Original electrical station materials also use restrained grime, wear and oxidized metal; no extra per-frame materials or lights are created.

Powered handhelds and electrical stations occasionally develop loose contacts or damaged wiring after active use. Wind generators and electric purifiers may develop motor faults. Loose contacts flicker briefly, then lose output; **SHAKE** reseats them for free with a 1.4-second wrist animation. Wiring/motor faults require **REPAIR**. The repair panel shows the reusable tool and **HAVE / NEED** amounts; a missing requirement disables repair. Craft **Repair Kit** from **2 Metal + 1 Wood + 1 Rope**. The kit is retained after use. Torch repairs use 1 Wire + 1 Plastic; handheld radio uses 2 Wire + 1 Screw; generator uses 2 Wire + 2 Screw; electric purifier uses 1 Wire + 2 Screw; rescue radio uses 2 Wire + 2 Screw. A seized motor adds 1 Motor. Legacy lamp uses 1 Wire + 1 Plastic. Stored charge, battery installation and switch state are preserved when repaired; shaking cannot recharge an empty cell. Existing solar exposure, four-minute solar charging and thirty-game-day radio battery rules remain.

`equipment_repairs.gd` is a Player child. Repair/assembly takes six seconds, with visible opening, wire fitting, screwdriver turns, closing and testing in both cameras. Held electronics and Repair Kit crafting use this sequence; Wind Generator, Electric Purifier and Rescue Radio construction also hold a six-second component assembly. Repair and handheld crafting exchange parts/results atomically at 85% completion; structure construction revalidates its final supported placement before spending. Damage, movement, changing equipment, pause/menu, swimming, invalid targets and lost focus cancel pending handheld work before contact without spending. The repair panel participates in `SurvivalServices.is_modal`; touch input is released before its buttons start work. Saved electronics/machines gain optional validated `faults`/`fault` and `fault_after`; old saves default to healthy equipment. Pending actions are not saved.

Roof rain protection uses a cached **128 × 128 RF height texture** covering 32m around the camera in raft-local space, alongside the existing 64 exact nearby wall/roof masks. Every overlapping roof and upper deck contributes even in houses with more than 64 pieces; repeated instanced pieces are identified by their scene path rather than generated node names. Rotated roof edges conservatively cover intersected weather cells; the actual narrow stair passage stays open. Rain and splashes share this mask and blue-grey colour. The texture updates at the retained shelter sampling interval, not every frame; there is no mobile smoke/fog change.

`contact_audio.gd` preloads **22 CC0 recorded contact clips** for timber, beach grit/mud, grass, snow, stone, casing, metal, cloth and hammering. `tools/prepare_contact_audio.py` decodes/normalizes the recordings, removes leading silence while preserving attacks and natural tails, and writes `audio/contact/source_manifest.json` with source hashes, timings and licenses; `tools/import_contact_audio.ps1` imports through a small isolated project. Maximum retained attack padding is 0.5ms; hardware/output latency is separate. Consecutive surface samples avoid identical repeats and use small pitch/level variation. Footfalls follow measured actual movement relative to a moving platform, twice per 1.84m walk / 2.37m run cycle, and share their phase with displayed gait, head bob and held-item sway. Standing, blocked movement, air and swimming do not make ground contacts. Snow/volcanic stone/spring grass/beach/wood are selected by the ground probe. Sand footprints share beach contacts. Tree damage and impact now occur at the axe downstroke (57% of each swing). Build hammer taps, repair casing/wire/contact stages and shaking use contact cues; final timed placement avoids an extra duplicate impact. Late sounds are skipped after stalls/resume. Existing eating/drinking/water/cooking beds and electronic radio tones remain; these are not claimed to be newly recorded.

Verification uses isolated `contact_audio_smoke.gd`, `equipment_repair_smoke.gd`, expanded roof-rain and construction fixtures, and the existing gameplay/touch/battery suites. Desktop previews and imported icons are checked separately. Phone sound-output latency, FPS, touch behaviour and a fresh APK remain unverified until the owner exports and tests.

Final verification for this update: **884 checks passed across 17 isolated source suites**, including 33 contact-audio checks, plus **150 desktop preview checks** across repair (52), rain/touch (46) and construction/wind (52). Five worn-equipment pictures were rendered/imported and the final repair menu, both camera views and icons were inspected. Desktop previews used the Dummy audio driver: they validate cue scheduling and visuals, not audible device latency. Contact WAVs total about 197 KiB and are imported as uncompressed mono 16-bit PCM. No APK was exported.

### Distant current, compact construction and DIY wind power (2026-10-09)

The preceding source/menu release was **1.1.6**, Android **version code 9 / name 1.1.6**; the section above records the current release. These current, construction and wind-power defaults supersede the older near-resupply defaults below. No APK was built or exported; normal player saves and the once-per-save 2,000 testing supplies remain intact.

New debris enters **52–59 metres upstream**, with a four-second fade and 2.5–4.5 seconds between arrivals, and moves through real buoyancy/current physics at the retained **0.32 m/s**. It never replenishes in casting range or teleports forward when nearby supplies are low. Loading populates an existing spread from 6–52m upstream, so the survivor starts with salvage already passing through the current. The essential-material cycle, mobile **48-body / 24-prewarm** budget, desktop 80/35, moving-raft anchoring and protected rope catches remain. Only departing/out-of-corridor pieces fade for recycling; the former full-pool near-target recycling is removed. Screws, insulated wire, motors and batteries join rare salvage, with recognizable original models on scrap floats. Distant arrivals take time to reach an anchored raft; collection and sailing through the existing lane supply the survivor in the meantime.

Night water has a restrained navy body colour and a broken silver moonlight path that continues into the distance instead of stopping at the daytime 120m glitter cutoff. Sky/cloud shadow suppression, visible textured salvage, wave/buoyancy synchronization, the existing slow celestial clock and mobile fog/smoke restrictions remain. No extra lights or reflection passes are added.

Foundation plane targeting now chooses an actual connected cardinal deck neighbour even when the view ray hits a stair, wall, debris or empty sea. Rotated raft/grid placement, occupied-cell rejection, support chains, exact preview/commit and edit ownership remain. Empty roof targeting projects onto the ceiling plane before room/landing selection. New stairs use a **2.4m ramp + 0.2m landing**, twelve timber treads, 1.4m width and the unchanged 2.65m rise. The player uses a 50-degree slope limit only while contacting stairs; ordinary terrain remains 45 degrees. Collision/headroom probes, top sockets, smart-roof landing support and the continuous narrow ceiling opening use the actual flight length. `stair_geometry.gd` saves optional `survival.run`; old records without that field retain their 2.8m run/3m landing so saved stacked flights stay connected. New compact flights save/restore their shorter geometry. Roof snapshots include lengths, so old and new stairs may coexist, including edit previews.

**Screw** costs 1 Metal; **Wire** costs 1 Metal + 1 Plastic; **Motor** costs 3 Metal + 2 Wire + 2 Screw. Existing Battery crafting remains 1 Metal + 1 Plastic. Crafting lists these components and their distinct icons. The level-3 **Wind Generator** costs **8 Wood + 4 Metal + 4 Screw + 2 Wire + 1 Motor + 1 Battery**, consumed together on actual construction. Recovered complete generators retain their one-item installation recipe. Saved construction costs retain/refund these component names.

The original turbine model has a braced timber mast, wooden pitched blades, bolts, a salvaged motor, yawing tail, insulated leads, a battery box, four charge bars and a brake lever. Gradual rotor acceleration/spindown and slow yaw follow the existing wind direction and gusts. Charging uses wind strength cubed, capped at 2.2 charge/second, and requires open sky; battery capacity remains 120 charge. Aiming/using toggles the brake with the existing hand animation and sleeve sound. **Braking stops charging but stored energy still powers consumers within 12m**, retaining their existing consumption rates. Full batteries regulate charge while the rotor continues turning. Rotor/mast collision is physical and included in placement, preventing a turbine through a ceiling. Existing `charge`/`enabled` saves remain compatible; animation speed is transient. The generator's original crafting picture is rendered from this model, cached/warmed with other station pictures, and recorded in asset credits.

Verification uses isolated `tools/verify_source.ps1` suites, including `current_wind_build_smoke.gd`, actual stair traversal and the existing construction, Continue, battery, rope, touch and night tests. Native views use `tools/preview_survival_update.ps1 -TestScript current_wind_build_smoke.gd -SilentAudio`, plus the stairs and meals/night suites. `-SilentAudio` avoids the prior Windows audio-device invalidation only in previews; production audio remains enabled. Desktop/source checks do not prove actual phone FPS, touch, sound or a freshly exported APK.

Final verification: **510 focused source checks across twelve isolated suites**, plus **138 Mobile/D3D12 desktop checks** (current/wind/build 49, meals/night/supplies 58, stairs/sky 31), all passed. The actual character traverses the shorter flight in both directions; rotated empty-cell placement, full rotor clearance, six-component crafting, braked-battery output and legacy/new stair restoration are exercised. Native pictures `build/diy-wind-generator.png`, `build/night-moon-ocean.png`, `build/night-supplies-quality-{1,2}.png` and `build/compact-stairs-preview.png` were inspected, as was the final textured generator crafting picture. The source loading stress fixture retains its previously documented shutdown-only ObjectDB warning. Testing found and fixed `portable_electronics.gd` accessing a null current scene during transitions; its existing 42-check battery/solar/save suite passes. `git diff --check` is clean. Phone testing and manual APK packaging remain unverified.

### Distinct recipe pictures, clear night sea and reliable salvage (2026-10-09)

Current source/menu version is **1.1.5**, Android **version code 8 / name 1.1.5**, superseding the older release notes below. Restart the editor to reload these settings before the owner's manual export. No APK is exported by this change.

All eighteen recipes now use different original photographic food cutouts, including recognizable whole grilled fish, roasted vegetables, steak, bird, crab, banana mash and ingredient-specific broths. `item_art.gd.MEAL_REGIONS` maps measured bounds in one cached transparent `textures/ui/food/recipe_atlas.png`, with square padding and clipped sampling to keep tails and plates intact and prevent adjacent pictures bleeding into thumbnails. The edited atlas adds clear transparent gutters; all eighteen final runtime thumbnails and the actual cooking menu are inspected. Camp Kitchen and bag/HUD consume the same food lookup. The loading menu warms one shared food atlas instead of eighteen obsolete generic thumbnails, retaining the separate station, tumbler and tank resources. Existing Baked Potato aliases, recipe/cooking transactions, ingredient counts, effects and held food models are preserved. Generation/refinement prompts and provenance: `textures/ui/food/RECIPE_ART.md` and `ASSET_CREDITS.md`.

Night ocean shading uses clearer moonlit blue body/deep/reflection tones and reduces the dark sky-mirror contribution; sky-hiding facet darkening fades out at night and analytic cloud reflections remain daylight-only. Swell, ripple contrast, moon shimmer and CPU/GPU wave matching are retained. Night ambient energy is 0.52 and the existing shadowless diffuse fill is 0.35, fading continuously to the unchanged daytime 0.62/0.32. This makes real shaded salvage visible without adding lights or mobile fog/smoke. The existing single sky clock, moon/stars and twenty-minute default cycle remain.

The old crest lift subtracted blue light in wave troughs, making broad black bands; night lift now applies only to positive crests and the trough contrast eases after dark. `resource_visual.gd` updates one shared night-readability value across cached weathered materials every atmosphere sample (0.5 seconds). `debris_weathered.gdshader` adds subtle colour-preserving sky bounce below bloom brightness, fading out in daylight. New debris inherits the current value. It keeps texture detail visible on unlit faces without new lights, object outlines or extra rendering passes.

`debris_spawner.gd` keeps the existing **48-body / 24-prewarm mobile** budgets and desktop 80/35, but narrows the corridor from 60m wide/80m upstream to **28m / 30m**. The first eighteen pieces spawn 6–18m upstream in an 8m half-width lane. An ongoing target of eighteen pieces within 24m prioritizes fresh supplies 10–18m upstream. A repeating twelve-piece cycle guarantees Wood, Rope, Plastic, Metal, Stone, Soil and Barrel, plus one random salvage piece containing sponge, all six crop seeds or generator/lamp equipment. Speed remains 0.32m/s with the existing small variation and buoyancy. Departing bodies fade and recycle relative to the sailing raft; a full pool can recycle distant unhooked loot to restore nearby supply. Hooked/frozen catches are protected. Supply remains anchored to the raft while the survivor explores land. Spawning stays staggered and bounded; none of the temporary 2,000 testing supplies or existing player saves are reset.

Focused verification: `tools/verify_source.ps1` with `meals_night_supplies_smoke.gd`, `camp_fire_smoke.gd`, `rope_smoke.gd`, `night_sky_smoke.gd` and `loading_performance_smoke.gd`, using `--mobile-effects`. Desktop screenshots/checks: `tools/preview_survival_update.ps1 -TestScript meals_night_supplies_smoke.gd`; the existing camp-fire preview verifies the actual cooking menu and touch transactions. New previews are `build/recipe-food-gallery.png` and `build/night-supplies-quality-{1,2}.png`. Source/desktop results do not prove actual phone FPS, touch behaviour or a freshly exported APK.

Final validation: **297 focused source checks** passed (meals/night/supply 52, camp/fire/transactions 49, rope 30, sky/clock 29, edit/debris/materials 110, real loading/Continue 27). **58 Mobile/D3D12 desktop checks** passed, including all eighteen distinct alpha cutouts, the actual `build/recipe-camp-kitchen.png`, and visibly lit textured Wood at both Battery Saver and Balanced. Final menu/gallery/night screenshots were inspected and `git diff --check` passed. The final graphics run uses `-SilentAudio` solely because Windows invalidated its WASAPI device in the preceding render; production audio settings/assets remain unchanged. The source loading stress fixture reports a 15-instance shutdown-only ObjectDB warning; no source/renderer errors or failed checks remain. Actual phone FPS/audio/touch and manual APK packaging are unverified.

### Camp pictures, deliberate fire actions, larger start and Camp Kitchen (2026-10-09)

This follow-up is **source/menu v1.1.4, Android version code 7**. It supersedes the 1.1.3 identification note below. Restart the owner editor before manual Android export so cached export settings do not write the old version back; verify version/name **1.1.4** and version/code **7** in the Android preset. Keep the existing package/signing and install the newly exported update over the app. No APK is built by this work.

Bonfire, Rain Collector, Sand Filter and Cooking Setup have four different transparent pictures rendered from their actual original game models, including the filter's layers and the collector's open barrel. `item_art.gd` caches them; the loading menu warms them with the three new dish pictures. Cooking Setup no longer aliases the bonfire picture. Assets are original/free and recorded in `textures/ui/stations/SOURCES.md` and `ASSET_CREDITS.md`; `tools/render_camp_icons.ps1` reproduces/imports them using isolated data.

New bonfires and cooking setups begin **off**, retaining 180 seconds of stored starter fuel. Aim at an unlit fire and use **LIGHT FIRE**, owning **2 Stone**. Stones are reusable: both hands hold a stone, strike three times with clacks and six brief local sparks, then ignition commits at final contact in a 2.2-second action. If no fuel remains, it spends exactly **1 Wood** at contact for 90 seconds; remaining fuel needs no extra Wood. Rain-exposed fires cannot light. To put a burning fire out, use **PUT OUT FIRE** in Camp Kitchen, or hold Stone and aim/use **PUT OUT FIRE**. Fuel is preserved and cooking/boiling pauses. The existing completed-output automatic fire-off rule remains. Old saved `burning`/fuel/job values restore normally.

Hold an unlit Torch, aim at a burning bonfire/cooking setup and use **LIGHT TORCH** for a 1.3-second dip/ignition animation. Its Burning Torch exchange commits at contact and keeps the next-dawn deadline. **PUT OUT** shows a left-hand cloth cap and snuff action before converting/equipping the reusable Torch. Both unlit and lit held torches show a mount preview on a suitable Wall or solid lower Window, then **PLACE TORCH** reaches/releases at contact without another crafting cost. Taking a wall torch returns its actual lit/off item and remaining deadline with the existing capacity check. Hold Stone to light/put out a mounted torch. New timed `FireActions` commands reject inappropriate tools/targets/reach and cancel before contact on damage, moving away, equipment change, menus, pause, swimming or focus loss. Temporary selected-item visuals are hidden during actions in both camera modes; these pending actions are transient, not saved. Existing wall-torch fuel/burning/end_time records remain unchanged.

**New Game** adds one actual Foundation at raft-local `(0,0,2)`, increasing the default deck from **2 x 2 to 2 x 4 metres**. It uses normal collision, grid registration, reciprocal sockets, buoyancy sampling, editing/removal and version-1 structure saving. It is granted once at a fresh start; removing it does not regenerate it on Continue. Existing saved raft layouts stay intact. All 2,000 testing-material/Soil supplies remain.

**Camp Kitchen** uses a dark bordered panel, large 48px cook/boil buttons, dish pictures, food/water/health benefits, preparation text, coloured HAVE / NEED ingredient counts, recipe category tabs, remaining fuel, **+ WOOD** and fire on/off controls. Cards use two columns in landscape and one at narrower widths. All eighteen recipes share `food_rules.gd` and the existing transactional station jobs. Three additions are **Grilled Fish and Onion** (Fish + Onion, 16s, food/water/health +36/+5/+10), **Coconut Fish Stew** (Fish + Coconut + Onion + Clean Water Can, 22s, +46/+30/+14), and **Crab Tomato Broth** (Raw Crab + Tomato + Onion + Clean Water Can, 20s, +42/+28/+12). Water-can ingredients still return empty cans, output cannot duplicate and overflow remains recoverable in a loot bag. Existing meal identifiers/effects stay usable in old saves.

Verification commands: `tools/verify_camp_update.ps1` and `tools/preview_survival_update.ps1 -TestScript camp_fire_smoke.gd`. The new suite checks ignition contact/cancellation/fuel/stones, first/third person props, held and mounted light/off states, wall transfer, larger-starter support/legacy Continue, distinct asset pixels, recipe transactions, menu layout and native phone-style touch plus emulated-mouse COOK routing. Desktop preview images are `build/camp-{craft,kitchen,stews,strike-first,strike-third,light-torch,snuff-torch,mount-torch}.png`. Normal owner saves are untouched; source/desktop validation does not establish physical-phone FPS or touch behaviour.

Final validation: **638 checks across twelve isolated source suites** and **58 Mobile/D3D12 desktop checks**, all passed without script/engine errors. New asset rendering separately produced four station pictures and three dish pictures. All relevant menu/hand screenshots were inspected, including a front-side third-person stone grip, final category styling and the cloth snuff cap. The real GUI COOK tap spends fish/coconut/onion exactly once and completes the existing job. HUD action labels now hide behind Bag/crafting/service modals so preparation text cannot cover recipe cards; the retained mobile suites and final desktop preview pass after this adjustment. `git diff --check` is clean. No APK was exported or installed and physical-phone performance remains unverified.

### Mobile Bag taps, roof rain and gentler survival drain (2026-10-09)

The custom survival HUD ignores Android's emulated mouse replay after handling a real finger event. A Bag touch now opens the panel once, immediately builds all 30 item and MAP/CRAFT hit targets, and releases movement/look ownership. Item inspection, dragging, recipe details and single-confirmation crafting retain physical desktop mouse support. Settings and ordinary menu widgets still receive their own mouse events.

Rain streaks and bouncing impact splashes now share the same roof/wall/upper-deck masks and moving raft transform. The previous splash material could show droplets falling through thin ceilings after a roof impact. Both draw paths now clip those fragments; sheltered water also cannot spawn impact splashes. Protection remains active through rain fade-out. Real stair openings remain open, outdoor rain remains visible, masks retain the existing 64-box bound and phone smoke/fog stays disabled.

Normal active hunger drain is **0.03/second** (1.8/minute) and water drain **0.05/second** (3/minute), with the existing 1.6 sprint and 2.0 swimming effort multipliers. A fed/hydrated survivor has no passive health decay. With either supply empty, health falls at **0.20/second**, rather than 1.5/second. Reading the Bag or a survival modal and paused gameplay consume no food/water; actual combat, drowning, cold/lava and raw-food penalties remain. Saved values and the save format are preserved; no refill/reset occurs on updating.

Project/menu version and Android preset are **1.1.3 / version code 6**, using the existing package identity/signing. The locally checked `build/OceanSurvival-updated.apk` is still **1.1.2 / code 5**, timestamp 2026-10-09 12:07 IST, and predates this follow-up. Its compiled underwater scripts, sea-plant/shark shaders and kelp/tank imports are present; the export exclusions do not block these updates. No authorized phone was connected for installed-version inspection. **No APK was exported or installed.** The owner should restart Godot to reload the externally edited preset/project settings, then export Android to `build/OceanSurvival-updated.apk` and install that newly exported APK over the same signed app, without uninstalling or clearing data. The main-menu footer must show **v1.1.3**.

Validation: `tools/verify_mobile_bag_rain.ps1` passed **372 checks across six isolated source suites**. The Mobile/D3D12 desktop preview passed **36 checks**, including touch-plus-emulated-mouse routing, immediate inventory/craft layouts, exactly one craft transaction, survival/menu rates, and actual GPU rain/splash positive controls and ceiling clipping on a moved/turned raft. Backpack/crafting screenshots were inspected at `build/mobile-fix-{backpack,crafting}.png`. A small GPU test viewport widens its test streak to avoid subpixel false negatives; the real game streak size is unchanged. This does not establish physical-phone FPS/touch behavior. Changed: HUD, rain system/shader, Stats, main-menu footer, project version and Android version fields. Added: `tests/mobile_bag_rain_smoke.gd`, `tools/verify_mobile_bag_rain.ps1`; preview routing and the starvation fixture are updated.

### Diving, swimming, map heading and water contact (2026-10-09)

The existing game now has a deep sand floor, submerged ruined neighbourhoods, textured moving sea plants, fish schools and huntable fish/crabs/turtles/rays. Swimming follows vertical view direction, with alternating first-person strokes and a third-person crawl/kick. Spear rewards commit at animation contact. The handmade plastic Diving Tank is available at level 1, costs 8 Plastic + 3 Rope + 2 Metal, supplies 180 underwater seconds and uses a cancellable six-second empty-hand refill on dry ground. Remaining air is shown with breath; low air blinks. Torch, Bonfire and tank appear first in crafting. Sharks stay farther away, cannot bite before level 6 and use rare shared-cooldown encounters.

Spring Isle adds a seventh island; the map also lists three diving destinations and its player arrow follows position and direction. Original island placements remain. Spring vegetation retains clearing/regrowth and planted-crop priority. Raft centre freeboard is 0.045 m with follow_speed 9, immersing log undersides; debris current is 0.32 m/s. Grid support, crest sampling, construction leveling, wave clock and hooked reeling remain. Optional air/catch fields extend validated version-1 saves. Deep-water background/tint replaces sky leakage without mobile environment fog/smoke. **FEATURE_UNDERWATER.md** records controls, balance, limits, files and save fields. Validation passed **556 checks in 12 isolated source suites** and **71 Mobile/D3D12 desktop preview checks**; phone FPS and APK behavior remain unverified. Owner saves/testing supplies are preserved, and the owner exports the APK manually.

### Visible night moon, stars and cycle length (2026-10-09)

Following the owner's report of fast sun/moon movement, the full day **and** night now default to **20 active real minutes**, selectable from **12–30 minutes** in Settings → Day + night length, in one-minute steps. Existing choices within that slower range are retained; older fast/out-of-range preferences use 20 minutes. Normal saves, calendar dates and current clock time are preserved. This supersedes both the earlier 8-minute default/6–10-minute range and the historical 24-minute default/6–96-minute range below. Paused gameplay still does not advance the clock.

Sky3D remains the only clock and retains the astronomical sun/calendar. `TimeOfDay.smooth_celestial_motion` is enabled in the main scene: orbital calculations remain at 10 Hz, while inexpensive axial rotation advances the rendered sun/star positions between samples at the current frame rate. Explicit time/date restoration still applies immediately. `get_render_time()` exposes the same clock's pending active fraction; `OceanAtmosphere` uses it each frame for a steady moon azimuth, 14–46 degrees above the horizon, fading smoothly out in daylight. This avoids the old sharp moon sweep near midnight caused by projecting the sun near its nadir. Every dark night has a visible moon, independent of real lunar phase/date. The existing MoonMap surface, Milky Way panorama and star field are reused with gentler twinkling, clearer stars, a soft moon halo and thinner sky clouds around the disc. Occasional original shooting stars cross the sky with bright heads and tapering, fading tails: two staggered shader schedules produce one 1.35-second meteor roughly every 14 seconds in varied directions. They fade out during daylight; inactive events skip the trail calculations. The shader gets moon direction from its texture basis rather than relying on a directional-light slot, and keeps moon brightness near the horizon independently of the stars' horizon fade. No extra sky pass, particles, mobile fog or smoke is added.

Run `tools/verify_night_update.ps1` for isolated duration/migration/calendar, all-month night visibility and retained survival/equipment checks. `tools/preview_survival_update.ps1 -TestScript night_sky_smoke.gd` renders three mobile quality profiles, pre-dawn moon/stars and two shooting-star positions to `build/night-sky-*.png`. Source/desktop checks do not establish physical-phone FPS. No APK is exported.

Slow-motion follow-up validation on 2026-10-09: **282 checks across seven isolated source suites** and **43 Mobile/D3D12 desktop sky checks** passed. At simulated 30/60 FPS, both bodies move less than 0.02 degrees per frame, the rendered sun stays aligned with orbital samples across midnight, and the default sun arc is under 19 degrees per real minute. Pause, old-fast-settings migration, calendar advancement and slower saved preferences pass. Night and pre-dawn screenshots were inspected, including the illuminated surface of the dawn crescent. Owner saves were untouched; phone performance remains unverified. This follow-up also changes `addons/sky_3d/src/TimeOfDay.gd`.

Changed files for this follow-up: `scripts/game_settings.gd`, `ocean_atmosphere.gd`, `scenes/main.tscn`, `addons/sky_3d/shaders/SkyMaterial.gdshader`, `tests/stairs_sky_smoke.gd`, `survival_loop_smoke.gd`, `visual_build_overhaul_smoke.gd`, `tools/preview_survival_update.ps1`, this guide and `ASSET_CREDITS.md`. Created: `tests/night_sky_smoke.gd`, `tools/verify_night_update.ps1`. Existing regression fixtures now use the current mobile physics step, compact-stair movement and completed-cooking fire-off rules.

Validation on 2026-10-09: **276 checks across seven isolated source suites** and **37 Mobile/D3D12 desktop night-sky checks** passed. Moon/stars were inspected at Battery Saver, Balanced, High and pre-dawn; two shooting-star screenshots show the head moving with its fading tail. The retained crop/torch fixture now follows the previously updated produce meshes and has a timeout. Normal saves were untouched. No APK was exported; physical-phone FPS remains unverified.

### Survival tools, volcano and winter islands (2026-10-09)

`FEATURE_TOOLS_BIOMES.md` contains the research links, complete source/asset manifest and manual checks. New craftable Axe, Pickaxe, Shovel, Paddle and reusable Anchor use the existing inventory, recipe confirmation, hotbar and HAND/E controls. The Axe doubles chopping damage and speeds planted-tree work; the Shovel gathers three Soil/Sand and speeds root harvesting. Pickaxes mine finite Metal/Stone deposits. Paddle strokes require standing aboard, spend six stamina and move an unupgraded raft with directional momentum/drag. Anchors stop horizontal movement while buoyancy continues; raise the anchor before sailing. New tools have original models, rendered inventory pictures, first/third person poses and timed sound cues. Contact actions cancel on changed equipment/target/reach, damage, menus, pause or focus loss; capacity checks preserve resources if a reward cannot fit.

Volcano Isle at X/Z **(-1500,900)** and Winter Isle at **(1100,-1300)** add two destinations without moving the original four or changing their pickup IDs. Both have indexed, textured terrain with matching static collision and compact shore masks. Volcano adds a recessed crater, animated emissive lava/channel, a nearby shadowless glow and richer mineral deposits. Lava contact causes 10 health/second. Winter adds snow on sheltered/upward surfaces, exposed rock and 14 shared-mesh spruce trees with subtle wind, felling and 6-Wood rewards. Winter exposure warns after 60 active seconds and causes 0.3 health/second after 180 seconds; a lit torch or burning fire within 6m warms the player, and leaving the island reduces exposure. Existing farming works on clear, dry, sufficiently level land. Felled spruce wait 360 active seconds, then grow over 30 seconds; planted ground crops hold their clearing until harvested/removed. Growing trees have no blocking collider and wait if the player occupies their trunk.

The map now scales to include all seven islands and three diving sites with distinct biome colours. New island courses stop 52m from their centres; manual rowing also stops at their shoreline. Camera far distance is 4000m. The near/far water border shares its exact edge vertices, and distant wave normals fade to suppress long reflection bands. New terrain setup cooperates with the shared 2ms frame budget; each new terrain has 2809 vertices/5408 triangles, tree meshes are shared and foliage culls at 160m. No new smoke, fog or particle emitters are added. The original mobile smoke/fog prohibition and testing supplies (including Soil) remain.

Optional version-1 save fields are `raft_anchored` (boolean), `biome_resources` (stable ID to remaining hits), `biome_tree_growth` (stable tree ID to wait/growth) and `winter_exposure` (seconds). Missing fields retain legacy behaviour. Saving merges delayed resource initialization with loaded records. Depleted mineral deposits remain depleted; forest regrowth waits/progress survive Continue. Actual owner saves are not reset.

Run `tools/verify_tools_biomes.ps1` for focused isolated source checks; its first-install loading suite uses separate fresh preferences. `tools/preview_survival_update.ps1 -TestScript survival_tools_biomes_smoke.gd` renders both islands and mining in each camera view. These desktop checks do not establish phone FPS, thermals or touch feel. No APK is exported by this workflow.

Validation on 2026-10-09: **526 checks across 10 isolated source suites** and a separate **94-check Mobile/D3D12 desktop preview** passed without script/engine errors. Five tool icons were rendered successfully. Crafting, all six map destinations, both new islands and first/third person mining screenshots were inspected. Owner saves were untouched; no APK was exported. These functional checks do not establish physical-phone performance or guarantee stall-free gameplay.

### Tumbler, salvage and presentation (2026-10-09)

Craft **Tumbler** for **2 Metal**. Hold the empty cup, aim at reachable ocean water and use **COLLECT WATER** for a two-second dip. It exchanges one empty tumbler for **Ocean Water Tumbler**. Drinking raw gives +12 water and -8 health; use the cooking menu's **BOIL** row to reserve one filled cup for an eight-second job. **Boiled Water Tumbler** gives +65 water with no raw-water penalty. Both drinks return one empty Tumbler atomically. These are intentionally simplified game water rules. Cup geometry has an open rim and visible water; first/third person drinking has timed sip sounds, cup tilt and falling water level. Filling now also holds the actual vessel.

Cooking and boiling extinguish their station immediately when one output is ready, stopping flame, light, crackle, steam and sizzling while preserving unused fuel. Relight with two reusable Stones to cook again; add one Wood if no fuel remains. Boiling pauses if the fire goes out and restores through the existing optional `station_job` record (`kind:boil`, `item:Boiled Water Tumbler`, remaining/duration); no save-version change. Full inventories drop completed water/food in the existing recoverable loot bag. All fifteen dish rows now show transparent 256 px renders of their cooked ingredients. `meal_visual.gd` caches original sliced carrot/banana rounds, tomato seeds, onion rings and diced roots/protein for bowls and pans. Three soft steam ribbons stay local to a nearby active pot; global mobile smoke/fog remains disabled.

The starter raft's decorative white flag/mast is removed. Purchased Sail Kit navigation is unchanged. WindGenerator and ElectricLamp are rare entries in the existing bounded floating-debris stream. Collect them, choose **PLACE**, and install on a supported deck. An owned kit replaces the raw crafting cost with one kit and is usable at any campaign level. Exact construction costs persist; moving preserves machine state, and removal returns its kit with capacity checks. Installed lamps use the existing generator power range and illuminate their LED lens only while powered. Salvage canisters/sheet metal have small dents/bends and dampness follows world sea level.

Pickup hands reach, grip the actual collected item and pull back; fruit/root harvesting carries its produce in both camera views. The existing batched flower variant now uses original curved petals, leaves, stems and a breeze shader, preserving clearing, crop exclusion and regrowth. Daily sky colours/cloud coverage derive from the saved calendar date and blend after midnight, including real month/leap-year boundaries. The existing celestial clock, adaptive mobile cloud path and disabled phone fog remain authoritative.

`tools/verify_realism_update.ps1` runs the focused source suites with isolated saves. `tools/preview_survival_update.ps1 -TestScript realism_polish_smoke.gd` and `-TestScript tumbler_smoke.gd` render the desktop views. `tools/render_food_icons.gd` renders the actual original food/cup geometry; `tools/import_food_icons.ps1` imports just those PNGs in a tiny project. No APK is built by these tools; phone FPS and touch feel still require physical-device testing.

Validation on 2026-10-09: **551 checks across 11 isolated source suites**, plus **78 realism and 21 tumbler checks in Mobile/D3D12 desktop previews**, all passed. Food menu, sliced pot/steam/flame, equipment/pickup, flower, daily sky and first/third person drinking screenshots were inspected. Normal player saves were untouched. These results do not establish physical-phone FPS or a fresh APK.

**2026-10-08 survival expansion:** Read `FEATURE_UPDATE.md` for current food values, timed medkits/cans, cooking, storage/death drops, dawn-based torches, interactive island plants and solar electronics. Its food and torch rules supersede historical instant-food and 180-second-torch descriptions below. `food_rules.gd` owns meal configuration; the player child `SurvivalServices` validates new commands; `StationJob` saves cooking/filter progress. Added optional records are `survival_services.drops`, `electronics`, `wild_plants`, `progression.torch_end_time`, built `survival.contents` and `station_job`. Payload version 1 and authenticated atomic saves remain backwards compatible, with stricter nested validation. All original building indexes remain; StorageBox and CookingSetup append to the list. Testing supplies remain enabled, and the owner exports the APK manually. The full file manifest, controls, architecture and seven-section testing checklist are in `FEATURE_UPDATE.md`.

The preceding expansion validation passed **929 checks across 18 isolated source suites** and a separate **85-check Mobile/D3D12 desktop cooking/storage preview**, which exited cleanly. Cooking/storage screenshots were inspected. Normal saves were untouched. No APK was exported and physical phone controls/performance remain unverified; see `FEATURE_UPDATE.md` for suite details and manual checks. The subsequent loading/stutter changes and their separate validation are described below.

### Moving buildings, construction hands and touch controls (2026-10-08)

Edit pickup now uses the normal placement resolver for foundations, walls, half walls, roofs and pots, retaining rotation and excluding the moving piece from support/overlap checks. PLACE revalidates the candidate; Cancel restores the original raft-local transform and socket links even after sailing. Saves during a move record the original committed position. Roof editing moves one tile, and its collision stays disabled until the move ends. Removing a red preview cannot unregister a different foundation underneath. Pot crops survive relocation; pots still require foundation/roof tops.

Assembly locks the original aim ray relative to the raft and the resolver's actual support. Looking elsewhere during assembly or briefly touching water no longer cancels a green placement. Leaving build mode, changing the selected piece, losing support, opening a modal or leaving reach still cancels without spending. Placement and affordability are checked again before materials are spent. Build/edit mode shows a right-hand hammer and left-hand timber in both camera modes, hiding the selected food/equipment; leaving restores the selected item.

The permanent rope gun has a separate first quick slot before the six inventory quick slots and Bag. It consumes no bag capacity. CAST appears when this slot is selected and the gun is idle; selecting food/equipment hides CAST. Return and loaded reeling happen automatically, with no mobile RECALL button. Hook flight uses 9.81 m/s² downward acceleration, a locked ballistic trajectory and swept collision. Reeling shows a two-hand pose. Rope collection respects pickup stack sizes and bag overflow, releasing unaccepted amounts instead of deleting them.

Touch controls use larger spaced targets (at least 54px at the checked viewport sizes), clearer text and an always-visible joystick dock. The 124px reference action button sits on the left above the joystick, appearing only for a valid action, with COLLECT, OPEN/CLOSE, EAT, PLANT and other relevant labels. Growing/unready targets hide it. Jump uses a jumping person, Run a running person, Collect an open hand, and food/doors/water distinct pictograms. USE and CLIMB share one context slot without overlapping. Touch ownership and releases remain intact. The mission panel hides during construction so the material/placement chip stays legible.

Soil washes up randomly in tied floating sacks and can still be gathered from higher dry island land. A separate optional inventory flag `testing_soil_granted` supplies up to 2,000 Soil once per save, including existing saves. It does not reset the original six-material grant or refill spent Soil after a successful grant. New Game resets both testing flags. `Inventory.pickup_received(item,amount)` reports accepted world pickups; the HUD queues their icon, canonical item name and actual accepted count one by one above the play area. Full bags produce no false pickup message, and partial stacks show only the accepted count.

Floating logs/barrels reuse the original photographed timber atlas with weathering; metal has rust, plastic has rounded edges/seams and scratches, rope has shared braided geometry, Soil has tied cloth sacks, stones use an irregular smooth shared mesh and Sponge retains its porous shader. Existing imported model sources remain intact. Potato, banana and coconut starter pickups look like produce rather than packets. `resource_visual.gd` caches geometry and weather materials; the menu warms the new shaders and produce icons sequentially before gameplay.

Adult island coconut palms measure 6–8.4 m, and cultivated mature coconut palms approximately 6.7–7.7 m, compared with the 1.8 m survivor. Seedlings start small and retain continuous growth. Optional crop `fruit_layout:1` identifies the taller coconut crown; legacy saves retain fruit ripeness while rebasing fruit sockets into the new crown. Banana, tomato and potato use shared original modeled geometry and procedural skin in hands and pickups; banana tree fruit uses the same model. Their transparent inventory icons are rendered from those models.

Run `tools/verify_edit_tree.ps1` for isolated edit placement, saves/cancel, assembly, hands, tree proportions, touch routing/layout, construction, crops and rope checks. `tools/preview_survival_update.ps1 -TestScript edit_tree_smoke.gd -TimeoutSeconds 240` renders desktop controls, hands, produce icons and coconut/player scale. Normal saves remain untouched; these checks do not establish phone performance.

`tools/verify_controls_debris.ps1` additionally exercises Soil grant migration, sequential collection messages, full/partial rope stacks, all eleven floating salvage models, menu warming and environment teardown. The native fixture renders `build/floating-debris-preview.png` and `build/collection-controls-preview.png`. After regenerating icon PNGs, let the editor import them or run `tools/import_produce_icons.ps1`; it imports only those three files through a tiny isolated project and copies their import metadata/cache, without scanning the source-test junctions or changing game saves.

Follow-up verification: the eight-suite construction/control pass completed 399 checks. After adding final Soil/debris/loading and interruption coverage, the six-suite final pass completed 250 checks (edit/tree/controls/debris 101, rope 30, testing resources 11, menu loading 21, environment 41, action/farming 46). Including the five retained unaffected suites, 487 distinct checks across 11 source suites passed across these runs. The final separate Mobile/D3D12 desktop preview completed 110 checks, exited without script/engine errors, and its controls, build hands, produce, debris and coconut scale images were inspected. Debris freeboard was lowered so floating objects sit partly in the water rather than hovering. No APK was exported, real-phone performance remains unverified, and normal saves were untouched.

### Loading and movement stalls (2026-10-08)

The menu prepares imported models, texture/audio/shader dependencies, and scripts in dependency order using one background resource request at a time. It only retrieves a resource after `THREAD_LOAD_LOADED`; a live request remains cancellable without applying inventory/save changes. Script dependencies precede their users, including BuildSocket before Player. This removes the former synchronous player/HUD compilation burst while avoiding simultaneous worker script-preload requests. Scene instantiation and attaching nodes still run on the main thread. Maintain the warm-path lists when adding preload dependencies. `--profile-loading` prints per-resource durations for isolated diagnostics. This follows Godot's [background-loading guidance](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html); dependency ordering also addresses the reported [script-preload deadlock](https://github.com/godotengine/godot/issues/120827).

Continue and Quick Save now use the existing loading handoff as well as New Game. Continue retains the saved time and selected camera. `Player.restoration_complete` stays false until ground crops, all building pieces and socket links are restored across render frames. Input remains held by the handoff during restoration. Autosave/manual saves refuse incomplete restoration, preserving the prior complete on-disk save. The save payload format is unchanged. Socket restoration uses nine nearby spatial bins with the same horizontal-distance/order rule as the previous exhaustive scan. Construction visual batches and stair ceiling updates wait until restoration finishes.

`frame_work_budget.gd` cooperatively limits shore/wild/crop/restoration setup to 64 units or 2 ms per render frame. Each of the four decorative grass fields gets its own lane capped at 16 units or 0.5 ms, preventing fixed callback order from starving later islands while keeping their combined allowance at 2 ms. A single operation may exceed a time budget. Grass waits for actual terrain readiness, yields during both raycasts and final MultiMesh filling, and checks its generation after each yield. Background tasks use render frames so physics catch-up cannot run repeated preparation batches before the next rendered frame. These tasks continue after the loading handoff within their budgets. Setup verification must wait on render frames/readiness rather than assuming a count of physics ticks equals completed background work.

Roofs share one staircase snapshot per container/render frame; explicit refresh immediately sees edits. Dry weather skips whole-raft rain-mask scans; starting rain still refreshes shelter before emission. Wild growth snapshots active crop positions once per tick rather than allocating a group list for each wild plant. Crops, harvesting, shelter and stair openings retain their existing rules.

Ocean height evaluation uses typed, fixed wave expressions rather than unpacking Variant arrays for every probe. `Ocean.get_deck_crest()` batches all of the raft's existing probes, including each tilted corner's Y correction, with one water-origin/clock lookup. Additional physics ticks against the same visible wave clock reuse the sampled crest, conservatively adding the formula's slope bound and the changed corner Y for small motion/tilt. A new clock, wave setting, foundation sample set or larger motion forces resampling. The wave formula and minimum freeboard are unchanged. Debris commits its computed buoyancy/current velocity once per tick rather than four separate body updates. A cheap conservative radius rejects distant foundations before the swimming-climb search calculates their inverse support transforms. Hidden desktop touch controls skip mode scanning; displayed phone controls keep their normal per-frame checks and action ownership.

The raft also updates its compound parent transform at most once per rendered wave frame. Extra catch-up ticks accumulate their elapsed delta for the next update instead of repeatedly invalidating every child foundation collider. A changed wave clock, dirty deck, or entering/leaving construction/editing forces a fresh update even within the same render frame. Navigation distance, passenger carrying, tilt smoothing and the dry-deck clamp still consume the accumulated elapsed time.

Fresh phone settings now default to 30 FPS. Existing saved graphics/FPS choices remain intact. At the phone's 30 FPS setting, physics runs at 30 Hz, reducing world simulation and catch-up work; phone 60 FPS and regular desktop retain 60 Hz physics. Movement/buoyancy continue using elapsed delta. Mobile Auto starts at 0.72 render scale with MSAA disabled; Balanced/High retain 2x MSAA, and Battery Saver retains its lighter profile. `--mobile-effects` exercises these quality/setup policies on desktop too. The UI stays at native resolution. For the owner's Xiaomi phone, Battery Saver / 30 FPS remains the initial profile to try. Source/desktop results do not establish physical phone FPS or guarantee that all driver/thermal/storage stalls are eliminated.

Run `tools/verify_loading_update.ps1` for the real asynchronous loader, a 120-piece Continue fixture, save protection, socket/wave equivalence, buoyancy-cache invalidation, movement during setup, cancellation, cinematic handoff, dense dry-deck probes and rope checks, all in isolated storage. Logs include `build/source-loading_performance_smoke-console.log`. Normal player saves must not be used for profiling, and no APK export is included.

Loading follow-up validation: **593 checks across 13 isolated source suites passed** (loading 26, menu 21, cinematic 39, construction/weather 39, visual construction 53, wild plants 65, action/farming 46, rope 29, mobile 93, foundation 17, crops/torch 37, island visuals 87, environment 41). Fixture waits now honor the real input handoff and bounded render-frame preparation. The final separate **27-check Mobile/D3D12 desktop preview** restored 120 pieces, exercised walking/turning with visible touch controls, captured `build/loading-gameplay-preview.png`, and exited without script/engine errors. Dense rotating-deck probes retained over 0.25 m clearance. Grass diagnostics confirmed all fields finish; decorative grass may take many setup frames while gameplay remains available.

These checks establish functional completion, not freeze-free performance: the 120-piece desktop stress fixture still showed slow frames (median 65 ms, 95th percentile 89 ms during its movement sample) and a one-off setup/process peak around 0.86 seconds on the final run. Timings vary with system load and should not be compared as controlled benchmarks. Further tuning may be needed for very large rafts. No APK was exported, no real-phone run was performed, and normal saves were untouched.

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
- Quick casts start at 20 m; holding charges up to 60 m. Hook flight follows a locked gravity trajectory, sweeps against solid structures, lands on moving ocean waves, and the braided rope starts at the muzzle.
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
- The menu has an animated dusk sea; HUD, touch controls, crafting, bag and settings use cached matte panels and brass accents. Crop icons show the actual produce; legacy seed names use the same produce artwork. Island markers hide during modal panels and return when they close. Touch hit areas and action ownership are preserved.
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
| Android preset version | 1.1.3, version code 6; owner exports the signed ARM64 APK manually |
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
| `scripts/inventory.gd` | Slot storage, recipes, capacity checks, testing grant, compatible encrypted save/load |
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

Normal starter items include Rope and plantable potato/coconut/banana produce, plus carrot and tomato. Crop setup runs before the testing grant. Legacy crop Seed identifiers load as the matching edible/plantable produce with the same counts.

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
| PlanterPot | 4 Wood, 2 Soil |
| PlanterBox | 6 Wood, 4 Soil |
| TreePot | 8 Wood, 1 Rope, 6 Soil |

Twenty pieces are registered (the later sections describe HalfWall, CargoCrate, WallTorch and SandFilter): the nine above, Bonfire (8 Wood + 4 Stone), RainCollector (6 Wood + 1 Barrel + 2 Rope), and the five advanced machines described below. Raft Extension remains a legacy recipe/scene rather than a separate active selectable piece.

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

Stats starts health, hunger and thirst at 100. Active hunger drains 0.03 per second and thirst 0.05 per second, with 1.6 sprint/2.0 swim effort multipliers. Either reaching zero causes 0.20 health damage per second; fed/hydrated movement causes no passive health decay. Paused gameplay, survival modals, title screens and test scenes do not drain supplies. Stat changes emit signals for the HUD; health reaching zero triggers death handling. Saved values are preserved on updates.

Food interaction consumes the selected inventory item and applies its configured reward. Current coconut rewards include 12 hunger and 28 thirst, banana 30 hunger, and fish 24 hunger. Inspect the whole interaction branch for secondary health bonuses when changing nutrition. A death-screen save is normalized to survivable values, and legacy zero-health Continue handling avoids instantly resuming into a dead game. Preserve these protections when changing respawn rules.

The Fishing Rod starts timed fishing while on raft/shore rather than swimming. Fishing requires open water and takes 4–6.5 active seconds with a 7.5-second cooldown. A completed catch adds one Fish; overflow spawns a world pickup instead of losing the reward. Spear interaction raycasts nearby sharks (current reach 5.2 m and damage 38). Consume/cooldown/target checks belong to the interaction path, not merely the visual animation.

The gameplay scene has one spawner with two sharks, patrolling around 110 m from the raft. Sharks have 70 health, 85 m detection range, 4.1 chase speed, 1.7 patrol speed, 2.6 m bite range and 12 bite damage. They cannot attack before level 6 and use rare, time-limited encounters with shared cooldowns; spear combat remains. Life Vest is persistent equipped state and reduces incoming bite damage through the player's handler (current damage multiplier 0.38). It is not a one-use shield. Keep shark and player damage delegation consistent so vest protection is applied once.

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

The logical payload is still version-1 JSON. `scripts/save_storage.gd` now wraps new writes in an AES-256-CBC envelope authenticated with HMAC-SHA256 and a separately derived authentication key. It writes and validates a temporary file before replacing the primary, retains one `.bak`, and recovers a corrupt primary from a valid backup. Legacy plaintext JSON remains readable and migrates only on a successful write. The 32-byte `user://raft_save.key` belongs with both save slots when copying saves between installations. A missing/wrong key or unreadable primary and backup cannot overwrite the existing save or clear live inventory. Failed writes report an error instead of showing QUICK-SAVED. Encryption deters casual editing; a local key cannot make an offline game cheatproof. A first migration backup can still contain the previous plaintext payload until the next valid rotation. Restoration rejects malformed, non-finite, excessively large or singular building transforms before creating nodes; inventory entries require a valid item string and finite positive count, bounded by the current stack capacity. Current saves focus on inventory, stats, time, upgrades, collected pickup IDs and structures; do not assume every transient hook, debris, enemy, player position or raft navigation state is persisted.

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

The scene and Settings default to a 24-minute active day. Rain checks every 3–7 active minutes, with a 65% chance and 1–2.5-minute duration. TimeOfDay now accumulates processed delta, preventing a daylight jump after pause. Rain duration also uses active delta. Optional save metadata weather stores raining, remaining and next_check. Planter built-piece records add optional moisture, defaulting to 0.75 for old saves. Fire/collector records add optional survival dictionaries for fuel/burning/cook/item and water/seconds. Existing transforms, type strings, inventory and save versions remain compatible.

Stairs now have twelve 22 cm visual treads and one continuous walkable collider that meets the landing top. Floor snap is 0.32 m; maximum curb step is 0.30 m with clearance/landing checks. Land jump velocity is 4.5 with gravity 18 (about 0.56 m apex), water jump 2.8 and held swim-up speed 2.0. Saved stair roots remain unchanged; new placement uses a corrected entry socket and a landing level aligned with upper decks.

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

Conditions add underwater oxygen/drowning, stamina-driven sprint/swim exhaustion and wetness. Bandage restores 25 health; Diving Tank is available at level 1, equips once, supplies 180 underwater seconds and refills through a six-second empty-hand pump on dry ground. Both have real crafting/use and hand visuals. Mission status and condition values appear in the existing HUD without taking touch ownership. UI updates retain the existing throttling. Gameplay pause stops the new systems; full inventory preserves finished water and cooking ingredients.

Original wild_boar.glb, sea_turtle.glb and shore_crab.glb add four bounded wildlife actors per island; nearby AI flees, boars retaliate when injured, lit fires repel approach and storms stop roaming. Distant actors suspend movement after 65 m. Both spear and bow use real collision damage. Raw Meat/Raw Crab cook into 45/28-hunger meals. Animal health and 240-second respawn timers restore through optional saved state. Original reef_shark.glb replaces the earlier cone-fin/sphere shark visuals while retaining attack, spear, collision and health behaviour. Original raw_meat.glb, cooked_meat.glb and diving_tank.glb identify the new pickups/held equipment correctly. These are original modeled assets, not photographic scans. See models/ORIGINAL_SURVIVAL_ASSETS_LICENSE.md and ASSET_CREDITS.md.

Machine bodies have shared cached meshes/materials, 1 Hz simulation and no shadowed dynamic lights. Nearby rotor animation and animal physics are bounded by visibility distance. This is an implemented survival expansion, not all 106 feature categories from the pasted full-game design. ADVANCED_SURVIVAL.md lists the remaining terrain, biome, ecology, NPC, medical and art-production systems accurately. No APK is exported by this source update; the owner builds it manually.

## Flooded world, torch and rain storage (2026-10-05)

Current solo-survivor behavior and controls are detailed in ADVANCED_SURVIVAL.md. New Game uses scripts/flooded_world_intro.gd over the loading menu: the owner-supplied 31-second video with embedded narration and timed subtitles, SKIP STORY and BACK TO MENU. Continue bypasses it. The menu preserves selection/cancellation and saves until a successful transition. Headless menu checks bypass presentation; native preview checks exercise full video decoding and the dawn handoff. The 95-percent flood is narrative context. NPC survivors and underwater cities are future scope.

Torch is the tenth portable crafting card (2 Wood, 1 Rope). Equip from the hotbar and LIGHT within 3 m of a lit campfire; 1 Wood gives 180 held seconds. PUT OUT extinguishes. Swimming or exposed rain extinguishes; solid roofs shelter. Both camera views retain their normal visuals. The progression child is now Node3D to own shadowless torch light, third-person torch and cached spatial fire audio. Optional progression.torch_fuel restores to zero for old saves. Exposed rain increases wetness; held fire speeds drying.

RainCollector capacity is now 12 saved portions; collection remains 20 exposed rain seconds each, and transfer remains capacity safe. Water surface fill follows saved contents. IslandBirds.flight_position retains hunt dictionary keys/state but uses staggered shore/sea journeys rather than fixed circles. Population stays bounded. Original cached survival_audio.gd fire crackle is synthesized, while ocean and movement recordings retain their existing provenance. Native item thumbnails and the generated opening atlas are in textures/ui; their creation notes are in textures/ui/FLOODED_WORLD_ART.md.

Final 2026-10-05 source verification: nine isolated suites passed 350 checks (27 rope, 11 supplies, 93 mobile, 17 foundation, 41 environment, 23 marker, 21 menu, 53 survival loop and 64 advanced survival). A subsequent touch-opening check is recorded with the final validation. Tests include all five machine previews, exact construction costs and real Continue restoration. This is source verification, not phone or APK verification.

### Narrated opening, dawn handoff and timber raft (2026-10-05 history; opening superseded below)

The opening now uses four prerecorded English narration clips, spoken by the installed Windows Microsoft David Desktop synthesizer, with original generated approach/impact effects and the existing licensed ocean recording. It is synthetic narration, not a human voice actor. Each shot lasts at least its audio length plus 0.85 seconds (minimum 5 s), so the roughly 26-second story finishes its words before changing shots. Buttons use the ocean UI theme and are positioned in _ready before first input. Existing volume/mute applies to the Master bus.

On successful New Game entry after the cinematic, scripts/wake_transition.gd carries the final raft image in a temporary root CanvasLayer above the new scene. It waits for the player and initial frames, fades through black into dawn gameplay over two seconds, holds player movement/HUD/survival drain, then restores them. Failure/cancellation removes the overlay and preserves the existing menu/save rollback. Continue bypasses both cinematic and dawn override, restoring its saved time. No persisted cinematic flag is added.

The starter raft's old box mesh is hidden while its 2x2 m physics, grid/support sockets and buoyancy remain. scripts/starter_raft_visual.gd supplies nine batched rounded logs, two cross-poles, visible rope lashings and clear deck space. The decorative flag/mast was removed on 2026-10-09; navigation still requires the existing Sail Kit/Motor Kit, which install their functioning upgrade visuals. Foundation decks use the shared generated weathered timber texture through wood_planks.gdshader; logs use raft_timber.gdshader with cut-end rings. Imported-resource shader parameters are static and geometry is built once per raft, not per frame. Required island export textures remain untouched.

Latest complete verification: all ten isolated source suites passed 367 checks (the nine-suite 350 plus 17 cinematic/raft checks). Desktop Mobile/D3D12 previews covered four story shots, the rounded starter raft, foundation surfaces, crafting and wildlife. A native New Game → touch Skip → dawn handoff → playable controls probe also passed. These checks do not prove Android FPS, a fresh APK, or complete photorealism of every existing asset. No APK was exported.


Story arrival now explicitly uses first person to match the cinematic hands/raft shot; CAMERA still switches to third person normally. Continue retains the usual camera setting. The final focused source check covers this arrival and both camera/touch modes.

## Complete narration, hand grip and distant island groves (2026-10-05)

Before the 2026-10-07 video replacement, the New Game intro read the full displayed text in all four shots, using four locally recorded synthesized voice clips. Shot progression requires AudioStreamPlayer.finished and the minimum shot duration; a slow loading frame cannot skip narration. Wrapped captions display complete paragraphs. Native full-play verification covers all four clip starts and finishes, followed by dawn handoff and released movement. The art remains four photographic-style shots with pan/fades, rather than an animated 3D film.

The third-person rope launcher now follows BeachSurvivor's animated Wrist.R, including wrist orientation, through rope_hand_grip.gd. Imported armature scale is removed from the weapon transform. First-person skin geometry forms a wrapped pistol grip and connected forearm in one batch; hook launch origins continue using the actual visible muzzle. The permanent gun and its no-drop inventory rules are unchanged. The decorative cloth is at the raft's aft edge so it no longer blocks the initial held-gun view.

New worlds use island_layout.gd: Home Isle (280,-560), Reef Isle (-820,570), Driftwood Cay (-1000,-820), Far Cove (1380,950), in X/Z metres. Their starting distances are approximately 626, 999, 1293 and 1675 metres. Optional saved island_layout=1 retains this layout on Continue; missing layout on an existing nonempty legacy save selects 0 and retains its original scene coordinates. New games select 1. Existing resource IDs, built raft-local transforms, navigation speeds and actual owner saves are preserved.

Each island adds CoastalGrove: two harvestable bananas, two harvestable coconuts and four textured coastal broadleaf/shade trees. Banana planter visuals also use the new curved textured leaves and pseudostem. Existing coconut palms keep the supplied textured GLB. Original meshes/materials share one 1254-square atlas; foliage culls at 120 metres, decorative bark at 240 metres. Eight grove trees per island are created over separate frames after terrain collision is ready; new groves are excluded from island scan rescaling/material replacement/collision cooking. Decorative shade trees have simple trunk colliders. Plant interaction/growth updates sleep beyond 85 metres and elapsed fruit regrowth catches up on return. Shadow casting is disabled for new textured leaf geometry.

Optional saved island_groves is keyed by stable scene island name, then tree name. It stores existing PlantInstance state (stage, chopping health, fruit slots and regrowth) and a removed tombstone after stump removal. Saves merge incompletely initialized groves with prior records so early saving cannot discard delayed trees. Distant fruit elapsed time is included when saving. No normal user data was reset.

Verification: the full isolated suite passed 394 checks; final focused checks added legacy-location and removed-tree assertions, bringing the combined current coverage to 396 checks (world_visual_smoke 28, cinematic_raft_smoke 18; remaining suites unchanged). Native Mobile-renderer previews inspected both hand views and leaf/bark textures. Full native intro played all four voice clips to completion and reached playable dawn. The full-story native shutdown reported one ObjectDB warning; the final world visual preview closed without engine errors. These checks do not establish phone FPS, thermals or touch behavior on a real Android device. No APK was built; export manually after editor resource imports refresh.

New asset prompt/provenance: textures/ui/COASTAL_TREE_ART.md. Current previews: build/updated-gun-hand-first-person.png, updated-gun-hand-third-person.png, updated-island-trees.png and updated-banana-texture.png.

## Video intro and prepared dawn arrival (2026-10-07)

New Game plays the owner-supplied 31-second moving film in `video/new_game_intro.ogv`, replacing the four-image opening. Following the owner's latest request, the added Microsoft David narrator has been removed. Only the original soundtrack plays, restored to full level with a clipping limiter and brief end fades; its voice, effects and musical tension are preserved. Readable, centered subtitles follow the embedded video playback position, so a long frame, background pause, or the selected FPS cannot run the words ahead of the film. Existing Master volume/mute applies. The resolution is now 720 × 408 at a constant 30 fps, with mild compression-noise reduction and an opening fade. The existing source mark is preserved. Source provenance and preparation details are recorded in `video/INTRO_ASSETS.md`.

The menu completes its serial script preparation before starting the film, removing the observed preparation hitch from playback. The normal loading menu remains responsive during this short preparation and Cancel Loading clears the pending story. Resource loading continues behind the film. Continue/Quick Save bypass both the film and dawn override, keeping their saved clock. Actual New Game state still changes only after validated scene entry; cancellation preserves disk saves and inventory.

SKIP STORY stops all embedded sound immediately and holds the current video texture. Normal completion holds `video/intro_arrival.jpg`, taken from the actual final raft shot. BACK TO MENU, Escape and Android Back cancel playback; backgrounding pauses video and narration together. If the resources are still loading, an animated Preparing your raft caption and progress bar remain on the held frame.

`wake_transition.gd` carries that frame above scene entry, fades it to black, waits for all IslandSetup controllers to report completion plus at least 0.6 seconds and a brief frame-settling period (twelve frames below 50 ms, or at most two seconds after world readiness on a slower phone), then reveals first-person dawn over 1.6 seconds. It holds player processing/movement/input, HUD and Stats drain until the reveal finishes, releases touch/actions, restores their previous state and removes its temporary audio/overlay. Android Back cannot pause the hidden gameplay underneath this handoff. This avoids showing an incompletely prepared world; it cannot guarantee device-specific frame rates or a fixed total loading time. The presentation adds no saved fields, and all existing testing supplies/building/gear contracts are retained.

Verification: four isolated suites passed **164 checks** (39 cinematic/raft, 21 menu-loading, 93 mobile and 11 testing supplies). Full native Mobile/D3D12 playback at 30 FPS completed the film, all eight subtitle cues, scene entry and the dawn reveal, then released playable controls. The final desktop playback observation was about 33 ms at the 95th percentile and 34 ms maximum, excluding screenshot export work; it is not a phone measurement. One existing shutdown ObjectDB warning was still reported. Current previews: `build/cinematic-opening.png`, `cinematic-impact.png`, `cinematic-flood.png`, `cinematic-raft.png`, `cinematic-handoff.png`, `cinematic-playable.png`; logs: `build/video-native-preview.log`, `video-native-console.log`, `video-native-stderr.log`.

No APK was built/exported. Reopen the editor and finish resource imports before the owner's manual Android export. The existing all-resources preset includes the recognized OGV and its arrival texture; keep `video/*` out of exclusions, and keep required island textures. Source/native checks do not prove the contents of a freshly exported APK or phone FPS/thermals/touch behavior.


## Rounded timber construction and systems update (2026-10-07)

The owner's latest reference supersedes the earlier clapboard/glass-window concept: foundations and roofs now have five closely joined rounded long timbers per tile, with two pairs of hemp wraps, small binding knots and underside cross-poles. Walls and half walls use five vertical rounded timbers and back cross-poles. Doors have five timber members and horizontal/diagonal bracing in the swinging leaf. Windows are permanent open frames with a clear gap and no glass, shutter or door panel. Legacy window open/closed flags load as open; only doors keep an interactive saved open state. Natural grain comes from the original generated photographic atlas documented in `textures/construction/PHOTOGRAPHIC_TIMBER.md`. Original boxes remain hidden placement/physics proxies, so tile sizes, support, saves and player collision remain compatible.

HalfWall is appended as build index 16 (older indexes are unchanged), costs 4 Wood and 1 Rope, and is 1.25 m high. CargoCrate follows at index 17, costs 6 Wood, 2 Rope and 1 Metal, and snaps to a supported deck/roof. It includes a wooden crate, rope coil and draped net, with a physical collision box. It is a decorative cargo prop; there is no second storage inventory. Cycle the build selection to reach these pieces; the first six mobile blueprint shortcuts retain their existing functions. New Game still starts on the original small raft, with the existing once-per-save testing supplies. The large camp in the renderer preview is a test fixture built from these same playable pieces.

A room bounded by full walls, doors or windows can be roofed in one action. The preview displays its total tiles/cost, and the entire cost is checked/spent transactionally; insufficient supplies cannot leave a partially paid roof. The enclosed-room flood fill is limited to 64 deck cells. A single wall or adjacent supported roof can offer one tile; aiming near a roof edge offers the neighbouring deck tile. Stairwells are excluded from automatic ceilings to preserve headroom. Upper floors and non-cardinal legacy structures retain the original socket path. A faint raft-local 2 m grid is visible only while constructing.

The existing rig now wears muted canvas/denim/boot vertex colours with a shared weave texture and includes a blended swimming clip. This is an adaptation of the original stylized CC0 model, not a photorealistic scanned character. First-person FOV is 75, with optional smoothly weighted 0.05 m head bob; the existing collision capsule and camera eye placement are retained. Third person uses a 5 m spring arm and a slight downward initial view when switching from a level first-person camera; its existing collision shortening and input ownership remain active.

Settings expose an 8-minute full day/night cycle (6–10 minutes) and head bob. The existing Sky3D clock remains authoritative. Low-frequency atmosphere updates add dawn mist, near-island night fireflies and sparse ocean luminescence; Battery Saver disables the GPU effects. Lamps automatically illuminate at night and preserve charge during daylight. High desktop Forward+ supports SSAO, SSR and volumetric fog; mobile fog/smoke is disabled under the later phone-effects policy. Static island ridge occluders avoid moving-raft occlusion updates.

`scripts/raft_construction_batch.gd` combines repeated geometry into shared MultiMesh draws while preserving individual physics roots, sockets and save identity. Highlighted pieces temporarily render separately. Per-instance material seeds use flat shader interpolation so perspective rounding cannot speckle the grain. The selected photographic texture is the cleaner second generated version; its retained import settings limit the runtime atlas to 1024 with mipmaps and BPTC/ASTC compression. Construction now reuses the included CC0 timber impact (`audio/chop.ogg`) instead of generated hammer/saw tones. A reused swim-particle emitter avoids per-frame allocation. Solver templates and shape caches are reused and released when the player exits its scene. This does not claim an unsupported texture streaming switch.

Ocean shading adds broader irregular wave slopes, filtered distant detail, stronger directional sunlight glitter, selected crest foam and darker troughs. The displaced height formula remains identical to `Ocean.get_height()` for buoyancy. Sky3D remains the source of the sunlight direction: glitter naturally changes as the player turns, rather than staying on one screen edge. Cumulus stays visible near the sea horizon with bounded grazing-ray sampling. Warm sunlight, soft diffuse fill without secondary glints, modest colour contrast and low-density haze improve timber depth. New Game still reveals dawn at 6.25; the reference preview uses late afternoon at 16.6. Continue keeps the saved time.

Saved data now uses authenticated AES-256 envelopes, a per-install random key and a verified temporary-file commit with backup recovery. Existing plaintext saves still load and migrate on a successful write. Keep the key alongside the save and backup when transferring data; losing it prevents encrypted-save recovery. Missing keys, failed writes and corrupt files preserve live inventory and existing recoverable saves. Built transforms must contain finite bounded values with a usable basis before restoration. See `VISUAL_BUILD_OVERHAUL.md` for implementation and test evidence. No APK was exported by this update; existing installed builds do not contain these changes.

## Natural island surfaces and placement (2026-10-07)

All four islands now use three textured rocky headlands with matching baked collision meshes. Existing island coordinates, terrain footprint, resource identifiers, crop pickups, player saves and navigation are retained. Rock surfaces share one 1K CC0 Poly Haven scan with diffuse, normal and AO/roughness maps; world projection avoids stretched cliff texture. The original home beach scan keeps its own albedo maps, with damp shoreline darkening and sand normal detail. The other islands replace their white placeholders with the CC0 Aerial Beach 01 material.

IslandBeacon is now a navigation anchor only: there is no light pillar, glowing orb or coloured island light. The existing map/HUD destination hint still uses its anchor. Palms below sea level search inward for dry terrain instead of floating above water; imported trunk colliders move with the root. Grove fruit names and saved health/regrowth/removal state stay compatible.

IslandLandscape waits for terrain preparation, then adds the owner's lowpoly plant kit and eight rounded boulders. IslandWildPlants places up to 44 new plants in eight shared MultiMesh batches (ten material draws), with at most 64 saved records including existing palms/grove trees. Trunks and shoreline rocks have simple solid collision; small plants are walkable interaction targets. Placement rejects submerged vegetation, keeps the front approach beach open, and uses at most sixteen terrain queries per frame. Interactive plants retain their visible instances in Battery Saver, with a 55m range, so solid trunks cannot become invisible. Decorative ground grass keeps its separate adaptive density budget.

Shallow-water colour and thin, broken shore foam use one 32-square terrain-height texture per island, prepared once with 16 queries per mobile physics frame (64 on desktop). The masks fade into deep water at their border. This keeps the existing opaque ocean pass and matching buoyancy waves; it does not add screen/depth/reflection passes or real transparent-water refraction. A shared 256-square seamless normal texture adds smooth irregular moving chop. Lower mobile sky profiles retain the atmospheric sky and cirrus while skipping the volumetric cloud march.

New free-asset sources, exact download fingerprints and retained BPTC/ASTC imports: textures/island/SOURCES.md. Preserve the existing required home-island scan textures and add textures/island when exporting manually. No APK was built. The focused island_visual_smoke suite passed 71 checks in isolated storage, covering all four colliders, actual dry palm roots, resource caches, removal of beacon visuals, shared materials, compact shore masks and mobile quality limits. The earlier 470-check run predates these island changes; it was not repeated at the owner's request.
The dense 800 m ocean patch and its disjoint far strips follow the active camera in X/Z, so island approaches use the same smoothly tessellated waves as the raft. The world-space wave sample and water Y are unchanged; focused checks verify that moving the rendered patch does not alter buoyancy height. Beach sand now replaces low shoreline vertex paint, and photographic detail replaces unfiltered high-frequency grain that caused stripes. The scan detector excludes imported trees, preventing their Sketchfab wrappers from suppressing materials on other islands.

## Crop models, portable wall fire and construction corrections (2026-10-07)

The supplied `tomato_plant.py.blend1` contains a plant-generation script and camera/light, rather than mesh objects. Its embedded source was inspected, copied to `tools/tomato_owner_source.py`, and explicitly run only inside a fresh Blender process with automatic embedded execution disabled. `tools/prepare_tomato_model.py` preserves the branching, leaf and fruit forms while reducing tessellation and baking leaf colour/normal detail into embedded 512px maps. The presentation pot, soil, ground, camera and lights are excluded. `models/tomato_plant.glb` has 13,235 triangles and six material surfaces. `models/potato_plant.glb` has 14,713 triangles and six surfaces: original compound oval leaves, white flowers, root fibres and eleven irregular tubers, guided by the owner's reference. It shares the owner's baked leaf maps. Provenance/budgets are in `models/crop_models.source.json`; these owner-derived materials are not asserted to be CC0.

Seed stages remain small soil bumps. Sprout/growing stages use continuously scaled crop meshes with fruit/flowers hidden; mature stages reveal them. Existing timers, watering, yield, seeds, planter compatibility and saved stage data are unchanged. Potato tubers are below the soil line. Hold the existing HAND/E harvest action: the whole plant lifts 0.38m over 0.42s, holds its roots/tubers in view for one second, then shrinks and delivers produce/seeds. A harvesting guard prevents duplicate grabs; full inventory rejects the harvest before animation and preserves the crop. Tomato harvesting retains the existing root-crop reward behavior.

Craft a Torch (2 Wood, 1 Rope), select it and use it near a burning campfire with 1 Wood to light it. Aim at a nearby solid wall face and press HAND/E: MOUNT transfers that owned torch and its remaining flame fuel into a wall bracket without charging a second recipe. Mounted flames provide a warm 5.5m light during gameplay, including night. Select Wood and use the wall torch to add 180s fuel (maximum 900s); a held burning torch lights a fuelled, extinguished wall torch. Use with an empty hand or other normal interaction item to take it back; a full bag preserves it. A lit pickup transfers its remaining fuel. Roof cover protects the flame; exposed rain extinguishes it while leaving the mounted fuel available for relighting.

WallTorch is appended at build index 18, leaving indices 0–17 intact. It can also be selected as a build piece (2 Wood, 1 Rope), initially unlit. Mounting accepts solid wall or lower window timber, clamps away from corners/ceilings, rejects overlaps and limits placements to sixteen per raft. It saves its raft-local transform plus optional `survival: {fuel, burning}` through the existing built-piece save/restore route. Torch fuel restoration accepts up to 900s. Transparent animated flames are explicitly excluded from the static wall/timber batch. Lights use no extra cubemap shadows on Mobile.

The survivor import's +Z front is rotated to gameplay -Z, fixing forward motion that appeared to walk backwards. A bounded two-bone right-arm modifier applies after walking animation while holding the launcher/torch in third person. The launcher follows the actual wrist position but camera aim determines barrel direction, preventing animated wrist roll from turning it backwards. Torch grip stays upright. First/third person visibility, muzzle anchoring and touch ownership remain intact. Rope casts use 12m/s² gravity with a solved initial velocity; segments are swept in at most 0.5m travel steps against solid physics objects, excluding the player. Moving-water crossings land on the current wave; walls/terrain recall the hook. Quick/charged ranges remain 20/60m, with existing automatic salvage, recall and full-bag release behavior.

Ground-floor wall hits continue on exact 2m foundation edge slots instead of thin front/back wall sockets; high wall hits retain stacking. Edge selection owns panel orientation; rotation flips its facing without turning it across the foundation. New stairs anchor at a supported deck's entry edge, match a 2.8m upper-deck top, test the real ramp and landing shapes, and reject low roofs above the character's path. Existing stair flights keep openings when automatic room roofing is calculated; skipped openings are never charged as roof tiles. Window collision remains the four solid frame/lower members with a physical clear opening.

Rope lashings now use three geometric helical strands, repeated tight wraps and figure-eight knots, with rough fine fibre shading. Rain fragments below nearby actual roof/upper-deck footprints are masked using at most 64 raft-local boxes; masks follow raft movement and roof removal. Covered rain audio is quieter and emitter restarts clear lingering drops. Ocean amplitude/speed are 1.25/0.65, with matching CPU/visual/raft-foam wave constants. An indexed 128x128 ocean patch concentrates its geometry within 80m of the camera; the far water strips remain bounded. A cached 128x128 R8 ground-foundation mask prevents crests drawing through solid timber. The supplied coconut GLB in `3d models` is byte-identical to the canonical `models/coconut_palm.glb` used by island and planter palms.

Focused final source checks passed in isolated storage: construction/weather 38, crops/torch 37 and rope 29 (104 checks). Related actual movement/survival and visual-building suites also passed 53 each during this update. Mobile/D3D12 desktop previews were inspected for mature plants, pulled potato roots, mounted night fire and third-person aiming, alongside the earlier open-window/rope/rain views. The full unrelated regression suite was not run. No APK was exported and no phone FPS, thermals or touch performance is claimed.

## Action feedback, soil and rainwater filter (2026-10-07)

SurvivalAction adds original distinct cast/reel, chop, crop pull, fruit pick, collection, earth gathering, planting/watering, building/crafting, eating/drinking, bandaging and equipment/fire/weapon motions, with short readable progress feedback. HeldArmPose solves the actual rig after its gait; matching first-person tools/hands avoid camera shake. Fingers flex toward each grip, with item-specific contact offsets and clearance for bulky produce. The fishing rod has a flexing tip and moving reel; the bobber travels in an arc, and the final reel raises a visible fish. These are original procedural key poses using the existing stylized rig, not motion-capture or photorealistic character animation.

Build input shows a 0.75-second ASSEMBLING bar and keeps the preview at its captured raft-local position. Materials are charged once at completion after rechecking support, range and the full smart-roof cost. Leaving build mode, changing selection, swimming or invalidating support cancels without spending. Both touch and desktop inputs use the same path.

PlanterPot costs 4 Wood + 2 Soil; PlanterBox costs 6 Wood + 4 Soil; TreePot costs 8 Wood + 1 Rope + 6 Soil. Gather Soil on island land above y=1; lower beach land gives Sand. Timber beds contain a single cached irregular soil mesh, clods and embedded twigs, with the existing CC0 beach scan for fine grain and moisture shading. Growth, watering and harvest rules remain compatible; potato tubers stay buried until the lift.

SandFilter is build index 19 (older indexes retained): 6 Wood + 4 Sand + 2 Sponge + either 2 Plastic or 2 Metal, preferring plastic when available. Sponge now appears in ocean salvage. The larger timber-supported plastic/steel can shows sand, sponge and a collection container. It collects and filters rainwater after 20 active exposed-rain seconds, holds five Water, needs no fuel, and pauses beneath a roof. It uses existing machine water/seconds saving. It does not turn seawater into drinking water; the existing heated purifier remains available. Collection is capacity-safe.

New placed pieces save optional actual paid cost metadata for accurate refunds and alternative container selection. Restored values are recognized, bounded resource costs. Older pieces without it retain their legacy costs (old planters cannot refund newly required Soil).

Raft buoyancy samples each foundation's corners/centre and shared edges against Ocean.get_height, using the highest crest plus clearance instead of the average. Upward safety clamping and smooth settling keep expanded/rotating decks clear of waves; the existing ocean deck mask remains active. Dense source probes passed with over 0.60 m deck clearance. No movement, foundation grid, inventory capacity, testing supplies or owner saves are reset.

Focused verification: rope 29, actions/farming/building/buoyancy 40 and cinematic 39 checks passed in isolated storage (108 total). The action checks include excluding the first-person hand from third-person items even when deferred node names change. Earlier affected crop/torch and construction/weather suites passed 37 and 38 checks. Desktop Mobile/D3D12 previews covered soil, filter, cast/reel, grip, harvest and build progress. The final native preview exited cleanly. The updated intro contains one stereo Vorbis audio stream and the preserved 848x480/24 fps Theora video stream. No APK export or phone performance test was performed.

## Smaller windows and calmer floating raft (2026-10-07)

Window keeps the same 2 m wide, 2.5 m high outer frame and sockets, but its unobstructed opening is now 1.04 m wide by 0.87 m high instead of 1.56 by 1.74. The lower wall and side panels are joined timber with matching solid collision. There is still no glass, shutter or door; old closed flags load open.

Ocean wave height is now 0.68 (previously 1.25), with speed 0.52 (previously 0.65). Lower ripple-normal strength, restrained whitecaps, softer trough contrast and broken sunlight highlights keep a calmer detailed sea. CPU buoyancy, ocean vertex/fragment waves and hull foam now share Ocean's explicit wave_time uniform rather than mixing scene time with the engine's global shader TIME; this prevents loading-time phase mismatch.

The physical AnimatableBody raft now gently pitches and rolls toward the sampled swell, up to 1.6 degrees, with smaller limits for expanded bases. It smoothly bobs and rides lower: default float_height 0.045 and follow_speed 9.0, bounded 0.035-0.085 m above the supporting sampled crest. Rounded log undersides remain immersed. Every sample compensates for its tilted corner height, retaining a dry deck. Lower water/wave scale replaces the previous unusually high 0.60 m default. Dense quarter-metre probes across the expanded rotating raft measured at least 0.269 m deck-surface clearance in this update.

Build/edit mode holds pitch and roll level for the existing exact grid/socket solvers, retaining yaw. Sailing displacement, pitch/roll and buoyancy are committed in one transform because sync_to_physics overwrites earlier queued component setters. Construction still stores stable raft-local piece transforms; there are no new saved fields or recipe changes.

Focused checks passed: construction/weather 39 and actions/farming/raft 46 (85 total), including a ray through the window, solid side collision, dry deck probes, real rocking, bobbing, level construction, standing on the raft, synchronized wave time and navigation on both axes. The short Mobile/D3D12 renderer preview exited cleanly and visibly changed height and tilt. Images: build/smaller-open-timber-window.png, gentle-ocean-floating-raft.png and gentle-ocean-raft-swell.png. No APK was exported and phone performance remains unverified.


## Shelter, stairwell, crafting and plantable food corrections (2026-10-08)

BAG → CRAFT now includes Plant Pot, Plant Bed and Tree Pot on its first page, followed by all construction and equipment recipes on six-card pages. A recipe tap only selects its details. The separate detail panel lists each full material name with HAVE / NEED, highlights shortages, and requires CONFIRM CRAFT for portable equipment. CHOOSE BUILD SPOT selects a structure; aiming and PLACE confirm its actual construction cost. Pots can be positioned on clear top surfaces of a supported foundation or roof; the full base must be supported. Other deck equipment also permits the raft. These props do not require the one centre socket. Pot costs remain 4 Wood + 2 Soil, bed 6 Wood + 4 Soil, and tree pot 8 Wood + 1 Rope + 6 Soil. Gather Soil on island ground above y=1; beach gathering remains Sand. Materials are still spent only on successful placement.

The normal HUD has HEALTH, WATER and HUNGER percentages, with a pulsing red LOW warning at 25% or below. The resource-count pills are removed. Build feedback and crafting still show material counts where needed. USE has a larger touch target above and to the left of CAST, separated from climb/edit controls. Tapping a bag item exposes USE / EAT (or USE / DRINK) and HOLD TO PLANT / HOLD ITEM. Equipping a bag item swaps it safely into the selected hotbar slot. USE from the bag explicitly eats/drinks; world USE plants a held crop when aiming at compatible soil. Finger ownership, release and modal input blocking continue through the existing routing.

Potato, carrot, tomato, onion, coconut and banana are both edible and plantable items. Potato/carrot/tomato/onion fit a Plant Pot or Plant Bed; coconut/banana use Tree Pot. All pots require a foundation or roof top. Any of the six crops may be planted on reachable dry, mostly level island sand/soil without a pot (above y=0.4, upward normal at least 0.82), with at least 1.1m spacing and a maximum of 64 ground crops. Wet/steep/blocked ground is rejected without consuming food. The existing growth, watering, maturity, root digging, individual fruit picking and tree chopping rules remain. Root harvests combine their former food and seed rewards into produce that can be eaten or replanted. Existing Seed item identifiers are canonical aliases for their crop: loading old inventory changes the item name while preserving count and slot location, and inventory capacity simulations use the same alias. Crop icons show produce artwork rather than packets; onion uses a render of the supplied bulb.

GroundPlot subclasses Planter and draws only a soil patch/plant slot. Optional top-level `ground_crops` records store island node path, island-local `p: [x,y,z]`, normal nested plant state and moisture. Missing records mean no ground crops, preserving old saves. Restore accepts at most 64 records on an actual island with finite bounded positions. Harvesting/removing the ground plant frees its patch and queues a save. Built planter records and all existing building indexes are unchanged.

Foundations keep canonical 2m occupancy and snap their visual/placed orientation to 90-degree turns, including after a fine rotation. Aiming at the centre of an occupied cell shows red instead of selecting an unrelated free neighbour. The ghost uses whole-mesh material overrides, including timber details and MultiMeshes, so invalid pieces visibly stay red.

Roof roots now use `roof_opening.gd`. Ceiling tiles are retained around stairs instead of omitting whole tiles. Matching flights cut one continuous 1.4m-wide corridor from stair-local Z=0.45 to 2.90; visual panels and actual collision share the same rectangles. Stairs may be added beneath a ceiling at their destination level; walls and other headroom obstructions are still rejected. Cut geometry is derived from existing stair/roof transforms, including restored saves, and closes when the flight is removed. Roof geometry revisions invalidate the timber batch. No separate saved hole field is needed.

Rain masks follow the actual enabled ceiling panel colliders, including stair cutouts, and also mask the solid members of walls, windows and doors. Roof masks take priority within the bounded 64-mask budget. Empty structure lists clear old uniforms; indoor splash hits are discarded. The masks follow raft movement and turning, while rain remains visible outside and through a real open stairwell. Desktop rendering and isolated checks are recorded separately from phone evidence. No APK export is part of this change.

Banana and early crop growth (2026-10-08): planted and island-grove bananas share models/banana_plant.glb, prepared from the supplied banana-tree FBX (LOD1, 1,998 triangles). Missing source texture maps are replaced by original vertex colours; provenance is recorded in ASSET_CREDITS.md and models/banana_plant.source.json. The raw source folder is excluded from Godot imports, while the prepared GLB is bundled. All five crops show small foliage immediately and grow continuously from 16 percent scale. Aim at a young plant or its occupied pot/ground plot within 3.5m to see the remaining growth time as minutes:seconds. Dry soil shows a watering warning and an estimate at the current slower growth rate. Mature plants show ready/harvest prompts; tree fruit can be aimed at individually and regrows after picking. Young tree collision grows with the stem rather than using a full adult canopy box. Existing planted state remains compatible; no additional save fields were needed for countdowns or banana visuals.

Carrot source integration (2026-10-08): models/carrot_plant.glb now uses the supplied carrot_plant.blend model, with merged/reduced feathery foliage and an underground carrot root. It shares immediate small-plant growth, pot/ground countdowns, watering and edible/replantable harvests with the other crops. Carrot harvesting lifts the whole plant 0.45m to reveal the root before collection. Raw Blender source is excluded from runtime imports; prepared geometry and owner-asset provenance are retained. Plant prompt controls are freed with their plant and hidden during inventory/crafting, preventing stale overlapping countdowns.

Validation for the 2026-10-08 changes: 429 checks passed across nine focused suites (shelter/farming/UI 80, foundation 17, construction/weather 39, actions/farming 46, survival loop 53, mobile controls 93, crop/torch 37, visual construction 53, testing supplies 11). A separate Mobile/D3D12 desktop run passed all 80 shelter/farming/UI checks with no script or renderer errors. Inspected previews: build/fixed-craft-confirmation.png, fixed-produce-use-and-percentages.png, fixed-banana-sapling-countdown.png, fixed-banana-grown.png, fixed-carrot-sapling-countdown.png, fixed-carrot-grown.png, fixed-carrot-root-harvest.png, fixed-single-stair-opening.png and fixed-sheltered-rain.png. Tests used tools/verify_source.ps1 with separate custom user storage; the owner's normal saves were not reset. No APK was built/exported and real-phone behavior/performance remains unverified.

## Roof/foundation pots, onion agriculture and clear mobile air (2026-10-08 follow-up)

PlanterPot, PlanterBox and TreePot require an actual upward top hit on Foundation or Roof. They reject ocean, island ground, bare raft, side faces, deck overhangs and roof stair openings, with red previews at the attempted position. Nine probes across the full base test the real enabled deck/roof collision panels. Placement does not project a missed ray onto a nearby foundation or clamp the pot back from an edge. PLACE rechecks before spending; moving/confirming an existing pot uses the same solver. Editing props preserves foundation occupancy and restores each collision shape's prior enabled state, including growing/fruit collision. Existing saved pots retain their transforms. Direct island planting remains available for all six produce crops without pots.

Onion uses the owner's original real_onion_plant.blend geometry, prepared as four growth GLBs for the existing Seed/Sprout/Growing/Mature states. The carrot similarly uses the supplied carrot_plant.blend through its prepared GLB; .gdignore only prevents automatic raw Blender imports, not use of those source assets. Onions show a small plant immediately, then continuously enlarge while switching to supplied developing leaf/bulb forms. Growth takes 20 + 35 + 25 seconds at normal soil moisture; dry soil grows at one quarter speed and the aim countdown reflects that. A mature onion is dug for 1.2 seconds, lifted to reveal its bulb, and gives 2–4 harvest onions plus the former two seed rewards as edible/replantable onions. USE eats one for 14 hunger. New games receive four onions once; continued games can collect four from the new Home Isle Onion cache without changing previous pickup IDs. Onion Seed is a canonical alias. Held food, world pickups and the inventory icon derive from the supplied mature bulb. Saved plant/ground formats and building indexes remain unchanged.

Phone smoke/fog policy: GameSettings.mobile_effects_profile() recognizes mobile, Android and iOS features. OceanAtmosphere never creates MorningSeaMist on phones, and disables Environment depth fog, volumetric fog and Sky3D screen fog at every quality setting. RainSystem also enforces clear air at startup, rain start and intensity updates, preventing storms from restoring fog. Weather, rain drops, lighting, fire and gameplay continue normally. Desktop visual verification can opt into this policy with the --mobile-effects user argument; tools/verify_source.ps1 accepts -GodotUserArgs @('--mobile-effects') while keeping its isolated save directory. No additional setting or saved field is introduced. Island wildlife's deferred population now checks island validity after yields so a removed ground-farming test island cannot cause a freed-instance error.

Follow-up validation: 586 checks passed across 13 focused source suites: planter/onion 51, shelter/farming/UI 89, clear mobile air 28, foundation 17, crops/torch 37, actions/farming 46, construction/weather 39, survival loop 53, mobile controls 93, visual construction 53, testing supplies 11, environment 41 and world visuals 28. The latest planter/onion, shelter and clear-air source runs used --mobile-effects. Separate Mobile/D3D12 desktop previews passed all 51 planter/onion and 89 shelter checks without script or renderer errors, also with the phone effects policy. Inspected images include build/onion-roof-and-red-ocean.png, onion-roof-pot-countdown.png, onion-sprout-countdown.png, onion-grown-in-soil.png, onion-bulb-harvest.png, fixed-carrot-grown.png and fixed-carrot-root-harvest.png. Native farming fixtures have visible soil/foundation surfaces; tests do not place crops in the ocean. World visual expectations now recognize the supplied BananaPlantModel and explicitly sample the current wrist follower for headless verification. The owner's normal saves were untouched. No APK was built/exported; phone touch/performance remains unverified and the source changes require the owner's next manual APK export.


## Compact stairs, clock alignment and salvage visuals (2026-10-08)

Stairs now occupy 1.4 m by 3.0 m instead of 2 m by 4 m. Twelve 23.3 cm treads cover a 2.8 m continuous ramp; the 20 cm landing meets the existing 2.8 m upper-deck top. Its 43.4 degree slope stays below the player's 45 degree walking limit. Stacking uses the new landing endpoint. Saved piece transforms and recipe costs are unchanged. The single ceiling corridor ends at stair-local Z=2.90 and closes when stairs are removed. Foundations may overlap the bottom of a flight only when their upper face remains below its foot; actual walls and machines still block placement. A ground-floor stair landing supports a grid-aligned roof tile and its immediate supported neighbours without requiring a wall first.

Sky3D remains the only clock, with the current 8-minute default and saved calendar/time. The scene uses the addon's astronomical sun calculations at a tropical latitude of 8 degrees, longitude 82.5 degrees and UTC+5:30; the later visible-night-moon update supplies the moon path. Celestial updates run at 10 Hz. Morning/night ambient and fill lighting follow sun elevation continuously instead of jumping at fixed hours. New Game still starts at 6.25 and Continue preserves its saved time. Softer cloud coverage improves scale; lower phone cloud profiles retain two-sample sky clouds without volumetric marching or screen fog. The existing no-phone-smoke/fog policy remains in force.

Water replaces crossed sine micro-ripples with filtered irregular moving normals, softens distant specular aliasing and reduces whitecap speckle. The old large minimum RGB value flattened night water into solid blue; a small additive night fill now retains visible wave contrast. CPU/vertex wave heights, shared wave_time and raft buoyancy are unchanged.

Floating driftwood and barrels use original shared smooth meshes, irregular cut ends, barrel stave seams and separate rusty metal bands. Existing pickup identities, collision dimensions, current and buoyancy remain. All salvage retains shared weathered materials; salt and wetness variation and end-grain orientation are corrected. Potato skin has irregular eyes, tomato geometry has softer shoulders and banana ends darken naturally. Tomato/potato plants display the same produce geometry/skin as harvested food. Imported crop foliage retains the owner's textures and normal maps, with shared softer double-sided leaf materials. No new external assets or licenses are required. The three produce inventory PNGs are re-rendered from the updated models and reimported separately.

Testing Soil has grant revision 2: existing saves from the previous testing grant are topped up to 2,000 Soil once when sufficient bag space exists. New saves receive 2,000 Soil. The revision is saved, preventing repeat refill on Continue; spent Wood/Rope/Plastic/Barrel/Stone/Metal retain their existing once-per-save rules. Full bags defer the unaccepted remainder until a later load with space. The player's normal save files are never edited by source verification.

Validation: 383 focused source checks passed across nine suites (stairs/sky 27, construction/weather 39, foundations 17, testing supplies 11, shelter/farming/UI 89, environment 41, edit/tree/materials 110, menu/loading 21 and world visuals 28). Mobile/D3D12 desktop previews passed 31 stairs/sky checks and 119 edit/tree/material checks. The actual CharacterBody walks up and down the compact flight through its shared ceiling opening. Rendered previews cover the full staircase, morning/sunset/night water, produce and every floating salvage type; refreshed produce PNGs were imported separately. The verifier now captures complete native stderr before evaluating failures, and the preview helper retains its Windows process handle for a reliable exit code. All game runs used isolated user storage. No APK was exported; phone performance/touch behavior remains unverified.


## Food action animation and repaired intro motion (2026-10-08)

Eating now lifts an independent edible prop, holds it near the mouth for two soft bite contacts, then lowers it over 1.75 seconds. Drinking uses a separate can tilt and two sip contacts over 1.55 seconds. Independent first/third-person props remain visible after the last selected item is consumed. Action cancellation/completion removes those props and restores the selected hand item; sound cues fire once and skip stale contacts after a long frame. Food nutrition, atomic inventory exchanges and empty-can returns keep their existing immediate behavior. First-person food tilts independently of the forearm to avoid clipping into the camera. Third-person fingers keep their food grip even when the consumed inventory slot is empty.

Starting a recipe shows a two-second stirring preparation with a wooden spoon and left-hand bowl. CookingSetup replaces its solid sphere with an open metal pan and three-legged stand. Active station jobs show food browning and five small surface bubbles at 10 Hz; there is no smoke or fog. Fire-out pauses the existing job, hides bubbles, stops its sizzle and displays FIRE OUT. Relighting resumes the saved remaining time. Cooking visuals are created only for cooking jobs; distant jobs stop their audio and bubble animation beyond 12 metres. Completion clears visuals, awards/overflows one dish through the existing capacity-safe path and plays a quiet contact cue. The existing cook/filter save format is unchanged.

Five original small preloaded PCM sounds add bite, sip, stirring, spatial cooking sizzle and food-ready feedback. Harvesting, planting, digging, bandaging and equipment fitting also receive timed cloth/handling feedback using the already credited rustle. Sounds use the Master bus and do no runtime sample synthesis. These are procedural animations on the existing stylized character, with no motion-capture or new character rig.

The owner's original intro timestamps contained two 1.042-second holds at approximately 15 and 23 seconds. Offline preparation stretches the preceding moving shot over each gap while preserving the original soundtrack timing. Cut-aware interpolation produces a 720 × 408 / 30 fps Theora stream with one-second keyframes; no interpolation runs in-game. Captions, Skip/Back, background pause, save protection and the dawn handoff retain their existing behavior. Final arrival still uses the original last raft shot.

Validation: 316 isolated source checks passed across food actions (34), survival services (85), action/farming (46), cinematic/raft (39), menu/loading (21) and mobile (91). The native Mobile/D3D12 food fixture passed 34 checks and rendered eating/drinking and preparation in both camera views plus the simmering pan. Full repaired-film playback completed all eight subtitle cues, dawn handoff and playable controls at a desktop p95 of 33 ms / maximum 34 ms, excluding screenshot export time. Offline full decode found no long freeze before the final arrival. The food preview had no stderr warnings; the full-world cinematic fixture still reported the existing ObjectDB shutdown warning (10 instances). No APK was exported and phone FPS/thermals/touch remain unverified. Preview files: `build/food-eating-first-person.png`, `food-eating-third-person.png`, `food-drinking.png`, `food-preparing-food.png`, `food-preparing-third-person.png`, `food-simmering-pan.png`. Offline media check: `tools/verify_intro_video.py --ffmpeg <executable>`.
