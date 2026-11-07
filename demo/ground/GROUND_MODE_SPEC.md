# Ground Mode v1 · Hathaway Movement Slice

Open [Ground Trial](ground_demo.tscn) in the demo project. Use **F6** to switch between dusk and daylight, **F7** to switch between chase and witness, and **Backspace** to reset. **P** pauses the simulation. Mouse orbit and wheel zoom work in chase.

The acceptance sequence is **two steps → 90° pivot → powered hop → one-foot catch → skid → guard**. The current **9 m, 10 t** chassis should visibly load a foot, push off, commit to the move, and recover its weight. Armored Core VI is the shipped-game reference for short powered repositioning and landing recovery. Hathaway supplies the sole mechanics, posing, and street-level staging. [Armored Core VI movement](https://www.armoredcore.net/article/230911_1.html) · [Gustav Karl ankle rig](https://area.autodesk.jp/case/animation/hathaway-the-witch-of-circe/) · [Hathaway production and camera](https://febri.jp/topics/gundam_hathaway_chap2_3_1/)

The proposed follow-up is documented in the [authored locomotion plan](AUTHORED_LOCOMOTION_PLAN.md).

## Movement

| Input or event | Required behavior and tuning targets |
|---|---|
| **W/S, A/D** | Body-relative steps. Show a weight shift, then alternate heel catch, flat support, and toe-off. Target **2.5 m/s** forward and **1.25 m/s** reverse or sideways with **0.6–0.85 s** steps. The current gait uses **0.70 s** steps with **0.13 s** of load. Finish the committed plant before reversing. Settle when the next plant is blocked or unreachable. |
| **Q/E tap** | Load the inside foot, pivot through two placements, and settle within **5°** of the **90°** target. Holding the key produces one pivot. |
| **R tap** | From support, load the legs and request a **0.50 s** hot burst. Capture the held direction at acceptance and use forward when neutral. Start a **1 s** cooldown at the beginning of the request. Reject held, airborne, and cooldown repeats. From rest, target **0.8–1.6 m** rise and **3–6 m** to touchdown. |
| **Ascent and descent** | Tuck on ascent and reach during descent. Request one short cushion when time to contact and valve readiness allow it. |
| **Touchdown** | Catch on the lead boot, compress the legs, and settle the torso. Preserve contact momentum. A sink speed of **5 m/s** or more takes **0.45 s** to recover before another hop. |
| **Shift** | Brake against support. Slide above grip with the feet following measured motion, then replant. |
| **Ctrl** | Hold an asymmetric guard pose. Cap the step target at reverse speed. Release movement to settle into idle. |

## Visual targets

- **Street and scale.** A **12 × 40 m** street with a flat lane, an **8°** ramp, a wall, concrete cover, a parked vehicle, **2.08 m** doors, and **3.3 m** lamps. The existing mech GLB supplies the calibrated skeleton and nozzle hardpoints used by flight. The source FBX includes duplicate animation stacks. Street props use boxes so their dimensions and contact planes are visible in daylight.
- **Davao-inspired dusk.** Use matte cel armor, cool blue-gray shadows, warm lamp pools, and an amber-white jet flash. The loaded boot and knee should read clearly through touchdown. Jet light follows delivered hot thrust, dust follows native touchdown, and the skid trail follows measured slip. Reuse the demo's Mobile renderer and inspect the same poses in neutral daylight.
- **Cameras.** Chase begins around **3.6 m** above pavement at **54° vertical FOV**, follows the interpolated body via Phantom Camera, and pulls in when geometry obstructs it. The fixed **1.7 m** pedestrian camera frames the vehicle in the foreground. Both views must show the load, lift, catch, and settle.

## Integration

The ground scene owns its input and world. The existing `RigidBody3D` carries position and momentum through every phase. The capsule handles hull collision. Two shallow, fixed ground-only pads widen its native normal support footprint so a bounded foot push can load one side without tipping the capsule. The animated feet and traction anchors remain independent of these pads.

The capsule and pads use frictionless native contact. A reachable boot sample must agree with a current floor contact before it contributes traction. The combined normal load budget is projected body weight minus delivered thrust along the support normal. Each loaded boot gets a share capped at **0.70 × load** for grip or **0.45 × load** for skid. Double support can apply an opposed foot couple for yaw. Support loss cuts traction immediately. [Godot contact state](https://docs.godotengine.org/en/stable/classes/class_physicsdirectbodystate3d.html) · [Godot material friction](https://docs.godotengine.org/en/stable/classes/class_physicsmaterial.html)

Ground control submits SI force and moment requests to the existing allocator. Hot and cold nozzles retain their gimbals, finite valves, per-port caps, and speed-scaled cold limits. The body applies nozzle, aero, and sole forces once per physics tick. Ground mode supplies pose phase, foot anchors and headings, slip, and landing load to the full-body rig, followed by the two leg IK solves, sole alignment, and hardpoint capture. The loaded heel or toe stays in terrain space through rollover.

## Replay and checks

Run `python3 tools/check_godot.py` from the repository root. The ground replay checks **≤0.10 m** planted drift, **≤3°** planted yaw drift, and **≤0.10 m/s** settled speed. It also checks the pivot and hop ranges, ramp support, blocked steps, contact loss, failed cushion ignition, hard landing, and the traction and nozzle caps.

Capture the same 60 Hz input timeline at **30** and **144** render FPS. Each run exports chase and pedestrian frames in both light presets at toe-off, heel catch, pivot, ignition, apex, catch, skid, and guard.

```sh
godot --path demo --disable-vsync --fixed-fps 30 --script res://ground/tests/test_ground_movement.gd -- /tmp/ground-30
godot --path demo --disable-vsync --fixed-fps 144 --script res://ground/tests/test_ground_movement.gd -- /tmp/ground-144
```

Use Godot's movie writer for an uninterrupted pass. Choose `--chase` or `--witness` after the argument separator. Add `--day` for neutral light.

```sh
godot --path demo --disable-vsync --fixed-fps 30 --write-movie /tmp/witness.avi --script res://ground/tests/test_ground_movement.gd -- --witness
```

Shield collision, weapons, damage, enemy AI, and film-scale chassis are later milestones. Touchdown and slip can serve those systems when they are built.
