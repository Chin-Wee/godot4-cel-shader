# SOLID refactor

Scope: all first-party code in this repository (`src/`, `demo/aerial/`,
`demo/actors/`, and `demo/scripts/`). Bundled addons and imported assets retain
their upstream ownership. `demo` intentionally carries self-contained copies of
the distributable shaders; copy parity is part of validation.

Keep existing game behavior, controls, physical units, serialized scene/resource
contracts, shader interfaces, and fixed/render clock ownership. Use the existing
Godot composition pattern (`flight_pose` already delegates to arm/contact
components); introduce no general-purpose service framework or empty interfaces.

## Work and completion evidence

- [x] Separate aerial scene composition from camera, lighting/weather/material
  ownership, and HUD presentation. Migrate callers to the component that owns the
  operation instead of retaining duplicate state or forwarding every old field.
  Verify camera timing at 30/144/240 FPS, surface palettes, effect lifetime,
  paused controls, walk mode, and native visual output.
- [x] Separate imported mech asset preparation from movement/animation playback;
  review the shared controller and roster for substitutability and narrow input
  ownership. Verify imported resources remain unchanged, locomotion, jump timing,
  actor switching, and aerial model reuse.
- [x] Review flight input, dynamics, actuator allocation, and procedural pose
  dependencies end to end. Separate responsibilities where actual coupling
  requires it while retaining the DCS/Elite Dangerous flight references and
  Titanfall/Overgrowth pose references. Verify native flight, thruster, handling,
  maneuver, acrobatics, research-bodyflight, and animation-contract checks.
- [x] Review the remaining geometry, cloud field/banks, VFX, terrain/grass,
  compositor, shader, and authoring code. Record concrete fixes or why an existing
  cohesive owner should remain; verify corresponding headless/native checks and
  distributable/demo shader parity.
- [ ] Audit the complete refactor against these boundaries and checks; integrate
  through `main`, run integration validation, and update the canonical Graphify
  graph. The installed Graphify parser currently does not index GDScript; source
  review and runnable behavior checks remain authoritative.

## Baseline

- Starting integration revision: `26ccd75`.
- The old `capture_aerial.gd` inspected the initially empty hero trail and probed
  an outer flare ghost that can be offscreen. Its fixture now inspects the seeded
  missile trail and the shader's visible inner ghost. The complete native capture
  passes, including exhaust, effects, glow, occlusion, cloud entry and rain.
- Preserve unrelated untracked Godot `.uid` files and existing worktrees.

## Progress

The aerial scene now composes native Camera3D/Node3D/CanvasLayer children. Camera,
lighting/material/weather state and HUD presentation each have one owner.
`mech_assets.gd` prepares imported resources without controlling a body;
`flight_input.gd` adapts platform input while the solver consumes commands.
Five cel shader wrappers share one implementation with explicit feature defines.

| Reviewed area | Ownership decision and evidence |
| --- | --- |
| Shared controls and mech roster | Retain the small movement/input base and roster. Inactive actors continue simulating with input disabled; four-model locomotion/jump calibration and switching checks pass. |
| Native body, dynamics and actuators | Retain one force-application pipeline and one native motion authority. Move only OS input out. All flight, handling, thruster, body-flight and acrobatics checks pass. |
| Pose, arm, contact, profile and servo | Retain existing composition: read-only motion snapshot, profile Resource, native modifier/two-bone IK order, and bounded servos. Pose/contact tests and native authoring preview pass. |
| Cloud field and banks | Retain the shared sampled density field for mesh, CPU weather and GPU shadows. Field/connectivity/packing and coverage checks pass. |
| Geometry, trails and explosions | Retain pure mesh helpers and bounded effect owners. Transient explosion materials no longer enter persistent palette storage. Geometry, fixed-distance trails, VFX lifetime/transport and palette checks pass. |
| Atmosphere and outline compositors | Retain effect-local GPU ownership and uniform-set caching; atmosphere retains render-thread retirement. Native lighting validation covers source occlusion, MSAA, resize, cloud invalidation and scene reload; post source/runtime copies match. |
| Grass and factory material application | Retain the native MultiMesh/material adapters. Grass material isolation, moving target, actor switching and target deletion checks pass. |
| Cel shaders | Replace five duplicated implementations with shared includes. Preserve runtime painting and template height mapping. Six native variants match baseline pixels exactly; shared-copy checks pass. |
| Pose studio and baker | Retain authoring-only AnimationPlayer data and real completed-rig sampling. Imported animation resources remain unchanged; native preview verifies five clip families and skeleton deformation. No baked asset is rewritten. |

## Verification

- `python3 tools/check_godot.py`: 24 headless runs, including 30/144/240 FPS
  camera checks, plus shared/distributable copy checks. The runner rejects script
  errors even when Godot returns zero.
- Native `capture_shader_variants.gd`: all six configurations render successfully;
  the before/after images contain identical pixel data.
- Native `capture_lighting.gd`: isolated layers, black/white source occlusion,
  veiling glare, MSAA, resizing, stable allocations, cloud invalidation and reload.
- Native `capture_aerial.gd`: the complete image/capture assertions now pass after
  correcting the stale trail and flare probes; no production effect is weakened.
- Acrobatics and research-bodyflight replays pass in both review/chase cameras.
- Native sunset/day references differ by only 6/9 color bytes per full frame;
  normalized mean byte differences are below 0.0000002.
- Native pose preview loads hover, belly/back, head-scan and extended-layout clips
  and verifies actual shoulder deformation.

Integration validation and the canonical graph update remain pending.
