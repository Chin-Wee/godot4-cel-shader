# Mech flight animation contract

Status: implementation contract, 3 November 2026. Runtime evidence and commands are documented in README.md.

## Required behaviors

1. Ground jump into upright, gyro-stabilized helicopter-like flight. Grounded
   legs supply the push; powered low-speed support catches ascent. Animate pelvis,
   chest, both arms and legs, with feasible heel/calf/backpack thrust alignment.
   Pitch/roll responds immediately. A powered hover direction tap adds a
   0.5-second directional burst at 4× hover thrust, with a one-second cooldown
   from activation. Release retains the burst direction; held or early taps do
   not repeat or queue it. Engine cutoff cancels it through the short force fade. The selected cruise detent
   remains independent; short force ramps and existing servos smooth delivery.
   Forward/backward/sideways slides and yaw use Armored Core VI as a visual
   reference, including complementary hand and leading/trailing leg roles.
   Directional intention starts body preparation before acceleration. One knee
   visibly gathers while the opposite leg stays longer; diagonal movement and
   reversal exchange these roles smoothly. Release follows actual braking effort,
   while an unloaded release returns to quiet hover without a fabricated catch.
2. Powered fighter-like flight in any orientation. The chassis provides lift;
   streamlined posture follows useful airflow, not world-up. Bank, pitch and yaw
   have deliberate full-body initiation, sustained effort and recovery.
   W pitches down and S pulls up through bank/inversion. A/D always commands
   longitudinal aircraft roll; Q/E always commands aircraft yaw. Upright space
   motion and plane flight share those same body-relative axes, without an
   automatic posture/airspeed remapping (Elite Dangerous reference). Powered aligned pulls
   receive soft ±30-degree airflow pitch protection. Shift permits an intentional
   departure; large misalignment cannot trigger forced trajectory alignment.
   The guard covers all powered detents; it does not provide stall immunity when
   an underpowered climb loses airspeed. Full-output leg posture keeps actual
   engine moments within the existing cold-gas capacity. Completed torso/limb
   poses must also generate correctly signed aerodynamic pitch, yaw and roll
   through actual point forces. Main vectoring trims the combined moment before
   cold gas supplies the remainder; airspeed alone never disables attitude control.
3. Main engines off: rotate freely while retaining existing travel. Cold-gas
   attitude control supplies actual torque. Air-load/rate-error-dependent compact or extended preparation and arrest poses
   express the maneuver; neither pose nor orientation rewrites velocity. Gravity
   and atmospheric forces remain active.
4. Atmospheric falling: depict skydiver body flight. Relative wind, broadside
   exposure, downward travel and braking progressively establish arch/box, track,
   flare or recovery. Signed relative wind distinguishes belly and back silhouettes. Both
   shoulders/elbows, wrists, pelvis, head and legs participate.
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

## Dynamic rotation requirements

Preserve existing controls and powered pitch protection. Engine-off or Shift
braking permits full front/back flips with a 1.95 rad/s request ceiling and the
existing finite torque limit. Target 3.3–4.5 seconds per clean low-airload flip
after the slower-pitch tuning.
Actual rotation drives preparation, swing, inversion and opening; blocked motion
cannot advance a turn. Front/back swing targets must differ. Full rolls need
shoulder/pelvis opposition, staggered arms/legs, compact corkscrew and opening;
a captured bank must remain a loaded, offset pose rather than a continuous tuck.

Holding permits repeated turns without a pose reset. Release/reversal must
interrupt at any angle. Preserve joint velocities, normalize simultaneous
pitch/roll correction strength, and give landing/leg launch priority. Keep Shift
braking visible. Reuse the current native body, point forces, pose writer and
joint servos; no direct velocity/attitude edits or simulated tuck inertia.

## Visual acceptance

Review jump/hover, banked/inverted powered flight, cutoff with independent
rotation/travel, spread-versus-track falling, and an uninterrupted combined
transition sequence. Review both close-up body-relative and normal chase views.
Active body preparation should read before acceleration/rate develops; passive
lag must remain secondary. Numeric flight checks alone cannot establish pose
quality. Include staged
bank → capture/release → pull-up → release, overlapping input, cancellation and
reversal at 2×/4×. Four directional hover slides need 20–25 degree torso lean
and complementary knee/hand roles. Full-power sideways travel must retain yaw
stability and finite torque reserve; both camera views must keep the mech framed.

References:
- https://www.gdcvault.com/play/1020583/Animation-Bootcamp-An-Indie-Approach
- https://primagames.com/eguides/titanfall-eguide/behind-the-scenes/animation
- https://www.uspa.org/uspa-news/foundations-of-flight-neutral-body-position
- https://www.uspa.org/skydiveschool/d
- https://www.apf.com.au/members/members/publications/misc-publications/basic-body-flight-for-b-rels-and-beyond

## Research body-flight requirements

Steering feedback uses the effective protected/flip-scaled pilot-local rate,
not the nominal MAX_RATE. Engine-off air load must retain bank expression even
with detached flow. Actual completed limb projection supplies extra braking
drag; the key alone cannot change force before geometry moves. Deceleration
after release cannot self-latch a flare. Extended layouts require useful air
support and low unmet rotation demand; compact alternatives remain in vacuum.

The head anticipates turns, adjusts for belly/back/tracking presentation and
accepts independent camera vision intent. Preserve bounded mechanical neck
angles/speed, quiet settling, body momentum and camera independence. Head look
must not move control panels or nozzles. Keep the existing single pose writer;
use Uncharted's additive/look-at approach as the production reference for this
neck-only correction. Research sources and calibrated-model limitations live
in README.md; no footage-derived parameter fit is claimed.
