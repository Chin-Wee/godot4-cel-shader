---
type: "query"
date: "2026-11-02T07:34:00.591885+00:00"
question: "implement the phantom camera in the aerial demo scene. everything moves quite fast, so make sure we dont get jittery stuff."
contributor: "graphify"
outcome: "useful"
source_nodes: ["PhantomCamera3D", "PhantomCameraHost"]
---

# Q: implement the phantom camera in the aerial demo scene. everything moves quite fast, so make sure we dont get jittery stuff.

## Answer

Expanded from graph vocabulary: aerial camera phantom flight physics interpolation. Source review found the physics-driven RigidBody3D was followed from raw positions on render frames. The aerial scene now enables native interpolation for its mechs, reads get_global_transform_interpolated into a render-clock target, and uses PhantomCamera3D SIMPLE follow/damping and look-at through a manual PhantomCameraHost before weather/post updates. Armored Core VI is the independent orbit/target-focus behavior reference. Native plugin damping replaces the two custom camera springs. Mouse/zoom events defer to the render update during live flight; zero-delta resets bypass addon damping, and reset_flight clears interpolation history. Validated 30/144/240 FPS sub-tick follow, focus, orbit, zoom, pause, teleport, fixed capture views, aerial stack and native body-flight replays. Native rendering inspected. GDScript source is authoritative; the installed Graphify AST does not index .gd files.

## Outcome

- Signal: useful

## Source Nodes

- PhantomCamera3D
- PhantomCameraHost