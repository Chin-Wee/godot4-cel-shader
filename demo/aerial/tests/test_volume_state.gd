extends SceneTree
class FixtureClouds:
 extends Node3D
 var bank_transforms: Array=[Transform3D(Basis.IDENTITY.scaled(Vector3(120,80,100)),Vector3(0,350,-300))]
 var shapes: Array=[PackedVector4Array([Vector4(0,0,0,1)])]
 var coverage:=1.0
func _initialize(): call_deferred("run")
func run():
 var clouds=FixtureClouds.new()
 root.add_child(clouds)
 var effect=load("res://aerial/atmosphere_volume.gd").new()
 var sun=Vector3(-0.6,0.3,-0.7).normalized()
 effect.configure(clouds,sun)
 var first=effect._state.duplicate()
 assert(first.cloud_bytes.size()==effect.CLOUD_BYTES and first.active==1)
 clouds.position.x=50
 effect.configure(clouds,sun)
 assert(effect._state.cloud_key==first.cloud_key,"Rigid cloud drift invalidated the shadow bake")
 assert(effect._state.cloud_inverse!=first.cloud_inverse,"Rigid cloud drift did not move the shadow lookup")
 clouds.coverage=0
 effect.configure(clouds,sun)
 assert(effect._state.cloud_key!=first.cloud_key and effect._state.active==0,"Coverage left a stale shadow field")
 var values=effect._matrix_values(Projection(Transform3D.IDENTITY))
 assert(values.size()==16 and values[0]==1 and values[15]==1)
 clouds.queue_free()
 print("Volume state checks passed: bounded layout, drift lookup, coverage invalidation.")
 quit()
