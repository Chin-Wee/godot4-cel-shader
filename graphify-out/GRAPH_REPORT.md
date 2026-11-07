# Graph Report - godot4-cel-shader  (2026-11-07)

## Corpus Check
- 31 files · ~2,125,165 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 1071 file(s) not represented in the graph (top: .glb 162, .obj 157, .fbx 156)

## Summary
- 525 nodes · 585 edges · 37 communities (30 shown, 7 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 2 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3ab72622`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Flight pose design
- PhantomCamera3D
- PhantomCamera2D
- TransitionType
- TweenDirectorResource
- PhantomCamera
- Camera3DResource
- PhantomCameraHost
- FollowLockAxis3D
- 4. Architectural Options for This Project (Godot 4.7)
- PhantomCameraNoise3D
- PhantomCameraManager
- PhantomCameraNoiseEmitter2D
- PhantomCameraNoiseEmitter3D
- Grass direction: Breath of the Wild
- FollowMode2D
- PhantomCamera3DExtensions
- Node2D
- Node3D
- StringName
- .GetLimit
- StringName
- .EmitNoise
- .EmitNoise
- Q: implement the phantom camera in the aerial demo scene. everything moves quite fast, so make sure we dont get jittery stuff.
- MechAsset
- Balanced aerial thrust and directional braking
- Q: Why do A/D and Q/E keep their axes between space and plane flight?
- SOLID refactor
- Q: refactor the codebase based on solid design principles.
- check_godot.py
- Q: Where are Armored Core hover tap burst control timings and force handling defined?
- Q: How does flight enforce physical hot/cold nozzle forces and finite activation/restart timing?
- Ground Combat Direction: Gundam Hathaway Grunt MS Study
- Q: How are aerial per-booster thrust caps and redundant opposing burns handled?
- Q: How does aerial cold-jet thrust scale with speed from rest to 40 mps?

## God Nodes (most connected - your core abstractions)
1. `PhantomCamera3D` - 70 edges
2. `PhantomCamera2D` - 54 edges
3. `PhantomCamera` - 29 edges
4. `PhantomCameraNoise3D` - 19 edges
5. `PhantomCameraNoiseEmitter2D` - 17 edges
6. `PhantomCameraNoiseEmitter3D` - 17 edges
7. `Camera3DResource` - 17 edges
8. `PhantomCameraNoise2D` - 16 edges
9. `PhantomCameraHost` - 15 edges
10. `TweenDirectorResource` - 15 edges

## Surprising Connections (you probably didn't know these)
- `PhantomCamera2D` --inherits--> `PhantomCamera`  [EXTRACTED]
  demo/addons/phantom_camera/scripts/phantom_camera/PhantomCamera2D.cs → demo/addons/phantom_camera/scripts/phantom_camera/PhantomCamera.cs
- `PhantomCamera3D` --inherits--> `PhantomCamera`  [EXTRACTED]
  demo/addons/phantom_camera/scripts/phantom_camera/PhantomCamera3D.cs → demo/addons/phantom_camera/scripts/phantom_camera/PhantomCamera.cs
- `PhantomCamera` --references--> `EaseType`  [EXTRACTED]
  demo/addons/phantom_camera/scripts/phantom_camera/PhantomCamera.cs → demo/addons/phantom_camera/scripts/resources/PhantomCameraTween.cs
- `PhantomCamera` --references--> `PhantomCameraTween`  [EXTRACTED]
  demo/addons/phantom_camera/scripts/phantom_camera/PhantomCamera.cs → demo/addons/phantom_camera/scripts/resources/PhantomCameraTween.cs
- `PhantomCamera` --references--> `TransitionType`  [EXTRACTED]
  demo/addons/phantom_camera/scripts/phantom_camera/PhantomCamera.cs → demo/addons/phantom_camera/scripts/resources/PhantomCameraTween.cs

## Import Cycles
- None detected.

## Communities (37 total, 7 thin omitted)

### Community 0 - "Flight pose design"
Cohesion: 0.06
Nodes (32): Dynamic rotation requirements, Mech flight animation contract, Recommended architecture, Required behaviors, Research body-flight requirements, Visual acceptance, Banks, rolls and somersaults, Flight pose design (+24 more)

### Community 1 - "PhantomCamera3D"
Cohesion: 0.04
Nodes (45): CameraAttributes, Vector2, PhantomCamera3D, Attributes, AutoFollowDistance, AutoFollowDistanceDivisor, AutoFollowDistanceMax, AutoFollowDistanceMin (+37 more)

### Community 2 - "PhantomCamera2D"
Cohesion: 0.05
Nodes (37): NodePath, Vector2, PhantomCamera2D, AutoZoom, AutoZoomMargin, AutoZoomMax, AutoZoomMin, DrawLimits (+29 more)

### Community 3 - "TransitionType"
Cohesion: 0.07
Nodes (26): GDScript, StringName, EaseType, EaseIn, EaseInOut, EaseOut, EaseOutIn, PhantomCameraTween (+18 more)

### Community 4 - "TweenDirectorResource"
Cohesion: 0.08
Nodes (25): PhantomCamera.TweenDirector, GodotObject, Node, StringName, MethodName, PhantomCameraTweenDirector, TweenDirector, GDScript (+17 more)

### Community 5 - "PhantomCamera"
Cohesion: 0.08
Nodes (24): GodotObject, StringName, InactiveUpdateMode, Always, Never, MethodName, PhantomCamera, DeadZoneHeight (+16 more)

### Community 6 - "Camera3DResource"
Cohesion: 0.08
Nodes (23): KeepAspect, GDScript, StringName, Vector2, Camera3DResource, CullMask, Far, Fov (+15 more)

### Community 7 - "PhantomCameraHost"
Cohesion: 0.10
Nodes (19): Callable, PhantomCamera, StringName, InterpolationMode, Auto, Idle, Manual, Physics (+11 more)

### Community 8 - "FollowLockAxis3D"
Cohesion: 0.09
Nodes (22): FollowLockAxis3D, None, X, XY, XYZ, XZ, Y, YZ (+14 more)

### Community 9 - "4. Architectural Options for This Project (Godot 4.7)"
Cohesion: 0.10
Nodes (21): 4.1 Ground Locomotion & Physics Authority, 4.2 Skeletal Animation & Mechanical Weight, 4.3 Combat Loop, Lethality, and Subsystem Damage, 4.4 Camera, Scale Framing, and Readability, 4.5 Cel Lighting, Atmosphere, and Systemic "Scale Ruler" VFX, 4. Architectural Options for This Project (Godot 4.7), Option 4.1A — Unified Force-Driven `RigidBody3D` ("Grounded Extension of `aerial_mech.gd`"), Option 4.1B — Dual-Mode Kinematic/Dynamic Hybrid (`CharacterBody3D` Ground $\leftrightarrow$ `RigidBody3D` Ballistic/Crash) (+13 more)

### Community 10 - "PhantomCameraNoise3D"
Cohesion: 0.11
Nodes (17): GDScript, Resource, StringName, MethodName, PhantomCameraNoise3D, Amplitude, Frequency, NoiseSeed (+9 more)

### Community 11 - "PhantomCameraManager"
Cohesion: 0.15
Nodes (12): PhantomCamera.Manager, GodotObject, PhantomCamera2D, PhantomCamera3D, PhantomCameraHost, StringName, MethodName, PhantomCameraManager (+4 more)

### Community 12 - "PhantomCameraNoiseEmitter2D"
Cohesion: 0.06
Nodes (25): GodotObject, Node2D, StringName, MethodName, PhantomCameraNoiseEmitter2D, Continuous, DecayTime, Duration (+17 more)

### Community 13 - "PhantomCameraNoiseEmitter3D"
Cohesion: 0.12
Nodes (11): GodotObject, Node3D, StringName, MethodName, PhantomCameraNoiseEmitter3D, Continuous, DecayTime, Duration (+3 more)

### Community 14 - "Grass direction: Breath of the Wild"
Cohesion: 0.29
Nodes (6): Grass direction: Breath of the Wild, Local checks, Recommended implementation order, Scope and evidence, Sources and what each supports, Why this scene looks like panels

### Community 15 - "FollowMode2D"
Cohesion: 0.07
Nodes (19): CollisionShape2D, PhantomCamera.Noise, GodotObject, FollowLockAxis2D, None, X, Xy, Y (+11 more)

### Community 16 - "PhantomCamera3DExtensions"
Cohesion: 0.25
Nodes (4): Camera3DResource, PhantomCamera3DExtensions, Quaternion, Vector3

### Community 19 - "StringName"
Cohesion: 0.67
Nodes (3): StringName, MethodName, PropertyName

### Community 21 - "StringName"
Cohesion: 0.67
Nodes (3): StringName, MethodName, SignalName

### Community 24 - "Q: implement the phantom camera in the aerial demo scene. everything moves quite fast, so make sure we dont get jittery stuff."
Cohesion: 0.40
Nodes (4): Answer, Outcome, Q: implement the phantom camera in the aerial demo scene. everything moves quite fast, so make sure we dont get jittery stuff., Source Nodes

### Community 26 - "MechAsset"
Cohesion: 0.50
Nodes (3): Controls and animations, MechAsset, Validation

### Community 27 - "Balanced aerial thrust and directional braking"
Cohesion: 0.20
Nodes (9): Answer, Balanced aerial thrust and directional braking, Directional braking, Force allocation, Fuel and hardware, Outcome, Q: How does aerial flight balance directional burst forces and minimize cold-gas use?, Source Nodes (+1 more)

### Community 28 - "Q: Why do A/D and Q/E keep their axes between space and plane flight?"
Cohesion: 0.40
Nodes (4): Answer, Outcome, Q: Why do A/D and Q/E keep their axes between space and plane flight?, Source Nodes

### Community 29 - "SOLID refactor"
Cohesion: 0.33
Nodes (5): Baseline, Progress, SOLID refactor, Verification, Work and completion evidence

### Community 30 - "Q: refactor the codebase based on solid design principles."
Cohesion: 0.40
Nodes (4): Answer, Outcome, Q: refactor the codebase based on solid design principles., Source Nodes

### Community 32 - "Q: Where are Armored Core hover tap burst control timings and force handling defined?"
Cohesion: 0.40
Nodes (4): Answer, Outcome, Q: Where are Armored Core hover tap burst control timings and force handling defined?, Source Nodes

### Community 33 - "Q: How does flight enforce physical hot/cold nozzle forces and finite activation/restart timing?"
Cohesion: 0.40
Nodes (4): Answer, Outcome, Q: How does flight enforce physical hot/cold nozzle forces and finite activation/restart timing?, Source Nodes

### Community 34 - "Ground Combat Direction: Gundam Hathaway Grunt MS Study"
Cohesion: 0.13
Nodes (14): 1. Scope, Target Reference, and Evidence Standard, 2. Anatomy of the Hathaway Target Scenes, 3.1 Sunrise (Bandai Namco Filmworks Studio 1 / D.I.D., Sublimation & YAMATOWORKS) — *Gundam Hathaway*, 3.2 Industrial Light & Magic (ILM) — *Pacific Rim*, 3.3 Respawn Entertainment — *Titanfall* & *Titanfall 2*, 3.4 Sucker Punch Productions — *Ghost of Tsushima*, 3. Underlying Techniques of the Four Reference Productions, 5. Recommended Option Stack & Phased Path (+6 more)

### Community 35 - "Q: How are aerial per-booster thrust caps and redundant opposing burns handled?"
Cohesion: 0.40
Nodes (4): Answer, Outcome, Q: How are aerial per-booster thrust caps and redundant opposing burns handled?, Source Nodes

### Community 36 - "Q: How does aerial cold-jet thrust scale with speed from rest to 40 mps?"
Cohesion: 0.40
Nodes (4): Answer, Outcome, Q: How does aerial cold-jet thrust scale with speed from rest to 40 mps?, Source Nodes

## Knowledge Gaps
- **299 isolated node(s):** `PhantomCamera.Manager`, `Instance`, `PhantomCamera2Ds`, `PhantomCamera3Ds`, `PhantomCameraHosts` (+294 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 370 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PhantomCamera3D` connect `PhantomCamera3D` to `PhantomCamera`, `Camera3DResource`, `PhantomCameraHost`, `FollowLockAxis3D`, `PhantomCameraNoise3D`, `PhantomCamera3DExtensions`, `Node3D`, `StringName`, `.EmitNoise`?**
  _High betweenness centrality (0.228) - this node is a cross-community bridge._
- **Why does `PhantomCamera2D` connect `PhantomCamera2D` to `PhantomCamera`, `PhantomCameraHost`, `PhantomCameraNoiseEmitter2D`, `FollowMode2D`, `Node2D`, `StringName`, `.GetLimit`, `.EmitNoise`?**
  _High betweenness centrality (0.177) - this node is a cross-community bridge._
- **Why does `PhantomCamera` connect `PhantomCamera` to `PhantomCamera3D`, `PhantomCamera2D`, `TransitionType`, `PhantomCameraHost`?**
  _High betweenness centrality (0.148) - this node is a cross-community bridge._
- **What connects `PhantomCamera.Manager`, `Instance`, `PhantomCamera2Ds` to the rest of the system?**
  _299 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Flight pose design` be split into smaller, more focused modules?**
  _Cohesion score 0.05714285714285714 - nodes in this community are weakly interconnected._
- **Should `PhantomCamera3D` be split into smaller, more focused modules?**
  _Cohesion score 0.043478260869565216 - nodes in this community are weakly interconnected._
- **Should `PhantomCamera2D` be split into smaller, more focused modules?**
  _Cohesion score 0.05405405405405406 - nodes in this community are weakly interconnected._