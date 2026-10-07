# Rounded timber, ocean and construction update

Source update, 2026-10-07. The owner's latest screenshots guide the handcrafted log construction and ocean lighting. These are actual game meshes and shaders. Renderer previews use the same craftable pieces in an isolated test scene; they do not change the owner's saves or grant a completed camp at New Game.

## Playable changes

- Foundations, roofs, full walls and half walls use five joined rounded timber members, underside/back cross-poles, doubled hemp bindings and knots. Hidden original boxes preserve placement bounds and collision.
- The hinged door has timber, bindings and cross-bracing. Windows have a hinged wooden shutter and an unobstructed opening when open. There is no glass. Their optional saved open states default to closed for old records.
- HalfWall is appended at index 16, height 1.25 m, cost 4 Wood and 1 Rope. CargoCrate follows at index 17, cost 6 Wood, 2 Rope and 1 Metal. Its crate, rope coil and net use shared procedural geometry. It is a physical decorative prop, not an extra storage inventory.
- Enclosed full-wall rooms receive their entire roof in one transaction, with total materials shown in the preview. Flood fill is bounded to 64 deck cells. Existing roofs are excluded; insufficient supplies spend nothing. Higher/non-cardinal structures retain the legacy socket route.
- Build Mode shows a subtle raft-local 2 m grid. Shared timber draws retain individual physics, sockets, removal refunds and save identity. Edited pieces temporarily render separately.

Older recipe indexes and six mobile blueprint shortcuts are unchanged. Cycle the selection to reach the new pieces. The small starter raft and once-per-save 2,000 testing supplies remain enabled.

## Materials and presentation

Final asset: `textures/construction/timber_photographic_atlas.png`, original built-in ImageGen output, 1254 by 1254. Four strips contain pine, cedar, walnut and hemp. Its retained import settings use a 1024 size limit, High Quality VRAM compression and mipmaps, currently producing BPTC/ASTC. Full generation/edit prompts are in `textures/construction/PHOTOGRAPHIC_TIMBER.md`. No texture or geometry was extracted from the owner's reference screenshot.

Longitudinal UVs follow each timber. Flat interpolation of per-instance seeds fixes the grain speckling observed in real Mobile/D3D12 rendering; ordinary anisotropic mip sampling remains stable. Photographic albedo, rounded geometric normals, member variation and damp roughness/specular masks supply the wood response. Hemp uses a rough material. No wood emission is used.

Ocean shading adds broad irregular slopes, moving ripples, directional sun glitter, selected whitecaps, trough contrast and analytic sky reflection, with filtered distant detail. Its displaced height formula is unchanged and mirrored by the buoyancy sampler. Sun glitter follows the real camera/sun direction; it is not fixed to one screen edge.

Sky3D owns sun, moon and clock. The default day is 24 real minutes, adjustable from 6 to 96. New Game keeps the prepared dawn reveal at 6.25; Continue restores saved time. The preview uses late afternoon at 16.6. Cumulus stays visible near the horizon, with bounded grazing rays to avoid marching bands. Soft diffuse fill adds no second specular sun. Mobile uses depth fog and analytic reflections; High desktop Forward+ can add SSAO, SSR and volumetric fog. Battery Saver disables mist/fireflies and the extra small water-detail layer.

The existing CC0 rig has canvas/denim/boot colours, weave UVs and a blended swimming clip. It remains stylized and does not match the reference's realistic human. First person retains FOV 75 and the original eye/capsule, with optional 0.05 m head bob. Third person uses a 5 m collision-aware spring arm and initial downward angle. Shared solver templates, a reused GPU swim emitter and cached construction audio avoid repeated allocations.

## Save compatibility

`scripts/save_storage.gd` writes AES-256-CBC with PKCS#7 padding, a fresh IV and HMAC-SHA256 using a separate derived authentication key. Authentication precedes decryption. The random 32-byte local key is `user://raft_save.key`. This protects against corrupted/edited data; a person with access to the local key can still read their own saves.

Valid legacy plaintext saves load and migrate on a successful write. The first migration backup can remain plaintext until a later save rotates it. A temporary file is flushed and verified before replacement. Corrupt primaries do not replace valid backups. Failed reads/writes or missing keys preserve live inventory and unreadable existing saves. Restored transforms must be finite, bounded and nonsingular. Transfer the original key with encrypted primary/backup files.

## Verification

All twelve isolated source suites passed on 2026-10-07 through `tools/verify_source.ps1`:

| Suite | Checks |
| --- | ---: |
| Rope | 27 |
| Testing supplies | 11 |
| Mobile controls | 93 |
| Foundations | 17 |
| Environment | 41 |
| Island markers | 23 |
| Menu loading | 21 |
| Survival loop | 53 |
| Advanced survival | 64 |
| Cinematic raft / video | 39 |
| World visuals | 28 |
| Visual construction / authenticated saves | 53 |
| Total | 470 |

Construction checks place 63 foundations through real grid/cost validation, verify transactional room roofs, rotated raft support, half walls, wooden shutters, the craftable cargo prop, mixed save restoration and malformed transforms. Three 64-wall add/remove cycles verify bounded draw/node/resource retention. The empty-water rope fixture disables random startup salvage; separate assertions still verify actual capture/release.

Native fixture: `tests/visual_build_native_preview.gd`, staged `MobileTests` data, real Mobile/D3D12 renderer, 1280 by 720, 75 pieces and 10 shared timber draws. Its settled short NVIDIA MX450 sample recorded median 16.664 ms, p95 17.012 ms, maximum 17.345 ms. These are short desktop observations after preparation, not sustained phone/thermal measurements.

Views: `build/overhaul-timber-room.png`, `overhaul-joined-timbers.png`, `overhaul-survivalist.png`, `overhaul-window-open.png`, `overhaul-night-camp.png`. Logs: `build/source-*-console.log`, `build/overhaul-native-preview.log`. The full source stage was `build/source-check-71cbd67383c449f198d95f14a4556a6d`.

Staging directories contain junctions to real project folders; never recursively delete through them. Historical shutdown ObjectDB warnings are distinct from failed assertions; inspect the current logs before making leak claims. No APK was exported or inspected, and no phone FPS/touch/thermal result is claimed. Reopen Godot, finish imports and follow `BUILD_ANDROID.md` for manual export.
