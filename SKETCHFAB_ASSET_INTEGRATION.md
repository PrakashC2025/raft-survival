# Sketchfab assets for the existing island scene

This is an integration note for the current Godot project, not a new project. The codebase does **not** bundle or claim downloaded Sketchfab files. Instead, the home-island bird component is ready to accept a licensed GLB, and the existing palm instances can be swapped after a creator-authorized download. Keep the current Kenney CC0 models as fallback until those files are imported.

## Compatible candidate models

These Sketchfab pages were checked on 2026-10-03. Re-check the live page and its download/license terms before each redistribution; only download assets whose creator has enabled it.

- **Bird:** [Low-Poly Seagull (with Animation & Rigged)](https://sketchfab.com/3d-models/low-poly-seagull-with-animation-rigged-985024328902444c8270c0f09acc897e) by **simonaskLDE**, CC Attribution / CC BY 4.0, about 580 triangles. `scripts/island_birds.gd` can instance its GLB, orbit it around the home island and play its first non-reset animation. If the animation is a ground idle rather than a flight cycle, disable it in Blender or re-export a flight clip.
- **Low-poly coconut palm:** [Simple Low poly Coconut Tree](https://sketchfab.com/3d-models/simple-low-poly-coconut-tree-ec0493afa1664a63ba278d54703ef995) by **Jewel John**, CC Attribution / CC BY 4.0, about 1.1k triangles. This is a mobile-friendly option for replacing a palm instance.
- **More detailed stylized palm pack:** [Stylized palm / coconut tree pack](https://sketchfab.com/3d-models/stylized-palm-coconut-tree-pack-35e96b479cf942ad9407eb01a11ffa3a) by **W_illness**, CC Attribution / CC BY 4.0, about 36.2k triangles. Prefer only after reducing it to a mobile budget (or use it for a close-up hero tree).

CC BY requires attribution and a link to the license; include creator, source URL, license, and any changes in `ASSET_CREDITS.md`. Do not remove creator credit or re-upload the source model as your own. Sketchfab downloads are user-initiated; this repo intentionally does not bypass the creator's download flow.

## Import a bird

1. On the model page, use **Download 3D Model** and choose the available glTF/GLB download. Inspect the included license/readme and preserve any attribution text.
2. In Godot, copy the extracted `.glb` and its referenced textures into `models/`, e.g. `models/sketchfab_seagull.glb`. Keep companion textures beside the GLB and let Godot import them; do not flatten or delete referenced images.
3. Select `Island/IslandBirds` in `scenes/main.tscn`. Set **Sketchfab Bird Model** to `res://models/sketchfab_seagull.glb` in the Inspector. The runtime keeps the low-poly gull fallback if this export is blank or the path is absent.
4. Check the imported forward axis/scale and the first non-reset animation. Adjust `model.scale` in `scripts/island_birds.gd` (currently 0.55) if needed. If the source has no flying animation, the flock's orbit still works; use a flight clip for convincing wings.
5. Test on the Mobile renderer. Keep the bird count small (default 4) and imported shadows disabled for a mobile-friendly scene. If the GLB includes separate image files, verify those new dependencies are covered by Android export filters and inspect the finished package after a manual export.

## Replace or add a palm

1. Download the coconut palm GLB through its Sketchfab page and copy it plus referenced textures to `models/`.
2. Open `scenes/main.tscn`; change a selected `PalmTree*` node's instance to the imported GLB, or add a new Node3D instance under `Island`. Match the existing ground-level placement and scale (the old instances are roughly 2–3x depending on the Kenney model's source units).
3. If the imported tree has separate leaves and trunk, preserve node names/materials as appropriate. `IslandSetup` creates trunk colliders and skips leaf collisions; add leaf meshes under a node containing “leaf” or to group `no_collision` to keep them visual-only. Verify that palm snapping does not move it onto its own collision body.
4. For CC BY assets, add the source line to `ASSET_CREDITS.md`. Keep the existing Kenney scene instances if the download is unavailable; the current game remains playable without external Sketchfab files.

## Import realistic grass (`realistic_grass.zip`)

1. Run the bundled converter on your downloaded `.zip` archive (supports Sketchfab glTF zips with `scene.gltf` + `scene.bin` + `textures/`, `.glb` zips, and `.obj` zips):
   ```bash
   python tools/import_grass_zip.py path/to/realistic_grass.zip --wire-scene
   ```
   This writes `models/realistic_grass.glb` (plus any companion textures in `models/`) and assigns `sketchfab_grass_model = "res://models/realistic_grass.glb"` on `Island/IslandGrass` in `scenes/main.tscn`.
2. At runtime, `scripts/island_grass.gd` automatically centers and grounds imported grass meshes at `y = 0`, normalizes tuft height (`target_tuft_height = 0.38`), bakes a vertical `0..1` `COLOR_0` wind-sway gradient if the source model was not vertex-painted, forwards any imported `albedo_texture` (with alpha cutout) to `shaders/grass_wind.gdshader`, and budgets instance count by triangle count so high-poly grass clumps stay mobile-safe.
3. Add the creator credit and license from the archive's `license.txt` to `ASSET_CREDITS.md`. Leave `sketchfab_grass_model` blank to keep the built-in 3-blade procedural tuft fallback.

## Existing runtime hooks

```gdscript
# scripts/island_setup.gd -- swaps island Palm* nodes to the prepared coconut palm GLB
@export_file("*.glb,*.gltf") var sketchfab_palm_model := "res://models/coconut_palm.glb"

# scripts/island_birds.gd -- set in the IslandBirds Inspector
@export_file("*.glb") var sketchfab_bird_model := ""
@export_range(1, 8, 1) var bird_count := 4

# scripts/island_grass.gd -- uses the prepared 24-triangle realistic grass tuft GLB
@export_file("*.glb,*.gltf,*.scn,*.tscn") var sketchfab_grass_model := "res://models/realistic_grass.glb"
@export var target_tuft_height := 0.38
```

`tools/prepare_island_models.py` prepares `3d models/coconut_palm (1).glb` and `3d models/realistic_grass.glb` into `models/coconut_palm.glb` and `models/realistic_grass.glb` (and updates the files in `3d models/` in place). Both `IslandSetup` and `IslandGrass` load via `ResourceLoader` when imported by Godot Editor and fall back to runtime `GLTFDocument` buffer parsing before the editor has generated `.godot/imported/*.scn`.

`IslandMountain` in the existing home-island scene is generated locally by `scripts/island_mountain.gd`; no external mountain project or model is required. Sand gathering, held-item presentation, planter top-dressing, save restoration, and pooled footprints are already implemented in the current game source.
