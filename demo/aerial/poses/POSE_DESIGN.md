# Flight pose design

The new pose vocabulary gives each action a readable silhouette before adding
load response. The production architecture reference remains **Uncharted 4**:
deliberate animation with controlled physical secondary motion, using the existing
procedural rig and native Godot IK. The [flight animation contract](../flight-animation-contract.md)
still defines movement authority and the five required behaviors.

## Key poses

| Action | Keys | Full-body intent |
| --- | --- | --- |
| Ground launch | Ready Coil → Launch Push → Hover Catch | Compress pelvis and knees, extend the legs, then collect the forearms and absorb the catch through chest and knees. |
| Upright support | Hover Support | Bent elbows with hands ahead of the armor, soft knees and restrained trim. Avoid hanging both arms straight down. |
| Powered flight | Flight Pierce → Flight Sustain | Lead into the attitude, sweep both hands behind the torso, lengthen the legs and keep the chassis compact. |
| Banking | Bank Left / Right | Gather the inside arm and extend the outside arm along a diagonal; chest leads and legs follow. |
| Independent rotation | Coast Gather → Coast Arrest → Coast Settle | Collect the limbs to initiate, make an opposing stroke to arrest rotation, then relax without reversing the attained chassis attitude. |
| Atmospheric fall | Fall Box / Turn Left / Turn Right | Arch the chest and hips, fold the calves upward, open hands and use asymmetric shoulder/forearm pressure to turn. |
| Tracking | Track | Lengthen the legs and sweep the arms back to reduce the broadside silhouette. |
| Braking | Brake Flare | Spread hands above shoulder height, open fingers, bend knees and present more area to the wind. |
| Reverse thrust | Retro Brace | Bring forearms forward, gather fingers and brace chest/hips against the delivered acceleration. |
| Landing | Landing Guard → Landing Absorb | Prepare ahead of contact, then compress on real support and recover through pelvis, chest, arms and legs. |

## Motion and response

### Directional maneuver effort

Gameplay now composes directional corrections rather than cycling the study
clips. The production references are Overgrowth's compact authored poses with
procedural adaptation and Uncharted 4's controlled secondary motion:

- https://www.gdcvault.com/play/1020583/Animation-Bootcamp-An-Indie-Approach
- https://www.gdcvault.com/play/1024087/Physics-Animation-in-Uncharted-4

`flight_controller.gd` publishes its existing requested main-force vector before
spool/cone limits, alongside delivered propulsion, velocity, aerodynamic force
and angular intent. This is telemetry; animation does not calculate or apply a
second set of movement forces. `flight_pose.gd` interprets these in body space.

One small effort history distinguishes prepare, load, sustain and release.
Rising throttle prepares the hands during spool-up. Opposing thrust establishes
a coupled hip/knee/ankle squat and forward arm brace. The brace releases as the
opposed travel component disappears, even if lateral travel remains. Outgoing
acceleration opens an aft arm stroke and retains a shallower knee compression.
As acceleration settles, the mech lengthens toward cruise despite continued high
engine output. Canceling or redirecting input retargets the existing moving pose;
there are no queued clips, fixed-duration commitments or velocity writes.

Signed transverse thrust, load and turn intent choose a lead side. A short
deadband/hysteresis retains it through zero speed and exactly opposing vectors.
The two hands, elbow paths, wrists, fingers and knees take complementary roles.
Oblique airflow adds directional deformation. Powered symmetric tracking grows
with heading/thrust/travel alignment; unpowered tracking remains possible along
either end of the body. Quiet hover keeps its calibrated leg support and small
trim. Fixed world-up roll offsets were removed from the arm targets because they
could oppose the commanded stroke during inversion.

The primary arm posture has an explicit remaining-weight budget: landing,
reverse load, aerodynamic braking/box, acceleration, tracking, then neutral.
Steering and secondary balance correct that posture. Preparation supplies an
outward clearance arc before the aft stroke. Existing calibrated elbow poles,
soft reach, joint/hand limits and actual 30-degree gimbals remain authoritative.
Coupled leg flexion preserves the calf/heel thrust line; saturated motors reduce
extra articulation. Hover drift damping is 3.6 (previously 3.2) to settle the
moving-port transient within the same bounded force allowance.

Validate the temporal response and record actual input-driven motion:

```sh
godot --headless --path demo --fixed-fps 60 --script res://aerial/tests/test_maneuver_intent.gd
godot --path demo --disable-render-loop --fixed-fps 60 --script res://aerial/tests/capture_maneuver_intent.gd -- /tmp/maneuver-intent
```

The capture covers an oblique reverse through zero, a 2-to-4-times-hover burst,
cancel/re-ignition, and opposing turns in body and chase cameras. Reports include
effort phase, lead side, force vectors, alignment, independent fingers, gimbal
angles and actuator demand. Reverse/burst checks require the real attitude
actuators to stay within capacity and the actual gimbals within their cones.

### Authored study timing

The six native motion studies cover launch, forward flight/banks, braking/reverse
thrust, coast/arrest, skydiving and landing. Each includes preparation, action and
settling rather than interpolating between two held poses. At interior keys the
head leads by 60 ms, shoulders by 40 ms, hands follow by 20 ms and legs by 70 ms;
launch legs lead by 40 ms. Pelvis/waist settle 40 ms later. The deliberate landing
compression is quicker than the longer recovery.

Gameplay keeps continuous behavior weights and the existing velocity-preserving
springs. Animation now reads the pilot request before the physics command filter,
so brief inputs start a visible stroke before angular velocity develops. Arms
respond faster, roll diagonals are larger, and the chest/head lead is stronger
while coasting or falling. Hands can gather in front of the chest or sweep aft,
with the calibrated elbow hinge and armor-clearance bounds retained.

Powered torso and leg motion remain restrained by the six real nozzle mounts and
their 30-degree gimbals. Falling gets its own calf-folded shape, separate from the
powered braking brace. Quiet hover trim remains small; input-driven movement,
airflow, acceleration and real contact provide variation instead of random sway.

## Native Pose Studio

Open `res://aerial/pose_studio.tscn` and run the scene. Left/right selects a clip,
Space pauses, R restarts and 1/2/3 chooses three-quarter/front/side views. Select
`PosePlayer` to inspect the `design` library in Godot's Animation dock. `K_` clips
hold the 19 keys; `M_` clips contain the six motion studies.

This is a **frozen-chassis authoring study**. Its keyed visual attitude makes prone
flight and falling legible under neutral lighting. Gameplay attitude and travel
remain owned by the rigid body; these presentation clips are not played over it.
Gameplay uses the updated pose anchors and response logic in the existing rig.

Regenerate the editable library from the real rig after changing the design:

```sh
godot --headless --path demo --script res://aerial/poses/bake_pose_library.gd
godot --path demo res://aerial/pose_studio.tscn
godot --path demo --fixed-fps 60 --disable-render-loop --script res://aerial/tests/capture_pose_studio.gd -- /tmp/flight-key-poses
```

The capture check exports every key in three views, samples the six studies at
30 fps and verifies actual skeleton deformation. Use the separate physical
contract replays for movement/contact validation and gameplay-camera review.
