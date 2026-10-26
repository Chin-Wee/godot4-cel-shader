extends Node3D

# A sampled field fixture, with the same layout and weather density contract as
# the production marching-cubes clouds. No lobe proxy participates in shadows.
var bank_transforms: Array = [Transform3D(Basis.IDENTITY.scaled(Vector3(130,80,100)),Vector3(0,350,-300))]
var field_size := Vector3i(33,21,29)
var field_bounds := AABB(Vector3(-1.6,-0.6,-1.4),Vector3(3.2,2.0,2.8))
var density_fields: Array[PackedFloat32Array] = []
var field_revision := 0
var coverage := 1.0

func _init() -> void:
 rebuild(false)

func rebuild(tunnel: bool) -> void:
 density_fields.clear()
 for variant in 4:
  var values := PackedFloat32Array()
  for z in field_size.z:
   for y in field_size.y:
    for x in field_size.x:
     var fraction := Vector3(x,y,z)/Vector3(field_size-Vector3i.ONE)
     var point := field_bounds.position+fraction*field_bounds.size
     var signed_density := 0.8-float(variant)*0.04-(point-Vector3(0,0.25,0)).length()
     if tunnel: signed_density = minf(signed_density,Vector2(point.x,point.z).length()-0.35)
     values.append(signed_density)
  density_fields.append(values)
 field_revision = hash(density_fields)
