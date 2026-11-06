---
type: "query"
date: "2026-11-06T19:24:23.970043+00:00"
question: "How does aerial cold-jet thrust scale with speed from rest to 40 mps?"
contributor: "graphify"
outcome: "corrected"
correction: "Cold hardware ratings remain fixed, but usable physical thrust now scales linearly from 15 percent at rest to 100 percent at 40 mps, with gentler low-speed force ramps."
source_nodes: ["demo_aerial_readme_run_and_controls", "demo_aerial_flight_animation_contract_required_behaviors"]
---

# Q: How does aerial cold-jet thrust scale with speed from rest to 40 mps?

## Answer

Source authority: integration commit 278c64d, feature de3ffc2.

The aerial flight controller now limits each cold nozzle to its fixed hardware rating multiplied by lerp(0.15, 1.0, clamp(native body speed in m/s / 40, 0, 1)). This gives 15% at rest, 36.25% at 10 m/s, 57.5% at 20 m/s, and 100% at or above 40 m/s. Speed is the magnitude of native world translational velocity, including vertical motion, independent of heading or wind. Disabled zero-rated nozzles remain disabled. Hot hardware ratings remain unchanged.

cold_power_fraction() supplies the speed fraction; cold_thrust_limit(index) multiplies each nozzle's own Newton rating. The shared _cold_capacity() feeds both horizon/reachable allocation and actual executed valve forces, so this is a physical cap, not a visual-only throttle. Existing finite ignition, minimum burn, restart and rise/fall dynamics remain. The existing Star Citizen-referenced placed-thruster allocator architecture and solver budget are reused. Propulsion force slew scales by sqrt(cold power fraction), and burst shutdown reserves that gentler slew, to keep combined thrust balanced under reduced low-speed trim authority. HUD cold load reports actual force divided by full hardware rating, matching exhaust intensity.

Scoped validation passed native detents/six-axis/hover/momentum/redirected thrust/braking/lift/contact/IK checks and all seven cardinal/diagonal/heading-relative balanced bursts under the existing chassis tilt, cross-axis force and jerk limits. Low-speed burst jerk is about 25 m/s^3. Full-authority rotation fixtures now run above 40 m/s. Tests cover speed endpoints and intermediate values in horizontal, vertical and diagonal directions, disabled hardware, mass independence, actual per-frame speed caps, and truthful HUD load. The installed Graphify structural updater does not index GDScript AST; source remains authoritative and the existing semantic-refresh-needed marker remains explicit.

Integration validation: python3 tools/check_godot.py passed all 25 runs on main, including PhantomCamera at 30/144/240 FPS. Full log: /tmp/cold-speed-main-validation.log. Replay metrics: /var/folders/y9/zgzbjttn0v10ym8cc4h1tm9h0000gn/T/godot-checks-h5kdhjb3.

## Outcome

- Signal: corrected
- Correction: Cold hardware ratings remain fixed, but usable physical thrust now scales linearly from 15 percent at rest to 100 percent at 40 mps, with gentler low-speed force ramps.

## Source Nodes

- demo_aerial_readme_run_and_controls
- demo_aerial_flight_animation_contract_required_behaviors