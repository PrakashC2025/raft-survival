# RaftSurvival — Complete Project Documentation

> **Engine:** Godot 4.7 · **Language:** GDScript · **Physics:** Jolt 3D  
> **Renderer:** Mobile (D3D12 on Windows) · **Resolution:** Stretched canvas

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Folder & File Map](#2-folder--file-map)
3. [Input Map](#3-input-map)
4. [Autoloads](#4-autoloads)
5. [Main Scene Tree (`main.tscn`)](#5-main-scene-tree-maintscn)
6. [Player System (`player.gd`)](#6-player-system)
7. [Camera & Crosshair](#7-camera--crosshair)
8. [Ocean System (`ocean.gd`)](#8-ocean-system)
9. [Raft System (`raft.gd` + `raft.tscn`)](#9-raft-system)
10. [Debris System (`debris.gd` + `debris_spawner.gd`)](#10-debris-system)
11. [Rope / Hook System (`rope_system.gd`)](#11-rope--hook-system)
12. [Building System](#12-building-system)
13. [Inventory System (`inventory.gd`)](#13-inventory-system)
14. [Door System (`door.gd` + `door.tscn`)](#14-door-system)
15. [Building Scenes](#15-building-scenes)
16. [Physics & Collision Layers](#16-physics--collision-layers)
17. [Complete Code — All Scripts](#17-complete-code--all-scripts)
18. [Complete Code — All Scenes](#18-complete-code--all-scenes)
19. [Game Loop & Frame Flow](#19-game-loop--frame-flow)
20. [State Machines](#20-state-machines)
21. [Build Algorithm Deep Dive](#21-build-algorithm-deep-dive)
22. [Rope Algorithm Deep Dive](#22-rope-algorithm-deep-dive)
23. [How to Extend](#23-how-to-extend)

---

## 1. Project Overview

**RaftSurvival** is a first-person ocean survival game built in Godot 4. The player starts on a small 2×2 wooden raft in the middle of a vast ocean. Floating debris drifts by on the current. The player uses a throwable hook (Q) to catch distant debris or picks it up directly (E) at close range. Collected resources are spent to build foundations, walls, doors, windows, and stairs to expand the raft into a larger structure.

### Recent Bug Fixes (Sep 2026)

**Root cause:** Every `.tscn` build-piece scene file had been saved in an incomplete/truncated form — the root `[node ...]` block was never closed with its trailing `]` bracket. This produced `Parse Error: Unexpected end of file` and `Index p_idx = N is out of bounds` errors. Because the startup scenes (`raft.tscn`, `foundation.tscn`, `wall.tscn`, `door.tscn`, etc.) failed to load:

- The **raft never appeared on the ocean** in `main.tscn` (`res://main.tscn:53` → `[ext_resource] referenced non-existent resource at: res://raft.tscn`).
- **Build mode (B) never activated** — `player.gd` preloads every `BUILD_SCENES` path into `build_pieces`; since `load()` returned `null`, `build_pieces` stayed empty and `_toggle_build()` early-returned.
- Debris spawning, doors, and material pickup were likewise broken.

**Fix:** All **10 scene files** were rewritten as clean UTF-8 text with the root node properly closed AND with explicit `socket_type` / `accepts` on every `BuildSocket` so the placement logic behaves correctly:

| File | Sockets set |
|---|---|
| `raft.tscn` | 4× `FOUNDATION_EDGE` (N/S/E/W) + 4× corner `FOUNDATION_EDGE` |
| `foundation.tscn` | 4× `FOUNDATION_EDGE` + 1× `FOUNDATION_TOP` |
| `wall.tscn` | 1× `WALL_BASE`, 1× `WALL_TOP`, 4× `WALL_SIDE` |
| `door.tscn` | 2× `DOOR_SLOT` |
| `window.tscn` | 1× `WINDOW_SLOT` |
| `stairs.tscn` | 6× `FOUNDATION_EDGE` |
| `roof.tscn` | `WALL_TOP`, `WALL_TOP`, 4× `FOUNDATION_EDGE` |
| `bonfire.tscn` | (no build sockets) |
| `debris.tscn` | (no build sockets) |
| `raft_extension.tscn` | (no build sockets) |

Verified: all scenes load cleanly via Godot headless import (no parse errors), so the raft now appears on the ocean and **Build Mode (B)** enters correctly, letting the player place foundation/wall/roof/stairs/door/window pieces.

### Build / Edit / Door / Window Fixes (Sep 2026)

Six gameplay bugs in the build pipeline were fixed in `player.gd` + the piece scenes. The current code uses the shared socket placement path (`_resolve_placement` / `_compute_piece_transform`), not the older `_calc_*` functions described in earlier sections of this doc.

1. **Ghost preview (BUG 1).** `_spawn_ghost()` previously parented the ghost under the moving `build_surface` raft and never reset its scale, so the preview inherited the raft's motion and possibly a baked scale. The ghost is now parented to a static `BuildPreviewRoot` under the scene root, reset `ghost.scale = Vector3.ONE`, seeded at `aim_point`, and always positioned via `ghost.global_transform` (absolute world pose) each frame.
2. **False INVALID previews (BUG 2).** `_check_overlap`, `_check_overlap_edit`, and `_confirm_edit` now exclude **all** `build_surface` members (plus player/ghost/edited piece) via a shared `_overlap_excludes()`, so a piece can snap to / overlap the raft and existing buildings without reporting a false collision. This also fixed a real GDScript runtime error: `_overlap_excludes` passed an untyped `Array` into a typed `Array[RID]` return, throwing "Trying to assign an array of type `Array` to a variable of type `Array[RID]`" every preview frame (which failed the overlap check closed → false INVALID). The parameter is now typed `Array[RID]` and both callers cast their literal with `as Array[RID]`.
3. **Edit-mode offset (BUG 3).** `_update_edit_follow()` no longer hardcodes a raft `z=-3` grid; it reuses the live `_resolve_placement(piece_name, aim_point)` shared with build mode, so moves track the raft's current transform.
4. **Door (BUG 4).** `door.tscn` root gets explicit `collision_layer = 1` so the single aim raycast (mask = 3) hits it; interaction stays on the one source of truth (`"toggle" in aim_collider`) — the separate `IntractZone` Area3D is unused.
5. **Window glass (BUG 5).** `window.tscn` material is `transparency=1`, `albedo_color = Color(0.3,0.7,1.0,0.35)`, `metallic=0.6`, `roughness=0.05`, `cull_mode=2` (double-sided). `_apply_building_color()` no longer recolours windows opaque.
6. **Ceiling / foundation-on-wall (BUG 6).** Walled socket `Socket_Top` (WALL_TOP) accepts `Foundation` and resolves to `socket_gpos + half.y` (flush on top of the wall); walls join `build_surface`, and the BUG-2 overlap exclude lets the ceiling foundation overlap the wall below and validate green.

### Core Gameplay Loop

```
See debris floating by
		↓
Aim crosshair at debris
		↓
┌─────────────────────────────────┐
│  CLOSE (≤5m): Press E          │ → Direct pickup into inventory
│  FAR  (>5m): Hold Q → Release  │ → Hook thrown toward debris
│       ↓                         │
│  Hook catches debris            │
│       ↓                         │
│  Press Q/F to reel in           │
│       ↓                         │
│  Debris reaches collection dist │
│       ↓                         │
│  Inventory.add(item_name)       │
└─────────────────────────────────┘
		↓
Spend resources in Build Mode (B)
		↓
Expand raft → Build walls → Build upper floors
```

### Key Design Principles

- **Single Aim Source:** One raycast from the camera center powers all interactions (pickup, hook throw, building placement).
- **World-Space Hook:** After throwing, the hook is locked in world space. Camera rotation never moves it.
- **Socket-Based Building:** Every build piece has `BuildSockets` (Marker3D nodes). The build system snaps to these sockets for perfect edge-to-edge alignment.
- **Ocean-Driven Debris:** Debris spawns upstream and drifts past the player on a simulated current with buoyancy, wave bobbing, and gentle tumbling.

---

## 2. Folder & File Map

```
project_root/
├── project.godot              # Engine config, input map, autoloads, physics
├── main.tscn                  # Main scene: world root with all children
│
├── player.gd                  # Player: movement, swimming, aim, building, HUD
├── camera_pivot.tscn          # (inline in main.tscn — CamPivot node)
├── crosshair.gd               # Screen-center UI reticle
│
├── ocean.gd                   # Ocean mesh + wave height function
├── raft.gd                    # Raft: floats on ocean, build surface root
├── raft.tscn                  # Raft scene: mesh + collision + sockets
│
├── debris.gd                  # Debris: buoyancy, current, fade in/out
├── debris.tscn                # Debris scene: RigidBody3D + mesh
├── debris_spawner.gd          # Spawner: upstream spawning, cleanup, groups
│
├── rope_system.gd             # Hook + rope: state machine, throw, reel, cancel
│
├── inventory.gd               # Autoload singleton: items, recipes, crafting
│
├── foundation.tscn            # 2×2×0.3m platform with 8 edge sockets
├── wall.tscn                  # 2×2.5×0.2m vertical panel with 4 sockets
├── window.tscn                # 1.5×1.5m transparent plane with 1 socket
├── stairs.tscn                # 5-step staircase (30° incline)
├── door.tscn                  # Realistic door: frame + panel + handle + hinges
├── door.gd                    # Door script: toggle open/close with lerp
│
└── icon.svg                   # Project icon
```

---

## 3. Input Map

All input actions defined in `project.godot`:

| Action | Key | Purpose |
|---|---|---|
| `move_forward` | ↑ / W | Walk / swim forward |
| `move_back` | ↓ / S | Walk / swim backward |
| `move_left` | ← / A | Walk / swim left |
| `move_right` | → / D | Walk / swim right |
| `move_down` | C | Dive / swim down |
| `jump` | Space | Jump (land) / Swim up (water) |
| `interact` | E | Pickup debris / Place building / Confirm edit / Toggle door |
| `build` | B | Toggle build mode / Cancel edit |
| `cycle_build` | Tab | Cycle building type (Foundation→Wall→Stairs→Door→Window) |
| `rotate_build` | R | Rotate building preview 90° |
| `remove_build` | X | Remove building (edit mode) + refund resources |
| `sprint` | Shift | Sprint (land) / Swim fast (water) |
| `rope_throw` | Q | Hold to charge, release to throw hook. Q/F to reel when extended. **Created dynamically** by `rope_system.gd` if not in project.godot |
| `rope_pull` | F | Reel hook back. **Created dynamically** |
| `rope_cancel` | Right-click | Cancel throw / release debris. **Created dynamically** |

**Note:** `rope_throw`, `rope_pull`, and `rope_cancel` are NOT in `project.godot`. They are created at runtime by `rope_system.gd::_ensure_actions()` to avoid conflicts.

---

## 4. Autoloads

| Name | Script | Purpose |
|---|---|---|
| `Inventory` | `inventory.gd` | Global item tracker + crafting cost checker. Accessible as `Inventory.add("Wood")`, `Inventory.can_afford("Foundation")`, etc. |

### Inventory API

```gdscript
# Add items
Inventory.add("Wood", 5)
Inventory.add("Rope")          # defaults to amount=1

# Check if player can afford a recipe
Inventory.can_afford("Foundation")  # → true/false

# Craft (deducts resources)
Inventory.craft("Foundation")   # → true if successful

# Debug: unlimited resources
Inventory.infinite = true       # can_afford() always returns true
```

### Recipes

| Recipe | Cost |
|---|---|
| Foundation | 5 Wood |
| Wall | 8 Wood + 1 Rope |
| Stairs | 6 Wood + 1 Rope |
| Door | 4 Wood + 1 Rope |
| Window | 3 Wood + 1 Plastic |
| Bonfire | 8 Wood + 2 Rope |
| Raft Extension | 10 Wood + 2 Plastic |

---

## 5. Main Scene Tree (`main.tscn`)

```
Main (Node3D)
├── DirectionalLight3D              # Sun light
├── WorldEnvironment                # Sky, ambient light, fog
│
├── Ocean (MeshInstance3D)          # Water plane, script: ocean.gd
│   └── [uid://... Ocean class_name]
│
├── Raft (AnimatableBody3D)         # Player's home base, script: raft.gd
│   ├── CollisionShape3D            # BoxShape3D (2×0.3×2)
│   ├── MeshInstance3D              # BoxMesh brown planks
│   ├── F1 / F2 / F3 / F4         # Marker3D — corner markers for wave sampling
│   └── BuildSockets/              # Socket_North, Socket_South, etc.
│
├── Player (CharacterBody3D)        # First-person controller, script: player.gd
│   ├── CollisionShape3D            # CapsuleShape3D (player body)
│   ├── MeshInstance3D              # Capsule mesh (HIDDEN — first-person)
│   ├── CamPivot (Node3D)           # Pitch rotation node
│   │   └── SpringArm3D            # Length=0.0 (camera at player position)
│   │       └── Camera3D           # First-person camera, offset=(0, 0.6, 0)
│   ├── RopeSystem (Node3D)         # Hook+rope, script: rope_system.gd
│   │   ├── HookOrigin (Node3D)    # Follows player hand position
│   │   ├── Hook (MeshInstance3D)  # SphereMesh — invisible when IDLE
│   │   ├── RopeMesh (MeshInstance3D) # CylinderMesh — straight line hand→hook
│   │   └── AimRay (RayCast3D)     # Camera-center raycast for hook aim
│   └── CanvasLayer
│       ├── Crosshair (Control)     # Screen-center reticle, script: crosshair.gd
│       └── InventoryHUD (Label)    # Resource counters + build mode info
│
├── DebrisSpawner (Node3D)          # Continuous upstream spawning, script: debris_spawner.gd
│   └── [Debris instances]          # Runtime-created Debris nodes
│
└── [Build surfaces]                # Raft + placed foundations all in "build_surface" group
```

### Important Node Relationships

```
Player.global_position = character body in world
Camera3D is a CHILD of CamPivot which is a CHILD of Player
  → Camera moves with player but can pitch independently
  → Camera offset (0, 0.6, 0) = eye level above feet

RopeSystem is a CHILD of Player
  → HookOrigin follows player's hand (right +0.4, forward +0.3, up +0.8)
  → Hook is a WORLD-SPACE entity (position set manually, not parented to camera)

Raft is an AnimatableBody3D (NOT CharacterBody3D)
  → Floats on ocean, but doesn't collide with player like a static wall
  → Player stands on it via CharacterBody3D floor detection
```

---

## 6. Player System

**File:** `player.gd` (980 lines)  
**Node:** `CharacterBody3D` named "Player"  
**Group:** "player"

### Constants

```gdscript
WALK_SPEED = 3.0          # m/s normal walking
SPRINT_SPEED = 5.0        # m/s sprinting
SWIM_SPEED = 2.0          # m/s swimming
SWIM_SPRINT_SPEED = 3.5   # m/s swim sprint
JUMP_VELOCITY = 10.0      # jump force on land
WATER_JUMP_VELOCITY = 12.0 # burst jump out of water
DIVE_VELOCITY = -6.0       # dive downward force
GRAVITY = 9.8              # m/s²
MOUSE_SENSITIVITY = 0.003  # radians per pixel

# Swimming
SWIM_UP_CONTINUOUS = 5.0   # upward speed when holding space underwater
SWIM_DOWN_SPEED = 3.0      # downward speed when holding C
SWIM_ACCELERATION = 12.0   # how fast vertical speed changes
SWIM_DECELERATION = 6.0    # how fast vertical speed drops to zero
FLOAT_FORCE = 8.0          # buoyancy near surface
FLOAT_DAMPING = 0.95       # velocity multiplier per frame
WATER_ENTER_OFFSET = 0.3   # how far below surface triggers swimming
WATER_EXIT_OFFSET = 1.5    # how far above surface exits swimming
MAX_SWIM_DEPTH = 30.0      # depth limit

# Aim
AIM_DISTANCE = 60.0        # raycast max length
PICKUP_RANGE = 5.0         # E key direct pickup max distance
NEARBY_PICKUP_RANGE = 2.0  # fallback: collect if debris is very close
```

### Node References

```gdscript
@onready var cam_pivot: Node3D = $CamPivot
@onready var camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var crosshair: Control = $CanvasLayer/Crosshair
@onready var rope_system: RopeSystem = $RopeSystem
```

### Build Variables

```gdscript
BUILD_RECIPE_NAMES = ["Foundation", "Wall", "Stairs", "Door", "Window"]
BUILD_SCENES = ["res://foundation.tscn", "res://wall.tscn", ...]
SOCKET_SNAP_RADIUS = 2.5  # max distance to find a socket
SOCKET_MATCH_TOLERANCE = 0.3

var selected_piece_index: int = 0
var build_mode: bool = false
var ghost: Node3D = null              # current preview piece
var build_rotation: float = 0.0       # radians, increments by PI/2
var build_valid: bool = false         # true = green preview = can place
var _ghost_valid_mat: StandardMaterial3D    # green transparent
var _ghost_invalid_mat: StandardMaterial3D  # red transparent
```

### Edit Variables

```gdscript
var _editing: Node3D = null           # the building being edited
var _edit_original_pos: Vector3       # where it was before pickup
var _edit_original_rot: Vector3       # rotation before pickup
var _last_click_time: float = 0.0     # for double-click detection
```

### Aim Variables (Single Source of Truth)

```gdscript
var aim_point: Vector3       # world position where ray hit
var aim_normal: Vector3      # surface normal at hit point
var aim_collider: Node3D     # what was hit
var aim_distance: float      # distance from camera to hit
var aim_valid: bool          # did the ray hit anything?
```

### `_ready()` — Initialization

```gdscript
func _ready() -> void:
    add_to_group("player")
    rope_system.player = self
    rope_system.camera = camera
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    camera.current = true
    
    # Hide player mesh (first-person)
    var mesh := get_node_or_null("MeshInstance3D")
    if mesh != null:
        mesh.visible = false
    
    # Load build scenes
    if build_pieces.is_empty():
        for scene_path in BUILD_SCENES:
            var scene = load(scene_path) as PackedScene
            if scene:
                build_pieces.append(scene)
    
    # Testing: unlimited resources
    Inventory.infinite = true
    Inventory.add("Wood", 999)
    Inventory.add("Rope", 999)
    Inventory.add("Plastic", 999)
    
    _create_hud()
```

### `_unhandled_input()` — Mouse Look

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        # Horizontal: rotate entire player body
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        # Vertical: rotate camera pivot (clamped)
        cam_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
        cam_pivot.rotation.x = clamp(cam_pivot.rotation.x, -1.4, 1.4)
    
    if event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
```

**Why this works:**  
- `rotate_y()` rotates the CharacterBody3D around its vertical axis — the player's facing direction changes.  
- `cam_pivot.rotate_x()` pitches the camera up/down without rotating the body.  
- Clamping at ±1.4 radians (≈80°) prevents looking past straight up/down.  
- Mouse is captured at start so it disappears and controls the camera.

### `_update_aim()` — Central Raycast

```gdscript
func _update_aim() -> void:
	var space_state := get_world_3d().direct_space_state
	var ray_origin := camera.global_position
	var ray_dir := -camera.global_transform.basis.z    # camera forward
	var ray_end := ray_origin + ray_dir * AIM_DISTANCE
	
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 3       # bits 1+2: structures + debris
	query.exclude = [get_rid()]    # skip own collision body
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
```

**Why this matters:**  
This single raycast powers EVERY interaction — debris pickup, hook throw direction, and building placement. The crosshair is at screen center, and this ray fires from the camera through that exact screen center. This guarantees the crosshair and all interactions point at the same world location.

### `_physics_process(delta)` — Main Loop

```
1. _update_aim()                        # Fire raycast every frame
2. Get ocean height at player position
3. Read movement input (WASD → Vector2)
4. Calculate movement direction from camera facing
5. If swimming → _update_swimming()
   If on land  → _update_land()
6. move_and_slide()                     # CharacterBody3D physics
7. _update_swimming_state()             # Check if entered/exited water
```

### Swimming State Machine

```
				 ┌────────────────────────────┐
				 │        ON LAND             │
				 │  velocity.y -= gravity     │
				 │  jump = upward burst       │
				 │  C key = dive              │
				 └───────────┬────────────────┘
							 │ player.y < water_y + 0.3
							 ↓
				 ┌────────────────────────────┐
				 │      IS SWIMMING           │
				 │  Space = swim up           │
				 │  C = swim down             │
				 │  No input = decelerate     │
				 │  Near surface = buoyancy   │
				 └───────────┬────────────────┘
							 │ player.y > water_y + 1.5
							 │ OR is_on_floor()
							 ↓
				 ┌────────────────────────────┐
				 │        ON LAND             │
				 │  Clamp velocity.y ≤ 0      │
				 └────────────────────────────┘
```

**Key swimming details:**
- **Water enter:** Player y-position drops below `water_y + 0.3m`
- **Water exit:** Player y-position rises above `water_y + 1.5m` OR stands on a floor (raft)
- **Buoyancy:** Only active near the surface (depth between -1 and 2 meters). Pushes player toward `water_y + 0.2m` with spring force. Prevents violent surface shaking by only applying when `|error| > 0.3`.
- **Depth limit:** At 30m depth, vertical velocity is damped to zero.

---

## 7. Camera & Crosshair

### Camera Setup (in `main.tscn`)

```
Player (CharacterBody3D)
└── CamPivot (Node3D)                     # pitch rotation
	└── SpringArm3D (length=0.0)          # no arm — camera at pivot position
		└── Camera3D                      # offset = (0, 0.6, 0)
```

- **SpringArm3D length = 0.0:** Camera sits exactly at the CamPivot position (no spring-back)
- **Camera offset (0, 0.6, 0):** Eye level, 0.6m above player's feet
- **No player mesh visible:** `MeshInstance3D.visible = false` in both scene and code
- **First-person:** The camera IS the player's eyes. Crosshair = screen center = aim point.

### Crosshair (`crosshair.gd`)

```gdscript
extends Control

enum State { NONE, ITEM, BUILD }

@export var crosshair_size: float = 24.0
@export var line_width: float = 3.0
@export var aim_vertical_offset: float = 0.0
@export var color_idle: Color = Color(1.0, 1.0, 1.0, 0.85)     # white
@export var color_item: Color = Color(0.4, 1.0, 0.4, 0.95)     # green
@export var color_build: Color = Color(0.4, 0.8, 1.0, 0.95)    # blue

var state: int = State.NONE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # don't block mouse
    custom_minimum_size = Vector2(crosshair_size, crosshair_size)
    # Center on screen
    set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    get_viewport().size_changed.connect(_position_reticle)
    _position_reticle()

func _position_reticle() -> void:
    var vp := get_viewport_rect().size
    var half := custom_minimum_size * 0.5
    position = Vector2(vp.x * 0.5 - half.x, vp.y * 0.5 + aim_vertical_offset - half.y)

func _draw() -> void:
    var col: Color = color_idle
    if state == State.ITEM:  col = color_item
    elif state == State.BUILD: col = color_build
    var r: float = crosshair_size * 0.5
    var radius: float = max(r - line_width * 0.5, 0.5)
    draw_arc(Vector2(r, r), radius, 0.0, TAU, 32, col, line_width, true)
```

**Crosshair states:**
- **NONE (white):** Default. Looking at nothing relevant.
- **ITEM (green):** Looking at collectible debris within pickup range, or an interactable door.
- **BUILD (blue):** In build mode, or editing a placed building.

---

## 8. Ocean System

**File:** `ocean.gd`  
**Node:** `MeshInstance3D` (large water plane in the scene)  
**Group:** "ocean"

```gdscript
extends MeshInstance3D
class_name Ocean

@export var wave_height := 0.4
@export var wave_speed := 1.2
var _time := 0.0

func _ready() -> void:
    add_to_group("ocean")

func _process(delta: float) -> void:
    _time += delta

func get_height(world_pos: Vector3) -> float:
    var h := sin(world_pos.x * 0.4 + _time * wave_speed) \
        + sin(world_pos.z * 0.3 + _time * wave_speed * 0.8) \
        + 0.5 * sin((world_pos.x + world_pos.z) * 0.7 + _time * 1.7)
    return global_position.y + h * wave_height * 0.33
```

**How it works:**
- The ocean is a giant `MeshInstance3D` (flat plane) with a blue material.
- `get_height()` returns the exact water surface Y at any world position.
- Uses **3 sine waves** with different frequencies, speeds, and phases for natural-looking waves:
  - Wave 1: frequency 0.4 along X, speed 1.2
  - Wave 2: frequency 0.3 along Z, speed 0.96 (1.2 × 0.8)
  - Wave 3: diagonal (X+Z) at frequency 0.7, speed 1.7, half amplitude
- The final height = `ocean_y + h × 0.4 × 0.33` = ocean_y + h × 0.133
- Maximum wave amplitude: ~0.4m (0.133 × 3 peaks)

**Who calls `get_height()`:**
- `raft.gd` — to float on the surface
- `debris.gd` — to bob on the surface
- `rope_system.gd` — to snap the hook to water level

---

## 9. Raft System

### `raft.tscn` Scene Tree

```
Raft (AnimatableBody3D)              # script: raft.gd
├── CollisionShape3D                 # BoxShape3D (2×0.3×2)
├── MeshInstance3D                   # BoxMesh (2×0.3×2) — brown planks
├── F1 (Marker3D)                    # (0.9, 0, 0.9)  — corner for wave sampling
├── F2 (Marker3D)                    # (-0.9, 0, 0.9)
├── F3 (Marker3D)                    # (0.9, 0, -0.9)
├── F4 (Marker3D)                    # (-0.9, 0, -0.9)
└── BuildSockets (Node3D)
    ├── Socket_North (Marker3D)      # (0, 0, 1)
    ├── Socket_South (Marker3D)      # (0, 0, -1)
    ├── Socket_East (Marker3D)       # (1, 0, 0)
    ├── Socket_West (Marker3D)       # (-1, 0, 0)
    ├── Socket_NorthEast (Marker3D)  # (0.707, 0, 0.707)
    ├── Socket_NorthWest (Marker3D)  # (-0.707, 0, 0.707)
    ├── Socket_SouthEast (Marker3D)  # (0.707, 0, -0.707)
    └── Socket_SouthWest (Marker3D)  # (-0.707, 0, -0.707)
```

### `raft.gd` — Floating Physics

```gdscript
extends AnimatableBody3D

@export var float_height: float = 0.6   # deck sits 0.6m above water
@export var follow_speed: float = 4.0    # how fast it follows waves

var ocean: Ocean = null
var _markers: Array = []     # [F1, F2, F3, F4]

func _ready() -> void:
    add_to_group("build_surface")  # raft is a valid build target
    _markers = [
        get_node_or_null("F1"),
        get_node_or_null("F2"),
        get_node_or_null("F3"),
        get_node_or_null("F4"),
    ]
    rotation = Vector3.ZERO  # raft stays level, never tilts

func _physics_process(delta: float) -> void:
    var oc := _get_ocean()
    if oc == null: return
    
    # Average wave height at 4 corners
    var avg_height: float = 0.0
    var count: int = 0
    for m in _markers:
        if m != null:
            avg_height += float(oc.get_height(m.global_position))
            count += 1
    if count > 0:
        avg_height /= float(count)
    
    # Smoothly move to target height
    var target_y: float = avg_height + float_height
    global_position.y = lerpf(
        global_position.y,
        target_y,
        1.0 - exp(-follow_speed * delta)
    )
```

**Key design decisions:**
- **`AnimatableBody3D`:** Can be moved by code but still collides with CharacterBody3D (the player). This is how the player stands on the moving raft.
- **4-corner averaging:** Samples wave height at each corner marker and averages them. This prevents the raft from tilting on waves — it only moves up/down as a unit.
- **`lerpf()` with exponential smoothing:** Smooth, frame-rate-independent motion. At 120 physics ticks/sec, `1 - exp(-4 * (1/120)) ≈ 0.033`, so the raft moves ~3.3% toward the target each tick.
- **`float_height = 0.6`:** The raft deck top sits 0.6m above average water level. Wave peaks (0.4m max) never wash over the deck.

---

## 10. Debris System

### Debris Scene (`debris.tscn`)

```
Debris (RigidBody3D)                  # script: debris.gd
├── CollisionShape3D                  # BoxShape3D (0.6×0.3×0.6)
├── MeshInstance3D                    # BoxMesh (0.6×0.3×0.6)
└── F1 (Marker3D)                     # unused marker
```

**Size:** 0.6×0.3×0.6 meters — small floating debris, realistic.

### `debris.gd` — Buoyancy & Current

```gdscript
extends RigidBody3D
class_name Debris

@export var item_name := "Wood"
@export var current_direction: Vector3 = Vector3(0, 0, 1)
@export var current_speed: float = 1.2
@export var freeboard: float = 0.15      # how high above water
@export var buoyancy: float = 8.0
@export var max_vertical_speed: float = 2.0

var travel_start: Vector3 = Vector3.ZERO  # spawn position (for despawn check)
var collected: bool = false
var is_hooked: bool = false
```

**Item Profiles (visual + physics per type):**

| Item | Mass (kg) | Freeboard (m) | Color |
|---|---|---|---|
| Wood | 2.0 | 0.20 | Warm brown (0.85, 0.65, 0.35) |
| Rope | 1.0 | 0.05 | Dark tan (0.75, 0.60, 0.35) |
| Plastic | 0.6 | 0.25 | Light blue (0.3, 0.7, 1.0) |
| Barrel | 6.0 | 0.30 | Dark brown (0.70, 0.45, 0.20) |
| Stone | 4.0 | 0.10 | Gray (0.65, 0.65, 0.65) |
| Metal | 5.0 | 0.15 | Silver (0.80, 0.80, 0.85) |

**Buoyancy Physics (per frame):**

```gdscript
func _physics_process(delta: float) -> void:
    if freeze or is_hooked or collected:
        return    # skip when rope is holding this piece
    
    var water_y := float(ocean.get_height(global_position))
    
    # Vertical: rest at water surface + freeboard
    var rest_y := water_y + freeboard
    var y_error := rest_y - global_position.y
    linear_velocity.y += (buoyancy * y_error - BUOY_DAMPING * linear_velocity.y) * delta
    linear_velocity.y = clamp(linear_velocity.y, -max_vertical_speed, max_vertical_speed)
    
    # Horizontal: current direction + small random drift
    var target_velocity := dir * current_speed * _speed_variation + side * _side_drift
    var k := 1.0 - exp(-3.0 * delta)
    linear_velocity.x = lerpf(linear_velocity.x, target_velocity.x, k)
    linear_velocity.z = lerpf(linear_velocity.z, target_velocity.z, k)
    
    # Gentle tumble
    angular_velocity = Vector3(sin(t * 0.5) * 0.2, _rot_speed, cos(t * 0.4) * 0.2)
```

**How buoyancy works:**
1. **Target Y** = ocean surface height + freeboard (how high the item floats)
2. **Error** = target Y - current Y (positive means too low, negative means too high)
3. **Spring force** = buoyancy × error (pushes toward target)
4. **Damping** = -BUOY_DAMPING × velocity (prevents oscillation)
5. **Result:** Item smoothly bobs to the correct water level, then gently follows waves

**Collision layers:**
- Layer 2 (debris): Pickup raycast can detect it
- Mask 1 (structures): Physically collides with raft/player

**Fade in/out:**
- On spawn: alpha goes from 0 to 1 over 1.5 seconds
- Before despawn: alpha goes from 1 to 0 over 1.5 seconds
- Uses `StandardMaterial3D.albedo_color.a` for transparency

### `debris_spawner.gd` — Continuous Spawning

```gdscript
extends Node3D

@export var debris_scene: PackedScene
@export var current_direction: Vector3 = Vector3(0, 0, 1)
@export var current_speed: float = 1.2
@export var spawn_width: float = 60.0       # lateral spread
@export var upstream_distance: float = 80.0  # how far upstream to spawn
@export var downstream_distance: float = 120.0 # how far before despawn
@export var max_debris: int = 80
@export var prewarm_count: int = 35          # spawn 35 at startup

# Spawn timing: 0.2–0.5 seconds between spawns
@export var spawn_interval_min: float = 0.2
@export var spawn_interval_max: float = 0.5
```

**Spawn flow:**

```
_prewarm() → 35 debris spread from -80m to +60m along current
                ↓
每一 0.2–0.5 sec:
    _cleanup() → fade out debris past +120m
    _spawn_upstream() → new debris at -80m to -64m
                ↓
    Random position:
        along current: -80m to -64m (upstream)
        lateral: ±30m (spawn_width / 2)
        jitter: ±5m
                ↓
    Random item from pool:
        Wood ×6, Rope ×3, Plastic ×2, Barrel ×1, Stone ×2, Metal ×1
                ↓
    Current speed varies: 0.7× to 1.3× base speed
```

**Despawn logic:**

```gdscript
func _cleanup() -> void:
    for d in _active:
        var travelled: float = (d.global_position - d.travel_start).dot(_direction)
        if travelled > downstream_distance and not d._is_fading_out:
            d.start_fade_out()    # begin 1.5s fade
        if d.is_fade_done():
            d.queue_free()        # fully faded → remove
```

---

## 11. Rope / Hook System

**File:** `rope_system.gd` (483 lines)  
**Node:** `RopeSystem` (Node3D, child of Player)

### State Machine

```
         ┌──────────┐
         │   IDLE   │ ← hold Q to charge, release to throw
         └────┬─────┘
              │ Q release
              ↓
         ┌──────────┐
         │ THROWING │ ← hook flies along locked direction
         └────┬─────┘
              │ reached max distance / hit debris
              ↓
      ┌───────┴────────┐
      │                │
┌─────┴─────┐    ┌─────┴─────┐
│  EXTENDED │    │  HOOKED   │ ← debris attached
└─────┬─────┘    └─────┬─────┘
      │                │
      │ Q/F            │ Q/F
      ↓                ↓
┌──────────────────────────┐
│         REELING          │ ← hook + debris move toward player
└──────────┬───────────────┘
           │ reached player
           ↓
┌──────────────────────────┐
│        RETURNING         │ ← empty hook flies back
└──────────┬───────────────┘
           │ close enough
           ↓
         ┌──────────┐
         │   IDLE   │
         └──────────┘

Cancel (right-click) from any active state → RETURNING
```

### Exported Tuning Variables

```gdscript
@export var max_hook_distance: float = 22.0   # max throw range (meters)
@export var throw_speed: float = 22.0          # hook flight speed (m/s)
@export var reel_speed: float = 12.0           # reel-in speed (m/s)
@export var return_speed: float = 20.0         # empty return speed (m/s)
@export var debris_hook_radius: float = 1.5    # how close hook must get to catch
@export var collection_radius: float = 1.5     # how close to player to collect
```

### Key Variables (Immutable After Throw)

```gdscript
var _throw_direction: Vector3    # captured ONCE at throw moment
var _throw_start: Vector3        # hand position at throw moment
var _hook_world_pos: Vector3     # current hook position in world
var _hook_travelled: float       # distance thrown so far
var _hooked_debris: RigidBody3D  # debris attached to hook
```

### How Throwing Works

```gdscript
func _throw_hook() -> void:
    var aim_point := _get_aim_point()       # camera raycast result
    var hand := _hand_pos()                 # HookOrigin position
    var to_aim := aim_point - hand
    
    # LOCK direction — NEVER recalculated after this
    _throw_direction = (to_aim / aim_dist).normalized()
    _throw_start = hand
    _hook_world_pos = hand                  # hook starts at hand
    
    _state = State.THROWING
```

**Critical rule:** `_throw_direction` is set once and never changes. The hook travels along this fixed world-space vector regardless of where the player looks afterward.

### How Reeling Works

```gdscript
func _handle_reeling(delta: float) -> void:
    var hand := _hand_pos()
    var to_hand := hand - _hook_world_pos
    var dist := to_hand.length()
    
    if dist <= collection_radius:
        _collect_debris()    # add to inventory
        _start_return()      # hook returns
        return
    
    var dir := to_hand.normalized()
    _hook_world_pos += dir * reel_speed * delta  # smooth movement
    
    # Move hooked debris with hook
    if _hooked_debris != null:
        _hooked_debris.global_position = _hook_world_pos + Vector3(0, 0.3, 0)
        _hooked_debris.linear_velocity = Vector3.ZERO
```

### Rope Visual

The rope is a single `CylinderMesh` stretched from the player's hand to the hook:

```gdscript
func _update_rope_visual() -> void:
	var from := _hand_pos()       # HookOrigin (follows player hand)
	var to := _hook_world_pos     # hook position (world-locked)
	var rope_len := from.distance_to(to)
	
	# Position at midpoint
	_rope_mesh.global_position = (from + to) * 0.5
	
	# Orient Y axis along rope direction
	var rope_dir := (to - from).normalized()
	var arbitrary := Vector3.UP
	if abs(rope_dir.dot(Vector3.UP)) > 0.9:
		arbitrary = Vector3.FORWARD
	var right := arbitrary.cross(rope_dir).normalized()
	var perp := rope_dir.cross(right).normalized()
	_rope_mesh.global_transform.basis = Basis(right, rope_dir, perp)
	
	# Stretch cylinder to match distance
	var cyl: CylinderMesh = _rope_mesh.mesh
	cyl.height = rope_len
```

**Why this looks correct:**  
- The `CylinderMesh` extends along its local Y axis.
- `Basis(right, rope_dir, perp)` maps Y to the rope direction.
- The cylinder stretches from hand to hook — one continuous straight line.
- When the player turns, `from` (hand) moves but `to` (hook) stays fixed → rope reorients naturally.

### Hook Origin

```gdscript
func _update_hook_origin() -> void:
	var forward := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	_hook_origin.global_position = player.global_position + right * 0.4 + forward * 0.3 + Vector3(0, 0.8, 0)
```

- **Right +0.4m:** Slightly to the right of the player center (dominant hand)
- **Forward +0.3m:** Slightly in front of the body
- **Up +0.8m:** Chest height
- This position updates every frame, so the rope start point follows the player's hand naturally.

### Debris Detection

```gdscript
func _check_debris() -> void:
    for d in get_tree().get_nodes_in_group("debris"):
        if d is RigidBody3D and is_instance_valid(d):
            if d.get("collected") == true: continue
            if d.global_position.distance_to(_hook_world_pos) <= debris_hook_radius:
                _hook_debris(d)    # attach debris to hook
                return
```

Distance-based detection (1.5m radius). No need for perfect aim — forgiving gameplay.

### Water Surface Interaction

```gdscript
func _snap_hook_to_water() -> void:
    var water_y := _get_ocean_y(_hook_world_pos)
    if _hook_world_pos.y > water_y + 1.0:
        _hook_world_pos.y = water_y + 0.2
```

When the hook reaches max distance, if it's more than 1m above the water, it snaps to 0.2m above the water surface. This prevents the hook from floating in the sky.

---

## 12. Building System

The building system lives entirely in `player.gd`. Here's the complete architecture:

### Build Mode Flow

```
Press B
    ↓
_toggle_build() → build_mode = true
    ↓
_spawn_ghost() → instantiate selected scene as preview
    ↓
Every frame: _update_build_preview()
    ↓
┌────────────────────────────────────────────┐
│ 1. Fire aim raycast (camera center)        │
│ 2. Find buildable target at hit point      │
│ 3. Calculate placement based on piece type │
│ 4. If no target, search all sockets        │
│ 5. Set ghost position + rotation           │
│ 6. Check collision overlap                 │
│ 7. Check structural support                │
│ 8. Show GREEN (valid) or RED (invalid)     │
└────────────────────────────────────────────┘
    ↓
Press E → _try_build()
    ↓
┌────────────────────────────────────────────┐
│ 1. Check build_valid == true               │
│ 2. Check Inventory.can_afford(recipe)       │
│ 3. Inventory.craft(recipe)                  │
│ 4. Instantiate final piece                  │
│ 5. Copy ghost position + rotation          │
│ 6. Add to "build_surface" group            │
└────────────────────────────────────────────┘
```

### Foundation Placement Algorithm

```gdscript
func _calc_foundation_placement(target: Node3D, hit_pos: Vector3, normal: Vector3) -> Vector3:
    # Case 1: Aiming at a WALL top → place as ceiling
    if top_socket != null and normal.y > 0.3:
        return Vector3(sp.x, sp.y + 0.15, sp.z)
    
    # Case 2: Aiming at a SIDE edge (horizontal normal)
    if h_normal.length() > 0.3:
        extend_dir = h_normal.normalized()    # use hit normal
    
    # Case 3: Aiming at TOP surface (normal is UP)
    else:
        extend_dir = camera_forward projected to XZ   # use camera direction
    
    # Apply rotation
    rotated_dir = extend_dir.rotated(Vector3.UP, build_rotation)
    
    # Place center 2.0m away from target center in that direction
    placement = target.global_position + rotated_dir * 2.0
    placement.y = target.global_position.y
    return placement
```

**Why this works:**  
- The raft is 2×2m. Its center is at `target.global_position`.
- The edge is 1.0m from center (half-size).
- The new foundation center is placed 2.0m from the target center = 1.0m beyond the edge.
- New foundation near edge = center - 1.0 = target edge. **Perfect alignment.**

### Wall Placement

```gdscript
func _calc_wall_placement(target: Node3D, hit_pos: Vector3, normal: Vector3) -> Vector3:
    # Find nearest socket on the foundation
    best_socket = nearest_socket_to_aim
    
    # Wall sits at the socket position (at the foundation edge)
    return Vector3(sp.x, sp.y + 1.25, sp.z)   # 1.25 = half wall height
```

- Wall center is at the foundation edge (socket position).
- Wall height = 2.5m, half = 1.25m, so bottom is at foundation surface.

### Structural Support Check

```gdscript
func _check_support(pos: Vector3, piece_name: String) -> bool:
    # Foundation: must be within 1.5–2.5m of an existing structure (edge-to-edge)
    # Wall: must be within 1.2m of a foundation center (directly above)
    # Door: must be within 2.0m of a Wall
    # Window: must be within 1.0m of a Wall
```

### Validation Pipeline

```
Position calculated
    ↓
Collision check: BoxShape3D at position, exclude player + ghost + all structures
    ↓
If collision found → INVALID
    ↓
Support check: must be connected to raft/foundation tree
    ↓
If no support → INVALID
    ↓
Both pass → VALID → GREEN preview
```

### Socket System

Every buildable piece has `BuildSockets` (Node3D) with `Marker3D` children:

```
Foundation (2×2)
├── Socket_North      (0, 0, 1)     ← edge center
├── Socket_South      (0, 0, -1)
├── Socket_East       (1, 0, 0)
├── Socket_West       (-1, 0, 0)
├── Socket_NorthEast  (0.707, 0, 0.707)  ← corner
├── Socket_NorthWest  (-0.707, 0, 0.707)
├── Socket_SouthEast  (0.707, 0, -0.707)
└── Socket_SouthWest  (-0.707, 0, -0.707)

Wall (2×2.5×0.2)
├── Socket_Base       (0, -1.25, 0)   ← bottom center
├── Socket_Top        (0, 1.25, 0)    ← top center (for ceiling)
├── Socket_Left       (-1, 0, 0)      ← left edge
└── Socket_Right      (1, 0, 0)       ← right edge

Window (1.5×1.5)
└── Socket_Center     (0, 0, 0)

Door (1×2)
├── Socket_Front      (0, 0, 0.1)
└── Socket_Back       (0, 0, -0.1)
```

### Empty-Space Socket Search

When the crosshair points at ocean/sky (no direct target), the system searches ALL build surfaces for nearby sockets:

```gdscript
func _find_nearest_valid_socket(aim: Vector3, piece_name: String) -> Vector3:
    for surf in get_tree().get_nodes_in_group("build_surface"):
        for socket in _get_build_sockets(surf):
            var dist: float = aim.distance_to(socket.global_position)
            if dist >= best_dist: continue
            
            # Calculate where piece would go from this socket
            if piece_name == "Foundation":
                # Offset = 1.0 (half piece size) in socket direction
                candidate = socket_pos + Vector3(0, 0, 1)  # for Socket_North
```

**Important:** The offset is **1.0m** (half piece size), not 2.0m. The socket is already at the edge, so we only need to offset by the half-size to place the new center.

### Edit Mode

**Double-click E** on any placed building (NOT the raft):

```gdscript
func _start_edit(target: Node3D) -> void:
    _editing = target
    _edit_original_pos = target.global_position
    _edit_original_rot = target.rotation
	# Disable collision so it doesn't push physics
	col.disabled = true
	# Make blue/transparent
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.6)
```

```gdscript
func _update_edit_follow() -> void:
	# Snap to 2m grid aligned with raft (raft at z=-3)
	target_pos.x = snapped(target_pos.x, 2.0)
	target_pos.z = snapped(target_pos.z + 3.0, 2.0) - 3.0
	target_pos.y = _edit_original_pos.y
	_editing.global_position = target_pos
```

```gdscript
func _confirm_edit() -> void:
	# Check overlap at new position
	# If clear → keep new position
	# If overlap → snap back to original
	col.disabled = false
	_apply_building_color(_editing)
	_editing = null
```

```gdscript
func _remove_editing() -> void:
	# Refund resources
	for recipe_name in RECIPE_REFUND:
		if building_name.begins_with(recipe_name):
			for item in refund:
				Inventory.add(item, refund[item])
	_editing.queue_free()
```

### Refund Table

| Building | Refund |
|---|---|
| Foundation | 5 Wood |
| Wall | 8 Wood + 1 Rope |
| Stairs | 6 Wood + 1 Rope |
| Door | 4 Wood + 1 Rope |
| Window | 3 Wood + 1 Plastic |

---

## 13. Inventory System

**File:** `inventory.gd`  
**Autoload Name:** `Inventory`

```gdscript
extends Node

var items := {"Wood": 0, "Rope": 0, "Plastic": 0, "Barrel": 0, "Stone": 0, "Metal": 0}
var infinite: bool = false   # debug: bypass all costs

const RECIPES := {
	"Foundation":      {"Wood": 5},
	"Wall":            {"Wood": 8, "Rope": 1},
	"Stairs":          {"Wood": 6, "Rope": 1},
	"Door":            {"Wood": 4, "Rope": 1},
	"Window":          {"Wood": 3, "Plastic": 1},
	"Bonfire":         {"Wood": 8, "Rope": 2},
	"Raft Extension":  {"Wood": 10, "Plastic": 2},
}

func add(item: String, amount: int = 1) -> void:
	items[item] = items.get(item, 0) + amount

func can_afford(recipe: String) -> bool:
	if infinite: return true
	for item in RECIPES[recipe]:
		if items.get(item, 0) < RECIPES[recipe][item]:
			return false
	return true

func craft(recipe: String) -> bool:
	if not can_afford(recipe): return false
	if infinite: return true
	for item in RECIPES[recipe]:
		remove(item, RECIPES[recipe][item])
	return true
```

---

## 14. Door System

### `door.gd`

```gdscript
extends AnimatableBody3D
class_name Door

@export var open_angle: float = 90.0
@export var swing_speed: float = 4.0
var is_open: bool = false
var _target_rotation: float = 0.0

func toggle() -> void:
	is_open = !is_open
	_target_rotation = deg_to_rad(open_angle) if is_open else 0.0

func _physics_process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _target_rotation, delta * swing_speed)
```

**Interaction:** Press E while aiming at the door → calls `toggle()` → door swings open/closed with smooth lerp.

### `door.tscn` Scene Tree

```
Door (AnimatableBody3D)            # script: door.gd
├── CollisionShape3D               # BoxShape3D (1.0×2.0×0.12) — thin door slab
├── FrameLeft (MeshInstance3D)     # BoxMesh (0.12×2.0×0.12) — dark frame
├── FrameRight (MeshInstance3D)    # same
├── FrameTop (MeshInstance3D)      # BoxMesh (1.0×0.12×0.12) — header
├── Panel (MeshInstance3D)         # BoxMesh (0.76×1.7×0.06) — lighter door panel
├── Handle (MeshInstance3D)        # SphereMesh (r=0.035) — gold knob
├── Hinge1 (MeshInstance3D)        # BoxMesh (0.08×0.04×0.02) — metal hinge
├── Hinge2 (MeshInstance3D)        # second hinge
├── IntractZone (Area3D)           # detection zone
│   └── CollisionShape3D           # BoxShape3D (1.8×2.5×1.8) — large trigger
└── BuildSockets (Node3D)
	├── Socket_Front (0, 0, 0.1)
	└── Socket_Back (0, 0, -0.1)
```

---

## 15. Building Scenes

### Foundation (`foundation.tscn`)

```
Foundation (StaticBody3D)
├── CollisionShape3D               # BoxShape3D (2×0.3×2)
├── MeshInstance3D                 # BoxMesh (2×0.3×2) — brown material
└── BuildSockets (Node3D)          # 8 sockets: N/S/E/W/NE/NW/SE/SW
```

**Size:** 2×0.3×2 meters — a flat platform that tiles perfectly.

### Wall (`wall.tscn`)

```
Wall (StaticBody3D)
├── CollisionShape3D               # BoxShape3D (2×2.5×0.2)
├── MeshInstance3D                 # BoxMesh (2×2.5×0.2) — darker brown
└── BuildSockets (Node3D)
	├── Socket_Base (0, -1.25, 0)  # bottom center
	├── Socket_Top (0, 1.25, 0)    # top center
	├── Socket_Left (-1, 0, 0)     # left edge
	└── Socket_Right (1, 0, 0)     # right edge
```

**Size:** 2×2.5×0.2 meters — tall vertical panel.

### Window (`window.tscn`)

```
Window (StaticBody3D)
├── CollisionShape3D               # BoxShape3D (1.5×1.5×0.1)
├── MeshInstance3D                 # PlaneMesh (1.5×1.5) — transparent blue
└── BuildSockets (Node3D)
	└── Socket_Center (0, 0, 0)
```

**Material:** Transparent glass (alpha 0.35, metallic, low roughness).

### Stairs (`stairs.tscn`)

```
Stairs (StaticBody3D)              # Rotated 30° via transform
├── CollisionShape3D               # BoxShape3D (2×0.2×2.8) — covers all steps
├── Step01 (MeshInstance3D)        # BoxMesh (2×0.2×0.4)
├── Step02                         # offset (0, 0.2, 0.4)
├── Step03                         # offset (0, 0.4, 0.8)
├── Step04                         # offset (0, 0.6, 1.2)
└── Step05                         # offset (0, 0.8, 1.6)
```

**5 steps**, each 0.2m tall and 0.4m deep, at 30° incline.

---

## 16. Physics & Collision Layers

### Layer Assignments

| Bit | Layer Name | Used By |
|---|---|---|
| 1 | Structures | Raft, foundations, walls (StaticBody3D/AnimatableBody3D) |
| 2 | Debris | Floating debris (RigidBody3D) |
| 3 | Player | Player CharacterBody3D |

### Raycast Masks

| Raycast | Mask | Purpose |
|---|---|---|
| Player `_update_aim()` | 3 (bits 1+2) | Detect structures + debris, exclude self |
| RopeSystem `_aim_ray` | 3 (bits 1+2) | Hook aim — same targets |

### Physics Engine

```ini
[physics]
common/physics_ticks_per_second=120    # high tick rate for smooth physics
3d/physics_engine="Jolt Physics"       # Jolt for accurate collision
```

---

## 17. Complete Code — All Scripts

### `inventory.gd` (Autoload)

```gdscript
extends Node

var items := {"Wood": 0, "Rope": 0, "Plastic": 0, "Barrel": 0, "Stone": 0, "Metal": 0}
var infinite: bool = false

const RECIPES := {
	"Foundation":      {"Wood": 5},
	"Wall":            {"Wood": 8, "Rope": 1},
	"Stairs":          {"Wood": 6, "Rope": 1},
	"Door":            {"Wood": 4, "Rope": 1},
	"Window":          {"Wood": 3, "Plastic": 1},
	"Bonfire":         {"Wood": 8, "Rope": 2},
	"Raft Extension":  {"Wood": 10, "Plastic": 2},
}

func add(item: String, amount: int = 1) -> void:
	items[item] = items.get(item, 0) + amount
	print("Inventory:", items)

func has(item: String, amount: int) -> bool:
	return items.get(item, 0) >= amount

func remove(item: String, amount: int) -> void:
	items[item] = items.get(item, 0) - amount

func can_afford(recipe: String) -> bool:
	if infinite: return true
	if not RECIPES.has(recipe): return false
	for item in RECIPES[recipe]:
		if items.get(item, 0) < RECIPES[recipe][item]:
			return false
	return true

func craft(recipe: String) -> bool:
	if not RECIPES.has(recipe): return false
	if not can_afford(recipe): return false
	if infinite: return true
	for item in RECIPES[recipe]:
		remove(item, RECIPES[recipe][item])
	return true
```

### `ocean.gd`

```gdscript
extends MeshInstance3D
class_name Ocean

@export var wave_height := 0.4
@export var wave_speed := 1.2
var _time := 0.0

func _ready() -> void:
	add_to_group("ocean")

func _process(delta: float) -> void:
	_time += delta

func get_height(world_pos: Vector3) -> float:
	var h := sin(world_pos.x * 0.4 + _time * wave_speed) \
		+ sin(world_pos.z * 0.3 + _time * wave_speed * 0.8) \
		+ 0.5 * sin((world_pos.x + world_pos.z) * 0.7 + _time * 1.7)
	return global_position.y + h * wave_height * 0.33
```

### `raft.gd`

```gdscript
extends AnimatableBody3D

@export var float_height: float = 0.6
@export var follow_speed: float = 4.0

var ocean: Ocean = null
var _markers: Array = []

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
		if ocean == null:
			ocean = get_node_or_null("%Ocean")
	return ocean

func _physics_process(delta: float) -> void:
	var oc := _get_ocean()
	if oc == null: return
	var avg_height: float = 0.0
	var count: int = 0
	for m in _markers:
		if m != null:
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

### `debris.gd`

```gdscript
extends RigidBody3D
class_name Debris

@export var item_name := "Wood"
@export var current_direction: Vector3 = Vector3(0, 0, 1)
@export var current_speed: float = 1.2
@export var freeboard: float = 0.15
@export var buoyancy: float = 8.0
@export var max_vertical_speed: float = 2.0

var travel_start: Vector3 = Vector3.ZERO
var collected: bool = false
var is_hooked: bool = false
var mass_kg: float = 2.0
var ocean: Ocean = null
var _wander_seed: float = 0.0
var _side_drift: float = 0.0
var _speed_variation: float = 1.0
var _rot_speed: float = 0.0
var _fade_timer: float = 0.0
var _fade_duration: float = 1.5
var _is_fading_in: bool = true
var _is_fading_out: bool = false
var _fade_material: StandardMaterial3D = null

const BUOY_DAMPING: float = 3.0

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
	gravity_scale = 0.0
	collision_layer = 2
	collision_mask = 1
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
	if freeze or is_hooked or collected: return
	if ocean == null: return
	var water_y: float = float(ocean.get_height(global_position))
	var rest_y: float = water_y + freeboard
	var y_error: float = rest_y - global_position.y
	linear_velocity.y += (buoyancy * y_error - BUOY_DAMPING * linear_velocity.y) * delta
	linear_velocity.y = clamp(linear_velocity.y, -max_vertical_speed, max_vertical_speed)
	var dir: Vector3 = Vector3(current_direction.x, 0.0, current_direction.z).normalized()
	var side: Vector3 = Vector3(-dir.z, 0.0, dir.x).normalized()
	var target_velocity: Vector3 = dir * current_speed * _speed_variation + side * _side_drift
	var k: float = 1.0 - exp(-3.0 * delta)
	linear_velocity.x = lerpf(linear_velocity.x, target_velocity.x, k)
	linear_velocity.z = lerpf(linear_velocity.z, target_velocity.z, k)
	var t: float = Time.get_ticks_msec() / 1000.0 + _wander_seed
	angular_velocity = Vector3(sin(t * 0.5) * 0.2, _rot_speed, cos(t * 0.4) * 0.2)
	if _is_fading_in and _fade_material != null:
		_fade_timer += delta
		var alpha: float = clampf(_fade_timer / _fade_duration, 0.0, 1.0)
		_fade_material.albedo_color.a = alpha
		if alpha >= 1.0:
			_is_fading_in = false
	if _is_fading_out and _fade_material != null:
		_fade_timer += delta
		var alpha: float = clampf(1.0 - _fade_timer / _fade_duration, 0.0, 1.0)
		_fade_material.albedo_color.a = alpha
```

### `debris_spawner.gd`

```gdscript
extends Node3D

@export var debris_scene: PackedScene
@export var current_direction: Vector3 = Vector3(0, 0, 1)
@export var current_speed: float = 1.2
@export var spawn_width: float = 60.0
@export var upstream_distance: float = 80.0
@export var downstream_distance: float = 120.0
@export var max_debris: int = 80
@export var prewarm_count: int = 35
@export var spawn_interval_min: float = 0.2
@export var spawn_interval_max: float = 0.5

var _timer: float = 0.0
var _next_interval: float = 0.0
var _active: Array = []
var player: Node3D
var _direction: Vector3 = Vector3.ZERO
var _side: Vector3 = Vector3.ZERO

const ITEM_POOL := [
	"Wood","Wood","Wood","Wood","Wood","Wood",
	"Rope","Rope","Rope",
	"Plastic","Plastic",
	"Barrel",
	"Stone","Stone",
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

func _prewarm() -> void:
	for i in prewarm_count:
		var dist := randf_range(-upstream_distance, downstream_distance * 0.5)
		_spawn_at(dist)

func _spawn_upstream() -> void:
	_spawn_at(-randf_range(upstream_distance * 0.8, upstream_distance))

func _spawn_at(along_t: float) -> void:
	if not debris_scene: return
	var d = debris_scene.instantiate()
	var p := _get_player()
	var origin := p.global_position if p != null else Vector3.ZERO
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
		if d.freeze: continue
		var travelled: float = (Vector3(d.global_position) - Vector3(d.travel_start)).dot(_direction)
		if travelled > downstream_distance and not d._is_fading_out:
			d.start_fade_out()
		if d.is_fade_done():
			d.queue_free()
			_active.remove_at(i)
```

### `crosshair.gd`

```gdscript
extends Control

enum State { NONE, ITEM, BUILD }

@export var crosshair_size: float = 24.0
@export var line_width: float = 3.0
@export var aim_vertical_offset: float = 0.0
@export var color_idle: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var color_item: Color = Color(0.4, 1.0, 0.4, 0.95)
@export var color_build: Color = Color(0.4, 0.8, 1.0, 0.95)

var state: int = State.NONE

func _ready() -> void:
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
	position = Vector2(vp.x * 0.5 - half.x, vp.y * 0.5 + aim_vertical_offset - half.y)

func _draw() -> void:
	var col: Color = color_idle
	if state == State.ITEM: col = color_item
	elif state == State.BUILD: col = color_build
	var r: float = crosshair_size * 0.5
	var radius: float = max(r - line_width * 0.5, 0.5)
	draw_arc(Vector2(r, r), radius, 0.0, TAU, 32, col, line_width, true)
```

### `door.gd`

```gdscript
extends AnimatableBody3D
class_name Door

@export var open_angle: float = 90.0
@export var swing_speed: float = 4.0
var is_open: bool = false
var _target_rotation: float = 0.0

func toggle() -> void:
	is_open = !is_open
	_target_rotation = deg_to_rad(open_angle) if is_open else 0.0

func _physics_process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _target_rotation, delta * swing_speed)
```

### `rope_system.gd`

*(Full code: 483 lines — see Section 11 for complete breakdown with all state handlers, throw logic, reel logic, debris detection, rope visual, and charge bar UI.)*

### `player.gd`

*(Full code: 980 lines — see Sections 6 and 12 for complete breakdown with movement, swimming, aim, building, editing, and HUD.)*

---

## 18. Complete Code — All Scenes

### `main.tscn` Key Properties

```
Main (Node3D)
├── DirectionalLight3D
├── WorldEnvironment
├── Ocean (MeshInstance3D) [script: ocean.gd]
├── Raft (AnimatableBody3D) [script: raft.gd] at position (0, 1.0, -3)
│   ├── CollisionShape3D: BoxShape3D(2, 0.3, 2)
│   ├── MeshInstance3D: BoxMesh(2, 0.3, 2)
│   ├── F1–F4: Marker3D corners
│   └── BuildSockets: 8 edge sockets
├── Player (CharacterBody3D) [script: player.gd]
│   ├── CollisionShape3D: CapsuleShape3D
│   ├── MeshInstance3D: visible=false (first-person)
│   ├── CamPivot
│   │   └── SpringArm3D(length=0.0)
│   │       └── Camera3D(offset=0,0.6,0)
│   ├── RopeSystem (Node3D) [script: rope_system.gd]
│   └── CanvasLayer
│       ├── Crosshair [script: crosshair.gd]
│       └── InventoryHUD (Label)
└── DebrisSpawner (Node3D) [script: debris_spawner.gd]
```

---

## 19. Game Loop & Frame Flow

### Every Physics Tick (120 Hz)

```
Player._physics_process(delta)
├── _update_aim()                          # Fire raycast from camera center
├── Get ocean height at player position
├── Read WASD input → calculate direction
├── if is_swimming:
│   └── _update_swimming(delta)
│       ├── Space = swim up / water jump
│       ├── C = swim down
│       ├── No input = decelerate
│       └── Near surface = buoyancy
│   else:
│   └── _update_land(delta)
│       ├── WASD = walk/sprint
│       ├── Space = jump
│       └── C = dive
├── move_and_slide()                       # CharacterBody3D physics
└── _update_swimming_state()               # Check water entry/exit

Raft._physics_process(delta)
├── Sample wave height at 4 corners
├── Average them
├── Calculate target_y = avg + float_height
└── Smoothly lerp to target_y

RopeSystem._physics_process(delta)
├── _update_hook_origin()                  # Follow player hand
├── match _state:
│   ├── IDLE: handle Q charge/release
│   ├── THROWING: move hook along locked direction
│   ├── EXTENDED: wait for Q/F/reel or cancel
│   ├── HOOKED: wait for reel input
│   ├── REELING: move hook toward player
│   └── RETURNING: empty hook returns
├── _update_hook_visual()                  # Position hook mesh
├── _update_rope_visual()                  # Stretch rope mesh
└── _update_charge_bar_ui()               # Show charge bar

Debris._physics_process(delta)             # Each debris instance
├── if frozen/hooked/collected: skip
├── Calculate buoyancy force toward water surface
├── Apply horizontal current + drift
├── Gentle angular tumble
└── Fade in/out alpha

DebrisSpawner._process(delta)              # Node3D timer
├── _timer += delta
├── if timer >= next_interval:
│   ├── _cleanup()                         # Fade+remove past debris
│   └── _spawn_upstream()                  # New debris at -80m
```

### Every Render Frame

```
Player._process(delta)
├── _update_hud()                          # Update label text
├── Handle build mode input (B, Tab, R)
├── Handle edit mode input (E, X)
├── Handle double-click detection
├── Handle normal E pickup
└── Update crosshair state

Crosshair._process(_delta)
└── _position_reticle()                    # Keep centered on screen
```

---

## 20. State Machines

### Rope System State Machine

| State | Input | Next State | Action |
|---|---|---|---|
| IDLE | Q hold→release | THROWING | Capture aim direction, start hook flight |
| THROWING | max distance reached | EXTENDED | Hook stops at target |
| THROWING | debris within 1.5m | HOOKED | Debris attaches to hook |
| EXTENDED | Q or F | REELING | Pull hook back |
| EXTENDED | Right-click | RETURNING | Cancel, return empty hook |
| HOOKED | Q or F | REELING | Pull hook+debris back |
| HOOKED | Right-click | RETURNING | Release debris, return hook |
| REELING | distance ≤ 1.5m | RETURNING | Collect debris, start return |
| RETURNING | distance ≤ 0.5m | IDLE | Hook hidden, ready for next throw |

### Player Swimming State

| State | Condition | Next State |
|---|---|---|
| ON LAND | player.y < water_y + 0.3 | IS SWIMMING |
| IS SWIMMING | player.y > water_y + 1.5 | ON LAND |
| IS SWIMMING | is_on_floor() | ON LAND |

### Building Mode

| State | Input | Next State |
|---|---|---|
| NOT BUILDING | B | BUILDING |
| BUILDING | B | NOT BUILDING |
| BUILDING | E (valid ghost) | NOT BUILDING (piece placed) |
| NOT BUILDING | Double-click E on building | EDITING |
| EDITING | E | NOT BUILDING (edit confirmed) |
| EDITING | X | NOT BUILDING (building removed) |
| EDITING | B | NOT BUILDING (edit cancelled) |

---

## 21. Build Algorithm Deep Dive

### How Foundation Snapping Works

**Scenario 1: Aiming at raft's top surface (normal = UP)**

```
Camera looking forward at raft top
    ↓
hit_normal = (0, 1, 0) → h_normal = (0, 0, 0) → length < 0.3
    ↓
Use camera forward direction: cam_dir = normalize(camera_forward projected to XZ)
    ↓
extend_dir = cam_dir (e.g., (0, 0, 1) = looking north)
    ↓
Apply rotation: rotated_dir = extend_dir.rotated(UP, build_rotation)
    ↓
placement = raft_center + rotated_dir × 2.0
    ↓
Result: New foundation center is 2.0m from raft center in the looked direction
```

**Scenario 2: Aiming at raft's side edge (normal = horizontal)**

```
Camera aimed at the side face of the raft
	↓
hit_normal = (0, 0, 1) → h_normal = (0, 0, 1) → length > 0.3
	↓
extend_dir = (0, 0, 1)  (use the hit normal directly)
	↓
placement = raft_center + (0, 0, 1) × 2.0
	↓
Foundation edge aligns with raft edge at z = -2 (for raft at z = -3)
```

**Scenario 3: Aiming at wall top (ceiling/upper floor)**

```
Wall has Socket_Top
	↓
normal.y > 0.3 → aiming at wall top
	↓
placement = Socket_Top.position + (0, 0.15, 0)
	↓
Foundation placed on top of wall as an upper floor
```

### How Collision Validation Works

```
1. Create BoxShape3D matching the building type:
   Foundation: (2, 0.3, 2)
   Wall: (2, 2.5, 0.2)
   Door: (1.2, 2.2, 0.15)
   Window: (1.2, 1.0, 0.15)

2. Transform = rotation × position

3. Collision mask = 1 (structures only)

4. Exclude: ghost itself, player, all "build_surface" group members
   (prevents detecting the raft or existing buildings as overlaps)

5. intersect_shape() → if empty = no overlap
```

### How Support Validation Works

```
Foundation:
  For each structure in "build_surface" group:
	Calculate XZ distance between proposed position and structure center
	If distance is between 1.5 and 2.5 (edge-to-edge = 2.0):
	  → SUPPORTED (edges touch)
	If distance is between 1.5 and 3.0:
	  → SUPPORTED (diagonal neighbor)
  → NOT SUPPORTED

Wall:
  For each structure in "build_surface":
	If |dx| < 1.2 and |dz| < 1.2:
	  → SUPPORTED (wall is directly above this structure)
  → NOT SUPPORTED

Door:
  For each structure:
	If name starts with "Wall" and distance < 2.0:
	  → SUPPORTED
  → NOT SUPPORTED
```

---

## 22. Rope Algorithm Deep Dive

### Throw Direction Capture

```
Q pressed → _throw_hook():
	aim_point = camera raycast result (world position)
	hand = HookOrigin.global_position (player's hand)
    direction = normalize(aim_point - hand)
    
    _throw_direction = direction     ← STORED ONCE, NEVER CHANGED
    _throw_start = hand
    _hook_world_pos = hand
```

### Hook Flight (THROWING state)

```
Every physics tick:
    step = throw_speed × delta (= 22 × 0.0083 ≈ 0.183m per tick at 120Hz)
    new_dist = _hook_travelled + step
    
    if new_dist >= max_hook_distance (22m):
        _hook_world_pos = _throw_start + _throw_direction × 22
        _snap_hook_to_water()    # if hook is in sky, bring to water level
        _check_debris()          # check if any debris is within 1.5m
        → EXTENDED or HOOKED
    else:
        _hook_world_pos = _throw_start + _throw_direction × new_dist
        _check_debris()          # can catch debris mid-flight
        → THROWING (continue) or HOOKED
```

### Reel Physics (REELING state)

```
Every physics tick:
    hand = _hand_pos()                       # current player hand position
    to_hand = hand - _hook_world_pos         # vector from hook to hand
    dist = length(to_hand)
    
    if dist ≤ collection_radius (1.5m):
        _collect_debris()                    # Inventory.add()
        _start_return()
        return
    
    dir = normalize(to_hand)
    _hook_world_pos += dir × reel_speed × delta  (= 12 × 0.0083 ≈ 0.1m/tick)
    
    # Debris follows hook
    if _hooked_debris:
        _hooked_debris.global_position = _hook_world_pos + (0, 0.3, 0)
        _hooked_debris.linear_velocity = ZERO
```

### Rope Visual Update

```
from = _hand_pos()          # follows player (updates every frame)
to = _hook_world_pos        # locked in world after throw
rope_len = distance(from, to)

midpoint = (from + to) / 2
rope_direction = normalize(to - from)

# Build rotation basis:
#   Y axis = rope direction (CylinderMesh extends along Y)
#   X axis = perpendicular to rope
#   Z axis = perpendicular to both

Basis(right, rope_dir, perp)

# Stretch cylinder to match distance
cylinder.height = rope_len
```

### Why the Rope Doesn't Follow the Camera

```
Frame 1: Player looks east, throws hook
	_throw_direction = (1, 0, 0)     ← LOCKED
	_hook_world_pos = hand + (1,0,0) × distance

Frame 100: Player now looks north
	_throw_direction is STILL (1, 0, 0)    ← NOT RECALCULATED
	_hook_world_pos is STILL in the east
	
	from = _hand_pos()           ← moved because player turned
	to = _hook_world_pos         ← stayed in world
	
	Rope draws a line from current hand to fixed hook
	The rope naturally reorients because the hand moved
	But the hook NEVER moved
```

---

## 23. How to Extend

### Add a New Building Type

1. Create a `.tscn` scene:
   ```
   StaticBody3D (root)
   ├── CollisionShape3D
   ├── MeshInstance3D
   └── BuildSockets (Node3D)
	   └── Socket_xxx (Marker3D)
   ```

2. Add to `player.gd`:
   ```gdscript
   const BUILD_RECIPE_NAMES := [..., "NewType"]
   const BUILD_SCENES := [..., "res://new_type.tscn"]
   ```

3. Add recipe to `inventory.gd`:
   ```gdscript
   const RECIPES := { ..., "NewType": {"Wood": 10} }
   ```

4. Add support check in `_check_support()` and socket logic in `_find_nearest_valid_socket()`.

### Add a New Resource Type

1. Add to `inventory.gd`:
   ```gdscript
   var items := { ..., "Gold": 0 }
   ```

2. Add to `ITEM_PROFILES` in `debris.gd`:
   ```gdscript
   "Gold": {"mass": 3.0, "freeboard": 0.15, "color": Color(1.0, 0.85, 0.0)}
   ```

3. Add to `ITEM_POOL` in `debris_spawner.gd`.

### Change Ocean Waves

Modify `ocean.gd` `get_height()`:
- Change `wave_height` export (default 0.4)
- Add/remove sine terms for different wave patterns
- Change frequencies (0.4, 0.3, 0.7) for different wave spacing

### Tune Hook System

All values are `@export` in `rope_system.gd`:
- `max_hook_distance`: How far the hook can go (default 22m)
- `throw_speed`: How fast it flies (default 22 m/s)
- `reel_speed`: How fast it comes back (default 12 m/s)
- `debris_hook_radius`: Catch radius (default 1.5m)
- `collection_radius`: Pickup distance (default 1.5m)

---

*End of documentation.*
# Recent Bug Fixes (Sep 2026) 
