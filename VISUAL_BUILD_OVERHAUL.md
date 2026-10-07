# Rounded timber, ocean and construction update

Source update, 2026-10-07. The owner's latest screenshots guide the handcrafted log construction and ocean lighting. These are actual game meshes and shaders. Renderer previews use the same craftable pieces in an isolated test scene; they do not change the owner's saves or grant a completed camp at New Game.

## Playable changes

- Foundations, roofs, full walls and half walls use five joined rounded timber members, underside/back cross-poles, doubled hemp bindings and knots. Hidden original boxes preserve placement bounds and collision.
- The hinged door has timber, bindings and cross-bracing. Windows are permanent open timber frames without glass or shutters; legacy closed windows restore as open gaps. Door open-state restoration remains intact.
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

Native fixture: `tests/visual_build_native_preview.gd`, staged `MobileTests` data, real Mobile/D3D12 renderer, 1280 by 720 and 10 shared timber draws. The latest short NVIDIA MX450 samples recorded late afternoon (73 pieces): median 17.001 ms, p95 21.656 ms, maximum 24.028 ms; night (75 pieces): median 18.958 ms, p95 23.681 ms, maximum 25.441 ms. These are short desktop observations after preparation, not sustained phone/thermal measurements. These construction samples precede the subsequent island graphics changes.

Views: `build/overhaul-timber-room.png`, `overhaul-joined-timbers.png`, `overhaul-survivalist.png`, `overhaul-window-open.png`, `overhaul-night-camp.png`. Logs: `build/source-*-console.log`, `build/overhaul-native-preview.log`. The full source stage was `build/source-check-71cbd67383c449f198d95f14a4556a6d`.

Staging directories contain junctions to real project folders; never recursively delete through them. Historical shutdown ObjectDB warnings are distinct from failed assertions; inspect the current logs before making leak claims. No APK was exported or inspected, and no phone FPS/touch/thermal result is claimed. Reopen Godot, finish imports and follow `BUILD_ANDROID.md` for manual export.

## Subsequent island graphics update

The owner's island reference and request to remove the centre light apply to all four islands. They now have shared CC0 rock/sand PBR maps, three solid headlands, grounded dry palms, smaller broadleaf sprays, four bounded canopy/understory draws, shoreline boulders, inland grass patches and a clear approach beach. Glowing pillars, orbs and coloured beacon lights are removed; map/HUD navigation anchors remain. Existing coordinates, terrain footprint, resource IDs and saved plant records remain compatible.

The ocean uses shared seamless normal detail, compact terrain masks for approximate shallows/foam, and a dense camera-centred 800 m patch. World buoyancy samples retain their original formula. Lower mobile profiles retain the established atmospheric sky and cirrus. Textures are 1K with retained mipmapped BPTC/ASTC imports. New asset sources and download fingerprints are in textures/island/SOURCES.md.

Per the owner's request, the full suite was not repeated. The focused island_visual_smoke suite passed 71 checks in isolated storage: solid matching headlands, sand assignment after tree import, dry grounded palms, invisible navigation anchors, crop pickups, batched mobile budgets, four small height masks, and unchanged buoyancy after ocean recentering. The earlier 470 checks are evidence for the preceding construction/intro/save update, not a fresh full regression of this island update.
Actual desktop renderer views: build/island-realism-Island.png, island-realism-ReefIsle.png, island-realism-DriftwoodCay.png, island-realism-FarCove.png and island-realism-mobile-balanced.png. The native fixture waits for completed grass and terrain preparation; it applies mobile foliage ceilings and hides only the preview HUD. Its latest 1280x720 Mobile/D3D12 High sample on NVIDIA MX450 recorded median 20.378 ms and p95 33.525 ms. This short desktop sample is not a 60 FPS guarantee or phone measurement. Both High and Balanced sky paths were visually reviewed. The experimental cheap cumulus approximation was removed after visible artefacts; Balanced retains the established atmospheric sky and cirrus path. Use the existing Battery Saver/30 FPS option if needed on the actual phone.

The environment is improved with free surface scans and original/shared geometry, but the current procedural island silhouettes and vegetation remain below the uploaded reference's photorealistic asset quality. No exact AAA visual match or real-device result is claimed.

Follow-up corrections: rope wraps/knots now have three geometric braided strands and rough fibre shading; building sound reuses the existing CC0 timber impact. Ground walls align to exact foundation edges, stairs check head clearance, and automatic roofs preserve stairwells. Rain is masked below actual nearby roof footprints, while exposed decks remain wet. Visible ocean swells use denser nearby tessellation, restrained blue colours and a compact solid-deck displacement mask. The exact supplied coconut model remains shared by island/planter palms. Crops use the new tomato and potato GLBs; harvesting potatoes lifts their real tubers/roots into view. A craftable/portable torch mounts on walls, supplies night light, and saves its flame/fuel. Gravity casts sweep solid obstacles; avatar forward and animated right-hand aim are corrected. See the latest GAME_GUIDE section for controls, costs, budgets and focused evidence. No APK or phone result was produced.
