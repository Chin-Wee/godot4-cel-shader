---
type: "query"
date: "2026-11-06T10:34:05.029787+00:00"
question: "Why do A/D and Q/E keep their axes between space and plane flight?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["demo_aerial_readme_run_and_controls", "demo_aerial_flight_animation_contract_required_behaviors"]
---

# Q: Why do A/D and Q/E keep their axes between space and plane flight?

## Answer

Source verified at 7b556b7. The user's repeated roll wording was interpreted as A/D always roll and Q/E always yaw, matching the existing plane bindings. The Elite Dangerous production reference supplies fixed ship axes across assisted/unassisted flight. flight_controller.gd now has one constant PILOT_AXES (body X pitch, body Z yaw, body -Y roll) shared by airflow measurement, native attitude demand and pilot_frame(). Space, powered hover, plane flight, speed and inversion cannot remap these axes. The former control_blend, control_target and roll_frame_locked state and associated posture/airspeed blending were removed.

Hover restoration releases the same commanded pilot axes; horizontal drift trim now checks pitch/yaw rather than pitch/roll. Native pose consumers already transform pilot intent into body coordinates, so no separate animation remapping was introduced. Replay yaw/roll rates use the fixed aircraft frame. Animation fixtures now check the appropriate physical chest/head axes. Existing tap boosts and interpolation are retained.

Validated: all 24 tools/check_godot.py runs pass on main, including camera at 30/144/240 FPS. Native body tests assert signed physical key axes upright, prone, inverted and through high/zero airspeed. Complete capture_mech and capture_acrobatics replays pass, including both body/chase cameras, roll-through-inversion, compound turns, cutoff/recovery and long full-thrust equilibrium. The installed Graphify updater does not parse GDScript; source remains authoritative and the semantic-refresh-needed sidecar retains this limitation.

## Outcome

- Signal: useful

## Source Nodes

- demo_aerial_readme_run_and_controls
- demo_aerial_flight_animation_contract_required_behaviors