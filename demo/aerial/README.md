# Aerial rendering study — DELIVERY MUST COMPLETE

A working comparison scene for the rendering goal. This is an ongoing visual
iteration, **not a claim that reference fidelity has been achieved**. The existing
factory/mech scene remains the default project scene.

## Run and controls

Open `aerial_demo.tscn` and press F6, or run from the repository root:

```sh
godot --path demo res://aerial/aerial_demo.tscn
```

- **W/S:** forward/back movement. **A/D:** strafe left/right normally.
- **Q/E:** yaw; response softens at flight speed. Arrow-key attitude bindings
  remain disabled. Body streamlining remains automatic outside combat attitude.
- **R/F:** vertical thrust up/down. **Ctrl held:** precision movement/yaw.
- **Space / C:** increase/decrease thrust through 0, 0.5, 1, 2 and 4 × hover.
  Each press changes one detent; holding the key does not repeat.
- **RMB held:** uncage momentum and raise the weapon to combat-ready.
  Angular damping stays active; WASD still translates outside the X/aero gate.
- **Shift + WASD:** 0.2-second vernier burst, with a 0.5-second recharge.
  Assisted flight catches the slide; uncaged flight keeps the momentum.
- **X held:** combat brake. With aerodynamic authority **strictly above 50%**,
  **W/S pitches down/up and A/D rolls left/right**. The HUD shows those bindings.
  A flow dip disables attitude input immediately. Held keys stay captured and
  neutral until release, so they cannot suddenly request translation. Releasing
  all directional keys below the threshold restores movement. Releasing X restores
  movement immediately. Shift+WASD remains a burst without also pitching/rolling.
  Outside that gate, WASD keeps normal movement. X still spreads the limbs and
  adds strong airbrake drag. Passive drag also
  increases above 35 m/s and reaches full strength at 100 m/s without pressing X.
- **Click:** capture mouse. **Mouse:** aim/look only; it never steers the chassis.
- **LMB:** raise, brace and fire the rifle. **MMB / Tab:** focus target/free aim.
- **Wheel:** zoom. **Home:** reset camera. **Esc:** release mouse. **P:** pause.
- **G:** ground-walk preview. **1 / 2:** palette. **3 / 4:** weather. **F8:** explosion.

Flight starts in stabilized 1× hover. WASD directly requests movement at low
speed, including braking when released. As speed builds, the suit streamlines
itself automatically. X plus the aero gate is the explicit attitude override.
Higher-speed drag
remains a physical force, so thrust can balance it rather than abruptly clamping
speed. The camera, head and weapon remain independent of movement.

The rifle rests low while moving normally. RMB, LMB, combat braking or target focus raises it
into braced aim. The offhand cradles the measured receiver underside for central
aim, releases to a chest guard for wide tracking, then regrips on return. Shot
recoil travels through the wrists/elbows. An out-of-arc aim cannot turn the chassis
or fire backwards through it. Rifle fire remains a bounded hitscan/tracer preview.
The factory/roster project settings remain intact; the giant canyon display uses
ten world units per motion meter.

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
- Flight tracks attitude (native Quaternion), world velocity and aim separately.
  Behavioral production references are the
  [DCS Su-27](https://www.digitalcombatsimulator.com/upload/iblock/ed7/Su-27%20DCS%20Flaming%20Cliffs%20Flight%20Manual%20EN.pdf)
  aerodynamic envelope, [Elite Dangerous flight assist](https://d1wv0x2frmpnh.cloudfront.net/elite/website/assets/English-PlayersGuide_v2.00-Horizons.pdf)
  for independent attitude/momentum, and [Armored Core VI quick boost](https://www.fromsoftware.jp/manual/armoredcore6/win/action.html).
  These are behavior references, not claims about unpublished game internals.
  The existing controller integrates thrust, lift, drag and gravity at up to 120 Hz.
  Aerodynamic authority multiplies speed, attached-flow quality and useful lift
  orientation. Lift falls away with AoA/sideslip; X increases real quadratic drag.
  Low-speed FBW applies bounded target-velocity corrections and 1× vertical
  support, following the existing vector-controller pattern. The X/aero gate
  overrides WASD with DCS-style body-axis pitch/roll. Entry requires aero >0.5;
  an overlapping held direction captures its binding through reduced airflow.
  Below the threshold, rotation input is disabled and those keys remain neutral
  until release; the existing attitude stays damped instead of auto-leveling.
  Automatic attitude alignment and hover velocity correction stop during that
  maneuver, while angular damping, physical X drag and ground recovery remain.
  No velocity replacement occurs on entry/exit. Pilot yaw is tracked independently of
  the automatic body-pitch target; no view or aim vector enters movement.
  Assisted flight pitches the body toward a prone stance as forward speed builds.
  Uncage removes path/velocity corrections while retaining yaw and angular damping.
  Additional quadratic drag ramps over 35–100 m/s and remains separate from X.
  Motion is integrated through forces; velocity is never replaced or rotated.
- Native swept CharacterBody capsule queries replace the old altitude floor clamp.
  Three swept segments predict the next three seconds of the current curved path.
  HUD warning begins below 2.4 seconds; recovery ramps from 1.3 to 0.6 seconds.
  Uncaged recovery is capped at 0.25 G; recaging permits a 4 G escape request.
  Actual collision clips travel at the native safe fraction and slides velocity
  along the surface. This is a chassis capsule, not per-limb collision. The
  aerodynamic coefficients and finite FBW/vernier forces are tunable game
  approximations, not measured Gundam flight data or a six-engine wrench solver.
- The physical root attitude leads the pose. Airflow, local acceleration, angular
  rates/acceleration, AoA departure, drag command, G load, aim and requested thrust
  drive the existing procedural rig. Pelvis, torso and arms overlap with 30 ms
  response differences. Free limbs trail airflow; G load, angular acceleration
  and vertical thrust
  compress/tuck the legs, opposed vernier demand braces them asymmetrically, and
  ankles follow later than hips/knees. Departure and X open the limbs,
  and the rifle arm resists airflow more strongly. The head leads within its
  30° yaw / 20° pitch zone; shoulder/torso articulation handles wider aim.
  Rifle aim is bounded to an 85° yaw / 70° pitch envelope. Gears 5's low-ready
  and braced two-hand presentation is the visual reference, rather than a claim
  about its implementation. The supplied `GunPose` is sampled once for finger
  grip rotations and the left/right wrist relationship, then stopped. Those
  grip poses blend through the existing procedural rig; no static flight clip plays.
  Native TwoBoneIK3D solves both hands. The receiver underside was projected onto
  the GUN source triangles at (-2.4, 5.661993, -0.832874) and transformed through
  its actual skin bind. A predicted wrist basis gives the offhand the same contact
  point used by the final weapon modifier, avoiding an extra IK pipeline.
  The rifle keeps a stable up axis, a tucked aiming elbow and a distinct low-ready
  stance. Offhand support fades for wide/unreachable aim and returns to a chest
  guard. Fingers release/regrip; a damped shot impulse drives arm follow-through.
  The camera stays gravity-upright and aiming never steers the chassis.
  No flight/hover/stall clips play. Imported clips remain for Animation dock
  preview and dynamic walking; native modifier influence fades out for walking.
  This supplied model has no independently rigged binders, so no binder animation
  is invented. Movement, motors, weapon clocks, pose and VFX pause together.
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
  Requested thrust/G load sets the six main engines' visible power. Per-instance
  power changes brightness and length without material copies. Shoulder/thigh
  pulses respond to angular demand, acceleration and directional bursts. The
  force integrator uses aggregate thrust/FBW budgets; local engine cones drive
  the visual actuators, not an individual-engine force/torque optimizer. Final
  modifier poses update attachment readbacks and local motor targets before
  rendering. Trails record actual paths and stay hidden at rest or on foot.
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
procedural flight, animation pause, bone attachment, static/live pose
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
checks cover normal movement and braking, 30/60/120 Hz agreement, detent edges,
the exact X/aero threshold, combat pitch/roll axes, held-input continuity,
restored low-aero movement, X release, high-speed passive
and X drag, camera-independent movement, native terrain prediction/collision,
source-triangle thruster seating, native IK, local motor cones, low-ready/raised
arm travel, exact offhand contact, wide release, recoil, rifle hits, walk and pause.
Motion captures show forward/side movement, bursts and braking, followed by an
isolated low-ready → braced aim → recoil → wide release → regrip sequence.
`arm-metrics.json` records the measured support weight and contact error.
`capture_mech.gd -- /tmp/combat --combat-only` runs a short native X/WASD replay;
`combat-telemetry.json` records aero, binding state, rotation commands and velocity.
These are desktop observations, not a device benchmark. The mech capture uses a native offscreen viewport at fixed 1280×800 resolution
with its host window minimized. Captures explicitly request a native redraw so a frozen window
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
