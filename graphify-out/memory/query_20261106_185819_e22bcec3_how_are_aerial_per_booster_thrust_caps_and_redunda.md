---
type: "query"
date: "2026-11-06T18:58:19.764202+00:00"
question: "How are aerial per-booster thrust caps and redundant opposing burns handled?"
contributor: "graphify"
outcome: "corrected"
correction: "Replaces mass-scaled six-engine capacity assumptions with ten fixed-Newton main caps and twelve fixed-Newton cold caps; reachable cold allocation sheds redundant counter-thrust."
source_nodes: ["demo_aerial_readme_run_and_controls", "demo_aerial_flight_animation_contract_required_behaviors"]
---

# Q: How are aerial per-booster thrust caps and redundant opposing burns handled?

## Answer

Source authority: integration commit 722313e, feature 3c84e40.

The aerial demo now has ten main boosters: the existing back/calf/heel pairs and two added forefoot modules per foot. Both foot armor and inner foot mesh faces were inspected in MechAsset.glb; selected exposed sidewall points at y=0.8,z=0.15 are seated on source triangles and clear the measured sole. The existing GLB and native procedural nozzle geometry are retained.

mech_rig_profile.gd exports per-index main_booster_max_thrust (ten defaults of 65000 N) and cold_booster_max_thrust (twelve defaults of 90000 N), ordered by aerial_mech MOUNTS and COLD_MOUNTS. These fixed hardware ratings do not scale with mass, detent or Quick Boost. Zero disables an individual outlet. Controller helpers convert ratings to normalized body-weight units for the existing allocator; actual native point forces and exhaust use each nozzle's own rating. The warm reset seed respects caps; added foot motors start closed and retain finite ignition. All runtime loops and cold socket offsets use the actual main count.

The existing Star Citizen placed-thruster / native Schur-block allocation architecture is reused. Reachable cold ports retain a fuel penalty of 0.03 and no quadratic preference for redundant horizon flow. Hot gimbals keep the existing preference. Necessary torque couples and unavoidable valve shutdown tails remain physical. Default reachable solves use 64 bounded sweeps for the added actuator set. All hot/cold ignition, restart, minimum burn, rise/fall, and native force-only motion constraints remain intact.

Validation includes direct allocator checks for redundant counter-jets, necessary pure-torque couples, and unavoidable shutdown flow; per-booster over-demand, unequal/zero ratings and mass-independence checks; all signed cold rotation axes; cardinal/diagonal/heading-relative bursts under the existing cross-axis, chassis-tilt and jerk thresholds; quiet-hover fuel duty and visual force agreement. Native Godot pose captures were inspected for the new foot mounts. The fixture copies PackedFloat32Array ratings explicitly to avoid leaking custom disabled hardware into subsequent checks. Production control axes remain A/D roll and Q/E yaw, with normal pitch/roll during the half-second tap burst and finite one-second cooldown. PhantomCamera behavior is unchanged.

Integration validation: python3 tools/check_godot.py passed all 25 runs on main, including PhantomCamera at 30/144/240 FPS. Logs: /tmp/booster-caps-main-validation.log; replay metrics: /var/folders/y9/zgzbjttn0v10ym8cc4h1tm9h0000gn/T/godot-checks-2l95z2y2. Structural Graphify update completed; installed parser does not index GDScript AST, and the existing semantic-refresh-needed marker remains honest about the unsupported semantic adapter.

## Outcome

- Signal: corrected
- Correction: Replaces mass-scaled six-engine capacity assumptions with ten fixed-Newton main caps and twelve fixed-Newton cold caps; reachable cold allocation sheds redundant counter-thrust.

## Source Nodes

- demo_aerial_readme_run_and_controls
- demo_aerial_flight_animation_contract_required_behaviors