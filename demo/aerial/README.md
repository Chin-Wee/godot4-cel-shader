# Aerial rendering study — DELIVERY MUST COMPLETE

A working comparison scene for the rendering goal. This is an ongoing visual
iteration, **not a claim that reference fidelity has been achieved**. The existing
factory/mech scene remains the default project scene.

## Run and controls

Open `aerial_demo.tscn` and press F6, or run from the repository root:

```sh
godot --path demo res://aerial/aerial_demo.tscn
```

- **1 / 2:** sunset / daylight palette.
- **3:** storm lighting and camera rain when inside cloud.
- **4:** change cloud cover; hidden banks stop contributing visibility/weather.
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
- Clouds use 18 continuous bank meshes in one MultiMesh. A native SphereMesh is
  deformed at low frequency and has a compressed base, eliminating the internal
  intersection rings from the original overlapping spheres. Rotated bank transforms
  also define visibility/weather regions. Density inverts the same deformation,
  preventing fog below flattened bases. Coverage affects both drawing and density.
  Native environment fog reduces visibility on entry; storm entry adds camera rain.
  These remain geometric approximations, not a claim about DMC's cloud technique.
- Trails store a fixed 512-instance history per emitter. Samples stay in world
  space, expand and fade with age, expire in the shader, and restart on teleport.
  Hero wing trails, a looping distant aircraft trail, and denser missile smoke
  have separate lifetimes and GPU wind/curl drift. Initial histories replay the same deterministic paths
  used by the animated objects; live movement continues sampling those paths.
- One mesh VFX shader supplies age, color ramp, HDR emission, Fresnel, graphic fire
  masses, dither dissolve and optional depth intersection fading. Explosions combine
  eight fire lobes, twelve smoke lobes, a ring, three arcs, twelve streaks and four
  debris shards. Transient effects are freed without retaining palette references.

Reusable shader sources live in `src/aerial`; the identical runtime copies are
in `demo/shaders/aerial`, following the repository's existing shader distribution.
The shared cel include and original material settings are preserved. The aircraft
proxy now lofts a faceted fuselage, closes each convex wing/fin with its own face
orientation center, and combines parts through native SurfaceTool batching. Dark
canopy/intake/nozzle surfaces retain a separate response. Static and live poses use
the same function, so the frozen captures represent the running scene.

A native CanvasLayer post pass runs after the 3D frame, below the HUD. It provides
resolved-frame highlight glow, an analytic solar corona, eight-tap screen-space
radial light scattering, and procedural normal-based rain refraction. Crysis is the
lightshaft visual reference; this is standard screen sampling, not a claim about
its exact source implementation. Rain uses jittered stretched drop fields and is
coupled to storm-cloud density. Sky, surface haze, fog, sunlight and live VFX all
follow palette/storm changes. The post pass is not HDR bloom or true volumetric
light transport; its approximation is an explicit remaining quality limit.

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
godot --path demo --script res://aerial/tests/capture_aerial.gd --resolution 1440x810 --always-on-top -- /tmp/godot-dmc-captures
```

The functional check covers opposing aircraft-part normals, static/live pose
agreement, cloud coverage and entry/exit, storm rain activation, fixed world-space
history, bounded trail allocation, teleport handling, palette changes and effect
expiry. A watchdog makes assertion failures terminate instead of hanging the check.

GPU captures include post on/off, sunset/daylight, aircraft above/below, explosion,
cloud entry, and wet/dry geometry. Pixel comparisons reject an inactive post or
rain pass. The rain preview deliberately forces rain over visible geometry for
inspection; normal play enables it only in storm cloud. Per-capture draw/primitive
counters are saved with frame names so unlike camera views are not conflated.
These are desktop observations, not a device benchmark. Keep the capture window
visible on macOS; a missing rendered frame fails through a watchdog. Headless mode
is rejected immediately for visual capture. Shader validation requires rendered
frames, not the headless functional check alone.

## Visual review and remaining goal

The first render revealed incorrect winding on custom geometry. Correcting it
restored terrain tops and aircraft panels. Further captures drove these changes:

1. Replace rounded hills with broad mesa caps and narrow canyon floors.
2. Reduce nearby haze and use cool shadow fill to separate foreground from distance.
3. Lift aircraft shadow planes without adding black outlines.
4. Increase trail puff overlap to give persistent paths actual volume.
5. Supply HDR directly through the unshaded VFX output; emission alone did not
   produce the required bright core. Separate front fire from rear smoke.

The next pass also replaced uniform mesa edges with a warped/jittered heightfield,
smooth terrain normals and a river, lifted upward aircraft panels separately from
cool underside fill, added a wider canopy frame/engine housings, narrowed the broad
additive sun lobe that was over-warming the entire sky, and scaled the explosion
for a stronger fire/smoke hierarchy. Lower fire gain preserves orange secondary
masses, while lobe breakup is restricted to fire meshes so the energy arcs stay solid.

Compared directly with the supplied references, these remain incomplete:

| Area | Current evidence | Remaining visual work |
|---|---|---|
| Aircraft | Closed convex parts, opposing normals, canopy/housing, panel fill and rim render from above/below | Proxy silhouette and livery still need closer matching |
| Environment | Warped mesa field, smooth normals, river and aerial depth render in both presets | More natural mesa distribution and finer value grouping still needed |
| Trails/exhaust | Persistent trajectory curves, dense smoke, wind drift and mesh flames render | Segmentation rhythm and near-camera shapes need refinement |
| Clouds | Continuous bank geometry, rotated density regions and coverage controls work | Bank variety, silhouette and internal lighting still need refinement |
| Explosions | Enlarged fire/smoke masses, arcs, rings, debris and post glow animate and expire | Need closer authored fire/smoke breakup and shot hierarchy |
| Weather/post | Storm palette, density-driven rain/refraction, cover, corona, glow and screen rays render | Glow/shafts are resolved-frame approximations; finer weather transitions remain |

The overall rendering goal stays active. Passing the functional checks does not
prove that the frame matches the references, and no visual similarity percentage
is claimed.
