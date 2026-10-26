extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var clouds=load("res://aerial/tests/volume_fixture_clouds.gd").new()
 root.add_child(clouds)
 var effect=load("res://aerial/atmosphere_volume.gd").new()
 var sun=Vector3(-0.6,0.3,-0.7).normalized()
 effect.configure(clouds,sun)
 var first=effect._state.duplicate()
 assert(first.cloud_bytes.size()==effect.CLOUD_BYTES and first.active==1)
 var count=clouds.field_size.x*clouds.field_size.y*clouds.field_size.z
 assert(first.field_bytes.size()==count*4*4,"Density atlas packing lost grid samples")
 assert(first.field_dimensions==Vector3i(33,21,116),"Variant atlas depth is incorrect")
 var packed=first.field_bytes.to_float32_array()
 for variant in 4:
  for index in [0,count/2,count-1]:
   assert(packed[variant*count+index]==clouds.density_fields[variant][index],"X-fast variant packing changed density samples")
 clouds.position.x=50
 effect.configure(clouds,sun)
 assert(effect._state.cloud_key==first.cloud_key,"Rigid cloud drift invalidated the shadow bake")
 assert(effect._state.field_key==first.field_key and effect._state.field_bytes==first.field_bytes,"Rigid cloud drift repacked the density atlas")
 assert(effect._state.cloud_inverse!=first.cloud_inverse,"Rigid cloud drift did not move the shadow lookup")
 clouds.coverage=0
 effect.configure(clouds,sun)
 assert(effect._state.cloud_key!=first.cloud_key and effect._state.active==0,"Coverage left a stale shadow field")
 assert(effect._state.field_key==first.field_key,"Coverage invalidated the source grid upload")
 var covered_key=effect._state.cloud_key
 effect.configure(clouds,sun.rotated(Vector3.UP,0.2))
 assert(effect._state.cloud_key!=covered_key and effect._state.field_key==first.field_key,"Sun motion did not rebake shadows independently of source grid upload")
 clouds.rebuild(true)
 effect.configure(clouds,sun)
 assert(effect._state.field_key!=first.field_key and effect._state.cloud_key!=first.cloud_key,"A changed density field left a stale atlas or shadow map")
 var metadata=effect._state.cloud_bytes.to_float32_array()
 assert(Vector3(metadata[0],metadata[1],metadata[2])==clouds.field_bounds.position)
 assert(Vector3(metadata[4],metadata[5],metadata[6])==clouds.field_bounds.size)
 assert(Vector3i(metadata[8],metadata[9],metadata[10])==clouds.field_size and metadata[11]==4)
 var values=effect._matrix_values(Projection(Transform3D.IDENTITY))
 assert(values.size()==16 and values[0]==1 and values[15]==1)
 clouds.queue_free()
 print("Volume state checks passed: grid packing, bounds, revision, drift lookup, coverage invalidation.")
 quit()
