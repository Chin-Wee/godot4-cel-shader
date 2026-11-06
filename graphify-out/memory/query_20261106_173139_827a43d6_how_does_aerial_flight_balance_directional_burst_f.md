---
type: "query"
date: "2026-11-06T17:31:39.603082+00:00"
question: "How does aerial flight balance directional burst forces and minimize cold-gas use?"
contributor: "graphify"
outcome: "corrected"
correction: "Joint hot/cold allocation and demand-driven fixed RCS replace the fixed 4x burst and recurring trim schedule."
source_nodes: ["demo_aerial_readme_run_and_controls", "demo_aerial_flight_animation_contract_required_behaviors"]
---

# Q: How does aerial flight balance directional burst forces and minimize cold-gas use?

## Answer

# Balanced aerial thrust and directional braking

Validated source revision: `437406fd3a54427d58789d02ff34627a529a54e3` on main. Source is authoritative; this corrects the older fixed-4x/clock-driven-RCS descriptions.

## Force allocation

`demo/aerial/flight_controller.gd::_calculate_thrusters` jointly allocates six hot and twelve fixed cold outlets. Desired net acceleration accounts for gravity and posed-surface air forces; desired moment accounts for the actual air moment. `thruster_allocator.gd` reuses native 3x3 force/moment blocks and bounded projection. Fixed cold jets have one pressure degree of freedom. A horizon chooses attainable force, then the next-tick solve accounts for reachable gimbals and predicted valve impulse. Only actual nozzle/panel point forces move the native rigid body.

The burst command lasts 0.5 s with a 1 s activation cooldown, normalized directional taps, no held repeats, and uninterrupted pitch/roll. Its magnitude is calculated rather than a fixed fourfold collective. The request ceiling, shutdown reserve and delivered-force slew govern the ramp. A/D remain roll and Q/E remain yaw in every orientation.

## Fuel and hardware

Hot-only allocation is tried first. Cold flow is penalized and small hover errors coast inside rate/tilt hysteresis. Required jets stay open through continuing demand so a minimum-burn tail cannot conceal a restart gap. All valves retain finite ignition, burn, shutdown and restart timing; powered hot engines retain real 1% pilot flow.

`aerial_mech.gd::COLD_MOUNTS` places opposed fixed ports on inspected chest/backpack armor. Shared rigid axes replace moving shoulder/thigh ports. The hover knee/hip calibration places heel thrust under the mass center. Fuel minimization is bounded and uses a flow proxy; it is not a claim of a global optimum or modeled tank depletion.

## Directional braking

`flight_pose.gd` and `arm_pose.gd` change chest, forearm and knee incidence for each Shift+pitch/yaw/roll input. Normal powered steering keeps compact weight transfer and shallow panels without opening the airbrake. Tests verify signed air moments and increased Shift energy loss on all six inputs.

## Verification and graph limits

`python3 tools/check_godot.py`: all 24 checks passed on main, including camera checks at 30/144/240 FPS. Seven cardinal/diagonal/heading-relative burst replays peaked at 0.4997 degrees chassis tilt and 66.0 m/s^3 jerk. Quiet hover fired no cold jets during 1800 ticks (30 s). Native pose renders and live forward/reverse force/exhaust captures also passed.

The installed Graphify updater refreshes structural/document headings but does not index GDScript AST. Semantic extraction remains pending with the previously unsupported opencode-go adapter. Inspect the current source and updated aerial README/animation contract before making code-relationship claims.

## Outcome

- Signal: corrected
- Correction: Joint hot/cold allocation and demand-driven fixed RCS replace the fixed 4x burst and recurring trim schedule.

## Source Nodes

- demo_aerial_readme_run_and_controls
- demo_aerial_flight_animation_contract_required_behaviors