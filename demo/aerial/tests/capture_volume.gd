extends SceneTree
class FixtureClouds:
 extends Node3D
 var bank_transforms: Array = [Transform3D(Basis.IDENTITY.scaled(Vector3(130,80,100)),Vector3(0,350,-300))]
 var shapes: Array = [PackedVector4Array([Vector4(0,0,0,1)])]
 var coverage := 1.0
func _initialize(): call_deferred("run")
func frame():
 for index in 5: await process_frame
 RenderingServer.force_draw()
func run():
 if DisplayServer.get_name()=="headless":
  push_error("Volume capture requires a native rendering display")
  quit(1)
  return
 create_timer(25.0).timeout.connect(func(): quit(2))
 if "--no-msaa" in OS.get_cmdline_user_args(): root.msaa_3d=Viewport.MSAA_DISABLED
 var center=Vector2i(root.size/2)
 var stage=Node3D.new()
 root.add_child(stage)
 var environment=WorldEnvironment.new()
 environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR
 environment.environment.background_color=Color(0.04,0.07,0.12)
 stage.add_child(environment)
 var clouds=FixtureClouds.new()
 stage.add_child(clouds)
 var camera=Camera3D.new()
 stage.add_child(camera)
 camera.position=Vector3(0,120,650)
 camera.far=6000
 camera.look_at(Vector3(0,150,-800))
 camera.current=true
 var effect=load("res://aerial/atmosphere_volume.gd").new()
 var sun=Vector3(0,0.45,-0.89).normalized()
 var settings={"density":0.00018,"strength":1.0,"sun_strength":3.0,"max_distance":1500.0}
 effect.configure(clouds,sun,settings)
 var compositor=Compositor.new()
 compositor.compositor_effects=[effect]
 camera.compositor=compositor
 await frame()
 var initial_status=effect.get_status()
 print("STATUS ",initial_status)
 await frame()
 assert(effect.get_status().texture_allocations==initial_status.texture_allocations and effect.get_status().pipeline_builds==initial_status.pipeline_builds,"Steady rendering allocated GPU resources")
 assert(effect.get_status().ready,"Volume compositor did not initialize")
 var open_visibility=effect.solar_visibility_texture.get_image().get_pixel(0,0).r
 print("OPEN_VISIBILITY ",open_visibility)
 var shadowed=root.get_texture().get_image()
 shadowed.save_png("/tmp/dmc-volume-shadowed.png")
 settings.shadow_strength=0.0
 effect.configure(clouds,sun,settings)
 await frame()
 var unshadowed=root.get_texture().get_image()
 unshadowed.save_png("/tmp/dmc-volume-unshadowed.png")
 assert(shadowed.get_data()!=unshadowed.get_data(),"Cloud occlusion produced no shadow columns")
 assert(shadowed.get_pixel(center.x,center.y).r<unshadowed.get_pixel(center.x,center.y).r,"Cloud shadow did not reduce atmospheric sunlight")
 settings.strength=0.0
 effect.configure(clouds,sun,settings)
 await frame()
 var off=root.get_texture().get_image()
 off.save_png("/tmp/dmc-volume-off.png")
 camera.compositor=null
 await frame()
 assert(root.get_texture().get_image().get_data()==off.get_data(),"Zero volume strength changed scene color")
 camera.compositor=compositor
 var panel=MeshInstance3D.new()
 panel.mesh=QuadMesh.new()
 panel.mesh.size=Vector2(70,70)
 var panel_material=StandardMaterial3D.new()
 panel_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 panel_material.albedo_color=Color(0.8,0.8,0.8)
 panel.material_override=panel_material
 stage.add_child(panel)
 panel.position=camera.position-camera.global_basis.z*150
 panel.basis=camera.basis
 await frame()
 var foreground=root.get_texture().get_image().get_pixel(center.x,center.y)
 settings.strength=1.0
 effect.configure(clouds,sun,settings)
 await frame()
 var fogged_foreground=root.get_texture().get_image().get_pixel(center.x,center.y)
 assert(absf(foreground.r-fogged_foreground.r)<0.03,"Atmospheric integration passed through foreground geometry")
 panel.queue_free()
 var blocker=MeshInstance3D.new()
 blocker.mesh=SphereMesh.new()
 blocker.mesh.radius=20
 blocker.mesh.height=40
 var white=StandardMaterial3D.new()
 white.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 white.albedo_color=Color.WHITE
 blocker.material_override=white
 stage.add_child(blocker)
 blocker.position=camera.position+sun*150
 await frame()
 var blocked_visibility=effect.solar_visibility_texture.get_image().get_pixel(0,0).r
 print("BLOCKED_VISIBILITY ",blocked_visibility)
 assert(open_visibility>0.9 and blocked_visibility<0.1,"Depth-derived solar visibility leaked through white geometry")
 var bakes=effect.get_status().shadow_bakes
 clouds.position.x=50
 effect.configure(clouds,sun,settings)
 await frame()
 assert(effect.get_status().shadow_bakes==bakes,"Rigid cloud drift rebaked the shadow field")
 clouds.coverage=0
 effect.configure(clouds,sun,settings)
 await frame()
 assert(effect.get_status().shadow_bakes==bakes+1,"Coverage did not rebuild the shadow field")
 root.size=Vector2i(853,479)
 await frame()
 assert(effect.get_status().quarter_size==Vector2i(ceili(root.size.x/4.0),ceili(root.size.y/4.0)),"Volume buffers did not resize with the viewport")
 print("Volume GPU checks passed: shadows, foreground depth, white occlusion, drift, coverage, zero strength, resize.")
 camera.compositor=null
 compositor=null
 effect=null
 stage.queue_free()
 await frame()
 quit()
