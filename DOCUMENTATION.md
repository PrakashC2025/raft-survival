# RaftSurvival — Complete Project Documentation

> **Engine:** Godot 4.7 · **Language:** GDScript · **Physics:** Jolt 3D  
> **Renderer:** Mobile (D3D12 on Windows) · **Resolution:** Stretched canvas (`canvas_items`, expand)
> **Physics ticks:** 120 Hz

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
- **Top-Attachment Roof:** Roofs snap to Wall tops automatically when aiming at a Wall.
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
├── ocean.gd                     # Wave height function (physics-side)
├── raft.gd                      # Floating physics + buoyancy sample points
├── raft.tscn                    # Base raft: 8 edge/corner sockets + BuiltPieces/
├── debris.gd / debris.tscn      # Floating debris (RigidBody3D)
├── debris_spawner.gd            # Continuous upstream debris stream
├── rope_system.gd               # Hook + rope state machine (~484 lines)
├── inventory.gd                 # Autoload singleton (items + crafting)
├── stats.gd                     # Survival stats (health/hunger/thirst) — NOT wired in yet
├── foundation.tscn              # 2x2x0.3m — 4 edge sockets + Socket_Top
├── wall.tscn                    # 2x2.5x0.2m — Socket_Base/Top/Middle + 4 sides
├── roof.tscn                    # 2x0.15x2m — Socket_Base/Top + 4 edge sockets
├── stairs.tscn                  # 5-step staircase — Socket_Base/Top + 4 edges
├── door.tscn / door.gd          # Swinging door + interact Area3D
├── window.tscn                  # 1.5x1.5x0.1m transparent pane
├── raft_extension.tscn          # Placeholder (no sockets/script yet)
├── bonfire.tscn                 # Placeholder (no physics body/script yet)
└── icon.svg
```

---

## 3. Input Map

Defined in `project.godot` (`[input]`). `rope_*` actions are **created at runtime** by `rope_system._ensure_actions()`.

| Action | Key | Purpose |
|---|---|---|
| `move_forward/back/left/right` | W / S / A / D (+ Arrows) | Movement |
| `jump` | Space | Jump / Swim up (hold = continuous swim up) |
| `move_down` | C | Dive on ground / Swim down |
| `interact` | E | Pickup debris / Toggle door / Double-click = pick up piece for editing |
| `build` | B | Toggle build mode / Cancel edit |
| `cycle_build` | Tab | Cycle: Foundation→Wall→Roof→Stairs→Door→Window |
| `rotate_build` | R **and** Y | Rotate build (90°) |
| `rotate_build_x` | X | Rotate on X axis (**edit mode only** — X is shadowed by `remove_build` in edit mode) |
| `place_build` | P | Place building / Confirm edit |
| `remove_build` | X | Remove building (edit mode) + refund |
| `sprint` | Shift | Sprint / Swim fast |
| `rope_throw` | Q (runtime) | Hold to charge, release to throw hook |
| `rope_pull` | F (runtime) | Reel hook / hooked debris |
| `rope_cancel` | Right-click (runtime) | Cancel throw / release debris |

> **Note:** `rotate_build` binds both R and Y. `rotate_build_x` binds X, but in edit mode X is consumed by `remove_build` first (checked earlier in `_process`), so the X-axis rotation is effectively unreachable via keyboard right now.

---

## 4. Autoloads

| Name | Script | Purpose |
|---|---|---|
| `Inventory` | `inventory.gd` | Item tracker + crafting |

```gdscript
Inventory.add("Wood", 5)
Inventory.can_afford("Foundation")  # -> true/false
Inventory.craft("Foundation")       # -> true/false
Inventory.infinite = true           # debug: crafting never consumes
```

> `stats.gd` is **not** registered as an autoload and is not instanced anywhere — it exists as an unwired survival-stats module (see [§21](#21-survival-stats-statsgd)).

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

From `main.tscn` (raft at (0, 0.235, -3), player at (0, 1.2, -3)):

```
Main (Node3D)
├── DirectionalLight3D            (shadow_enabled)
├── WorldEnvironment              (ProceduralSkyMaterial)
├── Ocean (MeshInstance3D) [ocean.gd]
│   └── PlaneMesh 500x500, 200x200 subdiv, ShaderMaterial (main.gdshader)
├── Raft (AnimatableBody3D) [raft.gd]  — instance of raft.tscn
│   ├── CollisionShape3D (Box 2x0.3x2)
│   ├── MeshInstance3D (BoxMesh, brown)
│   ├── F1-F4 (Marker3D corners at ±0.9/±0.9)
│   ├── BuildSockets/ (8 sockets: 4 cardinal + 4 corner)
│   └── BuiltPieces/ (runtime container for all placed structures)
├── Player (CharacterBody3D) [player.gd]
│   ├── CollisionShape3D (CapsuleShape3D)
│   ├── MeshInstance3D (CapsuleMesh, visible=false at runtime)
│   ├── CamPivot → SpringArm3D (length 0) → Camera3D (offset y=0.6, current)
│   ├── RopeSystem (Node3D) [rope_system.gd]
│   └── CanvasLayer
│       ├── Crosshair (Control) [crosshair.gd]
│       └── InventoryHUD (Label, created at runtime by player._create_hud)
└── DebrisSpawner (Node3D) [debris_spawner.gd]
    └── (runtime instances of debris.tscn)
```

Runtime-created nodes: `BuildPreviewRoot` (ghost preview parent), `BuildDebugMarkers` (debug spheres, only when `debug_building`).

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
```

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
WALL_SURFACE_SNAP_RANGE = 3.0    # wall ghost snaps to a surface within this 2D distance

FOUNDATION_WIDTH = 2.0, FOUNDATION_DEPTH = 2.0, FOUNDATION_THICKNESS = 0.30
FOUNDATION_HALF_WIDTH = 1.0, FOUNDATION_HALF_DEPTH = 1.0, FOUNDATION_HALF_HEIGHT = 0.15
```

### State Variables

```gdscript
var build_mode: bool = false
var ghost: Node3D = null
var build_rotation: float = 0.0      # 90° steps around Y
var build_rotation_x: float = 0.0    # X-axis rotation (edit mode)
var build_valid: bool = false
var _ghost_valid_mat / _ghost_invalid_mat  # green/red, alpha 0.85, unshaded, no_depth_test
```

### Grid & Occupancy

```gdscript
var _grid_occupancy: Dictionary = {}  # raft-relative Vector2i -> Node3D (Foundations + Raft only)
var _raft_node: Node3D = null
```

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

Camera chain: `CamPivot -> SpringArm3D(length=0) -> Camera3D(offset 0, 0.6, 0)`.

`crosshair.gd` draws a hollow circle centered on screen (with configurable `aim_vertical_offset`). It never intercepts mouse input (`MOUSE_FILTER_IGNORE`).

| Crosshair State | Color | When |
|---|---|---|
| NONE | White | Default |
| ITEM | Green | Aiming at debris (<=5m) or a toggleable object (door) |
| BUILD | Blue | Build mode / edit mode |

---

## 8. Ocean System

Two independent wave implementations must agree:

1. **Visual** — `main.gdshader` displaces the PlaneMesh vertices (uniforms `wave_height = 0.6`, `wave_speed = 1.2`; water color, roughness 0.05, metallic 0.3).
2. **Physics** — `ocean.gd` `get_height(world_pos)` returns the exact water Y at any point (used by raft, debris, player swimming, rope):

```gdscript
func get_height(world_pos: Vector3) -> float:
    var h := sin(world_pos.x * 0.4 + _time * wave_speed) \
        + sin(world_pos.z * 0.3 + _time * wave_speed * 0.8) \
        + 0.5 * sin((world_pos.x + world_pos.z) * 0.7 + _time * 1.7)
    return global_position.y + h * wave_height * 0.33
```

`wave_height = 0.4`, `wave_speed = 1.2` (exports). Max wave amplitude ~0.33m. The node registers in the `"ocean"` group so any runtime-instanced node (debris, etc.) can find it across scene boundaries.

---

## 9. Raft System

- `AnimatableBody3D` floating on the ocean, in the `"build_surface"` group, registered at grid cell `(0, 0)`.
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

**File:** `rope_system.gd` (~484 lines) · Node under Player. Fully blocks during build/edit mode (`_force_cancel`).

### State Machine

```
IDLE -> THROWING -> EXTENDED -> REELING -> RETURNING -> IDLE
                  \-> HOOKED -> REELING -/
Cancel from any active state -> RETURNING
```

### Parameters

| Parameter | Value |
|---|---|
| max_hook_distance | 22m |
| throw_speed | 22 m/s |
| reel_speed | 12 m/s |
| return_speed | 20 m/s |
| charge_speed | 30 m/s |
| debris_hook_radius | 1.5m |
| collection_radius | 1.5m |

### Flow

1. **Charge:** hold Q — a charge bar fills from 5m to `max_hook_distance`. Release Q to throw.
2. **Throw:** aim point from a dedicated RayCast3D (mask 3, 22m, player excluded). Direction is **locked once** at throw and never recalculated. `_throw_dist = min(charge_distance, max_hook_distance)`.
3. **Flight:** hook steps along the locked direction at 22 m/s, checking debris within 1.5m each frame. On arrival, snaps to water (`water_y + 0.2` if above). Hitting debris → HOOKED; otherwise → EXTENDED.
4. **HOOKED:** debris is frozen (`freeze_mode = STATIC`, `is_hooked = true`). Q or F starts reeling; right-click releases.
5. **REEL:** hook moves toward the hand at 12 m/s; hooked debris is dragged along (+0.3m Y) with zeroed velocity. Within 1.5m → collected (`Inventory.add(item_name)`, debris freed) and hook returns.
6. **RETURN:** hook flies back at 20 m/s; under 0.5m → IDLE.

Visuals: gold sphere hook, tan `CylinderMesh` rope (radius 0.025) oriented `Basis(right, rope_dir, perp)` from hand to hook, and a screen-space charge bar. Hook origin rides at `player.pos + right*0.4 + forward*0.3 + up*0.8`.

---

## 12. Inventory System

`inventory.gd` — autoload `Inventory`. Items: `Wood, Rope, Plastic, Barrel, Stone, Metal`.

```gdscript
func add(item, amount) / has(item, amount) / remove(item, amount)
func can_afford(recipe) -> bool   # infinite => always true
func craft(recipe) -> bool        # re-checks affordability; never lets counts go negative
```

See [§4](#4-autoloads) for the recipe table.

---

## 13. Door System

`door.gd` on `AnimatableBody3D`:

```gdscript
func toggle() -> void:  # called via "toggle" in collider check on E
    is_open = !is_open
    _target_rotation = deg_to_rad(open_angle) if is_open else 0.0
# _physics_process: rotation.y = lerp_angle(rotation.y, _target_rotation, delta * swing_speed)
```

- `open_angle = 90°`, `swing_speed = 4.0`.
- Node config: `collision_layer = 1`, `collision_mask = 5` (bits 1+3). Extra `IntractZone` Area3D (1.8×2.5×1.8) for interaction detection.
- Meshes: frame (left/right/top), panel, handle, 2 hinges.

---

## 14. Building Scenes

All build-piece roots are now **`AnimatableBody3D`** except Foundation (`StaticBody3D`). Every socket is a `BuildSocket` (Marker3D). `SocketType` enum: `FOUNDATION_EDGE(0), FOUNDATION_TOP(1), WALL_BASE(2), WALL_TOP(3), WALL_SIDE(4), DOOR_SLOT(5), WINDOW_SLOT(6), PILLAR_TOP(7)`. Sockets use `accepts` (explicit allow-list) for compatibility, not the enum.

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

### Wall (`wall.tscn`) — AnimatableBody3D, 2x2.5x0.2

```
CollisionShape3D (Box 2x2.5x0.2) + MeshInstance3D
BuildSockets/
  Socket_Base    (0, -1.25, 0)  WALL_BASE  accepts [Foundation, Wall, Door, Window]
  Socket_Top     (0,  1.25, 0)  WALL_TOP   accepts [Wall, Foundation, Roof]
  Socket_Middle  (0,  0,    0)  WALL_SIDE  accepts [Door, Window]
  Socket_North/South/East/West  WALL_SIDE  accepts [Wall]
SampleMarker
```

### Roof (`roof.tscn`) — AnimatableBody3D, 2x0.15x2

```
CollisionShape3D (Box 2x0.15x2) + MeshInstance3D
BuildSockets/
  Socket_Base    (0, -0.075, 0)  WALL_TOP (type 3)  accepts [Wall]
  Socket_Top     (0,  0.075, 0)  WALL_TOP          accepts [Roof]
  Socket_North/South/East/West   FOUNDATION_EDGE   accepts [Foundation]
SampleMarker
```

### Stairs (`stairs.tscn`) — AnimatableBody3D, 5 steps

```
CollisionShape3D (Box 2x0.2x2) + Step01..Step05 (Box 2x0.2x0.4 rising: (0,0.2i,0.4i))
BuildSockets/
  Socket_Base (0, -0.1, 0.6)  FOUNDATION_EDGE  accepts [Foundation]
  Socket_Top  (0,  0.9, 1.6)  FOUNDATION_EDGE  accepts [Foundation]
  Socket_North/South/East/West                 accepts [Foundation]
SampleMarker
```

### Door (`door.tscn`) — AnimatableBody3D, collision 1.0x2.0x0.12

```
CollisionShape3D + FrameLeft/Right/Top + Panel + Handle + Hinge1/Hinge2
IntractZone (Area3D, Box 1.8x2.5x1.8)
BuildSockets/
  Socket_Base (0, -1, 0)  DOOR_SLOT  accepts [Wall, Foundation]
  Socket_Top  (0,  1, 0)  DOOR_SLOT  accepts [Wall, Foundation]
```

### Window (`window.tscn`) — AnimatableBody3D, PlaneMesh 1.5x1.5 (transparent blue)

```
CollisionShape3D (Box 1.5x1.5x0.1) + MeshInstance3D
BuildSockets/
  Socket_Center  WINDOW_SLOT  accepts [Wall, Foundation]
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
- Door node: `collision_layer = 1`, `collision_mask = 5` (bits 1+3; bit 3 currently unused).

---

## 16. Game Loop & Frame Flow

### Physics Tick (120 Hz)

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
```

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
    Wall:       actual ray hit -> edge/wall-to-wall/socket -> footprint 3x3
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
| BUILDING | R / Y | Rotate 90° |

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

### Wall — Edge Attachment

The wall ghost follows the crosshair **everywhere**. When the aim ray misses or hits a non-build object, the crosshair is projected onto the structural deck plane (`deck_y + 1.25`) so the ghost never jumps to the raft.

```
Aim: ray hit (build surface) OR deck-plane projection of the crosshair.
Support selection: P1 ray-hit (Foundation/Raft/Wall/Door/Window)
                   P2 nearest surface to the projected aim, only if within
                      WALL_SURFACE_SNAP_RANGE (3m)
                   P3 none -> RED ghost AT the crosshair (deck height, invalid)
If support is Wall/Door/Window  -> WALL-TO-WALL socket placement:
    _find_best_socket (score = alignment*10 - dist, radius 2.5m)
    -> reciprocal -> _solve_socket_transform -> overlap (skips foundation below)
If support is Foundation/Raft  -> EDGE placement:
    _select_wall_edge: perpendicular distance to the 4 edge lines;
                       corner tie-break (within 0.25m) uses camera direction dot edge normal
    _compute_wall_transform:
        edge_angle = 90° for East/West sockets (wall runs along the edge)
        wall SLIDES along the edge to follow the crosshair:
            along = local_aim.dot(edge_axis) - socket_local.dot(edge_axis)
            clamped to ±(FOUNDATION_HALF_WIDTH - 0.1) so corners work
        wall Socket_Base offset (0, -1.25, 0) rotated by total angle
Footprint validation: center-point ray (mask 1, 1m above / 3m below, tolerance 0.3m)
    + 3x3 grid samples inset 40% from edges; valid if center supported
    OR support ratio >= minimum_support_ratio (0.50)
Overlap: scan BuiltPieces for Wall/Door/Window within 0.5m horizontally
```

Rotation: R toggles build_rotation in 90° steps (180° flip for a wall = two presses). No 90° rotation around X in build mode.

### Roof — Top Attachment

```
Method 1: Ray hits Wall -> free Socket_Top
Method 2: Walk up 5 ancestors -> Wall with free Socket_Top
Method 3: Search ALL BuiltPieces walls for nearest free Socket_Top (<=4m horizontal)
  -> Find reciprocal: Roof.Socket_Base
  -> Solve: RoofRoot = TargetSocket * inverse(RoofSocketLocal)  [_solve_socket_transform]
  -> Verify ghost socket error <= 0.1m
  -> Overlap: shape query with build_surface-group bodies filtered out
Hysteresis: _roof_last_support remembers the last Wall used (reset on piece cycle)
```

### Door / Window / Stairs — Socket-Based

```
_find_best_socket(support, piece, aim, normal):
    skip occupied / incompatible / >2.5m sockets
    score = socket_dir.dot(aim_dir) * 10 - distance
_find_reciprocal_socket(new_piece, support_name):
    type-compat bonus +10 (FOUNDATION_EDGE<->EDGE, FOUNDATION_TOP<->WALL_BASE,
    WALL_TOP<->WALL_BASE, WALL_SIDE<->WALL_SIDE, FOUNDATION_TOP<->DOOR/WINDOW_SLOT, WALL_TOP<->WALL_TOP)
    +50 if opposite-facing (full 3D direction, so vertical sockets work)
    -100 if same-direction
Solve: _solve_socket_transform (flat, Y-rotation only)
Verify: socket error <= 0.05m, edge gap |gap| < 0.05m (negative = penetration)
Overlap: filtered by build_surface group + anything below solved.origin.y - 1.0
```

### Placement (confirm — `_try_build`)

```
Requires build_valid; walls skip the socket requirement.
Inventory.can_afford + Inventory.craft.
Instantiate scene -> parent under raft's BuiltPieces (ALWAYS the raft root,
  never the socket's parent piece — keeps local transforms raft-relative).
Collision disabled before add, re-enabled deferred (prevents pushing the player).
Foundation: transform from exact cell formula (uses _ghost_cell, never recomputed).
Others: use the ghost preview transform directly.
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

**Remove (X):** unregister, free referencing sockets, refund via `RECIPE_REFUND` (same costs as recipes, minus Roof which is not refundable — Roof is absent from `RECIPE_REFUND`), free the piece.

**Cancel (B):** restore original transform + cell + sockets, restore color.

---

## 20. Rope Algorithm Deep Dive

- **Charge:** hold Q — `charge_distance` grows 5→22m at 30 m/s; a ColorRect bar shows the fraction.
- **Throw:** direction is captured **once** from the aim ray and never recalculated. Hook travels in that fixed world-space direction; camera rotation does not bend the rope.
- **Hook:** checks every frame for debris within 1.5m during flight; frozen debris is dragged during reeling and collected at 1.5m from the hand.
- **Reel:** `hook_pos += normalize(hand - hook_pos) * reel_speed * delta`.
- **Visual:** CylinderMesh from hand to hook, `Basis(right, rope_dir, perp)` — Y axis along the rope.

---

## 21. Survival Stats (stats.gd)

`extends Node` — **not registered as an autoload and not instanced in any scene** (dead code until wired up). Intended API:

```gdscript
signal stat_changed(stat_name: String, value: float)
signal player_died

MAX_VALUE = 100.0
hunger_drain_rate = 0.4 / s, thirst_drain_rate = 0.6 / s   # exports
health = hunger = thirst = 100.0

_process: drain hunger/thirst, emit stat_changed; if either <= 0 -> change_health(-2.0 * delta)
change_health(amount): clamps 0..100, emits player_died at 0
eat(food_value) / drink(thirst_value, health_bonus = 0.0)
```

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
1. Create `.tscn` with an AnimatableBody3D root (Foundation may stay StaticBody3D), CollisionShape3D, MeshInstance3D, BuildSockets, and a `SampleMarker`.
2. Add BuildSocket nodes with correct `socket_type` and explicit `accepts` lists.
3. Add to `BUILD_RECIPE_NAMES` and `BUILD_SCENES` in player.gd.
4. Add a recipe to `inventory.gd` RECIPES (and to `RECIPE_REFUND` if removable).
5. Add placement logic in `_resolve_placement()` if the piece is non-standard.

### New Resource Type
1. Add to `inventory.gd` items dict.
2. Add to `ITEM_PROFILES` in debris.gd (mass, freeboard, color).
3. Add to `ITEM_POOL` in debris_spawner.gd (weight = number of entries).

### Wire up Survival Stats
1. Register `stats.gd` as an autoload (or instance it in main.tscn).
2. Call `eat()` / `drink()` from item pickups and `change_health()` from hazards.
3. Connect `stat_changed` / `player_died` to HUD and respawn logic.

### Migrate placement to BuildSystem
Replace `player._solve_socket_transform` calls with `BuildSystem.solve_socket_attachment(target_socket, socket_local, build_rotation, support_flat_basis)` — the math is identical, and the shared helper is already extracted.

---

*End of documentation.*