---
type: "query"
date: "2026-11-06T10:21:46.903219+00:00"
question: "Where are Armored Core hover tap burst control timings and force handling defined?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["aerial/README.md", "Mech flight animation contract"]
---

# Q: Where are Armored Core hover tap burst control timings and force handling defined?

## Answer

Source verified at 6b61cdc. Armored Core VI Quick Boost is the production behavior reference. In demo/aerial/flight_controller.gd, _read_commands no longer delays pitch/roll: rotation_request follows WASD immediately. A new powered-hover direction press starts a normalized heading-local 0.5-second burst at 4x hover collective, with a 1-second activation-to-activation cooldown. Holding never repeats; early taps are discarded. Precision scales directional intent. Engine cutoff shortens the burst to its 0.06-second fade, avoiding an abrupt force drop. Reset clears all burst state.

Cruise engine_level spools independently; thrust_level combines it with the finite burst envelope. Existing six motors apply native forces at their actual outlets. Brief heel overdrive avoids the canted calf ports pushing opposite a reverse tap; 30-degree cones remain. Burst moment allocation uses the existing 10% force-trim budget to retain lateral stability. Pose, exhaust, HUD and replay telemetry all read the actual collective. FlightInput preserves taps between physics samples. No velocity assignments implement the burst.

Validated on main: python3 tools/check_godot.py passed all 24 runs, including camera checks at 30/144/240 FPS. The complete capture_mech replay passed takeoff, hover, fighter/coast/body-flight, landing, braking, continuous transitions and 90-second full-thrust equilibrium. Native Metal test_thruster_control captures also passed. Burst tests check exact cooldown reactivation, cutoff fade, diagonal normalization, motor ratings, force accounting and finite jerk. The installed Graphify updater does not parse GDScript; source remains authoritative and semantic-refresh-needed.json records that limitation.

## Outcome

- Signal: useful

## Source Nodes

- aerial/README.md
- Mech flight animation contract