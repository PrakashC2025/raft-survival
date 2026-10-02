# RaftSurvival — Complete Project Documentation

> **Engine:** Godot 4.7 · **Language:** GDScript · **Physics:** Jolt 3D  
> **Renderer:** Mobile (D3D12 on Windows) · **Resolution:** Stretched canvas (`canvas_items`, expand)
> **Physics ticks:** 60 Hz

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Folder & File Map](#2-folder--file-map)
3. [Input Map](#3-input-map)
4. [Autoloads](#4-autoloads)
5. [Main Scene Tree](#5-main-scene-tree)
6. [Player System](#6-player-system)
7. [Camera & Crosshair](#7-camera--crosshair)
8. [Ocean System](#8-ocean-system)
9. [Raft System](#9-raft-system)
10. [Debris System](#10-debris-system)
11. [Rope / Hook System](#11-rope--hook-system)
12. [Inventory System](#12-inventory-system)
13. [Door System](#13-door-system)
14. [Building Scenes](#14-building-scenes)
15. [Physics & Collision Layers](#15-physics--collision-layers)
16. [Game Loop & Frame Flow](#16-game-loop--frame-flow)
17. [State Machines](#17-state-machines)
18. [Build Algorithm Deep Dive](#18-build-algorithm-deep-dive)
19. [Edit System Deep Dive](#19-edit-system-deep-dive)
20. [Rope Algorithm Deep Dive](#20-rope-algorithm-deep-dive)
21. [Survival Stats (stats.gd)](#21-survival-stats-statsgd)
22. [Shared Helpers](#22-shared-helpers)
23. [Placeholder Scenes](#23-placeholder-scenes)
24. [How to Extend](#24-how-to-extend)
25. [Script Source Reference](#25-script-source-reference)
26. [Island](#26-island)

---

## 1. Project Overview

**RaftSurvival** is a first-person ocean survival game built in Godot 4. The player starts on a small 2x2 wooden raft in the middle of a vast ocean. Floating debris drifts by on the current. The player uses a throwable hook (Q) to catch distant debris or picks it up directly (E) at close range. Collected resources are spent to build foundations, walls, doors, windows, roofs, and stairs to expand the raft into a larger structure.

### Core Gameplay Loop

```
See debris floating by
		|
Aim crosshair at debris
		|
  CLOSE (<=5m): Press E        -> Direct pickup into inventory
  NEARBY (<=2m): Press E        -> Area pickup (no aim needed)
  FAR  (>5m): Hold Q / Release -> Hook thrown toward debris (charge = distance)
		|
Spend resources in Build Mode (B)
		|
Expand raft -> Build walls -> Build roof -> Build shelter
		|
Double-click E on a placed piece -> move / rotate / remove it (X refunds)
```

### Key Design Principles

- **Single Aim Source:** One raycast from the camera center powers all interactions.
- **Grid-Cell Foundation:** Foundations snap to a structural grid. Only Foundations (and the raft) live in the occupancy grid; walls/roofs/doors/windows are edge or socket attachments.
- **Edge-Based Wall:** Walls attach to Foundation edges. Crosshair determines which edge and position.
- **Cell-Centred Roof:** Roofs are 2x2 slabs that cover one whole **deck cell**, exactly like a Foundation tile — a roof aimed at any wall of a room is placed 1.0m off that wall's line so it is **centred on the room's cell**, flush on all four wall tops (never straddling the wall, half over the neighbour). Aiming at a roof's **edge** expands the roof into the adjacent free cell at the same height; aiming at its **center** stacks a second roof on top. Tiles chain cell-to-cell like foundations, and the plane-fill fallback tiles roofs **continuously in all 4 directions** off any existing roof chain, RED on occupied cells. A second roof can never land on an already-roofed cell (`ROOF SLOT OCCUPIED` / OVERLAP RED). A roof's TOP face doubles as a **second-floor deck**: walls, doors and windows snap onto it (center or edge slots) and stairs mount on its top-edge `Socket_Stairs*` sockets — full multi-level building from roof tops.
- **Full-height stairs:** one staircase flight climbs a full wall (~2.64m) to roof level; walking auto-steps each riser (no jumping needed) and the player can walk onto and across roof tops (roofs are solid walkable 2x2 slabs).
- **Group-Based Overlap:** All build pieces join the `"build_surface"` group. Overlap detection excludes group members hierarchically.
- **Flat Transform Solver:** All placement math uses the support's *flat* transform (position + Y-rotation only, no wave tilt) so placed buildings are always level, never tilted by waves.
- **Debug-by-default:** `player._ready()` sets `Inventory.infinite = true` and grants 999 Wood / Rope / Plastic.

---

## 2. Folder & File Map

```
project_root/
├── project.godot
├── main.gdshader                # Ocean vertex/fragment shader (visual waves)
├── main.tscn                    # Main scene (ocean, raft, player, spawner)
├── player.gd                    # ~2980 lines — movement, building, edit, HUD
├── build_socket.gd              # BuildSocket class (Marker3D sockets)
├── build_system.gd              # Shared static socket-attachment solver
├── crosshair.gd                 # Hollow-circle reticle (CanvasLayer)
├── ocean.gd                     # Wave height function + day/night driver for the ocean shader
├── raft.gd                      # Floating physics + buoyancy sample points
├── raft.tscn                    # Base raft: 8 edge/corner sockets + BuiltPieces/
├── debris.gd / debris.tscn      # Floating debris (RigidBody3D)
├── debris_spawner.gd            # Continuous upstream debris stream
├── rope_system.gd               # Hook + rope state machine (auto-reel, multi-catch)
├── rain_system.gd               # Random rain events: wind streaks, surface splashes, lightning
├── mobile_controls.gd           # Mobile touch UI (joystick, look drag, icon action buttons)
├── survival_hud.gd              # Mobile survival HUD (day/night clock, status circles, pills, hotbar, bag)
├── ui_icons.gd                  # Vector icon library (original primitives)
├── inventory.gd                 # Autoload singleton (items + crafting)
├── stats.gd                     # Survival stats (health/hunger/thirst) — autoload Stats (drain off)
├── foundation.tscn              # 2x2x0.3m — 4 edge sockets + Socket_Top
├── wall.tscn                    # 2x2.5x0.2m — Socket_Base/Top/Middle + 4 sides
├── roof.tscn                    # 2x0.15x2m — Socket_Base/Top + 4 edge sockets
├── stairs.tscn                  # 6-step + landing staircase (climbs a full wall, ~2.64m)
├── door.tscn / door.gd          # Wall-sized door: static frame + hinged leaf
├── window.tscn                  # Wall-sized panel with plus-shaped opening
├── raft_extension.tscn          # Placeholder (no sockets/script yet)
├── bonfire.tscn                 # Placeholder (no physics body/script yet)
└── icon.svg
```

---

## 3. Input Map

Defined in `project.godot` (`[input]`). `rope_*` actions are **created at runtime** by `rope_system._ensure_actions()`.

### 3.1 Mobile Touch Controls (`mobile_controls.gd`)

A full-screen `Control` under `Player/CanvasLayer` (`MobileControls`) that feeds the **same Input actions** as the keyboard — the game logic never knows the input is a touch:

- **Joystick = move only:** a **fixed joystick dock** sits at bottom-left; touch it (within `dock_zone_scale` × stick radius) and drag to walk. Analog strength is pushed to `move_*` via `Input.action_press(action, strength)`. Movement never spawns anywhere else on screen.
- **Touch anywhere else = look:** touching *any* other point of the screen and dragging rotates the camera (`player.add_look_input(rel, 0.007)` — the shared mouse/touch path). A second finger can look while the first holds the joystick.
- **Full button set** (each presses its keyboard action on touch-down, releases on touch-up, so taps and holds both behave like the keys):
  - Normal mode — `JUMP` (big; jump / hold = swim up), `RUN` (sprint, hold), `USE`/HAND (interact — **only shown when pressing it would actually do something**, i.e. the exact E-key test: aimed debris within pickup range, aimed door, **any debris within the nearby 2 m grab range**, an **empty planter while a seed is selected** (plant), or a **mature plant/tree/stump** (pick fruit / dig / chop / remove stump)), `DIVE` (shown while swimming; move_down), `CLIMB` (shown **only while swimming right next to the raft/foundation deck** — taps `player.climb_out()` to pull the player onto the deck; same logic as E), `ROPE` (big; **hold to charge, release to throw** — same as Q), `BACK` (shown only while the rope is out; rope_cancel recall), `EDIT` (shown when aiming at your own piece; one tap = desktop "E, E" pickup), `BUILD` (**left-center**, above the joystick grab zone — the icon turns into a red ✕ and its ring turns red while Build Mode is on, i.e. a visible ON/OFF state).
  - Build mode — big `PLACE`, `ROT`, `NEXT`, `EXIT` (JUMP/RUN/USE/ROPE hide so you don't mis-tap). `NEXT` cycles through every piece including the three planters; `PLACE` puts the selected piece down.
  - Edit mode — `PLACE` (confirm), `ROT`, `REMOVE`, `CANCEL` (left-center build button turns into ✕/cancel).
  - **All modes — `?` help button** (small, above the BUILD toggle on the left edge): opens an in-game controls guide panel (move / use / building / farming quick-start / rope / bag / PC keys). Tap anywhere outside the panel or the ✕ to close; while open, joystick and camera look are suspended.
- **Visibility:** mobile UI shows **only on real mobile builds** (Android/iOS) or when `force_show` is enabled in the inspector — **F10** toggles it live for quick desktop previews. Never on a plain PC otherwise, so the keyboard + mouse are untouched (the overlay is `mouse_filter = IGNORE`; it reads touches via `_input` and can never swallow the PC mouse). Everything is laid out per-viewport (safe margins, sizes scale), portrait and landscape.
- Buttons are invisible Button nodes (their hit areas) with **dark circular icon art painted by the overlay's `_draw()`** — original vector glyphs via `ui_icons.gd` (jump ↑, run, hand/interact, hook/rope, hammer↔X, check, rotate, …). Button identity/visibility still switches with mode.
- **SurvivalHUD (`survival_hud.gd`)** — a sibling full-screen overlay that coordinates with `MobileControls` through `claims_touch()`/`is_blocking()` (its areas are never turned into camera look; while its bag panel is open the joystick is dropped). **Normal mode** shows the **inventory hotbar** (inventory slots 0..5: items you own — a fresh game starts with `Rope` in slot 1) + a **BAG button**; tapping a slot selects that item (`player.select_hotbar_slot()` → `active_item`, cyan border). **Build Mode** swaps that bar for the **build-piece row** (Foundation/Wall/Roof/Stairs/Door/Window/PlanterPot/PlanterBox/TreePot; tap = `player.select_piece_for_build()`); the inventory is untouched underneath and is restored exactly when Build Mode exits. The bag opens a **30-slot panel** (5×5 bag + hotbar row) with **drag-and-drop**: drag any slot onto another — empty destination = move, same item = merge stacks, different item = swap; a drag ghost follows the finger and nothing is ever deleted. Overflowing pickups (stack size 99, new items auto-fill bag slots 6..29 before hotbar) show a **"BAG FULL"** toast instead of dropping items. Also draws a **day/night clock** at the far top-right corner (split sun/moon dial showing `Sky3D.current_time` as DAY n + hh:mm underneath; the status circles sit to its LEFT so the caption never overlaps anything), plus **status circles** (health/hunger/thirst), top-left **resource pills** (Wood/Rope/Plastic/Metal totals), and a small **build chip** top-center while placing/editing (piece + validity + cost). Tapping outside the panel or the ✕ closes it.
- Desktop dev label (`InventoryHUD`) is hidden while the mobile UI is active.
- The joystick ring/knob, resting D-pad dock, all action buttons, and the whole SurvivalHUD are `_draw()` visuals (no icon image assets).

| Action | Key | Purpose |
|---|---|---|
| `move_forward/back/left/right` | W / S / A / D (+ Arrows) | Movement |
| `jump` | Space | Jump / Swim up (hold = continuous swim up) |
| `move_down` | C | Dive on ground / Swim down |
| `interact` | E | Pickup debris (in range) / Toggle door / **Climb onto the raft while swimming next to it** / Plant a seed on an aimed empty planter (seed selected) / Pick a ripe fruit (tap) / Dig a crop, chop a tree, or remove a stump (hold) / Double-click = pick up piece for editing |
| `build` | B | Toggle build mode / Cancel edit |
| `cycle_build` | Tab | Cycle: Foundation→Wall→Roof→Stairs→Door→Window→PlanterPot→PlanterBox→TreePot |
| `rotate_build` | R **and** Y | Rotate build 90° (hold **Shift** for 15° fine steps) |
| `rotate_build_x` | X | Rotate on X axis (**edit mode only** — X is shadowed by `remove_build` in edit mode) |
| `place_build` | P | Place building / Confirm edit |
| `remove_build` | X | Remove building (edit mode) + refund |
| `sprint` | Shift | Sprint / Swim fast |
| `quick_save` | F5 | Quick-save (writes the second "quick" save slot) |
| `rope_throw` | Q (runtime) | Hold to charge, release to throw hook (reel is automatic) |
| `rope_pull` | F (runtime) | Skip the pause and reel immediately (shortcut — auto anyway) |
| `rope_cancel` | Right-click (runtime) | Recall the rope from any state; releases any caught debris |
| **F3** (runtime) | Toggle the build overlay (footprint samples + support ratio) |
| **F5** (dev, ocean.gd) | Force Noon (12:00) — jump straight to a time of day |
| **F6** (dev, ocean.gd) | Force Sunset (18:36) |
| **F7** (dev, ocean.gd) | Force Night (00:24) |
| **F8** (dev, ocean.gd) | Force Sunrise (06:24) |
| **F9** (dev, ocean.gd) | Toggle the day/night debug HUD (time, sun/moon energy, ambient, ocean factors, fog) |

> **Note:** `rotate_build` binds both R and Y; holding **Shift** while rotating uses 15° steps instead of 90° (handy for angling walls placed in a foundation's center). `rotate_build_x` binds X, but in edit mode X is consumed by `remove_build` first (checked earlier in `_process`), so the X-axis rotation is effectively unreachable via keyboard right now. **F3** toggles the build overlay in build mode (see below). **F5–F9** are dev-only time/debug keys handled by `ocean.gd` (`dev_time_keys` export — F3 is left to the build overlay).

### 3.2 Farming Quick Guide

Planters are build pieces — **PlanterPot** (potato), **PlanterBox** (bigger pot), **TreePot** (coconut / banana trees).

| Step | Desktop | Mobile |
|---|---|---|
| 1. Enter build mode | `B` | ✕/hammer button (left-center, turns ✕ while on) |
| 2. Pick the planter | `Tab` until PlanterPot/Box/TreePot | `NEXT` (bottom-right, cycles pieces) |
| 3. Place it on a deck | `P` (green ghost = ok) | `PLACE` (big ✓, bottom-right) |
| 4. Exit build mode | `B` | tap the ✕ button again |
| 5. Equip a seed | number row / hotbar click (seed must be in hand) | tap the seed in the hotbar (auto-granted: Potato/Coconut/Banana Seed) |
| 6. Plant it | aim at the empty planter + `E` | aim + tap `USE`/hand |
| 7. Wait | plant grows SEED→SPROUT→GROWING→MATURE on its own timer | same |
| 8. Harvest | aim + `E` (tap) picks one ripe fruit · aim + hold `E` digs potato / chops tree | aim + tap/hold `USE` |
| 9. After a tree falls | stump remains; aim + hold `E` to remove it and replant | aim + hold `USE` |

- Trees need several chop hits (`chop_hits_required` in `plant_data.gd`); each hit kicks the trunk, then the tree falls **away from you**, drops its `fell_drops` (Wood + Coconut/Banana) and leaves a stump.
- Only the **ripe fruit you are aiming at** is picked — the other slots keep growing and regrow on their own timers.
- Everything is data-driven in `plant_data.gd` (stage durations, regrow times, chop health, drops) — no per-plant code.

---

## 4. Autoloads

| Name | Script | Purpose |
|---|---|---|
| `Inventory` | `inventory.gd` | Item tracker + crafting |
| `Stats` | `stats.gd` | Survival stats (health/hunger/thirst) — **drain disabled** (`enabled=false`) until food/water sources exist |
| `PlantDB` | `plant_data.gd` | Plant registry (potato / coconut / banana defs: stage timers, fruit timers, chop health, drops) |

```gdscript
Inventory.add("Wood", 5)
Inventory.can_afford("Foundation")  # -> true/false
Inventory.craft("Foundation")       # -> true/false
Inventory.infinite = true           # debug: crafting never consumes
```

> `stats.gd` is registered as an autoload (`Stats`) and read by the mobile HUD's status circles. Its drain is gated behind `Stats.enabled` (see [§21](#21-survival-stats-statsgd)).

### Recipes

| Recipe | Cost |
|---|---|
| Foundation | 5 Wood |
| Wall | 8 Wood + 1 Rope |
| Roof | 8 Wood + 1 Rope |
| Stairs | 6 Wood + 1 Rope |
| Door | 4 Wood + 1 Rope |
| Window | 3 Wood + 1 Plastic |
| Bonfire *(recipe only — not buildable yet)* | 8 Wood + 2 Rope |
| Raft Extension *(recipe only — not buildable yet)* | 10 Wood + 2 Plastic |

Only the first six recipes are wired into `BUILD_RECIPE_NAMES` / `BUILD_SCENES` in `player.gd`. Bonfire and Raft Extension recipes exist in `inventory.gd` but no build scene is registered for them yet.

---

## 5. Main Scene Tree

**Boot flow:** `main_menu.tscn` (`main_menu.gd`) is the run scene — a
custom-drawn survival start screen (dusk sky, low sun, animated ocean waves,
a wooden title plaque, and wood-plank action buttons, all primitives, no
external art). It shows **New Game** only when no save exists. When
`user://raft_save.json` exists it also shows **Continue** (autosave); when
`user://raft_quicksave.json` exists it shows **QUICK SAVE** as a second resume
option — each labeled with the saved in-game day/time ("DAY 2 · 15:30").
Continue/Quick Save load that slot and jump straight into `main.tscn`; New
Game deletes BOTH save files and starts fresh.

**Menu input & scene entry (mobile-hardened).** The planks are custom-drawn,
so the script owns its own hit-testing. Buttons fire on **press-down** (never
on release): a phone reports `touch → drag → drag → release` and the release
position rarely matches the press position exactly, so press/release matching
used to drop taps — a second thumb on the screen, or a quick double tap whose
first release arrived after the second press, cancelled the pending button and
the menu looked completely dead. Touches are now tracked **per finger**
(`InputEventScreenTouch.index`), screen positions are converted from viewport
space into the Control's local space before the hit test, and the button rects
are rebuilt on demand (`_ensure_layout()`, `NOTIFICATION_RESIZED`) instead of
only inside `_draw()`. `main.tscn` is heavy (multi-megabyte island GLBs plus
the sky shaders), so it is **pre-loaded on a background thread** from
`_ready()` (`ResourceLoader.load_threaded_request`) and swapped in with
`change_scene_to_packed()`; the tapped plank shows `LOADING…` with a progress
bar meanwhile, a 20 s watchdog falls back to a blocking load, and any failure
draws a red on-screen banner (`COULD NOT START GAME · err N`) and re-enables
the buttons instead of failing silently. The chosen save slot is only applied
once the scene is known to be openable, so a failed transition can never wipe
a save. See `BUILD_ANDROID.md` for re-exporting the APK (the committed
`build/OceanSurvival.apk` is a stale pre-menu build).

From `main.tscn` (raft at (0, 0.235, -3), player at (0, 1.2, -3)):

```
Main (Node3D)
├── DirectionalLight3D            (shadow_enabled)
├── WorldEnvironment              (ProceduralSkyMaterial)
├── Ocean (MeshInstance3D) [ocean.gd]
│   └── PlaneMesh 500x500, 160x160 subdiv, ShaderMaterial (main.gdshader)
├── Raft (AnimatableBody3D) [raft.gd]  — instance of raft.tscn
│   ├── CollisionShape3D (Box 2x0.3x2)
│   ├── MeshInstance3D (BoxMesh, brown)
│   ├── F1-F4 (Marker3D corners at ±0.9/±0.9)
│   ├── BuildSockets/ (8 sockets: 4 cardinal + 4 corner)
│   └── BuiltPieces/ (runtime container for all placed structures)
├── Player (CharacterBody3D) [player.gd]
│   ├── CollisionShape3D (CapsuleShape3D)
│   ├── Body (Node3D) — low-poly humanoid, visible first-person body:
│   │     LegL/LegR (pants) · Torso/ArmL/ArmR (shirt) · Head (skin)
│   ├── CamPivot → SpringArm3D (length 0) → Camera3D (offset y=0.6, current)
│   │     └── HandPivot (rope-anchor viewmodel, local (0.18, -0.3, -0.55), inside the
│   │           camera frustum so the fist is visible) → Arm + Fist
│   ├── RopeSystem (Node3D) [rope_system.gd]
│   └── CanvasLayer
│       ├── Crosshair (Control) [crosshair.gd]
│       ├── MobileControls (Control) [mobile_controls.gd] — touch UI (hidden on
│       │     pure-desktop machines; see §3.1): icon action buttons + drawn joystick
│       ├── SurvivalHUD (Control) [survival_hud.gd] — day/night clock +
│       │     status circles (top-right), resource pills, build chip,
│       │     mode-aware hotbar (inventory items ↔ build pieces) + 30-slot
│       │     BAG panel with drag-and-drop (mobile only)
│       └── InventoryHUD (Label, created at runtime by player._create_hud;
│             hidden while the mobile UI is active)
└── DebrisSpawner (Node3D) [debris_spawner.gd]
	└── (runtime instances of debris.tscn)
```

Runtime-created nodes: `BuildPreviewRoot` (ghost preview parent), `BuildDebugMarkers` (debug spheres, only when `debug_building`), `BuildOverlayMarkers` (footprint-sample spheres, only while the F3 build overlay is on).

---

## 6. Player System

**File:** `player.gd` (~2980 lines) · **Node:** CharacterBody3D

### Movement Constants

```gdscript
WALK_SPEED = 3.0, SPRINT_SPEED = 5.0
SWIM_SPEED = 2.0, SWIM_SPRINT_SPEED = 3.5
JUMP_VELOCITY = 10.0, WATER_JUMP_VELOCITY = 12.0
DIVE_VELOCITY = -6.0, GRAVITY = 9.8
MOUSE_SENSITIVITY = 0.003
MAX_STEP_HEIGHT = 0.55, STEP_PROBE_FORWARD = 0.35
STEP_RISE_PER_FRAME = 0.05   # max riser lift per physics frame — smooth climb
```

**Auto-step** (`_try_step_up`, land only): while walking into an obstacle, probe
the body motion lifted up to `MAX_STEP_HEIGHT` and hop onto it — stair risers
and curbs are climbed by simply walking (mobile friendly); 2.5 m walls stay
blocked because they exceed every probe height. Riser lifts are spread over
several frames (`STEP_RISE_PER_FRAME`) so the body/camera never pops — the
stairs/roof walk feel smooth, and roofs read as one solid plain (all placed
pieces are `StaticBody3D` under the bobbing raft, sync error 0.0 mm).


### Swimming Constants

```gdscript
SWIM_UP_CONTINUOUS = 5.0      # hold Space while swimming
SWIM_DOWN_SPEED = 3.0         # hold C while swimming
SWIM_ACCELERATION = 12.0, SWIM_DECELERATION = 6.0
FLOAT_FORCE = 8.0, FLOAT_DAMPING = 0.95
WATER_ENTER_OFFSET = 0.3      # start swimming when head drops below water+0.3
WATER_EXIT_OFFSET = 1.5       # stop swimming above water+1.5 and not on floor
MAX_SWIM_DEPTH = 30.0
```

### Aim & Pickup

```gdscript
AIM_DISTANCE = 60.0, PICKUP_RANGE = 5.0, NEARBY_PICKUP_RANGE = 2.0
```

### Build Constants

```gdscript
BUILD_RECIPE_NAMES = ["Foundation", "Wall", "Roof", "Stairs", "Door", "Window"]
BUILD_SCENES = [foundation.tscn, wall.tscn, roof.tscn, stairs.tscn, door.tscn, window.tscn]
SOCKET_SNAP_RADIUS = 2.5
WALL_SURFACE_SNAP_RANGE = 4.0    # wall ghost snaps to a surface within this 2D distance
WALL_STACK_AIM_TOLERANCE = 0.6   # aiming this close to a wall's top stacks a 2nd floor wall
BUILD_ROTATION_STEP = PI/2        # R/Y rotate 90°
BUILD_ROTATION_FINE_STEP = PI/12  # hold Shift for 15° fine steps (e.g. angling a center wall)

FOUNDATION_WIDTH = 2.0, FOUNDATION_DEPTH = 2.0, FOUNDATION_THICKNESS = 0.30
FOUNDATION_HALF_WIDTH = 1.0, FOUNDATION_HALF_DEPTH = 1.0, FOUNDATION_HALF_HEIGHT = 0.15
```

### State Variables

```gdscript
var build_mode: bool = false
var ghost: Node3D = null
var build_rotation: float = 0.0      # 90° steps around Y (15° with Shift)
var build_rotation_x: float = 0.0    # X-axis rotation (edit mode)
var build_valid: bool = false
var _ghost_valid_mat / _ghost_invalid_mat  # green/red, alpha 0.85, unshaded, no_depth_test
```

### Grid & Occupancy

```gdscript
var _grid_occupancy: Dictionary = {}  # raft-relative Vector2i -> Node3D (Foundations + Raft only)
var _raft_node: Node3D = null
```

The raft registers itself at cell (0,0) as the structural anchor, and `_is_cell_structurally_supported()` treats the raft's own cell and its four cardinal neighbors as directly supported — located from the scene node, not `_grid_occupancy`. **The raft's own cell (0,0) is blocked for Foundation placement** (`_grid_is_blocked()` returns true for it): the raft IS the deck surface there, and a Foundation on that cell would be buried inside the raft box (identical 2x0.3x2 volume → z-fighting, raft color bleed, permanently blocked deck). So aiming at the raft deck snaps the FIRST Foundation to a **neighbor cell at the same level** — its top is exactly the raft deck height, flush edge-to-edge — and then expands around it. This keeps every deck piece level, so walls/roofs placed on any of them sit at the same height (no uneven floors).

### Edit System State

```gdscript
var _editing: Node3D = null
var _edit_original_transform / _edit_candidate_transform: Transform3D
var _edit_original_cell / _edit_candidate_cell: Vector2i
var _edit_valid: bool = false
var _last_click_time: float = 0.0, _last_clicked_piece: Node3D = null
const DOUBLE_CLICK_TIME: float = 0.30
```

### Hysteresis

```gdscript
var _roof_last_support: Node3D = null   # remembers last Wall used for a Roof
```

---

## 7. Camera & Crosshair

Camera chain: `CamPivot -> SpringArm3D(length=0) -> Camera3D(offset 0, 0.72, 0)`.

The player is a **human-sized** capsule (total 1.8m: `CapsuleShape3D radius 0.3 + height 1.2`, centred on the body origin). Standing, the capsule centre sits 0.9m above the deck so the eye is ~1.6m up — the player walks freely under 2.5m wall tops / roofs and through doorways (the old 3.0m capsule scraped ceilings and felt oversized). The visual body model is scaled 1.1x and shifted so its feet rest on the ground.

`crosshair.gd` draws a hollow circle centered on screen (with configurable `aim_vertical_offset`). It never intercepts mouse input (`MOUSE_FILTER_IGNORE`).

| Crosshair State | Color | When |
|---|---|---|
| NONE | White | Default |
| ITEM | Green | Aiming at debris (<=5m) or a toggleable object (door) |
| BUILD | Blue | Build mode / edit mode |

---

## 8. Ocean System

Two independent wave implementations must agree:

1. **Visual** — `main.gdshader` displaces the PlaneMesh vertices (uniforms `wave_height = 0.38`, `wave_speed = 0.45`) and shades the water **time-of-day aware** (see Day/Night below).
2. **Physics** — `ocean.gd` `get_height(world_pos)` returns the exact water Y at any point (used by raft, debris, player swimming, rope):

```gdscript
# Wave-field constants. MUST stay identical to main.gdshader's vertex wave
# formula (same dirs/freqs/amps/speeds) so buoyancy matches the visible waves.
const _WAVES := [
	[Vector2(1.0, 0.15), 0.055, 1.0, 0.45],   # long rolling swell
	[Vector2(-0.4, 0.92), 0.115, 0.75, 0.7],  # crossing swell
	[Vector2(0.8, -0.5), 0.24, 0.38, 1.05],   # gentle chop
	[Vector2(-0.75, -0.65), 0.50, 0.13, 1.45], # tiny fine chop
]  # [dir, freq, amp, time_speed]

func get_height(world_pos: Vector3) -> float:
	var h := 0.0
	var tt := _time * wave_speed
	for w in _WAVES:
		var d: Vector2 = w[0]
		var f: float = w[1]
		var a: float = w[2]
		var s: float = w[3]
		h += a * sin((world_pos.x * d.x + world_pos.z * d.y) * f + tt * s)
	return global_position.y + h * wave_height * 0.33
```

`wave_height = 0.38`, `wave_speed = 0.45` (exports). The four layers travel in **different directions** (two long swells → tiny fine chop) so the surface reads as smooth, slowly-breathing open-ocean motion instead of jittery chop; max wave amplitude ~0.35 m. The meander/envelope frequencies are halved vs. the old tuning, so crests bend over huge distances and wave sets arrive evenly (smooth sea, calm buoyancy). The node registers in the `"ocean"` group so any runtime-instanced node (debris, etc.) can find it across scene boundaries.

> Visual and physics waves share the same amplitude: `ocean.gd` pushes `wave_height`/`wave_speed` into the material every frame from its exports, so the raft floats on the same waves it sees (no shaking against mismatched wave heights).

### 8.1 Day / Night Lighting (Sky3D addon + time-aware ocean)

Lighting uses the bundled **Sky3D** addon (`Sky3D` WorldEnvironment with `SunLight` / `MoonLight` / `SkyDome` / `TimeOfDay` children) — nothing is duplicated or hand-rolled in opposition to it. Time is driven by `TimeOfDay` (15 real minutes per game day, `update_interval` 0.016s). The scene is configured for the game in `main.tscn`:

- `current_time = 9.5` on both `Sky3D` and `TimeOfDay` — a fresh game opens at **09:30 in full daylight** (the sun is ~36° up at the default 16° latitude), so the ocean, the island and the survivor are all in colour the moment the scene loads instead of a 00:28 deep-night start that hid every albedo. The 15-minute day cycle still runs from there, and `player.gd` restores the saved `game_time` when a save exists.
- `TimeOfDay.celestials_calculations = SIMPLE` — the sun sweeps a full day path and the **moon is opposite the sun**, so the moon reliably rises at sunset and stays up through the night (REALISTIC orbital mode kept the moon below the horizon for the game's default date/latitude — that's why it was never visible).
- `SkyDome`: `sun_light_energy 1.6`, warm horizon sun color for sunrise/sunset, `moon_light_energy 2.4` (cool blue), `moon_size 0.11`, `atm_night_tint` brightened to a soft deep blue, `atm_moon_mie_intensity 2.0`, `fog_density 0.00045` (very light atmospheric haze only), dark `ground_color`. A constant low **`FillLight`** directional (0.42 energy, no shadows) keeps the raft/buildings readable at dusk/night, and the Environment has `ambient_light_energy 1.3` + `reflected_light_energy 1.2`. The sky shader draws a **brighter, larger moon with a soft halo** (`moon_intensity`/`moon_glow_intensity` uniforms) and keeps a **minimum deep-blue night glow** (`night_lift` in `SkyMaterial.gdshader`) so dusk/night skies never read as pure black — evening through night was verified ~2–3× brighter in captured frames.
- The addon already fades everything smoothly from the sun/moon altitude (sun color lerp midday→horizon, energy by visible-disk factor, night ambient clamped to value ≥ 0.35 so unlit surfaces never go pure black, no hard day/night switch).

**Time-aware ocean** (`main.gdshader` + `ocean.gd`):

- `ocean.gd` runs every frame as the driver: it reads the SkyDome's live sun/moon transforms (**read from the `SkyDome` child node** — the old `Sky3D.get("sky")` property was unbound in this scene, so `_sky` was silently null and the water froze at day colors forever; time factors never updated) and pushes smooth factors into the shader (`night_factor`, `twilight_factor`, `moon_factor`) plus the sun/moon colors and directions.
- All shading math is done in **world space**: the vertex shader emits a **world-space wave normal** (analytic slope of the same wave field, passed as a varying — no per-fragment matrix cost) and the view vector is built from world positions, so fresnel, wave-face lighting and glitter track the real sun/moon directions no matter how the camera pitches.
- Shader output (`render_mode unshaded`, manually lit): a **vivid realistic blue** — bright azure at the horizon, rich cobalt mid sea, deep navy in the foreground/troughs, saturated blue-cyan lit crest faces, sparse whitecaps. Roughly (through the real ACES+sRGB pipeline): near-horizon sea ≈ `#0E6FB4` azure, mid water ≈ `#075A96` cobalt, steep foreground ≈ `#052B4C` near-black navy. **Never black or pale**, day or night: the near/steep view darkens into the deep water column, far water brightens to azure aerial light, and a lifted floor keeps nights navy. Night stays alive: moonlit crest faces keep the blue body (deep sea blue, never gray), the moon path shimmers along the swell lines as long broken streaks, whitecaps read as blue-white moonlit foam, and the whole water body dims only gently (×0.80 at full night). Dawn/dusk wraps lit crest faces in the warm horizon glow, so morning water glows without ever turning orange.
- **Layered detail**: 4 directional vertex waves + fragment-scale **micro ripples** (3 incommensurate directional lobes, analytic, distance-faded) that shade the near field as irregular moving chop; **wave-band shading** (lit crest faces toward the sun, darker troughs); **noise-free highlights**: sun glitter and whitecaps are broken into **elongated streaks** by a shared directional chop wave (product of two moving waves) so they follow the wave direction and never form round dots, blobs or a grid; whitecaps are sparse and gated on genuinely steep micro-crest facets near the camera (nothing beyond ~55 m, so the horizon stays clean cobalt); glitter hugs crest bands and fades out by ~150 m so the far field never dot-patterns; moon shimmer uses the same broken-streak breakup; night dims the whole water body (moon glitter is added after, so it still reads).
- **Palette is ACES-aware and LINEAR**: `ALBEDO` is linear HDR and the scene uses ACES tonemapping (mode 3, white 6.0). The ocean uniforms are deliberately **NOT `source_color`** — that hint makes `set_shader_parameter()` convert pushed colors sRGB→linear and silently darkens the water ~3×. Values were calibrated by rendering grey ramps and patches through the real pipeline and inverting the measured transfer curve onto the target displayed colors. Palette tunable on the Ocean node: `day_color`, `twilight_color`, `night_color`, `deep_color`, `horizon_color`, `crest_color`, `foam_color`, `haze_color`, `sparkle_strength`.
- **Underwater veil**: when the active camera dips below the wave surface a 2D gradient veil (`_OceanUnderwaterVeil` CanvasLayer, top lighter / bottom darker) fades in smoothly — denser with depth — giving a blue underwater tint + reduced visibility without touching gameplay rendering. Tunable: `under_alpha_max`, `under_top_color`, `under_bottom_color`.
- **Ocean underside**: the water shader uses `cull_disabled`, so the surface renders from below too. A `!FRONT_FACING` branch shades the underside as a dim water ceiling (deep/day/night mix with a soft sun/moon glow filtering through and grazing-angle darkening) — swimming under the surface shows water above you instead of see-through sky.

---

## 9. Raft System

- `AnimatableBody3D` floating on the ocean, in the `"build_surface"` group, registered at grid cell `(0, 0)`.
- **Foam ring** (`WaterFoam` child + `raft_foam.gd` / `raft_foam.gdshader`): a tiny procedural mesh (vertical skirt around the hull perimeter + thin top collar, unshaded + transparent) that churns subtle white foam where the ocean wave field laps the hull bottom. The shader re-evaluates the same 4-layer wave field, so foam appears exactly when water rises against the hull and fades as it drops (no mid-air foam); animated noise streams along the perimeter so the foam looks like water flowing around the raft. Follows the raft's bobbing (contact line = raft Y), dims at night, and copies `night_factor`/`twilight_factor`/`wave_*` from the ocean material every frame.
- **Buoyancy:** samples its 4 corner markers (F1–F4) **plus registered sample points** from placed pieces, averages the wave heights, then lerps to `target_y = avg + float_height`:

```gdscript
global_position.y = lerpf(global_position.y, target_y, 1.0 - exp(-follow_speed * delta))
```

  `float_height = 0.6`, `follow_speed = 4.0`. Rotation is zeroed in `_ready()` — the raft never tilts with waves.
- **Growing structure support:** `player._try_build()` calls `raft.register_sample_point(SampleMarker-or-F1)` after placing a piece so buoyancy averaging expands to cover the structure; `unregister_sample_point()` exists for removals. Invalid refs are pruned lazily each physics tick.
- `BuiltPieces/` container holds **all** placed structures — always parented directly to the raft (never to a foundation), so local transforms stay raft-relative.

---

## 10. Debris System

`debris.gd` (RigidBody3D, class `Debris`). Collision: **layer 2**, mask 1 (hits structures, not other debris). `gravity_scale = 0` (buoyancy fully controls vertical motion), `linear_damp = 2.5`, `angular_damp = 3.0`.

### Item Profiles

| Item | Mass | Freeboard | Color |
|---|---|---|---|
| Wood | 2.0 | 0.20 | Warm brown |
| Rope | 1.0 | 0.05 | Dark tan |
| Plastic | 0.6 | 0.25 | Light blue |
| Barrel | 6.0 | 0.30 | Dark brown |
| Stone | 4.0 | 0.10 | Gray |
| Metal | 5.0 | 0.15 | Silver |

Profile applied in `_ready()` (mass, freeboard, per-item mesh color + soft emission).

### Per-Frame Physics

```gdscript
# Vertical buoyancy — rest at water surface, follow waves gently
rest_y = water_y + freeboard
linear_velocity.y += (buoyancy * (rest_y - y) - BUOY_DAMPING * linear_velocity.y) * delta
linear_velocity.y = clamp(..., -max_vertical_speed, max_vertical_speed)

# Horizontal current — one dominant direction + small per-item drift
target = dir * current_speed * variation + side * side_drift
linear_velocity.x/z = lerpf(..., 1.0 - exp(-3.0 * delta))

# Gentle tumble
angular_velocity = (sin(t*0.5)*0.2, rot_speed, cos(t*0.4)*0.2)
```

- Skips all physics while `freeze` (hooked), `is_hooked`, or `collected`.
- **Fade in** on spawn and **fade out** before despawn (1.5s alpha tween on the material).

### Spawner (`debris_spawner.gd`)

| Parameter | Value |
|---|---|
| spawn_width | 60m |
| upstream_distance | 80m |
| downstream_distance | 120m |
| max_debris | 80 |
| prewarm_count | 35 |
| spawn interval | 0.2–0.5s |
| current_speed | 1.2 (per-item × 0.7–1.3) |

- `ITEM_POOL` weights: Wood×6, Rope×3, Plastic×2, Stone×2, Barrel×1, Metal×1.
- Prewarms upstream so debris is visible from frame 1. New debris always spawns upstream; despawns (with fade) after travelling `downstream_distance` along the current.

---

## 11. Rope / Hook System

**File:** `rope_system.gd` (~620 lines) · Node under Player. Fully blocks during build/edit mode (`_force_cancel`). Fully **automatic** after the throw: no manual reel/return keys are needed (they still work as shortcuts).

### State Machine

```
IDLE -> THROWING -> EXTENDED --(auto after ~0.8s, nothing caught)--> RETURNING
			   \-> HOOKED --(creep 3m scooping neighbors, then auto)--> REELING
REELING -> (collect all at hand) -> RETURNING -> IDLE
Cancel (right-click) from THROWING/EXTENDED/HOOKED/REELING -> RETURNING (releases any catch)
```

### Parameters

| Parameter | Value |
|---|---|
| max_hook_distance | 22m |
| throw_speed | 22 m/s |
| reel_speed | 14 m/s (loaded) / 30 m/s (empty) |
| return_speed | 30 m/s (always fast — empty returns snap back) |
| charge_speed | 30 m/s |
| debris_hook_radius | 1.8m |
| collection_radius | 1.5m |
| empty_wait_time | 0.8s |
| hook_pause_time | 0.25s (settle after creep) |
| hook_creep_distance / speed | 3m / 6 m/s |

### Flow

1. **Charge:** hold Q — a charge bar fills from 5m to `max_hook_distance`. Release Q to throw.
2. **Throw:** aim point from a dedicated RayCast3D (mask 3, 22m, player excluded). If the ray misses everything the aim point falls back to where the ray **crosses the ocean surface** — the hook always lands on the water where debris float, never sails 22 m at eye height over them (this was the “catch gap”). Direction is **locked once** at throw. `_throw_dist = min(charge_distance, aim_dist, max_hook_distance)`.
3. **Flight:** the hook is swept in ≤0.5 m sub-steps along the locked direction at 22 m/s (no debris can be skipped between frames), checking debris within 1.8m at every step.
4. **HOOKED (multi-catch):** caught pieces are frozen (`freeze_mode = STATIC`, `is_hooked = true`). After the first catch the hook **keeps creeping forward up to 3 m** (6 m/s) along the throw so debris sitting right next to the caught piece get scooped too — **one throw can haul a whole cluster**. Every frame checks for new debris (pieces already held never block new ones). Captured pieces **trail BEHIND the hook on the water surface** (0.7 m spacing, each riding `ocean.get_height + freeboard` — like a net towed behind a boat, never strung up in the air along the rope). After the creep + 0.25 s settle the hook **auto-reels** (Q/F just skip the pause).
5. **REEL:** hook leads, the trail follows; each piece is collected **individually as it reaches the raft edge** (within 1.5m of the hand → `Inventory.add(item_name)`, piece freed); if the hook reaches the hand first, remaining pieces are pulled in by hand. When the trail is empty the hook returns.
6. **EXTENDED (empty):** the hook rests on the water riding the waves, still hunting — any debris that drifts into range gets hooked. After `empty_wait_time` (0.8 s) with no catch it **returns by itself at 30 m/s** (no key press needed).
7. **Cancel:** right-click from any active state instantly recalls the rope — it **releases every hooked debris** (unfreezes them, `is_hooked = false`) and returns fast.

Visuals: gold sphere hook, tan `CylinderMesh` rope (radius 0.025) oriented `Basis(right, rope_dir, perp)` from hand to hook, and a screen-space charge bar. The rope origin is anchored to the **hand** viewmodel: `camera.pos − up·0.30 + right·0.18 − forward·0.55` (forward 0.55 m keeps the fist INSIDE the camera frustum on desktop and portrait mobile — verified on screen), so the rope visibly comes from the player's hand below-right of the view, **not from the head**.

---

## 12. Inventory System

`inventory.gd` — autoload `Inventory`. Items: `Wood, Rope, Plastic, Barrel, Stone, Metal`.

The authoritative store is **one array of 30 slots** (`Inventory.slots`); slots `0..5` are the hotbar and `6..29` the bag. Stacks cap at 99. `items` stays in sync as a totals dict for legacy readers (crafting, debug HUD, pills).

```gdscript
Inventory.add(item, amount)      # top-up partial stacks -> new bag stacks -> free hotbar
								 # returns the amount that could NOT be stored (emits bag_full)
Inventory.has(item, amount) / remove(item, amount)
Inventory.can_afford(recipe) / craft(recipe)   # infinite => always true, never consumes
# slot API (UI + drag/drop)
Inventory.slot_item(i) / slot_count(i) / slot_empty(i)
Inventory.place_at(i, item, count)             # e.g. fresh game: place_at(0, "Rope", 1)
Inventory.drop_into(from, to)                  # move / merge / swap, never duplicates or deletes
Inventory.swap_slots(a, b)
Inventory.changed / bag_full(amount)           # signals for the HUD + "BAG FULL" toast
```

A fresh game seeds `Rope × 1` into hotbar slot 0 (`player._ready` when the inventory is empty); the demo keeps `Inventory.infinite = true` so crafting never consumes the displayed (real) pickups. See [§4](#4-autoloads) for the recipe table.

**Selected slot = held item:** tapping a hotbar slot (or the 1-6 keys) sets
`player.active_slot_index` / `player.active_item`; `_update_hand_item()` spawns
a small procedural mesh (rope coil, wood log, plastic bottle, metal bar, stone,
barrel) in `HandPivot/Fist` under the camera, so the selection shows in the
player's hand, not just the UI highlight.

**Save / load — two slots:** `Inventory.save_game(meta, slot)` writes all 30
slots, the six hotbar assignments, selected slot, and player state to
`user://raft_save.json` for `"main"` (autosave: debounced 1 s after a change,
plus on quit/background) or `user://raft_quicksave.json` for `"quick"`
(manual snapshot — F5 on desktop, the **QUICK SAVE** chip in the bag-panel
header on mobile). `load_game(slot)` / `save_info(slot)` (menu labels) restore
the exact same data from either slot, and New Game wipes both files — Rope is
seeded into slot 1 only for a real new game, never overwriting a customized
hotbar on Continue.

**Built structures are saved too — fully offline:** `player._write_save()`
serializes every piece under the raft's `BuiltPieces/` (`player._serialize_built_pieces()`:
type + 12-float raft-local Transform3D) into the same `meta["built"]` payload,
and Continue rebuilds them (`player._restore_built_pieces()`, deferred in
`_ready`) with collisions re-enabled, foundations re-registered in the
occupancy grid, buoyancy samples re-added, and sockets re-linked. This is what
makes Continue return your actual raft/buildings — previously only the
inventory survived a restart. A build/remove/edit/quick-save all call
`_queue_save()` (even though `infinite = true` makes `craft()` skip the
`changed` signal, so the debounced autosave is triggered explicitly after a
build).

---

## 13. Door System

The Door is now a **wall-sized piece** (2×2.5×0.2 — same collision box as Wall) with a **static frame and a hinged leaf**. It shares the Wall placement solver (see §15), so it joins neighboring walls flush — collision touch = join, overlapping another wall = red `OVERLAPPING WALL` — and never embeds into a wall.

`door.gd` on `StaticBody3D`:

```gdscript
func toggle() -> void:  # called via "toggle" in collider check on E
	is_open = !is_open
	_target_rotation = deg_to_rad(open_angle) if is_open else 0.0
	_swinging = true
# _physics_process: only the LEAF swings (LeafPivot.rotation.y), like a real
#   door — the frame stays fixed. The leaf's own StaticBody3D (LeafBody, a
#   direct child of LeafPivot) rotates with it, so its collider swings out of
#   the doorway: closed = blocked, open = walk-through.
```

- `open_angle = 90°`, `swing_speed = 4.0`.
- Colliders (root body): `ColFrameLeft`/`ColFrameRight` (0.3×2.15×0.2 posts) + `ColFrameTop` (2.0×0.35×0.2 lintel) — the 1.4×2.15 m doorway stays open between them. The old single full-panel box is gone: it blocked the opening even when the door was open.
- Leaf collider: `LeafPivot/LeafBody` — its OWN `StaticBody3D` (Box 1.4×2.15×0.06, coincident with the leaf mesh). A CollisionShape3D tucked under a plain pivot Node3D is never registered by Godot (shapes must be direct children of a body), so the leaf is a body that rotates with the pivot. Frame + leaf bodies: `collision_layer = 1`, `collision_mask = 5` (bits 1+3).
- Interaction: `IntractZone` Area3D (1.8×2.5×1.8). The E key walks up the hit body's ancestors to find the Door's `toggle()`, since aiming at the closed leaf reports `LeafBody`.
- Node tree: `FrameLeft/Right/Top` (static frame meshes) + `LeafPivot` (hinged at x=-0.7) containing `LeafBody`, the leaf panel, handle, and 2 hinges.

---

## 14. Building Scenes

All build-piece roots are **`StaticBody3D`** (Foundation included). Pieces were previously `AnimatableBody3D`, but those fall behind the code-bobbed raft by up to ~0.43 m on the physics server (measured: server body transforms drift while node transforms follow the raft), which made roofs/stairs shake and opened phantom gaps underfoot; `StaticBody3D` pieces track the raft with **0 mm error**, so structures sit rock-solid. Every wood piece — Foundation, Wall, Door frame/leaf, Window trim, Roof (slab + seam strips), and Stairs steps/landing — uses **`wood_planks.gdshader`** with per-part `half_*`/color uniforms (board seams align to each mesh's edges; glass + handle/hinge metals keep their own materials). Every socket is a `BuildSocket` (Marker3D). `SocketType` enum: `FOUNDATION_EDGE(0), FOUNDATION_TOP(1), WALL_BASE(2), WALL_TOP(3), WALL_SIDE(4), DOOR_SLOT(5), WINDOW_SLOT(6), PILLAR_TOP(7)`. Sockets use `accepts` (explicit allow-list) for compatibility, not the enum.

### Raft (`raft.tscn`) — AnimatableBody3D, 2x0.3x2

```
BuildSockets/
  Socket_North/South/East/West        FOUNDATION_EDGE @ y=0.15, accepts [Foundation, Wall, Stairs]
  Socket_NorthEast/NorthWest/SouthEast/SouthWest  FOUNDATION_EDGE @ (±0.707, 0.15, ±0.707), accepts [Foundation]
BuiltPieces/                          (runtime container)
```

### Foundation (`foundation.tscn`) — StaticBody3D, 2x0.3x2

```
CollisionShape3D (Box 2x0.3x2) + MeshInstance3D
BuildSockets/
  Socket_North/South/East/West        FOUNDATION_EDGE @ y=0.15, accepts [Foundation, Wall, Stairs]
  Socket_Top                          FOUNDATION_TOP @ (0, 0.15, 0), accepts [Wall, Door, Window]
SampleMarker                          (buoyancy sample point, registered with raft)
```

### Wall (`wall.tscn`) — StaticBody3D, 2x2.5x0.2

```
CollisionShape3D (Box 2x2.5x0.2) + MeshInstance3D
ShaderMaterial (wood_planks.gdshader) — procedural vertical planks + grain, no texture files
BuildSockets/
  Socket_Base    (0, -1.25, 0)  WALL_BASE  accepts [Foundation, Wall, Door, Window]
  Socket_Top     (0,  1.25, 0)  WALL_TOP   accepts [Wall, Door, Window, Foundation, Roof]
  Socket_North/South/East/West  WALL_SIDE  accepts [Wall, Door, Window]
SampleMarker
```

> **Door/Window sockets** mirror the Wall layout exactly (same positions and
> accepts lists) so all three tile interchangeably — side-by-side joins, second-
> floor stacking, and roof placement all work. The old `Socket_Middle`
> (accepts `[Door, Window]`) was removed: it embedded doors/windows into the
> middle of a wall, which caused the nesting/overflow the player reported.

### Door (`door.tscn`) — StaticBody3D, 2x2.5x0.2

```
ColFrameLeft/Right (0.3x2.15x0.2 posts) + ColFrameTop (2.0x0.35x0.2 lintel)  — frame only, doorway stays open
LeafPivot (hinged at x=-0.7) -> LeafBody (own StaticBody3D, Box 1.4x2.15x0.06 leaf collider) + leaf mesh + handle + hinges
BuildSockets/  Socket_Base / Socket_Top / Socket_North/South/East/West  (same as Wall)
SampleMarker
```

### Window (`window.tscn`) — StaticBody3D, 2x2.5x0.2

Wall-sized panel with a **plus-shaped opening in the center** (4 wall corner
blocks + translucent glass cross). Sockets identical to Wall so it attaches to
walls flush, stacks, and rotates with R/Y like any wall piece.

```
CollisionShape3D (Box 2x2.5x0.2)
CornerTL/TR/BL/BR (0.7x0.95x0.2 wall blocks) + GlassV/GlassH (plus-shaped glass)
BuildSockets/  Socket_Base / Socket_Top / Socket_North/South/East/West  (same as Wall)
SampleMarker
```

### Roof (`roof.tscn`) — StaticBody3D, 2x0.15x2

```
CollisionShape3D (Box 2x0.15x2) + MeshInstance3D (main top slab)
ShaderMaterial (wood_planks.gdshader) — procedural boards + grain on slab AND
  seam strips (different tint), no texture files. Base `half_*` uniforms must
  match the piece half-extents; board seams align to piece edges.
SeamNorth/South/East/West — four raised 0.03m dark wood strips (height 0.005,
  y +0.0025 above the top face) along each tile edge. Neighboring tiles share
  these bands, so large roofs read as structured planks with fine dark seams
  instead of one flat slab. Visual only: no colliders, no sockets.
BuildSockets/
  Socket_Base    (0, -0.075, 0)  WALL_TOP (type 3)  accepts [Wall, Roof]
  Socket_Top     (0,  0.075, 0)  WALL_TOP          accepts [Roof]
  Socket_North/South/East/West   FOUNDATION_EDGE   accepts [Foundation, Roof]
SampleMarker
```

### Stairs (`stairs.tscn`) — StaticBody3D, one full-height flight

```
One flight of 6 steps + landing, total climb 2.64m (wall height + roof):
  Step01..06 (Box 2x0.44x0.6) rising 0.44m per riser at z 0.3/0.8/1.3/1.8/2.3/2.8,
  tread tops 0.34 .. 2.54; Landing (Box 2x0.18x1.0) at z 3.5, top 2.64 — level
  with a wall's Socket_Top, so the player steps straight off onto the roof.
  Every step has a matching CollisionShape3D (full riser boxes).
BuildSockets/
  Socket_Base (0, -0.1, 0.6)  FOUNDATION_EDGE  accepts [Foundation, Stairs]
  Socket_Top  (0,  2.54, 2.8) FOUNDATION_EDGE  accepts [Foundation, Stairs]
  Socket_North/South/East/West                 accepts [Foundation]
SampleMarker

Climbable WITHOUT jumping: the player's auto-step (_try_step_up) lifts the body
  over each 0.44m riser (MAX_STEP_HEIGHT 0.55) while walking, and stairs STACK
  on stairs via Socket_Top for taller floors.
```

### Placeholders

`raft_extension.tscn` (StaticBody3D, plain 2x0.3x2 box, no sockets/script) and `bonfire.tscn` (Node3D root with a CollisionShape3D but no physics body) — see [§23](#23-placeholder-scenes).

---

## 15. Physics & Collision Layers

| Bit | Layer | Used By |
|---|---|---|
| 1 | Structures | Raft, foundations, walls, roofs, stairs, doors, windows |
| 2 | Debris | Floating debris (`collision_layer = 2`, `collision_mask = 1`) |

- Player aim raycast: mask 3 (structures + debris), excludes player RID.
- Rope aim RayCast3D: mask 3, player added as exception.
- All build validation rays/shape queries: **mask 1** (structures only) — debris never blocks placement.
- Door frame AND leaf (`LeafBody`) are separate `StaticBody3D` bodies — both `collision_layer = 1`, `collision_mask = 5` (bits 1+3; bit 3 currently unused).

---

## 16. Game Loop & Frame Flow

### Physics Tick (60 Hz)

`project.godot` runs physics at **60 Hz** (was 120 Hz) — physics load is halved with no visible change to movement, buoyancy, or debris drift, which matters on low-end 4 GB phones.

### Performance Notes (mobile-friendly)

- **Renderer:** `renderer/rendering_method = "mobile"` (already set) — the correct backend for phones.
- **Ocean:** the 500×500 plane is 160×160 subdivisions (≈26k verts, down from 40k) and **`cast_shadow = 0`** — the largest, permanently-visible mesh no longer renders into the directional shadow maps every frame (day *and* night, since the MoonLight enables shadows too). Zero visual change (water self-shadows were never visible).
- **Shadows:** `directional_shadow_max_distance = 150` on SunLight/MoonLight and `directional_shadow/size = 2048` — shadow cost is limited to the play area around the raft.
- **Sky3D screen-space fog is disabled** (`SkyDome.fog_visible = false`): its atmospheric-scatter shader is a full-screen raymarch pass. At the game's very low density it was imperceptible, so disabling it is visually free on low-end GPUs (the sky/environment still carry the atmosphere).
- **HUD label** is only re-assigned when its text actually changes — re-setting identical text forced a full UI text re-layout every frame.
- Wave vertex geometry and `get_height()` are unchanged; only the shading responds to time of day (see §8.1).

```
Player._physics_process:
  _update_aim()                      # camera ray, mask 3, 60m
  -> land or swim movement
  -> move_and_slide()
  -> _update_swimming_state()        # enter/exit water, clamp velocity.y on exit

Raft._physics_process:
  Sample 4 corners + extra sample points -> average -> lerp global y

Debris._physics_process:
  Buoyancy + current + tumble + fade (skipped when frozen/hooked/collected)

RopeSystem._physics_process:
  (skips while build/edit active)
  Update hook origin -> state machine -> hook/rope visuals -> charge bar

RainSystem._process (child of Player, follows the camera):
  _follow_player() -> _update_intensity() (fade in/out) -> _process_splashes()
  _process_splashes(): splashes_per_second x intensity -> raycast down at
	camera-forward-biased sample points (mask 1 = structures) -> pooled splash
	bursts on raft/roof/surface; softer ripple on open water
```

### Rain System (`rain_system.gd`)

Random timed rain events (4–8 real minutes apart, 1.5–5 min long). **Falling rain** is a wind-oriented GPUParticles3D streak volume (aligned to velocity, so drops read as diagonal lines matching the wind; world-space particles with proximity fade so drops melt into surfaces instead of slicing through them). **Indoor cover:** every 0.15 s while raining, a vertical ray checks whether the camera is under a roof/deck (any horizontal-ish face on a `build_surface` piece); probe rays then measure the covered extent and the emitter switches from the full box around the camera to a **ring just OUTSIDE that footprint, spawned ~6 m above camera height** — drops fall onto the roof top and around the shelter and are visible at every open side, but never spawn under the roof, so rain can never appear inside a roofed room (walls/vertical faces can never count as cover). While outdoors next to a building, the box's TOP is capped just below the lowest nearby roof underside, so drops spawning above a house can never fall through its roof into the walls (visible from outside through doors/windows). **Submerged camera:** while the camera is below the wave surface (hysteresis at ±0.1 m) no rain is emitted and falling drops are cleared — rain never renders underwater. **Impact splashes** are a small pooled one-shot burst pool: every frame `splashes_per_second × intensity` raycasts drop straight down at sample points and fires a bright burst wherever a drop lands on a structure (raft/foundation/wall/roof/stairs/door/window — physics layer 1) or a softer ripple on open water. **Sample bias (`forward_bias = 0.75`) concentrates splashes inside a cone ahead of the camera** (`forward_cone_radius = 4.5 m`) — the raft/roof/deck fill the middle of the screen, so most rain visibly pounds the surfaces the player is looking at instead of scattering across empty ocean. Rain also darkens the sky/ocean, adds fog, can flash lightning + thunder, and fades in/out over `fade_time` (F11 toggles instantly in debug builds).

### Render Frame

```
Player._process:
  _update_hud()
  PRIORITY 1 — EDIT MODE (if _editing):
	P = confirm, X = remove+refund, B = cancel
	R = rotate (90°), then follow preview every frame
  E double-click detection (works in AND out of build mode)
  PRIORITY 2 — BUILD MODE:
	B = toggle, Tab = cycle piece, P = place, R = rotate
	_update_build_preview() every frame
  PRIORITY 3 — NORMAL:
	_handle_pickup() (E) + crosshair state (ITEM when aiming debris/door)
```

### Build Preview Flow

```
_update_build_preview():
  _ensure_ghost_materials()
  _resolve_placement(piece_name, aim_point)
	Foundation: structural build-plane ray -> grid cell -> candidate scoring
	Wall:       actual ray hit -> center/edge/wall-to-wall/stack -> footprint 3x3
	Roof:       Socket_Top of Wall (3 search methods)
	Door/Window/Other: best socket + reciprocal + gap check
  _apply_ghost_material(valid)        # BEFORE visibility (never flashes wrong color)
  valid  -> ghost.global_transform = solved, visible (GREEN)
  invalid-> fallback transform (per-piece), visible (RED), diag reason set
```

---

## 17. State Machines

### Build Mode

| State | Input | Next |
|---|---|---|
| NOT BUILDING | B | BUILDING (spawns ghost) |
| BUILDING | B | NOT BUILDING (frees ghost) |
| BUILDING | P (valid + affordable) | Piece placed under raft/BuiltPieces |
| BUILDING | Tab | Cycle piece (respawns ghost) |
| BUILDING | R / Y (Shift = 15°) | Rotate 90° (fine steps with Shift) |

### Edit Mode (piece pickup)

| State | Input | Next |
|---|---|---|
| IDLE | Double-click E on a piece (≤0.3s, same piece) | EDITING |
| EDITING | P (valid) | Confirmed — re-registered + sockets re-linked |
| EDITING | X | Removed — refunded (RECIPE_REFUND) + freed sockets |
| EDITING | B | Cancelled — restored to original transform |

During EDITING the piece's collision is disabled, it is unregistered from the grid, and its occupied sockets are freed; on confirm/cancel everything is re-linked.

### Rope

```
IDLE -> (hold Q, release) THROWING -> EXTENDED (Q/F = REELING, RMB = RETURNING)
								   \-> HOOKED (Q/F = REELING, RMB = release + RETURNING)
REELING -> (within 1.5m) collect -> RETURNING -> IDLE
```

---

## 18. Build Algorithm Deep Dive

All placement is computed by `_resolve_placement(piece_name, hit_point)` in `player.gd`, which fills a `_diag` dictionary (visible in the HUD when `debug_building`).

Structural support finds the raft from the **scene node** (`_get_raft_node()`), never `_grid_occupancy` — placing the first Foundation on the raft overwrites the raft's grid entry, so grid-based raft lookups would make every later build fail with `NO STRUCTURAL SUPPORT`.

### Build Overlay (F3)

While in build mode, **F3** toggles an on-screen overlay that visualizes the placement footprint validation:

- A **grid of flat cells** rendered in 3D at each footprint sample position, with a floating **% label** per cell — the percentage is how much of that cell's column is supported by the build surface directly below. Every piece type samples its footprint: walls and foundations use their 3×3 bottom grid, roofs sample their bottom plane too (`_validate_roof_footprint`).
- **Cell color follows the placement verdict**, so the overlay never contradicts the build system: **green** wherever P would build (even if the surface coverage is 0%, e.g. a Foundation expanding over water on grid support), **red** wherever the placement is invalid (overlapping wall, no support, etc.). The % label still shows the honest surface coverage under each cell.
- The grid **follows the ghost preview**, and on invalid resolves it recenters onto the ghost's visible position.
- A **HUD block** with either `Coverage: NN% (N cells, 100% = fully on surface)` (valid placements) or `Samples: X/Y supported (NN%) [placement REASON]` (collision-invalid), plus the center-ray result, bottom vs. surface height, the resolved edge/socket, and the surface piece. This works independently of `debug_building`.
- Markers are cleared when the overlay is toggled off or build mode is exited. The ghost's collision is excluded from the support rays, so the markers always show the real surface beneath the preview.

### Aim Resolution

- **Foundation:** ray is intersected with the structural build plane (`deck_y = raft_flat.y + 0.15`); if the ray misses or hits a non-build object, a plane fallback resolves the exact aim cell (looks up the Foundation under the crosshair among 9 neighboring cells).
- **Wall:** uses the *actual* ray hit — the crosshair itself picks the edge.
- **Roof / Door / Window:** ray hit determines the support.

### Foundation — Grid Cell

```
Candidate cells: aim cell, aim-side cell, support's cardinal+diagonal neighbors,
				 and neighbors of ALL occupied cells (gap filling).
Scoring: -dist, +100 if exact aim cell, +5 aimed direction, +2 per supporting neighbor, -3 diagonal-only
Reject: occupied, structurally unsupported (BFS to raft), >6m from aim
Transform: _compute_foundation_transform(cell)  # THE single authoritative cell->world formula
		   local = (cell.x*W, 0, cell.y*D), world = flat_raft * local, yaw = build_rotation
Validation pipeline (any failure => INVALID with reason):
  1. Size: collision box must equal 2x0.3x2 (±0.01) AND mesh AABB must match
  2. Height: foundation top (origin.y + 0.15) must equal structural deck Y (±0.01)
  3. Socket: _verify_foundation_connection — support edge socket vs reciprocal, error <= 0.1m
  4. Overlap: shape query, mask 1, excludes player/ghost/support ancestors
  5. Ghost cell must match candidate cell; rotation must be horizontal (±0.1 rad)
  6. Footprint: 4 shrunken corner cells must not overlap occupied cells (touching is valid)
```

### Wall / Door / Window — Edge Attachment

Door and Window are **wall-sized pieces** (2x2.5x0.2) that share this solver
with Wall: same sockets, same footprint validation, same overlap rejection.
They join walls flush (collision touch = join; overlap = RED `OVERLAPPING
WALL`) and can be stacked on and rotated like any wall piece.

The wall ghost follows the crosshair **everywhere**. When the aim ray misses or hits a non-build object, the crosshair is projected onto the structural deck plane (`deck_y + 1.25`) so the ghost never jumps to the raft.

```
Aim: ray hit (build surface) OR deck-plane projection of the crosshair.
Support selection: P1 ray-hit (Foundation/Raft/Wall/Door/Window)
				   P2a vertical drop at the projected aim — the build surface
					   directly UNDER the crosshair becomes the support (covers
					   grazing angles where the main ray passes over the deck edge)
				   P2 nearest surface to the projected aim, only if within
					  WALL_SURFACE_SNAP_RANGE (4m)
				   P2b WALL PREFERENCE — when the resolved surface is a deck
					   (Foundation/Raft) but a Wall/Door/Window is within snap
					   range AND not meaningfully farther than the deck (<= +0.5m),
					   snap to the WALL instead: the ghost auto-joins the wall's
					   side (foundation-style preview near walls) instead of
					   falling back to the deck edge and hanging off it.
				   P3 none -> DO NOT reject yet: fall through to the shared
					  FOOTPRINT validation below — the wall's real bottom may
					  still rest on a surface under the crosshair even when the
					  aim ray grazes past it. Genuinely unsupported spots
					  (open water, floating above) still come out INVALID.
If support is Wall/Door/Window  -> WALL-TO-WALL socket placement:
	STACKING first: aiming at the upper part of a Wall/Door/Window face
		places the new piece DIRECTLY ON TOP (Socket_Top -> Socket_Base),
		so 2nd/3rd/... floors stack recursively. Blocked if Socket_Top occupied.
	else _find_best_socket (score = alignment*10 - dist, radius 2.5m)
	-> reciprocal -> _solve_socket_transform -> overlap (skips foundation below)
If support is Foundation/Raft  -> EDGE or CENTER placement:
	CENTER: aiming in the middle zone of a deck piece (|local| <= half width / 2,
		i.e. the central 1x1m of a 2x2 tile) places the wall UPRIGHT in the deck
		CENTER (Foundation.Socket_Top / raft center) instead of snapping to an edge.
	else EDGE placement:
		_select_wall_edge: perpendicular distance to the 4 edge lines;
						   corner tie-break (within 0.25m) uses camera direction dot edge normal
		TILE-SLOT snapping (_solve_wall_edge_tile):
			walls are exactly one deck cell wide (2.0m), so each cell's edge can
			hold ONE wall, centered on that cell:
				raw_along = local_aim.dot(edge_axis) - socket_local.dot(edge_axis)
				slot k0   = round(raw_along / 2.0)   # slot under the crosshair
				center    = edge socket + edge_axis * (2.0 * k)
			try k0 first, then k0 ± 1 / ± 2 (aim direction first) until a slot
			is free AND footprint-valid — so two walls TILE FLUSH side-by-side:
			aiming at an occupied edge auto-shifts the ghost to the next free
			slot on the adjacent deck cell (±2.0m); when the whole run is full
			the ghost stays RED at the aimed slot (OVERLAPPING WALL)
			_wall_edge_slot_taken: same edge LINE only (|along| < 1.9m and
			perpendicular < 0.5m) — corner walls on perpendicular edges stay OK
			wall Socket_Base offset (0, -1.25, 0) rotated by total angle
		WALL PREFERENCE (over water only): if the resolved surface is a deck
			BUT no deck is directly under the crosshair (vertical drop hits
			water) and a Wall/Door/Window is within snap range and not >0.5m
			farther than the deck, the ghost auto-joins that wall's side
			instead. When the crosshair IS over a deck, the tile-slot deck path
			wins so walls tile onto deck cells rather than joining/stacking
			onto the wall that occupies the aimed slot.
If support is ROOF — roof TOP face (aimed from above, _is_roof_top_aim):
	A roof's top face is a SECOND-FLOOR DECK, so walls/doors/windows stand
	on it exactly like on a Foundation: center zone -> upright in the roof
	center; otherwise edge tile-slot snapping onto the roof's top edge, with
	the solved transform lifted +0.075 so the wall bottom rests flush on the
	slab's top face. A roof seen from below (or its side) is a ceiling and
	falls through to the deck-plane projection, where the footprint check
	keeps it RED.
Footprint validation (_validate_wall_footprint):
	- support rays use collision mask 1 and EXCLUDE the player RID, the preview
	  ghost RID, and the piece being edited, so the preview can never block
	  detection of the surface underneath it
	- center-point ray (1m above / 3m below, tolerance 0.3m) is the highest-
	  priority check; it can validate the wall alone
	- + 3x3 grid samples inset 40% from edges; a column counts as supported if
	  ANY of its depth samples hit (so the over-water half of an edge wall
	  doesn't invalidate it)
	- valid if center supported OR support ratio >= minimum_support_ratio (0.50)
	- INVALID reasons: NO SUPPORT SURFACE (0 columns hit) or
	  INSUFFICIENT SUPPORT: X/Y (some but < 50%)
	- the ghost follows the crosshair everywhere; a wall sitting on a
	  foundation (center, edges, corners, rotated) validates GREEN, while
	  open water / floating-above stays RED
	(stacked walls validate via the wall below; center walls via the deck)
Overlap: scan BuiltPieces for Wall/Door/Window within 0.5m horizontally
```

Rotation: R toggles build_rotation in 90° steps (180° flip for a wall = two presses). No 90° rotation around X in build mode.

### Roof — Top Attachment

```
Method 0 (ROOF-TO-ROOF): Ray hits an existing Roof -> attach to it
  Aim point in the roof's flat space decides the intent:
	center zone (|x|,|z| <= 0.45 of half-width) -> Socket_Top (stack on top)
	otherwise -> the side socket matching the aim direction (side expansion)
  -> Reciprocal socket on the new roof (Socket_Base for stacking, opposite
	 side socket for expansion)
  -> Solve: RoofRoot = TargetSocket * inverse(RoofSocketLocal)
  -> Overlap: shape query, other Roofs / non-build bodies block; walls and
	 foundations (build_surface group) are allowed contact
  No free socket on the aimed roof -> RED "ROOF SLOT OCCUPIED" (never jumps
  to a different wall)
Method 1: Ray hits Wall/Door/Window -> ITS Socket_Top (doors and windows tile
  like walls, so a roof rests on them too — no hole over a doorway)
Method 2: Walk up 5 ancestors -> Wall/Door/Window with free Socket_Top
Method 3: Search ALL BuiltPieces walls/doors/windows for nearest free
  Socket_Top (<=4m horizontal); the wall whose footprint the aim is over wins
  -> Find reciprocal: Roof.Socket_Base
  -> Solve: RoofRoot = TargetSocket * inverse(RoofSocketLocal)  [_solve_socket_transform]
  -> CELL-CENTRING (foundation behaviour): when the roof lands on a wall's
	top, shift the solved tile 1.0m (half a tile) off the wall line onto the
	deck cell the crosshair is aiming at, so the roof covers the whole room
	cell flush on its wall ring instead of straddling the aimed wall. The Y
	stays flush on the wall tops; neighbour tiles chain cell-to-cell (2.0m).
  -> Verify: centred roofs check the bottom-face height against the wall top
	(the base socket no longer coincides with the wall line); un-centred
	roof-to-roof solves keep the old <=0.1m socket check
  -> Overlap: walls/foundations below are allowed contact, but ANOTHER roof
	genuinely overlapping the same cell (centres <1.5m at the same level) or
	any non-build body makes the placement RED (doubled roofs z-fighting in
	one cell are rejected)
PLANE-FILL fallback (_resolve_roof_plane_tile): when none of the above found a
  wall top, but a roof chain exists within 6m of the crosshair, tile like a
  foundation: the nearest roof (any level) becomes the anchor, all math runs in
  the anchor's YAW-ONLY local frame (so angled chains tile along their own
  axes), and the ghost extends ONE 2x2 cell (2m) along the dominant local axis
  at the same height -> roof areas grow continuously in all 4 directions from
  a single wall-top anchor, no pixel-perfect wall-top aiming needed.
  Occupied cells are RED, never auto-skipped:
	- aim point inside an existing roof's footprint (tolerance 1.05m) at that
	  level -> "ROOF SLOT OCCUPIED" RED (same rule as foundations on a deck)
	- target cell already roofed -> RED
  Extension only fires from a FREE edge (aim past the last roof's rim).
  Physics overlap re-check (build bodies filtered) guards the final cell.
CLIMB: if the aimed wall's top is occupied by a STACKED Wall/Door/Window
  (wall-over-wall column), climb to the topmost wall and target ITS top. If it
  is occupied by a ROOF the cell is already roofed — the placement goes RED
  (roofs never stack through the roof that covers the same cell; double roofs
  are only possible by deliberately aiming at a roof's centre)
Hysteresis: _roof_last_support remembers the last Wall used (reset on piece cycle)
```

### Door / Window / Stairs — Socket-Based

```
_find_best_socket(support, piece, aim, normal):
	skip occupied / incompatible / >2.5m sockets
	score = socket_dir.dot(aim_dir) * 10 - distance
	(Stairs support: Socket_Top is used directly, no scoring)
_find_reciprocal_socket(new_piece, support_name):
	type-compat bonus +10 (FOUNDATION_EDGE<->EDGE, FOUNDATION_TOP<->WALL_BASE,
	WALL_TOP<->WALL_BASE, WALL_SIDE<->WALL_SIDE, FOUNDATION_TOP<->DOOR/WINDOW_SLOT, WALL_TOP<->WALL_TOP)
	+50 if opposite-facing (full 3D direction, so vertical sockets work)
	-100 if same-direction
	(Stairs support: reciprocal pinned to Socket_Base)
Solve: _solve_socket_transform (flat, Y-rotation only)
Verify: socket error <= 0.05m, edge gap |gap| < 0.05m (negative = penetration)
  — socket alignment is computed from the SOLVED transform (solved * socket),
	not the live ghost, because a freshly-spawned AnimatableBody3D ghost reads
	stale transforms until the physics sync
Overlap: filtered by build_surface group + anything below solved.origin.y - 1.0

Doors and windows attach to ANY wall's Socket_Middle — including stacked
  second-floor walls — so openings work on every level.
```

### Placement (confirm — `_try_build`)

```
Requires build_valid; walls skip the socket requirement.
Inventory.can_afford + Inventory.craft.
Instantiate scene -> rename to "<Piece>_<instance_id>" (unique per placement —
  Godot auto-renames duplicate children to "@ClassName@n", which breaks the
  name-based piece detection for every piece after the first of its type)
  -> parent under raft's BuiltPieces (ALWAYS the raft root, never the socket's
  parent piece — keeps local transforms raft-relative).
ALL collision shapes disabled before add, re-enabled deferred (prevents pushing
  the player; stairs have 5 stepped colliders).
Transform set BEFORE add_child (raft-local for all pieces): a physics body then
  enters the space already placed — setting global_transform right after add is
  overwritten by the physics sync for script-animated bodies (e.g. the Door's
  _physics_process), which used to snap doors back to the raft origin.
Foundation: transform from exact cell formula (uses _ghost_cell, never recomputed).
Others: ghost preview transform converted to raft-local.
Add to "build_surface" group.
Occupy target socket + link reciprocal socket (nearest socket within 0.35m).
Register Foundation cell in grid; register SampleMarker/F1 as raft buoyancy sample.
```

---

## 19. Edit System Deep Dive

**Pickup:** double-click E on the same piece within 0.3s (`_handle_double_click_edit` → `_start_edit`). The raft itself cannot be picked up.

**Start edit:**
- Saves original transform + grid cell; disables the piece's collision.
- Unregisters from grid, frees its occupied sockets and any sibling socket pointing at it.
- Applies the green ghost material; hides the build ghost while editing.

**Follow (per frame):**
- Foundation: grid-cell search around the aim cell (aim + neighbors, best score) → `_compute_foundation_transform`; overlap check excluding the piece itself.
- Non-foundation: `_find_best_socket` on the support (or raft fallback) + reciprocal-by-distance → socket solve; overlap check.
- Valid → green + move preview; invalid → red, stays put.

**Confirm (P):** re-enable collision, restore color, re-register at the new cell, re-link sockets.

**Remove (X):** unregister, free referencing sockets, refund via `RECIPE_REFUND` (same costs as recipes), free the piece.

**Cancel (B):** restore original transform + cell + sockets, restore color.

---

## 20. Rope Algorithm Deep Dive

- **Charge:** hold Q — `charge_distance` grows 5→22m at 30 m/s; a ColorRect bar shows the fraction.
- **Aim:** raycast hits (raft/debris) win; a miss falls back to the ray's **intersection with the ocean surface** so the hook lands on the water instead of flying at eye height over the debris (the old “catch gap”).
- **Throw:** direction is captured **once** and never recalculated. Hook travels in that fixed world-space direction in ≤0.5 m sub-steps; camera rotation does not bend the rope.
- **Hook:** every frame (flight, resting, creeping, reeling) checks *all* debris within 1.8m and hooks every eligible one — one throw can scoop a cluster. After the first catch the hook creeps forward up to 3 m to pick up neighbors, then auto-reels.
- **Empty:** nothing caught → hook rests up to 0.8 s (still hunting drift-ins, riding the waves) then **auto-returns at 30 m/s**.
- **Cancel:** right-click from any active state releases all catches (unfreeze, `is_hooked = false`) and returns the rope fast.
- **Trail:** captured pieces ride the water BEHIND the hook (`hook − (hook−hand).norm · (i+1)·0.7`, y = `ocean.get_height + freeboard`), velocities zeroed — a towed net, not a chain up in the air. Collected one by one as each reaches the raft edge.
- **Reel:** `hook_pos += normalize(hand - hook_pos) * speed * delta` (14 m/s loaded, 30 m/s empty); within 1.5m every captured piece is collected.
- **Visual:** CylinderMesh from hand to hook, `Basis(right, rope_dir, perp)` — Y axis along the rope. Origin anchored at the hand: `camera − up·0.30 + right·0.18 − forward·0.55` — and a visible **first-person viewmodel** (`Camera3D/HandPivot` → Arm + Fist boxes) sits at exactly that anchor inside the camera frustum, so the rope visibly starts from the hand in your view.

---

## 21. Survival Stats (stats.gd)

`extends Node` — registered as the **`Stats` autoload** and read by the mobile HUD's status circles. Drain is gated behind `@export enabled := false`, so nothing starves yet (set `enabled = true` or feed the drain rates when food/water sources exist). API:

```gdscript
signal stat_changed(stat_name: String, value: float)
signal player_died

MAX_VALUE = 100.0
enabled = false  # exports; when true drains hunger/thirst, damages at 0
hunger_drain_rate = 0.4 / s, thirst_drain_rate = 0.6 / s   # exports
health = hunger = thirst = 100.0

_process: if enabled, drain hunger/thirst, emit stat_changed; if either <= 0 -> change_health(-2.0 * delta)
change_health(amount): clamps 0..100, emits player_died at 0
eat(food_value) / drink(thirst_value, health_bonus = 0.0)
```

Consumers read `Stats.health / Stats.hunger / Stats.thirst` (floats 0..100).

---

## 22. Shared Helpers

### BuildSocket (`build_socket.gd`)

`class_name BuildSocket extends Marker3D`
- `@export socket_type: SocketType` (informational; placement uses `accepts`)
- `@export accepts: Array[String]` — empty = compatible with anything (use sparingly)
- `is_occupied: bool` / `occupying_piece: Node3D` + `occupy(piece)` / `free_socket()`
- `get_parent_raft()` — walks up to the first node in the `"build_surface"` group
- `get_parent_piece()` — walks up to the node whose `BuildSockets` child owns this socket
- `is_compatible(piece_name)` — `accepts.is_empty() or accepts.has(name)`

### BuildSystem (`build_system.gd`)

Static universal socket-attachment solver — the same math as `player._solve_socket_transform`:

```gdscript
static func solve_socket_attachment(
	target_socket: Node3D,
	new_piece_socket_local_position: Vector3,
	build_rotation_y: float,
	support_basis: Basis,
) -> Transform3D:
	# center = target_socket.global_position - local_offset.rotated(UP, rotation)
	# basis  = support_basis.rotated(UP, rotation)
```

Currently **unused by player.gd** (which has its own `_solve_socket_transform`) — kept as the canonical shared implementation to migrate toward.

---

## 23. Placeholder Scenes

| Scene | Root | State |
|---|---|---|
| `raft_extension.tscn` | StaticBody3D, Box 2x0.3x2 | No sockets, no script, no group — cannot be built yet. Recipe exists ("Raft Extension": 10 Wood + 2 Plastic). |
| `bonfire.tscn` | Node3D + CollisionShape3D (0.8x1.2x0.8) | Collision shape on a non-physics root; no script, no sockets. Recipe exists ("Bonfire": 8 Wood + 2 Rope). |

Neither is in `BUILD_RECIPE_NAMES` / `BUILD_SCENES`, so they are not placeable.

---

## 24. How to Extend

### New Building Type
1. Create `.tscn` with a `StaticBody3D` root (pieces track the code-bobbed raft at 0 mm error). CollisionShape3D must be a DIRECT child of a body; an animated sub-part (e.g. a door leaf) gets its own StaticBody3D under a pivot node. Add MeshInstance3D, BuildSockets, and a `SampleMarker`.
2. Add BuildSocket nodes with correct `socket_type` and explicit `accepts` lists.
3. Add to `BUILD_RECIPE_NAMES` and `BUILD_SCENES` in player.gd.
4. Add a recipe to `inventory.gd` RECIPES (and to `RECIPE_REFUND` if removable).
5. Add placement logic in `_resolve_placement()` if the piece is non-standard.

### New Resource Type
1. Add to `inventory.gd` items dict.
2. Add to `ITEM_PROFILES` in debris.gd (mass, freeboard, color).
3. Add to `ITEM_POOL` in debris_spawner.gd (weight = number of entries).

### Enable Survival Stats
1. `Stats` is already an autoload (values shown by the mobile HUD status circles).
2. Set `Stats.enabled = true` (or adjust `hunger_drain_rate`/`thirst_drain_rate`) once real sources exist.
3. Call `eat()` / `drink()` from item pickups and `change_health()` from hazards.
3. Connect `stat_changed` / `player_died` to HUD and respawn logic.

### Migrate placement to BuildSystem
Replace `player._solve_socket_transform` calls with `BuildSystem.solve_socket_attachment(target_socket, socket_local, build_rotation, support_flat_basis)` — the math is identical, and the shared helper is already extracted.

---


---
## 25. Script Source Reference

Full, verbatim source of every project script in `res://` (folders: `addons/` ship the upstream Sky3D addon and are not duplicated here). Files appear in the order of the [Folder & File Map](#2-folder--file-map), with additions noted.

> Last generated from the live source so it always matches the running code.

### `res://main.gdshader`

```glsl
shader_type spatial;
render_mode unshaded;

// ============================================================
// OCEAN — time-of-day responsive water
// Driven per-frame by ocean.gd (uniforms below are pushed from
// the Sky3D sun/moon state). The wave VERTEX formula is the
// original — only the shading is time-aware.
//
// Palette note: uniforms are NOT source_color — ocean.gd pushes
// TRUE LINEAR HDR values (source_color would silently convert
// them sRGB->linear and darken the water ~3x). The scene uses
// ACES tonemapping (mode 3), which lifts mid-tones. The colors
// below are the LINEAR inputs; the FINAL displayed ocean is a
// bright tropical turquoise/cyan:
//   day (0.035, 0.38, 0.42) -> ~sRGB (0.2x, 0.6x, 0.6x) turquoise/cyan
//   night (0.012, 0.04, 0.12) -> ~sRGB (0.06, 0.20, 0.44) navy
// Verified empirically against the real ACES+sRGB pipeline.
// ============================================================

// --- time-of-day state (ocean.gd) ---
uniform vec3 water_day_color = vec3(0.035, 0.38, 0.42);
uniform vec3 water_twilight_color = vec3(0.07, 0.085, 0.26);
uniform vec3 water_night_color = vec3(0.018, 0.06, 0.165);
uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform float twilight_factor : hint_range(0.0, 1.0) = 0.0;
uniform float moon_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -0.5, -0.8);
uniform vec3 sun_glint_color = vec3(1.0, 0.95, 0.85);
uniform vec3 moon_glint_color = vec3(0.62, 0.78, 0.95);
uniform float sparkle_strength : hint_range(0.0, 4.0) = 1.0;

// --- waves (identical geometry to the original) ---
uniform float wave_height = 0.55;
uniform float wave_speed = 1.2;

// Wave crest level (-1 trough .. +1 crest) interpolated to the fragment
// so the surface can shade rolling wave bands + crest foam.
varying float wave_crest;
varying vec3 world_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = wp;
	float h = sin(wp.x * 0.4 + TIME * wave_speed)
		+ sin(wp.z * 0.3 + TIME * wave_speed * 0.8)
		+ 0.5 * sin((wp.x + wp.z) * 0.7 + TIME * 1.7);
	VERTEX.y += h * wave_height * 0.33;
	// Normalized crest level for the fragment shader (raw sum ~ -2.5..+2.5).
	wave_crest = clamp(h / 2.2, -1.0, 1.0);
	// Per-vertex wave normal from the analytic slope of the same formula so
	// glints follow the wave shapes (never a flat dark plane at night).
	float amp = wave_height * 0.33;
	float dhdx = amp * (0.4 * cos(wp.x * 0.4 + TIME * wave_speed)
		+ 0.35 * cos((wp.x + wp.z) * 0.7 + TIME * 1.7));
	float dhdz = amp * (0.3 * cos(wp.z * 0.3 + TIME * wave_speed * 0.8)
		+ 0.35 * cos((wp.x + wp.z) * 0.7 + TIME * 1.7));
	NORMAL = normalize(vec3(-dhdx, 1.0, -dhdz));
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(-VIEW);
	float ndv = max(dot(n, v), 0.0);

	// Base water color: day -> twilight -> deep navy night, always tinted.
	vec3 base = mix(water_day_color, water_twilight_color, twilight_factor);
	base = mix(base, water_night_color, night_factor);

	// Fresnel: looking straight down shows the base; grazing angles (distant
	// ocean from a low camera) mix toward the horizon tint so the horizon
	// reads like real water reflecting the bright sky. Horizon tint is a
	// light turquoise/cyan by day (never grey-white) so distant water glows
	// like the reference instead of washing out.
	float fres = pow(1.0 - ndv, 2.0);
	vec3 sky_ref = mix(vec3(0.045, 0.44, 0.55), vec3(0.15, 0.19, 0.34), twilight_factor);
	sky_ref = mix(sky_ref, vec3(0.02, 0.075, 0.2), night_factor);
	base = mix(base, sky_ref, fres * 0.55);

	// Wave-band shading: rolling crests catch the light (lighter turquoise),
	// deep troughs fall darker — this is what makes the surface visibly roll
	// like the reference instead of reading as a flat tint.
	float crest = wave_crest;
	vec3 wave_shade = mix(vec3(0.45, 0.95, 1.0), vec3(1.0, 0.9, 0.7), twilight_factor * 0.5);
	wave_shade = mix(wave_shade, vec3(0.18, 0.3, 0.5), night_factor);
	float lit = smoothstep(0.2, 1.0, crest);
	base += wave_shade * lit * vec3(0.12, 0.24, 0.24) * (1.0 - night_factor);
	base *= 1.0 - 0.36 * smoothstep(-1.0, -0.1, -crest) * (1.0 - night_factor * 0.5);

	// Specular: sun glitter path by day/twilight, moon shimmer by night. Two
	// lobes: a broad glitter path following the sun direction + sharp bright
	// dots — the dense sun-glitter look of the reference.
	vec3 r = reflect(-v, n);
	float sdot = max(dot(r, normalize(sun_dir)), 0.0);
	float sun_spark = (pow(sdot, 45.0) * 0.7 + pow(sdot, 120.0) * 1.8)
		* sparkle_strength * (1.0 - night_factor) * 2.4;
	float moon_spark = pow(max(dot(r, normalize(moon_dir)), 0.0), 55.0)
		* sparkle_strength * 0.9 * moon_factor;
	vec3 light_add = sun_spark * sun_glint_color + moon_spark * moon_glint_color;

	// Broad soft sheen toward each light so wave faces read as rolling shapes
	// even in deep night. Kept SMALL: ACES lifts mid-tones hard, so a broad
	// white sheen desaturates the whole surface (the old washed-out look) and
	// an over-strong moon sheen makes night as bright as day.
	float sun_sheen = pow(max(dot(n, normalize(sun_dir)), 0.0), 9.0) * 0.035 * (1.0 - night_factor);
	float moon_sheen = pow(max(dot(n, normalize(moon_dir)), 0.0), 7.0) * 0.055 * moon_factor;
	light_add += sun_sheen * sun_glint_color + moon_sheen * moon_glint_color;

	// White crest foam caps on the higher wave tops — day only (subtle at
	// twilight, gone at night). Threshold lower than before so wave crests
	// visibly froth like the reference.
	float foam = smoothstep(0.5, 1.0, crest);
	light_add += foam * mix(vec3(0.85, 0.95, 1.0), vec3(0.18, 0.28, 0.45), night_factor)
		* vec3(0.15, 0.16, 0.17) * (1.0 - night_factor * 0.9);

	// Aerial haze toward the horizon: far water blends toward a pale bright
	// turquoise so the ocean fades warmly into the sky at distance.
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float haze = smoothstep(30.0, 220.0, dist);
	vec3 haze_col = mix(vec3(0.24, 0.56, 0.62), vec3(0.12, 0.14, 0.24), twilight_factor);
	haze_col = mix(haze_col, vec3(0.03, 0.08, 0.17), night_factor);
	base = mix(base, haze_col, haze * 0.5);

	// Never-black floor keeps the water reading as water even in deep night.
	vec3 col = max(base + light_add, vec3(0.012, 0.032, 0.095));
	ALBEDO = col;
}

```

### `res://player.gd`

```gdscript
extends CharacterBody3D

# ============================================================
# CONSTANTS
# ============================================================
const WALK_SPEED := 3.0
const SPRINT_SPEED := 5.0
const SWIM_SPEED := 2.0
const SWIM_SPRINT_SPEED := 3.5
const JUMP_VELOCITY := 10.0
const WATER_JUMP_VELOCITY := 12.0
const DIVE_VELOCITY := -6.0
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.003
# Max riser height the player can auto-step onto while walking (stairs/curbs).
# Must stay below wall height (2.5) so full walls still block.
const MAX_STEP_HEIGHT := 0.55
const STEP_PROBE_FORWARD := 0.35
# Max rise per physics frame when auto-climbing stairs — lifts a riser across
# several frames (smooth) instead of teleporting the body up in one pop.
const STEP_RISE_PER_FRAME := 0.05

# Swimming
const SWIM_UP_CONTINUOUS := 5.0
const SWIM_DOWN_SPEED := 3.0
const SWIM_ACCELERATION := 12.0
const SWIM_DECELERATION := 6.0
const FLOAT_FORCE := 8.0
const FLOAT_DAMPING := 0.95
const WATER_ENTER_OFFSET := 0.3
const WATER_EXIT_OFFSET := 1.5
const MAX_SWIM_DEPTH := 30.0

# Aim
const AIM_DISTANCE := 60.0
const PICKUP_RANGE := 5.0
const NEARBY_PICKUP_RANGE := 2.0
# Climb out of the ocean: horizontal reach to the deck edge + how far onto
# the deck the player lands (kept small so the board feels natural).
const CLIMB_OUT_RANGE := 2.2
const CLIMB_LAND_INSET := 0.45

# Build
const BUILD_RECIPE_NAMES := ["Foundation", "Wall", "Roof", "Stairs", "Door", "Window"]
const BUILD_SCENES := [
	"res://foundation.tscn",
	"res://wall.tscn",
	"res://roof.tscn",
	"res://stairs.tscn",
	"res://door.tscn",
	"res://window.tscn",
]
const SOCKET_SNAP_RADIUS: float = 2.5
const WALL_SURFACE_SNAP_RANGE: float = 4.0  # wall ghost snaps to a surface within this 2D distance
const WALL_STACK_AIM_TOLERANCE: float = 0.6  # aiming this close to a wall's top stacks a 2nd floor wall
const BUILD_ROTATION_STEP := PI / 2.0    # R / Y rotate 90°
const BUILD_ROTATION_FINE_STEP := PI / 12.0  # hold Shift for 15° fine steps (center walls)

# Grid & Foundation dimensions — single source of truth
const CELL_SIZE: float = 2.0  # kept for backward compat; prefer FOUNDATION_WIDTH/DEPTH
const FOUNDATION_WIDTH: float = 2.0
const FOUNDATION_DEPTH: float = 2.0
const FOUNDATION_THICKNESS: float = 0.30
const FOUNDATION_HALF_WIDTH: float = FOUNDATION_WIDTH * 0.5
const FOUNDATION_HALF_DEPTH: float = FOUNDATION_DEPTH * 0.5
const FOUNDATION_HALF_HEIGHT: float = FOUNDATION_THICKNESS * 0.5

var _roof_last_support: Node3D = null  # last support wall for roof hysteresis

# ============================================================
# NODE REFERENCES
# ============================================================
@onready var cam_pivot: Node3D = $CamPivot
@onready var camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var crosshair: Control = $CanvasLayer/Crosshair
@onready var rope_system: RopeSystem = $RopeSystem

var ocean: Ocean = null

@export var build_pieces: Array[PackedScene] = []
var selected_piece_index: int = 0
var build_mode: bool = false

# Active inventory selection (hotbar slot 0..5 -> item name). The hotbar is
# inventory slots 0..5; tapping a slot in normal mode selects its item here.
var active_slot_index: int = 0
var active_item: String = "Rope"

# Auto-save (debounced): writes the inventory + state to user:// after the
# last change, and on quit/pause so closing the game never loses progress.
var _save_pending := false
var _save_timer := 0.0
const SAVE_DELAY := 1.0
var _hand_item: Node3D = null
var _hand_time := 0.0       # accumulated seconds, drives held-item sway
var _fist_node: Node3D = null
var _step_climb := 0.0  # current smooth auto-climb progress (stairs/curbs)
var ghost: Node3D = null
var build_rotation: float = 0.0
var build_rotation_x: float = 0.0
var build_valid: bool = false
var _ghost_valid_mat: StandardMaterial3D = null
var _ghost_invalid_mat: StandardMaterial3D = null

# Diagnostics
@export var debug_building: bool = false
# Build overlay: toggleable on-screen footprint samples + support ratio (F3)
var build_overlay: bool = false
var _f3_held: bool = false
@export_range(0.0, 1.0) var minimum_support_ratio: float = 0.50
@export var placement_surface_tolerance: float = 0.30
var _diag: Dictionary = {}

# Edit system state machine
var _editing: Node3D = null              # currently selected building (null = IDLE)
var _edit_original_transform: Transform3D = Transform3D()
var _edit_original_cell: Vector2i = Vector2i(999999, 999999)
var _edit_valid: bool = false
var _edit_candidate_transform: Transform3D = Transform3D()
var _edit_candidate_cell: Vector2i = Vector2i(999999, 999999)
# Double-click detection
var _last_click_time: float = 0.0
var _last_clicked_piece: Node3D = null
const DOUBLE_CLICK_TIME: float = 0.30

# Aim
var aim_point: Vector3 = Vector3.ZERO
var aim_normal: Vector3 = Vector3.FORWARD
var aim_collider: Node3D = null
var aim_distance: float = 0.0
var aim_valid: bool = false

# State
var is_swimming: bool = false
var was_swimming: bool = false

# HUD
var _hud_label: Label = null
var _last_hud_text := ""

# Grid occupancy — maps raft-relative Vector2i → Node3D
var _grid_occupancy: Dictionary = {}
var _raft_node: Node3D = null  # cached reference to root raft
var _last_debug_key: String = ""  # prevents output flooding

# ============================================================
# OCEAN
# ============================================================
func _get_ocean() -> Ocean:
	if ocean == null or not is_instance_valid(ocean):
		ocean = get_tree().get_first_node_in_group("ocean")
		if ocean == null:
			ocean = get_node_or_null("%Ocean")
	return ocean

# ============================================================
# INIT
# ============================================================
func _ready() -> void:
	add_to_group("player")
	rope_system.player = self
	rope_system.camera = camera
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true
	if build_pieces.is_empty():
		for scene_path in BUILD_SCENES:
			var scene = load(scene_path) as PackedScene
			if scene:
				build_pieces.append(scene)
	Inventory.infinite = true
	# Continue (menu loaded a save) keeps whatever was stored; New Game (no
	# save, empty bag) starts with Rope in hotbar slot 1 per the mobile spec.
	if Inventory.is_empty():
		Inventory.place_at(0, "Rope", 1)
	_create_hud()
	active_slot_index = int(Inventory.loaded_meta.get("active_slot", 0))
	active_slot_index = clampi(active_slot_index, 0, Inventory.HOTBAR_COUNT - 1)
	active_item = Inventory.slot_item(active_slot_index)
	Inventory.changed.connect(_refresh_active_item)
	Inventory.changed.connect(_queue_save)
	floor_snap_length = 0.18
	# Resume day time from the save (Continue) — otherwise leave the scene's
	# configured start time (noon).
	if Inventory.loaded_meta.has("game_time"):
		var sky3d: Node = get_parent().get_node_or_null("Sky3D")
		if sky3d != null:
			sky3d.set("current_time", float(Inventory.loaded_meta.get("game_time", 12.0)))
	_update_hand_item()
	# Rebuild the saved structure after a Continue (New Game has an empty
	# meta so this is a no-op). Deferred so the raft is fully in the tree.
	call_deferred("_restore_built_pieces")
	_queue_save()
	if debug_building:
		for i in BUILD_SCENES.size():
			var scene: PackedScene = load(BUILD_SCENES[i]) as PackedScene
			if scene:
				_validate_build_scene(scene, BUILD_RECIPE_NAMES[i])

# ============================================================
# MOUSE LOOK
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		add_look_input(event.relative)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ============================================================
# LOOK INPUT — shared by the mouse and the mobile touch controls.
# ============================================================
func add_look_input(rel: Vector2, sens: float = MOUSE_SENSITIVITY) -> void:
	if cam_pivot == null:
		return
	rotate_y(-rel.x * sens)
	cam_pivot.rotate_x(-rel.y * sens)
	cam_pivot.rotation.x = clamp(cam_pivot.rotation.x, -1.4, 1.4)

# ============================================================
# CENTRAL AIM SYSTEM
# ============================================================
func _update_aim() -> void:
	var space_state := get_world_3d().direct_space_state
	var ray_origin := camera.global_position
	var ray_dir := -camera.global_transform.basis.z
	var ray_end := ray_origin + ray_dir * AIM_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 3
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result:
		aim_valid = true
		aim_point = result.position
		aim_normal = result.normal
		aim_collider = result.collider as Node3D
		aim_distance = ray_origin.distance_to(result.position)
	else:
		aim_valid = false
		aim_point = ray_end
		aim_normal = -ray_dir
		aim_collider = null
		aim_distance = AIM_DISTANCE

# ============================================================
# PHYSICS PROCESS
# ============================================================
func _physics_process(delta: float) -> void:
	_update_aim()
	var oc := _get_ocean()
	var water_y: float = 0.0
	var has_ocean: bool = false
	if oc != null:
		water_y = oc.get_height(global_position)
		has_ocean = true
	var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var direction := _get_movement_direction(input_dir)
	var sprinting := Input.is_action_pressed("sprint")
	if is_swimming:
		_update_swimming(delta, direction, water_y, sprinting)
	else:
		_update_land(delta, direction, sprinting)
		_try_step_up()
	move_and_slide()
	_update_swimming_state(water_y, has_ocean)
	# Held-item sway: accumulate time and pose the hand visual (idle + walk).
	_hand_time += delta
	_update_hand_sway(delta)

func _update_swimming_state(water_y: float, has_ocean: bool) -> void:
	was_swimming = is_swimming
	if has_ocean:
		if is_swimming:
			is_swimming = global_position.y < water_y + WATER_EXIT_OFFSET and not is_on_floor()
		else:
			is_swimming = global_position.y < water_y + WATER_ENTER_OFFSET
	else:
		is_swimming = false
	if is_swimming != was_swimming:
		if not is_swimming:
			velocity.y = min(velocity.y, 0.0)

func _get_movement_direction(input_dir: Vector2) -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	return (right * input_dir.x + forward * input_dir.y).normalized()

func _update_land(delta: float, direction: Vector3, sprinting: bool) -> void:
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y -= GRAVITY * delta
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY
	if is_on_floor() and Input.is_action_just_pressed("move_down"):
		velocity.y = DIVE_VELOCITY

func _update_swimming(delta: float, direction: Vector3, water_y: float, sprinting: bool) -> void:
	var spd := SWIM_SPRINT_SPEED if sprinting else SWIM_SPEED
	velocity.x = direction.x * spd
	velocity.z = direction.z * spd
	if Input.is_action_just_pressed("jump"):
		velocity.y = WATER_JUMP_VELOCITY
	elif Input.is_action_pressed("jump"):
		velocity.y = move_toward(velocity.y, SWIM_UP_CONTINUOUS, SWIM_ACCELERATION * delta)
	elif Input.is_action_pressed("move_down"):
		velocity.y = move_toward(velocity.y, -SWIM_DOWN_SPEED, SWIM_ACCELERATION * delta)
	else:
		velocity.y = move_toward(velocity.y, 0.0, SWIM_DECELERATION * delta)
	var depth := water_y - global_position.y
	if depth > -1.0 and depth < 2.0:
		var surface_target := water_y + 0.2
		var error := surface_target - global_position.y
		if abs(error) > 0.3 and not Input.is_action_pressed("jump") and not Input.is_action_pressed("move_down"):
			velocity.y += error * FLOAT_FORCE * delta
		velocity.y *= FLOAT_DAMPING
	if depth > MAX_SWIM_DEPTH:
		velocity.y = move_toward(velocity.y, 0.0, SWIM_DECELERATION * delta)

# Walk up small steps (stairs / curbs) without jumping — mobile friendly.
# Runs right before move_and_slide: if walking into an obstacle that is lower
# than MAX_STEP_HEIGHT, lift the body onto it so the slide can carry it over.
func _try_step_up() -> void:
	if is_swimming or not is_on_floor():
		_step_climb = 0.0
		return
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horiz.length()
	if speed < 0.5:
		_step_climb = 0.0
		return
	var motion := horiz.normalized() * (speed * get_physics_process_delta_time() + STEP_PROBE_FORWARD)
	var params := PhysicsTestMotionParameters3D.new()
	var result := PhysicsTestMotionResult3D.new()
	params.from = global_transform
	params.motion = motion
	# Free to move at current height — normal walking, nothing to step over.
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		_step_climb = 0.0
		return
	# Blocked ahead: find how much lift clears the obstacle (stairs risers up to
	# MAX_STEP_HEIGHT). Tall walls (2.5 m) stay blocked at every probe height.
	# Small remaining lifts resolve in one smooth step; large ones are spread
	# over several frames (STEP_RISE_PER_FRAME) so stair risers don't pop the
	# camera 0.5 m in a single frame — the "shaking" when climbing stairs.
	var needed := -1.0
	for h in [0.06, 0.12, 0.18, 0.26, 0.38, MAX_STEP_HEIGHT]:
		var tf := global_transform.translated(Vector3(0.0, h, 0.0))
		params.from = tf
		params.motion = motion
		if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
			needed = h
			break
	if needed < 0.0:
		_step_climb = 0.0
		return
	# Continue the climb toward `needed`, capped per frame for smoothness.
	var step := clampf(needed - _step_climb, 0.0, STEP_RISE_PER_FRAME)
	if step <= 0.001:
		_step_climb = 0.0  # reached target last frame — next frame moves forward
		return
	global_position.y += step
	_step_climb += step
	if _step_climb >= needed - 0.001:
		_step_climb = 0.0
func _handle_pickup() -> void:
	if not Input.is_action_just_pressed("interact"):
		return
	# Boarding the raft from the water takes priority over pickups: when the
	# player is swimming right next to the raft/foundation, E climbs them out
	# (the mobile CLIMB button calls climb_out() directly — same result).
	if is_swimming and can_climb_out():
		climb_out()
		return
	if aim_valid and aim_collider != null:
		if aim_collider.is_in_group("debris") and aim_distance <= PICKUP_RANGE:
			_collect_debris(aim_collider)
			return
		# The Door's swinging leaf is its own StaticBody3D, so walk up the
		# tree to find the piece root that owns the togglable script (Door).
		var toggler: Node = aim_collider
		while toggler != null and not ("toggle" in toggler):
			toggler = toggler.get_parent()
		if toggler != null:
			toggler.toggle()
			return
	if aim_collider == null or not aim_collider.is_in_group("debris"):
		for d in get_tree().get_nodes_in_group("debris"):
			if d is Node3D and is_instance_valid(d):
				if global_position.distance_to(d.global_position) <= NEARBY_PICKUP_RANGE:
					_collect_debris(d)
					return

func _collect_debris(debris: Node3D) -> void:
	if debris.get("collected") == true:
		return
	var item_name: String = str(debris.get("item_name"))
	if item_name != "" and item_name != "null":
		debris.set("collected", true)
		Inventory.add(item_name)
		debris.queue_free()

# ============================================================
# BUILD SYSTEM — PROCESS & INPUT
# ============================================================
func _process(_delta: float) -> void:
	_tick_save(_delta)
	_update_hud()
	# Quick-save (F5) works in every mode — snapshots slot "quick".
	if Input.is_action_just_pressed("quick_save"):
		quick_save()
	# --- PRIORITY 1: Edit Mode ---
	if _editing != null:
		if Input.is_action_just_pressed("place_build"):
			_confirm_edit()
			return
		if Input.is_action_just_pressed("remove_build"):
			_remove_editing()
			return
		if Input.is_action_just_pressed("build"):
			_cancel_edit()
			return
		if Input.is_action_just_pressed("rotate_build"):
			_rotate_build()
		if Input.is_action_just_pressed("rotate_build_x"):
			_rotate_build_x()
		_update_edit_follow()
		crosshair.set_state(crosshair.State.BUILD)
		return
	# --- E double-click: pickup piece for editing (works in AND out of build mode) ---
	if Input.is_action_just_pressed("interact"):
		_handle_double_click_edit()
	# --- PRIORITY 2: Build Mode ---
	if Input.is_action_just_pressed("build"):
		_toggle_build()
	if Input.is_action_just_pressed("cycle_build") and build_mode:
		_cycle_build_piece()
	if build_mode and ghost:
		if Input.is_action_just_pressed("place_build"):
			_try_build()
		if Input.is_action_just_pressed("rotate_build"):
			_rotate_build()
		if Input.is_action_just_pressed("rotate_build_x"):
			_rotate_build_x()
		if Input.is_key_pressed(KEY_F3) and not _f3_held:
			build_overlay = not build_overlay
			if not build_overlay:
				_clear_overlay_markers()
		_f3_held = Input.is_key_pressed(KEY_F3)
		crosshair.set_state(crosshair.State.BUILD)
		_update_build_preview()
		return
	# --- PRIORITY 3: Normal gameplay ---
	_handle_pickup()
	if aim_valid and aim_collider != null and aim_collider.is_in_group("debris") and aim_distance <= PICKUP_RANGE:
		crosshair.set_state(crosshair.State.ITEM)
	elif aim_valid and aim_collider != null and "toggle" in aim_collider:
		crosshair.set_state(crosshair.State.ITEM)
	else:
		crosshair.set_state(crosshair.State.NONE)

func _toggle_build() -> void:
	if _editing != null:
		_cancel_edit()
		return
	if build_pieces.is_empty():
		return
	build_mode = !build_mode
	if build_mode:
		build_rotation = 0.0
		build_rotation_x = 0.0
		_spawn_ghost()
	elif ghost:
		ghost.queue_free()
		ghost = null
		if _debug_markers_root != null and is_instance_valid(_debug_markers_root):
			_debug_markers_root.queue_free()
			_debug_markers_root = null
			_debug_target_marker = null
			_debug_actual_marker = null
		_clear_overlay_markers()

var _build_preview_root: Node3D = null

func _get_build_preview_root() -> Node3D:
	if _build_preview_root != null and is_instance_valid(_build_preview_root):
		return _build_preview_root
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	_build_preview_root = Node3D.new()
	_build_preview_root.name = "BuildPreviewRoot"
	root.add_child(_build_preview_root)
	return _build_preview_root

func _spawn_ghost() -> void:
	if ghost:
		ghost.queue_free()
	ghost = build_pieces[selected_piece_index].instantiate()
	ghost.scale = Vector3.ONE
	ghost.visible = false
	_get_build_preview_root().add_child(ghost)
	ghost.global_position = aim_point
	# Disable ALL collision shapes (some pieces have several, e.g. stairs steps)
	for col in ghost.find_children("*", "CollisionShape3D", true, false):
		(col as CollisionShape3D).disabled = true
	if _ghost_valid_mat == null:
		_ghost_valid_mat = StandardMaterial3D.new()
		_ghost_valid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_valid_mat.albedo_color = Color(0.2, 0.9, 0.2, 0.5)
		_ghost_valid_mat.no_depth_test = true
	if _ghost_invalid_mat == null:
		_ghost_invalid_mat = StandardMaterial3D.new()
		_ghost_invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_invalid_mat.albedo_color = Color(0.9, 0.2, 0.2, 0.5)
		_ghost_invalid_mat.no_depth_test = true

func _cycle_build_piece() -> void:
	if build_pieces.is_empty():
		return
	selected_piece_index = (selected_piece_index + 1) % build_pieces.size()
	# Reset hysteresis when switching pieces
	_roof_last_support = null
	if build_mode:
		_spawn_ghost()

## Mobile hotbar quick-select: pick a build piece directly and enter build
## mode (or switch the current piece if already building).
func select_piece_for_build(index: int) -> void:
	if build_pieces.is_empty() or _editing != null:
		return
	if not build_mode:
		_toggle_build()
		if not build_mode:
			return
	selected_piece_index = posmod(index, build_pieces.size())
	_roof_last_support = null
	_spawn_ghost()

## Mobile normal-mode hotbar tap: select inventory slot 0..5 as the active
## item (building pieces live in Build Mode and go through
## select_piece_for_build instead). Empty taps clear the selection.
func select_hotbar_slot(index: int) -> void:
	if _editing != null:
		return
	active_slot_index = clampi(index, 0, Inventory.HOTBAR_COUNT - 1)
	active_item = Inventory.slot_item(active_slot_index)


func _refresh_active_item() -> void:
	active_item = Inventory.slot_item(clampi(active_slot_index, 0, Inventory.HOTBAR_COUNT - 1))
	_update_hand_item()


# ============================================================
# AUTO-SAVE — debounced write on change + save on quit/background
# ============================================================
func _queue_save() -> void:
	_save_pending = true
	_save_timer = SAVE_DELAY


## Build the state meta (selected slot + time of day + the built structure)
## and write it to the given slot ("main" autosave or "quick" quick-save).
func _write_save(slot: String) -> void:
	var meta := {"active_slot": active_slot_index}
	var sky3d: Node = get_parent().get_node_or_null("Sky3D")
	if sky3d != null and sky3d.get("current_time") != null:
		meta["game_time"] = float(sky3d.get("current_time"))
	# The built structure lives under the raft's BuiltPieces — without this the
	# save file holds only inventory and Continue returns an empty raft.
	meta["built"] = _serialize_built_pieces()
	Inventory.save_game(meta, slot)


func _flush_save() -> void:
	_write_save("main")


## Manual quick-save (desktop F5 / mobile SAVE chip in the bag panel).
## Writes a second snapshot slot that the main menu offers under "QUICK SAVE".
func quick_save() -> void:
	_write_save("quick")
	_hud_toast("QUICK-SAVED")


func _hud_toast(text: String) -> void:
	var hud: Node = get_node_or_null("CanvasLayer/SurvivalHUD")
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", text)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_flush_save()


# ============================================================
# BUILT STRUCTURE PERSISTENCE — the placed pieces are saved with the game
# ============================================================
## Serialize every piece under the raft's BuiltPieces into a compact array:
## each entry is the piece TYPE ("Foundation", "Wall", ...) plus its 12-float
## raft-local Transform3D (basis 9 + origin 3). Local transforms are stable
## because the raft only bobs on Y (its rotation is always identity).
func _serialize_built_pieces() -> Array:
	var raft: Node3D = _get_raft_node()
	if raft == null:
		return []
	var container: Node = raft.get_node_or_null("BuiltPieces")
	if container == null:
		return []
	var out: Array = []
	for piece in container.get_children():
		if not (piece is Node3D) or not is_instance_valid(piece):
			continue
		var pname: String = _find_piece_name(piece as Node3D)
		if pname == "" or pname == "Raft":
			continue
		var t := (piece as Node3D).transform
		var b := t.basis
		out.append({
			"t": pname,
			"x": [
				b.x.x, b.x.y, b.x.z,
				b.y.x, b.y.y, b.y.z,
				b.z.x, b.z.y, b.z.z,
				t.origin.x, t.origin.y, t.origin.z,
			],
		})
	return out


## Rebuild the saved structure after a Continue. Runs deferred so the whole
## scene (raft included) is ready; each piece is instantiated from its scene,
## given the saved raft-local transform, collisions enabled, registered in the
## occupancy grid + buoyancy samples, and sockets re-linked best-effort.
func _restore_built_pieces() -> void:
	var built: Array = Inventory.loaded_meta.get("built", [])
	if built.is_empty():
		return
	var raft: Node3D = _get_raft_node()
	if raft == null:
		return
	var container: Node = raft.get_node_or_null("BuiltPieces")
	if container == null:
		container = Node3D.new()
		container.name = "BuiltPieces"
		raft.add_child(container)
	var restored: Array = []
	for entry in built:
		if not (entry is Dictionary):
			continue
		var pname: String = str(entry.get("t", ""))
		var idx := BUILD_RECIPE_NAMES.find(pname)
		if idx < 0:
			continue
		var scene: PackedScene = build_pieces[idx]
		if scene == null:
			continue
		var piece: Node3D = scene.instantiate()
		piece.name = "%s_%d" % [pname, piece.get_instance_id()]
		var floats: Array = entry.get("x", [])
		if floats.size() == 12:
			var tb := Basis(
				Vector3(floats[0], floats[1], floats[2]),
				Vector3(floats[3], floats[4], floats[5]),
				Vector3(floats[6], floats[7], floats[8]))
			piece.transform = Transform3D(tb, Vector3(floats[9], floats[10], floats[11]))
		# Disable collision before adding (same as _try_build) so the body
		# never pushes the player on load.
		var cols: Array[Node] = piece.find_children("*", "CollisionShape3D", true, false)
		for c in cols:
			(c as CollisionShape3D).disabled = true
		container.add_child(piece)
		for c in cols:
			(c as CollisionShape3D).set_deferred("disabled", false)
		piece.add_to_group("build_surface")
		restored.append(piece)
		# Grid occupancy (foundations are grid-registered; walls/doors/etc are
		# edge attachments and do not occupy a grid cell).
		if pname == "Foundation":
			_grid_register(_world_to_grid(piece.global_position), piece)
		# Buoyancy sample so the raft's float height covers the rebuilt deck.
		var sample: Node = piece.get_node_or_null("SampleMarker")
		if sample == null:
			sample = piece.get_node_or_null("F1")
		if sample != null and raft.has_method("register_sample_point"):
			raft.register_sample_point(sample)
	# Best-effort socket re-link: every socket occupies the piece sitting at
	# its horizontal position (covers raft edge->Foundation, Foundation
	# Socket_Top->Wall/Door/Window, Stairs sockets, ...).
	_relink_restored_sockets(raft, restored)
	print("[SAVE] Restored %d built piece(s) from %s" % [restored.size(), str(Inventory.loaded_meta.get("loaded_slot", "main"))])


func _relink_restored_sockets(raft: Node3D, restored: Array) -> void:
	for s in _get_all_sockets(raft):
		var parent: Node3D = s.get_parent_piece()
		if parent == null:
			parent = raft
		var flat: Transform3D = _get_flat_support_transform(parent)
		var ws: Vector3 = flat * s.position
		var best: Node3D = null
		var best_d: float = 0.45
		for p in restored:
			if p == parent or not is_instance_valid(p):
				continue
			var d: float = Vector2(p.global_position.x - ws.x, p.global_position.z - ws.z).length()
			if d < best_d:
				best_d = d
				best = p
		if best != null:
			s.occupy(best)


# In _process (exists below): when _save_pending, count down and flush.
func _tick_save(delta: float) -> void:
	if not _save_pending:
		return
	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_pending = false
		_flush_save()


# ============================================================
# HELD ITEM VISUAL — the selected hotbar item appears in the fist
# ============================================================
func _update_hand_item() -> void:
	if _fist_node == null or not is_instance_valid(_fist_node):
		_fist_node = get_node_or_null("CamPivot/SpringArm3D/Camera3D/HandPivot/Fist") as Node3D
		if _fist_node == null:
			return
	if _hand_item == null or not is_instance_valid(_hand_item):
		_hand_item = Node3D.new()
		_hand_item.name = "HandItem"
		_fist_node.add_child(_hand_item)
	# Remove any old visuals
	for c in _hand_item.get_children():
		c.queue_free()
	_hand_item.position = Vector3.ZERO
	_hand_item.rotation = Vector3.ZERO
	if active_item == "":
		return
	# Each item is composed from primitives placed in a NATURAL HAND POSE around
	# the fist (offsets below are fist-local: +X right, +Y up, -Z forward).
	match active_item:
		"Rope":
			var coil := _hand_mat(Color(0.78, 0.6, 0.35))
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.13
			cyl.bottom_radius = 0.13
			cyl.height = 0.05
			var i3 := 0
			for ly in [-0.055, 0.005, 0.065]:
				var xf := Transform3D(Basis(Vector3.UP, float(i3) * TAU / 3.0), Vector3(0, ly, -0.24))
				_hand_part(cyl, coil, xf)
				i3 += 1
			var knot := _hand_mat(Color(0.9, 0.8, 0.52))
			var ks := SphereMesh.new()
			ks.radius = 0.045
			ks.height = 0.09
			_hand_part(ks, knot, Transform3D(Basis.IDENTITY, Vector3(0, 0.115, -0.24)))
		"Wood":
			var wood := _hand_mat(Color(0.62, 0.43, 0.22))
			var log := CylinderMesh.new()
			log.top_radius = 0.05
			log.bottom_radius = 0.07
			log.height = 0.55
			var along_z := Basis(Vector3(1, 0, 0), PI / 2.0)  # cylinder Y axis -> Z
			_hand_part(log, wood, Transform3D(along_z, Vector3(0, -0.01, -0.24)))
			var bark := _hand_mat(Color(0.42, 0.28, 0.14))
			var cap := CylinderMesh.new()
			cap.top_radius = 0.06
			cap.bottom_radius = 0.06
			cap.height = 0.02
			_hand_part(cap, bark, Transform3D(along_z, Vector3(0, -0.01, 0.045)))
			_hand_part(cap, bark, Transform3D(along_z, Vector3(0, -0.01, -0.525)))
		"Plastic":
			var body := _hand_mat(Color(0.42, 0.78, 0.92), 0.35)
			var bot := CapsuleMesh.new()
			bot.radius = 0.055
			bot.height = 0.3
			_hand_part(bot, body, Transform3D(Basis.IDENTITY, Vector3(0.02, -0.16, -0.25)))
			var neck := _hand_mat(Color(0.25, 0.45, 0.55), 0.4)
			var nk := CylinderMesh.new()
			nk.top_radius = 0.028
			nk.bottom_radius = 0.028
			nk.height = 0.08
			_hand_part(nk, neck, Transform3D(Basis.IDENTITY, Vector3(0.02, 0.07, -0.25)))
		"Metal":
			var steel := _hand_mat(Color(0.74, 0.76, 0.8), 0.3, 0.9)
			var rod := CylinderMesh.new()
			rod.top_radius = 0.035
			rod.bottom_radius = 0.035
			rod.height = 0.5
			var along_z2 := Basis(Vector3(1, 0, 0), PI / 2.0)
			_hand_part(rod, steel, Transform3D(along_z2, Vector3(0, 0.0, -0.22)))
			var tip := _hand_mat(Color(0.5, 0.52, 0.56), 0.3, 0.9)
			var tc := CylinderMesh.new()
			tc.top_radius = 0.036
			tc.bottom_radius = 0.036
			tc.height = 0.02
			_hand_part(tc, tip, Transform3D(along_z2, Vector3(0, 0.0, 0.035)))
			_hand_part(tc, tip, Transform3D(along_z2, Vector3(0, 0.0, -0.475)))
		"Stone":
			var rock := _hand_mat(Color(0.55, 0.55, 0.58), 1.0)
			var s1 := SphereMesh.new()
			s1.radius = 0.105
			s1.height = 0.21
			_hand_part(s1, rock, Transform3D(Basis.IDENTITY, Vector3(0, -0.02, -0.19)))
			var s2 := SphereMesh.new()
			s2.radius = 0.075
			s2.height = 0.15
			_hand_part(s2, rock, Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.08, -0.07, -0.15)))
		"Barrel":
			var wood2 := _hand_mat(Color(0.55, 0.28, 0.2))
			var bar := CylinderMesh.new()
			bar.top_radius = 0.1
			bar.bottom_radius = 0.1
			bar.height = 0.17
			_hand_part(bar, wood2, Transform3D(Basis.IDENTITY, Vector3(0, -0.14, -0.22)))
			var band := _hand_mat(Color(0.18, 0.11, 0.08), 0.7)
			var bw := CylinderMesh.new()
			bw.top_radius = 0.108
			bw.bottom_radius = 0.108
			bw.height = 0.03
			_hand_part(bw, band, Transform3D(Basis.IDENTITY, Vector3(0, -0.2, -0.22)))
			_hand_part(bw, band, Transform3D(Basis.IDENTITY, Vector3(0, -0.08, -0.22)))
		_:
			return


func _hand_mat(color: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	# A whisper of self-light keeps the held item readable at dusk/night on
	# small screens (cheap for a tiny mesh; scene lights still dominate by day).
	if metal > 0.5:
		m.emission_enabled = false
	else:
		m.emission_enabled = true
		m.emission = color * 0.09
	return m


func _hand_part(mesh: Mesh, mat: StandardMaterial3D, xform: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xform
	_hand_item.add_child(mi)


## Subtle idle + walk sway for the held item (mobile juice, no camera shake).
func _update_hand_sway(_delta: float) -> void:
	if _hand_item == null or not is_instance_valid(_hand_item):
		return
	if _hand_item.get_child_count() == 0:
		return
	var speed_h := Vector2(velocity.x, velocity.z).length()
	var amp: float = clampf(speed_h / maxf(WALK_SPEED, 0.01), 0.0, 1.3)
	var bob := sin(_hand_time * 9.5) * 0.016 * amp + sin(_hand_time * 1.6) * 0.006
	var sway := sin(_hand_time * 1.3) * 0.02 + sin(_hand_time * 4.7) * 0.012 * amp
	var roll := sin(_hand_time * 0.9) * 0.012 + cos(_hand_time * 4.7) * 0.01 * amp
	_hand_item.position = Vector3(0.0, bob, 0.0)
	_hand_item.rotation = Vector3(0.0, sway, roll)


## Mirror of the E-key interaction test, so the mobile HAND button lights up
## exactly when pressing it would actually do something (same as _handle_pickup):
##   - aimed at debris within the pickup range, or
##   - aimed at a togglable (door), or
##   - any debris within the nearby pickup range (the "reach out and grab it"
##     case — in real life you only take debris that is within your pickable
##     range, and the E key collects those even without precise aiming).
func can_interact_now() -> bool:
	if aim_valid and aim_collider != null:
		var c := aim_collider
		if c.is_in_group("debris") and aim_distance <= PICKUP_RANGE:
			return true
		var n: Node = c
		while n != null:
			if "toggle" in n:
				return true
			n = n.get_parent()
	# Nearby debris the E key would collect without aiming.
	for d in get_tree().get_nodes_in_group("debris"):
		if d is Node3D and is_instance_valid(d) and d.get("collected") != true:
			if global_position.distance_to(d.global_position) <= NEARBY_PICKUP_RANGE:
				return true
	return false

# ============================================================
# CLIMB OUT OF THE OCEAN — board the raft / foundation from the water
# ============================================================
## Nearest build surface (raft or any foundation) whose deck edge is within
## CLIMB_OUT_RANGE horizontally and whose deck sits above the water line —
## i.e. a real ledge the swimmer can pull themselves onto. Returns null when
## no climbable surface is near.
func _nearest_climb_surface() -> Node3D:
	var best: Node3D = null
	var best_d: float = CLIMB_OUT_RANGE
	var oc := _get_ocean()
	var water_y: float = oc.get_height(global_position) if oc != null else -INF
	for s in get_tree().get_nodes_in_group("build_surface"):
		if s == null or not is_instance_valid(s) or not (s is Node3D):
			continue
		# Only the raft itself and Foundations are deck ledges you can pull
		# yourself onto from the water (walls/roofs are not climb targets).
		if not (s.name.begins_with("Raft") or s.name.begins_with("Foundation")):
			continue
		# Deck top = flat origin + half thickness (raft and foundations are
		# both 0.3 thick boxes; this matches how the player walks on them).
		var flat: Transform3D = _get_flat_support_transform(s)
		var deck_top: float = flat.origin.y + FOUNDATION_HALF_HEIGHT
		if deck_top < water_y - 0.05:
			continue  # submerged — nothing to climb onto
		# Horizontal distance from the player to the deck footprint.
		var local: Vector3 = flat.affine_inverse() * global_position
		var hx := clampf(local.x, -FOUNDATION_HALF_WIDTH, FOUNDATION_HALF_WIDTH)
		var hz := clampf(local.z, -FOUNDATION_HALF_DEPTH, FOUNDATION_HALF_DEPTH)
		var d: float = Vector2(local.x - hx, local.z - hz).length()
		if d < best_d:
			best_d = d
			best = s
	return best

## True while swimming AND next to a climbable deck — the mobile CLIMB button
## only appears then (never on land, never in open water).
func can_climb_out() -> bool:
	return is_swimming and _nearest_climb_surface() != null

## Pull the player out of the water onto the nearest deck edge. Used by the
## mobile CLIMB button and by E while swimming. Lands the capsule a small
## step onto the deck (not teetering on the exact edge) and zeroes the swim
## velocity so the player immediately walks normally.
func climb_out() -> void:
	var surface := _nearest_climb_surface()
	if surface == null:
		return
	var flat: Transform3D = _get_flat_support_transform(surface)
	var deck_top: float = flat.origin.y + FOUNDATION_HALF_HEIGHT
	var local: Vector3 = flat.affine_inverse() * global_position
	# Land inside the edge so the player stands on the deck, not at the lip.
	var land_x := clampf(local.x, -(FOUNDATION_HALF_WIDTH - CLIMB_LAND_INSET),
		FOUNDATION_HALF_WIDTH - CLIMB_LAND_INSET)
	var land_z := clampf(local.z, -(FOUNDATION_HALF_DEPTH - CLIMB_LAND_INSET),
		FOUNDATION_HALF_DEPTH - CLIMB_LAND_INSET)
	var target: Vector3 = flat * Vector3(land_x, 0.0, land_z)
	# Capsule center sits ~1.05 m above the deck top (capsule radius 0.5,
	# shape offset -0.033, half height 1.0) — gravity settles the last cm.
	target.y = deck_top + 1.05
	global_position = target
	velocity = Vector3.ZERO
	is_swimming = false
	was_swimming = false

func _rotate_build() -> void:
	# Hold Shift for 15° fine steps (e.g. angling a center wall), otherwise 90°.
	var step: float = BUILD_ROTATION_FINE_STEP if Input.is_key_pressed(KEY_SHIFT) else BUILD_ROTATION_STEP
	build_rotation += step
	if build_rotation >= TAU:
		build_rotation -= TAU

func _rotate_build_x() -> void:
	build_rotation_x += PI / 2.0
	if build_rotation_x >= TAU:
		build_rotation_x -= TAU

# ============================================================
# BUILD SYSTEM — GRID & OCCUPANCY
# ============================================================
func _get_raft_node() -> Node3D:
	if _raft_node != null and is_instance_valid(_raft_node):
		return _raft_node
	_raft_node = get_tree().get_first_node_in_group("build_surface") as Node3D
	if _raft_node != null:
		_grid_register(Vector2i.ZERO, _raft_node)
	return _raft_node

# Canonical structural deck height: top surface of the Foundation floor.
# Every Foundation uses this same height — no cumulative calculation.
func _get_structural_deck_y() -> float:
	var raft: Node3D = _get_raft_node()
	if raft == null:
		return 0.0
	var flat_xf: Transform3D = _get_flat_support_transform(raft)
	return flat_xf.origin.y + FOUNDATION_HALF_HEIGHT

# Convert world position to grid cell relative to the raft.
func _world_to_grid(world_pos: Vector3) -> Vector2i:
	var raft := _get_raft_node()
	if raft == null:
		return Vector2i.ZERO
	# Use flat transform (no wave tilt) for consistent grid mapping
	var flat_xform: Transform3D = _get_flat_support_transform(raft)
	var local: Vector3 = flat_xform.affine_inverse() * world_pos
	var cx: int = int(roundf(local.x / FOUNDATION_WIDTH))
	var cz: int = int(roundf(local.z / FOUNDATION_DEPTH))
	return Vector2i(cx, cz)

# Get the world-space center of a grid cell relative to the raft.
func _grid_to_world(cell: Vector2i) -> Vector3:
	var raft := _get_raft_node()
	if raft == null:
		return Vector3.ZERO
	var local: Vector3 = Vector3(cell.x * FOUNDATION_WIDTH, 0.0, cell.y * FOUNDATION_DEPTH)
	# Use flat transform (no wave tilt) so grid positions are always level
	return _get_flat_support_transform(raft) * local

# Register a piece in the occupancy grid.
func _grid_register(cell: Vector2i, piece: Node3D) -> void:
	_grid_occupancy[cell] = piece

# Unregister a piece from the grid.
func _grid_unregister(cell: Vector2i) -> void:
	_grid_occupancy.erase(cell)

# Check if a cell is occupied.
func _grid_is_occupied(cell: Vector2i) -> bool:
	return _grid_occupancy.has(cell)

# A cell is blocked when it holds a REAL placed piece, or when it is the
# raft's own cell. The raft itself is registered at (0,0) as a structural
# anchor; the FIRST Foundation must be placed in a NEIGHBOR cell, because a
# Foundation on the raft's own cell would be buried INSIDE the raft box
# (identical 2x0.3x2 volume -> z-fighting, raft color bleed, blocked deck).
func _grid_is_blocked(cell: Vector2i) -> bool:
	var raft_node: Node3D = _get_raft_node()
	if raft_node != null and _world_to_grid(raft_node.global_position) == cell:
		return true
	if not _grid_occupancy.has(cell):
		return false
	var occ: Node3D = _grid_occupancy[cell] as Node3D
	if occ == null or not is_instance_valid(occ):
		return false
	return occ != raft_node

# Get the cell that a support piece occupies.
func _get_piece_cell(piece: Node3D) -> Vector2i:
	return _world_to_grid(piece.global_position)

# Find the support piece's cell, then determine which adjacent cell
# the player's aim is targeting.
func _aim_to_candidate_cell(support: Node3D) -> Vector2i:
	var support_cell: Vector2i = _get_piece_cell(support)
	# Convert aim point to support-local space
	var raft := _get_raft_node()
	if raft == null:
		return support_cell
	# Use flat transform (no wave tilt) for consistent aim-to-cell mapping
	var flat_xform: Transform3D = _get_flat_support_transform(raft)
	var local_aim: Vector3 = flat_xform.affine_inverse() * aim_point
	# Determine direction from support center to aim point
	var dx: float = local_aim.x - support_cell.x * FOUNDATION_WIDTH
	var dz: float = local_aim.z - support_cell.y * FOUNDATION_DEPTH
	# Map to grid offset
	var ox: int = 0
	var oz: int = 0
	# Determine which edge/corner the aim is closest to
	var abs_dx: float = absf(dx)
	var abs_dz: float = absf(dz)
	if abs_dx < 0.01 and abs_dz < 0.01:
		# Aim at center — use hit normal instead
		var normal_local: Vector3 = flat_xform.basis.inverse() * aim_normal
		normal_local.y = 0.0
		if normal_local.length() > 0.001:
			normal_local = normal_local.normalized()
			ox = int(roundf(normal_local.x))
			oz = int(roundf(normal_local.z))
		else:
			return support_cell
	elif abs_dx > abs_dz:
		# Primarily X direction
		ox = 1 if dx > 0 else -1
		# Check if also at Z edge for corner
		if abs_dz > FOUNDATION_HALF_WIDTH * 0.7:
			oz = 1 if dz > 0 else -1
	else:
		# Primarily Z direction
		oz = 1 if dz > 0 else -1
		if abs_dx > FOUNDATION_HALF_WIDTH * 0.7:
			ox = 1 if dx > 0 else -1
	return support_cell + Vector2i(ox, oz)

# ============================================================
# BUILD SYSTEM — STRUCTURAL SUPPORT
# ============================================================
func _is_structurally_supported(piece: Node3D) -> bool:
	# Raft is always supported
	if piece.name.begins_with("Raft"):
		return true
	# A piece sitting ON the raft (or in a cardinal neighbor cell) is supported
	# directly — the raft is located from the scene node, NOT _grid_occupancy,
	# which is overwritten when the first Foundation is placed on the raft's
	# cell (without this, that Foundation fails its own structural check and
	# every later build returns NO STRUCTURAL SUPPORT).
	var raft_sn: Node3D = _get_raft_node()
	if raft_sn != null:
		var raft_cell_sn: Vector2i = _world_to_grid(raft_sn.global_position)
		var piece_cell_sn: Vector2i = _get_piece_cell(piece)
		if piece_cell_sn == raft_cell_sn:
			return true
		if absi(piece_cell_sn.x - raft_cell_sn.x) + absi(piece_cell_sn.y - raft_cell_sn.y) == 1:
			return true
	# BFS from piece to find a path back to the raft — avoids infinite recursion
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	var start_cell: Vector2i = _get_piece_cell(piece)
	visited[start_cell] = true
	queue.append(start_cell)
	while not queue.is_empty():
		var current_cell: Vector2i = queue.pop_front()
		# Cardinal neighbors (full edge connection)
		var cardinal: Array[Vector2i] = [
			current_cell + Vector2i(0, -1), current_cell + Vector2i(0, 1),
			current_cell + Vector2i(-1, 0), current_cell + Vector2i(1, 0),
		]
		for n in cardinal:
			if visited.has(n):
				continue
			if _grid_occupancy.has(n):
				var neighbor: Node3D = _grid_occupancy[n] as Node3D
				if neighbor != null and is_instance_valid(neighbor):
					if neighbor.name.begins_with("Raft"):
						return true
					visited[n] = true
					queue.append(n)
		# Diagonal neighbors — only count when connecting to raft root
		var diagonal: Array[Vector2i] = [
			current_cell + Vector2i(-1, -1), current_cell + Vector2i(1, -1),
			current_cell + Vector2i(-1, 1), current_cell + Vector2i(1, 1),
		]
		for n in diagonal:
			if visited.has(n):
				continue
			if _grid_occupancy.has(n):
				var neighbor: Node3D = _grid_occupancy[n] as Node3D
				if neighbor != null and is_instance_valid(neighbor):
					if neighbor.name.begins_with("Raft"):
						return true
	return false

func _get_support_path(piece: Node3D) -> Array[String]:
	var path: Array[String] = []
	var current: Node3D = piece
	var visited: Dictionary = {}
	while current != null:
		if visited.has(current):
			break
		visited[current] = true
		path.append(current.name)
		if current.name.begins_with("Raft"):
			break
		var sockets_node := current.get_node_or_null("BuildSockets")
		if sockets_node == null:
			break
		var parent_piece: Node3D = null
		for socket in sockets_node.get_children():
			if socket is BuildSocket and socket.occupying_piece != null \
				and is_instance_valid(socket.occupying_piece):
				parent_piece = socket.occupying_piece
				break
		current = parent_piece
	return path

# ============================================================
# BUILD SYSTEM — SOCKET HELPERS
# ============================================================
func _get_all_sockets(root: Node) -> Array[BuildSocket]:
	var result: Array[BuildSocket] = []
	if root == null:
		return result
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BuildSocket:
			result.append(n)
		for c in n.get_children():
			stack.append(c)
	return result

## True when the crosshair is aimed at (or above) a roof's TOP face — i.e. the
## player is standing on it / looking down at it, so walls may mount it.
func _is_roof_top_aim(roof: Node3D, aim_world: Vector3) -> bool:
	if roof == null or _find_piece_name(roof) != "Roof":
		return false
	var flat: Transform3D = _get_flat_support_transform(roof)
	var local: Vector3 = flat.affine_inverse() * aim_world
	return local.y >= 0.03

func _find_support_piece(collider: Node3D) -> Node3D:
	if collider == null:
		return null
	if collider.name.begins_with("Foundation") or collider.name.begins_with("Wall") \
		or collider.name.begins_with("Roof") or collider.name.begins_with("Stairs") \
		or collider.name.begins_with("Door") or collider.name.begins_with("Window") \
		or collider.name.begins_with("Raft"):
		if collider.get_node_or_null("BuildSockets") != null:
			return collider
	var current: Node = collider
	for _i in range(5):
		if current == null:
			break
		if current is Node3D and current.get_node_or_null("BuildSockets") != null:
			return current as Node3D
		current = current.get_parent()
	return null

func _find_piece_name(node: Node3D) -> String:
	if node == null:
		return ""
	for n in BUILD_RECIPE_NAMES:
		if node.name.begins_with(n):
			return n
	if node.name.begins_with("Raft"):
		return "Raft"
	return ""

func _piece_name_from_node(node: Node3D) -> String:
	return _find_piece_name(node)

func _get_socket_world_direction(socket: BuildSocket) -> Vector3:
	var parent_piece: Node3D = socket.get_parent_piece()
	if parent_piece == null:
		return Vector3.FORWARD
	# Use flat transform (no wave tilt) for consistent direction scoring
	var parent_basis: Basis = _get_flat_support_transform(parent_piece).basis
	var local_pos: Vector3 = socket.position
	if absf(local_pos.y) < 0.01:
		local_pos.y = 0.0
	if local_pos.length() < 0.001:
		return Vector3.UP
	return (parent_basis * local_pos.normalized()).normalized()

func _is_corner_socket(socket: BuildSocket) -> bool:
	var sname: String = socket.name
	return sname.contains("NorthEast") or sname.contains("NorthWest") \
		or sname.contains("SouthEast") or sname.contains("SouthWest")

# ============================================================
# BUILD SYSTEM — TRANSFORM SOLVERS
# Get the support's flat transform (position + Y-rotation only, no wave tilt).
# This ensures placed buildings are always level, not tilted with waves.
func _get_flat_support_transform(support: Node3D) -> Transform3D:
	var pos: Vector3 = support.global_position
	var yaw: float = support.global_rotation.y
	return Transform3D(Basis(Vector3.UP, yaw), pos)

# Edge/face placement: new piece socket coincides with target socket.
# Always flat — ignores wave tilt.
func _solve_socket_transform(
	target_socket: BuildSocket,
	new_piece_socket_local_pos: Vector3,
	support: Node3D,
) -> Transform3D:
	# Use flat support transform (no wave tilt)
	var flat_xform: Transform3D = _get_flat_support_transform(support)
	var socket_local: Vector3 = target_socket.position
	var target_flat_pos: Vector3 = flat_xform * socket_local
	var rotated_offset: Vector3 = new_piece_socket_local_pos.rotated(Vector3.UP, build_rotation)
	var piece_center: Vector3 = target_flat_pos - rotated_offset
	var piece_basis: Basis = flat_xform.basis.rotated(Vector3.UP, build_rotation)
	return Transform3D(piece_basis, piece_center)

# Determine which cardinal edge of a foundation the crosshair targets.
# Returns the foundation edge socket name (e.g. "Socket_North").
func _select_wall_edge(foundation: Node3D, aim_world: Vector3) -> String:
	var flat_xf: Transform3D = _get_flat_support_transform(foundation)
	var local_aim: Vector3 = flat_xf.affine_inverse() * aim_world
	var half_w: float = FOUNDATION_HALF_WIDTH
	# Perpendicular distance from aim to each edge line in local space.
	var dist_n: float = absf(local_aim.z - half_w)
	var dist_s: float = absf(local_aim.z + half_w)
	var dist_e: float = absf(local_aim.x - half_w)
	var dist_w: float = absf(local_aim.x + half_w)
	var edges: Array = [
		{"name": "Socket_North", "dist": dist_n, "out": Vector3(0, 0, 1)},
		{"name": "Socket_South", "dist": dist_s, "out": Vector3(0, 0, -1)},
		{"name": "Socket_East",  "dist": dist_e, "out": Vector3(1, 0, 0)},
		{"name": "Socket_West",  "dist": dist_w, "out": Vector3(-1, 0, 0)},
	]
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	var best_name: String = edges[0]["name"]
	var best_dist: float = edges[0]["dist"]
	# Corner tolerance — when two edges are close, use camera direction to break tie.
	const CORNER_TOL: float = 0.25
	var candidates: Array = []
	for e in edges:
		if e["dist"] <= best_dist + CORNER_TOL:
			candidates.append(e)
	if candidates.size() == 1:
		return candidates[0]["name"]
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	var cam_flat: Vector3 = Vector3(cam_fwd.x, 0.0, cam_fwd.z).normalized()
	var best_score: float = -INF
	for e in candidates:
		var score: float = cam_flat.dot(e["out"])
		if score > best_score:
			best_score = score
			best_name = e["name"]
	return best_name

# Edge-snapping wall placement: wall snaps to the foundation edge the crosshair targets.
# The wall's width runs along the edge; the wall also SLIDES along the edge to follow
# the crosshair, so corners and any point along the edge work. Edge rotation is
# computed from the socket position.
func _compute_wall_transform(foundation: Node3D, aim_world: Vector3) -> Transform3D:
	var edge_name: String = _select_wall_edge(foundation, aim_world)
	var sockets_node: Node3D = foundation.get_node_or_null("BuildSockets")
	if sockets_node == null:
		return Transform3D()
	var edge_socket: Node3D = sockets_node.get_node_or_null(edge_name)
	if edge_socket == null:
		return Transform3D()
	# Flat transform of the foundation (no wave tilt).
	var flat_xf: Transform3D = _get_flat_support_transform(foundation)
	# Edge socket local position — e.g. (0, 0.15, 1) for North, (1, 0.15, 0) for East.
	var socket_local: Vector3 = edge_socket.position
	# Edge-specific rotation: wall width must run ALONG the edge.
	#   North/South edges (socket offset along Z): wall along X → no rotation.
	#   East/West  edges (socket offset along X): wall along Z → rotate 90°.
	# The slide axis is the direction the wall runs along.
	var edge_angle: float = 0.0
	var edge_axis: Vector3 = Vector3(1, 0, 0)
	if absf(socket_local.x) > absf(socket_local.z):
		edge_angle = PI * 0.5
		edge_axis = Vector3(0, 0, 1)
	# Combined rotation = edge rotation + player build_rotation.
	var total_rot: float = edge_angle + build_rotation
	# Slide the wall along the edge to follow the crosshair. `along` is the aim
	# projected onto the edge axis, relative to the edge socket (edge midpoint).
	var local_aim: Vector3 = flat_xf.affine_inverse() * aim_world
	var along: float = local_aim.dot(edge_axis) - socket_local.dot(edge_axis)
	# Clamp to the foundation extent — small inset so the wall's own footprint
	# samples stay on the surface when the wall is slid all the way to a corner.
	var max_slide: float = FOUNDATION_HALF_WIDTH - 0.1
	along = clampf(along, -max_slide, max_slide)
	# World position of the edge socket, slid along the edge axis.
	var target_local: Vector3 = socket_local + edge_axis * along
	var target_flat_pos: Vector3 = flat_xf * target_local
	# Wall Socket_Base local position (bottom center of the wall).
	var wall_base_local: Vector3 = Vector3(0, -1.25, 0)
	var rotated_offset: Vector3 = wall_base_local.rotated(Vector3.UP, total_rot)
	# Wall center = slid edge socket world pos − rotated base offset.
	var piece_center: Vector3 = target_flat_pos - rotated_offset
	# Wall basis = foundation basis rotated by combined angle.
	var piece_basis: Basis = flat_xf.basis.rotated(Vector3.UP, total_rot)
	return Transform3D(piece_basis, piece_center)

# Tile-slot edge placement for Wall/Door/Window on a deck edge (Foundation or
# Raft). Walls are exactly one deck cell wide (2.0m), so each cell's edge can
# hold ONE wall, centered on that cell — aiming anywhere along an edge snaps to
# the slot under the crosshair. If that slot already holds a wall, the ghost
# auto-shifts to the nearest free slot along the same edge line (±1 cell) so
# two walls TILE FLUSH side-by-side instead of overlapping or leaving a gap.
# When nothing nearby is free, returns the aimed slot's transform so the ghost
# still shows RED at the blocked spot (overlap validation runs downstream).
func _solve_wall_edge_tile(deck: Node3D, aim_world: Vector3, edge_name: String) -> Transform3D:
	var sockets_node: Node3D = deck.get_node_or_null("BuildSockets")
	if sockets_node == null:
		return Transform3D()
	var edge_socket: Node3D = sockets_node.get_node_or_null(edge_name)
	if edge_socket == null:
		return Transform3D()
	var flat_xf: Transform3D = _get_flat_support_transform(deck)
	var socket_local: Vector3 = edge_socket.position
	# Edge rotation + slide axis (mirrors _compute_wall_transform).
	var edge_angle: float = 0.0
	var edge_axis: Vector3 = Vector3(1, 0, 0)
	if absf(socket_local.x) > absf(socket_local.z):
		edge_angle = PI * 0.5
		edge_axis = Vector3(0, 0, 1)
	var total_rot: float = edge_angle + build_rotation
	var local_aim: Vector3 = flat_xf.affine_inverse() * aim_world
	var raw_along: float = local_aim.dot(edge_axis) - socket_local.dot(edge_axis)
	# Slot index under the crosshair: deck cells are 2.0m, so slots repeat every
	# 2.0m along the edge, starting at the aimed deck cell's edge midpoint.
	var k0: int = int(roundf(raw_along / 2.0))
	var dir: int = 1 if raw_along >= float(k0) * 2.0 else -1
	var wall_base_local: Vector3 = Vector3(0, -1.25, 0)
	var rotated_offset: Vector3 = wall_base_local.rotated(Vector3.UP, total_rot)
	var piece_basis: Basis = flat_xf.basis.rotated(Vector3.UP, total_rot)
	var fallback: Transform3D = Transform3D()
	# Try the aimed slot first, then walk outward in the aim direction so the
	# ghost continues the wall line naturally: k0, k0±1, k0±2.
	var order: Array[int] = [k0, k0 + dir, k0 - dir, k0 + dir * 2, k0 - dir * 2]
	for k in order:
		var target_local: Vector3 = socket_local + edge_axis * (2.0 * float(k))
		var target_flat_pos: Vector3 = flat_xf * target_local
		var cand: Transform3D = Transform3D(piece_basis, target_flat_pos - rotated_offset)
		if k == k0:
			fallback = cand
		if _wall_edge_slot_taken(cand, edge_axis, deck):
			continue
		if not _validate_wall_footprint(cand).get("valid", false):
			continue
		_diag["wall_tile_k"] = k
		return cand
	return fallback

# True when a placed Wall/Door/Window already occupies the same deck-edge slot
# as the candidate wall (same edge LINE, not merely nearby — corner walls on
# perpendicular edges must stay allowed).
func _wall_edge_slot_taken(cand: Transform3D, edge_axis: Vector3, deck: Node3D) -> bool:
	var ax: Vector2 = Vector2(edge_axis.x, edge_axis.z).normalized()
	var raft: Node3D = _get_raft_node()
	if raft == null:
		return false
	var bp: Node3D = raft.get_node_or_null("BuiltPieces")
	if bp == null:
		return false
	for w in bp.get_children():
		if not (w is Node3D) or w == deck or not is_instance_valid(w):
			continue
		var wn: String = _find_piece_name(w)
		if wn != "Wall" and wn != "Door" and wn != "Window":
			continue
		var d: Vector2 = Vector2(cand.origin.x - w.global_position.x, cand.origin.z - w.global_position.z)
		var along: float = d.dot(ax)
		var perp: Vector2 = d - ax * along
		# Only walls on the SAME floor level conflict — a second-floor wall above
		# a first-floor wall (separated by a roof) may share x/z harmlessly.
		if absf(along) < 1.9 and perp.length() < 0.5 and absf(cand.origin.y - w.global_position.y) < 1.7:
			return true
	return false

# Corner placement: foundation corner touches support corner.
# Always flat — ignores wave tilt.
func _solve_corner_transform(
	corner_socket: BuildSocket,
	_piece_name: String,
	support: Node3D,
) -> Transform3D:
	var flat_xform: Transform3D = _get_flat_support_transform(support)
	var support_pos: Vector3 = flat_xform.origin
	var local_dir: Vector3 = corner_socket.position
	local_dir.y = 0.0
	var sign_x: float = signf(local_dir.x)
	var sign_z: float = signf(local_dir.z)
	if absf(sign_x) < 0.5:
		sign_x = 0.0
	if absf(sign_z) < 0.5:
		sign_z = 0.0
	var half_ext: float = FOUNDATION_HALF_WIDTH
	var cell_half: float = FOUNDATION_HALF_WIDTH
	var corner_offset_local: Vector3 = Vector3(
		sign_x * (cell_half + half_ext),
		0.0,
		sign_z * (cell_half + half_ext)
	)
	var rotated_offset: Vector3 = corner_offset_local.rotated(Vector3.UP, build_rotation)
	var piece_center: Vector3 = support_pos + flat_xform.basis * rotated_offset
	var piece_basis: Basis = flat_xform.basis.rotated(Vector3.UP, build_rotation)
	return Transform3D(piece_basis, piece_center)

# ============================================================
# BUILD SYSTEM — CANDIDATE SELECTION
# ============================================================
# Find the best socket on the support for the given piece type and aim.
func _find_best_socket(
	support_piece: Node3D,
	piece_name: String,
	aim_world_pos: Vector3,
	target_aim_normal: Vector3,
) -> BuildSocket:
	var best_socket: BuildSocket = null
	var best_score: float = -1.0e10
	var aim_dir: Vector3 = target_aim_normal.normalized()
	var sockets_node := support_piece.get_node_or_null("BuildSockets")
	if sockets_node == null:
		return null
	# Use flat transform for consistent distance scoring (no wave tilt)
	var flat_xf: Transform3D = _get_flat_support_transform(support_piece)
	for socket in sockets_node.get_children():
		if socket == null or not is_instance_valid(socket):
			continue
		if socket.is_occupied:
			continue
		if not socket.is_compatible(piece_name):
			continue
		var socket_flat_pos: Vector3 = flat_xf * socket.position
		var dist: float = aim_world_pos.distance_to(socket_flat_pos)
		if dist > SOCKET_SNAP_RADIUS:
			continue
		var socket_dir: Vector3 = _get_socket_world_direction(socket)
		var alignment: float = socket_dir.dot(aim_dir)
		var score: float = alignment * 10.0 - dist
		if score > best_score:
			best_score = score
			best_socket = socket
	if best_socket == null and debug_building:
		var count: int = 0
		var occ_count: int = 0
		var detail: String = ""
		if sockets_node != null:
			count = sockets_node.get_child_count()
			for s in sockets_node.get_children():
				if s is BuildSocket:
					if s.is_occupied:
						occ_count += 1
						detail += "  [OCC] %s\n" % s.name
					elif not s.is_compatible(piece_name):
						detail += "  [INCOMPAT] %s\n" % s.name
					else:
						var sflat: Vector3 = flat_xf * s.position
						var sd: float = aim_world_pos.distance_to(sflat)
						detail += "  [DIST %.2fm] %s\n" % [sd, s.name]
		push_warning("[BUILD] No socket found! Total: %d, Occ: %d, Piece: %s\n%s" % [count, occ_count, piece_name, detail])
	return best_socket

# Find the best reciprocal socket on the new piece.
# The reciprocal must face OPPOSITE to the support socket.
func _find_reciprocal_socket(
	support_socket: BuildSocket,
	new_piece_temp: Node3D,
	effective_support_name: String,
) -> BuildSocket:
	var new_piece_sockets: Array[BuildSocket] = _get_all_sockets(new_piece_temp)
	var best: BuildSocket = null
	var best_score: float = -1.0e10
	# Get support socket direction in its parent piece's local space.
	# Use full 3D direction (do NOT zero Y) so vertical sockets like
	# Wall.Socket_Top (0, 1.25, 0) and Roof.Socket_Base (0, -0.075, 0)
	# are correctly identified as opposite-facing.
	var support_local_dir: Vector3 = support_socket.position
	if support_local_dir.length() > 0.001:
		support_local_dir = support_local_dir.normalized()
	else:
		support_local_dir = Vector3.FORWARD
	# STAIRS STACKING: the reciprocal for a stair is always its Socket_Base — the
	# diagonal sockets defeat the generic opposite-facing scoring, so pick it
	# directly when the support is a stair.
	if effective_support_name == "Stairs":
		for s in new_piece_sockets:
			if s != null and s.name == "Socket_Base" and s.is_compatible("Stairs"):
				return s
	for s in new_piece_sockets:
		if s == null or not is_instance_valid(s):
			continue
		if not s.is_compatible(effective_support_name):
			continue
		var score: float = 0.0
		# Type compatibility score
		if support_socket.socket_type == BuildSocket.SocketType.FOUNDATION_EDGE \
			and s.socket_type == BuildSocket.SocketType.FOUNDATION_EDGE:
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.FOUNDATION_TOP \
			and s.socket_type == BuildSocket.SocketType.WALL_BASE:
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.WALL_TOP \
			and s.socket_type == BuildSocket.SocketType.WALL_BASE:
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.WALL_SIDE \
			and s.socket_type == BuildSocket.SocketType.WALL_SIDE:
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.FOUNDATION_TOP \
			and (s.socket_type == BuildSocket.SocketType.DOOR_SLOT \
				or s.socket_type == BuildSocket.SocketType.WINDOW_SLOT):
			score = 10.0
		elif support_socket.socket_type == BuildSocket.SocketType.WALL_TOP \
			and s.socket_type == BuildSocket.SocketType.WALL_TOP:
			score = 10.0
		else:
			score = 1.0
		# Direction-opposite bonus: reciprocal must face opposite direction.
		# Use full 3D direction so vertical sockets are handled correctly.
		var new_local_dir: Vector3 = s.position
		if new_local_dir.length() > 0.001:
			new_local_dir = new_local_dir.normalized()
		else:
			new_local_dir = Vector3.FORWARD
		var dot: float = support_local_dir.dot(new_local_dir)
		# dot < 0 means opposite facing = correct reciprocal
		# dot ≈ 0 means perpendicular = acceptable for some types
		# dot > 0 means same direction = WRONG
		if dot < -0.5:
			score += 50.0  # Strong bonus for opposite-facing
		elif dot > 0.5:
			score -= 100.0  # Strong penalty for same-direction
		if score > best_score:
			best_score = score
			best = s
	return best

# ============================================================
# BUILD SYSTEM — VALIDATION HELPERS
# ============================================================
var _shape_cache: Dictionary = {}
var _ghost_target_socket: BuildSocket = null
var _ghost_transform: Transform3D
var _ghost_cell: Vector2i = Vector2i(999999, 999999)
var _ghost_support: Node3D = null

func _get_validation_shape(piece_scene: PackedScene) -> Shape3D:
	if _shape_cache.has(piece_scene):
		return _shape_cache[piece_scene]
	var temp: Node3D = piece_scene.instantiate()
	var col := temp.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape: Shape3D
	if col != null and col.shape != null:
		shape = col.shape.duplicate()
	else:
		# Door has no directly-named full panel (its colliders are frame posts +
		# a swing leaf under LeafBody) — use its largest descendant box, which
		# for a closed door is the 1.4x2.15x0.06 leaf.
		shape = _largest_descendant_box(temp)
		if shape == null:
			var bs := BoxShape3D.new()
			bs.size = Vector3(1, 1, 1)
			shape = bs
	temp.queue_free()
	_shape_cache[piece_scene] = shape
	return shape

# Largest-volume BoxShape3D anywhere under the piece (covers split-collider
# pieces like the Door whose shapes live under child bodies/pivots).
func _largest_descendant_box(piece: Node3D) -> BoxShape3D:
	var best: BoxShape3D = null
	var best_v: float = 0.0
	for c: Node in piece.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var b := cs.shape as BoxShape3D
		var v: float = b.size.x * b.size.y * b.size.z
		if v > best_v:
			best_v = v
			best = b
	return best

# ============================================================
# BUILD SYSTEM — FOOTPRINT VALIDATION
# ============================================================
# Check if a node is a valid build surface (Foundation, Raft, or
# a building piece that itself sits on a valid surface).
func _is_build_surface(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var n: Node3D = node
	for _i in range(5):
		if n == null:
			break
		if n.is_in_group("build_surface"):
			return true
		var nm: String = n.name
		if nm.begins_with("Foundation") or nm.begins_with("Raft"):
			return true
		n = n.get_parent() as Node3D
	return false

# RIDs to exclude from wall-footprint support rays: the player, the preview
# ghost, and the piece being edited must never block detection of the buildable
# surface underneath the wall.
func _support_ray_excludes() -> Array[RID]:
	var ex: Array[RID] = [get_rid()]
	if ghost != null and is_instance_valid(ghost):
		ex.append(ghost.get_rid())
	if _editing != null and is_instance_valid(_editing):
		ex.append(_editing.get_rid())
	return ex

# Validate that a wall's bottom footprint is supported by build surfaces.
# Uses center-point priority: if the center ray hits a valid surface, the wall
# is valid. This prevents edge-floating-point misses from causing false INVALID.
func _validate_wall_footprint(wall_xform: Transform3D) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var bottom_center: Vector3 = wall_xform.origin + wall_xform.basis * Vector3(0, -1.25, 0)
	var w_basis: Basis = wall_xform.basis
	var supported_count: int = 0
	var total_count: int = 0
	var foundation_height_sum: float = 0.0
	var foundation_hit_count: int = 0
	# --- Center-point check (highest priority) ---
	var center_supported: bool = false
	var center_ray_o: Vector3 = bottom_center + Vector3.UP * 1.0
	var center_ray_e: Vector3 = bottom_center + Vector3.DOWN * 3.0
	var center_q := PhysicsRayQueryParameters3D.create(center_ray_o, center_ray_e)
	center_q.collision_mask = 1
	center_q.exclude = _support_ray_excludes()
	var center_hit := space_state.intersect_ray(center_q)
	if center_hit:
		var ch_body: Node3D = center_hit.collider as Node3D
		if _is_build_surface(ch_body):
			var ch_diff: float = absf(bottom_center.y - center_hit.position.y)
			if ch_diff <= placement_surface_tolerance:
				center_supported = true
				foundation_height_sum += center_hit.position.y
				foundation_hit_count += 1
	# --- 3x3 grid sampling, counted per width-column ---
	# A wall is centered ON the deck edge: half its thickness hangs off into the
	# water, so only the inner half must rest on the surface. Counting each
	# width-column as supported when ANY of its depth samples hit prevents the
	# over-water half from wrongly invalidating edge placements (raft edges,
	# foundation edges, and walls slid to corners).
	var sample_count: int = 3
	var _sample_positions: Array[Vector3] = []
	var _sample_supported: Array[bool] = []
	for ix in range(sample_count):
		var tx: float = (float(ix) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
		var column_supported: bool = false
		for iz in range(sample_count):
			var tz: float = (float(iz) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			# 40% inset from width edges to avoid floating-point boundary misses
			var local_off: Vector3 = w_basis * Vector3(tx * 0.6, 0.0, tz * 0.06)
			var sample_pos: Vector3 = bottom_center + local_off
			_sample_positions.append(sample_pos)
			var ray_o: Vector3 = sample_pos + Vector3.UP * 1.0
			var ray_e: Vector3 = sample_pos + Vector3.DOWN * 3.0
			var q := PhysicsRayQueryParameters3D.create(ray_o, ray_e)
			q.collision_mask = 1
			q.exclude = _support_ray_excludes()
			var hit := space_state.intersect_ray(q)
			if hit:
				var hb: Node3D = hit.collider as Node3D
				if _is_build_surface(hb):
					var hd: float = absf(bottom_center.y - hit.position.y)
					if hd <= placement_surface_tolerance:
						column_supported = true
						foundation_height_sum += hit.position.y
						foundation_hit_count += 1
			_sample_supported.append(column_supported)
		if column_supported:
			supported_count += 1
		total_count += 1
	# Center support overrides grid result (prevents edge false-negatives)
	if center_supported and supported_count == 0:
		supported_count = 1
	if total_count == 0:
		total_count = 1
	var support_ratio: float = float(supported_count) / float(total_count)
	var valid: bool = center_supported or support_ratio >= minimum_support_ratio
	var foundation_height: float = foundation_height_sum / float(foundation_hit_count) if foundation_hit_count > 0 else 0.0
	_diag["footprint_total"] = total_count
	_diag["footprint_supported"] = supported_count
	_diag["footprint_ratio"] = support_ratio
	_diag["foundation_height"] = foundation_height
	_diag["bottom_height"] = bottom_center.y
	_diag["center_supported"] = center_supported
	_diag["sample_positions"] = _sample_positions
	_diag["sample_supported"] = _sample_supported
	_diag["footprint_cell_size"] = FOUNDATION_WIDTH * 0.5
	return {"valid": valid, "support_ratio": support_ratio, "supported_count": supported_count, "total_count": total_count, "foundation_height": foundation_height}

# Validate that a foundation's bottom footprint is supported.
func _validate_foundation_footprint(found_xform: Transform3D) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var half_w: float = FOUNDATION_HALF_WIDTH
	var sample_count: int = 3
	var supported_count: int = 0
	var total_count: int = 0
	var _sample_positions: Array[Vector3] = []
	var _sample_supported: Array[bool] = []
	for ix in range(sample_count):
		for iz in range(sample_count):
			var tx: float = (float(ix) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			var tz: float = (float(iz) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			var local_off: Vector3 = Vector3(tx * half_w * 0.8, -FOUNDATION_HALF_HEIGHT, tz * half_w * 0.8)
			var sample_pos: Vector3 = found_xform * local_off
			var ray_origin: Vector3 = sample_pos + Vector3.UP * 1.0
			var ray_end: Vector3 = sample_pos + Vector3.DOWN * 3.0
			var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			query.collision_mask = 1
			if ghost != null and is_instance_valid(ghost):
				query.exclude = [ghost.get_rid()]
			var result := space_state.intersect_ray(query)
			total_count += 1
			var sample_ok: bool = false
			if result:
				var hit_body: Node3D = result.collider as Node3D
				if _is_build_surface(hit_body):
					sample_ok = true
					supported_count += 1
			_sample_positions.append(sample_pos)
			_sample_supported.append(sample_ok)
	var support_ratio: float = float(supported_count) / float(total_count) if total_count > 0 else 0.0
	var valid: bool = support_ratio >= minimum_support_ratio
	_diag["footprint_total"] = total_count
	_diag["footprint_supported"] = supported_count
	_diag["footprint_ratio"] = support_ratio
	_diag["sample_positions"] = _sample_positions
	_diag["sample_supported"] = _sample_supported
	_diag["footprint_cell_size"] = FOUNDATION_WIDTH * 0.5
	return {"valid": valid, "support_ratio": support_ratio, "supported_count": supported_count, "total_count": total_count}

# Validate that a roof's bottom corners are supported by build surfaces
# (wall tops, other roofs, foundations). Samples a 3x3 grid on the roof's
# bottom plane and records per-sample results for the build overlay.
func _validate_roof_footprint(roof_xform: Transform3D) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var sample_count: int = 3
	var supported_count: int = 0
	var total_count: int = 0
	var _sample_positions: Array[Vector3] = []
	var _sample_supported: Array[bool] = []
	for ix in range(sample_count):
		for iz in range(sample_count):
			var tx: float = (float(ix) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			var tz: float = (float(iz) / float(sample_count - 1)) * 2.0 - 1.0 if sample_count > 1 else 0.0
			# Bottom plane of the roof (0.15 thick): sample at half thickness below
			# center, inset 40% like the other footprint validators.
			var local_off: Vector3 = Vector3(tx * 0.6, -0.075, tz * 0.6)
			var sample_pos: Vector3 = roof_xform * local_off
			var ray_origin: Vector3 = sample_pos + Vector3.UP * 1.0
			var ray_end: Vector3 = sample_pos + Vector3.DOWN * 3.0
			var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
			query.collision_mask = 1
			if ghost != null and is_instance_valid(ghost):
				query.exclude = [ghost.get_rid()]
			var result := space_state.intersect_ray(query)
			total_count += 1
			var sample_ok: bool = false
			if result:
				var hit_body: Node3D = result.collider as Node3D
				if _is_build_surface(hit_body):
					sample_ok = true
					supported_count += 1
			_sample_positions.append(sample_pos)
			_sample_supported.append(sample_ok)
	# Support ratio from the actual per-cell measurements (matches the overlay
	# grid labels) rather than a raw hit count — the roof overhangs its wall
	# support, so outer cells honestly show partial/0% support.
	var percents: Array = _overlay_sample_percents(_sample_positions, _sample_supported)
	var pct_sum: float = 0.0
	for p in percents:
		pct_sum += p
	var support_ratio: float = pct_sum / (percents.size() * 100.0) if percents.size() > 0 else 0.0
	_diag["footprint_total"] = total_count
	_diag["footprint_supported"] = supported_count
	_diag["footprint_ratio"] = support_ratio
	_diag["sample_positions"] = _sample_positions
	_diag["sample_supported"] = _sample_supported
	_diag["footprint_cell_size"] = 1.0
	return {"valid": support_ratio >= minimum_support_ratio, "support_ratio": support_ratio, "supported_count": supported_count, "total_count": total_count}

func _check_overlap(shape: Shape3D, xform: Transform3D, support: Node3D, extra_skip: Array[Node3D] = []) -> Array[Dictionary]:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = xform
	query.collision_mask = 1
	# Exclude the player and ghost via RID
	var excluded: Array[RID] = [get_rid()]
	if ghost != null and is_instance_valid(ghost):
		excluded.append(ghost.get_rid())
	if _editing != null and is_instance_valid(_editing):
		excluded.append(_editing.get_rid())
	query.exclude = excluded
	# Build set of support + all ancestors to filter out manually
	var skip_bodies: Array = []
	var excl_node: Node3D = support
	while excl_node != null and is_instance_valid(excl_node):
		skip_bodies.append(excl_node)
		excl_node = excl_node.get_parent() as Node3D
	# Also skip extra bodies (e.g. foundation under a wall)
	for extra in extra_skip:
		if extra != null and is_instance_valid(extra) and not skip_bodies.has(extra):
			skip_bodies.append(extra)
	# Also skip the editing piece and all its children
	if _editing != null and is_instance_valid(_editing):
		skip_bodies.append(_editing)
		for c in _editing.get_children():
			if c is Node3D:
				skip_bodies.append(c)
	var results: Array[Dictionary] = []
	var hits := space_state.intersect_shape(query, 8)
	for h in hits:
		var hit_body: Node3D = h.get("collider") as Node3D
		# Skip the support, its ancestors (raft, etc.), and the player
		if hit_body != null and skip_bodies.has(hit_body):
			continue
		var hit_dict: Dictionary = {}
		for key in h.keys():
			hit_dict[key] = h[key]
		results.append(hit_dict)
	return results

# Measure edge gap between two pieces along the connection direction.
# Returns the signed gap: negative = penetration, positive = gap, zero = flush.
# Uses flat support transform to match the flat solver.
func _measure_edge_gap(
	support: Node3D,
	support_socket: BuildSocket,
	new_xform: Transform3D,
	_new_piece_temp: Node3D,
	new_socket: BuildSocket,
) -> float:
	# Use flat support transform for consistent comparison
	var flat_xform: Transform3D = _get_flat_support_transform(support)
	var support_edge: Vector3 = flat_xform * support_socket.position
	var new_socket_world: Vector3 = (new_xform * new_socket.transform).origin
	var gap: float = support_edge.distance_to(new_socket_world)
	# Check if the new piece is on the correct side
	var conn_local: Vector3 = support_socket.position
	conn_local.y = 0.0
	var conn_dir: Vector3 = (flat_xform.basis * conn_local.normalized()).normalized() if conn_local.length() > 0.001 else Vector3.FORWARD
	var to_new: Vector3 = (new_xform.origin - flat_xform.origin).normalized()
	var side_check: float = to_new.dot(conn_dir)
	if side_check < 0.0:
		return -gap
	return gap

# ============================================================
# BUILD SYSTEM — GRID CELL FOUNDATION PLACEMENT
# ============================================================
# Determine which side of the support the player is aiming toward.
# Returns a Vector2i direction: (±1, 0) or (0, ±1) for edges,
# (±1, ±1) for corners, (0, 0) for center.
func _determine_aim_side(support: Node3D, aim_pos: Vector3) -> Vector2i:
	var flat_xf: Transform3D = _get_flat_support_transform(support)
	var inv_xf: Transform3D = flat_xf.affine_inverse()
	var local_aim: Vector3 = inv_xf * aim_pos
	var half_cell: float = FOUNDATION_HALF_WIDTH
	var dx: float = local_aim.x
	var dz: float = local_aim.z
	var side_x: int = 0
	var side_z: int = 0
	# Determine primary direction from local aim offset
	if dx > half_cell * 0.25:
		side_x = 1
	elif dx < -half_cell * 0.25:
		side_x = -1
	if dz > half_cell * 0.25:
		side_z = 1
	elif dz < -half_cell * 0.25:
		side_z = -1
	# If aim is near center, use camera forward projected onto build plane
	if side_x == 0 and side_z == 0:
		var cam_forward: Vector3 = -camera.global_transform.basis.z
		var local_forward: Vector3 = inv_xf.basis * cam_forward
		local_forward.y = 0.0
		if local_forward.length() > 0.01:
			local_forward = local_forward.normalized()
			side_x = int(roundf(local_forward.x))
			side_z = int(roundf(local_forward.z))
	return Vector2i(side_x, side_z)

# Check if a grid cell is structurally supported (has a supported neighbor
# connected via cardinal edge to the raft).
func _is_cell_structurally_supported(cell: Vector2i) -> bool:
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	# The raft anchors the grid: the cell it occupies and every cardinal
	# neighbor is directly supported by it (this lets the FIRST Foundation
	# be placed on or against the raft itself). The raft is located from the
	# scene node — NOT _grid_occupancy, which gets overwritten when the first
	# Foundation is placed on the raft's cell.
	var raft_node: Node3D = _get_raft_node()
	if raft_node != null:
		var raft_cell: Vector2i = _world_to_grid(raft_node.global_position)
		if cell == raft_cell:
			return true
		if absi(cell.x - raft_cell.x) + absi(cell.y - raft_cell.y) == 1:
			return true
	# Start BFS from all occupied cardinal neighbors
	var cardinal: Array[Vector2i] = [
		cell + Vector2i(0, -1), cell + Vector2i(0, 1),
		cell + Vector2i(-1, 0), cell + Vector2i(1, 0),
	]
	for n in cardinal:
		if visited.has(n):
			continue
		if _grid_occupancy.has(n):
			var piece: Node3D = _grid_occupancy[n] as Node3D
			if piece != null and is_instance_valid(piece):
				if piece.name.begins_with("Raft"):
					return true
				visited[n] = true
				queue.append(n)
	# Diagonal neighbors — only count raft
	var diagonal: Array[Vector2i] = [
		cell + Vector2i(-1, -1), cell + Vector2i(1, -1),
		cell + Vector2i(-1, 1), cell + Vector2i(1, 1),
	]
	for n in diagonal:
		if _grid_occupancy.has(n):
			var piece: Node3D = _grid_occupancy[n] as Node3D
			if piece != null and is_instance_valid(piece):
				if piece.name.begins_with("Raft"):
					return true
	# BFS through connected foundations to find raft
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var c_card: Array[Vector2i] = [
			current + Vector2i(0, -1), current + Vector2i(0, 1),
			current + Vector2i(-1, 0), current + Vector2i(1, 0),
		]
		for n in c_card:
			if visited.has(n):
				continue
			if _grid_occupancy.has(n):
				var piece: Node3D = _grid_occupancy[n] as Node3D
				if piece != null and is_instance_valid(piece):
					if piece.name.begins_with("Raft"):
						return true
					visited[n] = true
					queue.append(n)
	return false

# Count how many occupied neighbors a cell has (for scoring).
func _count_supporting_neighbors(cell: Vector2i) -> int:
	var count: int = 0
	var offsets: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0),
	]
	for o in offsets:
		if _grid_occupancy.has(cell + o):
			count += 1
	return count

# Compute the world-space Transform3D for a Foundation at a grid cell.
# This is the SINGLE AUTHORITATIVE cell-to-position formula.
# Every Foundation must be placed using only this function.
func _compute_foundation_transform(cell: Vector2i) -> Transform3D:
	var raft: Node3D = _get_raft_node()
	var flat_xf: Transform3D = _get_flat_support_transform(raft) if raft else Transform3D()
	# Canonical grid formula: local_pos = cell * FOUNDATION_WIDTH/DEPTH
	var local_pos: Vector3 = Vector3(cell.x * FOUNDATION_WIDTH, 0.0, cell.y * FOUNDATION_DEPTH)
	var world_pos: Vector3 = flat_xf * local_pos
	var world_basis: Basis = flat_xf.basis.rotated(Vector3.UP, build_rotation)
	return Transform3D(world_basis, world_pos)

# Find the socket on the support that faces a given candidate cell direction.
# Used by _try_build to know which socket to mark occupied.
func _find_connecting_socket(support: Node3D, candidate_cell: Vector2i) -> BuildSocket:
	var support_cell: Vector2i = _get_piece_cell(support)
	var diff: Vector2i = candidate_cell - support_cell
	var support_sockets: Array[BuildSocket] = _get_all_sockets(support)
	var best: BuildSocket = null
	var best_dot: float = -1.0
	for s in support_sockets:
		if s.socket_type != BuildSocket.SocketType.FOUNDATION_EDGE:
			continue
		var sdir: Vector3 = s.position
		sdir.y = 0.0
		if sdir.length() < 0.001:
			continue
		sdir = sdir.normalized()
		var target_dir: Vector3 = Vector3(float(diff.x), 0.0, float(diff.y)).normalized()
		var dot: float = sdir.dot(target_dir)
		if dot > best_dot:
			best_dot = dot
			best = s
	return best

# Find and verify the socket connection between support and candidate cell.
# Returns the socket position error (0 = perfect alignment).
func _verify_foundation_connection(
	support: Node3D,
	candidate_cell: Vector2i,
	solved: Transform3D,
	temp_piece: Node3D,
) -> float:
	var support_cell: Vector2i = _get_piece_cell(support)
	var diff: Vector2i = candidate_cell - support_cell
	var flat_sf: Transform3D = _get_flat_support_transform(support)
	# Find support socket facing the candidate direction
	var support_sockets: Array[BuildSocket] = _get_all_sockets(support)
	var best_support_socket: BuildSocket = null
	var best_dot: float = -1.0
	for s in support_sockets:
		if s.socket_type != BuildSocket.SocketType.FOUNDATION_EDGE:
			continue
		var sdir: Vector3 = s.position
		sdir.y = 0.0
		if sdir.length() < 0.001:
			continue
		sdir = sdir.normalized()
		var target_dir: Vector3 = Vector3(float(diff.x), 0.0, float(diff.y)).normalized()
		var dot: float = sdir.dot(target_dir)
		if dot > best_dot:
			best_dot = dot
			best_support_socket = s
	if best_support_socket == null:
		return 10.0
	_diag["target_socket_name"] = best_support_socket.name
	_diag["target_socket_pos"] = best_support_socket.global_position
	# Find reciprocal socket on new piece
	var effective_support_name: String = "Foundation"
	if support.name.begins_with("Raft"):
		effective_support_name = "Foundation"
	var reciprocal: BuildSocket = _find_reciprocal_socket(best_support_socket, temp_piece, effective_support_name)
	if reciprocal == null:
		return 10.0
	_diag["new_socket_name"] = reciprocal.name
	# Verify: ghost reciprocal socket position vs support socket position
	var ghost_sockets: Array[BuildSocket] = _get_all_sockets(temp_piece)
	for gs in ghost_sockets:
		if gs.name == reciprocal.name:
			var actual_pos: Vector3 = (solved * gs.transform).origin
			var flat_target: Vector3 = flat_sf * best_support_socket.position
			var err: float = actual_pos.distance_to(flat_target)
			_diag["actual_socket_pos"] = actual_pos
			_diag["socket_position_error"] = err
			return err
	return 10.0


# ============================================================
# ROOF PLANE TILE — foundation-style continuous roof tiling
# ============================================================
# If a roof chain exists near the crosshair, return a placement for the roof
# in the adjacent free cell at that same height (any of the 4 directions).
# Returns an EMPTY dict when no chain/cell applies (caller falls through to
# the wall-top search); otherwise a final resolved placement dict (valid or
# red-blocked) like the other roof branches.
func _resolve_roof_plane_tile(aim_pos: Vector3, _gh: Node3D) -> Dictionary:
	var raft_node: Node3D = _get_raft_node()
	if raft_node == null:
		return {}
	var bp: Node3D = raft_node.get_node_or_null("BuiltPieces")
	if bp == null:
		return {}
	var roofs: Array = []
	for child in bp.get_children():
		if child is Node3D and _find_piece_name(child) == "Roof":
			roofs.append(child)
	if roofs.is_empty():
		return {}
	# Nearest roof chain piece to the crosshair (any level — the aim's level is
	# implied by whichever roof is closest in 2D).
	var anchor: Node3D = null
	var best_d := INF
	for r in roofs:
		var rp: Node3D = r as Node3D
		var d := Vector2(aim_pos.x - rp.global_position.x, aim_pos.z - rp.global_position.z).length()
		if d < best_d:
			best_d = d
			anchor = rp
	if anchor == null or best_d > 6.0:
		return {}
	var plane_y: float = anchor.global_position.y
	# Work in the anchor's own rotated (yaw-only) frame so roof chains tile
	# along their real axes no matter how the wall chain underneath is rotated.
	var anchor_flat: Transform3D = _get_flat_support_transform(anchor)
	var to_local: Basis = anchor_flat.basis.inverse()
	var aim_local: Vector3 = to_local * (aim_pos - anchor.global_position)
	var lx := aim_local.x
	var lz := aim_local.z
	# Aiming basically over the anchor roof's own centre — the roof-to-roof /
	# wall-top branches decide that cell (stack top, RED, etc.) when hit.
	if absf(lx) < 0.55 and absf(lz) < 0.55:
		return {}
	var cell_tol: float = 1.05  # half tile (1.0) + small tolerance
	# Aim over an ALREADY roofed cell at this level -> RED, exactly like
	# foundations never extend from an occupied cell the crosshair is on.
	# (The anchor itself is covered: aim on its surface beyond the 0.55 zone.)
	for r in roofs:
		var rp: Node3D = r as Node3D
		if absf(rp.global_position.y - plane_y) > 0.6:
			continue
		var ro: Vector3 = to_local * (rp.global_position - anchor.global_position)
		if absf(ro.x - lx) <= cell_tol and absf(ro.z - lz) <= cell_tol:
			_diag["invalid_reason"] = "ROOF SLOT OCCUPIED"
			_diag["error_category"] = "COLLISION_ERROR"
			_diag["solved_pos"] = rp.global_position
			_diag["wall_foundation"] = rp.name
			var occ_tf := Transform3D(Basis(Vector3.UP, anchor.global_rotation.y), rp.global_position)
			return {"valid": false, "socket": null, "transform": occ_tf, "support": anchor}
	# New cell: one tile (2m) beyond the anchor along the dominant LOCAL axis,
	# at the same height — foundation-style extension in all 4 directions.
	var local_step := Vector3.ZERO
	if absf(lx) >= absf(lz):
		local_step = Vector3(2.0 if lx >= 0.0 else -2.0, 0.0, 0.0)
	else:
		local_step = Vector3(0.0, 0.0, 2.0 if lz >= 0.0 else -2.0)
	var new_center: Vector3 = anchor.global_position + (anchor_flat.basis * local_step)
	new_center.y = plane_y
	var fail_transform := Transform3D(Basis(Vector3.UP, anchor.global_rotation.y), new_center)
	# Target cell occupied by another roof at this level already?
	for r in roofs:
		var rp: Node3D = r as Node3D
		if absf(rp.global_position.y - plane_y) > 0.6:
			continue
		var ro: Vector3 = to_local * (rp.global_position - anchor.global_position)
		if absf(ro.x - local_step.x) <= cell_tol and absf(ro.z - local_step.z) <= cell_tol:
			_diag["invalid_reason"] = "ROOF SLOT OCCUPIED"
			_diag["error_category"] = "COLLISION_ERROR"
			_diag["solved_pos"] = new_center
			_diag["wall_foundation"] = anchor.name
			return {"valid": false, "socket": null, "transform": fail_transform, "support": anchor}
	# Find the anchor's side socket facing the new cell (free + compatible).
	var side_socket: BuildSocket = null
	var snode: Node3D = anchor.get_node_or_null("BuildSockets")
	if snode != null:
		var face_dir := (new_center - anchor.global_position).normalized()
		var best_side := -1.0
		for s in snode.get_children():
			if not (s is BuildSocket):
				continue
			var bs: BuildSocket = s as BuildSocket
			if bs.is_occupied or not bs.is_compatible("Roof"):
				continue
			if bs.name != "Socket_North" and bs.name != "Socket_South" \
				and bs.name != "Socket_East" and bs.name != "Socket_West":
				continue
			var ws: Vector3 = anchor_flat * bs.position
			var dot := Vector3(ws.x - anchor.global_position.x, 0.0, ws.z - anchor.global_position.z).normalized().dot(face_dir)
			if dot > best_side:
				best_side = dot
				side_socket = bs
	if side_socket == null:
		return {}
	var new_piece_idx_r: int = BUILD_RECIPE_NAMES.find("Roof")
	var temp_r: Node3D = build_pieces[new_piece_idx_r].instantiate()
	var recip_r: BuildSocket = _find_reciprocal_socket(side_socket, temp_r, "Roof")
	var solved_r := Transform3D()
	if recip_r != null:
		solved_r = _solve_socket_transform(side_socket, recip_r.position, anchor)
	else:
		solved_r = Transform3D(Basis(Vector3.UP, anchor.global_rotation.y), new_center)
	temp_r.queue_free()
	_diag["solved_pos"] = solved_r.origin
	_diag["wall_foundation"] = anchor.name
	_diag["target_socket_name"] = side_socket.name
	_diag["roof_plane_tile"] = true
	# Physics overlap sanity: ignore build bodies and the edge-touching anchor;
	# anything else genuinely inside the cell makes this RED.
	var shape_r: Shape3D = _get_validation_shape(build_pieces[new_piece_idx_r])
	var overlap_r := _check_overlap(shape_r, solved_r, anchor)
	var bad_hit := false
	for hit in overlap_r:
		var hb: Node3D = hit.get("collider") as Node3D
		if hb == null or not is_instance_valid(hb):
			continue
		var is_build := false
		var wn: Node = hb
		while wn != null:
			if wn.is_in_group("build_surface"):
				is_build = true
				break
			wn = wn.get_parent()
		if is_build:
			# Only other roofs matter — and only if they truly overlap (the
			# anchor and neighbours only touch edge-to-edge at 2m).
			if _find_piece_name(hb) == "Roof":
				var od := Vector2(solved_r.origin.x - hb.global_position.x, solved_r.origin.z - hb.global_position.z).length()
				if od < 1.5:
					bad_hit = true
					break
			continue
		bad_hit = true
		break
	if bad_hit:
		_diag["invalid_reason"] = "ROOF SLOT OCCUPIED"
		_diag["error_category"] = "COLLISION_ERROR"
		return {"valid": false, "socket": side_socket, "transform": solved_r, "support": anchor}
	_diag["final"] = "VALID"
	return {"valid": true, "socket": side_socket, "transform": solved_r, "support": anchor}


func _resolve_placement(piece_name: String, _hit_point: Vector3) -> Dictionary:
	_diag = {}
	_diag["piece"] = piece_name

	# Shared variables declared before branches to avoid CONFUSABLE_LOCAL_DECLARATION
	var solved: Transform3D = Transform3D()
	var new_piece_idx: int = BUILD_RECIPE_NAMES.find(piece_name)
	var shape: Shape3D = _get_validation_shape(build_pieces[new_piece_idx]) if new_piece_idx >= 0 else null
	var overlap_hits: Array[Dictionary] = []

	# Step 1: Aim — with build plane fallback for empty gaps
	var effective_aim_point: Vector3 = aim_point
	var effective_aim_normal: Vector3 = aim_normal
	var effective_collider: Node3D = aim_collider
	# For Foundation: use structural build plane for targeting.
	# For Wall: use ACTUAL ray hit — the player's crosshair determines which edge.
	if piece_name == "Foundation":
		var deck_y_bp: float = _get_structural_deck_y()
		var ray_o: Vector3 = camera.global_position
		var ray_d: Vector3 = -camera.global_transform.basis.z
		if absf(ray_d.y) > 0.001:
			var t_bp: float = (deck_y_bp - ray_o.y) / ray_d.y
			if t_bp > 0.0 and t_bp < AIM_DISTANCE:
				effective_aim_point = ray_o + ray_d * t_bp
				effective_aim_normal = Vector3.UP
	# Fallback: when ray misses OR hits a non-building object.
	# The crosshair determines the target — NOT nearest Foundation.
	# 1. Intersect the structural build plane to get exact aim position.
	# 2. Convert to grid cell.
	# 3. Look up the Foundation at that cell (or adjacent).
	var _hit_is_build: bool = aim_valid and aim_collider != null \
		and _find_support_piece(aim_collider) != null
	if not _hit_is_build:
		var raft: Node3D = _get_raft_node()
		if raft != null and build_mode:
			var deck_y: float = _get_structural_deck_y()
			var ray_origin: Vector3 = camera.global_position
			var ray_dir: Vector3 = -camera.global_transform.basis.z
			# Calculate build plane intersection (works even for horizontal camera)
			var _bp_t: float = -1.0
			if absf(ray_dir.y) > 0.001:
				_bp_t = (deck_y - ray_origin.y) / ray_dir.y
			else:
				# Horizontal camera: project 10m forward onto build plane
				_bp_t = 10.0
			if _bp_t > 0.0 and _bp_t < AIM_DISTANCE:
				effective_aim_point = ray_origin + ray_dir * _bp_t
				effective_aim_normal = Vector3.UP
				# Direct grid cell lookup — check aim cell + all neighbors
				var _aim_cell_fb: Vector2i = _world_to_grid(effective_aim_point)
				var _fb_foundation: Node3D = null
				var _fb_offsets: Array[Vector2i] = [
					Vector2i(0,0), Vector2i(1,0), Vector2i(-1,0),
					Vector2i(0,1), Vector2i(0,-1),
					Vector2i(1,1), Vector2i(1,-1),
					Vector2i(-1,1), Vector2i(-1,-1),
				]
				for _off in _fb_offsets:
					var _cc: Vector2i = _aim_cell_fb + _off
					if _grid_occupancy.has(_cc):
						var _occ: Node3D = _grid_occupancy[_cc] as Node3D
						if _occ != null and is_instance_valid(_occ):
							var _fb_pn: String = _find_piece_name(_occ)
							if _fb_pn == "Foundation" or _fb_pn == "Raft":
								_fb_foundation = _occ
								break
				if _fb_foundation != null:
					effective_collider = _fb_foundation
					aim_valid = true
					aim_point = effective_aim_point
					aim_normal = effective_aim_normal
					aim_collider = _fb_foundation
					aim_distance = _bp_t
					# else: no Foundation under crosshair — stay invalid (RED)
	if (not aim_valid or effective_collider == null) and piece_name != "Wall" \
		and piece_name != "Roof" and piece_name != "Door" and piece_name != "Window":
		# Walls, Roofs, Doors and Windows handle the aim-less case themselves
		# (deck-plane projection + auto-snap), so they must not bail out here.
		_diag["has_aim"] = false
		_diag["invalid_reason"] = "NO AIM"
		_diag["error_category"] = "AIM_ERROR"
		return {"valid": false}
	_diag["has_aim"] = true
	_diag["aim_pos"] = effective_aim_point
	_diag["aim_norm"] = effective_aim_normal
	if effective_collider != null:
		_diag["aim_collider_name"] = effective_collider.name
	else:
		_diag["aim_collider_name"] = "NONE"

	# Step 2: Support
	# Wall and Roof resolve their own support in their specific sections below.
	# For them, skip the generic support check and let them handle it.
	var support: Node3D = _find_support_piece(effective_collider)
	if support == null and piece_name != "Wall" and piece_name != "Roof" \
		and piece_name != "Door" and piece_name != "Window":
		_diag["invalid_reason"] = "INVALID SUPPORT"
		_diag["error_category"] = "SUPPORT_ERROR"
		return {"valid": false}
	if support != null:
		_diag["support_name"] = support.name
	else:
		_diag["support_name"] = "PENDING"

	# Step 3: Structural support (skip for Wall/Roof/Door/Window — they check
	# their own support in their placement sections below)
	if support != null and piece_name != "Wall" and piece_name != "Roof" \
		and piece_name != "Door" and piece_name != "Window":
		var supported: bool = _is_structurally_supported(support)
		_diag["support_valid"] = supported
		_diag["support_path"] = _get_support_path(support)
		if not supported:
			_diag["invalid_reason"] = "NO STRUCTURAL SUPPORT"
			_diag["error_category"] = "SUPPORT_ERROR"
			return {"valid": false}

	# ============================================================
	# FOUNDATION: Grid-cell-driven placement
	# ============================================================
	if piece_name == "Foundation":
		var found_idx: int = BUILD_RECIPE_NAMES.find("Foundation")
		var found_scene: PackedScene = build_pieces[found_idx]

		# Step 4a: Get support grid cell
		var support_cell: Vector2i = _get_piece_cell(support)
		_diag["support_cell"] = support_cell

		# Step 4b: Determine which side the player is aiming toward
		var aim_side: Vector2i = _determine_aim_side(support, effective_aim_point)
		_diag["aim_side"] = aim_side
		var debug_key: String = "%s_%s_%s_%s" % [support.name, str(support_cell), str(aim_side), piece_name]
		if debug_building and debug_key != _last_debug_key:
			_last_debug_key = debug_key
			print("[FOUNDATION] Support=%s cell=%s aim_side=%s" % [support.name, str(support_cell), str(aim_side)])

		# Step 4c: Generate candidate cells
		# Priority 1: The cell that the aim point directly maps to (gap filling)
		# Priority 2: Support's neighbor cells (edge expansion)
		var candidates: Array[Vector2i] = []
		# Direct aim cell — this is the cell the player is pointing at
		var aim_cell: Vector2i = _world_to_grid(effective_aim_point)
		if not candidates.has(aim_cell):
			candidates.append(aim_cell)
		# Aim side neighbor of the direct aim cell (in case aim hits edge)
		if aim_side != Vector2i.ZERO:
			var aim_side_cell: Vector2i = aim_cell + aim_side
			if not candidates.has(aim_side_cell):
				candidates.append(aim_side_cell)
		# Support's neighbor cells (edge expansion) — always generate,
		# dedup handles overlap with aim_cell.
		if aim_side != Vector2i.ZERO:
			var support_aim: Vector2i = support_cell + aim_side
			if not candidates.has(support_aim):
				candidates.append(support_aim)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = support_cell + offset
			if not candidates.has(c):
				candidates.append(c)
		for offset in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var c: Vector2i = support_cell + offset
			if not candidates.has(c):
				candidates.append(c)
		# Also check neighbors of ALL occupied cells (for gap filling between foundations)
		for occ_cell in _grid_occupancy:
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var c: Vector2i = Vector2i(occ_cell) + offset
				if not candidates.has(c):
					candidates.append(c)

		# Step 4d: Score and pick best candidate
		var best_cell: Vector2i = Vector2i(999999, 999999)
		var best_score: float = -1.0e10
		if debug_building and debug_key != _last_debug_key:
			print("=== FOUNDATION CANDIDATES (support=%s cell=%s) ===" % [str(_diag.get("support_name", "?")), str(support_cell)])
		for c in candidates:
			if _grid_is_blocked(c):
				if debug_building and debug_key != _last_debug_key:
					print("  [%s] REJECTED: OCCUPIED" % str(c))
				continue
			if not _is_cell_structurally_supported(c):
				if debug_building and debug_key != _last_debug_key:
					print("  [%s] REJECTED: NO SUPPORT" % str(c))
				continue
			var world_pos: Vector3 = _grid_to_world(c)
			var dist: float = effective_aim_point.distance_to(world_pos)
			if dist > 6.0:
				if debug_building and debug_key != _last_debug_key:
					print("  [%s] REJECTED: TOO FAR (%.1fm)" % [str(c), dist])
				continue
			var score: float = -dist
			# Priority: exact aim cell gets highest score to prevent preview jumping
			if c == aim_cell:
				score += 100.0
			# Bonus for aimed direction
			if c == support_cell + aim_side:
				score += 5.0
			# Bonus for more supporting neighbors
			var neighbor_count: int = _count_supporting_neighbors(c)
			score += float(neighbor_count) * 2.0
			# Penalty for diagonal-only support
			var is_diagonal: bool = (c.x != support_cell.x and c.y != support_cell.y)
			if is_diagonal and neighbor_count == 0:
				score -= 3.0
			if debug_building and debug_key != _last_debug_key:
				print("  [%s] dist=%.1f neighbors=%d score=%.1f" % [str(c), dist, neighbor_count, score])
			if score > best_score:
				best_score = score
				best_cell = c

		if debug_building and debug_key != _last_debug_key:
			print("  Selected: %s" % str(best_cell))

		if best_cell == Vector2i(999999, 999999):
			_diag["invalid_reason"] = "NO VALID NEIGHBOR CELL"
			_diag["error_category"] = "GRID_ERROR"
			return {"valid": false}

		_diag["target_cell"] = best_cell

		# Step 4e: Compute transform from grid cell
		var found_solved: Transform3D = _compute_foundation_transform(best_cell)
		_diag["solved_pos"] = found_solved.origin

		# Step 4f: Apply to ghost
		if ghost != null:
			ghost.global_transform = found_solved
			ghost.visible = true

		# Step 4f1: Size validation — collision and mesh must match canonical tile
		if ghost != null:
			var col_check: CollisionShape3D = ghost.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if col_check != null and col_check.shape != null and col_check.shape is BoxShape3D:
				var box: BoxShape3D = col_check.shape as BoxShape3D
				_diag["collision_size"] = box.size
				var sz_err_x: float = absf(box.size.x - FOUNDATION_WIDTH)
				var sz_err_z: float = absf(box.size.z - FOUNDATION_DEPTH)
				var sz_err_y: float = absf(box.size.y - FOUNDATION_THICKNESS)
				if sz_err_x > 0.01 or sz_err_z > 0.01 or sz_err_y > 0.01:
					_diag["final"] = "INVALID"
					_diag["invalid_reason"] = "FOUNDATION SIZE MISMATCH: coll=(%.2f,%.2f,%.2f) expected=(%.2f,%.2f,%.2f)" % [box.size.x, box.size.y, box.size.z, FOUNDATION_WIDTH, FOUNDATION_THICKNESS, FOUNDATION_DEPTH]
					_diag["error_category"] = "SIZE_ERROR"
					return {"valid": false}
			# Also verify mesh AABB matches canonical tile
			var stack_check: Array[Node] = ghost.get_children()
			while not stack_check.is_empty():
				var cn: Node = stack_check.pop_back()
				if cn is MeshInstance3D:
					var aabb: AABB = (cn as MeshInstance3D).get_aabb()
					_diag["mesh_size"] = aabb.size
					var msz_x: float = absf(aabb.size.x - FOUNDATION_WIDTH)
					var msz_z: float = absf(aabb.size.z - FOUNDATION_DEPTH)
					var msz_y: float = absf(aabb.size.y - FOUNDATION_THICKNESS)
					if msz_x > 0.01 or msz_z > 0.01 or msz_y > 0.01:
						_diag["final"] = "INVALID"
						_diag["invalid_reason"] = "FOUNDATION MESH SIZE MISMATCH: mesh=(%.2f,%.2f,%.2f) expected=(%.2f,%.2f,%.2f)" % [aabb.size.x, aabb.size.y, aabb.size.z, FOUNDATION_WIDTH, FOUNDATION_THICKNESS, FOUNDATION_DEPTH]
						_diag["error_category"] = "SIZE_ERROR"
						return {"valid": false}
					break  # only check first MeshInstance3D
				for cc in cn.get_children():
					stack_check.append(cc)

		# Step 4f2: Height validation — canonical deck height is the single source of truth
		var structural_deck_y: float = _get_structural_deck_y()
		var foundation_top_y: float = found_solved.origin.y + FOUNDATION_HALF_HEIGHT
		var height_error: float = absf(foundation_top_y - structural_deck_y)
		_diag["foundation_top_y"] = foundation_top_y
		_diag["raft_deck_y"] = structural_deck_y
		_diag["height_error"] = height_error
		if height_error > 0.01:
			_diag["invalid_reason"] = "HEIGHT MISMATCH: %.3fm" % height_error
			_diag["error_category"] = "HEIGHT_ERROR"
			return {"valid": false}

		# Step 4g: Verify socket connection
		var found_piece_temp: Node3D = found_scene.instantiate()
		var socket_err: float = _verify_foundation_connection(support, best_cell, found_solved, found_piece_temp)
		found_piece_temp.queue_free()
		_diag["socket_position_valid"] = socket_err <= 0.1

		# Step 4h: Overlap check
		var found_shape: Shape3D = _get_validation_shape(found_scene)
		var found_overlap := _check_overlap(found_shape, found_solved, support)
		_diag["overlap_valid"] = found_overlap.size() == 0
		_diag["overlap_count"] = found_overlap.size()
		if found_overlap.size() > 0:
			var hit_obj: PhysicsBody3D = found_overlap[0].get("collider") as PhysicsBody3D
			if hit_obj != null and is_instance_valid(hit_obj):
				_diag["overlap_object"] = hit_obj.name
			else:
				_diag["overlap_object"] = "?"
			_diag["invalid_reason"] = "OVERLAP: " + str(_diag.get("overlap_object", "?"))
			_diag["error_category"] = "COLLISION_ERROR"
			return {"valid": false}

		# All checks passed
		_diag["final"] = "VALID"
		# Hard validation: ghost cell must match candidate cell
		var ghost_grid_cell: Vector2i = _world_to_grid(ghost.global_position)
		_diag["ghost_grid_cell"] = ghost_grid_cell
		_diag["cell_match"] = ghost_grid_cell == best_cell
		if ghost_grid_cell != best_cell:
			_diag["final"] = "INVALID"
			_diag["invalid_reason"] = "GHOST CELL MISMATCH: ghost=%s candidate=%s" % [str(ghost_grid_cell), str(best_cell)]
			_diag["error_category"] = "GRID_ERROR"
			return {"valid": false}
		# Hard validation: ghost must be horizontal (not vertical)
		var ghost_x_rot: float = ghost.global_rotation.x
		var ghost_z_rot: float = ghost.global_rotation.z
		_diag["ghost_rot_x"] = rad_to_deg(ghost_x_rot)
		_diag["ghost_rot_z"] = rad_to_deg(ghost_z_rot)
		if absf(ghost_x_rot) > 0.1 or absf(ghost_z_rot) > 0.1:
			_diag["final"] = "INVALID"
			_diag["invalid_reason"] = "FOUNDATION ROTATION INVALID: X=%.1f Z=%.1f" % [rad_to_deg(ghost_x_rot), rad_to_deg(ghost_z_rot)]
			_diag["error_category"] = "ROTATION_ERROR"
			return {"valid": false}
		# Hard validation: Foundation footprint must not overlap any occupied cell.
		# Use the RAFT transform (not support) for consistent grid mapping.
		# Shrink corners slightly to avoid false positives at exact cell boundaries.
		# A 2m Foundation at a 2m cell fills exactly that cell; edge contact with
		# neighbors is valid (touching ≠ overlap).
		var raft_ft: Node3D = _get_raft_node()
		var flat_xf: Transform3D = _get_flat_support_transform(raft_ft) if raft_ft else Transform3D()
		var inv_xf: Transform3D = flat_xf.affine_inverse()
		var half_ext: float = FOUNDATION_HALF_WIDTH
		var grid_eps: float = 0.0001
		var footprint_corners: Array[Vector2i] = []
		var corner_offsets: Array[Vector2] = [
			Vector2(-half_ext + grid_eps, -half_ext + grid_eps),
			Vector2(half_ext - grid_eps, -half_ext + grid_eps),
			Vector2(half_ext - grid_eps, half_ext - grid_eps),
			Vector2(-half_ext + grid_eps, half_ext - grid_eps),
		]
		for co in corner_offsets:
			var world_c: Vector3 = found_solved * Vector3(co.x, 0.0, co.y)
			var local_c: Vector3 = inv_xf * world_c
			var fc: Vector2i = Vector2i(int(roundf(local_c.x / FOUNDATION_WIDTH)), int(roundf(local_c.z / FOUNDATION_DEPTH)))
			if not footprint_corners.has(fc):
				footprint_corners.append(fc)
		_diag["footprint_cells"] = footprint_corners
		var footprint_valid: bool = true
		var overlap_cell: Vector2i = Vector2i.ZERO
		for fc in footprint_corners:
			if fc != best_cell:
				# Footprint extends outside target cell — check if it overlaps an occupied cell
				if _grid_occupancy.has(fc):
					footprint_valid = false
					overlap_cell = fc
					break
		_diag["footprint_valid"] = footprint_valid
		if not footprint_valid:
			_diag["final"] = "INVALID"
			_diag["invalid_reason"] = "FOOTPRINT OVERLAP: cell %s occupied" % str(overlap_cell)
			_diag["error_category"] = "FOOTPRINT_ERROR"
			return {"valid": false}
		if debug_building and ghost != null:
			var mesh_aabb: AABB = AABB()
			var collision_aabb: AABB = AABB()
			var mesh_off: Vector3 = Vector3.ZERO
			# Recursively find MeshInstance3D (may be under MeshPivot)
			var stack: Array[Node] = ghost.get_children()
			while not stack.is_empty():
				var cn: Node = stack.pop_back()
				if cn is MeshInstance3D:
					mesh_aabb = (cn as MeshInstance3D).get_aabb()
					mesh_off = cn.position
				if cn is CollisionShape3D:
					var dbg_col: CollisionShape3D = cn as CollisionShape3D
					if dbg_col.shape is BoxShape3D:
						var box: BoxShape3D = dbg_col.shape as BoxShape3D
						collision_aabb = AABB(-box.size * 0.5, box.size)
						mesh_off = cn.position
				for cc in cn.get_children():
					stack.append(cc)
			_diag["mesh_offset"] = mesh_off
			_diag["mesh_aabb_min"] = ghost.global_transform * mesh_aabb.position
			_diag["mesh_aabb_max"] = ghost.global_transform * (mesh_aabb.position + mesh_aabb.size)
			_diag["collision_size"] = collision_aabb.size
			_diag["ghost_global_pos"] = ghost.global_position
			_diag["ghost_grid_cell"] = ghost_grid_cell
		if debug_building and debug_key != _last_debug_key:
			print("=== FOUNDATION GRID BUILD ===")
			print("  Support: %s cell %s" % [str(_diag.get("support_name", "?")), str(_diag.get("support_cell", Vector2i.ZERO))])
			print("  Target cell: %s" % str(_diag.get("target_cell", Vector2i.ZERO)))
			print("  Solved pos: %s" % str(_diag.get("solved_pos", Vector3.ZERO)))
			print("  Socket err: %s" % str(_diag.get("socket_position_error", -1.0)))
			print("  Overlap: %s" % str(_diag.get("overlap_valid", true)))
			print("  Footprint: %s cells=%s" % [str(_diag.get("footprint_valid", true)), str(_diag.get("footprint_cells", []))])
			print("  Ghost cell: %s match=%s" % [str(_diag.get("ghost_grid_cell", Vector2i.ZERO)), str(_diag.get("cell_match", false))])
			print("  Height: raft=%.3f found=%.3f err=%.3fm" % [_diag.get("raft_deck_y", 0.0), _diag.get("foundation_top_y", 0.0), _diag.get("height_error", 0.0)])
			print("============================")
		# Footprint sampling for the build overlay (visual only — foundation
		# validity itself is decided by the grid/occupancy checks above).
		_validate_foundation_footprint(found_solved)
		# Return with the connecting socket for _try_build
		var connect_socket: BuildSocket = _find_connecting_socket(support, best_cell)
		return {"valid": true, "socket": connect_socket, "transform": found_solved, "cell": best_cell, "support": support}

	# ============================================================
	# WALL: The ghost follows the crosshair EVERYWHERE.
	#   - Aiming at a Foundation/Raft surface -> edge snapping, wall slides along the edge.
	#   - Aiming at a Wall/Door/Window       -> socket placement (wall-to-wall).
	#   - Aiming at open water / no surface  -> RED ghost at the crosshair (deck height).
	# ============================================================
	# Door and Window are wall-sized pieces with wall sockets — they share the
	# Wall solver so they join walls flush (collision touch = join, overlap =
	# red) instead of embedding into a wall's Socket_Middle.
	if piece_name == "Wall" or piece_name == "Door" or piece_name == "Window":
		# ==== Aim: when the ray misses or hits a non-build object, project the
		# crosshair onto the structural deck plane so the ghost follows the aim
		# point instead of jumping to the raft. ====
		var wall_aim: Vector3 = aim_point
		var wall_aim_normal: Vector3 = aim_normal
		var _hit_is_build_wall: bool = aim_valid and aim_collider != null \
			and _find_support_piece(aim_collider) != null
		if not _hit_is_build_wall:
			var _deck_y_wall: float = _get_structural_deck_y()
			var _ro_wall: Vector3 = camera.global_position
			var _rd_wall: Vector3 = -camera.global_transform.basis.z
			var _bp_t_wall: float = -1.0
			if absf(_rd_wall.y) > 0.001:
				_bp_t_wall = (_deck_y_wall - _ro_wall.y) / _rd_wall.y
			else:
				_bp_t_wall = 10.0
			# Clamp: aiming up at the sky (t < 0) or far off the deck plane should
			# NOT send the ghost to the horizon — keep the aim near the structure
			# so the vertical drop can find the surface under the crosshair.
			if _bp_t_wall <= 0.0 or _bp_t_wall >= AIM_DISTANCE:
				_bp_t_wall = 10.0
			wall_aim = _ro_wall + _rd_wall * _bp_t_wall
			wall_aim_normal = Vector3.UP

		var wall_foundation: Node3D = null
		# P1: raycast hit — what the crosshair actually points at. A Roof counts
		# as a wall host ONLY when aimed at its top face (standing on it) — a
		# roof seen from below is a ceiling, not a floor to build on.
		if support != null:
			var _sn: String = _find_piece_name(support)
			if _sn == "Foundation" or _sn == "Raft" or _sn == "Wall" \
				or _sn == "Door" or _sn == "Window" or _is_roof_top_aim(support, wall_aim):
				wall_foundation = support
		# P2a: vertical drop at the (projected) aim — whatever build surface sits
		# directly under the crosshair becomes the support. This covers grazing
		# angles where the main aim ray passes just over the far edge of the deck.
		if wall_foundation == null:
			var _drop_deck_y: float = _get_structural_deck_y()
			var _drop_q := PhysicsRayQueryParameters3D.create(
				Vector3(wall_aim.x, _drop_deck_y + 4.0, wall_aim.z),
				Vector3(wall_aim.x, _drop_deck_y - 4.0, wall_aim.z))
			_drop_q.collision_mask = 1
			var _drop_hit := get_world_3d().direct_space_state.intersect_ray(_drop_q)
			if _drop_hit:
				var _drop_piece: Node3D = _find_support_piece(_drop_hit.get("collider") as Node3D)
				if _drop_piece != null:
					var _dpn: String = _find_piece_name(_drop_piece)
					if _dpn == "Foundation" or _dpn == "Raft" or _dpn == "Wall" \
						or _dpn == "Door" or _dpn == "Window" or _is_roof_top_aim(_drop_piece, wall_aim):
						wall_foundation = _drop_piece
		# P2: nearest surface to the (projected) aim — only when the crosshair is
		#     close enough to snap (otherwise the ghost stays at the aim point).
		if wall_foundation == null:
			var _raft: Node3D = _get_raft_node()
			if _raft != null:
				var _best_d: float = Vector2(wall_aim.x - _raft.global_position.x, wall_aim.z - _raft.global_position.z).length()
				var _best_wall_d: float = INF
				var _best_wall: Node3D = null
				wall_foundation = _raft
				var bp: Node3D = _raft.get_node_or_null("BuiltPieces")
				if bp != null:
					for child in bp.get_children():
						if child is Node3D:
							var _cn: String = _find_piece_name(child)
							if _cn == "Foundation" or _cn == "Raft" or _cn == "Wall" \
								or _cn == "Door" or _cn == "Window":
								var _fd: float = Vector2(wall_aim.x - child.global_position.x, wall_aim.z - child.global_position.z).length()
								if _cn == "Wall" or _cn == "Door" or _cn == "Window":
									if _fd < _best_wall_d:
										_best_wall_d = _fd
										_best_wall = child
								elif _fd < _best_d:
									_best_d = _fd
									wall_foundation = child
				# Prefer a Wall/Door/Window surface over a deck when the wall is
				# within snap range AND not meaningfully farther than the deck —
				# this is what makes the wall ghost auto-snap flush to a
				# neighboring wall (foundation-style preview) instead of falling
				# back to the deck edge and hanging off it.
				if _best_wall != null and _best_wall_d <= WALL_SURFACE_SNAP_RANGE \
					and _best_wall_d <= _best_d + 0.5:
					wall_foundation = _best_wall
				elif _best_d > WALL_SURFACE_SNAP_RANGE:
					wall_foundation = null
		# No surface found near the aim: DO NOT reject yet — the wall's actual
		# bottom FOOTPRINT may still rest on a foundation directly under the
		# crosshair (e.g. the aim ray grazing over the deck edge). The shared
		# footprint validation below samples the wall's real bottom; genuinely
		# unsupported spots (open water, floating above) still come out INVALID
		# there with NO SUPPORT SURFACE / INSUFFICIENT SUPPORT.
		# WALL PREFERENCE: when the current surface resolved to a deck
		# (Foundation/Raft), but a Wall/Door/Window is near the aim and NOT
		# meaningfully farther than the deck, snap to the WALL instead — the
		# ghost auto-joins the wall's side (foundation-style preview near
		# walls) rather than snapping to the deck edge and hanging off it.
		# Exception: when the crosshair sits over a DECK surface (vertical drop
		# hits Foundation/Raft), the player is aiming AT the deck to tile
		# another wall onto the deck's edge slots — the deck path must win so
		# walls tile side-by-side instead of joining/stacking onto the wall
		# that already occupies the aimed slot.
		var _wsn: String = _find_piece_name(wall_foundation)
		if wall_foundation != null and (_wsn == "Foundation" or _wsn == "Raft"):
			var _aim_over_deck0: bool = false
			var _drop_y0: float = _get_structural_deck_y()
			var _dq0 := PhysicsRayQueryParameters3D.create(
				Vector3(wall_aim.x, _drop_y0 + 4.0, wall_aim.z),
				Vector3(wall_aim.x, _drop_y0 - 4.0, wall_aim.z))
			_dq0.collision_mask = 1
			var _dh0 := get_world_3d().direct_space_state.intersect_ray(_dq0)
			if _dh0:
				var _dp0: Node3D = _find_support_piece(_dh0.get("collider") as Node3D)
				if _dp0 != null:
					var _dpn0: String = _find_piece_name(_dp0)
					if _dpn0 == "Foundation" or _dpn0 == "Raft":
						_aim_over_deck0 = true
			if not _aim_over_deck0:
				var _deck_d0: float = Vector2(wall_aim.x - wall_foundation.global_position.x, wall_aim.z - wall_foundation.global_position.z).length()
				var _near_wall0: Node3D = null
				var _near_wall_d0: float = INF
				var _raft0: Node3D = _get_raft_node()
				if _raft0 != null:
					var _bp0: Node3D = _raft0.get_node_or_null("BuiltPieces")
					if _bp0 != null:
						for _ch0 in _bp0.get_children():
							if _ch0 is Node3D:
								var _cn0: String = _find_piece_name(_ch0)
								if _cn0 == "Wall" or _cn0 == "Door" or _cn0 == "Window":
									var _fd0: float = Vector2(wall_aim.x - _ch0.global_position.x, wall_aim.z - _ch0.global_position.z).length()
									if _fd0 < _near_wall_d0:
										_near_wall_d0 = _fd0
										_near_wall0 = _ch0
				if _near_wall0 != null and _near_wall_d0 <= WALL_SURFACE_SNAP_RANGE \
					and _near_wall_d0 <= _deck_d0 + 0.5:
					wall_foundation = _near_wall0
					_wsn = "Wall"
		if _wsn == "Wall" or _wsn == "Door" or _wsn == "Window":
			# SECOND-FLOOR STACKING: aiming at the upper part of a wall's face
			# (top ~40%) places the new wall directly ON TOP (Socket_Top ->
			# Socket_Base) instead of attaching to its side. The old trigger
			# required aiming within 0.6m of the top edge, which is unreachable
			# from standing eye height — so every stack attempt silently fell
			# back to a SIDE attach that nested the new wall into the old one.
			var _w2w_socket: BuildSocket = null
			if _wsn == "Wall" or _wsn == "Door" or _wsn == "Window":
				var _wall_sockets: Node3D = wall_foundation.get_node_or_null("BuildSockets")
				if _wall_sockets != null:
					var _wall_top: BuildSocket = _wall_sockets.get_node_or_null("Socket_Top") as BuildSocket
					if _wall_top != null and _wall_top.is_compatible(piece_name):
						var _wall_top_y: float = (_get_flat_support_transform(wall_foundation) * _wall_top.position).y
						# Aim must be in the upper part of this wall's face: above the
						# wall's mid-height AND within the stack tolerance of the top.
						# Wall bottom from its own Socket_Base (the top socket's
						# counterpart) — robust for stacked walls on any floor.
						var _wall_base_s: BuildSocket = _wall_sockets.get_node_or_null("Socket_Base") as BuildSocket
						var _wall_base_y: float = _wall_top_y
						if _wall_base_s != null:
							_wall_base_y = (_get_flat_support_transform(wall_foundation) * _wall_base_s.position).y
						var _mid_y: float = (_wall_base_y + _wall_top_y) * 0.5
						if wall_aim.y >= _mid_y and wall_aim.y >= _wall_top_y - 1.0 \
							and not _wall_top.is_occupied:
							_w2w_socket = _wall_top
						elif wall_aim.y >= _mid_y and wall_aim.y >= _wall_top_y - 1.0 \
							and _wall_top.is_occupied:
							# Top already stacked — show RED instead of silently
							# side-attaching into the wall below.
							_diag["invalid_reason"] = "STACK OCCUPIED"
							_diag["error_category"] = "COLLISION_ERROR"
							return {"valid": false, "socket": null, "transform": Transform3D(), "support": wall_foundation}
			if _w2w_socket == null:
				_w2w_socket = _find_best_socket(wall_foundation, piece_name, wall_aim, wall_aim_normal)
			if _w2w_socket != null:
				var _wall_idx: int = BUILD_RECIPE_NAMES.find(piece_name)
				var _w2w_temp: Node3D = build_pieces[_wall_idx].instantiate()
				var new_socket: BuildSocket = _find_reciprocal_socket(_w2w_socket, _w2w_temp, _wsn)
				if new_socket != null:
					solved = _solve_socket_transform(_w2w_socket, new_socket.position, wall_foundation)
					_diag["solved_pos"] = solved.origin
					_diag["wall_foundation"] = wall_foundation.name
					_diag["wall_edge"] = _w2w_socket.name
					var wall_shape: Shape3D = _get_validation_shape(build_pieces[_wall_idx])
					# Also skip the foundation under this wall for overlap check
					var _extra_skip_wf: Array[Node3D] = []
					var _raft_wf: Node3D = _get_raft_node()
					if _raft_wf != null:
						var _bp_wf: Node3D = _raft_wf.get_node_or_null("BuiltPieces")
						if _bp_wf != null:
							var _best_wf_d: float = INF
							for _wf_child in _bp_wf.get_children():
								if _wf_child is Node3D and _find_piece_name(_wf_child) == "Foundation":
									var _wf_dist: float = Vector2(wall_foundation.global_position.x - _wf_child.global_position.x, wall_foundation.global_position.z - _wf_child.global_position.z).length()
									if _wf_dist < _best_wf_d:
										_best_wf_d = _wf_dist
										_extra_skip_wf.append(_wf_child)
					var wall_overlap := _check_overlap(wall_shape, solved, wall_foundation, _extra_skip_wf)
					_w2w_temp.queue_free()
					if wall_overlap.size() > 0:
						_diag["invalid_reason"] = "OVERLAPPING WALL"
						_diag["error_category"] = "COLLISION_ERROR"
						return {"valid": false, "socket": _w2w_socket, "transform": solved, "support": wall_foundation}
					_diag["final"] = "VALID"
					return {"valid": true, "socket": _w2w_socket, "transform": solved, "support": wall_foundation}
				else:
					_w2w_temp.queue_free()
			# Socket-based failed — find nearest Foundation for edge-snapping
			var _wf_fb_target: Node3D = null
			if wall_foundation != null:
				var _raft_wfb: Node3D = _get_raft_node()
				if _raft_wfb != null:
					var _best_wfb_d: float = INF
					var _bp_wfb: Node3D = _raft_wfb.get_node_or_null("BuiltPieces")
					if _bp_wfb != null:
						for _wfb_child in _bp_wfb.get_children():
							if _wfb_child is Node3D and (_find_piece_name(_wfb_child) == "Foundation" or _find_piece_name(_wfb_child) == "Raft"):
								var _wfb_d: float = Vector2(wall_foundation.global_position.x - _wfb_child.global_position.x, wall_foundation.global_position.z - _wfb_child.global_position.z).length()
								if _wfb_d < _best_wfb_d:
									_best_wfb_d = _wfb_d
									_wf_fb_target = _wfb_child
			if _wf_fb_target != null:
				wall_foundation = _wf_fb_target
		var _f_sn: String = _find_piece_name(wall_foundation)
		if _f_sn == "Roof" and _is_roof_top_aim(wall_foundation, wall_aim):
			# ROOF TOP: a roof aimed from above is a second-floor deck — walls,
			# doors and windows snap to its edges (and center) exactly like on a
			# Foundation, standing on the roof's TOP face. A roof seen from below
			# (or at its side) is a ceiling and falls through to the deck-plane
			# projection, where the footprint check keeps it invalid.
			var _flat_roof: Transform3D = _get_flat_support_transform(wall_foundation)
			var _roof_local_aim: Vector3 = _flat_roof.affine_inverse() * wall_aim
			var _roof_top_y: float = _flat_roof.origin.y + 0.075
			var _center_zone_r: float = FOUNDATION_HALF_WIDTH * 0.5
			if absf(_roof_local_aim.x) <= _center_zone_r and absf(_roof_local_aim.z) <= _center_zone_r:
				solved = Transform3D(
					Basis(Vector3.UP, build_rotation),
					Vector3(_flat_roof.origin.x, _roof_top_y + 1.25, _flat_roof.origin.z))
				_diag["solved_pos"] = solved.origin
				_diag["wall_foundation"] = wall_foundation.name
				_diag["wall_edge"] = "CENTER"
			else:
				var roof_edge: String = _select_wall_edge(wall_foundation, wall_aim)
				solved = _solve_wall_edge_tile(wall_foundation, wall_aim, roof_edge)
				# Roof edge sockets sit on the slab's MID plane (roof tiling);
				# lift the wall onto the TOP face so its bottom rests flush.
				solved.origin.y += 0.075
				_diag["solved_pos"] = solved.origin
				_diag["wall_foundation"] = wall_foundation.name
				_diag["wall_edge"] = roof_edge
		elif _f_sn == "Foundation" or _f_sn == "Raft":
			# CENTER placement: aiming in the middle zone of a deck piece places
			# the wall upright in the deck CENTER (Foundation.Socket_Top / raft
			# center) instead of snapping to the nearest edge.
			var _flat_wf: Transform3D = _get_flat_support_transform(wall_foundation)
			var _local_aim_wf: Vector3 = _flat_wf.affine_inverse() * wall_aim
			var _center_zone: float = FOUNDATION_HALF_WIDTH * 0.5
			if absf(_local_aim_wf.x) <= _center_zone and absf(_local_aim_wf.z) <= _center_zone:
				var _deck_c: float = _get_structural_deck_y()
				solved = Transform3D(
					Basis(Vector3.UP, build_rotation),
					Vector3(_flat_wf.origin.x, _deck_c + 1.25, _flat_wf.origin.z))
				_diag["solved_pos"] = solved.origin
				_diag["wall_foundation"] = wall_foundation.name
				_diag["wall_edge"] = "CENTER"
			else:
				var edge_name: String = _select_wall_edge(wall_foundation, wall_aim)
				solved = _solve_wall_edge_tile(wall_foundation, wall_aim, edge_name)
				_diag["solved_pos"] = solved.origin
				_diag["wall_foundation"] = wall_foundation.name
				_diag["wall_edge"] = edge_name
		else:
			# Support is not Foundation/Raft (or none found) — project to deck
			# height at the aim point; the footprint check decides validity.
			var deck_y_f: float = _get_structural_deck_y()
			var _f_pos: Vector3 = Vector3(wall_aim.x, deck_y_f + 1.25, wall_aim.z)
			solved = Transform3D(Basis(Vector3.UP, build_rotation), _f_pos)
			_diag["solved_pos"] = solved.origin
			if wall_foundation != null:
				_diag["wall_foundation"] = wall_foundation.name
			else:
				_diag["wall_foundation"] = "NONE"
		# FOOTPRINT VALIDATION: sample 3x3 grid on wall bottom to check support
		var fp_result := _validate_wall_footprint(solved)
		_diag["footprint_total"] = fp_result["total_count"]
		_diag["footprint_supported"] = fp_result["supported_count"]
		_diag["footprint_ratio"] = fp_result["support_ratio"]
		if not fp_result["valid"]:
			if fp_result["supported_count"] <= 0:
				_diag["invalid_reason"] = "NO SUPPORT SURFACE"
				_diag["error_category"] = "SUPPORT_ERROR"
			else:
				_diag["invalid_reason"] = "INSUFFICIENT SUPPORT: %d/%d (%.0f%%)" % [fp_result["supported_count"], fp_result["total_count"], fp_result["support_ratio"] * 100.0]
				_diag["error_category"] = "FOOTPRINT_ERROR"
			return {"valid": false, "socket": null, "transform": solved, "support": wall_foundation}
		# OVERLAP CHECK: reject if a wall already exists at this position
		var _wall_overlap: bool = false
		var _raft_w: Node3D = _get_raft_node()
		if _raft_w != null:
			var _bp_w: Node3D = _raft_w.get_node_or_null("BuiltPieces")
			if _bp_w != null:
				for _w in _bp_w.get_children():
					if _w is Node3D and is_instance_valid(_w) and _w != wall_foundation:
						var _wn: String = _find_piece_name(_w)
						if _wn == "Wall" or _wn == "Door" or _wn == "Window":
							var _wd: float = Vector3(solved.origin.x - _w.global_position.x, 0.0, solved.origin.z - _w.global_position.z).length()
							# Vertical guard: walls on different floors (e.g. above/below
							# a roof) share x/z but are never a conflict.
							if _wd < 0.5 and absf(solved.origin.y - _w.global_position.y) < 1.7:
								_wall_overlap = true
								break
		if _wall_overlap:
			_diag["invalid_reason"] = "OVERLAPPING WALL"
			_diag["error_category"] = "COLLISION_ERROR"
			return {"valid": false, "socket": null, "transform": solved, "support": wall_foundation}
		_diag["final"] = "VALID"
		if wall_foundation != null:
			_diag["support_name"] = wall_foundation.name
		else:
			_diag["support_name"] = "NONE"
		return {"valid": true, "socket": null, "transform": solved, "support": wall_foundation}

	# ============================================================
	# ROOF: TOP_ATTACHMENT — snap to Wall/structural top
	# ============================================================
	if piece_name == "Roof":
		# ROOF AIM FALLBACK: when the aim ray misses (e.g. aiming just over the
		# wall top into the sky, or at a gap), project the crosshair onto the
		# structural deck plane so the wall-top auto-snap below can still find
		# the nearest free Wall top. The roof is a 2x2 slab — the player should
		# never need a pixel-perfect ray hit to place it.
		if not aim_valid or effective_collider == null:
			var _deck_y_r: float = _get_structural_deck_y()
			var _ro_r: Vector3 = camera.global_position
			var _rd_r: Vector3 = -camera.global_transform.basis.z
			var _t_r: float = -1.0
			if absf(_rd_r.y) > 0.001:
				_t_r = (_deck_y_r - _ro_r.y) / _rd_r.y
			else:
				_t_r = 10.0
			if _t_r <= 0.0 or _t_r >= AIM_DISTANCE:
				_t_r = 10.0
			effective_aim_point = _ro_r + _rd_r * _t_r
			effective_aim_normal = Vector3.UP
			effective_collider = null

		# Find the wall or structural support the player is aiming at.
		# The ray hit collider determines the support. Walk up hierarchy.
		var roof_support: Node3D = null
		var roof_target_socket: BuildSocket = null

		# ROOF-TO-ROOF: ray hit an existing Roof — attach the new roof to it
		# (side-by-side expansion via the side sockets, or stacking on top via
		# Socket_Top). This must run FIRST so aiming at a roof never falls
		# through to the "search all walls" fallback and snaps to the wrong
		# wall's top.
		if support != null and _find_piece_name(support) == "Roof":
			# Edge-aware socket choice: the roof is 2x2, so the aim point in the
			# roof's flat space decides the intent. Aim near the CENTER -> stack
			# on top (Socket_Top). Aim near an EDGE -> expand sideways through
			# that edge's side socket. This matches how walls behave (upper face
			# = stack, side = attach) and avoids requiring the player to hit the
			# roof's 0.15m-thin side face.
			var rr_socket: BuildSocket = null
			var rr_flat: Transform3D = _get_flat_support_transform(support)
			var rr_local: Vector3 = rr_flat.affine_inverse() * aim_point
			var rr_sockets_node: Node3D = support.get_node_or_null("BuildSockets")
			var rr_center_zone: float = 0.45  # fraction of half-width
			if rr_sockets_node != null:
				if absf(rr_local.x) <= rr_center_zone and absf(rr_local.z) <= rr_center_zone:
					var rr_top: BuildSocket = rr_sockets_node.get_node_or_null("Socket_Top") as BuildSocket
					if rr_top != null and not rr_top.is_occupied and rr_top.is_compatible("Roof"):
						rr_socket = rr_top
				else:
					var rr_side_name: String = ""
					if absf(rr_local.x) >= absf(rr_local.z):
						rr_side_name = "Socket_East" if rr_local.x >= 0.0 else "Socket_West"
					else:
						rr_side_name = "Socket_North" if rr_local.z >= 0.0 else "Socket_South"
					var rr_side: BuildSocket = rr_sockets_node.get_node_or_null(rr_side_name) as BuildSocket
					if rr_side != null and not rr_side.is_occupied and rr_side.is_compatible("Roof"):
						rr_socket = rr_side
			if rr_socket == null:
				# Aimed roof has no free socket for another roof — show RED
				# instead of silently jumping to a different wall.
				_diag["invalid_reason"] = "ROOF SLOT OCCUPIED"
				_diag["error_category"] = "COLLISION_ERROR"
				return {"valid": false, "socket": null, "transform": Transform3D(), "support": support}
			var rr_idx: int = BUILD_RECIPE_NAMES.find("Roof")
			var rr_temp: Node3D = build_pieces[rr_idx].instantiate()
			var rr_new_socket: BuildSocket = _find_reciprocal_socket(rr_socket, rr_temp, "Roof")
			if rr_new_socket == null:
				rr_temp.queue_free()
				_diag["invalid_reason"] = "MISSING ROOF SOCKET"
				_diag["error_category"] = "TRANSFORM_ERROR"
				return {"valid": false, "socket": rr_socket, "transform": Transform3D(), "support": support}
			solved = _solve_socket_transform(rr_socket, rr_new_socket.position, support)
			_diag["solved_pos"] = solved.origin
			_diag["wall_foundation"] = support.name
			_diag["target_socket_name"] = rr_socket.name
			var rr_shape: Shape3D = _get_validation_shape(build_pieces[rr_idx])
			var rr_overlap := _check_overlap(rr_shape, solved, support)
			rr_temp.queue_free()
			# Allow contact with walls/foundations (build surface), but flag
			# overlap with OTHER roofs or non-build bodies.
			var rr_filtered: Array[Dictionary] = []
			for hit in rr_overlap:
				var hit_body: Node3D = hit.get("collider") as Node3D
				if hit_body == null or not is_instance_valid(hit_body):
					continue
				if _find_piece_name(hit_body) == "Roof":
					rr_filtered.append(hit)
					continue
				var _is_build_rr: bool = false
				var _wn_rr: Node = hit_body
				while _wn_rr != null:
					if _wn_rr.is_in_group("build_surface"):
						_is_build_rr = true
						break
					_wn_rr = _wn_rr.get_parent()
				if not _is_build_rr:
					rr_filtered.append(hit)
			if rr_filtered.size() > 0:
				var hit_obj_rr: Node3D = rr_filtered[0].get("collider") as Node3D
				var rr_obj_name: String = "?"
				if hit_obj_rr != null and is_instance_valid(hit_obj_rr):
					rr_obj_name = hit_obj_rr.name
				_diag["invalid_reason"] = "OVERLAP: " + rr_obj_name
				_diag["error_category"] = "COLLISION_ERROR"
				_validate_roof_footprint(solved)
				return {"valid": false, "socket": rr_socket, "transform": solved, "support": support}
			_validate_roof_footprint(solved)
			_diag["final"] = "VALID"
			return {"valid": true, "socket": rr_socket, "transform": solved, "support": support}

		# Method 1: Ray hit a Wall directly — use ITS Socket_Top. If the top is
		# already occupied (e.g. a 2nd-floor wall), still target this wall so the
		# placement goes RED instead of silently snapping the roof to a DIFFERENT
		# wall the player wasn't aiming at.
		if support != null and _find_piece_name(support) == "Wall":
			var sockets_node := support.get_node_or_null("BuildSockets")
			if sockets_node != null:
				for s in sockets_node.get_children():
					if s is BuildSocket and s.name == "Socket_Top" and s.is_compatible("Roof"):
						roof_target_socket = s
						roof_support = support
						break

		# Method 2: Ray hit something on top of a wall (e.g. another roof)
		# Walk up to find a Wall ancestor with Socket_Top
		if roof_support == null and support != null:
			var walk: Node3D = support
			for _i in range(5):
				if walk == null:
					break
				if _find_piece_name(walk) == "Wall":
					var sn := walk.get_node_or_null("BuildSockets")
					if sn != null:
						for s in sn.get_children():
							if s is BuildSocket and s.name == "Socket_Top" \
								and not s.is_occupied and s.is_compatible("Roof"):
								roof_target_socket = s
								roof_support = walk
								break
				if roof_support != null:
					break
				walk = walk.get_parent() as Node3D

		# PLANE-FILL (foundation-style continuous tiling): if no wall top was
		# targeted directly but a roof chain exists near the crosshair, fill the
		# adjacent free 2x2 cell at that roof's height — in ANY of the 4
		# directions, exactly like foundations tile out across the water. This
		# lets the player roof a whole area from one wall-top anchor without
		# pixel-perfectly hitting each wall's top.
		if roof_support == null:
			var _pf_res := _resolve_roof_plane_tile(effective_aim_point, ghost)
			if not _pf_res.is_empty():
				return _pf_res

		# Method 3: Ray didn't hit a Wall directly — search ALL built
		# pieces, but FIRST honor the wall the crosshair is actually over
		# (its horizontal footprint contains the aim point). Roofs must go on
		# the wall the player is aiming at — never silently jump to another.
		# Walls are NOT in _grid_occupancy (only Foundations are), so
		# we must search the BuiltPieces container where they live.
		if roof_support == null:
			var raft_node: Node3D = _get_raft_node()
			if raft_node != null:
				var bp: Node3D = raft_node.get_node_or_null("BuiltPieces")
				if bp != null:
					var aim_over_wall: Node3D = null
					var aim_over_socket: BuildSocket = null
					for child in bp.get_children():
						if not (child is Node3D):
							continue
						if _find_piece_name(child) != "Wall":
							continue
						var sn: Node3D = child.get_node_or_null("BuildSockets")
						if sn == null:
							continue
						var wall_flat: Transform3D = _get_flat_support_transform(child)
						var wall_local_aim: Vector3 = wall_flat.affine_inverse() * effective_aim_point
						# Aim inside the wall's 2.0 x 0.2 footprint -> this is the aimed wall
						if absf(wall_local_aim.x) <= 1.0 and absf(wall_local_aim.z) <= 0.15:
							for s in sn.get_children():
								if s is BuildSocket and s.name == "Socket_Top" and s.is_compatible("Roof"):
									aim_over_socket = s
									aim_over_wall = child
									break
						if aim_over_wall != null:
							break
					if aim_over_wall != null:
						roof_target_socket = aim_over_socket
						roof_support = aim_over_wall
					else:
						var best_horiz_d: float = 4.0  # generous horizontal search
						for child in bp.get_children():
							if not (child is Node3D):
								continue
							if _find_piece_name(child) != "Wall":
								continue
							var sn: Node3D = child.get_node_or_null("BuildSockets")
							if sn == null:
								continue
							for s in sn.get_children():
								if s is BuildSocket and s.name == "Socket_Top" \
									and not s.is_occupied and s.is_compatible("Roof"):
									var flat_sp: Vector3 = _get_flat_support_transform(child) * s.position
									# Use horizontal distance (ignore Y) since the aim
									# point may be on the Foundation surface far below
									# the Wall top.
									var dx: float = effective_aim_point.x - flat_sp.x
									var dz: float = effective_aim_point.z - flat_sp.z
									var horiz_d: float = sqrt(dx * dx + dz * dz)
									if horiz_d < best_horiz_d:
										best_horiz_d = horiz_d
										roof_target_socket = s
										roof_support = child

		if roof_support == null or roof_target_socket == null:
			_diag["invalid_reason"] = "NO VALID ROOF TARGET"
			_diag["error_category"] = "SUPPORT_ERROR"
			return {"valid": false}
		# A roof needs the TOP of the piece it lands on. If the targeted top is
		# taken by a stacked wall OR a roof, CLIMB to the topmost piece in that
		# column and target ITS top (the roof belongs on the highest surface the
		# player can see — roofs stack on roofs, walls stack on walls).
		var roof_climb: int = 0
		while roof_target_socket.is_occupied and roof_climb < 8:
			var above: Node3D = roof_target_socket.occupying_piece as Node3D
			roof_climb += 1
			if above == null or not is_instance_valid(above):
				break
			var above_pn: String = _find_piece_name(above)
			if above_pn != "Wall" and above_pn != "Roof":
				break
			var sn_above: Node3D = above.get_node_or_null("BuildSockets")
			if sn_above == null:
				break
			var top_above: BuildSocket = sn_above.get_node_or_null("Socket_Top") as BuildSocket
			if top_above == null or not top_above.is_compatible("Roof"):
				break
			roof_target_socket = top_above
			roof_support = above

		# Update roof hysteresis
		_roof_last_support = roof_support
		_diag["wall_foundation"] = roof_support.name
		_diag["target_socket_name"] = roof_target_socket.name
		_diag["target_socket_pos"] = roof_target_socket.global_position

		# Find the reciprocal socket on the Roof: Socket_Base
		if new_piece_idx == -1:
			_diag["invalid_reason"] = "INVALID BUILD SCENE"
			return {"valid": false}
		var roof_scene: PackedScene = build_pieces[new_piece_idx]
		var roof_temp: Node3D = roof_scene.instantiate()
		var roof_base_socket: BuildSocket = null
		for s in _get_all_sockets(roof_temp):
			if s.name == "Socket_Base" and s.is_compatible(_find_piece_name(roof_support)):
				roof_base_socket = s
				break
		if roof_base_socket == null:
			# Fallback: any compatible socket
			for s in _get_all_sockets(roof_temp):
				if s.is_compatible(_find_piece_name(roof_support)):
					roof_base_socket = s
					break
		if roof_base_socket == null:
			_diag["invalid_reason"] = "MISSING ROOF SOCKET"
			roof_temp.queue_free()
			return {"valid": false}

		_diag["new_socket_name"] = roof_base_socket.name

		# Solve: RoofRoot * RoofSocketLocal = TargetSocket
		# RoofRoot = TargetSocket * inverse(RoofSocketLocal)
		solved = _solve_socket_transform(roof_target_socket, roof_base_socket.position, roof_support)
		_diag["solved_pos"] = solved.origin

		# Apply to ghost and verify socket alignment
		if ghost != null:
			ghost.global_transform = solved
			ghost.visible = true

		var roof_flat_target: Vector3 = _get_flat_support_transform(roof_support) * roof_target_socket.position
		# Verify socket alignment from the SOLVED transform — the live ghost's
		# sockets read stale for AnimatableBody3D in the frame the transform is
		# set (Jolt sync), which produced false SOCKET MISMATCH errors.
		var actual_pos: Vector3 = solved * roof_base_socket.position
		var socket_err: float = actual_pos.distance_to(roof_flat_target)
		_diag["actual_socket_pos"] = actual_pos
		_diag["socket_position_error"] = socket_err
		_diag["socket_position_valid"] = socket_err <= 0.1
		if socket_err > 0.1:
			_diag["invalid_reason"] = "SOCKET MISMATCH: " + str(snappedf(socket_err, 0.001)) + "m"
			_diag["error_category"] = "TRANSFORM_ERROR"
			# Footprint sampling for the build overlay (samples the intended spot)
			_validate_roof_footprint(solved)
			roof_temp.queue_free()
			return {"valid": false}

		# Overlap check — exclude the support wall and foundations
		var roof_overlap := _check_overlap(shape, solved, roof_support)
		var roof_filtered: Array[Dictionary] = []
		for hit in roof_overlap:
			var hit_body: Node3D = hit.get("collider") as Node3D
			if hit_body == null or not is_instance_valid(hit_body):
				continue
			# Exclude ANY build-system body via group check
			var _is_build_roof: bool = false
			var _wn_r: Node = hit_body
			while _wn_r != null:
				if _wn_r.is_in_group("build_surface"):
					_is_build_roof = true
					break
				_wn_r = _wn_r.get_parent()
			if _is_build_roof:
				continue
			roof_filtered.append(hit)
		_diag["overlap_valid"] = roof_filtered.size() == 0
		if roof_filtered.size() > 0:
			var hit_obj: PhysicsBody3D = roof_filtered[0].get("collider") as PhysicsBody3D
			if hit_obj != null and is_instance_valid(hit_obj):
				_diag["overlap_object"] = hit_obj.name
			else:
				_diag["overlap_object"] = "?"
			_diag["invalid_reason"] = "OVERLAP: " + str(_diag.get("overlap_object", "?"))
			_diag["error_category"] = "COLLISION_ERROR"
			_validate_roof_footprint(solved)
			roof_temp.queue_free()
			return {"valid": false}

		roof_temp.queue_free()
		# Footprint sampling for the build overlay (visual only — the roof's
		# validity is determined by the socket/overlap checks above).
		_validate_roof_footprint(solved)
		_diag["final"] = "VALID"
		return {"valid": true, "socket": roof_target_socket, "transform": solved, "support": roof_support}

	# ============================================================
	# OTHER NON-FOUNDATION: Socket-based placement (Window, Door, etc.)
	# ============================================================
	# Step 4: Find target socket on the support
	var socket: BuildSocket = null
	# STAIRS STACKING: stairs attach to the TOP of the stair below, so a
	# staircase can climb up to a second floor (or higher).
	if piece_name == "Stairs" and support != null and _find_piece_name(support) == "Stairs":
		var _s_sk: Node3D = support.get_node_or_null("BuildSockets")
		if _s_sk != null:
			var _s_top: BuildSocket = _s_sk.get_node_or_null("Socket_Top") as BuildSocket
			if _s_top != null and not _s_top.is_occupied and _s_top.is_compatible("Stairs"):
				socket = _s_top
	if socket == null:
		socket = _find_best_socket(support, piece_name, effective_aim_point, effective_aim_normal)
	if socket == null:
		_diag["invalid_reason"] = "NO SOCKET"
		_diag["error_category"] = "SOCKET_ERROR"
		return {"valid": false}
	_diag["target_socket_name"] = socket.name
	_diag["target_socket_pos"] = socket.global_position
	if socket.is_occupied:
		_diag["invalid_reason"] = "SOCKET OCCUPIED"
		_diag["error_category"] = "SOCKET_ERROR"
		return {"valid": false}

	# Step 5: Find reciprocal socket on new piece
	if new_piece_idx == -1:
		_diag["invalid_reason"] = "INVALID BUILD SCENE"
		return {"valid": false}
	var new_piece_scene: PackedScene = build_pieces[new_piece_idx]
	var new_piece_temp: Node3D = new_piece_scene.instantiate()
	var support_piece_name: String = _find_piece_name(support)
	var effective_support_name: String = support_piece_name
	if support_piece_name == "Raft":
		effective_support_name = "Foundation"
	var new_piece_socket: BuildSocket = _find_reciprocal_socket(socket, new_piece_temp, effective_support_name)
	if new_piece_socket == null:
		var all_sockets: Array[BuildSocket] = _get_all_sockets(new_piece_temp)
		if not all_sockets.is_empty():
			new_piece_socket = all_sockets[0]
	if new_piece_socket == null:
		_diag["invalid_reason"] = "MISSING SOCKET"
		new_piece_temp.queue_free()
		return {"valid": false}
	_diag["new_socket_name"] = new_piece_socket.name

	# Step 6: Solve transform
	solved = _solve_socket_transform(socket, new_piece_socket.position, support)
	_diag["solved_pos"] = solved.origin

	# Step 7: Apply to ghost and verify socket alignment
	if ghost != null:
		ghost.global_transform = solved
		ghost.visible = true

	var flat_target_pos: Vector3 = _get_flat_support_transform(support) * socket.position
	if ghost != null:
		var ghost_sockets: Array[BuildSocket] = _get_all_sockets(ghost)
		for gs in ghost_sockets:
			if gs.name == new_piece_socket.name:
				# Compute from the solved transform instead of reading the live ghost:
				# a freshly-spawned AnimatableBody3D ghost doesn't reflect its new
				# transform in global reads until the physics sync, which would
				# falsely fail the alignment check on the first preview frame.
				var actual_pos: Vector3 = (solved * gs.transform).origin
				var socket_err: float = actual_pos.distance_to(flat_target_pos)
				_diag["actual_socket_pos"] = actual_pos
				_diag["socket_position_error"] = socket_err
				_diag["socket_position_valid"] = socket_err <= 0.05
				if socket_err > 0.05:
					_diag["invalid_reason"] = "SOCKET MISMATCH: " + str(snappedf(socket_err, 0.001)) + "m"
					_diag["error_category"] = "TRANSFORM_ERROR"
					new_piece_temp.queue_free()
					return {"valid": false}
				break

	# Step 8: Gap / penetration measurement
	var gap: float = _measure_edge_gap(support, socket, solved, new_piece_temp, new_piece_socket)
	_diag["edge_gap"] = gap
	_diag["gap_valid"] = absf(gap) < 0.05
	if absf(gap) >= 0.05:
		if gap < 0.0:
			_diag["invalid_reason"] = "PENETRATION: " + str(snappedf(gap, 0.001)) + "m"
		else:
			_diag["invalid_reason"] = "GAP: " + str(snappedf(gap, 0.001)) + "m"
		_diag["error_category"] = "GEOMETRY_ERROR"
		new_piece_temp.queue_free()
		return {"valid": false}

	# Step 9: Overlap check
	overlap_hits = _check_overlap(shape, solved, support)
	# Filter out build-system bodies (same as Wall/Roof overlap checks)
	var generic_filtered: Array[Dictionary] = []
	for hit in overlap_hits:
		var hit_body: Node3D = hit.get("collider") as Node3D
		if hit_body == null or not is_instance_valid(hit_body):
			continue
		var _is_gen_build: bool = false
		var _wn_g: Node = hit_body
		while _wn_g != null:
			if _wn_g.is_in_group("build_surface"):
				_is_gen_build = true
				break
			_wn_g = _wn_g.get_parent()
		if _is_gen_build:
			continue
		if hit_body.global_position.y < solved.origin.y - 1.0:
			continue
		generic_filtered.append(hit)
	_diag["overlap_valid"] = generic_filtered.size() == 0
	_diag["overlap_count"] = generic_filtered.size()
	if generic_filtered.size() > 0:
		var hit_obj: PhysicsBody3D = generic_filtered[0].get("collider") as PhysicsBody3D
		if hit_obj != null and is_instance_valid(hit_obj):
			_diag["overlap_object"] = hit_obj.name
		else:
			_diag["overlap_object"] = "?"
		_diag["invalid_reason"] = "OVERLAP: " + str(_diag.get("overlap_object", "?"))
		_diag["error_category"] = "COLLISION_ERROR"
		new_piece_temp.queue_free()
		return {"valid": false}

	new_piece_temp.queue_free()

	# All checks passed
	_diag["final"] = "VALID"
	if debug_building and ghost != null:
		var mesh_aabb: AABB = AABB()
		var collision_aabb: AABB = AABB()
		var mesh_off: Vector3 = Vector3.ZERO
		for c in ghost.get_children():
			if c is MeshInstance3D:
				mesh_aabb = c.get_aabb()
				mesh_off = c.position
			if c is CollisionShape3D:
				var dbg_col2: CollisionShape3D = c as CollisionShape3D
				if dbg_col2.shape is BoxShape3D:
					var box: BoxShape3D = dbg_col2.shape as BoxShape3D
					collision_aabb = AABB(-box.size * 0.5, box.size)
					mesh_off = c.position
		_diag["mesh_offset"] = mesh_off
		_diag["mesh_aabb_min"] = ghost.global_transform * mesh_aabb.position
		_diag["mesh_aabb_max"] = ghost.global_transform * (mesh_aabb.position + mesh_aabb.size)
		_diag["collision_size"] = collision_aabb.size
		_diag["ghost_global_pos"] = ghost.global_position
	if debug_building and _diag.get("final", "") == "VALID":
		print("=== BUILD VERIFY ===")
		print("  Solved pos: %s" % str(_diag.get("solved_pos", Vector3.ZERO)))
		print("  Ghost pos:  %s" % str(_diag.get("ghost_global_pos", Vector3.ZERO)))
		print("  Socket err: %s" % str(_diag.get("socket_position_error", -1.0)))
		print("  Mesh AABB:  %s -> %s" % [str(_diag.get("mesh_aabb_min", Vector3.ZERO)), str(_diag.get("mesh_aabb_max", Vector3.ZERO))])
		print("  Mesh off:   %s" % str(_diag.get("mesh_offset", Vector3.ZERO)))
		print("  Coll size:  %s" % str(_diag.get("collision_size", Vector3.ZERO)))
		print("  Support:    %s" % str(_diag.get("support_name", "?")))
		print("  Target:     %s at %s" % [str(_diag.get("target_socket_name", "?")), str(_diag.get("target_socket_pos", Vector3.ZERO))])
		print("  Actual:     %s at %s" % [str(_diag.get("new_socket_name", "?")), str(_diag.get("actual_socket_pos", Vector3.ZERO))])
		print("====================")
	return {"valid": true, "socket": socket, "transform": solved}


# ============================================================
# BUILD SYSTEM — GHOST PREVIEW
# ============================================================
func _update_build_preview() -> void:
	if ghost == null:
		return
	var piece_name: String = BUILD_RECIPE_NAMES[selected_piece_index]
	_ensure_ghost_materials()
	var resolved := _resolve_placement(piece_name, aim_point)
	var is_valid: bool = bool(resolved.get("valid", false))
	# Apply material FIRST — before ghost becomes visible — so it never
	# flashes with the wrong color.
	_apply_ghost_material(is_valid)
	if is_valid:
		var xform: Transform3D = resolved["transform"]
		_ghost_target_socket = resolved["socket"]
		_ghost_cell = resolved.get("cell", Vector2i(999999, 999999))
		_ghost_support = resolved.get("support", null)
		# Only update ghost transform if it actually changed (prevents jitter)
		var pos_delta: float = (xform.origin - _ghost_transform.origin).length()
		var rot_delta: float = xform.basis.get_euler().distance_to(_ghost_transform.basis.get_euler())
		if pos_delta > 0.001 or rot_delta > 0.001 or not build_valid:
			ghost.global_transform = xform
			_ghost_transform = xform
		ghost.visible = true
		build_valid = true
	else:
		# Still show ghost at aim position in RED so player sees where they're aiming
		_ghost_target_socket = null
		_ghost_cell = Vector2i(999999, 999999)
		_ghost_support = null
		build_valid = false
		# Use the transform from resolved result if available
		var fallback_xform: Transform3D = ghost.global_transform
		if resolved.has("transform"):
			fallback_xform = resolved["transform"]
		elif piece_name == "Foundation":
			var raft_fb: Node3D = _get_raft_node()
			if raft_fb != null:
				var aim_cell_fb: Vector2i = _world_to_grid(aim_point)
				fallback_xform = _compute_foundation_transform(aim_cell_fb)
		elif piece_name == "Wall" or piece_name == "Door" or piece_name == "Window":
			# Find nearest Foundation/Raft/Wall and snap wall to its edge
			var _wf_fb: Node3D = null
			var _raft_fb: Node3D = _get_raft_node()
			if _raft_fb != null:
				var _best_fb_d: float = Vector2(aim_point.x - _raft_fb.global_position.x, aim_point.z - _raft_fb.global_position.z).length()
				_wf_fb = _raft_fb
				var bp_fb: Node3D = _raft_fb.get_node_or_null("BuiltPieces")
				if bp_fb != null:
					for child in bp_fb.get_children():
						if child is Node3D:
							var _cn_fb: String = _find_piece_name(child)
							if _cn_fb == "Foundation" or _cn_fb == "Wall" \
								or _cn_fb == "Door" or _cn_fb == "Window":
								var _fd_fb: float = Vector2(aim_point.x - child.global_position.x, aim_point.z - child.global_position.z).length()
								if _fd_fb < _best_fb_d:
									_best_fb_d = _fd_fb
									_wf_fb = child
			if _wf_fb != null:
				var _wf_sn: String = _find_piece_name(_wf_fb)
				if _wf_sn == "Foundation" or _wf_sn == "Raft":
					fallback_xform = _compute_wall_transform(_wf_fb, aim_point)
				else:
					# Wall/Door/Window support — snap to nearest edge at deck height
					var deck_y_wfb: float = _get_structural_deck_y()
					var _wfb_pos: Vector3 = Vector3(aim_point.x, deck_y_wfb + 1.25, aim_point.z)
					fallback_xform = Transform3D(Basis(Vector3.UP, build_rotation), _wfb_pos)
		elif piece_name == "Roof":
			# Show roof ghost near the closest Wall top even when invalid
			# Search BuiltPieces (Walls are NOT in _grid_occupancy)
			var roof_fb_wall: Node3D = null
			var roof_fb_dist: float = 4.0  # horizontal search radius
			var raft_fb: Node3D = _get_raft_node()
			if raft_fb != null:
				var bp_fb: Node3D = raft_fb.get_node_or_null("BuiltPieces")
				if bp_fb != null:
					for child in bp_fb.get_children():
						if not (child is Node3D):
							continue
						if _find_piece_name(child) != "Wall":
							continue
						var sn := child.get_node_or_null("BuildSockets")
						if sn == null:
							continue
						for s in sn.get_children():
							if s is BuildSocket and s.name == "Socket_Top" \
								and not s.is_occupied and s.is_compatible("Roof"):
								var flat_sp: Vector3 = _get_flat_support_transform(child) * s.position
								var dx: float = aim_point.x - flat_sp.x
								var dz: float = aim_point.z - flat_sp.z
								var horiz_d: float = sqrt(dx * dx + dz * dz)
								if horiz_d < roof_fb_dist:
									roof_fb_dist = horiz_d
									roof_fb_wall = child
			if roof_fb_wall != null:
				# Compute roof transform at the nearest wall top
				var fb_sn := roof_fb_wall.get_node_or_null("BuildSockets")
				if fb_sn != null:
					for s in fb_sn.get_children():
						if s is BuildSocket and s.name == "Socket_Top" \
							and not s.is_occupied and s.is_compatible("Roof"):
							var roof_scene_fb: PackedScene = build_pieces[selected_piece_index]
							var roof_temp_fb: Node3D = roof_scene_fb.instantiate()
							var roof_base_fb: BuildSocket = null
							for rs in _get_all_sockets(roof_temp_fb):
								if rs.name == "Socket_Base":
									roof_base_fb = rs
									break
							if roof_base_fb != null:
								fallback_xform = _solve_socket_transform(s, roof_base_fb.position, roof_fb_wall)
							roof_temp_fb.queue_free()
							break
		ghost.global_transform = fallback_xform
		ghost.visible = true
	# Material already applied at the top of this function
	if debug_building:
		_update_debug_markers()
	if build_overlay:
		_update_overlay_markers()

func _ensure_ghost_materials() -> void:
	if _ghost_valid_mat == null:
		_ghost_valid_mat = StandardMaterial3D.new()
		_ghost_valid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_valid_mat.albedo_color = Color(0.1, 1.0, 0.1, 0.85)
		_ghost_valid_mat.no_depth_test = true
		_ghost_valid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _ghost_invalid_mat == null:
		_ghost_invalid_mat = StandardMaterial3D.new()
		_ghost_invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_invalid_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.85)
		_ghost_invalid_mat.no_depth_test = true
		_ghost_invalid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _apply_ghost_material(valid: bool) -> void:
	if ghost == null:
		return
	var mat: StandardMaterial3D = _ghost_valid_mat if valid else _ghost_invalid_mat
	# Recursively find all MeshInstance3D (may be under MeshPivot)
	var stack: Array[Node] = ghost.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).set_surface_override_material(0, mat)
		for c in n.get_children():
			stack.append(c)

# Debug markers: show target socket (blue) and actual ghost socket (yellow)
var _debug_markers_root: Node3D = null
var _debug_target_marker: MeshInstance3D = null
var _debug_actual_marker: MeshInstance3D = null

func _update_debug_markers() -> void:
	if _debug_markers_root == null:
		_debug_markers_root = Node3D.new()
		_debug_markers_root.name = "BuildDebugMarkers"
		get_tree().current_scene.add_child(_debug_markers_root)
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = 0.05
		var blue_mat: StandardMaterial3D = StandardMaterial3D.new()
		blue_mat.albedo_color = Color(0.2, 0.4, 1.0)
		blue_mat.no_depth_test = true
		_debug_target_marker = MeshInstance3D.new()
		_debug_target_marker.mesh = sphere
		_debug_target_marker.set_surface_override_material(0, blue_mat)
		_debug_markers_root.add_child(_debug_target_marker)
		var yellow_mat: StandardMaterial3D = StandardMaterial3D.new()
		yellow_mat.albedo_color = Color(1.0, 1.0, 0.0)
		yellow_mat.no_depth_test = true
		_debug_actual_marker = MeshInstance3D.new()
		_debug_actual_marker.mesh = sphere
		_debug_actual_marker.set_surface_override_material(0, yellow_mat)
		_debug_markers_root.add_child(_debug_actual_marker)
	if _ghost_target_socket != null and _debug_target_marker != null:
		var flat_sf: Transform3D = _get_flat_support_transform(_ghost_target_socket.get_parent_piece())
		var tpos: Vector3 = flat_sf * _ghost_target_socket.position
		_debug_target_marker.global_position = tpos
		_debug_target_marker.visible = true
	else:
		if _debug_target_marker != null:
			_debug_target_marker.visible = false
	if ghost != null and ghost.visible and _debug_actual_marker != null:
		var new_socket_name: String = str(_diag.get("new_socket_name", ""))
		var sockets: Array[BuildSocket] = _get_all_sockets(ghost)
		for gs in sockets:
			if gs.name == new_socket_name:
				_debug_actual_marker.global_position = gs.global_position
				_debug_actual_marker.visible = true
				return
			_debug_actual_marker.visible = false
	else:
		if _debug_actual_marker != null:
			_debug_actual_marker.visible = false

# ============================================================
# BUILD OVERLAY — footprint samples + support ratio (F3)
# ============================================================
var _overlay_markers_root: Node3D = null
var _overlay_cells: Array[MeshInstance3D] = []
var _overlay_labels: Array[Label3D] = []
var _overlay_mat_green: StandardMaterial3D = null
var _overlay_mat_orange: StandardMaterial3D = null
var _overlay_mat_red: StandardMaterial3D = null

func _ensure_overlay_markers(count: int) -> void:
	if _overlay_markers_root == null or not is_instance_valid(_overlay_markers_root):
		_overlay_markers_root = Node3D.new()
		_overlay_markers_root.name = "BuildOverlayMarkers"
		get_tree().current_scene.add_child(_overlay_markers_root)
		_overlay_cells.clear()
		_overlay_labels.clear()
	if _overlay_mat_green == null:
		_overlay_mat_green = StandardMaterial3D.new()
		_overlay_mat_green.albedo_color = Color(0.1, 1.0, 0.1, 0.65)
		_overlay_mat_green.no_depth_test = true
		_overlay_mat_green.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _overlay_mat_orange == null:
		_overlay_mat_orange = StandardMaterial3D.new()
		_overlay_mat_orange.albedo_color = Color(1.0, 0.65, 0.1, 0.65)
		_overlay_mat_orange.no_depth_test = true
		_overlay_mat_orange.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _overlay_mat_red == null:
		_overlay_mat_red = StandardMaterial3D.new()
		_overlay_mat_red.albedo_color = Color(1.0, 0.1, 0.1, 0.65)
		_overlay_mat_red.no_depth_test = true
		_overlay_mat_red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	while _overlay_cells.size() < count:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.04, 1.0)
		m.mesh = box
		# Cell box sits ON the sample point (bottom face at the sample height)
		m.position = Vector3(0, 0.02, 0)
		_overlay_markers_root.add_child(m)
		_overlay_cells.append(m)
		var lab := Label3D.new()
		lab.font_size = 48
		lab.outline_size = 10
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.pixel_size = 0.004
		lab.position = Vector3(0, 0.18, 0)
		lab.modulate = Color(1, 1, 1)
		_overlay_markers_root.add_child(lab)
		_overlay_labels.append(lab)

func _clear_overlay_markers() -> void:
	if _overlay_markers_root != null and is_instance_valid(_overlay_markers_root):
		_overlay_markers_root.queue_free()
	_overlay_markers_root = null
	_overlay_cells.clear()
	_overlay_labels.clear()

# Support percentage for one sample point: measure the gap between the sample
# height and the build surface directly below it (0% when nothing is found).
func _overlay_sample_percent(pos: Vector3, fallback: float) -> float:
	var space_state := get_world_3d().direct_space_state
	var ray_origin: Vector3 = pos + Vector3.UP * 1.0
	var ray_end: Vector3 = pos + Vector3.DOWN * 3.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	query.exclude = _support_ray_excludes()
	var hit := space_state.intersect_ray(query)
	if hit:
		var hb: Node3D = hit.collider as Node3D
		if _is_build_surface(hb):
			var gap: float = pos.y - hit.position.y
			# Sample sits right on the surface -> 100%; gap up to 0.3m scales down.
			var pct: float = clampf(1.0 - (gap - 0.02) / 0.3, 0.0, 1.0)
			if pct >= 0.99:
				return 100.0
			return pct * 100.0
	return 0.0 if fallback < 0.5 else 100.0

# Per-cell support percentage for every recorded sample position. Used by both
# the overlay grid labels and the HUD ratio so they always agree.
func _overlay_sample_percents(positions: Array, supported: Array) -> Array:
	var out: Array = []
	for i in positions.size():
		var is_sup: bool = bool(supported[i]) if i < supported.size() else false
		out.append(_overlay_sample_percent(positions[i], 100.0 if is_sup else 0.0))
	return out

func _update_overlay_markers() -> void:
	if _overlay_markers_root != null and is_instance_valid(_overlay_markers_root):
		for m in _overlay_cells:
			m.visible = false
		for l in _overlay_labels:
			l.visible = false
	if not build_mode or not build_overlay:
		return
	var positions: Array = _diag.get("sample_positions", [])
	var supported: Array = _diag.get("sample_supported", [])
	if positions.is_empty():
		return
	# INVALID resolves leave the ghost at its fallback spot (e.g. deck height)
	# while the recorded samples came from a different solve — recenter the
	# grid on the ghost's VISIBLE position so the overlay always shows where
	# the player actually sees the preview. Valid resolves already sample the
	# correct solve position, so no offset (the ghost may report a stale
	# transform for AnimatableBody3D in the same frame).
	var offset: Vector3 = Vector3.ZERO
	if not build_valid and ghost != null and is_instance_valid(ghost) and positions.size() > 0:
		var sample_origin: Vector3 = positions[0]
		var first_in_ghost_local: Vector3 = ghost.global_transform.affine_inverse() * sample_origin
		if first_in_ghost_local.length() < 3.0:
			offset = ghost.global_position - sample_origin
	var _overlay_percents: Array = _overlay_sample_percents(positions, supported)
	_ensure_overlay_markers(positions.size())
	var cell_size: float = float(_diag.get("footprint_cell_size", FOUNDATION_WIDTH * 0.5))
	for i in positions.size():
		var m: MeshInstance3D = _overlay_cells[i]
		var lab: Label3D = _overlay_labels[i]
		m.global_position = positions[i] + offset
		# Reorient the cell box so it lies flat on the surface (axis-aligned
		# on X/Z, no pitch/roll — grid stays level even over waves)
		m.global_basis = Basis(Vector3.UP, 0.0)
		(m.mesh as BoxMesh).size = Vector3(cell_size, 0.04, cell_size)
		var percents: Array = _overlay_percents
		var pct: float = 0.0
		if i < percents.size():
			pct = percents[i]
		# Cell COLOR follows the placement verdict (green = will build, red =
		# won't), so the overlay never contradicts the build system. The % label
		# still shows the actual surface coverage under that cell.
		if build_valid:
			m.set_surface_override_material(0, _overlay_mat_green)
		else:
			m.set_surface_override_material(0, _overlay_mat_red)
		m.visible = true
		lab.global_position = positions[i] + Vector3.UP * 0.22
		lab.text = "%d%%" % int(roundf(pct))
		lab.visible = true

func _overlay_hud_text() -> String:
	if not build_mode or not build_overlay:
		return ""
	var d: String = ""
	var positions: Array = _diag.get("sample_positions", [])
	var supported: Array = _diag.get("sample_supported", [])
	var tot: int = positions.size()
	var force_red: bool = not build_valid and str(_diag.get("invalid_reason", "")) not in ["", "NO SUPPORT SURFACE", "INSUFFICIENT SUPPORT"]
	d += "\n--- BUILD OVERLAY ---"
	if tot > 0:
		if force_red:
			var sup: int = int(_diag.get("footprint_supported", 0))
			d += "\nSamples: %d/%d supported (%.0f%%)  [placement %s]" % [sup, tot, float(_diag.get("footprint_ratio", 0.0)) * 100.0, str(_diag.get("invalid_reason", "?"))]
		else:
			var percents: Array = _overlay_sample_percents(positions, supported)
			var sum: float = 0.0
			for p in percents:
				sum += p
			var avg: float = sum / percents.size() if percents.size() > 0 else 0.0
			d += "\nCoverage: %.0f%%  (%d cells, 100%% = fully on surface)" % [avg, tot]
	else:
		d += "\nNo footprint samples for this piece"
	if _diag.has("center_supported"):
		d += "\nCenter ray: " + _yn(_diag.get("center_supported", false))
	if _diag.has("bottom_height") and _diag.has("foundation_height"):
		d += "\nBottom: %.3f  Surface: %.3f" % [_diag.get("bottom_height", 0.0), _diag.get("foundation_height", 0.0)]
	if _diag.has("wall_edge") and str(_diag.get("wall_edge", "")) != "":
		d += "\nEdge/Socket: " + str(_diag.get("wall_edge", "?"))
	if _diag.has("wall_foundation"):
		d += "\nSurface piece: " + str(_diag.get("wall_foundation", "?"))
	return d

# ============================================================
# BUILD SYSTEM — TRY BUILD (CONFIRM)
# ============================================================
func _try_build() -> void:
	if not build_valid:
		return
	var piece_name: String = BUILD_RECIPE_NAMES[selected_piece_index]
	# Walls use direct transform, no socket required
	# Walls, Doors and Windows use the direct ghost transform (no socket
	# required) — they are wall-sized pieces placed by the shared Wall solver.
	if piece_name != "Wall" and piece_name != "Door" and piece_name != "Window" \
		and _ghost_target_socket == null:
		return
	if not Inventory.can_afford(piece_name):
		return
	if not Inventory.craft(piece_name):
		return
	var scene: PackedScene = build_pieces[selected_piece_index]
	var piece: Node3D = scene.instantiate()
	# Give every placed piece a unique name — Godot auto-renames duplicate
	# children to "@AnimatableBody3D@n" (class name based), which breaks the
	# name-based piece detection (_find_piece_name etc.) for every piece after
	# the first of its type.
	piece.name = "%s_%d" % [piece_name, piece.get_instance_id()]
	# ALWAYS parent under the actual raft — NOT the socket's parent_raft.
	# When building from a Foundation, get_parent_raft() returns the Foundation
	# (it is in build_surface group). Parenting there causes the piece local
	# transform to be relative to the Foundation, not the raft, shifting the
	# final world position by the Foundation's offset.
	var raft: Node3D = _get_raft_node()
	if raft == null:
		piece.queue_free()
		return
	var container: Node = raft.get_node_or_null("BuiltPieces")
	if container == null:
		container = Node3D.new()
		container.name = "BuiltPieces"
		raft.add_child(container)
	# Disable ALL collision shapes BEFORE adding to tree to prevent pushing the
	# player (some pieces have several, e.g. stairs steps)
	var piece_cols: Array[Node] = piece.find_children("*", "CollisionShape3D", true, false)
	for _pc in piece_cols:
		(_pc as CollisionShape3D).disabled = true
	# Set the piece's transform BEFORE add_child so the physics body enters the
	# space already placed. Setting global_transform right after add would be
	# overwritten by the physics sync for script-animated bodies (e.g. the
	# Door's _physics_process), snapping the piece back to the raft origin.
	# Use the EXACT candidate cell from preview — never recompute from
	# world position, which can drift between preview and E press frames.
	var cell: Vector2i = _ghost_cell
	if cell == Vector2i(999999, 999999):
		# Fallback: recompute from ghost world transform
		var flat_xf: Transform3D = _get_flat_support_transform(raft)
		var inv_xf: Transform3D = flat_xf.affine_inverse()
		var local_pos: Vector3 = inv_xf * _ghost_transform.origin
		cell = Vector2i(int(roundf(local_pos.x / FOUNDATION_WIDTH)), int(roundf(local_pos.z / FOUNDATION_DEPTH)))
	# Place piece — use ghost transform for non-foundations (walls etc.)
	if piece_name == "Foundation":
		# Grid-based: exact formula from cell coordinates
		var raft_local_pos: Vector3 = Vector3(cell.x * FOUNDATION_WIDTH, 0.0, cell.y * FOUNDATION_DEPTH)
		var raft_local_basis: Basis = Basis(Vector3.UP, build_rotation)
		piece.transform = Transform3D(raft_local_basis, raft_local_pos)
	else:
		# Wall/other: use the ghost's preview transform, converted to raft-local
		piece.transform = raft.global_transform.affine_inverse() * _ghost_transform
	container.add_child(piece)
	# Re-enable collision after physics frame settles (prevents pushing player)
	for _pc in piece_cols:
		(_pc as CollisionShape3D).set_deferred("disabled", false)
	piece.add_to_group("build_surface")
	# Link sockets if available (walls use direct transform, no socket)
	if _ghost_target_socket != null:
		_ghost_target_socket.occupy(piece)
		_link_reciprocal_socket(piece, _ghost_target_socket)
	# Register in grid (only foundations — walls/other are edge attachments)
	if piece_name == "Foundation":
		_grid_register(cell, piece)
	# Register buoyancy sample
	var sample: Node = piece.get_node_or_null("SampleMarker")
	if sample == null:
		sample = piece.get_node_or_null("F1")
	if sample != null and raft.has_method("register_sample_point"):
		raft.register_sample_point(sample)
	# Persist the new structure (with infinite resources, craft() never emits
	# `changed`, so the autosave would otherwise never fire for buildings).
	_queue_save()
	if debug_building:
		print("[BUILD] === PRE-BUILD SNAPSHOT ===")
		print("  Preview cell: %s" % str(_ghost_cell))
		print("  Preview world: %s" % str(_ghost_transform.origin))
		print("  Preview socket: %s" % str(_ghost_target_socket.name) if _ghost_target_socket != null else "NULL")
		print("[BUILD] === POST-BUILD SNAPSHOT ===")
		print("  Built cell: %s" % str(cell))
		print("  Piece world: %s" % str(piece.global_position))
		print("  Piece local: %s" % str(piece.position))
		print("  Cell match: %s" % str(_ghost_cell == cell))
		var pos_err: float = piece.global_position.distance_to(_ghost_transform.origin)
		print("  Position error: %.4fm" % pos_err)
		print("[BUILD] Placed %s at cell %s" % [piece_name, str(cell)])
		print("[BUILD] Grid occupancy: %d pieces" % _grid_occupancy.size())
		for key in _grid_occupancy:
			var p: Node3D = _grid_occupancy[key] as Node3D
			var pname: String
			if p != null and is_instance_valid(p):
				pname = p.name
			else:
				pname = "NULL"
			print("  %s -> %s" % [str(key), pname])

func _link_reciprocal_socket(new_piece: Node3D, parent_socket: BuildSocket) -> void:
	var best: BuildSocket = null
	var best_dist: float = 0.35
	var pp: Node3D = parent_socket.get_parent_piece()
	var fp: Transform3D = _get_flat_support_transform(pp) if pp != null else Transform3D()
	var pfp: Vector3 = fp * parent_socket.position
	for s in _get_all_sockets(new_piece):
		var d: float = s.global_position.distance_to(pfp)
		if d < best_dist:
			best_dist = d
			best = s
	if best != null:
		var parent_piece_of_socket := parent_socket.get_parent_piece()
		best.occupy(parent_piece_of_socket if parent_piece_of_socket != null else new_piece)# ============================================================
# BUILD SYSTEM — EDIT SYSTEM
# ============================================================
const RECIPE_REFUND := {
	"Foundation": {"Wood": 5},
	"Wall": {"Wood": 8, "Rope": 1},
	"Roof": {"Wood": 8, "Rope": 1},
	"Stairs": {"Wood": 6, "Rope": 1},
	"Door": {"Wood": 4, "Rope": 1},
	"Window": {"Wood": 3, "Plastic": 1},
}



# Walk up the node hierarchy to find a node with BuildSockets (a building piece).
func _find_editable_target(collider: Node3D) -> Node3D:
	var current: Node = collider
	for _i in range(5):
		if current == null:
			break
		if current is Node3D and current.get_node_or_null("BuildSockets") != null:
			if current.name == "Raft" or current.is_in_group("raft"):
				return null
			if current == ghost:
				return null
			return current as Node3D
		current = current.get_parent()
	return null

# Handle double-click detection for edit mode pickup.
func _handle_double_click_edit() -> void:
	if not aim_valid or aim_collider == null:
		return
	var target := _find_editable_target(aim_collider)
	var now := Time.get_ticks_msec() / 1000.0
	if target != null and _last_clicked_piece == target and (now - _last_click_time) <= DOUBLE_CLICK_TIME:
		# Same piece clicked twice within time — PICK UP
		_start_edit(target)
		_last_clicked_piece = null
		_last_click_time = 0.0
	else:
		# First click or different piece — store and wait
		_last_clicked_piece = target
		_last_click_time = now

# Start editing a building piece.
func _start_edit(target: Node3D) -> void:
	_editing = target
	_edit_original_transform = target.global_transform
	_edit_original_cell = _world_to_grid(target.global_position)
	_edit_valid = false
	_edit_candidate_transform = target.global_transform
	_edit_candidate_cell = _edit_original_cell
	# Disable ALL collision shapes so the piece doesn't block itself while it is
	# dragged (a Door's leaf collider lives on its own child body).
	for c: Node in target.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).disabled = true
	# Unregister from grid — its cell is now free for candidate evaluation
	_grid_unregister(_edit_original_cell)
	# Free sockets this piece occupies
	for s in _get_all_sockets(target):
		if s.is_occupied:
			s.free_socket()
	# Free support sockets that reference this piece (siblings in BuiltPieces)
	var raft: Node3D = _get_raft_node()
	if raft != null:
		var bp: Node3D = raft.get_node_or_null("BuiltPieces")
		if bp != null:
			for sibling in bp.get_children():
				if sibling == target or not (sibling is Node3D):
					continue
				if sibling.get_node_or_null("BuildSockets") == null:
					continue
				for s in _get_all_sockets(sibling):
					if s.is_occupied and s.occupying_piece == target:
						s.free_socket()
	# Apply transparent preview material
	_set_edit_color(_ghost_valid_mat)
	if ghost:
		ghost.visible = false

# Called every frame while editing — update the preview position.
func _update_edit_follow() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	_ensure_ghost_materials()
	var piece_name := _piece_name_from_node(_editing)
	var raft: Node3D = _get_raft_node()
	if raft == null:
		_edit_valid = false
		_set_edit_color(_ghost_invalid_mat)
		return
	# Compute aim point on the structural deck plane
	var deck_y: float = _get_structural_deck_y()
	var ray_o: Vector3 = camera.global_position
	var ray_d: Vector3 = -camera.global_transform.basis.z
	var edit_aim: Vector3 = Vector3.ZERO
	var got_aim: bool = false
	if absf(ray_d.y) > 0.001:
		var t: float = (deck_y - ray_o.y) / ray_d.y
		if t > 0.0 and t < AIM_DISTANCE:
			edit_aim = ray_o + ray_d * t
			got_aim = true
	if not got_aim:
		# Fallback: use current piece position as aim
		edit_aim = _editing.global_position
	# Shared variables for both branches
	var new_xform: Transform3D = Transform3D()
	# --- Foundation: grid-based placement with neighbor search ---
	if piece_name == "Foundation":
		var aim_cell: Vector2i = _world_to_grid(edit_aim)
		# Try aim cell first, then neighbors — find best empty supported cell
		var best_cell: Vector2i = Vector2i(999999, 999999)
		var best_score: float = -1.0e10
		var cells_to_try: Array[Vector2i] = [aim_cell]
		for offset in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			cells_to_try.append(aim_cell + offset)
		for offset in [Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)]:
			cells_to_try.append(aim_cell + offset)
		for c in cells_to_try:
			if _grid_is_occupied(c):
				continue
			var wp: Vector3 = _grid_to_world(c)
			var dist: float = edit_aim.distance_to(wp)
			if dist > 6.0:
				continue
			var score: float = -dist
			if c == aim_cell:
				score += 100.0
			var nc: int = _count_supporting_neighbors(c)
			score += float(nc) * 2.0
			if score > best_score:
				best_score = score
				best_cell = c
		if best_cell.x == 999999:
			# No valid cell found — stay at current position, show invalid
			_edit_valid = false
			_set_edit_color(_ghost_invalid_mat)
			return
		new_xform = _compute_foundation_transform(best_cell)
		# Overlap check — exclude editing piece itself
		var ovl: Shape3D = _largest_descendant_box(_editing) if piece_name == "Door" else null
		if ovl == null:
			var _col0 := _editing.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if _col0 != null:
				ovl = _col0.shape
		if ovl != null:
			var hits := _check_overlap(ovl, new_xform, _editing)
			if hits.size() > 0:
				_edit_valid = false
				_set_edit_color(_ghost_invalid_mat)
				return
		_editing.global_transform = new_xform
		_edit_candidate_transform = new_xform
		_edit_candidate_cell = best_cell
		_edit_valid = true
		_set_edit_color(_ghost_valid_mat)
		return
	# --- Non-foundation: socket-based placement ---
	var support: Node3D = null
	if aim_valid and aim_collider != null:
		support = _find_support_piece(aim_collider)
	if support == null:
		support = raft
	if support == null:
		_edit_valid = false
		_set_edit_color(_ghost_invalid_mat)
		return
	var socket: BuildSocket = _find_best_socket(support, piece_name, edit_aim, Vector3.UP)
	if socket == null:
		_edit_valid = false
		_set_edit_color(_ghost_invalid_mat)
		return
	var reciprocal: BuildSocket = null
	var best_dist: float = 999.0
	for s in _get_all_sockets(_editing):
		if not s.is_compatible(_find_piece_name(support)):
			continue
		var d: float = (s.global_position - socket.global_position).length()
		if d < best_dist:
			best_dist = d
			reciprocal = s
			if best_dist < 0.01:
				break
	if reciprocal == null:
		_edit_valid = false
		_set_edit_color(_ghost_invalid_mat)
		return
	var flat_xform: Transform3D = _get_flat_support_transform(support)
	var target_pos: Vector3 = flat_xform * socket.position
	var offset: Vector3 = reciprocal.position.rotated(Vector3.UP, build_rotation)
	var new_pos: Vector3 = target_pos - flat_xform.basis * offset
	var new_basis: Basis = flat_xform.basis.rotated(Vector3.UP, build_rotation)
	new_xform = Transform3D(new_basis, new_pos)
	# Overlap check — exclude editing piece
	var ovl: Shape3D = _largest_descendant_box(_editing) if piece_name == "Door" else null
	if ovl == null:
		var _col1 := _editing.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if _col1 != null:
			ovl = _col1.shape
	if ovl != null:
		var hits := _check_overlap(ovl, new_xform, _editing)
		if hits.size() > 0:
			_edit_valid = false
			_set_edit_color(_ghost_invalid_mat)
			return
	_editing.global_transform = new_xform
	_edit_candidate_transform = new_xform
	_edit_valid = true
	_set_edit_color(_ghost_valid_mat)

# Confirm edit: place the building at the preview position.
func _confirm_edit() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	if not _edit_valid:
		return
	for c: Node in _editing.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).disabled = false
	_apply_building_color(_editing)
	# Register at new grid cell
	var new_cell: Vector2i = _world_to_grid(_editing.global_position)
	_grid_register(new_cell, _editing)
	# Re-link sockets for non-foundation pieces
	var piece_name := _piece_name_from_node(_editing)
	if piece_name != "Foundation":
		var support: Node3D = null
		if aim_valid and aim_collider != null:
			support = _find_support_piece(aim_collider)
		if support == null:
			support = _get_raft_node()
		if support != null:
			var socket: BuildSocket = _find_best_socket(support, piece_name, aim_point, aim_normal)
			if socket != null:
				socket.occupy(_editing)
				_link_reciprocal_socket(_editing, socket)
	_editing = null
	_queue_save()
	# If still in build mode, restore ghost visibility
	if build_mode and ghost != null:
		ghost.visible = true
		_update_build_preview()

# Cancel edit: restore the building to its original position.
func _cancel_edit() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	# Restore original transform
	_editing.global_transform = _edit_original_transform
	for c: Node in _editing.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).disabled = false
	_apply_building_color(_editing)
	# Re-register at original grid cell
	_grid_register(_edit_original_cell, _editing)
	# Re-link sockets at original position
	var piece_name := _piece_name_from_node(_editing)
	if piece_name != "Foundation":
		var raft := _get_raft_node()
		if raft != null:
			var support: Node3D = null
			var bp: Node3D = raft.get_node_or_null("BuiltPieces")
			if bp != null:
				for sibling in bp.get_children():
					if sibling == _editing or not (sibling is Node3D):
						continue
					if sibling.get_node_or_null("BuildSockets") == null:
						continue
					var d: float = (sibling.global_position - _edit_original_transform.origin).length()
					if d < 5.0:
						support = sibling
						break
				if support == null:
					support = raft
			if support != null:
				var socket: BuildSocket = _find_best_socket(support, piece_name, _edit_original_transform.origin, Vector3.UP)
				if socket != null:
					socket.occupy(_editing)
					_link_reciprocal_socket(_editing, socket)
	# Clear edit state
	_editing = null
	_edit_valid = false
	_queue_save()
	# If still in build mode, restore ghost visibility
	if build_mode and ghost != null:
		ghost.visible = true
		_update_build_preview()

# Remove the edited building and refund resources.
func _remove_editing() -> void:
	if _editing == null or not is_instance_valid(_editing):
		_editing = null
		return
	var building_name := _editing.name
	# Unregister from grid
	var cell: Vector2i = _world_to_grid(_editing.global_position)
	_grid_unregister(cell)
	# Free support sockets that reference this piece
	var raft: Node3D = _get_raft_node()
	if raft != null:
		var bp: Node3D = raft.get_node_or_null("BuiltPieces")
		if bp != null:
			for sibling in bp.get_children():
				if sibling == _editing or not (sibling is Node3D):
					continue
				if sibling.get_node_or_null("BuildSockets") == null:
					continue
				for s in _get_all_sockets(sibling):
					if s.is_occupied and s.occupying_piece == _editing:
						s.free_socket()
	# Refund resources
	for recipe_name in RECIPE_REFUND:
		if building_name.begins_with(recipe_name):
			var refund: Dictionary = RECIPE_REFUND[recipe_name]
			for item in refund:
				Inventory.add(item, refund[item])
			break
	_editing.queue_free()
	_editing = null
	_edit_valid = false
	_queue_save()
	# If still in build mode, restore ghost visibility
	if build_mode and ghost != null:
		ghost.visible = true
		_update_build_preview()

func _set_edit_color(mat: StandardMaterial3D) -> void:
	if _editing == null:
		return
	var stack: Array[Node] = _editing.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).set_surface_override_material(0, mat)
		for c in n.get_children():
			stack.append(c)

func _apply_building_color(obj: Node3D) -> void:
	if obj.name.begins_with("Door") or obj.name.begins_with("Window"):
		var reset_stack: Array[Node] = obj.get_children()
		while not reset_stack.is_empty():
			var n: Node = reset_stack.pop_back()
			if n is MeshInstance3D:
				(n as MeshInstance3D).set_surface_override_material(0, null)
			for c in n.get_children():
				reset_stack.append(c)
		return
	var building_name := obj.name
	var color := Color(0.72, 0.53, 0.30)
	if building_name.begins_with("Wall"):
		color = Color(0.62, 0.43, 0.22)
	elif building_name.begins_with("Stairs"):
		color = Color(0.55, 0.38, 0.20)
	var stack: Array[Node] = obj.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			(n as MeshInstance3D).set_surface_override_material(0, mat)
		for c in n.get_children():
			stack.append(c)

# ============================================================
# BUILD SYSTEM — SCENE VALIDATION
# ============================================================
func _validate_build_scene(scene: PackedScene, scene_name: String) -> void:
	var inst: Node3D = scene.instantiate()
	var errors: Array[String] = []
	if not (inst is Node3D):
		errors.append("Root is not Node3D")
	var has_mesh: bool = false
	for child in inst.get_children():
		if child is MeshInstance3D:
			has_mesh = true
			break
	if not has_mesh:
		errors.append("No MeshInstance3D found")
	var col := inst.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		# The Door's colliders live under ColFrame* / LeafBody (no directly-named
		# full panel) — any descendant CollisionShape3D satisfies the check.
		var desc: Array = inst.find_children("*", "CollisionShape3D", true, false)
		if desc.size() > 0:
			col = desc[0] as CollisionShape3D
	if col == null:
		errors.append("No CollisionShape3D found")
	elif col.shape == null:
		errors.append("CollisionShape3D has no shape")
	var sockets_node := inst.get_node_or_null("BuildSockets")
	if sockets_node == null:
		errors.append("No BuildSockets node")
	else:
		var socket_names: Dictionary = {}
		for c in sockets_node.get_children():
			if c is BuildSocket:
				if socket_names.has(c.name):
					errors.append("Duplicate socket: " + c.name)
				socket_names[c.name] = true
	if errors.size() > 0:
		print("[BUILD ERROR] " + scene_name + ":")
		for e in errors:
			print("  - " + e)
	else:
		print("[BUILD OK] " + scene_name + " validated")
	inst.queue_free()

# ============================================================
# HUD
# ============================================================
func _create_hud() -> void:
	_hud_label = Label.new()
	_hud_label.name = "InventoryHUD"
	_hud_label.add_theme_font_size_override("font_size", 18)
	_hud_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud_label.add_theme_constant_override("shadow_offset_x", 1)
	_hud_label.add_theme_constant_override("shadow_offset_y", 1)
	_hud_label.position = Vector2(15, 15)
	_hud_label.size = Vector2(400, 400)
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(_hud_label)
	_hud_label.visible = not _mobile_ui_active()

## True when the mobile touch UI is active (Android/iOS/web-mobile or the
## desktop F10 preview). The desktop dev label is replaced by the graphical
## mobile HUD then, so it must not stack on top of it.
func _mobile_ui_active() -> bool:
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile"):
		return true
	var mc: Node = get_node_or_null("CanvasLayer/MobileControls")
	return mc != null and bool(mc.get("force_show")) == true

func _update_hud() -> void:
	if _hud_label == null:
		return
	var want_label: bool = not _mobile_ui_active()
	if _hud_label.visible != want_label:
		_hud_label.visible = want_label
	if not want_label:
		return
	var text := ""
	for item_name in Inventory.items:
		var count: int = Inventory.items[item_name]
		if count > 0 or item_name in ["Wood", "Rope", "Plastic", "Metal"]:
			text += item_name + ": " + str(count) + "\n"
	if _editing != null:
		var piece_name: String = _piece_name_from_node(_editing)
		var status := "[VALID]" if _edit_valid else "[INVALID]"
		text += "\n--- EDIT MODE ---"
		text += "\nPiece: " + piece_name
		text += "\nStatus: " + status
		if not _edit_valid and _editing != null:
			text += "\nReason: Aim at empty supported cell"
		text += "\nP=Place  R/Y=Rotate  X=Remove  B=Cancel"
	elif build_mode:
		var recipe_name: String = BUILD_RECIPE_NAMES[selected_piece_index]
		var status := "[INVALID]" if not build_valid else "[VALID]"
		text += "\n--- BUILD MODE ---"
		text += "\nPiece: " + recipe_name
		text += "\nStatus: " + status
		if Inventory.can_afford(recipe_name):
			text += "\nCost: OK"
		else:
			text += "\nCost: NEED MORE"
		text += "\nR/Y=Rotate(90°)  Shift+R=15°  Tab=Switch  P=Place  B=Exit"
		text += "\nF3=Overlay " + ("ON" if build_overlay else "OFF")
		if build_overlay:
			text += _overlay_hud_text()
		elif debug_building and _diag.size() > 0:
			text += _format_debug_hud()
		else:
			# Always show footprint info and reason when available
			if _diag.has("footprint_ratio"):
				var _fp_r: float = _diag["footprint_ratio"]
				var _fp_s: int = int(_diag.get("footprint_supported", 0))
				var _fp_t: int = int(_diag.get("footprint_total", 0))
				text += "\nSupport: %d/%d (%.0f%%)" % [_fp_s, _fp_t, _fp_r * 100.0]
			if _diag.has("wall_foundation"):
				text += "\nSurface: " + str(_diag["wall_foundation"])
			if not build_valid and _diag.size() > 0:
				var reason: String = str(_diag.get("invalid_reason", ""))
				if reason == "":
					reason = str(_diag.get("final", "UNKNOWN"))
				if reason != "":
					text += "\nReason: " + reason
	# Only re-set the label when the text actually changed — re-assigning an
	# identical string forces a full text re-layout every frame on the UI
	# thread (expensive on low-end mobile), even when nothing changed.
	if text != _last_hud_text:
		_last_hud_text = text
		_hud_label.text = text

func _format_debug_hud() -> String:
	var d: String = ""
	d += "\n--- BUILD DEBUG ---"
	d += "\nPiece: " + str(_diag.get("piece", "?"))
	d += "\nAim: " + _yn(_diag.get("has_aim", false))
	if bool(_diag.get("has_aim", false)):
		d += "\n  Pos: " + str(_diag.get("aim_pos", Vector3.ZERO))
		d += "\n  Normal: " + str(_diag.get("aim_norm", Vector3.FORWARD))
		d += "\n  Collider: " + str(_diag.get("aim_collider_name", "?"))
	d += "\nSupport: " + str(_diag.get("support_name", "NONE"))
	if _diag.has("support_cell"):
		d += "\n  Cell: " + str(_diag.get("support_cell", Vector2i.ZERO))
	d += "\n  Path: " + _fmt_path(_diag.get("support_path", []))
	d += "\n  Valid: " + _yn(_diag.get("support_valid", false))
	if _diag.has("aim_side"):
		d += "\nAim Side: " + str(_diag.get("aim_side", Vector2i.ZERO))
	if _diag.has("target_cell"):
		d += "\nTarget Cell: " + str(_diag.get("target_cell", Vector2i.ZERO))
	d += "\nTarget Socket: " + str(_diag.get("target_socket_name", "NONE"))
	if _diag.has("target_socket_pos"):
		d += "\n  Pos: " + str(_diag.get("target_socket_pos", Vector3.ZERO))
	d += "\nNew Socket: " + str(_diag.get("new_socket_name", "NONE"))
	d += "\nSolved Pos: " + str(_diag.get("solved_pos", Vector3.ZERO))
	d += "\nSocket Error: " + str(_diag.get("socket_position_error", -1.0)) + "m"
	d += "\nEdge Gap: " + str(_diag.get("edge_gap", 0.0)) + "m"
	d += "\nOverlap: " + _yn(not bool(_diag.get("overlap_valid", true)))
	if int(_diag.get("overlap_count", 0)) > 0:
		d += "\n  Blocked by: " + str(_diag.get("overlap_object", "?"))
	d += "\nCorner: " + _yn(_diag.get("is_corner", false))
	var final_val: String = str(_diag.get("final", "INVALID"))
	var reason: String = str(_diag.get("invalid_reason", ""))
	d += "\nFinal: " + final_val
	if reason != "":
		d += "\nReason: " + reason
	var cat: String = str(_diag.get("error_category", ""))
	if cat != "":
		d += "\nCategory: " + cat
	# Tile dimension diagnostics
	d += "\n--- TILE DIMENSIONS ---"
	d += "\nTile: %.2f x %.2f x %.2f" % [FOUNDATION_WIDTH, FOUNDATION_DEPTH, FOUNDATION_THICKNESS]
	if _diag.has("collision_size"):
		var csz: Vector3 = _diag["collision_size"]
		d += "\nColl: %.2f x %.2f x %.2f" % [csz.x, csz.z, csz.y]
		var cx: float = absf(csz.x - FOUNDATION_WIDTH)
		var cz: float = absf(csz.z - FOUNDATION_DEPTH)
		var cy: float = absf(csz.y - FOUNDATION_THICKNESS)
		if cx > 0.01 or cz > 0.01 or cy > 0.01:
			d += "\n  ** SIZE MISMATCH **"
	if _diag.has("mesh_size"):
		var msz: Vector3 = _diag["mesh_size"]
		d += "\nMesh: %.2f x %.2f x %.2f" % [msz.x, msz.z, msz.y]
	# Geometry diagnostics
	if _diag.has("ghost_global_pos"):
		d += "\nGhost Pos: " + str(_diag.get("ghost_global_pos", Vector3.ZERO))
	if _diag.has("ghost_grid_cell"):
		d += "\nGhost Cell: " + str(_diag.get("ghost_grid_cell", Vector2i.ZERO))
	if _diag.has("cell_match"):
		d += "\nCell Match: " + _yn(_diag.get("cell_match", false))
	if _diag.has("footprint_valid"):
		d += "\nFootprint: " + _yn(_diag.get("footprint_valid", false))
	if _diag.has("footprint_cells"):
		d += "\n  Cells: " + str(_diag.get("footprint_cells", []))
	if _diag.has("ghost_rot_x"):
		d += "\nGhost Rot X: " + str(_diag.get("ghost_rot_x", 0.0)) + " deg"
		d += "\nGhost Rot Z: " + str(_diag.get("ghost_rot_z", 0.0)) + " deg"
	if _diag.has("mesh_aabb_min"):
		d += "\nMesh AABB: " + str(_diag.get("mesh_aabb_min", Vector3.ZERO)) + " -> " + str(_diag.get("mesh_aabb_max", Vector3.ZERO))
	if _diag.has("actual_socket_pos"):
		d += "\nActual Socket: " + str(_diag.get("actual_socket_pos", Vector3.ZERO))
	if _diag.has("foundation_top_y"):
		d += "\nFoundation Top: %.3f" % _diag.get("foundation_top_y", 0.0)
		d += "\nDeck Height: %.3f" % _diag.get("raft_deck_y", 0.0)
		d += "\nHeight Error: %.3fm" % _diag.get("height_error", 0.0)
	return d

static func _yn(val: Variant) -> String:
	return "YES" if val else "NO"

static func _fmt_path(path_arr: Variant) -> String:
	if path_arr is Array:
		var arr: Array = path_arr as Array
		if arr.is_empty():
			return "NONE"
		return " -> ".join(arr)
	return "NONE"

```

### `res://build_socket.gd`

```gdscript
extends Marker3D
class_name BuildSocket

# What kind of socket this is (informational; placement uses `accepts`).
enum SocketType {
	FOUNDATION_EDGE,
	FOUNDATION_TOP,
	WALL_BASE,
	WALL_TOP,
	WALL_SIDE,
	DOOR_SLOT,
	WINDOW_SLOT,
	PILLAR_TOP,
}

@export var socket_type: SocketType = SocketType.FOUNDATION_EDGE
# Which piece names this socket can host. Empty array means "compatible with
# anything" (use sparingly — explicit lists prevent cross-type mis-snaps).
@export var accepts: Array[String] = []

var is_occupied: bool = false
var occupying_piece: Node3D = null

func occupy(piece: Node3D) -> void:
	is_occupied = true
	occupying_piece = piece

func free_socket() -> void:
	is_occupied = false
	occupying_piece = null

# Walk up the tree to find the actual raft root this socket lives on.
func get_parent_raft() -> Node3D:
	var n: Node = self
	while n != null:
		if n.is_in_group("build_surface"):
			return n as Node3D
		n = n.get_parent()
	return null

# The piece this socket belongs to (its direct great-grandparent's parent,
# or whatever ancestor is the actual placed piece root).
func get_parent_piece() -> Node3D:
	var n: Node = self
	while n != null:
		# Skip until we find a node that has BuildSockets as a direct child.
		var sockets := n.get_node_or_null("BuildSockets")
		if sockets != null and self.get_parent() == sockets:
			return n as Node3D
		n = n.get_parent()
	return null

func is_compatible(piece_name: String) -> bool:
	return accepts.is_empty() or accepts.has(piece_name)

```

### `res://build_system.gd`

```gdscript
## Shared helper for the universal socket-to-socket attachment solver.
## Used by the build system to compute where a new piece must be placed so
## that its `new_piece_socket` exactly coincides with `target_socket` in
## world space.  Works for any piece type (foundation, wall, door, etc.).
##
## Returns a Transform3D suitable for assigning to the new piece's
## `global_transform`.
##
## Algorithm:
##   1. Compute the world-space offset from the new piece's center to its
##      attachment socket:  offset = new_piece_socket.position (local).
##   2. Rotate that offset by `build_rotation_y` around the global UP axis.
##   3. Place the piece center so that the rotated socket lands at the
##      target socket's global position:
##        center = target_socket.global_position - rotated_offset
##   4. The piece basis is the support piece's basis rotated by
##      `build_rotation_y`.
static func solve_socket_attachment(
	target_socket: Node3D,
	new_piece_socket_local_position: Vector3,
	build_rotation_y: float,
	support_basis: Basis,
) -> Transform3D:
	# 1. Local offset from piece center to attachment socket
	var local_offset: Vector3 = new_piece_socket_local_position

	# 2. Apply player build rotation (Y-axis only, around global UP)
	var rotated_offset: Vector3 = local_offset.rotated(Vector3.UP, build_rotation_y)

	# 3. Piece center in world space
	var piece_center: Vector3 = target_socket.global_position - rotated_offset

	# 4. Piece basis = support basis rotated by build rotation
	var piece_basis: Basis = support_basis.rotated(Vector3.UP, build_rotation_y)

	return Transform3D(piece_basis, piece_center)

```

### `res://crosshair.gd`

```gdscript
extends Control

# A small, always-centered hollow-circle reticle drawn in screen space.
# Lives under a CanvasLayer so it is independent of 3D movement/camera.
# Its center sits at (screen center X, screen center Y + aim_vertical_offset),
# and player.gd orients the interaction RayCast through this exact screen point.

enum State { NONE, ITEM, BUILD }

@export var crosshair_size: float = 24.0
@export var line_width: float = 3.0
# Negative = above exact screen center (creates visible space above the player).
@export var aim_vertical_offset: float = 0.0
@export var color_idle: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var color_item: Color = Color(0.4, 1.0, 0.4, 0.95)
@export var color_build: Color = Color(0.4, 0.8, 1.0, 0.95)

var state: int = State.NONE

func _ready() -> void:
	# Never intercept the mouse — camera look must pass through.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(crosshair_size, crosshair_size)
	anchors_preset = Control.PRESET_TOP_LEFT
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_position_reticle)
	_position_reticle()

func _process(_delta: float) -> void:
	_position_reticle()

func set_state(value: int) -> void:
	state = value
	queue_redraw()

func _position_reticle() -> void:
	var vp := get_viewport_rect().size
	var half := custom_minimum_size * 0.5
	# Center horizontally; offset vertically by the configured amount.
	position = Vector2(vp.x * 0.5 - half.x, vp.y * 0.5 + aim_vertical_offset - half.y)

func _draw() -> void:
	var col: Color = color_idle
	if state == State.ITEM:
		col = color_item
	elif state == State.BUILD:
		col = color_build

	var r: float = crosshair_size * 0.5
	var radius: float = max(r - line_width * 0.5, 0.5)
	draw_arc(Vector2(r, r), radius, 0.0, TAU, 32, col, line_width, true)

```

### `res://ocean.gd`

```gdscript
extends MeshInstance3D
class_name Ocean

# ============================================================
# OCEAN — day/night driver
# Reads the Sky3D sun/moon state each frame and pushes
# time-of-day uniforms to the ocean shader (main.gdshader).
# get_height() (buoyancy/waves/collision) is unchanged.
# ============================================================

# --- Time-of-day water palette (tune in the inspector) ---
# TRUE LINEAR HDR colors — the shader uniforms are deliberately NOT
# source_color (that hint silently converts pushed colors sRGB->linear and
# darkens the water ~3x). The scene uses ACES tonemapping (mode 3). Tuned so
# the final displayed ocean is a bright tropical turquoise like the reference
# raft-survival games:
#   day (0.035, 0.38, 0.42) -> ~sRGB (0.2x, 0.6x, 0.6x) turquoise/cyan
#   night (0.012, 0.04, 0.12) -> navy
# (verified empirically against the real ACES+sRGB pipeline).
@export var day_color := Color(0.035, 0.38, 0.42)
@export var twilight_color := Color(0.07, 0.085, 0.26)
@export var night_color := Color(0.018, 0.06, 0.165)
@export var sparkle_strength := 1.5

# Dev-only time keys. F3 is the build overlay, so the debug keys use F5-F9.
@export var dev_time_keys := true

@export var wave_height := 0.55
@export var wave_speed := 1.2
var _time := 0.0

var _sky3d: Node = null
var _sky: Node = null
var _mat: ShaderMaterial = null
var _sun_light: DirectionalLight3D = null
var _moon_light: DirectionalLight3D = null
var _env: Environment = null

# Debug HUD
var _label: Label = null
var _show_debug := false
var _last_night := 0.0
var _last_twilight := 0.0
var _last_moon := 0.0
var _sun_elev := 1.0
var _moon_elev := -1.0

func _ready() -> void:
	# Groups work across scene-file boundaries (unlike %UniqueName), so any
	# runtime-instanced node (debris, etc.) can always find this node.
	add_to_group("ocean")
	var scene := get_tree().current_scene
	if scene != null:
		_sky3d = scene.get_node_or_null("Sky3D")
	if _sky3d == null:
		_sky3d = get_node_or_null("../../Sky3D")
	if _sky3d != null:
		_sky = _sky3d.get("sky") as Node  # SkyDome node
		_sun_light = _sky3d.get_node_or_null("SunLight") as DirectionalLight3D
		_moon_light = _sky3d.get_node_or_null("MoonLight") as DirectionalLight3D
		_env = _sky3d.get("environment") as Environment
	if mesh is PlaneMesh:
		_mat = (mesh as PlaneMesh).material as ShaderMaterial
	if _mat != null:
		_mat.set_shader_parameter("water_day_color", day_color)
		_mat.set_shader_parameter("water_twilight_color", twilight_color)
		_mat.set_shader_parameter("water_night_color", night_color)
		_mat.set_shader_parameter("sparkle_strength", sparkle_strength)
		# Keep the visual waves and the buoyancy sample (get_height below) on the
		# same amplitude so the raft rides the visible waves instead of shaking
		# against them.
		_mat.set_shader_parameter("wave_height", wave_height)
		_mat.set_shader_parameter("wave_speed", wave_speed)
		_push_factors(0.0, 0.0, 0.0)

func _process(delta: float) -> void:
	_time += delta
	if _mat == null or _sky == null:
		return
	# Smooth factors from the SkyDome's own sun/moon directions (origin.y is
	# +1 at zenith / -1 at nadir in world space — the same value the addon uses
	# to fade its lights). Continuous curves, no hard day/night switch.
	var sun_y := 1.0
	var moon_y := -1.0
	var st := _sky.get("_sun_transform") as Transform3D
	if st != null:
		sun_y = st.origin.y
	var mt := _sky.get("_moon_transform") as Transform3D
	if mt != null:
		moon_y = mt.origin.y
	_sun_elev = sun_y
	_moon_elev = moon_y
	var night := clampf((-sun_y - 0.02) / 0.25, 0.0, 1.0)
	var twilight := clampf(1.0 - absf(sun_y) / 0.22, 0.0, 1.0)
	var moon_up := clampf(moon_y / 0.1, 0.0, 1.0)
	var moon_factor := night * moon_up
	_push_factors(night, twilight, moon_factor)
	_update_debug_hud(night, twilight, moon_factor)

func _push_factors(night: float, twilight: float, moon_factor: float) -> void:
	_last_night = night
	_last_twilight = twilight
	_last_moon = moon_factor
	_mat.set_shader_parameter("night_factor", night)
	_mat.set_shader_parameter("twilight_factor", twilight)
	_mat.set_shader_parameter("moon_factor", moon_factor)
	if _sun_light != null and is_instance_valid(_sun_light):
		_mat.set_shader_parameter("sun_dir", _sun_light.global_transform.origin.normalized())
		_mat.set_shader_parameter("sun_glint_color", _sun_light.light_color)
	if _moon_light != null and is_instance_valid(_moon_light):
		_mat.set_shader_parameter("moon_dir", _moon_light.global_transform.origin.normalized())
		_mat.set_shader_parameter("moon_glint_color", _moon_light.light_color)

func _unhandled_input(event: InputEvent) -> void:
	if not dev_time_keys or _sky3d == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F5:
				_force_time(12.0)
			KEY_F6:
				_force_time(18.6)
			KEY_F7:
				_force_time(0.4)
			KEY_F8:
				_force_time(6.4)
			KEY_F9:
				_show_debug = not _show_debug
				_ensure_debug_label()
				if _label != null:
					_label.visible = _show_debug

# Dev shortcut: jump straight to a time of day (Sky3D -> TimeOfDay recomputes
# the sun/moon coords immediately).
func _force_time(hour: float) -> void:
	_sky3d.set("current_time", hour)

func _ensure_debug_label() -> void:
	if _label != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "_OceanDebugUI"
	layer.layer = 20
	add_child(layer)
	_label = Label.new()
	layer.add_child(_label)
	_label.position = Vector2(12.0, 90.0)
	_label.add_theme_font_size_override("font_size", 12)
	_label.modulate = Color(1.0, 1.0, 0.8, 0.95)

func _update_debug_hud(night: float, twilight: float, moon_factor: float) -> void:
	if not _show_debug or _label == null:
		return
	var lines: PackedStringArray = []
	lines.append("Time: %s" % str(_sky3d.get("game_time") if _sky3d else "?"))
	if _sun_light != null:
		lines.append("Sun:   elev=%+.2f  energy=%.2f" % [_sun_elev, _sun_light.light_energy])
	if _moon_light != null:
		lines.append("Moon:  elev=%+.2f  energy=%.2f" % [_moon_elev, _moon_light.light_energy])
	if _env != null:
		lines.append("Ambient: energy=%.2f color=%s" % [_env.ambient_light_energy, _env.ambient_light_color.to_html(false)])
	if _sky != null:
		lines.append("Sky:   exposure=%.2f  fog=%.5f" % [float(_sky.get("exposure")), float(_sky.get("fog_density"))])
	lines.append("Ocean: night=%.2f twilight=%.2f moon=%.2f" % [night, twilight, moon_factor])
	var text := "\n".join(lines)
	if text != _label.text:
		_label.text = text

# Returns the exact water surface height (world Y) at any given world position.
func get_height(world_pos: Vector3) -> float:
	var h := sin(world_pos.x * 0.4 + _time * wave_speed) \
		+ sin(world_pos.z * 0.3 + _time * wave_speed * 0.8) \
		+ 0.5 * sin((world_pos.x + world_pos.z) * 0.7 + _time * 1.7)
	return global_position.y + h * wave_height * 0.33

```

### `res://raft.gd`

```gdscript
extends AnimatableBody3D

@export var float_height: float = 0.6
@export var follow_speed: float = 4.0

var ocean: Ocean = null
var _markers: Array = []
var _extra_sample_points: Array[Node3D] = []

func _ready() -> void:
	add_to_group("build_surface")
	_markers = [
		get_node_or_null("F1"),
		get_node_or_null("F2"),
		get_node_or_null("F3"),
		get_node_or_null("F4"),
	]
	rotation = Vector3.ZERO

func _get_ocean() -> Ocean:
	if ocean == null or not is_instance_valid(ocean):
		ocean = get_tree().get_first_node_in_group("ocean")
	return ocean

# Called by player.gd after a piece is placed, passing one of the piece's
# own corner/center markers so the raft's buoyancy averaging expands to
# cover the growing structure.
func register_sample_point(marker: Node3D) -> void:
	if marker != null and not _extra_sample_points.has(marker):
		_extra_sample_points.append(marker)

# Called when a piece is removed (Fix support for X / remove_build).
func unregister_sample_point(marker: Node3D) -> void:
	_extra_sample_points.erase(marker)

func _physics_process(delta: float) -> void:
	var oc := _get_ocean()
	if oc == null:
		return

	var avg_height: float = 0.0
	var count: int = 0

	for m in _markers:
		if m != null and is_instance_valid(m):
			avg_height += float(oc.get_height(m.global_position))
			count += 1

	# Prune invalid refs lazily while summing (freed pieces, etc.)
	for i in range(_extra_sample_points.size() - 1, -1, -1):
		var m = _extra_sample_points[i]
		if not is_instance_valid(m):
			_extra_sample_points.remove_at(i)
			continue
		avg_height += float(oc.get_height(m.global_position))
		count += 1

	if count > 0:
		avg_height /= float(count)

	var target_y: float = avg_height + float_height
	global_position.y = lerpf(
		global_position.y, target_y,
		1.0 - exp(-follow_speed * delta)
	)

```

### `res://debris.gd`

```gdscript
extends RigidBody3D
class_name Debris

# ---- Identity (kept so Inventory can collect it) ----
@export var item_name := "Wood"

# ---- Ocean current (assigned by the spawner so all debris share a stream) ----
@export var current_direction: Vector3 = Vector3(0, 0, 1)
@export var current_speed: float = 1.2

# ---- Floating profile ----
@export var freeboard: float = 0.15
@export var buoyancy: float = 8.0
@export var max_vertical_speed: float = 2.0

# World position where this piece was spawned; the spawner uses it to
# measure how far downstream it has travelled before despawning.
var travel_start: Vector3 = Vector3.ZERO
var collected: bool = false
var is_hooked: bool = false

var mass_kg: float = 2.0
var ocean: Ocean = null

var _wander_seed: float = 0.0
var _side_drift: float = 0.0
var _speed_variation: float = 1.0
var _rot_speed: float = 0.0

# Fade in/out
var _fade_timer: float = 0.0
var _fade_duration: float = 1.5
var _is_fading_in: bool = true
var _is_fading_out: bool = false
var _fade_material: StandardMaterial3D = null

const BUOY_DAMPING: float = 3.0

# Each entry controls how "floaty" that item looks (rides higher/lower).
const ITEM_PROFILES := {
	"Wood":    {"mass": 2.0, "freeboard": 0.20, "color": Color(0.85, 0.65, 0.35)},
	"Rope":    {"mass": 1.0, "freeboard": 0.05, "color": Color(0.75, 0.60, 0.35)},
	"Plastic": {"mass": 0.6, "freeboard": 0.25, "color": Color(0.3, 0.7, 1.0)},
	"Barrel":  {"mass": 6.0, "freeboard": 0.30, "color": Color(0.70, 0.45, 0.20)},
	"Stone":   {"mass": 4.0, "freeboard": 0.10, "color": Color(0.65, 0.65, 0.65)},
	"Metal":   {"mass": 5.0, "freeboard": 0.15, "color": Color(0.80, 0.80, 0.85)},
}

func _ready() -> void:
	add_to_group("debris")
	ocean = get_tree().get_first_node_in_group("ocean")
	if ocean == null:
		ocean = get_node_or_null("%Ocean")

	_wander_seed = randf() * 1000.0
	_side_drift = randf_range(-0.3, 0.3)
	_speed_variation = randf_range(0.9, 1.0)
	_rot_speed = randf_range(-1.0, 1.0)

	_apply_profile()

	mass = mass_kg
	linear_damp = 2.5
	angular_damp = 3.0
	gravity_scale = 0.0   # buoyancy fully controls vertical motion

	# Sit on a dedicated layer so the pickup RayCast can detect debris
	# specifically. IMPORTANT: this only works if the Reach RayCast3D's
	# Collision Mask (Inspector) has bit 2 enabled — see the note above.
	collision_layer = 2
	# Keep default mask (1) so it still physically collides with the raft/player.
	collision_mask = 1

	# Snap onto the real wave height where it spawned.
	if ocean != null:
		global_position.y = float(ocean.get_height(global_position)) + freeboard

func start_fade_out() -> void:
	_is_fading_out = true
	_fade_timer = 0.0

func is_fade_done() -> bool:
	return _is_fading_out and _fade_timer >= _fade_duration

func _apply_profile() -> void:
	if ITEM_PROFILES.has(item_name):
		var prof = ITEM_PROFILES[item_name]
		mass_kg = prof["mass"]
		freeboard = prof["freeboard"]
		# Apply colour to the mesh so different debris is visually distinct
		var mesh_inst := get_node_or_null("MeshInstance3D")
		if mesh_inst and mesh_inst.get_surface_override_material(0) == null:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = prof["color"]
			mat.emission_enabled = true
			mat.emission = prof["color"] * 0.3
			mat.emission_energy_multiplier = 0.4
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.0
			mesh_inst.set_surface_override_material(0, mat)
			_fade_material = mat

func _physics_process(delta: float) -> void:
	# Skip all buoyancy/current math while the rope system is holding this
	# piece (freeze == true) — it has no effect on a frozen body today since
	# nothing currently un-freezes and re-releases debris, but computing
	# target velocities on a body that can't move is wasted work, and this
	# guard makes that assumption explicit instead of silently relying on
	# RigidBody3D's frozen state to absorb it.
	if freeze or is_hooked or collected:
		return
	if ocean == null:
		return

	var water_y: float = float(ocean.get_height(global_position))

	# ---- Vertical buoyancy: rest at the surface, follow the waves gently ----
	var rest_y: float = water_y + freeboard
	var y_error: float = rest_y - global_position.y
	linear_velocity.y += (buoyancy * y_error - BUOY_DAMPING * linear_velocity.y) * delta
	linear_velocity.y = clamp(linear_velocity.y, -max_vertical_speed, max_vertical_speed)

	# ---- Horizontal current: one dominant direction + small variation ----
	var dir: Vector3 = Vector3(current_direction.x, 0.0, current_direction.z).normalized()
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x).normalized()
	var target_velocity: Vector3 = dir * current_speed * _speed_variation + side * _side_drift
	var k: float = 1.0 - exp(-3.0 * delta)
	linear_velocity.x = lerpf(linear_velocity.x, target_velocity.x, k)
	linear_velocity.z = lerpf(linear_velocity.z, target_velocity.z, k)

	# ---- Gentle natural tumble ----
	var t: float = Time.get_ticks_msec() / 1000.0 + _wander_seed
	angular_velocity = Vector3(sin(t * 0.5) * 0.2, _rot_speed, cos(t * 0.4) * 0.2)

	# ---- Fade in on spawn ----
	if _is_fading_in and _fade_material != null:
		_fade_timer += delta
		var alpha: float = clampf(_fade_timer / _fade_duration, 0.0, 1.0)
		_fade_material.albedo_color.a = alpha
		if alpha >= 1.0:
			_is_fading_in = false

	# ---- Fade out before despawn ----
	if _is_fading_out and _fade_material != null:
		_fade_timer += delta
		var alpha: float = clampf(1.0 - _fade_timer / _fade_duration, 0.0, 1.0)
		_fade_material.albedo_color.a = alpha

```

### `res://debris_spawner.gd`

```gdscript
extends Node3D

# Continuous ocean-current debris stream.
# Debris flows from UPSTREAM → past player → DOWNSTREAM → despawn.

@export var debris_scene: PackedScene
@export var current_direction: Vector3 = Vector3(0, 0, 1)
@export var current_speed: float = 1.2
@export var spawn_width: float = 60.0
@export var upstream_distance: float = 80.0
@export var downstream_distance: float = 120.0
@export var max_debris: int = 80
@export var prewarm_count: int = 35

# Staggered timing — 1 piece every 0.2–0.5 seconds
@export var spawn_interval_min: float = 0.2
@export var spawn_interval_max: float = 0.5

var _timer: float = 0.0
var _next_interval: float = 0.0
var _active: Array = []
var player: Node3D
var _direction: Vector3 = Vector3.ZERO
var _side: Vector3 = Vector3.ZERO

const ITEM_POOL := [
	"Wood", "Wood", "Wood", "Wood", "Wood", "Wood",
	"Rope", "Rope", "Rope",
	"Plastic", "Plastic",
	"Barrel",
	"Stone", "Stone",
	"Metal",
]

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	_direction = Vector3(current_direction.x, 0.0, current_direction.z).normalized()
	if _direction.length() < 0.001:
		_direction = Vector3(0, 0, 1)
	_side = Vector3(-_direction.z, 0.0, _direction.x).normalized()
	_next_interval = randf_range(spawn_interval_min, spawn_interval_max)
	_prewarm()


func _get_player() -> Node3D:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	return player


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _next_interval:
		_timer = 0.0
		_next_interval = randf_range(spawn_interval_min, spawn_interval_max)
		_cleanup()
		if _active.size() < max_debris:
			_spawn_upstream()


# Fill the upstream corridor at startup — debris visible from frame 1.
func _prewarm() -> void:
	for i in prewarm_count:
		# Spread evenly from upstream to just past the player
		var dist := randf_range(-upstream_distance, downstream_distance * 0.5)
		_spawn_at(dist)


# New debris always enters from upstream.
func _spawn_upstream() -> void:
	_spawn_at(-randf_range(upstream_distance * 0.8, upstream_distance))


func _spawn_at(along_t: float) -> void:
	if not debris_scene:
		return

	var d = debris_scene.instantiate()

	var p := _get_player()
	var origin := p.global_position if p != null else Vector3.ZERO

	# Random lateral position + small along-current jitter
	var lateral := randf_range(-spawn_width * 0.5, spawn_width * 0.5)
	var jitter := randf_range(-5.0, 5.0)
	var spawn_point := origin + _direction * (along_t + jitter) + _side * lateral

	d.item_name = ITEM_POOL.pick_random()
	d.current_direction = _direction
	d.current_speed = current_speed * randf_range(0.7, 1.3)
	d.travel_start = spawn_point
	d.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))

	d.position = spawn_point
	d.position.y = 0.0

	add_child(d)
	_active.append(d)


func _cleanup() -> void:
	for i in range(_active.size() - 1, -1, -1):
		var d = _active[i]
		if not is_instance_valid(d):
			_active.remove_at(i)
			continue
		if d.freeze:
			continue
		var travelled: float = (Vector3(d.global_position) - Vector3(d.travel_start)).dot(_direction)
		if travelled > downstream_distance and not d._is_fading_out:
			d.start_fade_out()
		if d.is_fade_done():
			d.queue_free()
			_active.remove_at(i)

```

### `res://rope_system.gd`

```gdscript
extends Node3D
class_name RopeSystem

## Ocean-survival hook + rope system.
## Q = charge & throw hook toward the crosshair. Right-click (rope_cancel) = recall.
## Fully automatic after the throw:
##   - hook lands ON the water (never sails over it) and keeps checking for debris;
##   - anything that drifts into range gets hooked (multiple pieces per throw);
##   - with a catch  -> hook pauses ~0.4 s, then reels itself back to the hand;
##   - nothing caught -> hook waits ~0.8 s for drift-ins, then RETURNS BY ITSELF fast;
##   - cancel/recall anytime: releases any hooked debris and pulls the rope back.

# ============================================================
# STATE MACHINE
# ============================================================
enum State { IDLE, THROWING, EXTENDED, HOOKED, REELING, RETURNING }

var _state: int = State.IDLE

# ============================================================
# EXPORTS
# ============================================================
@export var max_hook_distance: float = 22.0
@export var throw_speed: float = 22.0
@export var reel_speed: float = 14.0
@export var return_speed: float = 30.0
@export var debris_hook_radius: float = 1.8
@export var collection_radius: float = 1.5
## How long the hook rests when nothing is hooked before auto-returning.
@export var empty_wait_time: float = 0.8
## How long the hook settles after creeping before auto-reeling it in.
@export var hook_pause_time: float = 0.25
## How much farther the hook keeps gliding after the FIRST catch so debris
## sitting right next to the caught piece also get scooped (no "gap").
@export var hook_creep_distance: float = 3.0
@export var hook_creep_speed: float = 6.0

# ============================================================
# NODES
# ============================================================
var player: Node3D = null
var camera: Camera3D = null

var _hook: MeshInstance3D = null
var _hook_origin: Node3D = null
var _rope_mesh: MeshInstance3D = null
var _rope_material: StandardMaterial3D = null
var _aim_ray: RayCast3D = null
var _charge_bar: ColorRect = null

# ============================================================
# STATE — all world-space, immutable after throw
# ============================================================
var _throw_direction: Vector3 = Vector3.FORWARD
var _throw_start: Vector3 = Vector3.ZERO
var _throw_dist: float = 0.0
var _hook_world_pos: Vector3 = Vector3.ZERO
var _hook_travelled: float = 0.0
var _state_timer: float = 0.0
var _crept: float = 0.0
var _creep_done: bool = false

## Every piece captured by the current throw (one hook can scoop several).
var _hooked_debris: Array[RigidBody3D] = []
var _collected: bool = false
var _is_charging: bool = false
var _charge_distance: float = 0.0
var _charge_speed: float = 30.0

# ============================================================
# INIT
# ============================================================
func _ready() -> void:
	_ensure_actions()
	_create_hook_origin()
	_create_hook()
	_create_rope_mesh()
	_create_charge_bar()
	_create_aim_ray()


func _ensure_actions() -> void:
	if not InputMap.has_action("rope_throw"):
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_Q
		InputMap.add_action("rope_throw")
		InputMap.action_add_event("rope_throw", ev)
	if not InputMap.has_action("rope_pull"):
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.add_action("rope_pull")
		InputMap.action_add_event("rope_pull", ev)
	if not InputMap.has_action("rope_cancel"):
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		InputMap.add_action("rope_cancel")
		InputMap.action_add_event("rope_cancel", ev)


func _create_hook_origin() -> void:
	_hook_origin = Node3D.new()
	_hook_origin.name = "HookOrigin"
	add_child(_hook_origin)


func _create_hook() -> void:
	_hook = MeshInstance3D.new()
	_hook.name = "Hook"
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	_hook.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.8, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.8, 0.2) * 0.3
	_hook.material_override = mat
	_hook.visible = false
	add_child(_hook)


func _create_rope_mesh() -> void:
	_rope_mesh = MeshInstance3D.new()
	_rope_mesh.name = "RopeMesh"
	_rope_material = StandardMaterial3D.new()
	_rope_material.albedo_color = Color(0.7, 0.6, 0.3)
	_rope_material.no_depth_test = false
	_rope_mesh.material_override = _rope_material
	_rope_mesh.visible = false
	add_child(_rope_mesh)


func _create_charge_bar() -> void:
	_charge_bar = ColorRect.new()
	_charge_bar.color = Color(0.9, 0.8, 0.2, 0.75)
	_charge_bar.visible = false
	_charge_bar.size = Vector2(0, 5)
	add_child(_charge_bar)


func _create_aim_ray() -> void:
	_aim_ray = RayCast3D.new()
	_aim_ray.target_position = Vector3(0, 0, -max_hook_distance)
	_aim_ray.collision_mask = 3
	add_child(_aim_ray)


# ============================================================
# HELPERS
# ============================================================
## Aim point: real raycast hit (raft/debris), otherwise the point where the
## crosshair ray crosses the OCEAN SURFACE. Without this the hook used to fly
## 22 m straight at eye height and never reach the water where debris float.
func _get_aim_point() -> Vector3:
	if camera == null:
		return _hook_origin.global_position + Vector3(0, 0, -10)
	if player != null:
		_aim_ray.add_exception(player)
	_aim_ray.global_position = camera.global_position
	_aim_ray.global_rotation = camera.global_rotation
	_aim_ray.force_raycast_update()
	if _aim_ray.is_colliding():
		return _aim_ray.get_collision_point()

	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var water_y := _get_ocean_y(origin) + 0.15
	if dir.y < -0.001:
		var t := (water_y - origin.y) / dir.y
		if t > 1.0 and t <= max_hook_distance:
			return origin + dir * t
	return origin + dir * max_hook_distance


func _hand_pos() -> Vector3:
	return _hook_origin.global_position


func _get_ocean_y(pos: Vector3) -> float:
	if player == null:
		return 0.0
	var oc = player.get("ocean")
	if oc != null:
		return float(oc.get_height(pos))
	return 0.0


func _is_build_active() -> bool:
	if player == null:
		return false
	var bm = player.get("build_mode")
	return bm != null and bool(bm)


func _is_editing_active() -> bool:
	if player == null:
		return false
	return player.get("_editing") != null


# ============================================================
# PHYSICS — main update
# ============================================================
func _physics_process(delta: float) -> void:
	if player == null or camera == null:
		return

	# Block during build/edit
	if _is_build_active() or _is_editing_active():
		if _state != State.IDLE:
			_force_cancel()
		return

	# Update hook origin (follows the player's hand)
	_update_hook_origin()

	# State machine
	match _state:
		State.IDLE:
			_handle_idle(delta)
		State.THROWING:
			_handle_throwing(delta)
		State.EXTENDED:
			_handle_extended(delta)
		State.HOOKED:
			_handle_hooked(delta)
		State.REELING:
			_handle_reeling(delta)
		State.RETURNING:
			_handle_returning(delta)

	# Update visuals
	_update_hook_visual()
	_update_rope_visual()
	_update_charge_bar_ui()


# ============================================================
# HOOK ORIGIN — anchored at the hand, BELOW and to the RIGHT of the
# camera so the rope visibly comes from the player's hand, not the head.
# ============================================================
func _update_hook_origin() -> void:
	if player == null or camera == null:
		return
	var b := camera.global_transform.basis
	var cam_pos := camera.global_position
	# Hand anchor — matches the visible viewmodel fist (Camera3D/HandPivot).
	# Placed so the fist stays INSIDE the camera frustum on desktop AND
	# portrait mobile: 0.55 m forward, 0.30 m below, 0.18 m right.
	_hook_origin.global_position = cam_pos - b.y * 0.30 + b.x * 0.18 - b.z * 0.55


# ============================================================
# STATE: IDLE
# ============================================================
func _handle_idle(delta: float) -> void:
	if Input.is_action_just_pressed("rope_cancel"):
		_cancel_charge()
		return
	if Input.is_action_just_pressed("rope_throw"):
		_is_charging = true
		_charge_distance = 5.0
	elif _is_charging and Input.is_action_pressed("rope_throw"):
		_charge_distance = minf(_charge_distance + _charge_speed * delta, max_hook_distance)
	elif _is_charging and Input.is_action_just_released("rope_throw"):
		_throw_hook()


func _cancel_charge() -> void:
	_is_charging = false
	_charge_bar.visible = false


# ============================================================
# STATE: THROWING — hook flies along the locked direction, sampled in
# small sub-steps so debris between physics frames can never be skipped.
# ============================================================
func _handle_throwing(delta: float) -> void:
	if Input.is_action_just_pressed("rope_cancel"):
		_start_return()
		return
	var remaining := throw_speed * delta
	while remaining > 0.001 and _state == State.THROWING:
		var step := minf(remaining, 0.5)
		remaining -= step
		_hook_travelled += step
		if _hook_travelled >= _throw_dist:
			_hook_world_pos = _throw_start + _throw_direction * _throw_dist
			_hook_travelled = _throw_dist
			_check_debris()
			_finish_flight()
			return
		_hook_world_pos = _throw_start + _throw_direction * _hook_travelled
		_check_debris()
		if not _hooked_debris.is_empty():
			_enter_hooked()
			return


func _finish_flight() -> void:
	_snap_hook_to_water()
	_check_debris()
	if _hooked_debris.is_empty():
		_state = State.EXTENDED
	else:
		_enter_hooked()
	_state_timer = 0.0


# ============================================================
# STATE: EXTENDED — hook rests on the water, still hunting: any debris that
# drifts into range is hooked; otherwise it auto-returns after a short wait.
# ============================================================
func _handle_extended(delta: float) -> void:
	# Keep the hook riding the wave surface so its reach stays constant
	# (only when it actually landed on/near the water).
	var wy := _get_ocean_y(_hook_world_pos) + 0.2
	if _hook_world_pos.y - wy < 3.0:
		_hook_world_pos.y = lerpf(_hook_world_pos.y, wy, clampf(delta * 4.0, 0.0, 1.0))
	_state_timer += delta
	_check_debris()
	if not _hooked_debris.is_empty():
		_enter_hooked()
		return
	if Input.is_action_just_pressed("rope_cancel"):
		_start_return()
		return
	if Input.is_action_just_pressed("rope_throw") or Input.is_action_just_pressed("rope_pull"):
		# Manual reel before the auto-wait expires.
		_state = State.REELING
		_state_timer = 0.0
		return
	if _state_timer >= empty_wait_time:
		# Nothing caught — come back on our own, fast.
		_start_return()


# ============================================================
# STATE: HOOKED — a piece is captured; extras drifting in keep getting
# scooped for a short pause, then the rope reels itself in automatically.
# ============================================================
func _handle_hooked(delta: float) -> void:
	_state_timer += delta

	# Creep forward along the throw direction: the first catch usually happens
	# at the near edge of a cluster, so keep gliding a little to scoop the
	# pieces that were sitting just behind/next to it.
	if not _creep_done:
		var step := minf(delta * hook_creep_speed, hook_creep_distance - _crept)
		_hook_world_pos += _throw_direction * step
		_crept += step
		if _crept >= hook_creep_distance - 0.001:
			_creep_done = true
		# Ride the water surface when creeping over water.
		var wy := _get_ocean_y(_hook_world_pos) + 0.2
		if _hook_world_pos.y - wy < 3.0:
			_hook_world_pos.y = lerpf(_hook_world_pos.y, wy, clampf(delta * 4.0, 0.0, 1.0))

	_check_debris()
	_place_captured_chain()
	if Input.is_action_just_pressed("rope_cancel"):
		_start_return()
		return
	if Input.is_action_just_pressed("rope_throw") or Input.is_action_just_pressed("rope_pull"):
		_state = State.REELING
		_state_timer = 0.0
		return
	# Auto-reel: after the creep is done (plus a tiny settle) or on a hard cap.
	if (_creep_done and _state_timer >= hook_pause_time) or _state_timer >= 2.0:
		_state = State.REELING
		_state_timer = 0.0


# ============================================================
# STATE: REELING — hook + captured pieces move toward the hand.
# Empty rope reels at the fast return speed; a loaded rope drags slowly.
# ============================================================
func _handle_reeling(delta: float) -> void:
	if Input.is_action_just_pressed("rope_cancel"):
		_start_return()
		return
	var hand := _hand_pos()
	var to_hand := hand - _hook_world_pos
	var dist := to_hand.length()

	# Move the hook toward the hand (never overshoot past it).
	var dir := to_hand.normalized()
	var speed := reel_speed if not _hooked_debris.is_empty() else return_speed
	var step := minf(speed * delta, dist)
	_hook_world_pos += dir * step
	_hook_travelled = _throw_start.distance_to(_hook_world_pos)

	# Scoop anything that drifts into the moving hook's reach.
	_check_debris()
	_place_captured_chain()

	# Collect each trailed piece as it reaches the raft edge (the hook leads,
	# the catch trails behind it in the water — pieces come in one by one).
	var i := 0
	while i < _hooked_debris.size():
		var d: RigidBody3D = _hooked_debris[i]
		if is_instance_valid(d) and hand.distance_to(d.global_position) <= collection_radius:
			_collect_one(d)
			_hooked_debris.remove_at(i)
		else:
			i += 1

	if _hooked_debris.is_empty():
		_start_return()
		return

	# Hook is at the hand but pieces are still trailing behind — pull them in.
	if dist <= 0.25:
		for d in _hooked_debris:
			if is_instance_valid(d):
				d.global_position = d.global_position.move_toward(hand, reel_speed * 2.0 * delta)


# ============================================================
# STATE: RETURNING — hook flies back to the hand (always fast; anything
# hooked was already released by _start_return / collected).
# ============================================================
func _handle_returning(delta: float) -> void:
	var hand := _hand_pos()
	var to_hand := hand - _hook_world_pos
	var dist := to_hand.length()

	if dist <= 0.5:
		_hook.visible = false
		_rope_mesh.visible = false
		_state = State.IDLE
		_state_timer = 0.0
		return

	var dir := to_hand.normalized()
	_hook_world_pos += dir * return_speed * delta


# ============================================================
# THROW — capture direction ONCE
# ============================================================
func _throw_hook() -> void:
	_is_charging = false
	_charge_bar.visible = false

	var aim_point := _get_aim_point()
	var hand := _hand_pos()
	var to_aim := aim_point - hand
	var aim_dist := to_aim.length()

	# LOCK direction — never recalculated
	if aim_dist > 0.001:
		_throw_direction = (to_aim / aim_dist).normalized()
	else:
		_throw_direction = -camera.global_transform.basis.z

	_throw_dist = minf(_charge_distance, max_hook_distance)
	# If the aim point is nearer than the charge (e.g. raft edge in the way),
	# don't overshoot past it.
	if aim_dist > 1.0 and aim_dist < _throw_dist:
		_throw_dist = aim_dist
	_throw_start = hand
	_hook_world_pos = hand
	_hook_travelled = 0.0
	_hooked_debris.clear()
	_collected = false
	_state_timer = 0.0
	_crept = 0.0
	_creep_done = false

	_hook.visible = true
	_hook.global_position = hand
	_rope_mesh.visible = true
	_state = State.THROWING


# ============================================================
# DEBRIS DETECTION — every frame, all around the hook, no early bail:
# one hook can scoop several pieces, and pieces already held don't block
# new ones drifting in next to them.
# ============================================================
func _check_debris() -> void:
	for d in get_tree().get_nodes_in_group("debris"):
		if not (d is RigidBody3D) or not is_instance_valid(d):
			continue
		if d.get("collected") == true:
			continue
		if d.get("is_hooked") == true:
			continue
		if _hooked_debris.has(d):
			continue
		if d.global_position.distance_to(_hook_world_pos) <= debris_hook_radius:
			_hook_debris(d)


func _hook_debris(debris: RigidBody3D) -> void:
	debris.set("is_hooked", true)
	debris.freeze = true
	debris.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_hooked_debris.append(debris)


func _enter_hooked() -> void:
	_state = State.HOOKED
	_state_timer = 0.0
	_crept = 0.0
	_creep_done = false


## Tow every captured piece BEHIND the hook on the water surface (like a net
## trailed behind a boat) — never strung up in the air along the rope line.
func _place_captured_chain() -> void:
	var hand := _hand_pos()
	var behind: Vector3 = _hook_world_pos - hand
	if behind.length() < 0.001:
		behind = _throw_direction
	else:
		behind = behind.normalized()
	var n: int = _hooked_debris.size()
	for i in n:
		var d: RigidBody3D = _hooked_debris[i]
		if not is_instance_valid(d):
			continue
		var fb: float = 0.15
		var fbv = d.get("freeboard")
		if fbv != null:
			fb = float(fbv)
		var pos := _hook_world_pos - behind * (float(i) + 1.0) * 0.7
		pos.y = _get_ocean_y(pos) + fb
		d.global_position = pos
		d.linear_velocity = Vector3.ZERO
		d.angular_velocity = Vector3.ZERO


func _release_debris() -> void:
	for d in _hooked_debris:
		if is_instance_valid(d):
			d.freeze = false
			d.set("is_hooked", false)
	_hooked_debris.clear()


func _collect_one(d: RigidBody3D) -> void:
	var item_name: String = str(d.get("item_name"))
	if item_name != "" and item_name != "null":
		d.set("collected", true)
		Inventory.add(item_name)
	d.queue_free()
	_collected = true


func _snap_hook_to_water() -> void:
	var water_y := _get_ocean_y(_hook_world_pos)
	if _hook_world_pos.y > water_y + 1.0:
		_hook_world_pos.y = water_y + 0.2


func _start_return() -> void:
	_release_debris()
	_state = State.RETURNING
	_state_timer = 0.0


# Convenience for the mobile UI (MobileControls shows a recall button while
# the rope is out).
func is_active() -> bool:
	return _state != State.IDLE


func _force_cancel() -> void:
	_release_debris()
	_hook.visible = false
	_rope_mesh.visible = false
	_hooked_debris.clear()
	_collected = false
	_is_charging = false
	_charge_bar.visible = false
	_state = State.IDLE
	_state_timer = 0.0


# ============================================================
# VISUALS — hook + rope
# ============================================================
func _update_hook_visual() -> void:
	if _state == State.IDLE:
		_hook.visible = false
		return
	_hook.visible = true
	_hook.global_position = _hook_world_pos


func _update_rope_visual() -> void:
	if _state == State.IDLE:
		_rope_mesh.visible = false
		return

	var from := _hand_pos()
	var to := _hook_world_pos
	var rope_len := from.distance_to(to)

	if rope_len < 0.1:
		_rope_mesh.visible = false
		return

	_rope_mesh.visible = true

	# Build a tube mesh along the rope path using CylinderMesh
	var mid := (from + to) * 0.5
	var dir := to - from
	var height := rope_len

	_rope_mesh.global_position = mid
	_rope_mesh.global_rotation = Vector3.ZERO

	# CylinderMesh extends along local Y axis — orient Y along the rope
	var rope_dir := dir.normalized()
	var arbitrary := Vector3.UP
	if abs(rope_dir.dot(Vector3.UP)) > 0.9:
		arbitrary = Vector3.FORWARD
	var right := arbitrary.cross(rope_dir).normalized()
	var perp := rope_dir.cross(right).normalized()
	# Y axis = rope direction, X = right, Z = perpendicular
	_rope_mesh.global_transform.basis = Basis(right, rope_dir, perp)

	# Update the cylinder mesh
	var existing_mesh := _rope_mesh.mesh
	var cyl: CylinderMesh = null
	if existing_mesh is CylinderMesh:
		cyl = existing_mesh as CylinderMesh
	else:
		cyl = CylinderMesh.new()
		cyl.top_radius = 0.025
		cyl.bottom_radius = 0.025
		_rope_mesh.mesh = cyl
	cyl.height = height


func _update_charge_bar_ui() -> void:
	if _charge_bar == null:
		return
	if _is_charging:
		_charge_bar.visible = true
		var vp := get_viewport().get_visible_rect().size
		var bar_w := (_charge_distance / max_hook_distance) * 200.0
		_charge_bar.size = Vector2(bar_w, 5)
		_charge_bar.position = Vector2(vp.x * 0.5 - bar_w * 0.5, vp.y * 0.5 + 35.0)
	else:
		_charge_bar.visible = false

```

### `res://rain_system.gd`

```gdscript
extends Node3D
class_name RainSystem

# ============================================================
# RAIN SYSTEM v2 — random, timed rain events with:
#   - wind-driven, properly-oriented falling rain streaks
#   - impact splashes/sparks where rain hits the raft, roofs, walls,
#     foundations, stairs, doors, windows (raycast-based, pooled for perf)
#   - a softer ripple splash where rain lands on open ocean
#   - sky/ocean darkening + optional lightning + audio
# Attach as a child of Player (like RopeSystem) so the rain volume always
# follows the camera. Fully self-building at runtime — no manual scene
# setup beyond adding this one node and attaching this script.
# ============================================================

# --- Scheduling (real-world minutes; independent of the in-game day/night
# clock, which runs on its own 15-real-minutes-per-day cycle) ---
@export var min_interval_minutes: float = 6.0
@export var max_interval_minutes: float = 14.0
@export var rain_chance: float = 0.55
@export var min_duration_minutes: float = 1.5
@export var max_duration_minutes: float = 5.0

# --- Falling rain visuals ---
@export var particle_amount: int = 700
@export var rain_area_size: Vector3 = Vector3(24.0, 16.0, 24.0)
@export var fall_speed: float = 14.0
@export var fade_time: float = 4.0
## Horizontal drift while falling (x = east/west, y = north/south). Small
## values (0.2-0.6) read as believable wind-blown rain; 0,0 = dead vertical.
@export var wind_direction: Vector2 = Vector2(0.4, 0.15)
@export var toggle_fog_during_rain: bool = true

# --- Impact splashes ("sparks") where rain hits solid surfaces ---
@export var splash_enabled: bool = true
@export var splash_pool_size: int = 16
@export var splashes_per_second: float = 28.0   # scaled by current rain intensity
@export var splash_particle_count: int = 7
@export var splash_scan_radius: float = 11.0    # only spawn splashes reasonably close to camera
## Splashes are biased toward the camera's forward cone (where the raft,
## roof and deck are on screen) so rain visibly pounds the surfaces the
## player is looking at instead of scattering across empty ocean.
@export var forward_bias: float = 0.75
@export var forward_cone_radius: float = 4.5
## Also spawn (fainter, rarer) ripple splashes on open water, not just structures.
@export var water_splash_enabled: bool = true

# --- Audio (optional — assign your own .ogg/.wav in the Inspector) ---
@export var rain_sound: AudioStream = null
@export var thunder_sounds: Array[AudioStream] = []
@export var enable_lightning: bool = true
@export var lightning_chance_per_check: float = 0.12

var _player: Node3D = null
var _camera: Camera3D = null
var _sky3d: Node = null
var _sky: Node = null
var _env: Environment = null
var _ocean: Node = null

var _particles: GPUParticles3D = null
var _rain_mat: StandardMaterial3D = null
var _rain_process_mat: ParticleProcessMaterial = null
var _audio: AudioStreamPlayer = null
var _thunder_audio: AudioStreamPlayer = null
var _overlay: ColorRect = null
var _flash: ColorRect = null

var _splash_pool: Array[GPUParticles3D] = []
var _splash_index: int = 0
var _splash_accum: float = 0.0

var _schedule_timer: Timer = null
var _lightning_timer: Timer = null

var _is_raining: bool = false
var _intensity: float = 0.0
var _target_intensity: float = 0.0
var _rain_end_time: float = 0.0

var _orig_fog_density: float = -1.0
var _orig_ambient_energy: float = -1.0
var _orig_wave_height: float = -1.0


func _ready() -> void:
	add_to_group("rain_system")
	_find_refs()
	_build_particles()
	_build_splash_pool()
	_build_audio()
	_build_overlay()

	_schedule_timer = Timer.new()
	_schedule_timer.one_shot = true
	add_child(_schedule_timer)
	_schedule_timer.timeout.connect(_on_schedule_timeout)
	_queue_next_check()


func _find_refs() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and (_camera == null or not is_instance_valid(_camera)):
		_camera = _player.get_node_or_null("CamPivot/SpringArm3D/Camera3D")
	if _sky3d == null:
		var scene := get_tree().current_scene
		if scene != null:
			_sky3d = scene.get_node_or_null("Sky3D")
			_ocean = scene.get_node_or_null("Ocean")
	if _ocean == null:
		_ocean = get_tree().get_first_node_in_group("ocean")
	if _sky3d != null:
		_sky = _sky3d.get("sky")
		_env = _sky3d.get("environment") as Environment


# ============================================================
# BUILD: falling rain — thin stretched streaks oriented along the actual
# fall direction (wind + gravity), not just camera-facing sprites. This is
# the single biggest visual upgrade: real rain reads as diagonal lines that
# match the wind, not vertical confetti.
# ============================================================
func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "RainParticles"
	_particles.amount = particle_amount
	_particles.lifetime = maxf(rain_area_size.y / fall_speed, 0.5)
	_particles.emitting = false
	_particles.local_coords = true
	_particles.visibility_aabb = AABB(-rain_area_size, rain_area_size * 2.0)

	var mat := ParticleProcessMaterial.new()
	var fall_dir := Vector3(wind_direction.x, -3.0, wind_direction.y).normalized()
	mat.direction = fall_dir
	mat.spread = 4.0
	mat.gravity = Vector3(0, -4.0, 0)
	mat.initial_velocity_min = fall_speed * 0.9
	mat.initial_velocity_max = fall_speed * 1.1
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = rain_area_size * 0.5
	mat.scale_min = 0.85
	mat.scale_max = 1.3
	# THE KEY LINE for a real "streak" look: orient each quad's long axis
	# along its actual velocity (wind + fall) instead of leaving it flat.
	mat.set("particle_flag_align_y_to_velocity", true)
	_particles.process_material = mat
	_rain_process_mat = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, clampf(fall_speed * 0.045, 0.35, 0.9))
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.albedo_color = Color(0.75, 0.82, 0.9, 0.0)
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = _rain_mat
	_particles.draw_pass_1 = quad

	add_child(_particles)


# ============================================================
# BUILD: splash/spark impact pool — small one-shot bursts fired wherever a
# raycast finds a raindrop hitting the raft, a roof, a wall top, stairs,
# a door, or a window. Pooled and reused so performance stays flat no
# matter how long it rains (no growing node count).
# ============================================================
func _build_splash_pool() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.9, 0.95, 1.0, 0.95)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = smat

	for i in splash_pool_size:
		var p := GPUParticles3D.new()
		p.name = "Splash%d" % i
		p.amount = splash_particle_count
		p.lifetime = 0.45
		p.one_shot = true
		p.explosiveness = 0.95
		p.emitting = false
		# World-space: once fired, these must NOT follow RainSystem's own
		# per-frame repositioning onto the camera.
		p.local_coords = false
		p.draw_pass_1 = quad

		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 55.0
		pm.gravity = Vector3(0, -9.0, 0)
		pm.initial_velocity_min = 1.0
		pm.initial_velocity_max = 2.2
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		pm.damping_min = 1.0
		pm.damping_max = 2.2
		p.process_material = pm

		add_child(p)
		_splash_pool.append(p)


func _build_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "RainAudio"
	_audio.stream = rain_sound
	_audio.volume_db = -80.0
	add_child(_audio)

	_thunder_audio = AudioStreamPlayer.new()
	_thunder_audio.name = "ThunderAudio"
	add_child(_thunder_audio)

	if enable_lightning:
		_lightning_timer = Timer.new()
		_lightning_timer.wait_time = 6.0
		_lightning_timer.one_shot = false
		add_child(_lightning_timer)
		_lightning_timer.timeout.connect(_maybe_lightning)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RainOverlay"
	layer.layer = 15
	get_tree().current_scene.add_child.call_deferred(layer)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.55, 0.65, 0.75, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.call_deferred("add_child", _overlay)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.call_deferred("add_child", _flash)


# ============================================================
# SCHEDULING
# ============================================================
func _queue_next_check() -> void:
	var minutes := randf_range(min_interval_minutes, max_interval_minutes)
	_schedule_timer.start(minutes * 60.0)


func _on_schedule_timeout() -> void:
	if not _is_raining and randf() <= rain_chance:
		var duration := randf_range(min_duration_minutes, max_duration_minutes) * 60.0
		start_rain(duration)
	_queue_next_check()


# ============================================================
# PUBLIC CONTROL
# ============================================================
func start_rain(duration_seconds: float) -> void:
	_find_refs()
	if _is_raining:
		_rain_end_time = maxf(_rain_end_time, Time.get_ticks_msec() / 1000.0 + duration_seconds)
		return
	_is_raining = true
	_rain_end_time = Time.get_ticks_msec() / 1000.0 + duration_seconds
	_target_intensity = 1.0
	_particles.emitting = true
	if rain_sound != null:
		_audio.play()
	if _lightning_timer != null:
		_lightning_timer.start()
	_cache_environment_originals()
	if toggle_fog_during_rain and _sky != null:
		_sky.set("fog_visible", true)


func stop_rain() -> void:
	_is_raining = false
	_target_intensity = 0.0
	if _lightning_timer != null:
		_lightning_timer.stop()


func is_raining() -> bool:
	return _is_raining


func _cache_environment_originals() -> void:
	if _sky != null and _orig_fog_density < 0.0:
		_orig_fog_density = float(_sky.get("fog_density"))
	if _env != null and _orig_ambient_energy < 0.0:
		_orig_ambient_energy = _env.ambient_light_energy
	if _ocean != null and _orig_wave_height < 0.0:
		_orig_wave_height = float(_ocean.get("wave_height"))


func _process(delta: float) -> void:
	_follow_player()
	_update_intensity(delta)
	_process_splashes(delta)
	if _is_raining and Time.get_ticks_msec() / 1000.0 >= _rain_end_time:
		stop_rain()
	if not _is_raining and _intensity <= 0.001:
		if _particles.emitting:
			_particles.emitting = false
		if toggle_fog_during_rain and _sky != null and _orig_fog_density >= 0.0:
			_sky.set("fog_visible", false)
			_sky.set("fog_density", _orig_fog_density)


func _follow_player() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_find_refs()
		return
	global_position = _camera.global_position


func _update_intensity(delta: float) -> void:
	if fade_time <= 0.001:
		_intensity = _target_intensity
	else:
		_intensity = move_toward(_intensity, _target_intensity, delta / fade_time)

	if _rain_mat != null:
		_rain_mat.albedo_color.a = clampf(_intensity * 0.55, 0.0, 0.55)

	if rain_sound != null:
		_audio.volume_db = lerpf(-80.0, -6.0, _intensity)

	if _sky != null and _orig_fog_density >= 0.0:
		_sky.set("fog_density", lerpf(_orig_fog_density, _orig_fog_density + 0.01, _intensity))
	if _env != null and _orig_ambient_energy >= 0.0:
		_env.ambient_light_energy = lerpf(_orig_ambient_energy, _orig_ambient_energy * 0.7, _intensity)
	if _ocean != null and _orig_wave_height >= 0.0:
		_ocean.set("wave_height", lerpf(_orig_wave_height, _orig_wave_height * 1.35, _intensity))

	if _overlay != null:
		_overlay.color.a = clampf(_intensity * 0.08, 0.0, 0.08)

	if _flash != null and _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - delta * 2.0, 0.0)


# ============================================================
# IMPACT SPLASHES — periodically raycast down at random points near the
# camera; wherever a drop would land, fire a pooled splash burst. Hits on
# structures (raft/foundation/wall/roof/stairs/door/window, physics layer
# "Structures") get a brighter, faster burst; open water gets a softer one.
# ============================================================
func _process_splashes(delta: float) -> void:
	if not splash_enabled or not _is_raining or _intensity <= 0.05 or _camera == null:
		return
	_splash_accum += delta * splashes_per_second * _intensity
	while _splash_accum >= 1.0:
		_splash_accum -= 1.0
		_spawn_one_splash()


func _spawn_one_splash() -> void:
	var cam_pos := _camera.global_position
	# Bias sample points into the camera's forward cone — the raft/roof/surface
	# fill the middle of the screen, so most rain should visibly pound those
	# surfaces; the remaining samples scatter wider for ambient rain everywhere.
	var fwd := -_camera.global_transform.basis.z
	fwd.y = 0.0
	var fwd_n := fwd.normalized()
	var right := Vector3(-fwd_n.z, 0.0, fwd_n.x)
	var x: float
	var z: float
	if fwd_n.length() > 0.01 and randf() < forward_bias:
		var f_dist := sqrt(randf()) * forward_cone_radius
		var f_angle := randf_range(-1.0, 1.0)  # ~ +-57 degrees wide
		x = cam_pos.x + fwd_n.x * f_dist + right.x * f_angle * f_dist
		z = cam_pos.z + fwd_n.z * f_dist + right.z * f_angle * f_dist
	else:
		var angle := randf() * TAU
		var dist := sqrt(randf()) * splash_scan_radius
		x = cam_pos.x + cos(angle) * dist
		z = cam_pos.z + sin(angle) * dist

	var space_state := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, cam_pos.y + 14.0, z),
		Vector3(x, cam_pos.y - 20.0, z))
	# Layer 1 = Structures (raft, foundations, walls, roofs, stairs, doors,
	# windows) per the project's physics layer map — never debris (layer 2).
	q.collision_mask = 1
	var hit := space_state.intersect_ray(q)

	if hit:
		_fire_splash(hit.position, true)
		return

	if water_splash_enabled and _ocean != null:
		var water_y := float(_ocean.call("get_height", Vector3(x, 0.0, z)))
		_fire_splash(Vector3(x, water_y, z), false)


func _fire_splash(pos: Vector3, on_structure: bool) -> void:
	var p: GPUParticles3D = _splash_pool[_splash_index]
	_splash_index = (_splash_index + 1) % _splash_pool.size()
	p.global_position = pos + Vector3(0, 0.02, 0)
	var pm := p.process_material as ParticleProcessMaterial
	if pm != null:
		if on_structure:
			# Rain pounding wood/roof reads better with a slightly stronger,
			# denser burst — this is the "drop hitting the surface" moment.
			pm.initial_velocity_min = 1.4
			pm.initial_velocity_max = 2.8
			p.amount = splash_particle_count + 2
		else:
			# Softer, sparser ripple on open water — rain already animates
			# the ocean surface, this is just a subtle accent.
			pm.initial_velocity_min = 0.5
			pm.initial_velocity_max = 1.0
			p.amount = maxi(splash_particle_count / 2, 3)
	p.restart()
	p.emitting = true


func _maybe_lightning() -> void:
	if not _is_raining or not enable_lightning:
		return
	if randf() > lightning_chance_per_check:
		return
	if _flash != null:
		_flash.color.a = 0.5
	if thunder_sounds.size() > 0:
		_thunder_audio.stream = thunder_sounds.pick_random()
		_thunder_audio.volume_db = randf_range(-6.0, 2.0)
		await get_tree().create_timer(randf_range(0.3, 1.4)).timeout
		_thunder_audio.play()


# ============================================================
# DEV DEBUG KEY — F11 instantly toggles rain on/off for testing.
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F11:
		if _is_raining:
			stop_rain()
		else:
			start_rain(120.0)

```

### `res://mobile_controls.gd`

```gdscript
extends Control
class_name MobileControls

const Icons := preload("res://ui_icons.gd")

## ============================================================
## MOBILE TOUCH CONTROLS — joystick = move, touch-screen = look
##   - The bottom-left joystick DOCK is the ONLY movement control: touch it
##     (within its grab zone) and drag to walk. It stays fixed at the dock.
##   - Touching ANYWHERE ELSE on the screen and dragging rotates the camera
##     (look). A second finger can look while the first holds the joystick.
##   - Action buttons are INVISIBLE Button nodes whose circular icon art is
##     painted by this overlay's _draw() (original vector glyphs, reference
##     style). They feed the SAME Input actions as the keyboard:
##       JUMP(jump) RUN(sprint,hold) USE(interact) DIVE(move_down)
##       ROPE(rope_throw, HOLD to charge, release to throw) RECALL(rope_cancel)
##       BUILD(build/exit/cancel) EDIT(pick up aimed piece) REMOVE(remove_build)
##       PLACE(place_build / confirm edit) ROT(rotate_build) NEXT(cycle_build)
##   Buttons swap per mode: normal / build / edit.
##   - The survival HUD (bag/hotbar) may claim touches: anything its
##     claims_touch() reports is never turned into camera look, and while its
##     bag panel is open all gameplay input is suspended.
## Shows on touch/mobile devices automatically; `force_show` previews on PC.
## ============================================================

@export var force_show: bool = false
## Grab zone around the joystick dock, as a multiple of the stick radius.
## Touches inside it start movement; touches outside it start camera look.
@export var dock_zone_scale: float = 1.6
## Look sensitivity per touch-pixel (mouse is 0.003; fingers are coarser).
@export var look_sensitivity: float = 0.007
## Movement dead zone (0..1 of joystick travel).
@export var joystick_deadzone: float = 0.18

var _player: Node = null
var _shown := false

# --- touch tracking ---
var _move_id := -1
var _look_id := -1
var _base := Vector2.ZERO   # joystick base (screen)
var _knob := Vector2.ZERO   # joystick knob (screen)
var _stick := Vector2.ZERO  # joystick vector, y+ = forward
var _dock := Vector2.ZERO   # resting joystick position (bottom-left)

# --- buttons (invisible; icon art drawn by _draw) ---
var _btn_jump: Button
var _btn_run: Button
var _btn_use: Button
var _btn_dive: Button
var _btn_rope: Button
var _btn_recall: Button
var _btn_edit: Button
var _btn_climb: Button
var _btn_build: Button
var _btn_place: Button
var _btn_rotate: Button
var _btn_next: Button
var _btn_remove: Button
var _all_buttons: Array[Button] = []

# cached mode state
var _mode := "init"  # "normal" | "build" | "edit"
var _rope_busy := false
var _swimming := false
var _can_edit := false
var _can_interact := false  # center crosshair points at an interactable
var _can_climb := false     # swimming next to the raft — CLIMB button available

# reference to the survival HUD overlay (bag/hotbar), lazy
var _hud: Control = null


func _ready() -> void:
	# IMPORTANT: this full-screen Control must never swallow mouse events or it
	# blocks desktop mouse-look (e.g. after Esc shows the cursor). Buttons keep
	# their own mouse_filter = STOP; the overlay itself is IGNORE and receives
	# touches via _input() instead of the GUI.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No Control parent (this hangs off a CanvasLayer), so anchors are useless.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	_build_buttons()
	# Apply the correct initial visibility (scene default is `visible = true`,
	# which used to leave the touch UI on screen on desktop machines).
	_shown = _should_show()
	visible = _shown
	var vp := get_viewport()
	vp.size_changed.connect(_apply_viewport_size)
	_apply_viewport_size()


func _apply_viewport_size() -> void:
	size = get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	_layout()


func _process(_delta: float) -> void:
	_update_visibility()
	# While the bag panel is open the whole screen belongs to the HUD: drop the
	# joystick and any held action so nothing drifts behind the panel.
	if _hud_node() != null and _hud_node().is_blocking():
		if _move_id != -1 or Input.is_action_pressed("jump") or Input.is_action_pressed("sprint") \
				or Input.is_action_pressed("rope_throw") or Input.is_action_pressed("interact"):
			_move_id = -1
			_stick = Vector2.ZERO
			queue_redraw()
			_release_all_actions()
		return
	_update_movement_actions()
	_sync_mode()


# ============================================================
# VISIBILITY
# ============================================================
func _should_show() -> bool:
	# Mobile UI only on real mobile builds (Android/iOS/web-mobile) or when
	# force_show is enabled in the inspector for desktop preview. Never on a
	# plain PC — desktop keeps the keyboard + mouse and must not be covered by
	# touch controls (some desktops report a touchscreen and previously the UI
	# popped up there and got in the way).
	if force_show:
		return true
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	return false


func _update_visibility() -> void:
	var want := _should_show()
	if want == _shown:
		return
	_shown = want
	visible = want
	if not want:
		_release_all_actions()
		_move_id = -1
		_look_id = -1


func _hud_node() -> Control:
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("survival_hud") as Control
	return _hud


# ============================================================
# TOUCH ROUTING — via _input (mouse_filter is IGNORE so the mouse is never
# blocked). Touches claimed by the HUD (bag/hotbar/panel) or landing on an
# action button are left to those controls; the bottom-left joystick dock is
# the ONLY movement control; every other touch starts camera look.
# ============================================================
func _input(event: InputEvent) -> void:
	# F10 toggles the mobile UI on/off — handy for previewing it on a PC
	# (Android/iOS builds show it automatically).
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F10:
		force_show = not force_show
		return
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _over_button(event.position):
				return  # the Button handles it
			if _hud_node() != null and _hud_node().claims_touch(event.position):
				return  # bag / hotbar / open panel
			if _move_id == -1 and _in_dock_zone(event.position):
				_start_move(event.index)
			elif _look_id == -1:
				_start_look(event.index, event.position)
		else:
			_end_touch(event.index)
	elif event is InputEventScreenDrag:
		if _move_id != -1 and event.index == _move_id and _hud_node() != null and _hud_node().is_blocking():
			_move_id = -1
			_stick = Vector2.ZERO
			queue_redraw()
			_release_all_actions()
		elif event.index == _move_id:
			_update_move(event.position)
		elif event.index == _look_id:
			_update_look(event.relative)
	# Mouse events are deliberately ignored here — desktop keeps mouse + keys.


func _over_button(pos: Vector2) -> bool:
	for b in _all_buttons:
		if b != null and b.visible and b.get_global_rect().has_point(pos):
			return true
	return false


## True when the touch is inside the joystick dock's grab zone (the ONLY
## place movement can start — everywhere else on the screen looks around).
func _in_dock_zone(pos: Vector2) -> bool:
	return pos.distance_to(_dock) <= _joy_radius() * dock_zone_scale


func _start_move(index: int) -> void:
	_move_id = index
	# Movement always anchors to the fixed dock (no dynamic spawning) so the
	# rest of the screen stays free for camera look.
	_base = _dock
	_knob = _dock
	_stick = Vector2.ZERO
	queue_redraw()


func _update_move(pos: Vector2) -> void:
	var radius := _joy_radius()
	var delta := pos - _base
	var len := delta.length()
	if len > radius:
		delta = delta / len * radius
		_knob = _base + delta
	else:
		_knob = pos
	_stick = Vector2(delta.x / radius, -delta.y / radius)
	if _stick.length() > 1.0:
		_stick = _stick.normalized()
	queue_redraw()


func _end_touch(index: int) -> void:
	if index == _move_id:
		_move_id = -1
		_stick = Vector2.ZERO
		queue_redraw()
	if index == _look_id:
		_look_id = -1


func _start_look(index: int, _pos: Vector2) -> void:
	_look_id = index


func _update_look(rel: Vector2) -> void:
	var p := _get_player()
	if p != null and p.has_method("add_look_input"):
		p.add_look_input(rel, look_sensitivity)


func _joy_radius() -> float:
	return clampf(size.y * 0.16, 70.0, 150.0)


# ============================================================
# MOVE ACTIONS — synthesized every frame from the joystick vector
# ============================================================
func _update_movement_actions() -> void:
	if not visible:
		return
	if _move_id == -1:
		for a in ["move_forward", "move_back", "move_left", "move_right"]:
			if Input.is_action_pressed(a):
				Input.action_release(a)
		return
	var v := _stick
	_set_move_action("move_forward", clampf(v.y, 0.0, 1.0))
	_set_move_action("move_back", clampf(-v.y, 0.0, 1.0))
	_set_move_action("move_left", clampf(-v.x, 0.0, 1.0))
	_set_move_action("move_right", clampf(v.x, 0.0, 1.0))


func _set_move_action(action: StringName, strength: float) -> void:
	if strength <= joystick_deadzone:
		if Input.is_action_pressed(action):
			Input.action_release(action)
	elif not Input.is_action_pressed(action) or not is_equal_approx(Input.get_action_strength(action), strength):
		Input.action_press(action, strength)


func _release_all_actions() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "interact",
			"move_down", "rope_throw", "rope_cancel", "build", "place_build", "cycle_build",
			"rotate_build", "remove_build"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


# ============================================================
# BUTTONS (invisible, icon art drawn in _draw)
# ============================================================
func _build_buttons() -> void:
	_btn_jump = _make_button("jump")
	_btn_rope = _make_button("hook")
	_btn_recall = _make_button("back")
	_btn_run = _make_button("run")
	_btn_use = _make_button("hand")
	_btn_dive = _make_button("down")
	_btn_edit = _make_button("pencil")
	_btn_climb = _make_button("climb")
	_btn_build = _make_button("hammer")
	_btn_place = _make_button("check")
	_btn_rotate = _make_button("rot")
	_btn_next = _make_button("next")
	_btn_remove = _make_button("trash")

	_all_buttons = [_btn_jump, _btn_rope, _btn_recall, _btn_run, _btn_use, _btn_dive,
			_btn_climb, _btn_edit, _btn_build, _btn_place, _btn_rotate, _btn_next, _btn_remove]

	# Hold-style buttons: press the action on touch-down, release on touch-up.
	_btn_jump.button_down.connect(_press_action.bind("jump"))
	_btn_jump.button_up.connect(_release_action.bind("jump"))
	_btn_rope.button_down.connect(_press_action.bind("rope_throw"))
	_btn_rope.button_up.connect(_release_action.bind("rope_throw"))
	_btn_run.button_down.connect(_press_action.bind("sprint"))
	_btn_run.button_up.connect(_release_action.bind("sprint"))
	_btn_dive.button_down.connect(_press_action.bind("move_down"))
	_btn_dive.button_up.connect(_release_action.bind("move_down"))
	_btn_build.button_down.connect(_press_action.bind("build"))
	_btn_build.button_up.connect(_release_action.bind("build"))
	_btn_place.button_down.connect(_press_action.bind("place_build"))
	_btn_place.button_up.connect(_release_action.bind("place_build"))
	_btn_rotate.button_down.connect(_press_action.bind("rotate_build"))
	_btn_rotate.button_up.connect(_release_action.bind("rotate_build"))
	_btn_next.button_down.connect(_press_action.bind("cycle_build"))
	_btn_next.button_up.connect(_release_action.bind("cycle_build"))
	_btn_remove.button_down.connect(_press_action.bind("remove_build"))
	_btn_remove.button_up.connect(_release_action.bind("remove_build"))
	_btn_recall.button_down.connect(_press_action.bind("rope_cancel"))
	_btn_recall.button_up.connect(_release_action.bind("rope_cancel"))

	# Tap-style: USE is momentary (like pressing E), EDIT picks the aimed piece,
	# CLIMB boards the raft directly (same as E while swimming next to it).
	_btn_use.button_down.connect(_press_action.bind("interact"))
	_btn_use.button_up.connect(_release_action.bind("interact"))
	_btn_edit.pressed.connect(_on_edit_pressed)
	_btn_climb.pressed.connect(_on_climb_pressed)

	for b in _all_buttons:
		add_child(b)
		b.pressed.connect(_queue_redraw)
		b.button_down.connect(_queue_redraw)
		b.button_up.connect(_queue_redraw)
	_sync_mode()


func _queue_redraw() -> void:
	queue_redraw()


func _press_action(action: StringName) -> void:
	if visible:
		Input.action_press(action)


func _release_action(action: StringName) -> void:
	Input.action_release(action)


## One tap = the desktop "E, E" double-pickup of the piece under the crosshair.
func _on_edit_pressed() -> void:
	var p := _get_player()
	if p == null or not visible:
		return
	if p.has_method("_handle_double_click_edit"):
		p.call("_handle_double_click_edit")
		p.call("_handle_double_click_edit")


## Tap = pull the player out of the water onto the nearest deck edge. The
## button only appears while swimming next to the raft/foundation, so the
## press always succeeds (climb_out no-ops if the ledge moved away).
func _on_climb_pressed() -> void:
	var p := _get_player()
	if p == null or not visible:
		return
	if p.has_method("climb_out"):
		p.call("climb_out")


func _make_button(kind: String) -> Button:
	var b := Button.new()
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.set_meta("icon_kind", kind)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, empty)
	return b


# ============================================================
# MODE SYNC — which buttons are visible, and what BUILD does per mode.
# ============================================================
func _sync_mode() -> void:
	var p := _get_player()
	var editing: bool = p != null and p.get("_editing") != null
	var building: bool = p != null and p.get("build_mode") == true
	var swimming: bool = p != null and p.get("is_swimming") == true
	var rope: Node = null
	if p != null:
		rope = p.get_node_or_null("RopeSystem")
	var rope_busy: bool = rope != null and rope.has_method("is_active") and bool(rope.call("is_active"))

	var mode := "edit" if editing else ("build" if building else "normal")
	var can_edit := false
	if mode == "normal" and p != null and p.get("aim_valid") == true:
		var c: Node = p.get("aim_collider")
		if c != null and p.has_method("_find_editable_target"):
			can_edit = p.call("_find_editable_target", c) != null
	var can_interact := false
	if mode == "normal" and p != null and p.has_method("can_interact_now"):
		can_interact = bool(p.call("can_interact_now"))
	var can_climb := false
	if mode == "normal" and swimming and p != null and p.has_method("can_climb_out"):
		can_climb = bool(p.call("can_climb_out"))

	if mode == _mode and rope_busy == _rope_busy and swimming == _swimming \
			and can_edit == _can_edit and can_interact == _can_interact and can_climb == _can_climb:
		return
	_mode = mode
	_rope_busy = rope_busy
	_swimming = swimming
	_can_edit = can_edit
	_can_interact = can_interact
	_can_climb = can_climb

	var normal: bool = mode == "normal"
	_btn_jump.visible = normal
	_btn_run.visible = normal
	# The HAND button only appears when the center crosshair is actually over
	# an interactable (debris / door / usable piece) — same logic as the E key.
	_btn_use.visible = normal and can_interact
	_btn_dive.visible = normal and swimming
	# CLIMB appears ONLY while swimming right next to the raft/foundation
	# (same test as the E key) — never on land, never in open water.
	_btn_climb.visible = normal and can_climb
	_btn_rope.visible = normal
	_btn_recall.visible = normal and rope_busy
	_btn_edit.visible = normal and can_edit
	_btn_place.visible = mode != "normal"
	_btn_rotate.visible = mode != "normal"
	_btn_next.visible = mode == "build"
	_btn_remove.visible = mode == "edit"

	# If a hold-style button vanished while held (e.g. the target moved away
	# from the crosshair mid-press), release its action so it never sticks.
	if not _btn_use.visible and Input.is_action_pressed("interact"):
		Input.action_release("interact")
	if not _btn_rope.visible and Input.is_action_pressed("rope_throw"):
		Input.action_release("rope_throw")
	if not _btn_run.visible and Input.is_action_pressed("sprint"):
		Input.action_release("sprint")

	queue_redraw()


# ============================================================
# LAYOUT — right-edge cluster; everything scales with the viewport.
# ============================================================
func _layout() -> void:
	var vp := size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var m := clampf(vp.y * 0.018, 8.0, 18.0)
	var big := clampf(vp.y * 0.15, 92.0, 132.0)
	var small := clampf(vp.y * 0.085, 54.0, 80.0)
	var tiny := clampf(vp.y * 0.07, 46.0, 64.0)
	var right := vp.x - m
	var bottom := vp.y - m

	# Resting joystick position: bottom-left corner, inside the move zone.
	var jr := _joy_radius()
	_dock = Vector2(m + jr, vp.y - m - jr)

	# Right-edge column (bottom up): JUMP/PLACE (big), ROPE, RECALL.
	var col_x := right - big
	_btn_jump.position = Vector2(col_x, bottom - big)
	_btn_jump.size = Vector2(big, big)
	_btn_place.position = _btn_jump.position
	_btn_place.size = _btn_jump.size
	_btn_rope.position = Vector2(col_x, bottom - big - m - big)
	_btn_rope.size = Vector2(big, big)
	_btn_recall.position = Vector2(right - small, bottom - big - m - big - m - small)
	_btn_recall.size = Vector2(small, small)

	# Left-of-column small stack (bottom up): RUN/USE (normal), DIVE, CLIMB,
	# EDIT, and the ROT/NEXT/REMOVE equivalents in build/edit modes.
	var s_x := right - big - m - small
	_btn_run.position = Vector2(s_x, bottom - small)
	_btn_run.size = Vector2(small, small)
	_btn_use.position = Vector2(s_x, bottom - small - m - small)
	_btn_use.size = Vector2(small, small)
	_btn_dive.position = Vector2(s_x, bottom - small - m - small - m - small)
	_btn_dive.size = Vector2(small, small)
	_btn_climb.position = Vector2(s_x, bottom - small - m - small - m - small - m - small)
	_btn_climb.size = Vector2(small, small)
	_btn_edit.position = Vector2(s_x, bottom - small - m - small - m - small - m - small - m - small)
	_btn_edit.size = Vector2(small, small)
	_btn_next.position = _btn_run.position
	_btn_next.size = _btn_run.size
	_btn_rotate.position = _btn_use.position
	_btn_rotate.size = _btn_use.size
	_btn_remove.position = _btn_dive.position
	_btn_remove.size = Vector2(small, small)

	# LEFT-CENTER BUILD toggle (enter/exit build mode): sits above the
	# movement joystick's grab zone, out of the camera-look area and never on
	# top of the center crosshair. Turns into an X (cancel) while building.
	var b_size := small
	var b_x: float = m
	var b_y: float = clampf(vp.y * 0.36, m, _dock.y - jr * 1.9 - b_size)
	_btn_build.position = Vector2(b_x, b_y)
	_btn_build.size = Vector2(b_size, b_size)

	queue_redraw()


# ============================================================
# ICON ART — every visible action button is painted here as a dark glassy
# circle with an original white vector glyph (reference-style).
# ============================================================
func _button_icon_kind(b: Button) -> String:
	var kind: String = str(b.get_meta("icon_kind", "?"))
	if b == _btn_build:
		# The build toggle morphs with its mode: hammer = enter, X = exit/cancel.
		kind = "x" if (_mode == "build" or _mode == "edit") else "hammer"
	return kind


func _draw() -> void:
	if not visible:
		return
	var radius := _joy_radius()
	if _move_id != -1:
		_draw_dpad(_base, radius, _knob)
	else:
		# Idle dock — a faint resting D-pad so players can SEE where to put
		# their thumb instead of hunting for an invisible control.
		_draw_dpad(_dock, radius, _dock)
	# Action buttons on top of the D-pad? No — buttons live bottom-right; draw
	# them after so nothing overlaps incorrectly.
	for b in _all_buttons:
		if b == null or not b.visible:
			continue
		_draw_action_button(b)


func _draw_action_button(b: Button) -> void:
	var rect := b.get_global_rect()
	var center := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5
	var pressed := b.is_pressed() or b.has_focus()
	var bg := Color(0.06, 0.08, 0.11, 0.55) if not pressed else Color(0.16, 0.2, 0.28, 0.75)
	draw_circle(center, r * 0.92, bg)
	var ring: Color = Color(1, 1, 1, 0.32)
	if _button_icon_kind(b) == "hammer" and _mode == "normal":
		ring = Color(0.55, 0.9, 0.5, 0.5)
	elif _button_icon_kind(b) == "x":
		ring = Color(0.95, 0.4, 0.35, 0.5)
	elif _button_icon_kind(b) == "check":
		ring = Color(0.4, 0.95, 0.6, 0.5)
	elif _button_icon_kind(b) == "climb":
		ring = Color(0.4, 0.85, 0.95, 0.6)
	draw_arc(center, r * 0.92, 0.0, TAU, 40, ring, clampf(r * 0.06, 1.5, 3.0), true)
	var col := Color(1, 1, 1, 0.92) if not pressed else Color(1, 1, 1, 1.0)
	_draw_icon_glyph(b, center, r * 0.48, col)


func _draw_icon_glyph(b: Button, center: Vector2, r: float, col: Color) -> void:
	var w := clampf(r * 0.26, 3.0, 7.0)
	var kind := _button_icon_kind(b)
	match kind:
		"jump":
			Icons.arrow_up(self, center, r, w, col)
		"down":
			Icons.arrow_down(self, center, r, w, col)
		"back":
			Icons.arrow_left(self, center, r, w, col)
		"next":
			Icons.chevrons(self, center, Vector2.RIGHT, r, w, col)
		"check":
			Icons.check(self, center, r, w, col)
		"x":
			Icons.cross(self, center, r, w, col)
		"run":
			Icons.run(self, center, r * 1.15, w * 0.9, col)
		"hand":
			Icons.hand(self, center, r, w * 0.7, col)
		"climb":
			# Arrow up out of a wave — "pull yourself onto the raft".
			Icons.arrow_up(self, center + Vector2(0, -r * 0.1), r * 0.6, w, col)
			var wy := center.y + r * 0.45
			var wpts := PackedVector2Array()
			for wi in range(5):
				var wt := float(wi) / 4.0
				wpts.append(Vector2(center.x - r * 0.6 + wt * r * 1.2, wy + sin(wt * PI) * r * 0.18))
			draw_polyline(wpts, col, maxf(w * 0.7, 1.5), true)
		"hook":
			Icons.hook(self, center, r, w * 0.9, col)
		"hammer":
			Icons.hammer(self, center, r, w, col)
		"pencil":
			Icons.pencil(self, center, r, w, col)
		"trash":
			Icons.trash(self, center, r, w, col)
		"rot":
			Icons.rotate(self, center, r, w, col)
		_:
			Icons.check(self, center, r, w, col)


# ============================================================
# DEBUG DRAW — D-pad joystick: transparent base ring, four directional
# arrows pointing toward the central thumbstick (reference style).
# ============================================================
func _draw_dpad(center: Vector2, radius: float, knob_pos: Vector2) -> void:
	# Transparent base plate.
	draw_circle(center, radius, Color(1, 1, 1, 0.08))
	draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.28), 2.5)
	draw_arc(center, radius * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 1.5)
	# Four directional arrows pointing toward the central thumbstick.
	var dirs: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for dir in dirs:
		_draw_inward_arrow(center, dir, radius)
	# Central thumbstick (moves with the touch).
	var knob_r := clampf(radius * 0.34, 22.0, 44.0)
	draw_circle(knob_pos, knob_r, Color(1, 1, 1, 0.34))
	draw_arc(knob_pos, knob_r, 0.0, TAU, 32, Color(1, 1, 1, 0.45), 2.0)


## One directional chevron whose tip points IN toward the center (like the
## reference D-pad, where the arrows converge on the thumbstick).
func _draw_inward_arrow(center: Vector2, dir: Vector2, radius: float) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var tip := center + dir * radius * 0.30
	var back := center + dir * radius * 0.82
	var half_w := radius * 0.16
	var pts := PackedVector2Array([
		tip,
		back + perp * half_w,
		back - perp * half_w,
	])
	draw_colored_polygon(pts, Color(1, 1, 1, 0.34))


func _get_player() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player


# Exposed for tests: where the resting joystick dock sits.
func _dock_center() -> Vector2:
	return _dock

```

### `res://survival_hud.gd`

```gdscript
extends Control
class_name SurvivalHUD

const Icons := preload("res://ui_icons.gd")

## ============================================================
## MOBILE SURVIVAL HUD — graphical overlay shown on touch devices (and the
## desktop F10 preview). All art is drawn from primitives (no external icons).
##
## NORMAL MODE (Build Mode OFF):
##   - bottom-center: HOTBAR of inventory slots 0..5 (items the player owns)
##     + a BAG button at its right end. Tap a slot to make that item the
##     active one (highlighted). Tapping the BAG opens the 30-slot panel.
##   - bag panel: 30 slots (5 x 6). Rows 0-4 = bag-only slots 6..29, the
##     bottom row = the hotbar (slots 0..5, one authoritative array). Items
##     can be dragged between ANY two slots: move / merge / swap, and a drag
##     ghost follows the finger. Item pickups stack and overflow reports
##     "BAG FULL" instead of silently deleting anything.
## BUILD MODE (ON):
##   - the bottom hotbar temporarily becomes the BUILD-PIECE row (Foundation,
##     Wall, Roof, Stairs, Door, Window). Tapping a piece selects it for the
##     existing preview/placement system. Exiting Build Mode restores the
##     inventory hotbar exactly as it was (nothing is moved or changed).
##
## The HUD never swallows the mouse (desktop), only claims touches on its own
## controls; it coordinates with MobileControls via claims_touch()/is_blocking().
## ============================================================

const PIECE_ORDER := ["Foundation", "Wall", "Roof", "Stairs", "Door", "Window"]
const RESOURCE_PILL_ITEMS := ["Wood", "Rope", "Plastic", "Metal"]
const STATS := [["health", "Health"], ["hunger", "Hunger"], ["thirst", "Thirst"]]

const HOTBAR_COUNT := 6
const BAG_COLS := 5
const BAG_ROWS := 6   # 5x5 bag + 1 hotbar row = 30

var _bag_open := false

# --- geometry (recomputed every frame while visible) ---
var _vp := Vector2.ZERO
var _hotbar_rects: Array = []      # bottom bar (normal-mode items or build pieces)
var _bag_rect := Rect2()           # the BAG button (normal mode)
var _slot := 0.0                   # current slot size
var _panel_rect := Rect2()
var _close_rect := Rect2()
var _save_rect := Rect2()          # SAVE chip in the bag panel header
var _save_flash_until := 0.0       # brief "SAVED ✓" state after a quick-save
var _bag_slot_rects: Array = []    # 30 rects, index = inventory slot index
var _status_centers: Array = []
var _clock_center := Vector2.ZERO   # day/night clock at the far top-right
var _clock_r := 0.0
var _sky: Node = null
var _pill_rects: Array = []
var _chip_rect := Rect2()
var _chip_text := ""
var _toast := ""
var _toast_until := 0.0
var _toast_rect := Rect2()

# --- drag & touch ---
var _press_slot := -1
var _press_pos := Vector2.ZERO
var _dragging := false
var _drag_from := -1
var _drag_pos := Vector2.ZERO
var _press_bag := false
var _pressed_visual := -1

var _stats_node: Node = null
var _last_key := ""

# --- pause (button under the day/night clock) ---
var _pause_center := Vector2.ZERO
var _pause_btn_rect := Rect2()
var _paused := false
var _pause_panel_rect := Rect2()
var _pause_resume_rect := Rect2()
var _pause_quit_rect := Rect2()


func _ready() -> void:
	add_to_group("survival_hud")
	_stats_node = get_tree().root.get_node_or_null("/root/Stats")
	# Keep this HUD ticking (pause overlay, clock) while the game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	Inventory.changed.connect(_inventory_changed)
	Inventory.bag_full.connect(_on_bag_full)
	var vp := get_viewport()
	vp.size_changed.connect(_on_size_changed)
	visible = _should_show()
	_on_size_changed()


func _inventory_changed() -> void:
	_last_key = ""
	if visible:
		queue_redraw()


func _on_bag_full(amount: int) -> void:
	_show_toast("BAG FULL" if amount >= 1 else "")


func _show_toast(text: String) -> void:
	_toast = text
	_toast_until = Time.get_ticks_msec() / 1000.0 + 2.2
	queue_redraw()


## Public toast (used by the player for quick-save feedback etc.).
func show_toast(text: String) -> void:
	_show_toast(text)


func _should_show() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	var mc: Node = get_parent().get_node_or_null("MobileControls")
	return mc != null and bool(mc.get("force_show")) == true


func _on_size_changed() -> void:
	size = get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	queue_redraw()


func _process(_delta: float) -> void:
	var want := _should_show()
	if visible != want:
		visible = want
		if not want:
			_bag_open = false
			_cancel_drag()
		queue_redraw()
	if not visible:
		return
	_compute_layout()
	if _flash_active():
		queue_redraw()  # re-draw the "SAVED ✓" chip while it is lit
	var key := _build_cache_key()
	if key != _last_key:
		_last_key = key
		queue_redraw()


# ============================================================
# PUBLIC — coordination with MobileControls
# ============================================================
func is_blocking() -> bool:
	return visible and _bag_open


## Should MobileControls treat this screen point as HUD territory (never
## start camera look from it)?
func claims_touch(pos: Vector2) -> bool:
	if not visible:
		return false
	if _bag_open:
		return true
	if _bag_rect.has_point(pos):
		return true
	for r in _hotbar_rects:
		if r.has_point(pos):
			return true
	return false


func _in_build_mode() -> bool:
	var p := _get_player()
	return p != null and p.get("build_mode") == true


func _editing() -> bool:
	var p := _get_player()
	return p != null and p.get("_editing") != null


# ============================================================
# LAYOUT / GEOMETRY
# ============================================================
func _compute_layout() -> void:
	_vp = size
	if _vp.x <= 0.0 or _vp.y <= 0.0:
		return
	var m: float = maxf(12.0, _vp.y * 0.022)
	var top_safe: float = maxf(m, _vp.y * 0.035)
	var font := ThemeDB.fallback_font
	var cr: float = clampf(_vp.y * 0.05, 23.0, 34.0)
	var gap: float = cr * 0.16

	# top-right corner: day/night CLOCK occupies the far corner column; the
	# status circles sit to its LEFT so the clock's caption never overlaps them.
	_clock_center = Vector2(_vp.x - m - cr, top_safe + cr)
	_clock_r = cr
	var cap_fs: int = int(clampf(cr * 0.58, 14.0, 20.0))
	var cap_w: float = font.get_string_size("DAY 99", HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
	var cap_w2: float = font.get_string_size("88:88", HORIZONTAL_ALIGNMENT_LEFT, -1, cap_fs).x
	var clock_left: float = _clock_center.x - maxf(cap_w, cap_w2) * 0.5 - gap * 0.5
	_status_centers.clear()
	var sx := clock_left - cr
	for i in range(STATS.size()):
		_status_centers.append(Vector2(sx, top_safe + cr))
		sx -= cr * 2.0 + gap

	# pause button centered under the clock caption (same far-right column)
	_pause_btn_rect = Rect2()
	if _clock_r > 0.0:
		var pb_r: float = _clock_r * 0.66
		var pb_y: float = _clock_center.y + _clock_r + cap_fs * 1.75 + pb_r
		_pause_center = Vector2(_clock_center.x, pb_y)
		_pause_btn_rect = Rect2(_pause_center.x - pb_r, _pause_center.y - pb_r, pb_r * 2.0, pb_r * 2.0)

	# resource pills top-left
	_pill_rects.clear()
	var px := m
	var py := top_safe
	var ph: float = clampf(cr * 0.92, 22.0, 32.0)
	for item in RESOURCE_PILL_ITEMS:
		var count: int = int(Inventory.total(item))
		if count <= 0:
			continue
		var label := str(count)
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(ph * 0.56)).x
		var w: float = ph + tw + ph * 0.7
		_pill_rects.append(Rect2(px, py, w, ph))
		px += w + gap

	# bottom bar: normal = inventory slots + bag button; build = piece slots
	_slot = clampf(_vp.y * 0.105, 54.0, 86.0)
	var sg: float = _slot * 0.14
	var building: bool = _in_build_mode()
	var n: int = HOTBAR_COUNT
	var extra: int = 0 if building else 1  # bag button after the slots
	var total: float = float(n + extra) * _slot + float(n - 1 + extra) * sg
	var x0: float = (_vp.x - total) * 0.5
	var y0: float = _vp.y - m - _slot
	_hotbar_rects.clear()
	for i in range(n):
		_hotbar_rects.append(Rect2(x0 + float(i) * (_slot + sg), y0, _slot, _slot))
	_bag_rect = Rect2(x0 + float(n) * (_slot + sg), y0, _slot, _slot)

	# build/edit chip top-center
	_chip_text = _build_chip_text()
	if _chip_text != "":
		var fs: int = int(clampf(cr * 0.62, 14.0, 20.0))
		var cw: float = font.get_string_size(_chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + cr * 1.4
		var ch: float = cr * 1.15
		_chip_rect = Rect2((_vp.x - cw) * 0.5, top_safe, cw, ch)
	else:
		_chip_rect = Rect2()

	# bag panel grid (5 cols x 5 bag rows + 1 hotbar row = 30 slots)
	_bag_slot_rects.clear()
	if _bag_open:
		var cell: float = clampf(minf(_vp.x * 0.082, _vp.y * 0.072), 44.0, 78.0)
		var cg: float = cell * 0.16
		var pad: float = cell * 0.5
		var head_h: float = cell * 0.78
		var pw: float = float(BAG_COLS) * cell + float(BAG_COLS - 1) * cg + pad * 2.0
		var phh: float = float(BAG_ROWS) * cell + float(BAG_ROWS - 1) * cg + pad * 2.0 + head_h
		_panel_rect = Rect2((_vp.x - pw) * 0.5, (_vp.y - phh) * 0.5, pw, phh)
		var ccr: float = cell * 0.4
		_close_rect = Rect2(_panel_rect.end.x - ccr - pad * 0.6, _panel_rect.position.y + pad * 0.35, ccr, ccr)
		# SAVE chip in the header, left of the close button
		var sfs: int = int(clampf(cell * 0.3, 12.0, 18.0))
		var stxt: String = "SAVED ✓" if _flash_active() else "QUICK SAVE"
		var sw: float = font.get_string_size(stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		var scw: float = sw + cell * 0.5
		_save_rect = Rect2(_close_rect.position.x - scw - pad * 0.6, _panel_rect.position.y + pad * 0.35, scw, ccr)
		var grid_origin := Vector2(_panel_rect.position.x + pad, _panel_rect.position.y + pad + head_h)
		for idx in range(Inventory.SLOT_COUNT):
			var r := _row_of(idx)
			var c := _col_of(idx)
			var rr := Rect2(grid_origin.x + float(c) * (cell + cg),
				grid_origin.y + float(r) * (cell + cg), cell, cell)
			_bag_slot_rects.append(rr)
	else:
		_save_rect = Rect2()

	# toast pill (above the bottom bar)
	_toast_rect = Rect2()
	var now := Time.get_ticks_msec() / 1000.0
	if _toast != "" and now < _toast_until:
		var tfs: int = int(clampf(_slot * 0.3, 15.0, 24.0))
		var tw2: float = font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		var tw_: float = tw2 + _slot * 0.7
		var th: float = _slot * 0.5
		_toast_rect = Rect2((_vp.x - tw_) * 0.5, y0 - th - m, tw_, th)
	else:
		_toast = ""

	# pause overlay (drawn above everything while paused)
	if _paused:
		var ppad: float = clampf(_vp.y * 0.035, 16.0, 26.0)
		var ppw: float = minf(_vp.x * 0.72, 430.0)
		var ptrow: float = clampf(_vp.y * 0.055, 30.0, 46.0)
		var pbh2: float = clampf(_vp.y * 0.078, 46.0, 68.0)
		var psep2: float = clampf(_vp.y * 0.02, 10.0, 16.0)
		var pph2: float = ppad * 2.0 + ptrow + psep2 + pbh2 * 2.0 + psep2
		_pause_panel_rect = Rect2((_vp.x - ppw) * 0.5, (_vp.y - pph2) * 0.5, ppw, pph2)
		var pqx: float = _pause_panel_rect.position.x + ppad
		var pqw: float = ppw - ppad * 2.0
		_pause_resume_rect = Rect2(pqx, _pause_panel_rect.position.y + ppad + ptrow + psep2, pqw, pbh2)
		_pause_quit_rect = Rect2(pqx, _pause_resume_rect.end.y + psep2, pqw, pbh2)
	else:
		_pause_panel_rect = Rect2()
		_pause_resume_rect = Rect2()
		_pause_quit_rect = Rect2()


func _row_of(idx: int) -> int:
	if idx < HOTBAR_COUNT:
		return BAG_ROWS - 1
	return (idx - HOTBAR_COUNT) / BAG_COLS


func _col_of(idx: int) -> int:
	if idx < HOTBAR_COUNT:
		return idx
	return (idx - HOTBAR_COUNT) % BAG_COLS


func _idx_at(pos: Vector2) -> int:
	for i in range(_bag_slot_rects.size()):
		if (_bag_slot_rects[i] as Rect2).has_point(pos):
			return i
	return -1


func _build_cache_key() -> String:
	var p := _get_player()
	var key := str(_vp)
	key += "|bag" + str(_bag_open)
	if p == null:
		return key
	key += "|bm" + str(p.get("build_mode") == true)
	key += "|ed" + str(_editing())
	key += "|sel" + str(int(p.get("selected_piece_index")))
	key += "|act" + str(int(p.get("active_slot_index")))
	key += "|av" + str(p.get("active_item"))
	key += "|valid" + str(p.get("build_valid") == true)
	# inventory digest (totals are cheap; pickups/removals change them)
	for item in Inventory.items:
		key += "|" + item + str(int(Inventory.items.get(item, 0)))
	for s in STATS:
		key += "|" + s[0] + str(int(roundf(float(_get_stat(s[0])))))
	key += "|clk" + str(int(floorf(_time_now() * 60.0)))
	key += "|drag" + str(_dragging) + str(_drag_from) + str(_pressed_visual)
	key += "|toast" + _toast + str(Time.get_ticks_msec() / 1000.0 < _toast_until)
	key += "|save" + str(_flash_active())
	key += "|p" + str(_paused)
	return key


func _build_chip_text() -> String:
	var p := _get_player()
	if p == null:
		return ""
	if p.get("_editing") != null:
		return "EDITING  " + str(p.get("_editing").name).to_upper()
	if p.get("build_mode") != true:
		return ""
	var idx: int = clampi(int(p.get("selected_piece_index")), 0, PIECE_ORDER.size() - 1)
	var piece_name2: String = PIECE_ORDER[idx]
	var ok: bool = p.get("build_valid") == true
	var state := "READY" if ok else "NO SPOT"
	var cost := ""
	if Inventory.RECIPES.has(piece_name2):
		var parts: Array = []
		var recipe: Dictionary = Inventory.RECIPES[piece_name2]
		for item in recipe:
			parts.append("%s %d" % [str(item).substr(0, 3).to_upper(), int(recipe[item])])
		cost = "   " + "  ".join(parts)
	var afford := "OK" if Inventory.can_afford(piece_name2) else "NEED MORE"
	return "%s  %s%s   [%s]" % [piece_name2.to_upper(), state, cost, afford]


func _get_stat(which: String) -> float:
	if _stats_node == null or not is_instance_valid(_stats_node):
		return 100.0
	return float(_stats_node.get(which))


func _flash_active() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _save_flash_until


func _do_quick_save() -> void:
	var p := _get_player()
	if p == null or not p.has_method("quick_save"):
		return
	p.call("quick_save")
	_save_flash_until = Time.get_ticks_msec() / 1000.0 + 1.6
	queue_redraw()


func _cancel_drag() -> void:
	_press_slot = -1
	_dragging = false
	_drag_from = -1
	_pressed_visual = -1
	_press_bag = false


# ============================================================
# INPUT — touches on hotbar / bag / panel
# ============================================================
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _paused:
		# While paused only the overlay buttons react; nothing else moves.
		if event is InputEventScreenTouch:
			_handle_pause_input(event as InputEventScreenTouch)
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _pause_btn_rect.size.x > 0.0 and _pause_btn_rect.has_point(touch.position):
			_set_paused(true)
			get_viewport().set_input_as_handled()
			return
	if _bag_open:
		_handle_bag_input(event)
	else:
		_handle_bar_input(event)


func _handle_bar_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _bag_rect.has_point(touch.position) and not _in_build_mode():
				_press_bag = true
				_bag_open = true
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			for i in range(_hotbar_rects.size()):
				if (_hotbar_rects[i] as Rect2).has_point(touch.position):
					_pressed_visual = i
					_tap_bar_slot(i)
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
		else:
			_pressed_visual = -1
			queue_redraw()


## Normal mode: hotbar slot = inventory selection. Build mode: piece select.
func _tap_bar_slot(i: int) -> void:
	var p := _get_player()
	if p == null:
		return
	if _in_build_mode():
		if p.has_method("select_piece_for_build"):
			p.call("select_piece_for_build", i)
	elif p.has_method("select_hotbar_slot"):
		p.call("select_hotbar_slot", i)


func _handle_bag_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _save_rect.has_point(touch.position):
				_do_quick_save()
				get_viewport().set_input_as_handled()
				return
			_press_pos = touch.position
			var idx := _idx_at(touch.position)
			if idx >= 0 and not Inventory.slot_empty(idx):
				_press_slot = idx
				_pressed_visual = idx
			else:
				_press_slot = -1
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		# released
		var release_pos := touch.position
		if _press_slot >= 0:
			if _dragging:
				var dest := _idx_at(release_pos)
				if dest >= 0 and dest != _drag_from:
					Inventory.drop_into(_drag_from, dest)
					# selection lives on the hotbar row: keep it coherent
					_refresh_selection_after_move()
				_cancel_drag()
			else:
				# plain tap (no drag): hotbar-row tap selects the item
				if _press_slot < HOTBAR_COUNT:
					var p := _get_player()
					if p != null and p.has_method("select_hotbar_slot"):
						p.call("select_hotbar_slot", _press_slot)
				_cancel_drag()
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		# tap on background: close unless it started on the panel chrome
		if _close_rect.has_point(touch.position):
			_bag_open = false
			queue_redraw()
		elif not _panel_rect.has_point(touch.position):
			_bag_open = false
			queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _press_slot >= 0:
			if not _dragging and _press_pos.distance_to(drag.position) > 14.0:
				_dragging = true
				_drag_from = _press_slot
			if _dragging:
				_drag_pos = drag.position
			queue_redraw()
			get_viewport().set_input_as_handled()


func _handle_pause_input(t: InputEventScreenTouch) -> void:
	if t.pressed:
		if _pause_resume_rect.has_point(t.position):
			_set_paused(false)
		elif _pause_quit_rect.has_point(t.position):
			_quit_to_menu()
		get_viewport().set_input_as_handled()


func _set_paused(p: bool) -> void:
	if _paused == p:
		return
	_paused = p
	if p:
		_cancel_drag()
		_bag_open = false
	get_tree().paused = p
	queue_redraw()


func _quit_to_menu() -> void:
	var p := _get_player()
	if p != null and p.has_method("_flush_save"):
		p.call("_flush_save")
	_set_paused(false)
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _refresh_selection_after_move() -> void:
	var p := _get_player()
	if p != null and p.has_method("_refresh_active_item"):
		p.call("_refresh_active_item")


func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


# ============================================================
# DRAW
# ============================================================
func _draw() -> void:
	if not visible or _vp.x <= 0.0:
		return
	_draw_status()
	_draw_clock()
	_draw_pause_btn()
	_draw_pills()
	_draw_chip()
	if _bag_open:
		_draw_bag_panel()
	else:
		_draw_bottom_bar()
	if _toast != "" and _toast_rect.size.x > 0.0:
		_draw_toast()
	# drag ghost rides above everything
	if _dragging and _drag_from >= 0:
		_draw_drag_ghost()
	# pause overlay is the top-most layer
	if _paused:
		_draw_pause_overlay()


func _draw_pause_btn() -> void:
	if _pause_btn_rect.size.x <= 0.0:
		return
	var c := _pause_center
	var r: float = _pause_btn_rect.size.x * 0.5
	draw_circle(c, r, Color(0.05, 0.07, 0.1, 0.9))
	draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.32), maxf(r * 0.06, 1.0), true)
	var bw: float = maxf(r * 0.16, 1.6)
	var bh: float = r * 0.72
	draw_rect(Rect2(c.x - r * 0.3, c.y - bh * 0.5, bw, bh), Color(1, 1, 1, 0.95))
	draw_rect(Rect2(c.x + r * 0.3 - bw, c.y - bh * 0.5, bw, bh), Color(1, 1, 1, 0.95))


func _draw_pause_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, _vp), Color(0.0, 0.0, 0.0, 0.55))
	var rect := _pause_panel_rect
	if rect.size.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	_draw_rounded(rect, 24.0, Color(0.055, 0.075, 0.1, 0.98))
	_draw_rounded(rect, 24.0, Color(1, 1, 1, 0.25), false, 2.0)
	var tfs: int = int(clampf(rect.size.y * 0.08, 22.0, 36.0))
	var ttext := "PAUSED"
	var tw: float = font.get_string_size(ttext, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	_draw_text(ttext, Vector2(rect.position.x + (rect.size.x - tw) * 0.5,
			rect.position.y + rect.size.y * 0.1 + tfs * 0.36), tfs, Color(1, 1, 1, 0.97))
	_draw_pause_button(_pause_resume_rect, "RESUME", true)
	_draw_pause_button(_pause_quit_rect, "QUIT TO MENU", false)


func _draw_pause_button(btn: Rect2, label: String, primary: bool) -> void:
	if btn.size.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var bg: Color = Color(0.13, 0.26, 0.3, 0.98) if primary else Color(0.28, 0.16, 0.13, 0.98)
	var border: Color = Color(0.5, 0.95, 1.0, 0.75) if primary else Color(1.0, 0.72, 0.66, 0.6)
	_draw_rounded(btn, btn.size.y * 0.5, bg)
	_draw_rounded(btn, btn.size.y * 0.5, border, false, 2.0)
	var fs: int = int(clampf(btn.size.y * 0.42, 18.0, 28.0))
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(label, Vector2(btn.position.x + (btn.size.x - tw) * 0.5,
			btn.position.y + btn.size.y * 0.5 + fs * 0.36), fs, Color(1, 1, 1, 0.97))


func _draw_toast() -> void:
	_draw_rounded(_toast_rect, _toast_rect.size.y * 0.5, Color(0.55, 0.12, 0.1, 0.88))
	_draw_rounded(_toast_rect, _toast_rect.size.y * 0.5, Color(1, 1, 1, 0.35), false, 1.5)
	var fs: int = int(clampf(_toast_rect.size.y * 0.55, 15.0, 24.0))
	var font := ThemeDB.fallback_font
	var tw: float = font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(_toast, Vector2(_toast_rect.position.x + (_toast_rect.size.x - tw) * 0.5,
			_toast_rect.position.y + _toast_rect.size.y * 0.52 + fs * 0.34), fs, Color(1, 1, 1, 0.98))


## Bottom bar: NORMAL = inventory slots 0..5 + bag; BUILD = piece slots.
func _draw_bottom_bar() -> void:
	var building: bool = _in_build_mode()
	var p := _get_player()
	var sel_piece: int = int(p.get("selected_piece_index")) if p != null else -1
	var act_slot: int = int(p.get("active_slot_index")) if p != null else 0
	for i in range(_hotbar_rects.size()):
		var rect: Rect2 = _hotbar_rects[i]
		if building:
			var piece_sel: bool = i == sel_piece
			_draw_slot(rect, _pressed_visual == i, piece_sel)
			Icons.piece(self, PIECE_ORDER[i], rect.get_center(), _slot * 0.3,
				Color(0.88, 0.72, 0.42, 0.95) if piece_sel else Color(0.75, 0.6, 0.34, 0.85))
		else:
			var item_sel: bool = i == act_slot and not Inventory.slot_empty(i)
			_draw_slot(rect, _pressed_visual == i, item_sel)
			_draw_item_slot(rect, i, item_sel)
	if not building and _bag_rect.size.x > 0.0:
		_draw_slot(_bag_rect, _press_bag, false)
		Icons.backpack(self, _bag_rect.get_center(), _slot * 0.3, Color(0.9, 0.75, 0.45, 0.95))


func _draw_item_slot(rect: Rect2, idx: int, selected: bool) -> void:
	if Inventory.slot_empty(idx):
		return
	var item: String = Inventory.slot_item(idx)
	var count: int = Inventory.slot_count(idx)
	var glyph: Color = Color(1, 1, 1, 0.98) if selected else Color(0.95, 0.95, 0.95, 0.9)
	Icons.item_icon(self, item, rect.get_center(), _slot * 0.26)
	if count > 1:
		var fs: int = int(clampf(_slot * 0.28, 13.0, 22.0))
		var label := str(count)
		var font := ThemeDB.fallback_font
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_draw_text(label, Vector2(rect.end.x - tw - rect.size.x * 0.06,
				rect.position.y + rect.size.y * 0.8 + fs * 0.26), fs, glyph)
	else:
		# even count "1" is shown small, like the reference slot numbers
		var fs: int = int(clampf(_slot * 0.2, 10.0, 16.0))
		var label := str(count)
		var font := ThemeDB.fallback_font
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_draw_text(label, Vector2(rect.end.x - tw - rect.size.x * 0.06,
				rect.position.y + rect.size.y * 0.78 + fs * 0.24), fs, Color(1, 1, 1, 0.6))


func _draw_status() -> void:
	var cr: float = clampf(_vp.y * 0.05, 23.0, 34.0)
	var col: Color = Color(1, 1, 1, 0.9)
	var font := ThemeDB.fallback_font
	for i in range(STATS.size()):
		if i >= _status_centers.size():
			break
		var center: Vector2 = _status_centers[i]
		var c: Color = _status_bg(STATS[i][0])
		draw_circle(center, cr, c)
		draw_arc(center, cr, 0.0, TAU, 40, Color(1, 1, 1, 0.28), clampf(cr * 0.05, 1.5, 2.5), true)
		var glyph_r: float = cr * 0.52
		Icons.status_icon(self, STATS[i][0], center, glyph_r, Color(1, 1, 1, 0.95))
		var val: int = int(roundf(_get_stat(STATS[i][0])))
		var label := str(val)
		var fs: int = int(clampf(cr * 0.62, 13.0, 19.0))
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_draw_text(label, Vector2(center.x - tw * 0.5, center.y + cr + fs * 0.15), fs, col)


## Current in-game hour (float, Sky3D.current_time). Day number + hh:mm derive
## from it; falls back to 12.0 (noon) while the sky node is unavailable.
func _time_now() -> float:
	if _sky == null or not is_instance_valid(_sky):
		var sc: Node = get_tree().current_scene
		if sc != null:
			_sky = sc.get_node_or_null("Sky3D")
	if _sky != null and is_instance_valid(_sky) and _sky.get("current_time") != null:
		return float(_sky.get("current_time"))
	return 12.0


## Day/night clock: split circle (sun above / moon + stars below) with the
## saved day and clock time printed underneath, at the far top-right corner.
func _draw_clock() -> void:
	var c: Vector2 = _clock_center
	var r: float = _clock_r
	if r <= 4.0 or _clock_center == Vector2.ZERO:
		return
	var t := _time_now()
	var day: int = int(floorf(t / 24.0)) + 1
	var hh: int = int(t) % 24
	var mm: int = int((t - floorf(t)) * 60.0) % 60
	var font := ThemeDB.fallback_font
	var fs: int = int(clampf(r * 0.58, 14.0, 20.0))
	var lw: float = maxf(font.get_string_size("DAY 99", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
		font.get_string_size("88:88", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var cx: float = maxf(c.x, lw * 0.5 + 2.0)  # keep the caption fully on-screen

	# base dial (night navy) + thin ring + faint sunpath track
	draw_circle(c, r, Color(0.04, 0.06, 0.09, 0.97))
	draw_arc(c, r, 0.0, TAU, 44, Color(1, 1, 1, 0.32), maxf(r * 0.05, 1.2), true)
	draw_arc(c, r * 0.62, 0.0, TAU, 40, Color(1, 1, 1, 0.12), 1.0, true)

	# SUN POSITION on a 24 h dial: midnight at the bottom, sunrise on the left,
	# noon at the top, sunset on the right (theta_s points at the sun). The
	# amber "day" half is the semicircle FACING the sun, so it rotates through
	# the day — the dial reads as a sunrise -> noon -> sunset wheel.
	var theta_s: float = PI * 0.5 + ((12.0 - t) / 24.0) * TAU
	var is_day: bool = t >= 6.0 and t < 18.0
	# day half fades at dawn/dusk and goes faint at night
	var day_a: float = 0.22
	if is_day:
		day_a = 1.0
	elif t >= 5.0 and t < 19.0:
		day_a = 0.55
	var half := PackedVector2Array()
	half.append(c)
	var steps: int = 22
	for i in range(steps + 1):
		var a: float = theta_s - PI * 0.5 + PI * float(i) / float(steps)
		half.append(c + Vector2(cos(a), -sin(a)) * r * 0.97)
	draw_colored_polygon(half, Color(1.0, 0.68, 0.25, day_a))

	# orbital marker: the sun by day, a crescent moon on the opposite side by
	# night (moonrise/set mirror the sun around the dial)
	var mrk_a: float = theta_s if is_day else theta_s + PI
	var mrk: Vector2 = c + Vector2(cos(mrk_a), -sin(mrk_a)) * r * 0.62
	if is_day:
		draw_circle(mrk, r * 0.26, Color(1.0, 0.8, 0.35, 0.45))  # glow
		draw_circle(mrk, r * 0.17, Color(1.0, 0.95, 0.68, 1.0))
	else:
		var m2r: float = r * 0.17
		draw_circle(mrk, m2r, Color(0.9, 0.94, 1.0, 1.0))
		draw_circle(mrk + Vector2(m2r * 0.55, 0.0), m2r, Color(0.04, 0.06, 0.09, 1.0))

	# caption: DAY + clock time under the dial, centered on it
	var y0: float = c.y + r + fs * 0.1
	var day_txt := "DAY %d" % day
	var day_w: float = font.get_string_size(day_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(day_txt, Vector2(cx - day_w * 0.5, y0 + fs * 0.3), fs, Color(1, 0.92, 0.7, 0.98))
	var time_txt := "%02d:%02d" % [hh, mm]
	var time_w: float = font.get_string_size(time_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(time_txt, Vector2(cx - time_w * 0.5, y0 + fs * 0.3 + fs * 1.05), fs,
		Color(0.65, 0.9, 1.0, 0.95))


func _status_bg(kind: String) -> Color:
	match kind:
		"health":
			return Color(0.72, 0.16, 0.16, 0.62)
		"hunger":
			return Color(0.8, 0.52, 0.12, 0.62)
		"thirst":
			return Color(0.18, 0.48, 0.85, 0.62)
	return Color(0.3, 0.3, 0.34, 0.62)


func _draw_pills() -> void:
	var font := ThemeDB.fallback_font
	var ph: float = clampf(clampf(_vp.y * 0.05, 23.0, 34.0) * 0.92, 22.0, 32.0)
	for i in range(_pill_rects.size()):
		if i >= RESOURCE_PILL_ITEMS.size():
			break
		var rect: Rect2 = _pill_rects[i]
		var item: String = RESOURCE_PILL_ITEMS[i]
		draw_rect(rect, Color(0.05, 0.07, 0.1, 0.62), true)
		draw_rect(rect, Color(1, 1, 1, 0.16), false, 1.0)
		var center := Vector2(rect.position.x + ph * 0.5, rect.position.y + ph * 0.5)
		Icons.item_icon(self, item, center, ph * 0.34)
		var count: int = int(Inventory.total(item))
		var fs: int = int(ph * 0.5)
		var label := str(count)
		_draw_text(label, Vector2(rect.position.x + ph * 0.92, rect.position.y + ph * 0.5 + fs * 0.32), fs, Color(1, 1, 1, 0.95))


func _draw_chip() -> void:
	if _chip_text == "" or _chip_rect.size.x <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var fs: int = int(clampf(clampf(_vp.y * 0.05, 23.0, 34.0) * 0.62, 14.0, 20.0))
	draw_rect(_chip_rect, Color(0.04, 0.06, 0.09, 0.72), true)
	draw_rect(_chip_rect, Color(1, 1, 1, 0.2), false, 1.0)
	var tw: float = font.get_string_size(_chip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(_chip_text, Vector2(_chip_rect.position.x + (_chip_rect.size.x - tw) * 0.5,
			_chip_rect.position.y + _chip_rect.size.y * 0.5 + fs * 0.36), fs, Color(1, 1, 1, 0.95))


func _draw_bag_panel() -> void:
	draw_rect(Rect2(Vector2.ZERO, _vp), Color(0.0, 0.0, 0.0, 0.5))
	var font := ThemeDB.fallback_font
	var rect := _panel_rect
	_draw_rounded(rect, 22.0, Color(0.055, 0.075, 0.1, 0.98))
	_draw_rounded(rect, 22.0, Color(1, 1, 1, 0.2), false, 2.0)
	# header
	var fs: int = int(clampf(rect.size.y * 0.028, 17.0, 25.0))
	_draw_text("BACKPACK", Vector2(rect.position.x + rect.size.x * 0.045,
			rect.position.y + rect.size.y * 0.062 + fs * 0.2), fs, Color(1, 1, 1, 0.95))
	var sub: String = "DRAG TO MOVE / SWAP  -  TAP HOTBAR ROW TO USE"
	var sfs: int = int(fs * 0.5)
	var subw: float = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
	_draw_text(sub, Vector2(rect.position.x + rect.size.x * 0.045,
			rect.position.y + rect.size.y * 0.112 + sfs * 0.2), sfs, Color(1, 1, 1, 0.55))
	# quick-save chip + close button
	var ccr: float = _close_rect.size.x * 0.5
	if _save_rect.size.x > 0.0:
		var flash: bool = _flash_active()
		var sc := _save_rect.get_center()
		_draw_rounded(_save_rect, ccr * 0.55,
			Color(0.1, 0.45, 0.22, 0.95) if flash else Color(0.1, 0.16, 0.22, 0.9))
		_draw_rounded(_save_rect, ccr * 0.55, Color(1, 1, 1, 0.3), false, 1.5)
		var stxt: String = "SAVED ✓" if flash else "QUICK SAVE"
		var chip_fs: int = int(clampf(_save_rect.size.y * 0.34, 12.0, 18.0))
		var stw: float = font.get_string_size(stxt, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_fs).x
		_draw_text(stxt, Vector2(sc.x - stw * 0.5, sc.y + chip_fs * 0.34), chip_fs,
			Color(0.75, 1.0, 0.8, 1.0) if flash else Color(1, 1, 1, 0.92))
	var cc := _close_rect.get_center()
	draw_circle(cc, ccr, Color(1, 1, 1, 0.1))
	Icons.cross(self, cc, ccr * 0.9, clampf(ccr * 0.24, 2.0, 4.0), Color(1, 1, 1, 0.85))
	# grid
	var p := _get_player()
	var act_slot: int = int(p.get("active_slot_index")) if p != null else 0
	for idx in range(_bag_slot_rects.size()):
		var b: Rect2 = _bag_slot_rects[idx]
		var is_hotbar: bool = idx < HOTBAR_COUNT
		var selected: bool = is_hotbar and idx == act_slot and not Inventory.slot_empty(idx)
		_draw_slot(b, _pressed_visual == idx, selected)
		# hotbar row gets a subtle divider tint so it reads as the equip row
		if is_hotbar:
			_draw_rounded(b.grow(-2.0), b.size.x * 0.16, Color(1, 1, 1, 0.03), true, 1.0)
		if not Inventory.slot_empty(idx):
			Icons.item_icon(self, Inventory.slot_item(idx), b.get_center(), b.size.x * 0.24)
			var count: int = Inventory.slot_count(idx)
			if count > 0:
				var cfs: int = int(clampf(b.size.x * 0.28, 11.0, 20.0))
				var label := str(count)
				var tw2: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
				_draw_text(label, Vector2(b.end.x - tw2 - b.size.x * 0.08,
						b.position.y + b.size.y * 0.78 + cfs * 0.26), cfs, Color(1, 1, 1, 0.95))


func _draw_drag_ghost() -> void:
	if _drag_from < 0 or _drag_from >= Inventory.SLOT_COUNT or Inventory.slot_empty(_drag_from):
		return
	var size := _slot * 0.92
	var r := Rect2(_drag_pos.x - size * 0.5, _drag_pos.y - size * 0.5, size, size)
	_draw_slot(r, false, false)
	Icons.item_icon(self, Inventory.slot_item(_drag_from), r.get_center(), size * 0.28)
	var font := ThemeDB.fallback_font
	var count: int = Inventory.slot_count(_drag_from)
	if count > 1:
		var cfs: int = int(clampf(size * 0.26, 11.0, 20.0))
		var label := str(count)
		var tw2: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		_draw_text(label, Vector2(r.end.x - tw2 - r.size.x * 0.1, r.position.y + r.size.y * 0.8 + cfs * 0.24), cfs, Color(1, 1, 1, 0.98))


func _draw_slot(rect: Rect2, pressed: bool, selected: bool) -> void:
	var bg := Color(0.05, 0.07, 0.1, 0.66)
	if selected:
		bg = Color(0.1, 0.18, 0.24, 0.88)
	elif pressed:
		bg = Color(0.16, 0.2, 0.26, 0.82)
	var radius: float = rect.size.x * 0.2
	_draw_rounded(rect, radius, bg)
	var border: Color = Color(1, 1, 1, 0.25)
	if selected:
		border = Color(0.42, 0.92, 1.0, 0.95)
	elif pressed:
		border = Color(1, 1, 1, 0.6)
	_draw_rounded(rect.grow(-1.5), radius * 0.9, border, false, 2.0)
	if selected:
		_draw_rounded(rect.grow(2.0), radius, Color(0.42, 0.92, 1.0, 0.12), false, 3.0)


# ============================================================
# HELPERS
# ============================================================
func _draw_rounded(rect: Rect2, radius: float, color: Color, filled: bool = true, width: float = 1.0) -> void:
	if filled:
		draw_style_box(_rounded_style(color), rect)
	else:
		draw_style_box(_rounded_style_outline(color, width), rect)


func _rounded_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(18)
	s.set_border_width_all(0)
	return s


func _rounded_style_outline(color: Color, width: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.set_corner_radius_all(18)
	s.border_color = color
	s.set_border_width_all(int(maxf(width, 1.0)))
	return s


func _draw_text(text: String, top_left: Vector2, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, top_left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

```

### `res://ui_icons.gd`

```gdscript
class_name UiIcons
## Original vector icon library for the mobile UI. Every glyph is drawn from
## primitives (no external art): action buttons, build pieces, and survival
## resources. All drawing targets a CanvasItem (`c` = self).

static func _line(c: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	c.draw_line(a, b, col, w, true)


static func _circle(c: CanvasItem, center: Vector2, radius: float, col: Color, filled: bool = true, w: float = 0.0) -> void:
	if filled:
		c.draw_circle(center, radius, col)
	else:
		c.draw_arc(center, radius, 0.0, TAU, 40, col, maxf(w, 1.0), true)


# A single chevron pointing along `dir`.
static func chevron(c: CanvasItem, center: Vector2, dir: Vector2, len: float, w: float, col: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var tip := center + dir * len * 0.5
	var back := center - dir * len * 0.5
	_line(c, tip, back + perp * len * 0.42, w, col)
	_line(c, tip, back - perp * len * 0.42, w, col)


# Two chevrons (double arrow).
static func chevrons(c: CanvasItem, center: Vector2, dir: Vector2, len: float, w: float, col: Color) -> void:
	var off := dir * len * 0.26
	chevron(c, center - off, dir, len * 0.8, w, col)
	chevron(c, center + off, dir, len * 0.8, w, col)


static func arrow_up(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	chevron(c, center + Vector2(0, r * 0.05), Vector2.UP, r * 0.55, w, col)
	_line(c, center + Vector2(0, r * 0.62), center + Vector2(0, -r * 0.15), w, col)


static func arrow_down(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	chevron(c, center + Vector2(0, -r * 0.05), Vector2.DOWN, r * 0.55, w, col)
	_line(c, center + Vector2(0, -r * 0.62), center + Vector2(0, r * 0.15), w, col)


static func arrow_left(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	chevron(c, center, Vector2.LEFT, r * 0.6, w, col)


static func check(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(-r * 0.5, 0.0), center + Vector2(-r * 0.1, r * 0.42), w, col)
	_line(c, center + Vector2(-r * 0.1, r * 0.42), center + Vector2(r * 0.55, -r * 0.45), w, col)


static func cross(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(-r * 0.45, -r * 0.45), center + Vector2(r * 0.45, r * 0.45), w, col)
	_line(c, center + Vector2(r * 0.45, -r * 0.45), center + Vector2(-r * 0.45, r * 0.45), w, col)


# Running person silhouette.
static func run(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	# head
	_circle(c, center + Vector2(0, -r * 0.55), r * 0.2, col)
	# torso leaning forward
	_line(c, center + Vector2(-r * 0.2, -r * 0.32), center + Vector2(r * 0.25, r * 0.05), w * 1.5, col)
	# front leg (up) and back leg (extended back)
	_line(c, center + Vector2(r * 0.25, r * 0.05), center + Vector2(r * 0.05, r * 0.75), w * 1.4, col)
	_line(c, center + Vector2(-r * 0.2, -r * 0.32), center + Vector2(-r * 0.5, r * 0.35), w * 1.3, col)
	_line(c, center + Vector2(-r * 0.5, r * 0.35), center + Vector2(-r * 0.62, r * 0.72), w * 1.2, col)
	# swing arm
	_line(c, center + Vector2(r * 0.25, r * 0.05), center + Vector2(r * 0.55, -r * 0.4), w * 1.2, col)


# Simple open hand (interact).
static func hand(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	# palm
	var palm := center + Vector2(0, r * 0.25)
	_circle(c, palm, r * 0.34, col)
	# four fingers
	for i in range(4):
		var fx := center.x + (float(i) - 1.5) * r * 0.18
		var fy := center.y - r * 0.05
		_circle(c, Vector2(fx, fy), r * 0.11, col)
	# thumb
	_circle(c, center + Vector2(-r * 0.45, r * 0.05), r * 0.13, col)


# Fishing-hook shape (rope throw).
static func hook(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	var top := center + Vector2(0, -r * 0.62)
	var hook_c := center + Vector2(0, r * 0.18)
	var rad := r * 0.34
	_line(c, top, hook_c + Vector2(0, -rad), w * 1.2, col)
	c.draw_arc(hook_c, rad, -PI * 0.5, PI * 1.15, 24, col, w * 1.2, true)
	# barb
	var tip := hook_c + Vector2(sin(PI * 1.15) * rad, cos(PI * 1.15) * rad)
	_line(c, tip, tip + Vector2(-0.22, -0.14) * r, w * 1.0, col)
	# eye
	_circle(c, top, w * 0.62, col, false, w * 0.8)


# Hammer (enter build mode).
static func hammer(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(r * 0.35, r * 0.5), center + Vector2(-r * 0.35, -r * 0.42), w * 1.6, col)
	# head sits across the top of the handle
	var hs := r * 0.3
	var hx := center.x - r * 0.3 - hs * 0.9
	var hy := center.y - r * 0.42 - hs * 0.28
	c.draw_rect(Rect2(hx, hy, hs * 1.8, hs * 0.56), col)
	# second (peen) block to make the head read as two-lobed
	c.draw_rect(Rect2(hx - hs * 0.34, hy + hs * 0.1, hs * 0.34, hs * 0.36), col)


# Pencil (pick up piece for editing).
static func pencil(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(-r * 0.5, r * 0.5), center + Vector2(r * 0.42, -r * 0.42), w * 1.2, col)
	var tip := center + Vector2(r * 0.42, -r * 0.42)
	_line(c, tip, tip + Vector2(r * 0.14, -r * 0.02), w * 1.2, col)
	_line(c, center + Vector2(r * 0.42, -r * 0.42), center + Vector2(r * 0.5, -r * 0.28), w * 1.2, col)


# Trash bin (remove piece).
static func trash(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	_line(c, center + Vector2(-r * 0.5, -r * 0.45), center + Vector2(r * 0.5, -r * 0.45), w, col)
	_line(c, center + Vector2(-r * 0.3, -r * 0.45), center + Vector2(-r * 0.22, r * 0.55), w, col)
	_line(c, center + Vector2(r * 0.3, -r * 0.45), center + Vector2(r * 0.22, r * 0.55), w, col)
	_line(c, center + Vector2(-r * 0.22, r * 0.55), center + Vector2(r * 0.22, r * 0.55), w, col)
	_line(c, center + Vector2(-r * 0.06, -r * 0.32), center + Vector2(-r * 0.02, r * 0.4), w, col)
	_line(c, center + Vector2(r * 0.12, -r * 0.32), center + Vector2(r * 0.08, r * 0.4), w, col)


# Circular rotation arrow.
static func rotate(c: CanvasItem, center: Vector2, r: float, w: float, col: Color) -> void:
	var arc_r := r * 0.52
	# big arc leaving a gap at the bottom-right
	var a0 := -0.6
	var a1 := 4.9
	c.draw_arc(center, arc_r, a0, a1, 32, col, w, true)
	# arrowhead on the tip of the arc, pointing along travel direction
	var end := center + Vector2(cos(a1), sin(a1)) * arc_r
	var tang := Vector2(-sin(a1), cos(a1))
	var tip := end + tang * r * 0.16
	var back := end - tang * r * 0.1
	var perp := Vector2(-tang.y, tang.x)
	var pts := PackedVector2Array([tip, back + perp * r * 0.14, back - perp * r * 0.14])
	c.draw_colored_polygon(pts, col)


# ============================================================
# BUILD PIECES (hotbar glyphs)
# ============================================================
static func piece(c: CanvasItem, kind: String, center: Vector2, r: float, col: Color) -> void:
	match kind:
		"Foundation":
			c.draw_rect(Rect2(center.x - r * 0.62, center.y - r * 0.3, r * 1.24, r * 0.6), col)
		"Wall":
			c.draw_rect(Rect2(center.x - r * 0.42, center.y - r * 0.62, r * 0.84, r * 1.24), col)
		"Roof":
			var pts := PackedVector2Array([
				center + Vector2(0, -r * 0.62),
				center + Vector2(r * 0.64, r * 0.34),
				center + Vector2(-r * 0.64, r * 0.34),
			])
			c.draw_colored_polygon(pts, col)
			c.draw_rect(Rect2(center.x - r * 0.64, center.y + r * 0.34, r * 1.28, r * 0.16), col)
		"Stairs":
			for i in range(4):
				var y := center.y + r * 0.62 - float(i) * r * 0.34
				var x0 := center.x - r * 0.66 + float(i) * r * 0.32
				c.draw_rect(Rect2(x0, y - r * 0.3, r * (0.66 - float(i) * 0.16) + r * 0.32, r * 0.3), col)
		"Door":
			c.draw_rect(Rect2(center.x - r * 0.44, center.y - r * 0.62, r * 0.88, r * 1.24), col)
			c.draw_rect(Rect2(center.x - r * 0.16, center.y - r * 0.62, r * 0.32, r * 1.24), Color(0.05, 0.07, 0.1, 0.9))
		"Window":
			c.draw_rect(Rect2(center.x - r * 0.48, center.y - r * 0.62, r * 0.96, r * 1.24), col)
			c.draw_rect(Rect2(center.x - r * 0.3, center.y - r * 0.5, r * 0.16, r * 1.0), Color(0.05, 0.07, 0.1, 0.9))
			c.draw_rect(Rect2(center.x - r * 0.44, center.y - r * 0.1, r * 0.88, r * 0.16), Color(0.05, 0.07, 0.1, 0.9))
		_:
			_circle(c, center, r * 0.5, col)


# ============================================================
# SURVIVAL RESOURCES (bag grid + top pills)
# ============================================================
static func item_color(item: String) -> Color:
	match item:
		"Wood":
			return Color(0.66, 0.45, 0.22)
		"Rope":
			return Color(0.78, 0.66, 0.38)
		"Plastic":
			return Color(0.35, 0.72, 0.9)
		"Metal":
			return Color(0.62, 0.65, 0.7)
		"Barrel":
			return Color(0.75, 0.28, 0.2)
		"Stone":
			return Color(0.55, 0.55, 0.58)
	return Color(0.8, 0.8, 0.8)


static func item_icon(c: CanvasItem, item: String, center: Vector2, r: float) -> void:
	var col := item_color(item)
	match item:
		"Wood":
			# three stacked logs (end-on rings)
			for i in range(3):
				var off := Vector2(float(i - 1) * r * 0.55, r * 0.25)
				_circle(c, center + off, r * 0.3, col)
				_circle(c, center + off, r * 0.12, Color(0.9, 0.75, 0.45), true)
		"Rope":
			# coiled rope
			_circle(c, center, r * 0.5, col, false, r * 0.2)
			_circle(c, center, r * 0.18, col, false, r * 0.16)
			_circle(c, center, r * 0.05, col)
		"Plastic":
			# bottle
			c.draw_rect(Rect2(center.x - r * 0.2, center.y - r * 0.42, r * 0.4, r * 0.84), col)
			c.draw_rect(Rect2(center.x - r * 0.12, center.y - r * 0.62, r * 0.24, r * 0.24), col)
			c.draw_rect(Rect2(center.x - r * 0.3, center.y - r * 0.14, r * 0.6, r * 0.22), Color(0.9, 0.97, 1.0))
		"Metal":
			# ingot
			var pts := PackedVector2Array([
				center + Vector2(-r * 0.6, -r * 0.1),
				center + Vector2(-r * 0.4, -r * 0.5),
				center + Vector2(r * 0.4, -r * 0.5),
				center + Vector2(r * 0.6, -r * 0.1),
				center + Vector2(r * 0.35, r * 0.5),
				center + Vector2(-r * 0.35, r * 0.5),
			])
			c.draw_colored_polygon(pts, col)
		"Barrel":
			c.draw_rect(Rect2(center.x - r * 0.42, center.y - r * 0.62, r * 0.84, r * 1.24), col)
			c.draw_arc(center + Vector2(-r * 0.42, 0), r * 0.42, -PI * 0.5, PI * 0.5, 12, col, r * 0.18, true)
			c.draw_arc(center + Vector2(r * 0.42, 0), r * 0.42, PI * 0.5, PI * 1.5, 12, col, r * 0.18, true)
			_line(c, center + Vector2(-r * 0.42, -r * 0.2), center + Vector2(r * 0.42, -r * 0.2), r * 0.12, Color(0.9, 0.8, 0.6))
			_line(c, center + Vector2(-r * 0.42, r * 0.2), center + Vector2(r * 0.42, r * 0.2), r * 0.12, Color(0.9, 0.8, 0.6))
		"Stone":
			var pts2 := PackedVector2Array([
				center + Vector2(-r * 0.55, r * 0.2),
				center + Vector2(-r * 0.3, -r * 0.45),
				center + Vector2(r * 0.25, -r * 0.5),
				center + Vector2(r * 0.55, -r * 0.1),
				center + Vector2(r * 0.2, r * 0.5),
				center + Vector2(-r * 0.4, r * 0.45),
			])
			c.draw_colored_polygon(pts2, col)
		_:
			_circle(c, center, r * 0.5, col)


static func status_icon(c: CanvasItem, kind: String, center: Vector2, r: float, col: Color) -> void:
	match kind:
		"health":
			c.draw_rect(Rect2(center.x - r * 0.12, center.y - r * 0.55, r * 0.24, r * 1.1), col)
			c.draw_rect(Rect2(center.x - r * 0.55, center.y - r * 0.12, r * 1.1, r * 0.24), col)
		"hunger":
			# bowl
			c.draw_arc(center + Vector2(0, r * 0.1), r * 0.5, PI, TAU, 20, col, r * 0.2, true)
			_line(c, center + Vector2(-r * 0.6, r * 0.1), center + Vector2(r * 0.6, r * 0.1), r * 0.2, col)
		"thirst":
			# droplet
			var pts := PackedVector2Array([
				center + Vector2(0, -r * 0.6),
				center + Vector2(r * 0.42, r * 0.05),
				center + Vector2(0, r * 0.55),
				center + Vector2(-r * 0.42, r * 0.05),
			])
			c.draw_colored_polygon(pts, col)


static func backpack(c: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	c.draw_rect(Rect2(center.x - r * 0.55, center.y - r * 0.38, r * 1.1, r * 0.85), col)
	# flap
	c.draw_rect(Rect2(center.x - r * 0.55, center.y - r * 0.52, r * 1.1, r * 0.2), col)
	# straps
	c.draw_rect(Rect2(center.x - r * 0.3, center.y - r * 0.3, r * 0.16, r * 0.62), Color(0.9, 0.85, 0.7))
	c.draw_rect(Rect2(center.x + r * 0.14, center.y - r * 0.3, r * 0.16, r * 0.62), Color(0.9, 0.85, 0.7))
	# pocket
	c.draw_rect(Rect2(center.x - r * 0.2, center.y - r * 0.1, r * 0.4, r * 0.36), Color(0.85, 0.7, 0.45))

```

### `res://inventory.gd`

```gdscript
extends Node
## Register as an Autoload: Project Settings -> Globals -> Autoload
## Path: res://inventory.gd   Node Name: Inventory
##
## AUTHORITATIVE inventory: one array of 30 slots. The first six (0..5) are
## the hotbar (what the bottom bar shows in NORMAL mode); 6..29 is the bag.
## New pickups prefer the bag first so the hotbar stays the player's own
## arrangement (a fresh game starts with Rope in slot 0, per spec).
##
## `items` is a legacy convenience dict of TOTALS kept in sync for older code
## (crafting checks, debug HUD, resource pills). Everything mutates through
## the slot API below so the UI is never out of sync.

const SLOT_COUNT := 30
const HOTBAR_COUNT := 6
const MAX_STACK := 99
const BAG_START := HOTBAR_COUNT  # first bag-only slot index

signal changed
signal bag_full(amount: int)  # amount that could not be stored anywhere

const SAVE_PATH := "user://raft_save.json"        # autosave (written on change/quit)
const QUICK_SAVE_PATH := "user://raft_quicksave.json"  # manual quick-save slot
const SAVE_VERSION := 1

var slots: Array = []          # SLOT_COUNT entries: {} (empty) or {"item": String, "count": int}
var items := {"Wood": 0, "Rope": 0, "Plastic": 0, "Barrel": 0, "Stone": 0, "Metal": 0}
## Meta loaded by load_game() (active hotbar slot, day time, ...) so the game
## scene can restore state after a Continue — the menu applies it.
var loaded_meta: Dictionary = {}

# Test/debug toggle. When true, crafting never consumes resources (handy for
# trying out the building system). Flip it with the debug key in Player.
var infinite: bool = false

# What each craftable/placeable thing costs.
const RECIPES := {
	"Foundation":      {"Wood": 5},
	"Wall":            {"Wood": 8, "Rope": 1},
	"Roof":            {"Wood": 8, "Rope": 1},
	"Stairs":          {"Wood": 6, "Rope": 1},
	"Door":            {"Wood": 4, "Rope": 1},
	"Window":          {"Wood": 3, "Plastic": 1},
	"Bonfire":         {"Wood": 8, "Rope": 2},
	"Raft Extension":  {"Wood": 10, "Plastic": 2},
}


func _ready() -> void:
	_ensure_slots()


func _ensure_slots() -> void:
	if slots.size() != SLOT_COUNT:
		slots.clear()
		for i in range(SLOT_COUNT):
			slots.append({})


# ---------------------------------------------------------------
# Slot access helpers (UI + internal)
# ---------------------------------------------------------------
func slot_get(idx: int) -> Dictionary:
	if idx < 0 or idx >= slots.size():
		return {}
	return slots[idx]


func slot_empty(idx: int) -> bool:
	return idx < 0 or idx >= slots.size() or slots[idx].is_empty()


func slot_item(idx: int) -> String:
	var s: Dictionary = slot_get(idx)
	return str(s.get("item", "")) if not s.is_empty() else ""


func slot_count(idx: int) -> int:
	var s: Dictionary = slot_get(idx)
	return int(s.get("count", 0)) if not s.is_empty() else 0


func is_empty() -> bool:
	for s in slots:
		if not s.is_empty():
			return false
	return true


func total_count() -> int:
	var t := 0
	for s in slots:
		if not s.is_empty():
			t += int(s.get("count", 0))
	return t


func total(item: String) -> int:
	var t := 0
	for i in range(slots.size()):
		if not slot_empty(i) and slot_item(i) == item:
			t += slot_count(i)
	return t


## Place an item directly into a specific slot (used for the fresh-game Rope
## in slot 1). Overwrites nothing — only writes when the slot is empty.
func place_at(idx: int, item: String, count: int) -> bool:
	_ensure_slots()
	if idx < 0 or idx >= slots.size() or not slot_empty(idx) or count <= 0:
		return false
	slots[idx] = {"item": item, "count": int(count)}
	_recompute()
	emit_signal("changed")
	return true


## Move slot a -> slot b. Empty dest = move; same item = merge (remainder
## stays in a); different item = swap. Never duplicates or loses items.
func drop_into(from_idx: int, to_idx: int) -> void:
	_ensure_slots()
	if from_idx == to_idx or from_idx < 0 or from_idx >= slots.size() \
		or to_idx < 0 or to_idx >= slots.size() or slot_empty(from_idx):
		return
	var f: Dictionary = slots[from_idx]
	var t: Dictionary = slots[to_idx]
	if t.is_empty():
		slots[to_idx] = f
		slots[from_idx] = {}
	elif str(t.get("item", "")) == str(f.get("item", "")) and int(t.get("count", 0)) < MAX_STACK:
		var room: int = MAX_STACK - int(t.get("count", 0))
		var take: int = mini(int(f.get("count", 0)), room)
		t["count"] = int(t.get("count", 0)) + take
		f["count"] = int(f.get("count", 0)) - take
		if int(f.get("count", 0)) <= 0:
			slots[from_idx] = {}
	else:
		slots[to_idx] = f
		slots[from_idx] = t
	_recompute()
	emit_signal("changed")


func swap_slots(a: int, b: int) -> void:
	_ensure_slots()
	if a == b or a < 0 or a >= slots.size() or b < 0 or b >= slots.size():
		return
	var tmp: Dictionary = slots[a]
	slots[a] = slots[b]
	slots[b] = tmp
	_recompute()
	emit_signal("changed")


# ---------------------------------------------------------------
# Legacy count API (used by debris, crafting, refunds, debug HUD)
# ---------------------------------------------------------------
## Add an item. Existing partial stacks are topped up first (bag stacks before
## hotbar stacks), then new stacks go into the bag, and only as a last resort
## into an empty hotbar slot. Whatever cannot be stored is reported via
## bag_full() and returned — nothing is ever silently deleted.
func add(item: String, amount: int = 1) -> int:
	_ensure_slots()
	if amount <= 0:
		return 0
	var remaining: int = amount
	# 1) Top up partial stacks of the same item anywhere (bag first).
	remaining = _fill_partial_stacks(item, remaining, BAG_START, SLOT_COUNT - 1)
	remaining = _fill_partial_stacks(item, remaining, 0, BAG_START - 1)
	# 2) New stacks into bag-only slots.
	remaining = _fill_empty_stacks(item, remaining, BAG_START, SLOT_COUNT - 1)
	# 3) Last resort: new stacks in free hotbar slots.
	remaining = _fill_empty_stacks(item, remaining, 0, BAG_START - 1)
	if remaining > 0:
		emit_signal("bag_full", remaining)
	_recompute()
	emit_signal("changed")
	return remaining


func _fill_partial_stacks(item: String, amount: int, from: int, to: int) -> int:
	var remaining: int = amount
	for i in range(from, to + 1):
		if remaining <= 0:
			break
		if slot_empty(i) or slot_item(i) != item:
			continue
		var room: int = MAX_STACK - slot_count(i)
		if room <= 0:
			continue
		var take: int = mini(remaining, room)
		slots[i]["count"] = slot_count(i) + take
		remaining -= take
	return remaining


func _fill_empty_stacks(item: String, amount: int, from: int, to: int) -> int:
	var remaining: int = amount
	for i in range(from, to + 1):
		if remaining <= 0:
			break
		if not slot_empty(i):
			continue
		var take: int = mini(remaining, MAX_STACK)
		slots[i] = {"item": item, "count": take}
		remaining -= take
	return remaining


## Remove `amount` of an item, consuming bag stacks before hotbar stacks.
func remove(item: String, amount: int) -> void:
	_ensure_slots()
	var remaining: int = amount
	for i in range(SLOT_COUNT - 1, -1, -1):
		if remaining <= 0:
			break
		if slot_empty(i) or slot_item(i) != item:
			continue
		var take: int = mini(remaining, slot_count(i))
		slots[i]["count"] = slot_count(i) - take
		if slot_count(i) <= 0:
			slots[i] = {}
		remaining -= take
	if remaining > 0:
		# Never let a total go negative (guards callers that forget has()).
		push_warning("[Inventory] remove(%s, %d) had only %d" % [item, amount, amount - remaining])
	_recompute()
	emit_signal("changed")


func has(item: String, amount: int) -> bool:
	return total(item) >= amount


func can_afford(recipe: String) -> bool:
	if infinite:
		return true
	if not RECIPES.has(recipe):
		return false
	for item in RECIPES[recipe]:
		if total(item) < RECIPES[recipe][item]:
			return false
	return true


func craft(recipe: String) -> bool:
	if not RECIPES.has(recipe):
		return false
	# Re-check affordability here too, not just in the caller — craft() must
	# never be the thing that lets an item count go negative, even if some
	# future caller forgets to check can_afford() first.
	if not can_afford(recipe):
		return false
	if infinite:
		return true
	for item in RECIPES[recipe]:
		remove(item, RECIPES[recipe][item])
	return true


func _recompute() -> void:
	for k in items:
		items[k] = 0
	for i in range(slots.size()):
		if slot_empty(i):
			continue
		var item_name: String = slot_item(i)
		if not items.has(item_name):
			items[item_name] = 0
		items[item_name] = int(items[item_name]) + slot_count(i)


# ================================================================
# Save / Load — two slots under user://:
#   "main"  = autosave  (debounced on change + on quit) — Continue loads this
#   "quick" = manual quick-save snapshot (F5 on desktop, SAVE chip in the bag
#             panel on mobile) — the menu offers it as a second Continue option
# ================================================================
func _save_path_for(slot: String) -> String:
	return QUICK_SAVE_PATH if slot == "quick" else SAVE_PATH


func has_save(slot: String = "main") -> bool:
	return FileAccess.file_exists(_save_path_for(slot))


func save_game(extra: Dictionary = {}, slot: String = "main") -> void:
	_ensure_slots()
	var slot_data: Array = []
	for i in range(slots.size()):
		if slot_empty(i):
			slot_data.append([])
		else:
			slot_data.append([slot_item(i), slot_count(i)])
	var data := {
		"version": SAVE_VERSION,
		"slots": slot_data,
		"saved_at": Time.get_unix_time_from_system(),
	}
	for k in extra:
		data[str(k)] = extra[k]
	var f := FileAccess.open(_save_path_for(slot), FileAccess.WRITE)
	if f == null:
		push_warning("[Inventory] Could not open save file for writing.")
		return
	f.store_string(JSON.stringify(data))
	f.close()


## Reads just the meta of a slot without touching the live inventory
## (used by the menu to label Continue buttons, e.g. "DAY 2 · 15:30").
func save_info(slot: String = "main") -> Dictionary:
	var path := _save_path_for(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	return parsed


## Loads a slot's save into the inventory (replacing current contents) and
## returns the meta it carried. Returns {} when there is no save.
func load_game(slot: String = "main") -> Dictionary:
	loaded_meta = {}
	if not has_save(slot):
		return {}
	var f := FileAccess.open(_save_path_for(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	_ensure_slots()
	for i in range(slots.size()):
		slots[i] = {}
	var stored: Array = data.get("slots", [])
	for i in range(mini(stored.size(), SLOT_COUNT)):
		var entry = stored[i]
		if entry is Array and entry.size() >= 2 and (str(entry[0]) != "") and int(entry[1]) > 0:
			slots[i] = {"item": str(entry[0]), "count": int(entry[1])}
	loaded_meta = data.duplicate()
	loaded_meta.erase("version")
	loaded_meta.erase("slots")
	loaded_meta.erase("saved_at")
	_recompute()
	emit_signal("changed")
	return loaded_meta


## Wipe everything (used by "New Game"). Also removes BOTH save files so the
## next boot offers only New Game until something is collected/saved again.
func new_game_reset() -> void:
	_ensure_slots()
	for i in range(slots.size()):
		slots[i] = {}
	loaded_meta = {}
	_recompute()
	emit_signal("changed")
	for slot in [SAVE_PATH, QUICK_SAVE_PATH]:
		if FileAccess.file_exists(slot):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))

```

### `res://stats.gd`

```gdscript
extends Node
signal stat_changed(stat_name: String, value: float)
signal player_died

const MAX_VALUE := 100.0
@export var hunger_drain_rate: float = 0.4
@export var thirst_drain_rate: float = 0.6
## Stat drain is OFF until food/water sources exist (no eatables drop yet) —
## set this true (or the drain rates) when adding consumables so survivors
## actually need to eat and drink.
@export var enabled := false

var health: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0

func _process(delta: float) -> void:
	if not enabled:
		return
	hunger = clampf(hunger - hunger_drain_rate * delta, 0.0, MAX_VALUE)
	thirst = clampf(thirst - thirst_drain_rate * delta, 0.0, MAX_VALUE)
	stat_changed.emit("hunger", hunger)
	stat_changed.emit("thirst", thirst)
	if hunger <= 0.0 or thirst <= 0.0:
		change_health(-2.0 * delta)

func change_health(amount: float) -> void:
	health = clampf(health + amount, 0.0, MAX_VALUE)
	stat_changed.emit("health", health)
	if health <= 0.0:
		player_died.emit()

func eat(food_value: float) -> void:
	hunger = clampf(hunger + food_value, 0.0, MAX_VALUE)

func drink(thirst_value: float, health_bonus: float = 0.0) -> void:
	thirst = clampf(thirst + thirst_value, 0.0, MAX_VALUE)
	if health_bonus != 0.0:
		change_health(health_bonus)
```

### `res://door.gd`

```gdscript
extends StaticBody3D
class_name Door
@export var open_angle: float = 90.0
@export var swing_speed: float = 4.0
var is_open: bool = false
var _target_rotation: float = 0.0
var _swinging: bool = false

# Only the LEAF swings like a real door — the frame stays fixed. The leaf
# pivots on its hinge edge (LeafPivot is positioned at the hinge line), so
# rotating the pivot swings the leaf without moving the static frame.
@onready var _leaf_pivot: Node3D = $LeafPivot

func toggle() -> void:
	is_open = !is_open
	_target_rotation = deg_to_rad(open_angle) if is_open else 0.0
	_swinging = true

func _physics_process(delta: float) -> void:
	if _swinging and _leaf_pivot != null:
		_leaf_pivot.rotation.y = lerp_angle(_leaf_pivot.rotation.y, _target_rotation, delta * swing_speed)
		if absf(_leaf_pivot.rotation.y - _target_rotation) < 0.01:
			_leaf_pivot.rotation.y = _target_rotation
			_swinging = false

```

### `res://main_menu.gd`

```gdscript
extends Control
## ============================================================
## MAIN MENU — survival-styled ocean start screen.
## Fully drawn from primitives (no external art): a dusk sky with a low sun
## over animated waves, a wooden title plaque, and wood-plank action buttons.
##   - No saves            -> NEW GAME only
##   - Autosave present    -> CONTINUE (resumes it)
##   - Quick-save present  -> QUICK SAVE (second resume option)
## Each resume button shows the saved in-game day/time.
## ============================================================

const GAME_SCENE := "res://main.tscn"

# button ids in display order
var _buttons: Array = []          # of {id, label, sub}
var _btn_rects: Array = []        # parallel Rect2
var _hover := -1
var _press := -1
var _busy := false
var _t := 0.0
var _vp := Vector2.ZERO
var _title_w := 0.0

func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_buttons.clear()
	if Inventory.has_save("main"):
		_buttons.append({"id": "continue", "label": "CONTINUE",
			"sub": _save_sub("main")})
	if Inventory.has_save("quick"):
		_buttons.append({"id": "quick", "label": "QUICK SAVE",
			"sub": _save_sub("quick")})
	_buttons.append({"id": "new", "label": "NEW GAME", "sub": ""})
	queue_redraw()


## Human label for a save slot: "DAY n · hh:mm" from the saved game time.
func _save_sub(slot: String) -> String:
	var info: Dictionary = Inventory.save_info(slot)
	if info.has("game_time"):
		var gt: float = float(info["game_time"])
		var day: int = int(floorf(gt / 24.0)) + 1
		var h: int = int(gt) % 24
		var m: int = int((gt - floorf(gt)) * 60.0) % 60
		return "DAY %d  ·  %02d:%02d" % [day, h, m]
	if info.has("saved_at"):
		var stamp: String = Time.get_datetime_string_from_unix_time(int(info["saved_at"]), true)
		if stamp.length() >= 16:
			return "SAVED  " + stamp.substr(0, 16)
	return ""


func _process(delta: float) -> void:
	_t += delta
	if not visible:
		return
	_vp = size
	# hover tracking (mouse)
	if not OS.has_feature("mobile") and not OS.has_feature("android") \
			and not OS.has_feature("ios"):
		var mp := get_global_mouse_position()
		_hover = _btn_at(mp)
	queue_redraw()  # animated waves need a redraw every frame


# ============================================================
# INPUT — custom buttons (works with mouse and touch)
# ============================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = _btn_at(mb.position)
			else:
				if _btn_at(mb.position) == _press:
					_activate(_press, mb.position)
				_press = -1
			queue_redraw()
			accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_press = _btn_at(t.position)
		elif _press >= 0:
			if _btn_at(t.position) == _press:
				_activate(_press, t.position)
			_press = -1
		queue_redraw()
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


func _btn_at(pos: Vector2) -> int:
	for i in range(_btn_rects.size()):
		if (_btn_rects[i] as Rect2).has_point(pos):
			return i
	return -1


func _activate(btn_idx: int, _pos: Vector2) -> void:
	if btn_idx < 0 or btn_idx >= _buttons.size() or _busy:
		return
	_busy = true
	var id: String = _buttons[btn_idx]["id"]
	if id == "continue":
		Inventory.load_game("main")
	elif id == "quick":
		Inventory.load_game("quick")
	else:
		Inventory.new_game_reset()
	get_tree().change_scene_to_file(GAME_SCENE)


# ============================================================
# LAYOUT
# ============================================================
func _layout_buttons() -> void:
	_btn_rects.clear()
	var s := _vp
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var bw: float = minf(s.x * 0.78, 440.0)
	var bhs: Array = []
	for b in _buttons:
		bhs.append(104.0 if str(b["sub"]) != "" else 92.0)
	var gap: float = 20.0
	var total_h: float = 0.0
	for h in bhs:
		total_h += float(h)
	total_h += gap * float(maxi(0, bhs.size() - 1))
	var y: float = (s.y * 0.5) - total_h * 0.5 + s.y * 0.03
	for i in range(_buttons.size()):
		var w2: float = bw
		if str(_buttons[i]["sub"]) != "":
			w2 = bw  # same width; subs are short
		_btn_rects.append(Rect2((s.x - w2) * 0.5, y, w2, bhs[i]))
		y += bhs[i] + gap


# ============================================================
# DRAW — sky / sun / ocean / title / buttons
# ============================================================
func _draw() -> void:
	if _vp.x <= 0.0:
		_vp = size
	if _vp.x <= 0.0:
		return
	_layout_buttons()
	var s := _vp
	var horizon: float = s.y * 0.55
	_draw_sky(s, horizon)
	_draw_sun(s, horizon)
	_draw_ocean(s, horizon)
	_draw_title(s)
	_draw_buttons(s)
	_draw_footer(s)


func _lerp_color(a: Color, b: Color, k: float) -> Color:
	var kk := clampf(k, 0.0, 1.0)
	return Color(a.r + (b.r - a.r) * kk, a.g + (b.g - a.g) * kk,
		a.b + (b.b - a.b) * kk, a.a + (b.a - a.a) * kk)


func _draw_sky(s: Vector2, horizon: float) -> void:
	# banded vertical gradient: deep night navy -> teal -> warm horizon glow
	var top_c := Color(0.008, 0.03, 0.06)
	var mid_c := Color(0.03, 0.12, 0.16)
	var glow_c := Color(0.32, 0.16, 0.1)
	var bands := 30
	var band_h: float = horizon / float(bands)
	for i in range(bands):
		var k: float = float(i) / float(bands)
		var col: Color
		if k < 0.55:
			col = _lerp_color(top_c, mid_c, k / 0.55)
		else:
			col = _lerp_color(mid_c, glow_c, (k - 0.55) / 0.45)
		draw_rect(Rect2(0.0, float(i) * band_h, s.x, band_h + 1.0), col)


func _draw_sun(s: Vector2, horizon: float) -> void:
	# low warm sun with a soft glow, sitting just on the horizon right-of-center
	var cx: float = s.x * 0.72
	var cy: float = horizon - s.y * 0.03
	var sr: float = minf(s.y * 0.085, 84.0)
	# glow rings
	for g in range(6, 0, -1):
		var gr: float = sr * (1.0 + float(g) * 0.34)
		var ga: float = 0.05 + float(6 - g) * 0.008
		draw_circle(Vector2(cx, cy), gr, Color(1.0, 0.62, 0.28, ga))
	draw_circle(Vector2(cx, cy), sr, Color(1.0, 0.8, 0.42, 0.95))
	draw_circle(Vector2(cx, cy), sr * 0.82, Color(1.0, 0.94, 0.72, 1.0))
	# horizontal haze band around the sun line
	draw_rect(Rect2(0.0, cy - sr * 0.7, s.x, sr * 1.6), Color(1.0, 0.55, 0.3, 0.05))


func _draw_ocean(s: Vector2, horizon: float) -> void:
	var depth: float = s.y - horizon
	var bands := 26
	var band_h: float = depth / float(bands)
	for i in range(bands):
		var k: float = float(i) / float(bands)
		var col := _lerp_color(Color(0.03, 0.14, 0.17), Color(0.005, 0.02, 0.035), k)
		draw_rect(Rect2(0.0, horizon + float(i) * band_h, s.x, band_h + 1.0), col)
	# animated wave crest lines (cheap: a few sine polylines)
	var rows := 10
	for r in range(rows):
		var ky: float = float(r) / float(rows)
		var base_y: float = horizon + 6.0 + ky * depth * 0.92
		var amp: float = 2.5 + ky * depth * 0.09
		var speed: float = 1.6 + ky * 0.9
		var alpha: float = 0.34 * (1.0 - ky * 0.72)
		var pts := PackedVector2Array()
		var segs := 26
		for i in range(segs + 1):
			var x: float = s.x * float(i) / float(segs)
			var ph: float = sin(x * 0.018 + _t * speed + float(r) * 1.7)
			var ph2: float = sin(x * 0.007 - _t * speed * 0.6 + float(r))
			pts.append(Vector2(x, base_y + ph * amp + ph2 * amp * 0.6))
		draw_polyline(pts, Color(0.75, 0.95, 1.0, alpha), 1.4, true)
	# sun glint path (soft vertical shimmer under the sun)
	var gx: float = s.x * 0.72
	for k in range(16):
		var gy: float = horizon + 8.0 + float(k) * (depth * 0.8) / 16.0
		var gw: float = 3.0 + float(k) * 1.5
		var ga: float = 0.14 * (1.0 - float(k) / 18.0)
		draw_rect(Rect2(gx - gw * 0.5, gy, gw, 3.0), Color(1.0, 0.9, 0.6, ga))


func _draw_title(s: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var fs: int = int(clampf(s.y * 0.105, 40.0, 74.0))
	var title := "RAFT SURVIVAL"
	var tw: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_title_w = tw
	var cx: float = s.x * 0.5
	var ty: float = s.y * 0.16 + fs
	# wooden plaque behind the title
	var pad: float = fs * 0.8
	var plaque := Rect2(cx - tw * 0.5 - pad, ty - fs * 1.15, tw + pad * 2.0, fs * 1.9)
	_draw_rounded(plaque, 14.0, Color(0.14, 0.09, 0.05, 0.92))
	_draw_rounded(plaque, 14.0, Color(0.38, 0.26, 0.13, 0.9), false, 2.0)
	# wood grain: a few faint darker streaks
	for i in range(6):
		var gy2: float = plaque.position.y + 6.0 + float(i) * (plaque.size.y - 12.0) / 5.0
		draw_line(Vector2(plaque.position.x + 8.0, gy2), Vector2(plaque.end.x - 8.0, gy2 + 1.5),
			Color(0.0, 0.0, 0.0, 0.18), 2.0)
	# rivets at the plaque corners
	var rr2: float = 3.4
	for pt in [plaque.position + Vector2(10, 10), Vector2(plaque.end.x - 10, plaque.position.y + 10),
			Vector2(plaque.position.x + 10, plaque.end.y - 10), Vector2(plaque.end.x - 10, plaque.end.y - 10)]:
		draw_circle(pt, rr2, Color(0.55, 0.5, 0.32, 0.9))
	# title text with a soft shadow
	_draw_text(title, Vector2(cx - tw * 0.5 + 3.0, ty + fs * 0.32 + 3.0), fs, Color(0.0, 0.0, 0.0, 0.55))
	_draw_text(title, Vector2(cx - tw * 0.5, ty + fs * 0.32), fs, Color(1.0, 0.87, 0.58, 1.0))
	# subtitle
	var sub := "OCEAN SURVIVAL"
	var sfs: int = int(fs * 0.32)
	var sw2: float = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
	_draw_text(sub, Vector2(cx - sw2 * 0.5, ty + fs * 1.35), sfs, Color(0.55, 0.88, 0.95, 0.95))


func _draw_buttons(s: Vector2) -> void:
	for i in range(_btn_rects.size()):
		var r2 := _btn_rects[i] as Rect2
		var b: Dictionary = _buttons[i]
		var label: String = b["label"]
		var sub: String = b["sub"]
		var is_resume: bool = b["id"] != "new"
		var hovered: bool = i == _hover
		var pressed: bool = i == _press
		var off: float = 3.0 if pressed else 0.0
		var rr := Rect2(r2.position.x, r2.position.y + off, r2.size.x, r2.size.y)
		# drop shadow
		_draw_rounded(Rect2(rr.position + Vector2(0, 5), rr.size), rr.size.y * 0.22,
			Color(0.0, 0.0, 0.0, 0.4))
		# plank body + border
		var base := Color(0.24, 0.17, 0.1, 0.97)
		if is_resume:
			base = Color(0.2, 0.23, 0.16, 0.97) if b["id"] == "quick" else base
		if hovered:
			base = base.lightened(0.12)
		if pressed:
			base = base.darkened(0.14)
		_draw_rounded(rr, rr.size.y * 0.2, base)
		var border_c := Color(0.1, 0.06, 0.03, 1.0)
		if hovered:
			border_c = Color(0.95, 0.72, 0.32, 0.95)
		elif is_resume:
			border_c = Color(0.62, 0.5, 0.28, 0.9)
		_draw_rounded(rr, rr.size.y * 0.2, border_c, false, 2.0)
		# top edge catch-light (plank highlight)
		draw_line(Vector2(rr.position.x + 8.0, rr.position.y + 2.0),
			Vector2(rr.end.x - 8.0, rr.position.y + 2.0), Color(1.0, 1.0, 1.0, 0.14), 2.0)
		# side icon
		var icon_c := Vector2(rr.position.x + rr.size.y * 0.5, rr.position.y + rr.size.y * 0.5)
		_draw_button_icon(icon_c, rr.size.y * 0.42, b["id"],
			Color(1.0, 0.9, 0.65, 0.95) if hovered else Color(0.85, 0.72, 0.45, 0.9))
		# label + sub (centered, pushed right of the icon)
		var font := ThemeDB.fallback_font
		var fs: int = int(clampf(rr.size.y * 0.3, 20.0, 30.0))
		var lw2: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lx: float = rr.position.x + (rr.size.x - lw2) * 0.5 + rr.size.y * 0.2
		var ly: float = rr.position.y + rr.size.y * 0.44
		_draw_text(label, Vector2(lx, ly + fs * 0.3), fs, Color(1.0, 0.98, 0.92, 1.0))
		if sub != "":
			var sfs: int = int(clampf(rr.size.y * 0.2, 13.0, 18.0))
			var sw3: float = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
			_draw_text(sub, Vector2(rr.position.x + (rr.size.x - sw3) * 0.5, ly + fs * 0.55 + sfs * 0.85),
				sfs, Color(0.6, 0.85, 0.95, 0.85))


func _draw_button_icon(c: Vector2, r: float, id: String, col: Color) -> void:
	match id:
		"continue":
			# play triangle
			var tri := PackedVector2Array([
				c + Vector2(-r * 0.42, -r * 0.55), c + Vector2(-r * 0.42, r * 0.55),
				c + Vector2(r * 0.6, 0.0),
			])
			draw_colored_polygon(tri, col)
		"quick":
			# clock: circle + hands
			draw_arc(c, r * 0.62, 0.0, TAU, 24, col, maxf(r * 0.12, 1.5), true)
			draw_line(c, c + Vector2(0.0, -r * 0.4), col, maxf(r * 0.12, 1.5))
			draw_line(c, c + Vector2(r * 0.26, r * 0.2), col, maxf(r * 0.12, 1.5))
		_:
			# plus = new game
			draw_arc(c, r * 0.62, 0.0, TAU, 24, col, maxf(r * 0.12, 1.5), true)
			draw_line(c + Vector2(-r * 0.3, 0.0), c + Vector2(r * 0.3, 0.0), col, maxf(r * 0.14, 2.0))
			draw_line(c + Vector2(0.0, -r * 0.3), c + Vector2(0.0, r * 0.3), col, maxf(r * 0.14, 2.0))


func _draw_footer(s: Vector2) -> void:
	var fs := 14
	var foot := "BUILD. SURVIVE. SAIL ON."
	var font := ThemeDB.fallback_font
	var tw: float = font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_text(foot, Vector2((s.x - tw) * 0.5, s.y - fs * 1.4), fs, Color(1, 1, 1, 0.28))


func _draw_text(text: String, top_left: Vector2, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, top_left, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_rounded(rect: Rect2, radius: float, color: Color, filled: bool = true, width: float = 1.0) -> void:
	var sbox := StyleBoxFlat.new()
	sbox.set_corner_radius_all(int(radius))
	if filled:
		sbox.bg_color = color
		sbox.set_border_width_all(0)
	else:
		sbox.bg_color = Color(0, 0, 0, 0)
		sbox.set_border_width_all(int(maxf(width, 1.0)))
		sbox.border_color = color
	draw_style_box(sbox, rect)

```

### `res://wood_planks.gdshader`

```glsl
shader_type spatial;

// Procedural plank-wood for build pieces (roofs, walls, ...).
// Generates plank boards + long wood-grain streaks entirely in-shader from the
// piece's LOCAL axes (per-face, using the object-space normal), so every 2x2 /
// 2x2.5 box tiles cleanly with no texture files. Board seams align to the
// piece edges, matching the roof's physical seam strips.
//
// Per-face layout chosen by face normal:
//   horizontal faces (+Y/-Y): boards run along local X, stack along Z
//   vertical faces facing Z : boards run vertical (Y), stack along X
//   vertical faces facing X : boards run vertical (Y), stack along Z (thin)

uniform vec3 base_color : source_color = vec3(0.62, 0.43, 0.22);
uniform vec3 seam_color : source_color = vec3(0.30, 0.20, 0.11);
uniform float half_x = 1.0;    // local half-extents (meters) of this piece
uniform float half_y = 1.25;
uniform float half_z = 1.0;
uniform float plank_width = 0.25;  // width of one board in meters
uniform float seam_width = 0.006;  // width of the dark board seam in meters
uniform float grain_strength = 0.16;
uniform float tint_variation = 0.07;

varying vec3 v_pos;    // object-space vertex position (meters, centered)
varying vec3 v_normal; // object-space face normal

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_pos = VERTEX;
	v_normal = NORMAL;
}

void fragment() {
	vec3 an = abs(v_normal);
	float along = 0.0;  // meters along the board's length
	float across = 0.0; // meters across the board stack, 0 at the face edge
	if (an.y > an.x && an.y > an.z) {
		// Horizontal surface (roof/deck top, box top/bottom).
		along = v_pos.x;
		across = v_pos.z + half_z;
	} else if (an.z >= an.x) {
		// Wall face with its wide dimension along X.
		along = v_pos.y;
		across = v_pos.x + half_x;
	} else {
		// Thin end face (or wall oriented along Z).
		along = v_pos.y;
		across = v_pos.z + half_z;
	}

	// Board seams: dark line at the start of every plank.
	float wp = across / plank_width;
	float f = fract(wp);
	float line_weight = 1.0 - smoothstep(0.0, seam_width / plank_width, f);
	float board_id = floor(wp);

	// Subtle per-board brightness variation.
	float board_shade = 1.0 + tint_variation * (hash12(vec2(mod(board_id, 64.0), 7.7)) - 0.5) * 2.0;

	// Wood grain: long streaks along the board, tight variation across it.
	float streak = vnoise(vec2(along * 0.8, across * 80.0));
	float streak2 = vnoise(vec2(along * 2.4 + 17.0, across * 40.0));
	float grain = mix(streak, streak2, 0.5);
	// Broad tonal wave so planks don't read as flat stripes.
	grain += 0.35 * vnoise(vec2(along * 0.35, floor(across / plank_width) * 3.1 + 5.0));

	float shade = board_shade * (1.0 + grain_strength * (grain - 0.5) * 2.0);
	vec3 albedo = base_color * shade;
	albedo = mix(seam_color, albedo, 1.0 - line_weight);

	ALBEDO = albedo;
	ROUGHNESS = 0.9;
}

```

---

## 26. Island

A beach-sculpted island (`models/sand_raftsurvival.glb`) centered **85 m east, 165 m south** of the raft start (≈183 m, ~28° right of the raft's forward axis — inside the 75° FOV, so it is visible from the raft in open ocean). `island_setup.gd` rescales the raw ~284 m scan to a 36 m footprint (squashed vertically to 62 % so the dunes read as a beach islet, not a sand cone) and drops it so the scan's water line — measured from the mesh at local y ≈ 11, the widest beach ring; the scan is cut off at y ≈ 4.2, it does *not* continue below sea level — rides the live sea surface, leaving a ~36 m islet that rises ~3 m out of the water with ~0.5 m of skirt hiding the cut rim. The same transform (`scale 0.12693 / 0.078697 / 0.12693`, y −0.8657) and pre-snapped palm heights are baked into `main.tscn` so the editor viewport matches the running game; the runtime normalisation is idempotent with those values. Players can find it by the pulsing light pillar (`island_beacon.gd`) and the on-screen diamond/distance hint (`island_marker.gd`), both of which stay readable at night.

**Files**

| File | Role |
|---|---|
| `models/island_terrain.glb` | 24×24 m terrain — grassy mound (peak ≈ 2.1 m) + flat sand ring beyond r = 10 m; per-vertex `COLOR_0` carries the absolute grass→tan blend |
| `models/palm_tree.glb` | Low-poly palm: 8-sided tapered trunk with lean, 12 drooping fronds, 3 coconuts; origin at trunk base |
| `models/grass_blade.glb` | 8×35 cm blade, 5 height segments; `COLOR_0` = black (base) → white (tip) wind mask |
| `grass_wind.gdshader` | Wind sway. Reads the blade's `COLOR_0` as the bend mask; `INSTANCE_CUSTOM.x/y` = per-blade phase/strength so every blade sways out of sync. Uniforms: `wind_strength` (0.18), `wind_speed` (1.6), `wind_gustiness` (0.5), `wind_direction` |
| `island_terrain.gdshader` | Realistic terrain material applied per-surface by `island_setup.gd`: vertex-paint albedo + per-pixel fbm detail, slope-based rock, and a wet-sand band that tracks the live water line (`water_line` uniform pushed every frame) |
| `island_grass.gd` | `@tool` scatterer: raycasts down at random points inside `scatter_radius`, keeps hits that are flat enough (`min_surface_flatness`), above `min_height_above_water` and below `max_height_above_water` over sea level (the beach scan continues ~22 m *below* the water line, so without the lower bound blades sprout on submerged sand), fills one `MultiMeshInstance3D` (single draw call; `use_custom_data = true` is required by the shader). **Hit transforms are converted world → node-local** before storage: ray hits are world-space, but the MultiMeshInstance sits inside the Island, so raw world transforms would apply the island offset twice (blades landing over open ocean — the "no grass" bug). Retries a few frames if no collider exists yet |
| `island_setup.gd` | Runtime setup: creates trimesh `StaticBody3D` colliders for the island + each palm (same result as the editor's *Mesh → Create Trimesh Static Body*), applies the terrain shader (grass surface keeps white `base_color` so the vertex paint shows; sand surface gets the sand tint; palms/beacon/grass are excluded), snaps palms onto the terrain, then rebuilds the grass one frame later. Skips meshes under a `no_collision` group node (the beacon visuals). For the beach scan (`sand_raftsurvival.glb`) it also normalises the import: every imported root is scaled by `k = ISLAND_TARGET_SIZE / widest_mesh_footprint` and the whole island is dropped so `SCAN_WATER_LINE` (11.0 — the widest beach ring of the scan, whose mesh bottom is y ≈ 4.2) sits on the live water height (`_water_height_at()`); the old value 0.0 left the island floating ~0.5 m above the waves |
| `island_beacon.gd` | Pulsing light pillar + glowing orb + soft `OmniLight3D` on the mound (`IslandBeacon`, y ≈ 3.2) — visible from the raft even at night. Registers in group `island_beacon`; its meshes join `no_collision` so no trimesh collider is generated for them |
| `island_marker.gd` | HUD hint (`IslandMarker` under `Player/CanvasLayer`): warm-orange diamond + `N m` distance readout. Sits above the island while on screen, clamps to the screen edge when it isn't (hollow diamond), fades out within `fade_distance` (18 m) of the beacon |

**Scene wiring (`main.tscn`)** — `Island` (beach-scan instance at 85, 0, -165) carrying the terrain, the beacon, **13 palms** (`kenney_palm_detailed_tall/short.glb`, scales 2.0–2.8, scattered 7–14 m out from the mound centre so they ring the crown) and `IslandGrass` (9000 blades, radius 15.5 m — covers the whole islet; node 6 m above sea level, rays +14/−16, so they cover the ~3 m crown and stop at the water line); the island also runs `island_destination.gd` (`map_label = "Home Isle"`, 12 coconut/banana/stone pickups). `IslandSetup` sits on `Main`.

**Startup order matters:** `IslandGrass._ready()` runs before any collider exists (prints "no ground yet" and bails) → `IslandSetup._ready()` generates collision + snaps palms → one `process_frame` later it calls `IslandGrass.rebuild()` → blades placed.

**Gotchas baked into the pipeline**

- Godot trimesh colliders are **one-sided**. An open grid sculpt needs its normals explicitly flipped up (Blender's "recalculate outside" can't fix a plane's winding); `fix_normals.py` flips only when the average face normal z is negative, so it is safe to re-run.
- Godot's glTF importer sets `vertex_color_use_as_albedo`, so vertex colors are **multiplied** by material albedo. The terrain materials are therefore neutral white (0.97) in Blender — the vertex `COLOR_0` carries the actual look.
- **Blender 5.x glTF export silently drops vertex colors by default**: `export_vertex_color` defaults to `MATERIAL`, which only bakes colors when the material node tree uses a Color Attribute node. Our materials don't, so early exports got a fake all-white `COLOR_0` (rigid bending, washed-out terrain). All exports go through `export_final.py` next to the .blend, which passes `export_vertex_color='ACTIVE'` to bake the active color attribute. Verified in-engine: blade `COLOR_0.r` runs 0.0 (base) → 1.0 (tip).
- Palm snapping excludes the palms' own collision bodies, otherwise a palm lands on top of its own pre-move trunk collider (y ≈ 4.7 instead of ≈ 1.55).

**Tuning** — grass budget: `instance_count` (3000 by default; the field is a single draw call with shadows off — desktop tests showed 2200–6000 blades all run >300 fps at 960×540, so raise it for looks and only lower toward 800–1200 if a phone struggles), `scatter_radius`, `min_surface_flatness` (0.7); wind: uniforms on `GrassField.material_override` at runtime, or the defaults atop `grass_wind.gdshader` (`wind_strength` 0.14, matched to the Sky3D wind direction of 2.356 rad).

---

*End of documentation.*
