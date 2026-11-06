---
type: "query"
date: "2026-11-06T11:47:27.099779+00:00"
question: "How does flight enforce physical hot/cold nozzle forces and finite activation/restart timing?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["demo_aerial_readme_run_and_controls", "demo_aerial_flight_animation_contract_required_behaviors"]
---

# Q: How does flight enforce physical hot/cold nozzle forces and finite activation/restart timing?

## Answer

Source verified at 9d823f4. All live mech control actuation now uses native apply_force at six hot nozzles, four cold nozzles and five posed aerodynamic panels. No direct RCS torque or central leg/launch force remains. Cold force and torque are sums of the actual finite nozzle forces and moment arms, including linear recoil; placing the nozzles at the centre of mass cannot invent rotation. Body velocities/attitude are not overwritten in live flight. Native gravity/contact remain; reset, pause/resume and frozen G walk preview are outside live flight integration. A/D roll and Q/E yaw remain fixed, and the user explicitly confirmed these bindings.

thruster_valve.gd provides per-outlet ignition, minimum burn, finite rise/fall and restart dead time after shutdown. Defaults: hot ignition 60 ms, minimum closed time 120 ms, full-flow rise/fall 60 ms, minimum burn 80 ms. Cold: 8 ms, 30 ms, 12/14 ms, 20 ms respectively. These are tunable fictional mech values, not universal real-engine specifications. Pressure impulse integrates sub-tick transitions and pulse boundaries; held/reversed commands cannot bypass valve state. Hot cruise spool and directional boost commands remain separate from delivered collective. R requests a half-second hot-thruster launch without changing cruise detent. Exiting the frozen walk preview cold-starts propulsion.

Cold allocation reuses bounded force/moment iteration and 30-degree nozzle cones, with inertia weighting and a conservative projected-gradient step; physical per-port capacity, not an inertia-derived free torque ceiling, limits authority. Steady countertorque burns continuously above 10% nozzle load, releasing below 6%; smaller trim uses 3 Hz / 65% duty. Actual geometry can block a high-load braked flip, which reports saturation rather than injecting torque. Hot burst/launch allocation can trade 25% resultant direction to retain moment authority. Poses, per-nozzle exhaust and HUD use delivered forces; preview throttle cannot fabricate an active plume. Production references are Kerbal Space Program placed RCS and Star Citizen's published thruster-location/capacity/response model; sources are linked in aerial/README.md.

Validation on main: all 24 tools/check_godot.py runs passed, including camera at 30/144/240 FPS, force accounting, valve impulse invariance across 30/60/144/240 Hz, restart/minimum burn, zero-lever torque, nozzle cones and force/visible-direction agreement. Complete capture_mech and both-camera capture_acrobatics replays passed; 90-second full-power equilibrium is about 137 m/s with actual recoil included in the force bound. Native Metal thruster captures passed and were visually reviewed. Graphify's installed updater does not index GDScript; structural/doc locations were refreshed, with the existing semantic/GDScript limitation retained in semantic-refresh-needed.json. Source is authoritative.

## Outcome

- Signal: useful

## Source Nodes

- demo_aerial_readme_run_and_controls
- demo_aerial_flight_animation_contract_required_behaviors