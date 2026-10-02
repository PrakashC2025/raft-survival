# Skill: Island Visuals (RaftSurvival / Godot 4.7)

## What this skill covers
Everything visual on the procedural island in this repo: terrain sand/grass/rock,
ocean, vegetation bakes, the apple tree, and the "grid pattern" class of bugs.
Read this BEFORE touching island visuals. Keep it updated after every change
(changelog at the bottom).

## Project facts
- Engine: Godot 4.7.1 (mono). Editor exe:
  `C:\Program Files\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe`
  (console variant: `..._console.exe`). In bash: `/c/Program Files/Godot/...`
- Project root: `C:/GodotProjects/raft-survival` (run terminal commands from here).
- Renderer is Mobile; scene uses ACES tonemap. Ocean uniforms are pushed as
  linear HDR (NOT source_color).
- Headless bake (run from project root):
  ```
  "/c/Program Files/Godot/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe" --headless --path . --script tools/bake_island_vegetation.gd
  ```
  First run imports assets and can take a few minutes; wait (timeout 600 s).
  Outputs land in `res://grass/baked/*.tres` and are committed.
- Headless script check:
  ```
  ..._console.exe --headless --path . --check-only --script <file.gd>
  ```
- There is no `tsc`/npm here; "typecheck" = the Godot script check above, or a
  `--headless --quit` run that prints parse errors.

## Asset pipeline
- `tools/bake_island_vegetation.gd` (@tool, extends SceneTree) bakes ALL real
  models once, at edit time — never at game start. It produces:
  - `palm_island.tres` — coconut_palm.glb merged, 5 surfaces; surface 2 is the
    alpha-scissor frond surface (gets the sway shader at runtime).
  - `coconut_sprout/young/mature.tres` — palm growth variants.
  - `grass_clump.tres`, `scan_tuft/dandelion/groundcover/flower.tres` —
    scattered undergrowth.
  - `apple_tree.res` — THE apple tree mesh (from models/apple_tree.glb,
    4 surfaces: ETG_BARK trunk, apple.leaf foliage, Apple fruit,
    ETG_BARK.apple fruiting twigs). ALL big bakes save as BINARY `.res`
    (text .tres parsed 10-20x slower and stalled the loading bar at 92%).
  - `apple_single.res` — ONE real apple isolated by largest connected
    component, 16 cm, pivot at the stem (top).
  - `apple_tree_mobile.res` — MOBILE twin of apple_tree.res (30th pass):
    same 5.7 m tree, same surfaces/materials/metas ("fruit_anchors", "src"),
    but 250k leaf-tri budget + second meshopt pass + no tangents (its
    materials carry albedo only) + 768 px texture cap → 16.4 MB vs 35.4 MB.
    Runtime picks it via `_mobile_bake` in plant_instance/island_generator;
    the Android export preset excludes the desktop `apple_tree.res`.
  - `coconut_bunch.res` / `coconut_single.res` — from king_coconut.glb
    (11 identical bunch copies + 1 stem): the whole bunch shell (~1176 tris)
    and the largest connected nut. The nuts INTERPENETRATE (contact necks
    as tight as intra-nut triangle spacing) so centroid-cut splitting can
    never isolate one nut — the single falls back to the whole shell,
    scaled small instead.
- Apple tree bake internals (see `_bake_apple` in the tool):
  - `nm.containsn("leaf")` → foliage; `nm == "Apple"` → fruit;
    `containsn("bark") && containsn("apple")` → fruiting twigs. These exact
    names matter; `containsn("apple")` alone would swallow the LEAF surface.
  - Foliage: `_cull_leaf_components(idx, 600000)` — union-find leaf CARDS,
    drops whole cards (never triangles inside a card; random dropping made
    the moth-eaten canopy). 600k ≈ 49% of 1.22M leaf tris → dense crown
    matching the glb preview (200k-500k read progressively twiggier).
  - Bark/twigs: `_simplify_skin` via `ImporterMesh.generate_lods` (meshopt,
    topology-preserving). Ratios: bark 0.45 (0.25 shaved the trunk smooth),
    twigs 0.60.
  - Fruit surface kept whole; apple_single takes the largest connected
    component of the Apple surface.
  - Textures downscaled to `APPLE_MAX_TEX` (1536) via `_baked_apple_material`.
  - Result: apple_tree.res ≈ 692k tris, 5.7 m, 3 surfaces (bark / alpha-
    scissor leaves / twigs), ~37 MB binary. One mesh for ALL growth stages
    + the island tree.

## Runtime systems
- `scripts/island_generator.gd` (class IslandGenerator, Node3D, group "island"):
  - `terrain_height_local(q)` is the CPU height field; BASE radial profile +
    `coast_wobble` + `lagoon_mask` are mirrored EXACTLY in shaders/main.gdshader
    `island_base()` — closed-form math only (no hash noise on the GPU side).
    KEEP-IN-SYNC comment applies to R_SHORE=32, R_OUTER=68, DEEP=12, BEACH_H=2.6.
  - Terrain sheet: grid_step 1.75 m, grid_half 140 m, vertex-colored
    (sand/wet/grass/rock/soil/pond mud), material = shaders/terrain_sand.gdshader
    on desktop, shaders/terrain_sand_mobile.gdshader on mobile (see
    `_terrain_shader_path()` — the compile-light clone; NEVER raise the
    mobile shader back toward the desktop noise budget, phones fail to
    build the pipeline and the island vanishes).
  - Sand rule (used in 4+ places — terrain paint, `is_sand_at`, island_grass
    mask, bush placement): `sand_h = 1.3 + (jitter-0.5)*1.4`;
    `grass_k = smoothstep(sand_h, sand_h+1.4, h) * smoothstep(0.62,0.86,slope_y)`
    where `jitter = _fbm(q*0.22 + Vector2(51.2,17.3))`. Keep these in sync!
  - The island spawns exactly ONE apple tree: `_scatter_props` scores 160
    candidate spots (flat + palm-clearance), best wins, always placed as
    `PlantInstance` with `start_stage = MATURE`, `plant_id = "Apple"`.
- `scripts/plant_instance.gd` (class PlantInstance, StaticBody3D):
  - `GROWTH_VARIANTS` maps plant id → baked stage meshes. Apple uses ONE mesh
    (`apple_tree.tres`, 5.7 m tall) at all stages; container scale animates.
  - `_tree_surface_overrides()` puts PALM_FROND sway shader on alpha-scissor
    surfaces ONLY for palm-sourced meshes (`sway_allowed` checks the baked
    mesh's `src` meta for "apple"). The apple's leaf cards are alpha-scissor
    too; sway (height-keyed to palm crowns) used to squeeze the whole apple
    canopy down to the trunk. NEVER re-enable sway on apple foliage.
  - Fruit crown anchors: canopy-fruit plants (`fruit_layout == "canopy"`, the
    apple) measure the REAL foliage — mean vertex height + max radius of the
    mature mesh's alpha-scissor surface(s) — instead of `_tree_top * 0.86`
    (which sat ~1 m above the bare upper twigs and floated apples in air).
    Hang-layout plants (palm) keep the heuristic.
    Each fruit gets material_override = shaders/fruit_tint.gdshader
    (ripeness 0→1 mixes leaf-green → real apple texture; needs albedo/normal/
    roughness textures from apple_single.tres material).
  - `start_stage = -1` = grow from seed; `3` = spawn already MATURE.  - `scripts/plant_data.gd` — PlantDB defs. Apple: fruit_count 8, fruit_mesh
    apple_single.tres, fruit_falls true, fruit_scale 1.8, food_value 30.
    Coconut: fruit_count 5, fruit_variation true, fruit_fall_item Coconut,
    fruit_fall_days 2.0 (daily drop / 2-day regrow cycle).
  - `scripts/coconut_pickup.gd` — physical dropped coconut (CoconutPickup,
    debris-compatible, CCD + thud physics, 300 s despawn).
- `scripts/island_grass.gd` — MultiMesh grass; samples where the terrain paint
  rule says grass (gk >= 0.5), never on sand.
- `scripts/footprints.gd` + `shaders/footprint.gdshader` — ring-buffer MultiMesh
  footprint stamps on sand only.

## Shaders (shaders/)
- `terrain_sand.gdshader` — vertex-color terrain. Masks: brightness/greenness
  → sand_mask; noise-warped world-height wet zones; foam wash lines near the
  waterline; mountain rock/soil breakup above the grass line. All foam/ripple
  patterns run through a 30°-rotated, fbm-warped coordinate `fuv` (never
  axis-aligned — see the grid bug below). Sand grain/ripple detail is
  DISTANCE-SCALED via `close_k` (full grit under ~5 m, calm by ~26 m).
- `main.gdshader` — the ocean. Waves L1..L4 + meander M1/M2 + envelope E1/E2,
  mirrored in `scripts/ocean.gd get_height()`. Island shallows via
  `island_base()`. Its shore foam `breakup` term is
  `sin(world_pos.x * 1.15 ...) * sin(world_pos.z * 0.95 ...)` — axis-aligned,
  which painted a faint GRID on the submerged sand near the shore.
- `palm_fronds_sway.gdshader` — palm fronds only (double-sided, height-banded
  sway). Do NOT let it apply to other trees' foliage.
- `fruit_tint.gdshader` — apple ripening (green → texture), needs the three
  texture uniforms wired from the baked material.
- `grass_wind.gdshader`, `rock_triplanar.gdshader`, `fresh_water.gdshader`,
  `footprint.gdshader` — as named.

## The "grid on the sand" bug (root causes, FIXED 2026-09-15)
1. Ocean shore-foam `breakup` used axis-aligned `sin(x)*sin(z)` — an invisible
   grid of foam strength over the shallows; where submerged sand glowed
   through, it read as a grid. FIX: two rotated incommensurate waves
   (bdir1 ~36°, bdir2 ~115°) — no preferred axis, cannot tile.
2. Terrain wet-sand foam wash lines `sin(uv.x ...)` / `sin(uv.y ...)`
   (independent x and y terms) → faint cross-hatch on wet sand. FIX: all foam
   line phases + the breakup now run through a rotated (30°) coordinate `fuv`
   with an fbm domain warp; the wet-sand band edge itself is noise-warped
   (`wet_warp`) so the damp stripe is ragged like real sand; ripples also run
   along the rotated axes.

## Known pitfalls
- ANY water/weather pattern must use HASH/VALUE NOISE, never products or sums
  of sine waves. sin(a)*sin(b) forms a perfect egg-crate DOT LATTICE (user
  screenshot 2026-09-15: regular dotted rows across the whole ocean); sums of
  3 plane waves form a hexagonal lattice; sin(x)*sin(z) along world axes makes
  grids. main.gdshader now has hash21_o/vnoise_o helpers — rain roughening,
  churn flecks, micro ripples and glitter chop ALL go through noise (gradients
  via forward differences with ne=0.10).
- Terrain shader albedo constants are LINEAR (ACES scene): a "looks pale"
  sRGB-ish value like (0.82,0.74,0.56) displays near-white. Keep sand albedo
  ≤ ~(0.70,0.60,0.42) linear. Large-scale sand variation must be
  MULTIPLICATIVE hue patches — additive dark subtract-clouds read as camo
  blotches (the 2026-09-15 "snow-camo sand" bug).
- NEVER drop leaf triangles randomly — always whole cards via union-find.
- NEVER apply palm sway shader to apple foliage (squashes leaves to trunk).
- NEVER anchor canopy fruit at a fraction of tree height — measure the leaf
  surface (mean height / max radius). AABB tops on the scanned tree are bare
  twigs.
- `--check-only --script` fails on scripts referencing autoloads (e.g.
  `Inventory` in plant_instance.gd) with "Identifier not found" — that is a
  check-mode false positive, NOT a real error. Verify with a headless
  `--quit-after 60` boot of scenes/main.tscn instead.
- Surface material names in apple_tree.glb are exact: "ETG_BARK", "apple.leaf",
  "Apple", "ETG_BARK.apple".
- `_simplify_skin` target picks the FIRST LOD at/below ratio — smaller ratio =
  fewer tris but flatter bark detail.
- Godot imported textures must exist as .import files; after adding textures,
  run the editor once (or the bake) so imports happen.
- When changing ANY of: sand paint rule, ocean island_base constants, wave
  constants — update BOTH the CPU (scripts/) and GPU (shaders/) copies.
- Prop placement MUST use `_ground()` (rendered-surface interpolation),
  NEVER `terrain_height_local()` directly — the analytic field floats above
  the visible mesh between grid vertices. New prop types: call _ground.
- Rain is exported `rain_color` on RainSystem (water-blue). Splash + streak
  materials both derive from it — change one property, not two materials.
- plant_instance `_tree_surface_overrides` is cached statically per mesh —
  changing bake output requires a game restart (or clearing the cache).

## Changelog

- 2026-09-25 (31st pass): NO-HANG BOOT + AUTO-QUALITY GOVERNOR (user:
  "hanging highly on my phone, fix hanging on any phone automatically,
  smooth experience with best graphics"). mobile_perf.gd rewritten from
  one-shot static cuts into a TWO-HALF AutoQuality system (autoload name
  and path unchanged):
  1. BOOT TIERING — `MobilePerf.device_tier()` classifies phones LOW/MID/
     HIGH from `OS.get_memory_info()["physical"]` + `OS.get_processor_
     count()` (desktop is always HIGH). Every subsystem now asks the tier
     for its budget instead of hardcoding "mobile" cuts: `grass_clumps()`
     (5000/6000/7000 baked-field cap), `palm_chunk()` (3/4/5 per frame),
     `palms_scale()` (0.55/0.7/0.8 of the grove), `terrain_rows_per_
     frame()` (8/12/18), `prewarm_window()`/`stall_window()` (menu loading
     guards — the fixed 8 s prewarm cutoff kept cutting off the 16 MB
     mobile apple parse), `scaling_base()` (0.70/0.80/0.90). All statics,
     safe via preload (no autoload-order or cycle issues; island_grass
     preloads island_generator which preloads mobile_perf).
  2. RUNTIME FPS GOVERNOR — a 90-frame ring buffer judges the MEAN frame
     time per ~1.5 s window against the 60 fps budget; one bad window
     drops one LADDER rung (render scale → rain → grass visibility →
     grass density), three good windows give one rung back. Degrade fast,
     restore slow, 3 s cooldown, never above the boot-tier settings, and
     only GAMEPLAY frames count (loading spikes never buy downgrades —
     the governor resets while the "island" group is missing). This is
     what makes mis-tiered phones self-correct within seconds.
  3. FIRST-LAUNCH TERRAIN FREEZE KILLED — the ~10 s single-frame n²
     height+paint pass (the biggest remaining phone hang) is now chunked
     row-batches across frames (`_terrain_compute_async`, awaits between
     batches). PARITY-CRITICAL discovery (tools/check_terrain_parity.gd):
     the old fused loop painted each vertex against a PARTIALLY-FILLED
     heights array — the right/below neighbors were still 0.0 at that
     instant. Pre-computing all heights first (the "obvious" chunking)
     repainted 98% of the island (worst Δ0.33). The chunked version keeps
     the exact per-vertex order and suspends only BETWEEN row batches:
     verified 0/25921 diffs vs the old loop AND byte-identical cache
     vs the shipped user:// file (`cmp` PASS).
  4. Misc: palm chunk size from tier; `_phase` now `await`s its callable
     (async phases suspend internally); rain budget applies on
     `node_added` (the old one-shot lookup fired before the rain node
     existed — it never actually applied); menu prewarm/stall windows are
     tier-based; island_grass joins group "grass_field" + exposes
     `governor_quality(vis_mul, count_mul)` (re-writes instance data from
     the retained full bake; visibility range always adjustable).
  - Debug/verify WITHOUT a phone: `RSM_FORCE_MOBILE=1 RSM_FORCE_TIER=low
    godot --headless --path . --quit-after 600 res://scenes/main.tscn`
    exercises tier detect + chunking + governor (observed: rung 1 down,
    rung 0 restore); `tools/check_terrain_parity.gd` proves cache parity.

- 2026-09-25 (30th pass): LOW-END TEXTURE MEMORY (user: "reduce mobile
  texture memory further"). Measured first with the new
  `tools/probe_vram.gd` (reports every texture embedded in the bakes:
  dimensions/format/bytes, deduped): vegetation textures were ALREADY
  VRAM-compressed at ~13.8 MB total — the palm's 15 maps (11.5 MB) are the
  biggest block, and the 37 MB apple bake is ~95% MESH data, not textures.
  Cuts shipped:
  1. Detail-map strip on phones: island_generator + plant_instance now
     null NORMAL + ROUGHNESS textures on every loaded bake material
     (`_strip_detail_maps`, once per mesh) — ~8 MB VRAM back on the palm
     alone, invisible at 0.85 res scale / phone distances.
  2. `apple_tree_mobile.res`: half-density leaves (whole-card cull,
     250k tris), second meshopt pass on bark/twigs, NO tangent arrays
     (materials are albedo-only — tangents were 16 B/vertex of waste),
     768 px texture cap. 35.4 → 16.4 MB. `_mobile_bake` picks it on
     phones (plant_instance growth variants + fruit meshes,
     island_generator apple tree; falls back to the full file if absent).
  3. Menu prewarm list is device-aware: phones prewarm only the mobile
     tree; desktop only the full one (`_prewarm_paths()`).
  4. Android export preset excludes `grass/baked/apple_tree.res` (the
     desktop tree is dead weight in the APK; mobile twins resolve at
     runtime and the desktop build still has its file on disk).
  - Also fixed: `_baked_apple_material` capped ALBEDO only — normal and
    roughness maps stayed full-size in every bake; now all three are
    capped (max_tex parameter).
  - Verify: `tools/probe_vram.gd` (textures), `tools/check_apple_mobile.gd`
    (mobile bake structure), full headless boot (island builds, 52 palms
    + apple tree, 0 errors).

- 2026-09-25 (29th pass): MOBILE ISLAND STILL INVISIBLE (user: "mobile shows
  only grass, no trees and land"). THREE root causes found:
  1. The 27th-pass terrain-shader cuts (3-octave fbm + `high_detail` gating)
     were still too heavy for some phone GPUs — the desktop shader keeps
     ~20 fbm calls/pixel (~600 hash ops) and the terrain pipeline fails to
     build on Mali/Adreno → terrain mesh never draws (grass field/ocean/sky
     use cheaper shaders, so the island reads as grass floating on water).
     FIX: dedicated `shaders/terrain_sand_mobile.gdshader` — IDENTICAL masks
     and color stops, but value-noise only (1–2 octaves), no loops, one
     shared noise domain per frequency band, bump/AO/mountain-mineral layers
     dropped (~1/10 the per-pixel work; vertex paint carries the look).
     `island_generator._terrain_shader_path()` picks it on `OS.has_feature
     ("mobile")` and `high_detail` is now set AT MATERIAL CREATION, not only
     in `_push_ocean_uniforms` (so a late-phase stall can't leave defaults).
  2. `generate()`'s palm while-loop `while _palms_placed < _palms_target()`
     has NO try-budget guard — `_place_palm_chunk` bails permanently if the
     bake is missing (`_palm_ok = false`), so the loop spins forever, the
     generator never reaches the apple tree / `_place_beacon_and_grass` /
     `_push_ocean_uniforms`, and the whole island build silently stops.
     FIX: hard round cap `_palms_target() * 8` + a short/continue log line.
  3. project.godot's `rendering_device/fallback_to_opengl3=true` line had a
     corrupted paste-mangled key ("island missing on mobilefailuremode).…")
     — the GL safety net was silently OFF, so a failed phone Vulkan driver
     rendered nothing instead of falling back. Key restored.
  - New tool: `tools/check_mobile_shader.gd` (headless, exits 1 if either
    terrain shader fails to compile).
  - PROJECT FACT correction: `rendering_device/fallback_to_opengl3` is TRUE
    again (was flipped to false in the 26th pass over "phone colors are
    wrong" — an invisible island beats a slightly different GL look).

### v5 — green summit ("top of island plain white")
- The v3 "bare summit above 10.5 m" soil term + v3 shader summit term bleached
  the peak pale gray-white under the new warm sun. Both `alpine_k` rules are now
  steep-faces-ONLY (cliff scree keeps mineral/soil detail); the summit and all
  gentle high meadows stay grass green. Paint cache bumped to **v5**.
- Ortho summit-disk check: WHITE 2.4% (was ~100% of the peak region).
- Gotcha: `--check-only`/`--script` boot modes report "Identifier not found:
  Inventory" in survival_hud.gd — autoloads aren't registered in those modes.
  Verify compile health with a real `--quit-after` game boot (clean) before
  hunting a phantom error.

### v4 — realistic grass + golden sand (root causes found by pixel evidence)
- **Grass invisible from gameplay distance**: alpha-scissor (0.42) vs VRAM-mip-minified
  atlas alpha (~0.35) triggered Godot's scissor distance-fade — every blade erased.
  Fix: threshold 0.26 + fragment alpha boost ×1.35; also back-face normal flip
  (cull_disabled blades rendered black from behind) and height mask 2.8→1.15 for
  the ~1 m real clump.
- **"Gray" sand (2 stacked bugs)**:
  1. The beach shelf (h 1.5-4 m) sat inside the old 1.3→2.7 m grass lerp — painted
     uniform DESATURATED OLIVE. Fix: golden-sand band holds to ~2.2 m (jitter ±1),
     grass ramps over 2.2 m, second high-freq noise dithers the band into tufty
     sand/green patches (never a flat blend). MIRRORED in 3 places:
     `_terrain_paint`, terrain_sand.gdshader `grass_k`, island_grass.gd mask.
     Paint cache bumped to **v4**.
  2. Terrain shader's `sand_mask` fed LINEAR COLOR into sRGB-calibrated thresholds
     (sand luma 0.36 < 0.45 → mask 0 → whole golden pipeline skipped). Fix: convert
     `COLOR` to sRGB (`sqrt`) for masks, keep linear copy for ALBEDO mixes.
  3. Shader `sand_edge` mix re-buried the golden paint under raw vertex color
     wherever the new ramp was mid-way — removed (dither lives in the paint now).
- **Washed-out lighting**: probe quads proved blue sky-ambient + fill drowned the
  warm sun (a golden albedo rendered neutral!). Rebalance: sun 1.6→1.4 (warmer
  color 1,0.91,0.75), ambient 1.3→0.32, fill 0.42→0.08, saturation 1.3.
  Result from the player beach view: 59.5% warm + 8.3% green (was ~0% warm).
- **Verification method that works**: ortho top-down + StandardMaterial reference
  quads (known albedo) + ASCII pixel maps. CAUTION: cameras mis-seat easily on a
  height-field island (clipped into hills / aimed at ocean); probe quads tell the
  truth. Palm shadows at noon are large — shadowed sand reads neutral, sample
  sunlit patches only.
- Baked field re-scattered under the new mask: 7,639 real clumps. (update after every change)
- 2026-09-16 (28th pass): FULL-ISLAND REAL GRASS + BIG NATURAL PALMS (user:
  "use realistics_grass_10.glb to cover the full island; coconut trees
  bigger + natural, not only straight trees; trees placed correctly").
  - GRASS: island_grass now scatters grass_clump.res (the REAL
    realistics_grass_10.glb bake, ~1 m wide, 2697 tris — probe:
    tools/probe_vegetation.gd) instead of the 184-tri scan_tuft speck.
    instance_count 15000 -> 9000 (bigger mesh needs fewer copies; one draw
    call holds), clump scale 1.4-2.6 -> 0.85-1.6 (the old range on this
    mesh = 2.6 m monster bushes), height stretched 0.9-1.35x footprint
    (tufty, not pancake), grass-line mask gk 0.35 -> 0.22 (fringe grass
    reaches near the waterline), mobile cap 7500 -> 6000. Baked field
    REGENERATED (9000 clumps) via tools/bake_grass_field.gd.
  - PALMS: _make_palm_plant scale 0.95-1.35 -> 1.25-1.75 (crown palms
    ~5.8-9.2 m); every tree leans 0-8 deg in a random direction (root
    rotation x/z — shore palms lean like real trees); 30% add a second
    4-9 deg CROOK on the PlantInstance node itself (crown swings with the
    trunk; collision/aim math is local so gameplay is unaffected — the
    sway shader is world-wind-keyed so lean changes nothing there).
    palm_count 40 -> 52, spacing 5.0 -> 4.2 m (crowns ~3.6 m never
    overlap). plant_instance._is_player_aiming_here reach now multiplies
    by the ACCUMULATED Node3D parent scale (walk up the ancestor chain):
    reach = maxf(3.5*ps, _tree_top*ps + 0.6) — a 1.75x palm is judged at
    its real ~9 m height and stays harvestable (the flat-local read made
    big trees unpickable).
  - Verified: bake DONE (9000 clumps), rendered boot 0 errors, 52 palms +
    apple tree placed.
- 2026-09-16 (27th pass): GREEN MOUNTAIN + MOBILE INVISIBLE ISLAND (user:
  "no grass on mountain, want fully covered green natural realistic look;
  island not showing on mobile, only on PC").
  - MOUNTAIN BALDNESS root cause: _terrain_paint's alpine soil blanket
    smoothstep(5.0, 9.5, h) lerped 85% brown over EVERY slope above 5 m,
    and terrain_sand.gdshader's `mountain` term added smoothstep(5.0, 9.0,
    h) rock texture on top — the whole upper island read bare dirt/rock.
    FIX (both sides kept in sync): soil/rock only where steep
    (smoothstep(0.35,0.55, 1-slope)) OR near the bare summit
    (smoothstep(10.5, 11.5, h)), fading in above 7.0 m. Gentle high
    meadows stay grass green. terrain cache renamed user://terrain_cache_v3_*
    — bump the version on ANY _terrain_paint change or phones keep stale
    paint forever.
  - MOBILE ISLAND INVISIBLE root cause: terrain fragment shader was ~24
    fbm calls x 5 octaves (~480 hash21 ops/pixel) — exceeds phone-GPU
    (Mali/Adreno) per-pixel ALU/compile budgets, the terrain pipeline
    fails, and the ISLAND MESH NEVER DRAWS on phones while PCs are fine.
    FIXES: (a) fbm 5 -> 3 octaves (finest octave was sub-pixel shimmer);
    (b) deduped the two twice-used ripple warp fbms; (c) new uniform
    `high_detail` (1 desktop / 0 mobile, pushed by _push_ocean_uniforms
    from the Terrain mesh's material) gates the mountain mineral detail,
    seabed bump, close-range grain bump and mountain bump blocks — mobile
    keeps vertex-paint colors + grass mottle; (d) project.godot
    rendering_device/fallback_to_opengl3 true so a failed phone Vulkan
    driver falls back to GL Compatibility instead of rendering nothing.
  - GRASS FIELD: scene override max_height_above_water was 8.0 (stale —
    the export default had moved to 11, summit is ~13.6 m) so the scatter
    mask cut the mountain at 8 m. Now 14.0 in BOTH main.tscn and the
    export default; min_surface_flatness 0.62 -> 0.55; seating sink
    sc*0.10 -> sc*0.16 (40% of clump height — curved-ground edges no
    longer float); mobile baked-field cap 3500 -> 7500 (3500 read bald).
  - TOOLS: new tools/bake_grass_field.gd (headless SceneTree boot of
    main.tscn, polls for the filled MultiMesh, quits) + island_grass.gd
    now saves the bake on headless runs too (was editor-only, so deleted
    baked fields could not be regenerated outside the editor).
  - Verified: bake DONE (15000 clumps), rendered boot 0 errors/shader
    errors, baked field re-saved (2.6 MB).
- 2026-09-15 (26th pass): grass coverage + realism (user: "island not real
  in long view, grass missing and not sitting in the land").
  - island_grass.gd: clump scale 0.9-1.8 -> 1.4-2.6 (specks -> meadow
    clumps); min_surface_flatness 0.72 -> 0.62 (all grassy slopes eligible);
    max_height_above_water 8 -> 11 (slopes up the mountain now carry grass);
    seating pos + n*0.02 -> - n*sc*0.10 (base sinks ~1/3 clump-height into
    the ground — the old lift left edges FLOATING on curved ground);
    mobile thin-floor 1800 -> 3500 (1800 read bald).
  - terrain_sand.gdshader: the grass ground was FLAT vertex-green (plastic
    lawn at distance). Added grass-ground texture: 2-octave blade mottle
    (±24%), olive dry patches, soil show-through in sparse spots, plus a
    low-frequency RAGGED sand/grass boundary (grass_k + fbm offset) so the
    vertex-paint contour ring breaks into natural inter-fingering.
  - Verified: bake regenerated (15000 clumps, 2.6 MB), boot 0 errors.
- 2026-09-15 (25th pass): the "giant floating coconut" fix — tree fruit vs
  drop finally size-matched.
  - ROOT CAUSE: slots carried the WHOLE bunch mesh each (5 overlapping
    34 cm shells = one giant blob under the crown) while drops were 9 cm —
    tree-big/ground-small mismatch the user kept reporting.
  - BAKE: coconut_single.res is now a REAL single nut via greedy BALL-CARVE
    (_carve_kc_nut). The nuts interpenetrate so NO cut-based union-find can
    split them (probe: cuts 0.5..30 -> one component). Greedy balls grown
    from uncovered centroids: winning radius picks the ball whose size ≈
    ONE nut's share (1176/11 ≈ 107 tris; picked 134 incl. neck), then the
    far side is patched with unclaimed tris inside the nut's bounding
    sphere (grown 15%). BALL-COUNT-ONLY scoring FAILED (r=12 matched 11
    balls but each ball was 283 tris = 2.6 fused nuts) — always score
    against the nut-share of triangles.
  - plant_data: Coconut fruit_mesh = coconut_single.res, fruit_scale 1.05
    (~12.6 cm ripe) — 5 clustered single nuts read as a natural bunch.
  - coconut_pickup: dropped nut 11-13 cm (randf_range 0.9-1.1 of the 12 cm
    bake), collider 0.05 — same size family as the tree nuts, with natural
    per-nut variation (user: drops "always same size").
  - Housekeeping: island_generator dead `tree_scale` removed;
    plant_instance._drop_fruit dead `drop` block removed (spawn goes via
    _spawn_fruit_pickup); @warning_ignore("integer_division") on the
    intentional i/2 pair split; probe scripts deleted after use.
  - Verified: bake DONE (single 134 tris), full boot 0 errors/warnings.
  - TALL-TREE PICKING (user: "can't take coconut from the long tree"): the
    interaction gate was a FLAT 3.5 m aim distance — a palm's crown sits
    4.65-5.3 m up, so no prompt ever showed. Reach now scales with the
    plant: maxf(3.5, _tree_top + 0.6). Also the hang-layout fruit-match
    radius is 1.2 m (bunches hang UNDER the crown; the aim hit lands on the
    aim-box wall beside them) — canopy fruit (apples) keep the tight 0.55.
- 2026-09-15 (24th pass): zero-warning pass. Dead `tree_scale` removed from
  island_generator (PlantInstance already varies size via _hvar + MESH_SCALE
  — an extra node scale would double-scale); dead `drop` construction block
  removed from _drop_fruit (the real spawn is _spawn_fruit_pickup, which
  builds its own pickup — the old block instantiated and discarded one);
  `@warning_ignore("integer_division")` on the intentional i/2 pair split.
  Godot 4.7 forbids `return` in fragment() — use if/else (bit pass 23).
- 2026-09-15 (23rd pass): NO MORE BLACK COCONUTS + in-game tree matches the
  glb preview (user screenshots showed dark spheres + glowing yellow balls
  under the crown).
  - ROOT CAUSE: coconut slots still used the PROCEDURAL SphereMesh fallback
    (fruit_mesh was never set for Coconut) — dark albedo in linear space
    under ACES, plus emission/EMISSION sparkle patches = "black nuts +
    yellow balls". The bake's nut-split also FAILED (nuts interpenetrate →
    centroid-cut union-find kept them fused) so coconut_single.res was the
    whole bunch rendered PBR-dark.
  - FIX: Coconut def now sets fruit_mesh = coconut_bunch.res (the REAL glb
    bunch is the slot fruit), fruit_scale 0.75 (~0.34 m ripe bunch),
    fruit_unlit = true. fruit_tint.gdshader gained an `unlit` mode:
    hue-preserving COLOR lift (base + (1-base)*(1-lum)*0.35), ROUGHNESS
    0.85, no normal map, NO emission — bright natural husk under any
    light. Bunch slots never sparkle (_set_sparkle gated on !fruit_unlit).
  - Godot trap: `return` inside fragment() = SHADER COMPILE ERROR — use
    if/else.
  - CoconutPickup: dropped nut = coconut_single.res scaled 0.72 (~9 cm),
    SAME unlit tint path (albedo_tex from the bake) so drops look
    identical to hanging nuts; collider radius 0.049 -> 0.04.
  - Apple bake: leaf budget 500k -> 600k leaf tris (692k total) — the
    in-game crown now reads as dense as the glb preview the user liked.
  - GODOT BINARY MOVED: now
    "/c/Program Files/Godot/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe"
    (old Godot_v4.7.1-stable_win64.exe path is gone — exit 127).
  - Verified: bake DONE, game boot 0 errors, menu boot 0 errors.
- 2026-09-15 (22nd pass): REAL king_coconut.glb drop pickup.
  - New bake _bake_king_coconut: the glb is 12 nodes — 11 IDENTICAL bunch
    copies (1176 tris, same AABB, material kc_HP1) + 1 stem. Merges the
    first bunch, welds verts (1e-2 grid), union-finds triangle connectivity,
    keeps the LARGEST shell = ONE coconut, scales to 12 cm, pivot at TOP,
    kc_HP1 texture downscaled via _baked_apple_material. Output
    grass/baked/coconut_single.res (64 KB, 1176 tris).
  - TRAPS: (a) the scene-walk BFS must push children onto the stack (first
    version only checked the root -> "no triangle data"); (b) after
    welding, SurfaceTool must index the WELDED arrays (wv/wn/wu) — indexing
    raw verts with welded ids scrambled the mesh (AABB 15.5 cm lie).
  - CoconutPickup: loads coconut_single.res when present (procedural
    sphere stays as fallback); mesh lift +0.06 so the nut rests on the
    ground. Covers BOTH natural drops AND the fell-scatter (they share
    _spawn_fruit_pickup). Pond sink: _process now takes max(ocean height,
    pond height) as the water surface — IslandGenerator.POND_POS/POND_R/
    pond_water_height() — so a nut rolled into the pond waterlogs+sinks
    like in the sea.
  - Verified: bake DONE, full boot 0 errors (island + 15000 clumps).
- 2026-09-15 (21st pass): MORE GRASS COVERAGE (user: "cover more places").
  - main.tscn IslandGrass: instance_count 9000 -> 15000, scatter_radius 42 ->
    48, visibility_distance 120 -> 140.
  - island_grass.gd: min_surface_flatness 0.78 -> 0.72 (gentler slopes
    eligible); grass-line mask threshold gk < 0.5 -> 0.35 (tufts now spill
    into the PARTIALLY-green transition band — dune grass creeps toward the
    beach; below 0.35 is pure painted sand so the beach stays clear);
    attempt budget target*3 -> target*4 (higher rejection rate from the
    wider radius/mask otherwise under-fills the field).
  - Baked field DELETED and regenerated in-boot: 15000 clumps placed,
    boot 0 errors. NOTE: attempts budget, flatness, gk threshold, radius
    and count are the FIVE grass-coverage knobs — changing any placement
    rule requires deleting grass/island_grass_baked.tres to re-bake.
- 2026-09-15 (20th pass): nuts STILL read "dropable big" (screenshot: dark
  balls beside the crown). Shrank the whole chain: PlantDB fruit_radius
  0.06 -> 0.042 (8.5 cm on-tree green nuts); CoconutPickup mesh radius
  0.075 -> 0.052 / height 0.10 (~10 cm dropped nut), collider 0.072 ->
  0.049. Ripe husk color unified across BOTH: def fruit_color AND pickup
  albedo now linear (0.17,0.09,0.028) ≈ dried-husk sRGB(0.45,0.33,0.18) —
  a drop looks continuous with the bunch, not a different object.
  Verified: headless boot 0 errors.
- 2026-09-15 (19th pass): GRID SAND — the SAME broken hash was still in the
  terrain shader family. hash21 in terrain_sand.gdshader (and
  rock_triplanar/fresh_water) was still fract(sin(dot(c,(127.1,311.7)))*43758)
  — grain_noise feeds floor(uv*24)≈3,400 into sin() as ~1e6 rad -> correlated
  diagonal bands -> the beach rendered as rectangle tiles (user screenshot).
  ALL THREE now use the precision-safe hash (mod 1024 wrap + Hoskins mix;
  rock keeps its per-rock seed offset). footprint.gdshader's fract(sin) is
  LOCAL-UV only (tiny inputs) — left as-is. island_terrain.gdshader is
  unreferenced/unused. RULE: audit EVERY shader for fract(sin(dot)) when a
  world-scale surface shows structure — the hash, not the noise type, is
  usually the culprit. Verified: headless boot 0 errors.
- 2026-09-15 (18th pass): chop-lock between trees + coconut "highlight" color.
  - ONE-TREE-AT-A-TIME bug: after _start_fall the dying tree kept its
    FULL-SIZE aim box (+ trunk cylinder) active through the 1 s fall + 5 s
    fade — the single aim ray hit it, so no other tree was targetable for
    ~6 s per cut. FIX: _start_fall shrinks the aim box to 0.2 m and frees
    _trunk_shape immediately (a dying tree aims at nothing). _finish_fade's
    stump path re-calls _update_collision which sets the stump box.
  - Coconut pickup color: Color(0.45,0.33,0.18) is LINEAR (ACES scene) and
    displayed as a washed pale tan that read as "highlighted" on the sand.
    Now (0.13,0.075,0.035) ≈ sRGB husk brown. RULE: code-set pickup colors
    must be converted to linear (pow ~2.2), never pasted as sRGB-looking
    values — same trap as the terrain sand albedo.
  - Verified: headless boot 0 errors.
- 2026-09-15 (17th pass): sparkle WHITE BOXES + leaned-palm floating bunch + REAL fell/regrow cycle.
  - White squares in palm crowns (screenshot): ripe-fruit sparkle billboards.
    TWO bugs: (a) GeometryInstance3D.transparency is IGNORED by the Mobile
    renderer -> the "twinkle" rendered as an opaque quad; (b) the old
    GradientTexture1D had hard top/bottom edges. FIX: GradientTexture2D
    FILL_RADIAL soft dot (edges alpha=0 on every renderer) + twinkle via
    SCALE pulse only. RULE: on Mobile, never animate visibility via
    .transparency — use texture alpha or scale.
  - Floating coconut beside a palm: baked palm trunk LEANS, but hang-layout
    fruit slots ringed the plant ORIGIN. FIX: _crown_off = mean XZ of all
    mature-mesh vertices above 72% height (x _ms); hang ring + canopy
    fallback scatter now center on it. Measured in _load_growth_variants.
  - FELL: tree falls -> ALL grown fruit scatters as physical pickups
    (_scatter_all_fruits, outward vel 1.2-2.6 m/s + up), wood from
    fell_drops (Coconut inventory double-dip REMOVED from fell_drops),
    then a 5 s wilting fade (_visual scale->0.06 + sink -0.35) — never
    instant vanish. Cross-renderer safe: NO material alpha animation (bake
    materials are shared between all palms — mutating one mutates all).
  - AUTO-REGROW: island stumps (NOT in a planter) wait ISLAND_DAY_SECONDS
    (~1 day, _regrow_wait member, ticked in _process STUMP branch) then
    _regrow_plant() restarts at SPROUT with the normal visible growth
    stages. Potted stumps keep manual removal.
  - Verified: headless boot 0 errors.
- 2026-09-15 (16th pass): RECTANGLE GRID on the ocean — REAL root cause found
  (gradient noise in pass 15 was necessary but NOT sufficient).
  - Cause: the hash itself, fract(sin(dot(c, vec2(127.1,311.7)))*43758.5453).
    At world scale the input reaches dot((±250 m)*2.73 octave) ≈ 200,000 rad;
    float32 sin() of that is quantized into correlated diagonal bands, so ALL
    lattice corners decorrelate poorly and cells render as straight-edged
    RECTANGLE patches across the whole sea (user screenshot pass 16). Any
    fract(sin(dot)) hash degenerates the same way once |input| ≳ ~10k rad.
  - FIX: precision-safe hash21_o — cell coords wrapped mod 1024.0 (plane 500 m
    x max octave 2.73 = 682 < 1024, so no wrap seam is ever visible) + the
    sine-free Hoskins-style mix (fract(vec3*0.1031), p3+=dot(p3,p3.yzx+33.33)).
  - RULE for this project: on the OCEAN (and any world-scale surface), every
    hash must (a) wrap its cell coords before hashing and (b) avoid sin() of
    large dot products. fract(sin(dot(...))*43758) is banned in world-space
    shaders.
  - Verified: headless boot 0 errors.
- 2026-09-15 (15th pass): OCEAN "box box" look + LOADING STUCK AT 92% — both fixed.
  - Ocean boxy cells: the rain/churn/micro-ripple helpers were VALUE noise —
    its bumps sit ON the hash lattice, painting visible square cells (and rain
    flecks popping one-per-cell in perfect rows). FIX: gnoise_o = GRADIENT
    noise (hashed corner DIRECTIONS, dot-product interpolation, remapped
    0.5+g*0.72) with the input pre-rotated mat2(vec2(0.8,-0.6),vec2(0.6,0.8)).
    Gradient-noise bumps land inside cells at random offsets — no readable
    lattice. RULE: value noise = boxy cells; use gradient noise for anything
    organic on water. (Godot TRAP: mat2() takes vec2s, not 4 floats.)
  - Ocean polygonal waves: PlaneMesh was 500 m with 160 subdivisions (~3 m
    flat quads) — crest lines broke into straight segments. Now 256
    subdivisions (scenes/main.tscn) ≈ 2 m quads.
  - LOADING STUCK AT 92%: (a) menu requested the scene AND all 5 big bakes
    with load_threaded_request SIMULTANEOUSLY — loader thrash stalled at
    ~0.92 forever. FIX: sequential prewarm chain (_request_next_prewarm,
    one at a time) + STALL WATCHDOG (no progress 15 s -> synchronous
    change_scene_to_file fallback; scene-ready prewarm capped at 8 s).
    (b) big bakes were TEXT .tres (slow parse). ALL vegetation bakes now
    save/load BINARY .res (apple_tree.res 31.7 MB vs 42 MB tres; parse is
    10-20x faster). Bake tool ResourceSaver paths + ALL consumers updated:
    plant_instance GROWTH_VARIANTS, island_generator PALM_MESH_PATH +
    apple_tree check + UNDERGROWTH_PATHS, plant_data fruit_mesh,
    apple_pickup, island_grass grass_mesh_path (+ export_file filter now
    "*.res", "*.tres", "*.glb"). main_menu PREWARM_PATHS.
  - Verified: bake DONE, headless boot 0 errors (8268 clumps, 40 palms,
    apple tree placed).
- 2026-09-15 (14th pass): nut frond-poke, SINKING coconuts, cross-swell waves.
  - Bunch tuck: ring_r 0.30 -> 0.20 crown_r, ring_y 0.24 -> 0.45 BELOW crown
    center, jitter 0.65..0.95, fruit_radius 0.06 (12 cm green nuts) — nuts no
    longer poke through drooping fronds.
  - CoconutPickup SINKS (waterlogged husk): _process checks get_height; 4 s
    under surface -> gravity_scale 0.35 + damp, fades/despawns 25 cm under.
    NO buoyancy float like Debris.
  - Wave realism: main.gdshader + ocean.gd _WAVES + raft_foam.gdshader ALL
    gained L5/L6 cross-swell (dir (0.33,0.94)/(-0.95,0.05), f 0.163/0.317,
    amp 0.27/0.16, s 0.87/1.23; WAVE_SUM 2.69) — 4 aligned harmonics read as
    regular parallel bands; the two incommensurate cross components scramble
    the interference into random-looking real-sea mixing. KEEP ALL THREE IN
    SYNC (raft foam lifts with the same field).
- 2026-09-15 (13th pass): UNSTRUCTURED rain/waves (screenshot: perfect dot
  lattice + parallel wave lines on the ocean during rain).
  - main.gdshader: added hash21_o/vnoise_o. REPLACED with noise:
    (a) micro ripples — old 3-plane-wave sum made a hexagonal dot lattice
    over the whole sea; now 2-octave value noise, gradient via forward
    difference (ne=0.10). (b) rain normal roughening — old 4-sine sum made
    parallel lines; now 2 scrolling noise octaves, amp 0.30*rain.
    (c) rain churn flecks — old sin*sin made the egg-crate grid; now
    thresholded (smoothstep 0.78-0.95) scrolling noise with fast flicker.
    (d) glitter/whitecap chop — old sin*sin diagonal lattice; now
    anisotropically stretched noise (sheared coords), amp 1.6.
  - rain_system.gd: storm wave boost +35% -> +12% (rain pats the water
    down, it does not build swell hills).
  - Verified: headless boot 0 errors.
- 2026-09-15 (12th pass): LOADING FREEZE fixed (86 s -> 14 s probe, faster
  via menu).
  - ROOT CAUSE of "Continue stuck": PlantInstance._ready load()s the baked
    meshes SYNCHRONOUSLY on the first game frame — apple_tree.tres was
    57 MB (700k leaf tris + 2048 px textures), 40 palms + tree deserialized
    inside change_scene -> one 77 s frame AFTER the loading bar filled.
    Probe: tools/probe_continue_load.gd (measures threaded load + add_child).
  - FIX 1 (bake): APPLE_MAX_TEX 2048 -> 1536, leaf budget 700k -> 500k
    (41% whole cards, still dense; file 57 MB -> 42 MB). RE-BAKED.
  - FIX 2 (menu prewarm): main_menu._start_threaded_load also issues
    load_threaded_request for the 5 big baked .tres (use_sub_threads=true)
    UNDER the loading bar — cache-warm before the game asks.
  - FIX 3 (staged generation): island_generator.generate() is now async —
    phases (terrain, pond, props, beacon/grass) separated by
    _phase(): process_frame + physics_frame awaits, so no single frame
    blocks; raycast-dependent phases still see fresh colliders.
  - FIX 4 (crash): rain_system._build_overlay used
    get_tree().current_scene.add_child — current_scene is NULL during scene
    change (RainSystem._ready runs first) -> SCRIPT ERROR each boot + lost
    overlay. Now get_tree().root.add_child.call_deferred.
  - Verified: probe t=14.2 s total (was 86.2 s), full boot 0 errors, island
    + 40 palms + apple tree + 8268 grass clumps. Docs updated (500k/1536).
- 2026-09-15 (11th pass): BIGGER trees, LUSH grass, small nuts on RANDOM sides.
  - GDScript warnings fixed: unused `max_slots` deleted; _drop_fruit ternary
    (CoconutPickupScript.new() if palm_drop else ApplePickupScript.new()) ->
    if/else (unrelated classes trip INCOMPATIBLE_TERNARY).
  - Bigger trees: MESH_SCALE const {"Apple": 1.25} in plant_instance (mi.scale
    in _build_real_tree_visual; _ms member multiplies _tree_top/_crown_y/_crown_r
    in _load_growth_variants AFTER measuring + fruit anchors multiply by _ms).
    Island apple tree scale 0.85-1.1 -> 1.0-1.15; palms 0.85-1.2 -> 0.95-1.35.
  - Grass: main.tscn IslandGrass instance_count 3500 -> 9000, scatter_radius
    30 -> 42, cast_shadows false (perf at 2.4x density). Baked field DELETED
    (grass/island_grass_baked.tres + .import) so runtime re-bakes: first boot
    needs ~2-5 min while the 9000-raycast field regenerates, then re-saves.
  - Coconuts smaller: PlantDB fruit_radius 0.075 (15 cm); CoconutPickup mesh
    0.075/0.14, collider 0.072.
  - Per-tree bunch sides: _init_fruit_slots hang path picks base_ang = random
    TAU; 50% of trees split the crop into TWO opposite ~52° arcs, the rest
    carry one 1.1-2.2 rad arc; per-slot jitter ±0.15-0.18 rad + y wobble.
    Crop VARIATION weighted: 20% bare / 35% 1-2 nuts / 45% 3-5 nuts (uniform
    randi made half the island identical).
  - Verified: headless boot 0 errors, 8268 clumps placed, island + 40 palms
    + apple tree OK.
- 2026-09-15 (10th pass): FRUIT PHYSICS ROOT CAUSE + free movement + pond/ocean rain + sand/rock beauty.
  - ROOT CAUSE of "apples floating in the sky" AND "can't move freely":
    PlantInstance's canopy box was collision_layer 1 (player + rigidbodies
    collide). Fruit spawned INSIDE it -> depenetration launched apples to the
    sky; every palm/apple tree was an invisible wall. FIX: AIM_ONLY_LAYER
    (1<<15) on PlantInstance bodies; player aim mask const AIM_MASK = 3 | 1<<15
    (player.gd). Player body unchanged (mask 1) -> walks freely. Added a thin
    trunk CylinderShape (sibling of _col_shape, _trunk_shape member) so chop
    aiming still registers; freed on stump.
  - _drop_fruit apple regrow: self-dropped slots use count*200 s (~4-5
    apples/day with 8 slots, staggered); PICKED apples keep fruit_regrow_time.
  - Apples: PlantDB fruit_scale 1.8 -> 1.0 (16 cm real apple). ApplePickup
    collider 0.05 -> 0.075 + mesh lift 0.07 (fruit no longer half-sinks).
  - Coconuts: hang ring tightened (ring_r 0.55->0.30 crown, ring_y crown_r*0.24
    BELOW fronds, jitter 0.72..1.0) = nestling cluster under the crown, not in
    the leaves; fruit_radius 0.13->0.10; CoconutPickup mesh 0.10/0.185,
    collider 0.098, 12x8 segments (smoother). SIZE UNCHANGED ON REQUEST.
  - Pond: _scatter_props' SECOND flat StandardMaterial3D disc (z-fighting the
    shader disc = fake look) DELETED; _build_pond_water is the only surface.
    fresh_water.gdshader v2: rain_strength uniform (island_generator._process
    pushes RainSystem._intensity) drives expanding rain RING ripples (hashed
    cell rings, 2 scales), surface roughening, darkening, alpha up; tangent-
    space sun/moon glint via EMISSION; vertex chop when raining. Dead
    duplicated wn lines removed.
  - Ocean rain (main.gdshader rain_strength uniform, pushed by ocean.gd from
    rain_system group): storm normal roughening (2 incommensurate packets),
    body darkening -14%, near-field bright churn FLECKS.
  - Sand beauty: aeolian wind streaks (fuv, elongated 4:1, multiplicative
    +/-3%) in terrain_sand.gdshader.
  - Rock beauty: terrain mountain gains geological warm/cool zoning + lichen
    on damp up-faces; rock_triplanar v4 gains large-scale warm/cool granite
    zone + height-gradient moss (stronger near base).
  - Verified: headless boot clean (0 errors, island + 40 palms + apple tree).
- 2026-09-15 (9th pass): apple tree rebuild + REAL COCONUT LIFECYCLE.
  Apple tree (bake + runtime):
  - Leaf budget 200k → 700k of 1.22M source leaf tris (57% whole cards,
    overlapping → dense crown). apple_tree.tres now 793k tris.
  - apple_single 9 cm → 16 cm + PlantDB `fruit_scale: 1.8` applied in
    _update_fruits (runtime ≈29 cm showpiece apples).
  - Bake writes meta `fruit_anchors` on apple_tree.tres: 8 density peaks
    (0.35 m lattice quantization of foliage+twig verts, greedy ≥0.45 m
    apart). plant_instance _init_fruit_slots canopy path hangs fruit from
    anchors (slightly below, ±6 cm jitter); deterministic shuffle per tree;
    falls back to the old sphere scatter when anchors are missing.
  Coconuts (real-palm feel):
  - Bake CUTS the baked-in nut cluster from palm_island.tres frond surface
    (y < 3.5 dropped, rebuilt mesh keeps all meta) — no more identical
    bunch on every palm.
  - Island palms are now PlantInstances (`_make_palm_plant`, MATURE,
    plant_id Coconut) — same path as the island apple tree. Static mesh
    `_make_real_palm` is GONE.
  - PlantDB Coconut: fruit_count 5, `fruit_variation` (each palm rolls
    0..5 ACTIVE slots — bare/sparse/full trees), `fruit_fall_item
    Coconut` + `fruit_fall_days 2.0`: ripe nuts drop ~one per DAY
    (PALM_DROP_DELAY 20 s + random 0..900 s spread), slot regrows over
    fruit_fall_days * ISLAND_DAY_SECONDS (900 s = Sky3D day). Picked
    slots also use the 2-day regrow.
  - scripts/coconut_pickup.gd (NEW): RigidBody3D debris-compatible
    CoconutPickup — mass 1.2, friction 0.9 / bounce 0.05 (thud, no
    trampoline), continuous_cd = true (never tunnels into terrain),
    despawns after 300 s.
  - _drop_fruit: palm drops spawn CoconutPickup; spawn position clamped
    above `_ground_below()` (physics ray → island field fallback) so a
    nut NEVER starts inside the land.
  - GDScript TRAP: `var x := a == b and c > d` fails to parse-infer when
    operands come from Dictionary.get() Variants — use `var x: bool = ...`
  - Verified: bake DONE (8 anchors, 700k leaf tris, 16 cm apple, nut cut
    2176/2592), headless boot clean.
- 2026-09-15 (8th pass): monsoon rain density in rain_system.gd.
  - particle_amount 700 → 1400 (desktop). Mobile halves it in _ready
    (maxi(n*0.5, 300)) — same auto-density rule as palms/grass.
  - Ring (covered) mode budget: +500 → +800 extra drops so sheltered rain
    stays as dense as the open-sky downpour.
  - Verified: headless boot clean.
- 2026-09-15 (7th pass): heavier-storm rain streaks in rain_system.gd.
  - Streak quad 0.018 x clamp(speed*0.045, 0.35, 0.9) → 0.012 x
    clamp(speed*0.062, 0.5, 1.35): longer, thinner slivers (at fall_speed 14
    → 0.012 x 0.87 m). Alpha cap raised 0.55 → 0.62 so thin streaks keep the
    downpour dense. Splash quads untouched (0.05 impact bursts).
  - Verified: headless boot clean.
- 2026-09-15 (6th pass): trees floating above ground FIXED + rain recolored.
  - ROOT CAUSE of floating trees: props were placed at `_ground(q)` =
    terrain_height_local (ANALYTIC field), but the visible terrain is the
    1.75 m-grid mesh whose triangles chord flat between vertices — all the
    fine noise detail between samples lifts the analytic height above the
    rendered surface → visible gap under trunks on any slope. FIX:
    `_rendered_height()` in island_generator.gd triangle-interpolates the
    SAME heights array the mesh was built from (same b<->c2 diagonal
    triangulation), and `_ground()` now returns it. `_terrain_heights` /
    `_terrain_n` members are filled at the end of the height sampling loop
    in _build_terrain (before the paint loop). Every prop (palms, apple
    tree, bushes, rocks, driftwood, beacon) flows through _ground → all
    fixed at once. FALLBACK: if _terrain_heights is empty, _rendered_height
    returns the analytic field (pre-terrain queries still work).
  - Rain color: was near-white Color(0.92,0.94,0.96) (read as falling snow).
    Now `@export var rain_color := Color(0.52, 0.72, 0.95)` (translucent
    water-blue) in scripts/rain_system.gd, applied to BOTH the streak
    material and the splash material; tintable in the Inspector.
  - Verified: headless boot clean, island builds, apple tree placed.
- 2026-09-15 (5th pass): "snow-camo sand" fix in terrain_sand.gdshader.
  Screenshot showed white/gray blotchy sand. Causes + fixes:
  - dry_sand (0.82,0.74,0.56) LINEAR displayed ~sRGB(233,224,195) and clipped
    to snow under ACES → (0.70,0.60,0.42) ≈ sRGB(215,200,170), warm tan.
    damp_sand also darkened (0.54,0.45,0.30). REMEMBER: terrain shader albedo
    constants are LINEAR — sRGB-looking values blow out under ACES tonemap.
  - wet_warp ±0.25 m flooded damp blotches up the dry beach → ±0.11 m, wet
    band gradient tightened (-0.15..1.4 → -0.15..1.05): damp sand hugs the
    waterline again.
  - grain_coarse (fbm uv*0.6 SUBTRACT-cloud, amp 0.10-0.18) was the gray
    camo → DELETED. Replaced with multiplicative hue mottle: patch =
    fbm(uv*0.55); albedo *= 1 + patch*(0.12,0.05,0.14) — ±6% hue patches,
    never brightness swing.
  - Ripples now patchy: rip_field = smoothstep(0.40,0.62,fbm(uv*0.07+off))
    masks ~half the beach; uniform ripples everywhere looked stamped.
  - RULE: on sand, large-scale variation = multiplicative hue tint; never
    additive brightness clouds; never snow-bright albedo constants.
  - Verified: headless boot clean, no grain_coarse refs left.
- 2026-09-15 (4th pass): underwater seabed detail in terrain_sand.gdshader.
  - `subm = smoothstep(0.15, -0.5, h)` — geometric submersion factor (the
    terrain shader has NO time-of-day input; ocean.gd only pushes night to
    the water, so underwater effects key on height, not on sky state).
  - `light_dapple` = subm faded out 3–7 m deep (light dies with depth).
  - Albedo: wave-formed seabed ripples (2-harmonic, rotated/warped fuv,
    amp 0.045 * subm * sand_mask) + moving caustic dapple (fbm scrolled at
    TIME*0.10/0.07, amp 0.07 * light_dapple * sand_mask).
  - Bump: seabed ripple relief layer (fbm uv*2.1, mix 0.55 * subm) +
    bump_strength += 0.12 * subm * sand_mask.
  - Verified: headless boot clean.
- 2026-09-15 (3rd pass): near-camera sand detail boost in terrain_sand.gdshader.
  - Distance-scaled detail: `close_k = smoothstep(26.0, 5.0, cam_dist)` — grain
    amplitudes (grain_fine 0.045→0.16, grain_micro 0.015→0.10, grain_coarse
    0.10→0.18) and ripple amplitudes (dry 0.035→0.085, wet 0.04→0.10) reach
    full strength under ~5 m and calm down by ~26 m (far-field micro noise is
    pure shimmer, so range gets LESS detail, not more).
  - Ripples gained a 2nd harmonic (2x freq, 0.35/0.4 amp) for crisp asymmetric
    crest lines instead of one soft sine.
  - Close-range grain BUMP layer (grain_noise uv*9, strength 0.65 * close_k *
    dry * sand_mask) fades in near the camera; bump_strength +0.30 * close_k.
  - Roughness sparkle: (grain_noise(uv*14)-0.5)*0.16*close_k*sand_mask so
    close highlights glint per-grain.
  - close_k is declared in the SAND GRAIN DETAIL section — anything earlier
    (masks, wet zones, foam) must not reference it.
  - Verified: headless boot clean.
- 2026-09-15 (2nd pass): APPLIED all fixes and re-baked.
  - Bake: leaf budget 80k→200k (201k leaf tris kept), bark ratio 0.25→0.45
    (92k trunk tris), APPLE_MAX_TEX 1024→2048. apple_tree.tres now 294k tris,
    3 surfaces. Deleted unused apple_tree_big.tres (stale doc reference too).
  - plant_instance.gd: sway shader keyed to palm meshes only (`src` meta);
    canopy fruit anchors measured from the alpha-scissor leaf surface.
  - main.gdshader: shore-foam breakup → rotated incommensurate waves.
  - terrain_sand.gdshader: foam lines/breakup/ripples → 30°-rotated fbm-
    warped coords; wet-band edge noise-warped.
  - Verified: bake DONE, headless boot clean (island + 40 palms + apple tree
    placed), apple_single.tres still carries albedo/normal/roughness maps.
- 2026-09-15: skill created. Diagnosed apple-tree + sand-grid issues:
  apple tree look caused by (a) leaf budget 80k halving the leaves,
  (b) palm sway shader applied to apple leaves, (c) fruit slots
  anchored at crown_y≈4.9 m above a 5.7 m mesh with ~3.6 m canopy,
  (d) bake texture cap 1024 px. Sand grid caused by axis-aligned
  sin(x)*sin(z) foam breakup in main.gdshader + axis-aligned foam/ripple
  terms in terrain_sand.gdshader.
