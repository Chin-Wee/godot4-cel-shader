# Aerial rendering study — DELIVERY MUST COMPLETE

A working comparison scene for the rendering goal. This is an ongoing visual
iteration, **not a claim that reference fidelity has been achieved**. The existing
factory/mech scene remains the default project scene.

## Run and controls

Open `aerial_demo.tscn` and press F6, or run from the repository root:

```sh
godot --path demo res://aerial/aerial_demo.tscn
```

- **Upright powered hover, WASD:** directional thrust for the first three seconds
  of each press. Continue holding to ramp into pitch/bank over 1.25 seconds.
  Release or reverse direction to restart that interval. Diagonals are normalized.
- **Forward flight / unpowered, W/S:** pitch down/pull up. **A/D:** bank/roll.
  **Q/E:** yaw immediately. The mouse remains independent of steering.
- **Space / C:** step through **0, 0.5, 1, 2, 4 × hover**. Each press changes one
  detent; key repeat is ignored. Engines ramp toward the request.
- **Shift held:** aerodynamic brake and spread posture; rotation remains available.
- **R:** finite ground-contact leg jump, without changing the thrust detent.
- **Ctrl held:** precision translation/rotation. **Mouse:** look only.
  **MMB / Tab:** camera focus/free look. Click captures the mouse.
- **Wheel:** zoom. **Home:** reset camera. **Esc:** release mouse. **P:** pause.
- **F9:** diagnostics: orange propulsion, cyan aerodynamics, magenta RCS torque,
  white gravity. Vectors use separate display scales, not common units.
- **G:** isolated walk preview. **1 / 2:** palette. **3 / 4:** weather.
  **F8:** explosion.

Flight starts at nominal 1× hover. Low-speed, near-upright powered flight receives
bounded upright/drift correction and 1× tilt compensation. Hold W and select 2×:
the first three seconds push forward upright, then continued holding pitches
into forward flight. Powered aligned flight softens pitch near 30 degrees of
airflow misalignment instead of outrunning the curving trajectory. Shift braking
permits an intentional combat departure; large misalignment and engine cutoff
retain independent attitude and travel. Thrust, lift, drag and gravity produce the path;
there is no cruise mode or velocity replacement. C down to zero removes main
propulsion after spool-down while cold-gas torque still controls attitude.
Aerodynamics and gravity remain active. Shift presents more area to the airflow,
including during an unpowered fall. The HUD reports selected/actual power,
requested/delivered thrust, hover assistance, airflow and actuator saturation.

Gun aiming, firing and the crosshair are removed for this flight-animation pass.
The runtime gun and its accessory mesh are hidden; source preview is retained.
Inspection found `GUN` and `Cube_001` weighted solely to Hands.R; `Cube` is
Torso-weighted backpack geometry and stays visible.
Both arms now anticipate pitch/yaw, gather or extend through rolls, spread during
braking and brace forward when delivered thrust opposes existing travel.
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
- The native `RigidBody3D` owns position, attitude, linear/angular velocity,
  gravity and collision response. The nested roster CharacterBody's collider and
  physics are disabled. One unscaled body carries the scaled capsule and visual
  model. Godot's fixed physics clock advances control and motors; rendering cannot
  advance movement or gimbals. Native continuous collision detection handles fast
  contact. Terrain prediction warns without adding force. Behavioral references:
  [DCS Su-27](https://www.digitalcombatsimulator.com/upload/iblock/ed7/Su-27%20DCS%20Flaming%20Cliffs%20Flight%20Manual%20EN.pdf)
  for the aerodynamic envelope and
  [Elite Dangerous](https://d1wv0x2frmpnh.cloudfront.net/elite/website/assets/English-PlayersGuide_v2.00-Horizons.pdf)
  for independent attitude/momentum. No unpublished internals are assumed.
- `flight_controller.gd` reads commands, measures motion/airflow, computes hover
  assistance, aerodynamics, main propulsion, RCS torque and leg push, then applies
  them through native physics. Forces are newtons; torque is newton metres. Ten
  world units represent one metre: native forces multiply by 10, torque by 100,
  velocities divide by 10, and native inertia divides by 100. Native gravity is
  scaled consistently and never added twice.
- Main forces use actual physics-tick gimbal directions and animated attachment
  positions. Off-centre application generates the actual engine moment. Measured
  equal shares caused forward drift because the calf ports cannot vector upright
  within their 30-degree cones. Low-power shares are 40% per steerable heel and
  5% per remaining motor. Each heel's share falls as it reaches the common engine
  capacity; the remainder is shared by the other four. All six reach one-sixth
  at maximum power. This permits backward hover force without demanding that the
  canted barrels point outside their cones. Bounded hover gimbal trim removes
  residual bias; it moves physical motors and cannot create extra force. Port-cant
  feed-forward is body-relative so yaw cannot leave stale world trim fighting the
  motors. Velocity feedback is 3.6/s; residual integral trim learns only during
  quiet hover below 1.5 m/s, preventing windup against an intentional slide.
- One damped angular-rate controller uses native shape-derived inertia and finite
  cold-gas torque. Requested rates are 1.0/0.8/1.2 rad/s before precision scaling;
  actuator limits correspond to 5 rad/s² per body axis. Main-engine moments consume
  the same torque budget. Saturation is displayed instead of erased by a velocity
  clamp. Rotation requests ease in over 0.14 s at up to 2×, rising to 0.28 s at
  4× while loaded joints settle. Full-power streaming tucks paired hips/knees to
  bring the lower outlets toward the mass centre. Directional hover replaces
  that tuck; backward force sweeps the calves forward with ankle counter-rotation
  so their canted ports can contribute without exceeding the nozzle cones.
  These are rig-profile calibrations; the cold-gas limit remains unchanged.
  Cold gas is a lumped three-axis actuator: exact outlet allocation and fuel
  are omitted. Fixed capsule inertia does not change with procedural limb motion.
- Hover fades over 18–45 m/s airspeed and 30–60 degrees from upright, and requires
  main power. It never depends on stall/attached-flow quality. Neutral pilot axes
  allow upright restoration. A press beginning in powered hover keeps its first
  three seconds of directional thrust even if climb airspeed then increases.
  Per-axis hold times reset on release/reversal; afterward the same input ramps
  from translation into rotation. Unpowered presses rotate immediately. Only nominal 1× receives
  vertical thrust compensation, capped at 2×. Other detents retain their collective
  intent. Requested zero disables hover trim; spool reaches exact zero and no
  recovery/translation force is injected afterward. Cold-gas torque remains.
- `pilot_frame()` isolates chest-forward hover/head-first flight coordinates. A
  bank-independent pitch projection and vertical-flow contribution blend its
  reference smoothly. The flight W/S pitch axis remains consistent through bank
  and inversion. A small DCS Su-27-inspired pitch envelope uses the measured angle
  of attack, the force-derived trajectory turn rate and 0.2 seconds of prediction
  to keep sustained powered pulls near ±30 degrees. It fades over 35–60 degrees
  of total misalignment and with Shift braking, so it cannot pull a deliberate
  upright combat slide back toward its velocity. Protection reaches full strength
  by 0.5× output and fades as the engines spool to zero. Underpowered climbing
  flight can still lose energy and stall. No attitude or velocity is assigned.
  Lift
  uses a calibrated 80 m² reference area at hero scale, 1.225 kg/m³ air, angle of
  attack and attached flow; pitch attachment stays full through 30 degrees and
  fades toward a stall at 65 degrees. Quadratic drag includes broadside area, induced drag,
  passive high-speed drag and Shift spread. Engine-off gliding and falling use
  these same equations; no velocity clamp supplies a terminal falling speed.
  Named feel parameters retain positive base Cd 0.075 plus 0.28 high-speed Cd.
  Engines spool at 3 hover multiples/s. Shift spread uses a 0.28 s critically
  damped response and 1.8 added Cd for a forgiving braking slide.
- R applies a 0.22-second sinusoidal contact-leg push with a 4 G peak only while
  suitable ground remains within 0.8 m of leg reach. It never changes main power or writes velocity. Native
  contact handles touchdown. This is one chassis capsule, not articulated limb
  collision. Pause commits the displayed native pose and preserves velocities
  for resume. G walking is an explicitly frozen preview, separate from normal
  takeoff and landing.
- The physical root attitude leads the pose. The visual language combines
  Hathaway's deliberate combat silhouettes, skydiver relative-wind responses and
  Titanfall's mechanical weight. Directional slides, backward bracing and rotating
  foot/hand counterbalance take their visual reference from
  [Armored Core VI's official movement footage](https://www.youtube.com/watch?v=64ChiBxhk4U&t=150s).
  The existing architecture remains
  [Overgrowth's authored poses with procedural corrections](https://www.gdcvault.com/play/1020583/Animation-Bootcamp-An-Indie-Approach).
  `flight_pose.gd` samples a read-only motion snapshot, blends five normalized
  posture anchors, and applies bounded servo/load responses. Hover, streamline,
  spread, coast and landing are weights, not flight-control modes. Posture changes
  retain servo velocity. Hover posing reads planned physical acceleration,
  including the braking push after release. The torso leans slightly over a
  leading/trailing leg pair; hands trail forward thrust and catch backward force.
  Inside/outside hands and knees exchange roles during sideways slides. Opposed
  thigh/knee offsets keep the lower-leg thrust axes nearly parallel. Relative
  airflow direction and pressure remain separate; freefall does not produce
  powered G-load compression. Legs retain bounded response times
  and joint speed limits in the rig profile. Pitch, yaw and roll intent lead the limbs before
  angular motion catches up. Turn direction, actual roll rate, roll release,
  angular acceleration and changing gravity orientation vary the poses.
  Retro bracing is measured from the dot product of actual thrust and existing
  velocity, not a new input mode. Saturated physical vectoring reduces additional
  articulation; actual nozzle cones and force capacities still apply.
  `arm_pose.gd` supplies direct shoulder/elbow/wrist joint poses to the full-body modifier. The supplied
  `GunPose` is sampled only for finger-curl calibration, then stopped. Neither
  hand follows a camera/weapon aim target. Inside/outside arms differ in a roll;
  release counterbalances the remaining spin. Braking opens both arms; reverse
  thrust gathers them forward. Bounded critically damped joint servos preserve
  continuity without idle swimming or a torso oscillator.
  No flight/hover/stall clips play. Imported clips remain for Animation dock
  preview and walking. Body/arm influence fades for walking; foot contact remains
  active. This model has no independently rigged binders. Movement, motors, pose
  and VFX pause together.
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
  pulses respond to bounded RCS torque. Main forces use actual motor directions;
  the cold-gas control couple uses the lumped actuator described above. Final
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

## Procedural pose ownership and tuning

The [flight animation contract](flight-animation-contract.md) defines the required
behaviors. The airborne rig uses one native modifier to write torso, arms,
wrists, fingers and legs. Arms use direct joint poses; there is no airborne arm
IK, elbow-pole solve, wrist post-pass or chain of completion signals.

The production reference is [Overgrowth's procedural animation approach](https://www.gdcvault.com/play/1020583/Animation-Bootcamp-An-Indie-Approach):
a compact authored pose vocabulary with directional joint corrections. Heavy
powered articulation takes its visual reference from [Titanfall's Titans](https://primagames.com/eguides/titanfall-eguide/behind-the-scenes/animation). These are adapted
visual principles; no unpublished game implementation is assumed.

| File | Owns |
| --- | --- |
| `flight_pose.gd` | Motion sampling, continuous behavior weights, load/flare/acceleration and one full-body pose application. |
| `arm_pose.gd` | Plain joint-pose data and servos, independent left/right shoulder, elbow, wrist and finger motion; completed limb geometry for diagnostics. |
| `contact_pose.gd` | Actual support, predicted preparation and platform-local stance plants; native foot IK operates only for support, then soles align and the completed pose is captured directly. |
| `aerial_mech.gd` | The native physical body, fixed-clock evaluation, actual animated thruster mounts and completed bone cache. |
| `mech_rig_profile.gd` | Bone names, joint-space pose extremes, limits and response speeds. Arm triples mean aft swing, outward elevation and elbow flexion in radians. |
| `pose_servo.gd` | Existing critically damped, speed-bounded response; no torso oscillator. |

Four native modifiers remain: full-body pose/ground-target preparation, two
support-only foot solvers, and final sole alignment/cache. In free flight only
the full-body pass authors limb poses; the foot solvers are inactive. The
full-body node keeps ground-target preparation running while its airborne pose
weight fades out over the retained walking animation. No native influence-zero
optimization can silently stop the walking target update.

Natural elbow clearance is authored directly. The upper arm opens away from the
ribs and the elbow flexes forward; an IK pole cannot force it behind the torso.
A held yaw/roll retains an asymmetric stroke as angular velocity develops.
Directional leg corrections run after all freefall/base blends, so a box pose
cannot overwrite the knee stagger. A small retained stance bias avoids perfectly
mirrored idle limbs; hover trim follows real control effort instead of a clock.

Broadside atmospheric falling holds elbows below/ahead of the shoulders, rotates
the upper arms externally to bend forearms toward the head, and folds the calves.
The pelvis leads the arch into the wind. Lengthwise airflow selects tracking. Falling still requires descent,
airflow and low main output; cutoff alone cannot manufacture a skydiver pose, and
vacuum descent cannot create aerodynamic body flight. Powered joints use slower
bounded response and hold the result; inertial offsets stay small and the torso
does not ring or sway after a command ends.

One shared flare value drives both hand opening and the leg squat. It responds
to Shift and loaded rapid deceleration; the G-load gate prevents ballistic gravity
from creating a false brace. Flare takes priority over reverse-thrust bracing.
As deceleration ends and delivered thrust drives outgoing acceleration, arms
sweep aft and knees lengthen toward cruise. Existing joint servos preserve
continuity on cancellation or renewed input. There is no maneuver state machine
or timer-driven gesture sequence: three smoothed effort values supply preparation,
reverse load and acceleration. The reported effort name is derived telemetry.

Physical support still owns plants. Two short rays prepare near-ground contact;
prediction alone cannot plant feet. A platform-local plant follows moving ground
and retains its last world position if the platform disappears. Native foot IK
limits extension, and sole tilt is capped at 0.5 radians. These visual contacts
operate over the same physical capsule; they add no suspension forces. Actual
30-degree gimbals and seated backpack/calf/heel outlets still produce the forces.
There are no hand boosters, weapon aiming, ragdoll bodies or velocity rewrites.

`test_air_pose.gd` measures displayed shoulders, elbows, hands and knees from the
completed skeleton, including held rotations and freefall. With a native renderer
it captures every fixture in three views and rejects blank renders. The contact
check covers landing, platforms, slopes and retained walking. Real input replays
include `flare_exit`: high-speed braking into a squat/wide-hand flare, then a
powered acceleration stroke and aerodynamic recovery in both review and gameplay
cameras. See [pose design and capture commands](poses/POSE_DESIGN.md).

F9 displays posture percentages, foot plants, probe count and impact strength.
Behavior and launch channels are recorded in the replay reports.
Use the rig profile to tune animation; flight-force tuning remains in the controller.

## Checks and comparison captures

`test_flight_controls.gd` runs 44 real-input sequences, including 24 sustained
W/S pulls across all four powered levels at 35, 70 and 110 m/s. It checks signed
travel/rotation, actuator reserve, release arrest, the hover hold interval and
distinct completed limb geometry. Native captures use the same timelines and solver.

```sh
godot --path demo --disable-render-loop --fixed-fps 60 --script res://aerial/tests/capture_mech.gd -- /tmp/aerial-mech
godot --headless --path demo --script res://aerial/tests/test_aerial_stack.gd
godot --headless --path demo --fixed-fps 60 --script res://aerial/tests/test_flight_pose.gd
godot --headless --path demo --fixed-fps 60 --script res://aerial/tests/test_procedural_pose.gd
godot --headless --path demo --fixed-fps 60 --script res://aerial/tests/test_animation_contract.gd
godot --headless --path demo --fixed-fps 60 --script res://aerial/tests/test_flight_controls.gd -- /tmp/flight-controls
godot --path demo --disable-render-loop --fixed-fps 60 --script res://aerial/tests/test_flight_controls.gd -- /tmp/flight-controls-native
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
`test_flight_pose.gd` steps actual native physics: held-key detents, six rotation
commands in upright/prone/inverted poses, settled hover, vacuum momentum while
rotating, transverse thrust, fast departure, unpowered lift, Shift braking,
skydiver drag, ground jump/contact, uninterrupted takeoff/cutoff/reorientation/
re-ignition, capsule collision, source-triangle thruster seating, gimbal limits,
completed arm geometry, free-hand motion, gun removal, pause and retained walking. Fixtures
alone may reset transforms/velocities; ordinary flight never does.

`capture_mech.gd` contains fixed native-key timelines for five flight behavior
families, plus isolated landing, braking, retro-thrust, steering/roll and endurance fixtures:

| Replay | Fixed input sequence and checks |
| --- | --- |
| `hover` | R leg push, two Space presses to 1×, short pitch/roll/yaw inputs, then neutral gyro/drift settling. |
| `fighter` / `inverted` | Powered bank rolls and pitch correction; separate inverted negative-AoA entry verifies upward lift. |
| `coast` | Zero main thrust; pitch/roll/yaw and release while atmospheric forces account for every velocity change. |
| `fall` | Unpowered descent, Shift spread/release/spread, then actual terrain contact. |
| `landing` | Upright drop onto a visible flat platform, planted soles, R jump and exactly one touchdown per landing. |
| `braking` | Main-off approach, Shift spread/release, two-arm opening, knee bracing and measured deceleration. |
| `retro` | Powered engines opposing existing travel, forward arm brace, then acceleration along the new facing. |
| `maneuvers` | Opposed roll commands, release/recovery and left/right yaw, with arm and knee asymmetry checks. |
| `bodyflight` | Unpowered broadside freefall, opposing yaw presses, roll and pitch/release; checks raised box arms and asymmetric steering strokes. |
| `transitions` | One uninterrupted hover → powered jet → upright braking slide → cutoff/reorientation → re-ignition/jet recovery. |
| `endurance` | 90 seconds at 4×; checks a stable terminal speed, released angular controls and a worst-pose drag energy ceiling. |

Fixtures set initial conditions once per replay. Timed inputs never rewrite
position, attitude or velocity. Each native physics tick checks finite state,
non-positive aerodynamic work and the applied-force momentum budget. Regressions
also limit jump/brake acceleration jerk and residual hover drift. Contact impulses are
excluded from flight smoothness limits. All reports include input timelines,
controller/driver hashes, sampled numeric telemetry, peaks and failures.

For fast automated checks and JSON telemetry:

```sh
godot --headless --path demo --fixed-fps 60 --script res://aerial/tests/capture_mech.gd -- /tmp/flight-replays
```

For native offscreen captures of those same inputs at 15 fps:

```sh
godot --path demo --disable-render-loop --fixed-fps 60 --script res://aerial/tests/capture_mech.gd -- /tmp/flight-replays-native
```

The replay owns its held-key snapshot and sends native key events through the
same game input handler. It uses the actor's existing replay-control field rather
than desktop-wide held-key polling, so window focus cannot release a synthetic
key midway through a maneuver. Gameplay input is unchanged. The native viewport
is 960×600 and the replay host stays minimized. Offscreen redraws do not advance
physics or present a window. Native input timelines therefore stay independent
of capture stride and GPU speed. `report.json` accompanies the ten rendered clips;
endurance records numeric telemetry without thousands of redundant screenshots.
`--metrics-only` suppresses images when using a native renderer. Run at the
project's existing 60 Hz physics rate; project settings are not modified.

Measured 4× equilibrium is approximately 140 m/s in the reference straight-flight
fixture. With 10,000 kg mass, 80 m² area and sea-level density, the minimum
high-speed Cd gives a conservative any-orientation bound near 168 m/s under
maximum thrust plus gravity. These are consequences of quadratic drag, not speed
clamps. Main-off momentum remains subject to actual gravity/lift/drag; the separate
vacuum check still proves that attitude torque cannot rewrite linear momentum.

These are desktop observations, not a device benchmark. The mech capture uses a native offscreen viewport at fixed 960×600 resolution
with its host window minimized. Captures explicitly request a native redraw so a frozen window
does not wait indefinitely for an automatic frame; a watchdog bounds failures. Headless mech runs
record physics telemetry without producing images. Shader validation requires rendered
frames, not the headless functional check alone. The separate soft-depth probe
renders two intersecting spheres and checks that the enabled material fades at
the floor while retaining the rest of its mesh. It saves `/tmp/dmc-soft-depth-probe.png`;
this path is verified on the current Mobile renderer.

### Flight animation contract validation

The [pose design and native Pose Studio](poses/POSE_DESIGN.md) provide 19 full-body
key poses and six editable motion studies. Run `pose_studio.tscn` to inspect the
silhouettes and timing separately from the physical gameplay replays below.
Runtime maneuver effort adds directional reverse/acceleration bracing, retained
left/right roles, independent hand expression and alignment-dependent cruise.
`test_maneuver_intent.gd` checks the temporal response; `capture_maneuver_intent.gd`
records reverse-through-zero, burst, interruption, turns, freefall and flare-to-flight with real
physics in both cameras. The study clips remain authoring references.

The contract-specific check covers normalized behavior weights, bounded transitions,
force-driven launch and recovery, quiet hover versus independent steering,
inverted fighter shape, thrust-cutoff continuity, start/coast/stop strokes,
vacuum exclusion, completed wrist articulation, box/arch, tracking, flare and
fast-stall exclusion. Existing flight/contact checks still validate the real body,
nozzle geometry, momentum budget, landing and retained walking.

Capture the five acceptance families in both close-up body-relative and the real
independent-look chase camera:

```sh
godot --path demo --disable-render-loop --fixed-fps 60 --script res://aerial/tests/capture_animation_contract.gd -- /tmp/animation-contract
```

Reports retain source hashes, inputs, behavior/posture weights, launch/track and
wrist channels. The two camera passes use identical inputs and native physics. The chase pass
sets one player-style orbit at each fixture, then uses the unchanged independent-look
camera. Rendering never evaluates a separate pose. `--metrics-only` skips frame output.
A head-first dive pitches into broadside falling and a flare. The uninterrupted
transition visits all four behavior influences; its recovery continuation cuts
thrust, retains aerodynamic coasting, then re-ignites without a fixture reset.

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
