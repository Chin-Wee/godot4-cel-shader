# Graph Report - godot4-cel-shader  (2026-10-26)

## Corpus Check
- 18 files · ~2,106,857 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 956 file(s) not represented in the graph (top: .glb 162, .obj 157, .fbx 156)

## Summary
- 415 nodes · 485 edges · 27 communities (21 shown, 6 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 2 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `bf78cf43`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Aerial rendering study — DELIVERY MUST COMPLETE
- PhantomCamera3D
- PhantomCamera2D
- TransitionType
- TweenDirectorResource
- PhantomCamera
- Camera3DResource
- PhantomCameraHost
- FollowLockAxis3D
- FollowMode2D
- PhantomCameraNoise3D
- PhantomCameraManager
- PhantomCameraNoiseEmitter2D
- PhantomCameraNoiseEmitter3D
- Grass direction: Breath of the Wild
- LimitTargetQueryResult
- PhantomCamera3DExtensions
- Node2D
- Node3D
- StringName
- .GetLimit
- StringName
- .EmitNoise
- .EmitNoise
- PhantomCameraNoise2D
- MechAsset

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

## Communities (27 total, 6 thin omitted)

### Community 0 - "Aerial rendering study — DELIVERY MUST COMPLETE"
Cohesion: 0.12
Nodes (14): Aerial rendering study — DELIVERY MUST COMPLETE, Asset selection, Checks and comparison captures, Implementation and reference, Run and controls, Visual review and remaining goal, Aerial rendering study, Base Materials (+6 more)

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
Nodes (24): Camera3DResource, KeepAspect, GDScript, StringName, Vector2, Camera3DResource, CullMask, Far (+16 more)

### Community 7 - "PhantomCameraHost"
Cohesion: 0.10
Nodes (19): Callable, PhantomCamera, StringName, InterpolationMode, Auto, Idle, Manual, Physics (+11 more)

### Community 8 - "FollowLockAxis3D"
Cohesion: 0.09
Nodes (22): FollowLockAxis3D, None, X, XY, XYZ, XZ, Y, YZ (+14 more)

### Community 9 - "FollowMode2D"
Cohesion: 0.11
Nodes (13): PhantomCamera.Noise, FollowLockAxis2D, None, X, Xy, Y, FollowMode2D, Framed (+5 more)

### Community 10 - "PhantomCameraNoise3D"
Cohesion: 0.11
Nodes (17): GDScript, Resource, StringName, MethodName, PhantomCameraNoise3D, Amplitude, Frequency, NoiseSeed (+9 more)

### Community 11 - "PhantomCameraManager"
Cohesion: 0.15
Nodes (12): PhantomCamera.Manager, GodotObject, PhantomCamera2D, PhantomCamera3D, PhantomCameraHost, StringName, MethodName, PhantomCameraManager (+4 more)

### Community 12 - "PhantomCameraNoiseEmitter2D"
Cohesion: 0.12
Nodes (11): GodotObject, Node2D, StringName, MethodName, PhantomCameraNoiseEmitter2D, Continuous, DecayTime, Duration (+3 more)

### Community 13 - "PhantomCameraNoiseEmitter3D"
Cohesion: 0.12
Nodes (11): GodotObject, Node3D, StringName, MethodName, PhantomCameraNoiseEmitter3D, Continuous, DecayTime, Duration (+3 more)

### Community 14 - "Grass direction: Breath of the Wild"
Cohesion: 0.29
Nodes (6): Grass direction: Breath of the Wild, Local checks, Recommended implementation order, Scope and evidence, Sources and what each supports, Why this scene looks like panels

### Community 15 - "LimitTargetQueryResult"
Cohesion: 0.22
Nodes (6): CollisionShape2D, GodotObject, LimitTargetQueryResult, IsCollisionShape2D, IsTileMapLayer, TileMapLayer

### Community 16 - "PhantomCamera3DExtensions"
Cohesion: 0.33
Nodes (3): PhantomCamera3DExtensions, Quaternion, Vector3

### Community 19 - "StringName"
Cohesion: 0.67
Nodes (3): StringName, MethodName, PropertyName

### Community 21 - "StringName"
Cohesion: 0.67
Nodes (3): StringName, MethodName, SignalName

### Community 24 - "PhantomCameraNoise2D"
Cohesion: 0.13
Nodes (14): GDScript, Resource, StringName, MethodName, PhantomCameraNoise2D, Amplitude, Frequency, NoiseSeed (+6 more)

### Community 26 - "MechAsset"
Cohesion: 0.50
Nodes (3): Controls and animations, MechAsset, Validation

## Knowledge Gaps
- **227 isolated node(s):** `PhantomCamera.Manager`, `Instance`, `PhantomCamera2Ds`, `PhantomCamera3Ds`, `PhantomCameraHosts` (+222 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 287 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PhantomCamera3D` connect `PhantomCamera3D` to `PhantomCamera`, `Camera3DResource`, `PhantomCameraHost`, `FollowLockAxis3D`, `PhantomCameraNoise3D`, `PhantomCamera3DExtensions`, `Node3D`, `StringName`, `.EmitNoise`?**
  _High betweenness centrality (0.365) - this node is a cross-community bridge._
- **Why does `PhantomCamera2D` connect `PhantomCamera2D` to `PhantomCamera`, `PhantomCameraHost`, `FollowMode2D`, `LimitTargetQueryResult`, `Node2D`, `StringName`, `.GetLimit`, `.EmitNoise`, `PhantomCameraNoise2D`?**
  _High betweenness centrality (0.284) - this node is a cross-community bridge._
- **Why does `PhantomCamera` connect `PhantomCamera` to `PhantomCamera3D`, `PhantomCamera2D`, `TransitionType`, `PhantomCameraHost`?**
  _High betweenness centrality (0.238) - this node is a cross-community bridge._
- **What connects `PhantomCamera.Manager`, `Instance`, `PhantomCamera2Ds` to the rest of the system?**
  _227 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Aerial rendering study — DELIVERY MUST COMPLETE` be split into smaller, more focused modules?**
  _Cohesion score 0.125 - nodes in this community are weakly interconnected._
- **Should `PhantomCamera3D` be split into smaller, more focused modules?**
  _Cohesion score 0.043478260869565216 - nodes in this community are weakly interconnected._
- **Should `PhantomCamera2D` be split into smaller, more focused modules?**
  _Cohesion score 0.05405405405405406 - nodes in this community are weakly interconnected._