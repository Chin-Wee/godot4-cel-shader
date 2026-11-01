# Mech flight animation contract

Status: implementation contract, 1 November 2026. Runtime evidence and commands are documented in README.md.

## Required behaviors

1. Ground jump into upright, gyro-stabilized helicopter-like flight. Grounded
   legs supply the push; powered low-speed support catches ascent. Animate pelvis,
   chest, both arms and legs, with feasible heel/calf/backpack thrust alignment.
   In powered hover, the first three seconds of each WASD press supply directional
   thrust with the chassis upright; continued holding gradually introduces tilt.
   Forward/backward/sideways slides and yaw use Armored Core VI as a visual
   reference, including complementary hand and leading/trailing leg roles.
2. Powered fighter-like flight in any orientation. The chassis provides lift;
   streamlined posture follows useful airflow, not world-up. Bank, pitch and yaw
   have deliberate full-body initiation, sustained effort and recovery.
   W pitches down and S pulls up through bank/inversion. Powered aligned pulls
   receive soft ±30-degree airflow pitch protection. Shift permits an intentional
   departure; large misalignment cannot trigger forced trajectory alignment.
   The guard covers all powered detents; it does not provide stall immunity when
   an underpowered climb loses airspeed. Full-output leg posture keeps actual
   engine moments within the existing cold-gas capacity.
3. Main engines off: rotate freely while retaining existing travel. Cold-gas
   attitude control supplies actual torque. Compact preparation and arrest poses
   express the maneuver; neither pose nor orientation rewrites velocity. Gravity
   and atmospheric forces remain active.
4. Atmospheric falling: depict skydiver body flight. Relative wind, broadside
   exposure, downward travel and braking progressively establish arch/box, track,
   flare or recovery. Both shoulders/elbows, wrists, pelvis and legs participate.
5. Transitions remain continuous. Thrust cutoff alone must not cause an instant
   spread pose; a fast stall must not trigger upright hover posing/braking.
   Preserve joint/spring velocities and actual body momentum across transitions.

## Recommended architecture

Use one full-body SkeletonModifier3D for airborne joint poses. arm_pose is plain
data consumed by that pass. Native foot IK is limited to ground support; no arm
IK/pole/wrist post-processing chain is used. Production references: Overgrowth's
authored procedural joint animation and Titanfall's deliberate heavy articulation.

Use a small contact/action state machine only for real support, launch and landing
phases. Airborne behavior uses continuous posture weights, not four exclusive
animation states or manual modes. Propulsion/support/alignment select the base;
relative wind, descent and brake intent supply aerodynamic shape; pilot request
and measured angular rate supply deliberate start/coast/stop strokes. Smaller
load/acceleration responses follow afterward. Directional leg corrections must
survive freefall blending. One shared loaded flare must produce a squat and
outward hand spread before transitioning to aft acceleration arms and cruise.
Capture the completed pose inside the final native pass, after optional ground
foot correction. One physical body remains movement authority.

Skydiver reference: USPA Category D start-coast-stop turns and APF Basic Body
Flight. Apply those cues chiefly to air-loaded falling and aerodynamic maneuvers;
do not apply one skydiver arm gesture equally to hover, fighter flight and coasting.

Keep contact rays near plausible ground interaction. Feet plant only on real
support. Preserve mechanical joint limits, nozzle seating and gimbal ranges.
No hand boosters or weapon aiming. Reserve physical ragdoll for a separately
scoped impact/incapacitation feature; normal piloting uses critically damped,
speed-bounded powered joints. Do not add idle swimming or torso spring ringing.
In broadside freefall, elbows stay below/ahead of the shoulders and externally
rotated upper arms fold forearms toward the head. Hands must not be raised by
lifting nearly straight arms overhead.

## Visual acceptance

Review jump/hover, banked/inverted powered flight, cutoff with independent
rotation/travel, spread-versus-track falling, and an uninterrupted combined
transition sequence. Review both close-up body-relative and normal chase views.
Active body preparation should read before acceleration/rate develops; passive
lag must remain secondary. Numeric flight checks alone cannot establish pose quality.

References:
- https://www.gdcvault.com/play/1020583/Animation-Bootcamp-An-Indie-Approach
- https://primagames.com/eguides/titanfall-eguide/behind-the-scenes/animation
- https://www.uspa.org/uspa-news/foundations-of-flight-neutral-body-position
- https://www.uspa.org/skydiveschool/d
- https://www.apf.com.au/members/members/publications/misc-publications/basic-body-flight-for-b-rels-and-beyond
