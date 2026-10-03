# Third-party asset credits

The bundled assets below are separate from the Raft Survival source-code license; the listed bundled art/audio assets are CC0/public-domain, so attribution is appreciated but not required. Optional Sketchfab recommendations at the end are not bundled and are CC BY; follow their live license/attribution terms before importing.

## 3D models

- **Beach survivor character** — Quaternius, *Beach Character* (male). The [Poly Pizza model page](https://poly.pizza/m/DojKLcO34E) labels it Public Domain (CC0). The original source GLB came from [H3-Teamy PR #746](https://github.com/grvermeulen/H3-Teamy/pull/746); its SHA-256 (`21f7667810fbffc90c1605629884abd144b4423ab309af9ee0338e51afabdf7d`) matches the PR's `beach-man.glb` byte-for-byte. `models/beach_survivor.glb` keeps the skinned mesh and skeleton. `tools/bake_palette_glb.py` converts the source `_PALETTE` attribute to standard linear `COLOR_0` vertex colors and generates vertex normals for Godot. Its eight CC0 idle, walk, run, and action clips come from Quaternius' *Casual Character* animation rig ([Poly Pizza](https://poly.pizza/m/kZ3DmIoGip)); the packed `anim-men.glb` from PR #746 has SHA-256 `2cf0c9713cc27902fe3e32f5878453bf838f72b632ef5a4278bb736bcf38f147`. `tools/merge_gltf_animations.py` combines those clips with the beach model after palette baking.
- **Palm trees, log, stone, and tree pot** — Kenney Nature Kit, CC0: [official pack](https://kenney.nl/assets/nature-kit). GLB conversions were sourced from [Hidencod/tge-assets](https://github.com/Hidencod/tge-assets), which identifies its Kenney model library as CC0 1.0. The two palm variants were recolored to a natural green/brown palette with `tools/recolor_kenney_palm.py`; the small rock was recolored as a neutral stone pickup with `tools/recolor_kenney_rock.py`.
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

See `SKETCHFAB_ASSET_INTEGRATION.md` for import, attribution, and scene replacement steps. The current playable palms remain the Kenney CC0 assets listed above; the bird flock has an original low-poly fallback until a downloaded GLB is assigned.

## Procedural environment detail

`scripts/vegetation_visual.gd` generates original curved grass tufts and pinnate palm fronds, used with the existing credited palm trunks. Leaf/bark/water shaders add original project surface detail and motion without external textures or copied reference-game artwork.
