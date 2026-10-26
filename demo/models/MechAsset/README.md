# MechAsset

Runtime source: the supplied `MechAsset.glb`, chosen after comparing it with the
matching `MechAsset.fbx` at the repository root. The GLB contains the same 11 named
clips without the FBX's duplicate animation stacks. Keep the original FBX for
future authoring; no texture files are required.

The inherited actor uses the existing matte, painterly mech shader, including
green painted accents converted from the source's black emissive material.
Standing rigid armor/foot vertices span 14.59817 source units; a scale of
0.12330315 and model Y offset of 0.124167 fit that standing pose to 1.8 meters.

## Controls and animations

Tab switches between George and MechAsset. WASD, mouse look and Space work for
the selected mech. Shift still runs on George; MechAsset walks only. Inactive
playable bodies continue braking, falling and landing. Grass follows the selected
actor. Switching keeps each actor's position and mouse capture state.

The reusable roster keeps its requested `(3, 0, -7)` slot. The sample scene
overrides it to `(2.5, 0.4, -7)` to clear its boundary wall and terrain; gravity
settles it vertically without collision recovery pushing it sideways.

`Idle Pose` maps to `Idle`; `Walk_Forward` maps to `Walk`. Godot imports
`Fall_Loop` as `Fall` through its built-in loop suffix handling. Jump plays during
ascent, Fall loops during descent, and Land completes before idle/walk resumes.
The shared AnimationPlayer crossfade remains 0.6 seconds, with ordinary playback
at 70%; jump playback fits its clip to the physics ascent.

Runtime animation resources are cloned. Root translations are held at the idle
root position so physics supplies displacement; walking stride is measured from
the original 16.6422-unit root travel first. Skeletal body and limb animation
remain intact. Boost, gun and default poses remain available for editor preview.

The controller reuses the project's existing actor/camera hierarchy. The
interaction reference for switching is GTA V: one active protagonist and camera.

## Validation

From the repository root:

```sh
godot --headless --path demo --script res://actors/mechs/tests/test_playable_mech.gd
godot --headless --path demo --script res://actors/mechs/tests/test_mech_locomotion.gd
godot --headless --path demo --script res://actors/mechs/tests/test_mech_jump_calibration.gd
```
