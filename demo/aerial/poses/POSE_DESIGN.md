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
  as the visual reference: a modest committed torso lean, leading/trailing knees,
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
- Air braking: Shift or loaded rapid deceleration drives one shared flare value.
  Knees squat while hands spread outside the shoulders. Flare wins over reverse
  bracing, which previously consumed its blend weight. The G-load gate excludes
  ballistic gravity from the deceleration response.
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

`pose_studio.tscn` retains 19 static key references and six native AnimationPlayer
studies. Select PosePlayer for the Animation dock. Arrow keys select clips,
Space pauses, R restarts, and 1/2/3 changes views. Rebuild that library with:

```sh
godot --headless --path demo --script res://aerial/poses/bake_pose_library.gd
```

Those frozen-chassis studies include a presentation attitude and remain separate
from physical gameplay. The library is regenerated from the current rig; the
live input replays provide the evidence for continuity and movement.
