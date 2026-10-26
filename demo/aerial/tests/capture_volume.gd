extends SceneTree
func _initialize(): call_deferred("run")
func frame():
 for index in 5: await process_frame
 RenderingServer.force_draw()
func shadow_at(effect, point: Vector3) -> float:
 # Test-only readback; production only consumes the GPU shadow field.
 var texture=Texture2DRD.new()
 texture.texture_rd_rid=effect._shadow_texture
 var image=texture.get_image()
 texture.texture_rd_rid=RID()
 var state=effect._state
 var plane=Vector2(point.dot(state.shadow_x),point.dot(state.shadow_y))
 var bounds: Vector4=state.shadow_bounds
 var uv=(plane-Vector2(bounds.x,bounds.y))/Vector2(bounds.z,bounds.w)
 return image.get_pixel(clampi(int(uv.x*image.get_width()),0,image.get_width()-1),clampi(int(uv.y*image.get_height()),0,image.get_height()-1)).b
func run():
 if DisplayServer.get_name()=="headless":
  push_error("Volume capture requires a native rendering display")
  quit(1)
  return
 create_timer(35.0).timeout.connect(func(): quit(2))
 if "--no-msaa" in OS.get_cmdline_user_args(): root.msaa_3d=Viewport.MSAA_DISABLED
 var center=Vector2i(root.size/2)
 var stage=Node3D.new()
 root.add_child(stage)
 var environment=WorldEnvironment.new()
 environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR
 environment.environment.background_color=Color(0.04,0.07,0.12)
 stage.add_child(environment)
 var clouds=load("res://aerial/tests/volume_fixture_clouds.gd").new()
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
 var strongest_shadow=0.0
 for y in range(0,shadowed.get_height(),2):
  for x in range(0,shadowed.get_width(),2):
   strongest_shadow=maxf(strongest_shadow,unshadowed.get_pixel(x,y).r-shadowed.get_pixel(x,y).r)
 assert(strongest_shadow>0.001,"Cloud shadow did not reduce atmospheric sunlight")
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
 assert(effect.get_status().field_uploads==1,"Rigid cloud drift uploaded the source density atlas")
 clouds.coverage=0
 effect.configure(clouds,sun,settings)
 await frame()
 assert(effect.get_status().shadow_bakes==bakes+1,"Coverage did not rebuild the shadow field")
 assert(effect.get_status().field_uploads==1,"Coverage uploaded an unchanged density atlas")
 clouds.coverage=1
 effect.configure(clouds,Vector3.UP,settings)
 await frame()
 var center_point=clouds.bank_transforms[0].origin
 assert(shadow_at(effect,center_point)>0.1,"Solid sampled grid did not block sunlight")
 var allocations=effect.get_status().texture_allocations
 clouds.rebuild(true)
 effect.configure(clouds,Vector3.UP,settings)
 await frame()
 assert(shadow_at(effect,center_point)<0.001,"A sampled tunnel was filled by a proxy shadow")
 assert(shadow_at(effect,center_point+Vector3(90,0,0))>0.1,"Tunnel regeneration erased its surrounding cloud")
 assert(effect.get_status().field_uploads==2 and effect.get_status().texture_allocations==allocations,"Shape revision did not update the atlas in place")
 root.size=Vector2i(853,479)
 await frame()
 assert(effect.get_status().quarter_size==Vector2i(ceili(root.size.x/4.0),ceili(root.size.y/4.0)),"Volume buffers did not resize with the viewport")
 camera.compositor=null
 compositor=null
 effect=null
 await frame()
 effect=load("res://aerial/atmosphere_volume.gd").new()
 effect.configure(clouds,sun,settings)
 compositor=Compositor.new()
 compositor.compositor_effects=[effect]
 camera.compositor=compositor
 await frame()
 assert(effect.get_status().ready and effect.get_status().field_uploads==1,"Reload did not recreate the density atlas")
 camera.compositor=null
 compositor=null
 effect=null
 stage.queue_free()
 await frame()
 print("Volume GPU checks passed: sampled tunnel, shadows, foreground depth, white occlusion, drift, coverage, zero strength, resize, reload.")
 quit()
