# Third-party asset credits

The assets below are separate from the Raft Survival source-code license. They are included here for provenance; all listed art/audio assets are CC0/public-domain, so attribution is appreciated but not required.

## 3D models

- **Beach survivor character** — Quaternius, *Beach Character* (male). The [Poly Pizza model page](https://poly.pizza/m/DojKLcO34E) labels it Public Domain (CC0). The original source GLB came from [H3-Teamy PR #746](https://github.com/grvermeulen/H3-Teamy/pull/746); its SHA-256 (`21f7667810fbffc90c1605629884abd144b4423ab309af9ee0338e51afabdf7d`) matches the PR's `beach-man.glb` byte-for-byte. `models/beach_survivor.glb` keeps the skinned mesh and skeleton. `tools/bake_palette_glb.py` converts the source `_PALETTE` attribute to standard linear `COLOR_0` vertex colors and generates vertex normals for Godot. Its eight CC0 idle, walk, run, and action clips come from Quaternius' *Casual Character* animation rig ([Poly Pizza](https://poly.pizza/m/kZ3DmIoGip)); the packed `anim-men.glb` from PR #746 has SHA-256 `2cf0c9713cc27902fe3e32f5878453bf838f72b632ef5a4278bb736bcf38f147`. `tools/merge_gltf_animations.py` combines those clips with the beach model after palette baking.
- **Palm trees, log, stone, and tree pot** — Kenney Nature Kit, CC0: [official pack](https://kenney.nl/assets/nature-kit). GLB conversions were sourced from [Hidencod/tge-assets](https://github.com/Hidencod/tge-assets), which identifies its Kenney model library as CC0 1.0. The two palm variants were recolored to a natural green/brown palette with `tools/recolor_kenney_palm.py`; the small rock was recolored as a neutral stone pickup with `tools/recolor_kenney_rock.py`.
- **Coconut and banana models** — Kenney Food Kit, CC0: [official pack](https://kenney.nl/assets/food-kit); GLB conversions from [Hidencod/tge-assets](https://github.com/Hidencod/tge-assets). Their embedded color textures are preserved.
- **Barrel model** — Kenney Pirate Kit, CC0: [official pack](https://kenney.nl/assets/pirate-kit); GLB conversion from [Hidencod/tge-assets](https://github.com/Hidencod/tge-assets).

## Audio

- **Ocean ambience** — Norwayjohn, [Freesound sound 404686](https://freesound.org/people/norwayjohn/sounds/404686/), CC0 1.0. The included MP3 is the source project's conversion of the CC0 WAV, from [Wave/Length](https://github.com/dougwhite/wave-length/); it loops quietly during gameplay.
- **Wood and island footsteps** — TinyWorlds, [Different Steps on Wood, Stone, Leaves, Gravel and Mud](https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud), CC0. The OGG files are included through the [OGA Footsteps pack](https://kenney.nl/assets/oga-footsteps): three wood variations for raft surfaces and gravel for island ground.
- **Pickup rustle and chopping sounds** — Kenney RPG Audio, CC0: [official pack](https://kenney.nl/assets/rpg-audio).
