# Flight pose design

The runtime uses one full-body pose writer. Production references are
[Overgrowth](https://www.gdcvault.com/play/1020583/Animation-Bootcamp-An-Indie-Approach)
for compact authored joint poses with procedural corrections and
[Titanfall's Titans](https://primagames.com/eguides/titanfall-eguide/behind-the-scenes/animation)
for deliberate heavy articulation. These are adapted visual principles, not
claims about unpublished game internals. The [flight animation contract](../flight-animation-contract.md)
defines the movement and visual requirements.

## Ownership

`flight_pose.gd` samples physics, builds the common flare/load/acceleration values,
and applies torso, arm, wrist, finger and leg joints in one native modifier.
`arm_pose.gd` is plain joint data with bounded servos. It creates no modifiers,
IK solvers, target nodes, elbow poles or completion callbacks. Its arm triples
are radians: aft swing, outward elevation and elbow flexion. The separate box
twist rotates the humerus about its own longitudinal axis after arm placement;
skeleton-space yaw cannot substitute for this external rotation.

Two native foot solvers remain for real support and the walking preview. Ground
target preparation runs in the full-body pass even after the airborne weight
fades to zero. Final sole alignment captures the completed bones directly while
they exist; no chain of modifier signals or restored-rest readbacks is involved.
There are four native modifiers, compared with the previous eight.

The imported Walk also animates the intermediate Shin bone. During stance this
returns toward rest because native two-bone IK represents Knee-to-Feet as one
virtual segment. Swing animation remains authored. A ray under a raised swing
foot cannot create a new plant. Unreachable foot targets retain mechanical reach
limits rather than stretching the skeleton.

## Motion language

- Hover: upper arms clear the ribs and elbows bend forward. Small corrections
  follow real attitude-control effort; a stable chassis holds its pose instead
  of swimming to a clock-driven cycle.
- Directional hover slides use [Armored Core VI](https://www.youtube.com/watch?v=64ChiBxhk4U&t=150s)
  as the visual reference: a 20–25 degree committed torso lean, leading/trailing knees,
  different inside/outside arm roles, and ankle preparation for the actual push.
  Hands trail forward thrust and catch backward force. The planned acceleration
  includes the braking push on release, so posture follows physical intention
  instead of continuing to lean into the old travel. Yaw offsets both hips and
  retains an asymmetric knee/hand counterbalance. This adds corrections to the
  same full-body writer; it adds no animation mode or post-processing pass.
  The controller exposes the unfiltered translation request before its force
  smoothing. This starts upper-body preparation without waiting for velocity or
  acceleration. One leg gathers with an additional 0.50 rad of coupled hip/knee
  flexion; the opposite leg extends by 0.18 rad. Lateral intent selects the raised
  knee; longitudinal movement retains the preceding lead side. Diagonals use
  the lateral component and a normalized strength. Existing joint servos carry
  their velocities through reversals rather than snapping or restarting a clip.
  On release, the actual hover braking request drives the opposing catch. With
  neither input nor braking effort, the pose settles into quiet support.
- Full-power stream uses paired hip/knee tuck to move the actual leg outlets
  toward the mass centre. Directional hover replaces this tuck; reverse pushes
  sweep the calves forward with ankle counter-rotation. The rig profile exposes
  both offsets. This preserves the existing nozzle cones and cold-gas capacity.
- Held yaw/roll: hands and knees retain complementary positions after angular
  velocity reaches the requested rate. Bank adds a stronger inside-leg gather;
  yaw uses a smaller twisting stagger with opposing hands. Release produces a
  counterstroke. Powered pitch adds symmetric compression for a pull-up and
  extension for a push-over, over the direction-dependent bank/yaw corrections.
- Freefall: use the [USPA neutral body position](https://www.uspa.org/uspa-news/foundations-of-flight-neutral-body-position):
  hips press into the wind, elbows stay below and slightly ahead of the shoulders,
  bent forearms place open hands near the head, and calves fold behind the body.
  External shoulder rotation establishes the elbow hinge plane; simply raising
  the upper arms produces the wrong silhouette. Directional corrections survive
  base/freefall blends. Lengthwise flow permits a tracking shape.
- Air braking: Shift changes armor incidence according to pitch, yaw and roll
  input. The outside arm opens while the inside arm gathers; pitch presents both
  forearms and changes chest/knee incidence. Without Shift, powered steering
  keeps compact weight transfer and shallow panels below the braking projection
  threshold. Shift or loaded deceleration during braking/reverse thrust drives one shared flare value.
  Knees squat while hands spread outside the shoulders. Flare wins over reverse
  bracing, which previously consumed its blend weight. The G-load gate excludes
  ballistic gravity from the deceleration response. The raw Shift request starts
  pose preparation before the aerodynamic brake finishes ramping; after release,
  the remaining delivered brake smoothly carries the pose back toward cruise.
- Acceleration: as braking ends, the brace unwinds, hands sweep aft, and the
  knees lengthen toward aerodynamic cruise as acceleration settles. Existing
  servos preserve continuity through cancellation and re-ignition. Throttle
  preparation has a stronger shoulder contribution before output finishes
  spooling. Side slip, turn direction and the retained lead side vary the brace.

Powered joints use the existing critically damped response with finite angular
speed. Arms reach at up to 1.8 rad/s, with 0.30/0.34 s shoulder/elbow response;
legs use 0.32/0.38/0.42 s response. The torso has no underdamped oscillator or
repeated settling bounce. Inertial torso/arm offsets and leg load compression
are restrained so purposeful brace/steer poses dominate passive motion. Head,
chest and pelvis remain coordinated instead of whipping around independently.

A retained lead side and a small stance bias keep the limbs from being exact
mirror copies. Thrust, airflow and turn intent increase that asymmetry. Three
smoothed effort values supply preparation, reverse load and acceleration; there
is no maneuver state machine or timer-driven gesture sequence. Movement, real
animated thruster mounts, 30-degree gimbals and force limits remain physical.
Coupled flexion is clamped against both the hip and knee limits before either
target is applied. Independently clipping a hip would otherwise leave the knee
rotating a loaded calf nozzle. At 4x output, the extra gathering stroke retains
45% strength to leave attitude-control reserve. Launch and landing suppress the
hover gesture so real ground support retains priority. `slide_knees`,
`slide_lean` and `slide_response` in the rig profile calibrate the silhouette.

## Physical body-flight coupling

Torso, forearms and calves supply five aerodynamic panels sharing one total
reference area. Their completed bone orientation and position determine native
point forces; local airflow includes angular velocity. This follows Microsoft
Flight Simulator 2020's distributed-surface principle at a deliberately small
proxy scale. Corrected skeleton-axis conversion makes a pull-up prepare into the
turn. Opposing forearm pressure and differential calf incidence supply signed
yaw/roll moments. The controller tries a balanced hot-only allocation first, then asks cold gas
for the remaining moment; air control does not merely hide RCS effects.

The profile exposes panel fractions/incidence and slide lean for calibration.
Powered joint servos, mechanical limits, planted feet and the fixed capsule
remain authoritative. No extra animation writer or physical limb bodies are added.

## Banks, rolls and somersaults

The existing Overgrowth-style pose writer adds corrections from real signed
pitch/roll travel. Native angular velocity advances that travel; holding input
against blocked motion can prepare a swing but cannot animate an inversion.
The profile's `maneuver_shape()` shares one normalized swing/tuck/open envelope:
long through 35°, gathering toward 140°, compact through 260°, then opening
through the last quarter. Its endpoints match across successive revolutions.

Banks retain their normal physical rate while shoulders and pelvis twist in
opposition over inside/outside knee and hand roles. After 55–140° of sustained
roll travel, the long bank blends into a compact, asymmetric corkscrew. Opening
reverses the arm/leg roles. The pilot-frame blend remains fixed until roll input
releases and measured roll rate falls below 0.15 rad/s.

Backflips open the chest and reach before a long-leg swing and leading knee
bring the pelvis into inversion. Frontflips fold the chest and sweep the hands
aft before compacting; they use different swing targets rather than a reversed
clip. Both then extend the legs and reach outward. The visual cue is the long
swing, inversion and extension of [pole vaulting](https://worldathletics.org/disciplines/jumps/pole-vault),
adapted to powered mechanical joints rather than a simulated pole.

Release/reversal requests an opening counterstroke immediately, independent of
remaining turn angle. Compound pitch/roll corrections share one blend budget.
Landing and leg launch suppress them; Shift retains a wide braking contribution.
The same joint limits and critically damped, speed-bounded servos apply afterward.
No pose writer, ragdoll, motion clip controller or extra inverse-kinematic pass
is added. The actual completed limbs still determine air panels and main outlets.

## Verification and authoring

```sh
godot --headless --path demo --fixed-fps 60 --script res://aerial/tests/test_air_pose.gd
godot --path demo --disable-render-loop --fixed-fps 60 --script res://aerial/tests/test_air_pose.gd -- /tmp/air-pose-geometry
godot --path demo --disable-render-loop --fixed-fps 60 --script res://aerial/tests/capture_maneuver_intent.gd -- /tmp/air-pose-motion
```

The geometry check reads displayed shoulders, elbows, hands and knees from the
completed skeleton. It tests held rotations, freefall asymmetry, squat/hand flare,
acceleration and cruise, checks the modifier count, and rejects blank native
captures. The real input replays record reverse, burst, interruption, opposing
turns, body flight and a complete `flare_exit` in body and gameplay chase views.
Reports use completed hand positions and geometric knee flexion, not IK targets.

`pose_studio.tscn` retains 45 static key references and fourteen native AnimationPlayer
studies. Select PosePlayer for the Animation dock. Arrow keys select clips,
Space pauses, R restarts, and 1/2/3 changes views. Rebuild that library with:

```sh
godot --headless --path demo --script res://aerial/poses/bake_pose_library.gd
```

Those frozen-chassis studies include a presentation attitude and remain separate
from physical gameplay. The library is regenerated from the current rig; the
live input replays provide the evidence for continuity and movement.

## Research adaptation and head intent

See the [behaviour mapping](../README.md#research-mapped-to-the-current-behaviours)
for sources and calibration limits. Belly and back presentation use signed
relative wind, with separate arm, hip/knee and head targets. Extended layouts
blend with compact flips from air pressure and effective-rate tracking error,
without changing physical inertia. Unpowered air-loaded banks retain their
loaded silhouette. Extra braking drag follows completed arm projection; release
cannot feed deceleration back into a permanently latched flare.

The existing neck servo now leads turn intent and accepts independent vision
intent relative to the completed torso. Uncharted's additive/look-at layering
is the production reference; this adaptation uses the neck alone. Bounds and
speed are rig-profile values. Head scanning never moves aerodynamic panels,
thruster hardpoints, camera or the chassis. There is no idle neck oscillator.

Pose Studio adds Back_Fall, front/back extended swing/inversion/opening, four
head-look keys, and Belly_Back_Recovery / Extended_Layouts / Head_Scan studies.
The same joint limits/servos generate these references and the runtime pose.
