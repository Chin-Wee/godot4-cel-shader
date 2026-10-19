# Grass direction: Breath of the Wild

## Scope and evidence

The visual target is **The Legend of Zelda: Breath of the Wild**. The sources
below describe independent recreations and another shipped game's grass system;
they do not establish Nintendo's exact implementation.

Production reference: **Ghost of Tsushima**, Eric Wohllaib's Sucker Punch GDC
talk, [Procedural Grass in Ghost of Tsushima](https://gdcvault.com/play/1027033/Advanced-Graphics-Summit-Procedural-Grass).
Use its grass rendering approach as a technical reference while aiming for
BOTW's softer shapes and colors.

## Why this scene looks like panels

- `grass_triangle.obj` is the only blade mesh in `demo/models/foliage/`. Inspection
  found nine vertices and seven triangles. All vertices have Z = 0 and share a
  single sideways normal. It has segments, but no resting curvature or twist.
- Random yaw exposes alternating bright and dark flat surfaces under the
  existing cel lighting. Higher density repeats those surfaces more often.
- Looking down exposes the lack of projected blade area. Softer normals improve
  shading, but cannot give a straight, upright plane a curved silhouette.
- Imported Godot UVs were checked: roots have V about 0.986 and the tip about
  0.020. The existing `1 - UV.y` mask has the correct direction. OBJ file UVs
  alone would misleadingly suggest the opposite because import flips V.

## Recommended implementation order

1. **Curved silhouettes first.** Reuse the existing segmented blade, give it
   resting curvature and a little twist, and vary height, width and lean
   independently. Anchor displacement exactly at the roots. Check from above
   and from the gameplay camera before increasing complexity.
2. **Softer foliage lighting.** Blend terrain-facing normals with curved blade
   normals, handle both faces consistently, retain a dark root / bright tip
   gradient, and add modest backlighting. Avoid turning every blade into a
   separate hard cel shadow. Match root color to the terrain.
3. **Spatial variation.** Use broad world-space patches for tint, height and
   lean, with smaller per-blade variation. Keep wind coherent across patches.
   Preserve the requested 160,000 blades while evaluating these changes.
4. **Interaction.** Follow the playable mech's world position in the existing
   shader. This is now enabled: 1.1 m influence radius and up to 0.35 m horizontal
   push, fading with distance. It recovers immediately as the mech leaves;
   persistent tracks and multiple simultaneous interactors require another pass.
5. **Scale after the look works.** Divide grass into MultiMesh tiles for culling
   and reduce density/segments with distance. Blend the far field into ground
   color. Avoid a new compute pipeline for this small scene.

These are proposed tuning steps, not claims about Nintendo's engine. Initial
acceptance: no obvious flat fins from above, stable roots, gentle connected
gusts, readable mech contact, and no visible boundary between grass and ground.

## Sources and what each supports

- [Daniel Ilett: Stylised Grass with Shaders in URP](https://danielilett.com/2021-08-24-tut5-17-stylised-grass/)
  is an explicit BOTW recreation. It demonstrates segmented blade curvature,
  randomized rotation/dimensions, base-to-tip color, placement masks and wind.
  Adapt the shape and shading ideas to Godot's existing MultiMesh; its Unity
  geometry/tessellation shader code is not a drop-in Godot implementation.
- [2Retr0: GodotGrass](https://github.com/2Retr0/GodotGrass) is a working Godot
  recreation inspired by Ghost of Tsushima. Its author documents curved blades,
  rounded normals, view-dependent width, clump variation, backlighting and
  tile-based LOD. It also records visible LOD transitions and the cost of grass
  shadows, useful constraints for our implementation.
- [Godot spatial shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)
  defines model/world transforms and instance data used to implement this in
  the current renderer.
- [Godot MultiMesh guidance](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
  explains instancing and the need to split instances spatially for culling.

## Local checks

Run `godot --headless --path demo --script res://scripts/tests/test_grass_interaction.gd`
from the repository root to check the main scene's target binding, movement
updates, material isolation and safe target removal. GPU appearance still needs
inspection in the rendered scene from both gameplay and overhead angles.
