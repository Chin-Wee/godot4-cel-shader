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
  Vertex RGB tints separate engine/fin/wing-root panels; vertex alpha carries an
  opaque livery mask for the gold or olive outer wings. It does not drive transparency.
- Terrain owns world-height/slope coloring and broad strata. Aircraft, terrain,
  clouds and mesh VFX share distance haze and palette controls. Sky/sun now belong
  to the aerial stack instead of relying on the old third-party sky material.
  The existing heightfield now separates level mesa caps, eroded cliff contours,
  lower benches and ribbed talus/outcrops. Warm exposed rock sits above blue valley
  shadows; a broad river apron preserves the open canyon composition.
- Clouds use 18 continuous banks across four native MultiMesh batches. Four native
  SphereMeshes follow different radial envelopes of broad cumulus lobes, with
  low-frequency crest breakup and compressed bases. The same envelopes define
  rotated visibility/weather regions, preventing fog below flattened bases.
  Coverage affects all batches and their density together. Sunward crowns receive
  broad warm transmission near the sun; shaded bases retain the stage palette.
  Transmission is an art-directed surface term, not a volumetric scattering solve.
  Native environment fog reduces visibility on entry; storm entry adds camera rain.
  These remain geometric approximations, not a claim about DMC's cloud technique.
- Trails store a fixed 512-instance history per emitter. Samples stay in world
  space, expand and fade with age, expire in the shader, and restart on teleport.
  Hero wing trails, a looping distant aircraft trail, and denser missile smoke
  have separate lifetimes and GPU wind/curl drift. Overlapping elongated puffs
  follow the trajectory tangent instead of forming evenly spaced round beads.
  Wind remains in world space through the oriented instance transforms. Initial
  wingtip histories replay the same aircraft poses used by live movement.
- One mesh VFX shader supplies age, color ramp, HDR emission, Fresnel, graphic fire
  masses, dither dissolve and optional depth intersection fading. Explosions combine
  eight fire lobes, twelve smoke lobes, a ring, three arcs, twelve streaks and four
  debris shards. Uneven lobe meshes, seeded orange/core islands and authored
  overlapping smoke offsets form an asymmetrical plume. Smoke lobes vary in aspect
  and vertex tint, and their value planes follow the shared sun direction.
  Tapered arcs have yellow cores and
  orange edges, grow with onset, and expire at 1.6 seconds; fire cools and expires
  at 2.4 seconds, while smoke/debris persist through the four-second effect.
  Transient effects are freed without retaining palette references.

Reusable shader sources live in `src/aerial`; the identical runtime copies are
in `demo/shaders/aerial`, following the repository's existing shader distribution.
The shared cel include and original material settings are preserved. The aircraft
proxy now lofts a longer faceted fuselage and canopy, with clipped wings, leading
strakes, lower fins and exposed twin engine housings. Closed panel prisms include
small physical bevels that give rim lighting actual grazing normals. Each convex
part has its own face orientation center before native SurfaceTool batching. Dark
canopy/intake/nozzle surfaces retain a separate response. Static and live poses use
the same function, so the frozen captures represent the running scene.

WorldEnvironment supplies native HDR glow, verified by an on/off GPU capture on
the current Godot 4.7 Mobile renderer. A CanvasLayer post pass runs after the 3D
frame, below the HUD. It supplies an analytic solar corona, twelve-tap screen-space
radial light scattering, chromatic flare ghosts and procedural normal-based rain
refraction. The supplied DMC sunset is the optical flare reference. Crysis is the
lightshaft visual reference; this is standard screen sampling, not a claim about
its exact source implementation. Rain uses jittered stretched drop fields and is
coupled to storm-cloud density. Source luminance masks solar effects behind dark
occluders, and cloud-interior density suppresses direct-sun optics. Bright white
geometry remains a known limit of luminance masking; a depth mask would be needed
to distinguish it reliably from the sun. Sky, surface haze, fog, sunlight and live
VFX share palette/storm changes and sun direction. Glow is engine-owned HDR; the
solar rays remain a screen-space approximation, with no volumetric light transport.

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
godot --path demo --script res://aerial/tests/capture_soft_depth.gd --resolution 1000x600 --always-on-top
```

The functional check uses native terrain raycasts at the river vertices to
reject a missing floor or terrain clipping through the water. It also covers
opposing aircraft-part/bevel normals, opaque livery
attributes, exact wingtip attachment, static/live pose
agreement, cloud coverage and entry/exit, storm rain activation, fixed world-space
history, bounded trail allocation, teleport handling, palette changes and effect
expiry. A watchdog makes assertion failures terminate instead of hanging the check.

GPU captures include native HDR glow on/off with Canvas disabled, Canvas on/off,
isolated flare on/off, sun occlusion, sunset/daylight, aircraft above/below/front, explosion phases,
cloud entry, and wet/dry geometry. Pixel comparisons reject an inactive post or
rain pass. A ghost-region pixel probe verifies flare contribution and suppression
behind a dark sphere. The rain preview deliberately forces rain over visible geometry for
inspection; normal play enables it only in storm cloud. Per-capture draw/primitive
counters are saved with frame names so unlike camera views are not conflated.
Native transform readbacks verify trail orientation/elongation and cloud placement;
the headless check also verifies accent, fire and smoke lifetime ordering.
Aircraft inspection cameras use the model's local axes, so banking cannot turn an
"above" view into an underside view.
These are desktop observations, not a device benchmark. Keep the capture window
visible on macOS; a missing rendered frame fails through a watchdog. Headless mode
is rejected immediately for visual capture. Shader validation requires rendered
frames, not the headless functional check alone. The separate soft-depth probe
renders two intersecting spheres and checks that the enabled material fades at
the floor while retaining the rest of its mesh. It saves `/tmp/dmc-soft-depth-probe.png`;
this path is verified on the current Mobile renderer.

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

Cloud/canyon comparison then replaced repeated flattened banks with four taller
cumulus silhouettes and broad sunward crown lighting. A wider valley and river,
fewer mesa caps, and talus skirts expose the blue valley floor. Shared haze begins
farther away to retain foreground value separation. The initial flight/camera height
now shows the open canyon while keeping the hero near the middle-right of the frame.

The erosion pass separates flat caps from steeper cliff contours, lower benches
and ribbed skirts, while preserving an open river apron. Native shadow on/off
captures show cast shadows contribute to the remaining vertical cliff bands.
Removing grid jitter/contour erosion did not eliminate them; increasing shadow
bias reduced the bands but distorted contact. The current shadow settings remain
in place, and the fixed 22-meter proxy grid remains a cliff-fidelity limitation.

Compared directly with the supplied references, these remain incomplete:

| Area | Current evidence | Remaining visual work |
|---|---|---|
| Aircraft | Beveled clipped wings, exposed engines, longer canopy/nose and geometry-bound livery render above/below/front | Proxy silhouette, finer panel hierarchy and rim consistency still need closer matching |
| Environment | Level mesa caps, eroded contours, lower benches/ribbed skirts, warm exposed rock and a broad river apron render in both presets | Cliff shading strips, finer erosion shapes and more authored foreground/midground grouping still needed |
| Trails/exhaust | Overlapping oriented puffs, historical wingtip poses, world wind and mesh flames render | Broader irregular breakup and near-camera shapes need refinement |
| Clouds | Four cumulus silhouettes, warm sunward crowns, matched density regions and coverage work | Lobe silhouettes/internal breakup still need closer matching |
| Explosions | Connected asymmetrical smoke plume, vertex value variation, shared sunlight, fire islands and separate age phases render | More heated inner lobes/fire pockets and less patterned fire still needed |
| Weather/post | Native HDR glow, orange horizon/crowns, isolated chromatic flare, sun occlusion and cloud-density optics gates render | Longer structured rays, white-geometry occlusion and finer weather transitions remain |

The overall rendering goal stays active. Passing the functional checks does not
prove that the frame matches the references, and no visual similarity percentage
is claimed.
