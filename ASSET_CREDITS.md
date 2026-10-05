# Third-party asset credits

Asset licenses are separate from the source-code license and are listed individually below. The supplied Sketchfab palm uses CC BY 4.0 and grass uses the Sketchfab Standard License; the newly authored survival GLBs and other identified assets use CC0. Optional Sketchfab recommendations are not bundled.

## 3D models

- **Beach survivor character** — Quaternius, *Beach Character* (male). The [Poly Pizza model page](https://poly.pizza/m/DojKLcO34E) labels it Public Domain (CC0). The original source GLB came from [H3-Teamy PR #746](https://github.com/grvermeulen/H3-Teamy/pull/746); its SHA-256 (`21f7667810fbffc90c1605629884abd144b4423ab309af9ee0338e51afabdf7d`) matches the PR's `beach-man.glb` byte-for-byte. `models/beach_survivor.glb` keeps the skinned mesh and skeleton. `tools/bake_palette_glb.py` converts the source `_PALETTE` attribute to standard linear `COLOR_0` vertex colors and generates vertex normals for Godot. Its eight CC0 idle, walk, run, and action clips come from Quaternius' *Casual Character* animation rig ([Poly Pizza](https://poly.pizza/m/kZ3DmIoGip)); the packed `anim-men.glb` from PR #746 has SHA-256 `2cf0c9713cc27902fe3e32f5878453bf838f72b632ef5a4278bb736bcf38f147`. `tools/merge_gltf_animations.py` combines those clips with the beach model after palette baking.
- **Coconut palm (island trees)** — evolveduk ([Sketchfab profile](https://sketchfab.com/evolveduk)), *Coconut Palm* ([Sketchfab model page](https://sketchfab.com/3d-models/coconut-palm-26e787f2ff2e4c0fb004c3b0210805a3)), licensed under [CC BY 4.0](http://creativecommons.org/licenses/by/4.0/). Prepared for gameplay with `tools/prepare_island_models.py` (`models/coconut_palm.glb` and `3d models/coconut_palm (1).glb`): root scale baked to `1.45 m` local height and canopy nodes named with `leaf` (`leafs` on the main frond mesh) so `IslandSetup` collides only with `Tree_0_Trunk` and `scripts/vegetation_visual.gd` animates the textured fronds.
- **Realistic grass tuft (island MultiMesh grass)** — Pasha ([Sketchfab profile](https://sketchfab.com/Pasha.)), *Realistic grass* ([Sketchfab model page](https://sketchfab.com/3d-models/realistic-grass-ba0971efc9ac4176b8f7d2379cd7250b)), Sketchfab Standard License ([terms](https://sketchfab.com/licenses)). Prepared for mobile MultiMesh scattering with `tools/prepare_island_models.py` (`models/realistic_grass.glb` and `3d models/realistic_grass.glb`): extracted a 6-ribbon (24-triangle, 72-face-vertex) 3D intersecting tuft with its embedded `512x256` RGBA grass-blade texture, converted to Y-up (`0.38 m` tall, grounded at `y = 0`), and baked a `0..1` vertical `COLOR_0` wind mask for `shaders/grass_wind.gdshader`.
- **Fallback palm trees, log, stone, and tree pot** — Kenney Nature Kit, CC0: [official pack](https://kenney.nl/assets/nature-kit). GLB conversions were sourced from [Hidencod/tge-assets](https://github.com/Hidencod/tge-assets), which identifies its Kenney model library as CC0 1.0. The two palm variants were recolored to a natural green/brown palette with `tools/recolor_kenney_palm.py`; the small rock was recolored as a neutral stone pickup with `tools/recolor_kenney_rock.py`.
- **Coconut and banana models** — Kenney Food Kit, CC0: [official pack](https://kenney.nl/assets/food-kit); GLB conversions from [Hidencod/tge-assets](https://github.com/Hidencod/tge-assets). Their embedded color textures are preserved.
- **Barrel model** — Kenney Pirate Kit, CC0: [official pack](https://kenney.nl/assets/pirate-kit); GLB conversion from [Hidencod/tge-assets](https://github.com/Hidencod/tge-assets).

## Audio

- **Ocean ambience** — Norwayjohn, [Freesound sound 404686](https://freesound.org/people/norwayjohn/sounds/404686/), CC0 1.0. The included MP3 is the source project's conversion of the CC0 WAV, from [Wave/Length](https://github.com/dougwhite/wave-length/); it loops quietly during gameplay.
- **Wood and island footsteps** — TinyWorlds, [Different Steps on Wood, Stone, Leaves, Gravel and Mud](https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud), CC0. The OGG files are included through the [OGA Footsteps pack](https://kenney.nl/assets/oga-footsteps): three wood variations for raft surfaces and gravel for island ground.
- **Pickup rustle and chopping sounds** — Kenney RPG Audio, CC0: [official pack](https://kenney.nl/assets/rpg-audio).
- **Sea wind, foliage rustle, and rain ambience beds** — original procedural project audio, generated offline by `tools/generate_environment_audio.py`. These WAVs use filtered seeded noise and periodic stereo envelopes; they are not downloaded recordings. The credited recorded ocean above remains the main wave layer.

## Optional Sketchfab integration recommendations (not bundled)

These are external suggestions only; no Sketchfab downloads are included in this repository until the owner downloads and integrates them. Confirm each live license before use and add a full CC BY attribution here if imported:

- Low-Poly Seagull (with Animation & Rigged) — simonaskLDE, [Sketchfab model page](https://sketchfab.com/3d-models/low-poly-seagull-with-animation-rigged-985024328902444c8270c0f09acc897e), CC BY 4.0 (as listed on the page, checked 2026-10-03).
- Simple Low poly Coconut Tree — Jewel John, [Sketchfab model page](https://sketchfab.com/3d-models/simple-low-poly-coconut-tree-ec0493afa1664a63ba278d54703ef995), CC BY 4.0 (as listed on the page, checked 2026-10-03).
- Stylized palm / coconut tree pack — W_illness, [Sketchfab model page](https://sketchfab.com/3d-models/stylized-palm-coconut-tree-pack-35e96b479cf942ad9407eb01a11ffa3a), CC BY 4.0 (as listed on the page, checked 2026-10-03).

See `SKETCHFAB_ASSET_INTEGRATION.md` for import, attribution, and scene replacement steps. Island and planter coconut palms use the supplied prepared coconut-palm GLB credited above; island grass uses the supplied prepared grass GLB. The bird flock uses original coastal_gull.glb models with animated wing pivots and huntable hitboxes; a licensed custom GLB can still be assigned.

## Procedural environment detail

`scripts/vegetation_visual.gd` generates original curved grass tufts and pinnate palm fronds for fallback foliage. Its leaf shader preserves the supplied coconut palm's texture and geometry; the grass shader uses the supplied grass texture. Procedural leaf/bark/water detail and motion are original project code.

The shared wood/metal/stone/cloth/soil surface shaders, rope coils, plastic canisters, metal scraps, seed packets, animated menu sea and matte/brass UI added on 2026-10-03 are original project code. They add no downloaded textures or models and preserve existing imported texture materials.

## Original CC0 survival models (2026-10-03)

models/coastal_fish.glb, coastal_gull.glb, human_hand.glb, survival_bow.glb and coastal_ridge.glb are original project assets generated offline by tools/generate_survival_models.gd. They have smooth modeled geometry and PBR materials, with no downloaded textures or geometry. Static meshes are merged by material; gull wing pivots stay separate for runtime animation. These assets are CC0 1.0; see models/ORIGINAL_SURVIVAL_ASSETS_LICENSE.md. The hollow rain barrel, planter walls, flames and projectile geometry are also original project code.

## Inventory artwork (2026-10-05)

`textures/ui/rope_launcher.png` is original AI-generated transparent rope-launcher artwork created with the built-in OpenAI ImageGen tool, with no input/reference images. Its text prompt describes this project's own olive/steel/rope launcher. The exact prompt is recorded in `textures/ui/ARTWORK.md`. The folded chart, compass, crossed salvage tools and nautical button trim are original project drawing code in `scripts/ui_icons.gd` and `scripts/survival_hud.gd`.

`textures/ui/survival_items.png` is original AI-generated artwork created with the built-in OpenAI ImageGen tool, using a text prompt and no reference images or third-party game art. It supplies 29 inventory item icons plus a backpack. Generation details and the exact prompt are in `textures/ui/ARTWORK.md`. Runtime UV regions/silhouettes preserve transparent margins and item proportions. The legacy action/build symbols remain original procedural code.

## Original advanced survival assets (2026-10-05)
Wild boar, sea turtle, shore crab, reef shark, raw/cooked meat and diving tank GLBs are original CC0 project models. Sources: tools/generate_wildlife_models.gd and tools/generate_advanced_models.gd. Machine geometry and shared surface detail are original project code in scripts/machine_visual.gd. No reference-game models or textures were copied. The existing palm, grass and other imported assets retain their separate license entries. See models/ORIGINAL_SURVIVAL_ASSETS_LICENSE.md.

Opening atlas: textures/ui/flooded_world_story.png, created using the built-in imagegen tool for this project. Full prompt and provenance: textures/ui/FLOODED_WORLD_ART.md. Torch/machine models and cached synthesized fire audio are original project content.

Latest raft surface: textures/ui/weathered_raft_wood.png, generated for this game with the built-in imagegen tool. Prompt: seamless orthographic close-up of continuous weathered driftwood, horizontal fibers, grey/brown salt erosion, natural knots/cracks, even diffuse light, no planks/seams/objects/text. Used as timber albedo on rounded logs and foundation planks; no downloaded wood scan.
Story narration audio/intro_space.wav, intro_city.wav, intro_flood.wav, intro_raft.wav: original project script synthesized locally using installed Microsoft David Desktop, 22.05 kHz mono PCM. These are synthesized speech, not a human recording. Current complete transcript matches the four CAPTIONS entries in scripts/flooded_world_intro.gd: Before the flood, our cities were alive. I thought the ocean ended at the shore. Then a stone from space struck the sea. A wave higher than the buildings came toward us. In one day, the ocean swallowed our cities. Ninety-five percent of the land disappeared. Only a few islands remained. I woke alone on a raft of tied logs. With my rope gun, I must salvage, build, and survive.
Original approach/impact audio/intro_approach.wav and intro_impact.wav are locally synthesized PCM effects. Existing ocean recording retains its original attribution above.

Coastal tree atlas textures/ui/coastal_tree_atlas.png is original generated photographic-style artwork created with the built-in imagegen tool, with no reference images. Exact prompt and usage: textures/ui/COASTAL_TREE_ART.md. Curved banana, coastal almond and coastal shade-tree meshes are original code in scripts/coastal_tree_visual.gd. These are textured game meshes, not photogrammetry. Existing coconut-palm textures retain their earlier attribution.
