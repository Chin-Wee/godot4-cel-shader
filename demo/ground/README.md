# Ground movement demo

Open [Ground Trial](ground_demo.tscn) in the demo project. The [mech animation and movement guide](../../MECH_ANIMATION_RESEARCH.md) defines the design and authoring targets.

| Input | Current demo action |
|---|---|
| W/S, A/D | Walk forward, backward, or sideways |
| Alt + W | Shoulder run (4.0 m/s target; 0.42 s steps) |
| Q/E tap | Pivot left or right |
| R tap | Powered hop in the held direction, or forward at neutral |
| Shift | Brake or skid |
| Ctrl | Crouched guard; forward travel uses a 1.25 m/s target and 0.80 s steps |
| F6 | Switch between dusk and daylight |
| F7 | Switch between chase and pedestrian views |
| Backspace | Reset the trial |
| P | Pause or resume |

Mouse orbit and wheel zoom work in chase. The level includes a flat street, an 8° ramp, a wall and human-scale props. The current replay checks walk, shoulder run, crouched travel, a 90° pivot, a powered hop, a one-foot catch, a skid and a guard.

## Replay and checks

Run `python3 tools/check_godot.py` from the repository root. The ground replay checks walk/run/crouch cadence, run speed, guard pelvis loading and foot IK, along with planted drift, pivot, hop, ramp support, blocked steps, contact loss, failed cushion ignition, hard landing, and traction and nozzle caps.

Capture the same 60 Hz input timeline at **30** and **144** render FPS. Each run exports chase and pedestrian frames in both light presets at toe-off, heel catch, pivot, ignition, apex, catch, skid, and guard.

```sh
godot --path demo --disable-vsync --fixed-fps 30 --script res://ground/tests/test_ground_movement.gd -- /tmp/ground-30
godot --path demo --disable-vsync --fixed-fps 144 --script res://ground/tests/test_ground_movement.gd -- /tmp/ground-144
```

Use Godot's movie writer for an uninterrupted pass. Choose `--chase` or `--witness` after the argument separator. Add `--day` for neutral light.

```sh
godot --path demo --disable-vsync --fixed-fps 30 --write-movie /tmp/witness.avi --script res://ground/tests/test_ground_movement.gd -- --witness
```
