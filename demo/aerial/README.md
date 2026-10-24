# Aerial rendering study — DELIVERY MUST COMPLETE

A working comparison scene for the rendering goal. This is an initial integrated
iteration, **not a claim that reference fidelity has been achieved**. The existing
factory/mech scene remains the default project scene.

## Run and controls

Open `aerial_demo.tscn` and press F6, or run from the repository root:

```sh
godot --path demo res://aerial/aerial_demo.tscn
```

- **1 / 2:** sunset / daylight palette.
- **3:** storm cloud shading.
- **Space:** trigger a graphic explosion.
- **P:** freeze aircraft, trails, cloud drift and effects for comparison.
- **Right click:** toggle the fly camera. WASD moves, Q/E descends/ascends, Shift moves faster.
- **Escape:** release the mouse.

The camera follows the hero's translation until free flight is enabled. Fly into
a cloud bank to see visibility drop. This scene demonstrates rendering rather
than combat, aircraft physics, collision or a mission system.

## Implementation and reference

The production visual reference is **DELIVERY MUST COMPLETE**, using the supplied
three images and comparison brief. Its unpublished aircraft/cloud implementation
is not assumed to be known. The stretched unsubdivided icosphere exhaust follows
the developer disclosure quoted in that brief; the other effects are visual
reconstructions using Godot's existing mesh, MultiMesh, camera and fog facilities.

- Aircraft shaders reuse the existing diffuse ramp, Bayer perturbation, stylized
  specular and Fresnel functions. Body orientation colors, a colored shadow floor,
  a bright rim and a separate canopy highlight material specialize those primitives.
- Terrain owns world-height/slope coloring and broad strata. Aircraft, terrain,
  clouds and mesh VFX share distance haze and palette controls. Sky/sun now belong
  to the aerial stack instead of relying on the old third-party sky material.
- Clouds use 540 low-detail lobes in one MultiMesh, with ellipsoidal visibility
  regions and native environment fog on camera entry. They are actual scene
  geometry with depth, not skybox clouds. The storm toggle currently changes
  cloud shading only; rain and a complete weather simulation remain open work.
- Trails store a fixed 512-instance history per emitter. Samples stay in world
  space, expand and fade with age, expire in the shader, and restart on teleport.
  Hero wing trails, a looping distant aircraft trail, and denser missile smoke
  have separate lifetimes. Initial histories replay the same deterministic paths
  used by the animated objects; live movement continues sampling those paths.
- One mesh VFX shader supplies age, color ramp, HDR emission, Fresnel, graphic fire
  masses, dither dissolve and optional depth intersection fading. Explosions combine
  eight fire lobes, twelve smoke lobes, a ring, three arcs, twelve streaks and four
  debris shards. Transient effects are freed without retaining palette references.

Reusable shader sources live in `src/aerial`; the identical runtime copies are
in `demo/shaders/aerial`, following the repository's existing shader distribution.
The shared cel include and original material settings are preserved.

## Asset selection

No aircraft, missile, contrail, explosion or 3D cloud asset was present in the
workspace search. Existing `terrain-1`, `terrain-2` and `terrain-3` mesh/material
metadata were inspected: they are the small grass/stone ground assets used by
the mech demo. None supplies the broad aerial canyon shapes in the reference.
The new scene therefore uses deterministic low-poly aircraft proxies, procedural
mesa geometry and native primitives. No third-party assets or dependencies were
added. Proxy geometry is an outstanding limitation of silhouette fidelity.

## Checks and comparison captures

```sh
godot --headless --path demo --script res://aerial/tests/test_aerial_stack.gd
godot --path demo --script res://aerial/tests/capture_aerial.gd --resolution 1440x810 -- /tmp/godot-dmc-captures
```

The functional check covers cloud entry/exit, fixed world-space history, bounded
trail allocation, teleport handling, palette inheritance and explosion expiry.
The capture script saves sunset, daylight, explosion and inside-cloud PNGs plus
render counters. Those counters are desktop observations, not a device benchmark.
Shader validation requires the rendered captures, not the headless test alone.

## Visual review and remaining goal

The first render revealed incorrect winding on custom geometry. Correcting it
restored terrain tops and aircraft panels. Further captures drove these changes:

1. Replace rounded hills with broad mesa caps and narrow canyon floors.
2. Reduce nearby haze and use cool shadow fill to separate foreground from distance.
3. Lift aircraft shadow planes without adding black outlines.
4. Increase trail puff overlap to give persistent paths actual volume.
5. Supply HDR directly through the unshaded VFX output; emission alone did not
   produce the required bright core. Separate front fire from rear smoke.

Compared directly with the supplied references, these remain incomplete:

| Area | Current evidence | Remaining visual work |
|---|---|---|
| Aircraft | Separate canopy/body, rim and shadow floor render correctly | Proxy shape and panel placement are too simple; stronger readable lit panels needed |
| Environment | Broad mesas, shared palette and aerial depth appear in both presets | Cliff edges and strata remain too regular; composition needs more organic depth layers |
| Trails/exhaust | Persistent trajectory curves, dense smoke and mesh flames render | Puff rhythm and wind distortion need closer matching |
| Clouds | Layered geometry and entry fog work | Lobes still read as grouped spheres; cloud silhouette and lighting need substantial refinement |
| Explosions | Fire/smoke masses, arcs and rings animate and expire | Need better fire/smoke overlap, scale hierarchy and soft glow |
| Weather/post | Palette switch, cloud shadow change and entry fog work | Rain/refraction, cloud-cover variation, sun shafts and controlled bloom remain unimplemented |

The overall rendering goal stays active. Passing the functional checks does not
prove that the frame matches the references, and no visual similarity percentage
is claimed.
