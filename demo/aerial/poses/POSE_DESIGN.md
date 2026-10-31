# Flight pose design

The runtime uses one full-body pose writer. Production references are
[Overgrowth](https://www.gdcvault.com/play/1020583/Animation-Bootcamp-An-Indie-Approach)
for compact authored joint poses with procedural corrections and
[Uncharted 4](https://www.gdcvault.com/play/1024087/Physics-Animation-in-Uncharted-4)
for controlled secondary motion. The [flight animation contract](../flight-animation-contract.md)
defines the movement and visual requirements.

## Ownership

`flight_pose.gd` samples physics, builds the common flare/load/acceleration values,
and applies torso, arm, wrist, finger and leg joints in one native modifier.
`arm_pose.gd` is plain joint data with bounded servos. It creates no modifiers,
IK solvers, target nodes, elbow poles or completion callbacks. Its arm triples
are radians: aft swing, outward elevation and elbow flexion.

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

- Hover: upper arms clear the ribs, elbows bend forward and a small alternating
  trim keeps the pose alive. An elbow pole cannot pull elbows behind the torso.
- Held yaw/roll: hands and knees retain complementary positions after angular
  velocity reaches the requested rate. Release produces a counterstroke.
- Freefall: broadside airflow raises open forearms toward head level and folds
  calves. Directional leg corrections run after base/freefall blends so the box
  pose cannot erase them. Lengthwise flow permits a tracking shape.
- Air braking: Shift or loaded rapid deceleration drives one shared flare value.
  Knees squat while hands spread outside the shoulders. Flare wins over reverse
  bracing, which previously consumed its blend weight. The G-load gate excludes
  ballistic gravity from the deceleration response.
- Acceleration: as braking ends, the brace unwinds, hands sweep aft, and the
  knees lengthen toward aerodynamic cruise as acceleration settles. Existing
  servos preserve continuity through cancellation and re-ignition.

A retained lead side and a small stance bias keep the limbs from being exact
mirror copies. Thrust, airflow and turn intent increase that asymmetry. Three
smoothed effort values supply preparation, reverse load and acceleration; there
is no maneuver state machine or timer-driven gesture sequence. Movement, real
animated thruster mounts, 30-degree gimbals and force limits remain physical.

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
