# Aerial rendering study — DELIVERY MUST COMPLETE

A working comparison scene for the rendering goal. This is an ongoing visual
iteration, **not a claim that reference fidelity has been achieved**. The existing
factory/mech scene remains the default project scene.

## Run and controls

Open `aerial_demo.tscn` and press F6, or run from the repository root:

```sh
godot --path demo res://aerial/aerial_demo.tscn
```

- **W/S or Up/Down:** forward thrust / reverse.
- **A/D or Left/Right:** yaw left / right.
- **Q/E:** strafe left / right.
- **Space:** climb. **C or Ctrl:** descend.
- **Shift:** boost. **X:** hard airbrake.
- **Drag either mouse button:** orbit the camera and aim gaze. **Wheel:** zoom.
- **R / Reset camera button:** restore the follow view.
- **Flight buttons:** Manual, Hover, Cruise, Boost, Brake cycle, Bank left,
  Bank right and Figure 8, matching the supplied Iron Man procedural rig.
- **P:** freeze movement, springs and VFX. Camera orbit still works for inspection.
- **G:** terrain-grounded walking preview / return to flight at the current location.
- **1 / 2:** sunset / daylight. **3:** storm. **4:** cloud coverage.
- **F:** explosion. Space is reserved for climbing.

Manual is selected at startup. Movement keys control the hero mech; maneuver
buttons run the reference's continuously simulated presets. The second mech uses
its own controller and Figure 8 preset. The camera follows with spring target
and acceleration lag. This remains a rendering/flight-control study, without
combat or a mission system. Walking uses the existing animated, stride-matched
terrain preview. The factory/roster project settings remain intact.

## Implementation and reference

The production visual reference is **DELIVERY MUST COMPLETE**, using the supplied
three images and comparison brief. Its unpublished aircraft/cloud implementation
is not assumed to be known. The stretched unsubdivided icosphere exhaust follows
the developer disclosure quoted in that brief; the other effects are visual
reconstructions using Godot's existing mesh, MultiMesh, camera and fog facilities.

- Both former jets now instance the supplied white `MechAsset.glb`. The roster
  actor supplies cloned animation resources, root displacement removal and source
  color conversion; aerial materials add the same distance haze, sky fill and Sun
  palette as the environment. Armor remains matte and desaturated, with visible
  muted green accents. No orange aircraft livery is applied to the model.
- Flight uses the supplied Iron Man script's velocity controller and procedural
  pose logic, adapted to Godot's -Z-facing actor and the Gundam's +Z-facing bones.
  The production motion reference is
  [Marvel's Iron Man VR](https://blog.playstation.com/archive/2019/07/18/how-marvels-iron-man-vr-nails-flying/).
  There is no scripted hero/wingman route and no static `Airborne`, idle or boost
  animation playing in flight. Each frame starts from the skeleton rest pose.
  Imported clips remain intact for Animation dock preview and dynamic walking.
  Six control inputs spool through critically damped springs. Heading inertia,
  target velocity, acceleration limits, coasting drag and the X brake reproduce
  the reference's controller equations. Integration uses substeps up to 1/120 s.
  The canyon display uses ten world units per reference motion unit, while pose
  tuning remains in the reference's units. A native terrain raycast replaces the
  prototype's flat-floor cushion; this is a velocity controller with vertical
  clearance, rather than Camouflaj's rigid-body/collision flight simulation.
  Actual forward/lateral speed, acceleration, boost, braking, climb and yaw rate
  produce continuous pose weights. Four articulated waist/chest joints distribute
  the difference between leading chest and lagging hips. Head gaze follows turn
  intent and camera orbit; legs trail with staggered spring response. Native
  SkeletonModifier3D generates the pose, then TwoBoneIK3D solves soft-reach hand
  targets and elbow poles. Arms are relaxed balance limbs without hand propulsion.
  Godot/source coordinate conversion preserves the correct bank direction.
  Flight influence fades out for the supplied dynamic walking clip. Springs,
  motors, movement and VFX pause together; camera inspection remains available.
- Terrain owns world-height/slope coloring and broad strata. Mechs, terrain,
  clouds and mesh VFX share distance haze and palette controls. Sky/sun now belong
  to the aerial stack instead of relying on the old third-party sky material.
  The existing heightfield now separates level mesa caps, eroded cliff contours,
  lower benches and ribbed talus/outcrops. Warm exposed rock sits above blue valley
  shadows; a broad river apron preserves the open canyon composition.
- Clouds use 18 deterministic banks across four native MultiMesh batches. Each
  variant is a coarse marching-cubes iso-surface extracted from a 33×21×29 signed
  density grid. Broad compressed decks, selected towers, shelves, underside cuts
  and weak secondary noise replace the previous origin-radial sphere deformation.
  Gradient normals retain large readable color planes. Weather samples the same
  trilinear field as the mesh; coverage and rigid drift affect both together.
  The meshing production reference is [Space Engineers' published marching-cubes
  mesher](https://github.com/KeenSoftwareHouse/SpaceEngineers/blob/master/Sources/Sandbox.Game/Engine/Voxels/MyMarchingCubesMesher.cs).
  The implementation uses a standard BSD-licensed lookup table, with its license
  retained beside the field generator. DMC's exact cloud generator is unpublished;
  this is a visual reconstruction, not a claim that it uses marching cubes.
  Three broad cloud tones use coarse world-space threshold noise and the shared
  Bayer pattern. Sunward lining, orange transmission/bank glow, directional haze
  and storm entry weather remain part of the lighting stack.
- Trails record fixed world-distance samples in a 512-slot history. Birth times
  interpolate along the input path, so both live motion and seeded histories use
  the same spacing and age semantics. Teleports break the path without moving old
  smoke. Distant trail coverage fades through the shared dither before the far
  plane, using the scene's existing haze range. Six-sided irregular flat-shaded
  wedges follow the tangent with varied
  deterministic roll, slight age spin, radial growth and dithered expiry. A separate
  wider camera-facing ribbon supplies low-opacity screen-door vapor around the
  core; it shares the same history and clock. The distant contrail uses a narrow
  noisy-width ribbon, while the missile layers a short-lived HDR ribbon and native
  bloom over its smoke/vapor aftermath. A short condensation delay exposes the
  depth-tested missile burn before opaque smoke forms. All layers share directional cel shading,
  palette changes, world-space wind and pause behavior. No soft round smoke texture
  or continuous alpha blend is used.
- One mesh VFX shader supplies age, color ramp, HDR emission, graphic fire,
  dither dissolve and optional depth intersection fading. Explosions keep eight
  fire lobes, twelve smoke lobes, twelve short sparks and six debris fragments.
  Each component has its own birth time, lifetime, launch velocity and drag.
  Fire cools within roughly a second, smoke slows into buoyant flow, and fragments
  tumble and fall under gravity. Low-frequency coherent flow bends the billows;
  smoke uses softer dithered edges and three lighting values. Fire patches advect
  and burn through on each lobe's local clock. Long-lived rings/arcs and shared spring overshoot
  have been removed: pressure reads through the fast outward burst and sparks.
  The production motion reference is
  [Battlefront II's independently simulated VFX particles](https://forums.ea.com/discussions/star-wars-battlefront-2-en/community-transmission-%E2%80%94-visual-effects-in-star-wars-battlefront-ii/10820960).
  Closed-form drag evaluates the existing bounded mesh particles without a new
  simulation framework, so pause and deterministic seeking remain available.
  Live bursts choose a fresh seed; captures can pass a seed for reproducibility.
  Transient effects are freed without retaining palette references.
- Each mech has six equal-size main boosters: two in the backpack's paired lower
  barrel caps, one in each calf recess, and one in each heel inlay. Four smaller
  cold-gas outlets occupy the shoulder and thigh recesses. There are no hand,
  forearm or upper-arm boosters. Mount centers were projected onto source mesh
  triangles; seated ball joints connect vectoring bells to the modeled ports.
  Each port's measured opening normal defines its neutral orientation in its
  attachment bone's space. Backpack barrel normals point down/aft, calf recesses
  point aft/down, and heel openings point down in the standing rest pose.
  Every main and cold-gas motor uses a spring-damped, 30-degree local cone.
  Yaw intent adds tangential main-exhaust offsets around each mount lever arm
  and opposite shoulder/thigh axial offsets to produce a visible control couple.
  Desired exhaust is transformed into that local frame and clamped before the
  motor moves. Bone animation is never canceled to maintain a world-down axis;
  legs and feet carry their booster axes through the procedural pose. A saturated
  motor remains at its local limit even when the requested force is unreachable.
  Gravity, desired acceleration and aerodynamic drag produce requested load,
  normalized across the six main boosters with smooth boost/brake/turn transfers.
  Per-instance power changes brightness and length without material copies.
  Opposed shoulder/thigh control pulses replace the reference's hand repulsors.
  As in the supplied script, requested force drives the animation and VFX; the
  independent velocity controller owns translation. This is not a constrained
  six-engine rigid-body optimizer. Final modifier poses update all attachment
  readbacks and local motor targets before rendering. Trails record actual flown
  paths and remain hidden during stationary hover or ground walking.
- Cel exhaust follows [KSP2's engine exhaust breakdown](https://forum.kerbalspaceprogram.com/topic/204884-developer-insights-11-%E2%80%93-engine-exhaust-visual-effects/): throttle drives mesh length, flow rate and brightness together.
  The supplied `Stylized_BOTW_Fire.gdshader` supplies the scrolling/twisting noise,
  tail deformation and rim-color ideas. Its duplicate in `open-sea-godot` was
  identical; no bound source textures/materials were present. The existing
  GDQuest fire mask/noise candidates were inspected, but a shared native seamless
  NoiseTexture2D avoids external texture dependencies.
  The original BotW vertex code overwrites its scroll with a default-zero speed
  component, and its added alpha masks can saturate opacity. Those equations are
  not carried over. Coarse noise instead moves hard color-band boundaries and a
  tail cutout; the surface does not display continuous texture shading.
  A normalized, tapered 20-triangle mesh scales rearward from its nozzle. Shape
  masks use normalized coordinates, while flow noise uses nozzle-local distance
  including parent scale, preserving turbulence size without world-space swimming.
  Small independent width/length pulses, tail sway and axial flutter change the
  silhouette while leaving the nozzle locked. A clamped displacement and expanded
  native AABB prevent movement from escaping the culling bounds. Separate instance
  phase offsets vary the six main engines without extra materials. The integrated flow
  clock preserves phase across throttle changes, wraps seamlessly, and freezes
  with the scene. Bright cell bands are an artistic approximation, not simulated
  shock diamonds. Pressure regimes, blendshapes and exhaust heat refraction are
  omitted because this scene has no engine/pressure model requiring them.

Reusable shader sources live in `src/aerial`; the identical runtime copies are
in `demo/shaders/aerial`, following the repository's existing shader distribution.
The shared cel include and original material settings are preserved.

WorldEnvironment supplies native HDR glow. A CanvasLayer pass below the HUD adds
an overexposed white core, warm glare envelope, broad halo, soft starburst, three
horizontal streak widths, large partial chromatic rings, two spectral ghosts and
weaker reflections. Veiling glare explicitly reduces local contrast near the Sun.
The supplied DMC sunset is the visual reference. Rain uses stretched drop fields
coupled to storm-cloud density.

A native CompositorEffect integrates atmospheric radiance and transmittance along
24 depth-clipped view-ray steps at quarter resolution. The production technique
reference is [Horizon Zero Dawn's volumetric cloudscapes](https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn),
using view-path integration and light-path cloud attenuation. This is a bounded
adaptation, not a port of Guerrilla's renderer. A cached 256-square cloud-local
shadow field creates darker columns between lit haze. The same signed grids used
by marching cubes and weather are uploaded as one four-variant 3D density atlas.
Sun rays sample the grids within each bank's field bounds, so openings affect
shadow thickness too. Rigid drift moves the lookup; field revision, coverage or
Sun changes rebuild the shadow field. The cached front/back/optical-depth map
remains a bounded approximation to layered scattering. A near fade protects cool
foreground values.
The cloud surface shader separately estimates optical thickness for orange
transmission, broad bank glow and cream/gold lining; this surface approximation is
not physical multiple scattering.

The compositor reads actual multisample depth on Mobile, then bilaterally upsamples
its scattering/transmittance into the native color attachment. Godot 4.7 Mobile's
packed HDR color lacks storage-image access, so the final step uses native raster
blending and preserves destination alpha. Packed HDR radiance is calibrated for
the engine's luminance multiplier. A GPU-only depth mask suppresses every optical
layer behind both dark and white geometry. The mask is bound only after its first
render callback creates a valid texture. Offscreen/behind-camera Sun, storms and
cloud interiors also suppress optics. No runtime CPU texture readback is used.

The current volume path requires a RenderingDevice renderer (Mobile or Forward+)
and is monoscopic. `atmosphere_strength` controls the solve; zero skips scattering
but keeps the solar mask active. `atmosphere_shadow_strength` controls cloud-column
contrast. Density, height falloff, range, Sun energy and ambient color are configured
in `_update_atmosphere`; optics and cloud terms have separate shader strengths for
A/B tuning. Sky, surfaces, new/live VFX and the volume share one Sun direction and
warm/cool palette. Explicit sky fill is applied in the material shaders because
they disable native ambient lighting. These captures validate desktop Metal
Mobile rendering, not phone performance or exact reference fidelity.

## Asset selection

The runtime model candidates were inspected: `MechAsset.glb` and the flat-color
George, Leela, Mike and Stan glTFs.
MechAsset is the white humanoid model with 76 mesh parts and 11 source
clips. The other four are colored compact robots and lack its directional boost
poses. The existing GLB is chosen over its FBX source for the same import reasons
recorded in `models/MechAsset/README.md`. No new external asset is needed.
The model has no named thruster sockets. Native Torso, Shin, Feet, Shoulder and Thigh attachments
provide paired backpack, calf and heel mounts plus shoulder/thigh control jets
without editing the skeleton. All mount coordinates were inspected in native
close-ups and measured against source triangles in bone-local space. The backpack
uses the paired lower barrels, rather than an estimated point beneath the pack.
Missile, trail, explosion, terrain and cloud geometry remain procedural.

## Checks and comparison captures

```sh
godot --path demo --script res://aerial/tests/capture_mech.gd --resolution 1440x810 --always-on-top -- /tmp/aerial-mech
godot --headless --path demo --script res://aerial/tests/test_aerial_stack.gd
godot --headless --path demo --script res://aerial/tests/test_flight_pose.gd
godot --headless --path demo --script res://aerial/tests/test_surface_lighting.gd
godot --headless --path demo --script res://aerial/tests/test_volume_state.gd
godot --headless --path demo --script res://aerial/tests/test_cloud_field.gd
godot --headless --path demo --script res://aerial/tests/test_faceted_trails.gd
godot --headless --path demo --script res://aerial/tests/test_vfx_timing.gd
godot --path demo --script res://aerial/tests/capture_vfx_motion.gd --resolution 1440x810 --always-on-top -- /tmp/dmc-vfx-motion
godot --path demo --script res://aerial/tests/capture_cloud_tones.gd --resolution 960x540 --always-on-top
godot --path demo --script res://aerial/tests/capture_cloud_trails.gd --resolution 1440x810 --always-on-top -- /tmp/dmc-cloud-trails
godot --path demo --script res://aerial/tests/capture_lighting.gd --resolution 1440x810 --always-on-top -- /tmp/dmc-lighting
godot --path demo --script res://aerial/tests/capture_volume.gd --resolution 960x540 --always-on-top
godot --path demo --script res://aerial/tests/capture_aerial.gd --resolution 1440x810 --always-on-top -- /tmp/godot-dmc-captures
godot --path demo --script res://aerial/tests/capture_soft_depth.gd --resolution 1000x600 --always-on-top
```

The functional check uses native terrain raycasts at the river vertices to
reject a missing floor or terrain clipping through the water. It also covers
white-model selection, root displacement removal, stride-based walking, supplied
boost/hover mapping, animation pause, torso attachment, static/live pose
agreement, cloud coverage and entry/exit, storm rain activation, fixed world-space
history, bounded trail allocation, teleport handling, palette changes and effect
expiry. A watchdog makes assertion failures terminate instead of hanging the check.
Afterburner checks cover normalized bounds, nozzle contact, throttle/visibility,
phase continuity, bounded flow time, silhouette pulses and pause behavior.

GPU captures include afterburner off/low/full, changing flow, phase wrap and
nonuniform aircraft scale, plus native HDR glow on/off with Canvas disabled, Canvas on/off,
isolated flare on/off, sun occlusion, sunset/daylight, aircraft above/below/front, explosion phases,
cloud entry, and wet/dry geometry. Pixel comparisons reject an inactive post or
rain pass. A ghost-region pixel probe verifies flare contribution and suppression
behind a dark sphere. The light-focused capture isolates every optical, cloud and
surface component, checks black/white solar occlusion and offscreen/behind-camera/
storm/cloud-interior gates, verifies actual gray-patch contrast reduction, switches
MSAA, resizes buffers and reloads the scene. The volume fixture checks foreground
depth cutoff, shadow attenuation, zero-strength color identity and allocation
stability. `lighting-metrics.json` records image deltas, resource counters and
per-capture draw/primitive counts. A missing GPU timing is reported as null, never
zero cost. The rain preview deliberately forces rain over visible geometry for
inspection; normal play enables it only in storm cloud. Per-capture draw/primitive
counters are saved with frame names so unlike camera views are not conflated.
Native transform readbacks verify trail orientation/elongation and cloud placement;
the headless check also verifies spark, fire and smoke lifetime ordering. The
explosion check covers independent lifetimes, drag deceleration, debris gravity,
smoke buoyancy, seed variation, deterministic seeking and bounded storage. Motion
captures include the complete dissipation tail rather than cutting the smoke off
at the end of a short preview; `--explosion-only` skips unchanged exhaust footage.
Mech captures inspect all six main mount attachments during directional pose
poses, local thrust cones, articulation, individual nozzle
close-ups, throttle states, a complete walk cycle and an exact frozen frame.
Cold-gas close-ups compare each outlet on/off to reject hidden plumes. Functional
checks also exercise all reference key bindings, eight continuously simulated
modes, 30/60/120 Hz controller agreement, boost/coasting/braking, strafe, climb,
reverse, floor clearance, camera input/gaze, source-triangle seating (within 0.02
source units), IK endpoints, local motor cones, normalized load and pause.
Checks cover exact outlet count, equal main sizing, independent vector commands,
motor limits and smooth response. The motion capture injects native key events
through hover → W → W+Shift → W+Shift+A → X. It verifies actual yaw, braking,
stopped clip playback and attachment integrity on every rendered frame.
These are desktop observations, not a device benchmark. Keep the capture window
visible on macOS. Captures explicitly request a native redraw so a frozen window
does not wait indefinitely for an automatic frame; a watchdog bounds failures. Headless mode
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
masses. The later natural-motion pass replaces the decorative arcs with short
  sparks and independently moving fire, smoke and debris.

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
| Trails/exhaust | Flat-shaded wedge cores, wide dithered vapor, thin/HDR ribbons and nozzle-anchored cel afterburners render | More authored smoke envelopes and afterburner cell shapes can refine reference fidelity |
| Clouds | Four density-derived decks with shelves/overhangs, three-tone breakup and shared mesh/weather/shadow fields | More authored macro composition can refine reference fidelity |
| Explosions | Connected asymmetrical smoke plume, vertex value variation, shared sunlight, fire islands and separate age phases render | More heated inner lobes/fire pockets and less patterned fire still needed |
| Weather/post | Layered solar optics, directional haze/fill, cloud transmission/lining and depth-clipped cloud-shadowed scattering render; dark/white occlusion and visibility gates pass | More authored shaft/column placement and finer weather transitions remain |

The overall rendering goal stays active. Passing the functional checks does not
prove that the frame matches the references, and no visual similarity percentage
is claimed.
