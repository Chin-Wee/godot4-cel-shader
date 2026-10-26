extends CompositorEffect

# Horizon Zero Dawn is the production reference for view-ray integration with
# light-path cloud attenuation. This is a bounded atmospheric adaptation, not its renderer.
const COMPUTE_PATH := "res://shaders/aerial/atmosphere-volume.glsl"
const COMPOSITE_PATH := "res://shaders/aerial/atmosphere-composite.glsl"
const SHADOW_SIZE := 256
const FRAME_BYTES := 84 * 4
const CLOUD_BYTES := (3 * 4 + 18 * 20) * 4

var solar_visibility_texture := Texture2DRD.new()
var _rd: RenderingDevice
var _mutex := Mutex.new()
var _state := {}
var _status := {"ready": false,"frames": 0,"shadow_bakes": 0,"error": ""}
var _cloud_key := 0
var _cloud_bytes := PackedByteArray()
var _field_key := 0
var _field_bytes := PackedByteArray()
var _shadow_x := Vector3.RIGHT
var _shadow_y := Vector3.UP
var _shadow_bounds := Vector4(-4000,-2000,8000,4000)
var _gpu_cloud_key := -1
var _gpu_field_key := -1
var _field_dimensions := Vector3i.ZERO
var _field_uploads := 0
var _depth_samples := -1
var _texture_allocations := 0
var _framebuffer_builds := 0
var _pipeline_builds := 0
var _framebuffer_format := -1
var _framebuffer: RID
var _color: RID
var _frame_buffer: RID
var _cloud_buffer: RID
var _density_texture: RID
var _density_sampler: RID
var _shadow_texture: RID
var _solar_texture: RID
var _fog_texture: RID
var _distance_texture: RID
var _sampler: RID
var _low_size := Vector2i.ZERO
var _shaders: Array[RID] = []
var _pipelines: Array[RID] = []

func _init() -> void:
 effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
 access_resolved_color = true
 # Mobile does not resolve MSAA depth for compositor effects. Read its actual attachment.
 access_resolved_depth = false
 _rd = RenderingServer.get_rendering_device()

func get_status() -> Dictionary:
 _mutex.lock()
 var result := _status.duplicate()
 _mutex.unlock()
 return result

func configure(clouds: Node3D, direction: Vector3, settings: Dictionary = {}) -> void:
 if not direction.is_finite() or direction.length_squared() < 0.000001:
  push_error("Atmospheric sunlight direction must be finite and nonzero")
  return
 var transforms: Array = clouds.get("bank_transforms")
 var field_size: Vector3i = clouds.get("field_size")
 var field_bounds: AABB = clouds.get("field_bounds")
 var fields: Array = clouds.get("density_fields")
 var sample_count := field_size.x*field_size.y*field_size.z
 assert(field_size.x >= 2 and field_size.y >= 2 and field_size.z >= 2 and fields.size() > 0 and fields.size() <= 4,"Cloud shadows require sampled density grids")
 var field_key := hash([clouds.get("field_revision"),field_size,field_bounds,fields.size()])
 if field_key != _field_key or _field_bytes.is_empty():
  var samples := PackedFloat32Array()
  for field in fields:
   assert(field.size() == sample_count,"Cloud density grid size does not match its layout")
   samples.append_array(field)
  _field_bytes = samples.to_byte_array()
  _field_key = field_key
 var active := clampi(roundi(transforms.size()*float(clouds.get("coverage"))),0,18)
 var local_sun := (clouds.global_basis.inverse()*direction).normalized()
 var key := hash([transforms,field_key,active,local_sun])
 if key != _cloud_key or _cloud_bytes.is_empty():
  _cloud_key = key
  _shadow_x = Vector3.UP.cross(local_sun).normalized()
  if _shadow_x.length_squared() < 0.01: _shadow_x = Vector3.RIGHT
  _shadow_y = local_sun.cross(_shadow_x).normalized()
  var values := PackedFloat32Array([field_bounds.position.x,field_bounds.position.y,field_bounds.position.z,0,
   field_bounds.size.x,field_bounds.size.y,field_bounds.size.z,0,
   field_size.x,field_size.y,field_size.z,fields.size()])
  assert(transforms.size() <= 18,"Cloud shadow field exceeded its bounded bank layout")
  var minimum := Vector2(INF,INF)
  var maximum := Vector2(-INF,-INF)
  for index in 18:
   if index < transforms.size():
    values.append_array(_matrix_values(Projection((transforms[index] as Transform3D).affine_inverse())))
    values.append_array(PackedFloat32Array([index % fields.size(),0,0,0]))
    for x in [field_bounds.position.x,field_bounds.end.x]:
     for y in [field_bounds.position.y,field_bounds.end.y]:
      for z in [field_bounds.position.z,field_bounds.end.z]:
       var point: Vector3 = transforms[index]*Vector3(x,y,z)
       var projected := Vector2(point.dot(_shadow_x),point.dot(_shadow_y))
       minimum = minimum.min(projected)
       maximum = maximum.max(projected)
   else:
    values.resize(values.size()+20)
  _cloud_bytes = values.to_byte_array()
  if transforms.is_empty():
   minimum = Vector2(-100,-100)
   maximum = Vector2(100,100)
  _shadow_bounds = Vector4(minimum.x-100,minimum.y-100,maximum.x-minimum.x+200,maximum.y-minimum.y+200)
 var state := settings.duplicate()
 state["cloud_key"] = key
 state["cloud_bytes"] = _cloud_bytes
 state["field_key"] = field_key
 state["field_bytes"] = _field_bytes
 state["field_dimensions"] = Vector3i(field_size.x,field_size.y,field_size.z*fields.size())
 state["cloud_inverse"] = clouds.global_transform.affine_inverse()
 state["active"] = active
 state["sun_direction"] = direction.normalized()
 state["shadow_x"] = _shadow_x
 state["shadow_y"] = _shadow_y
 state["shadow_bounds"] = _shadow_bounds
 _mutex.lock()
 _state = state
 _mutex.unlock()

static func _matrix_values(matrix: Projection) -> PackedFloat32Array:
 return PackedFloat32Array([matrix.x.x,matrix.x.y,matrix.x.z,matrix.x.w,
  matrix.y.x,matrix.y.y,matrix.y.z,matrix.y.w,
  matrix.z.x,matrix.z.y,matrix.z.z,matrix.z.w,
  matrix.w.x,matrix.w.y,matrix.w.z,matrix.w.w])

func _render_callback(kind: int, data: RenderData) -> void:
 if _rd == null or kind != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT: return
 _mutex.lock()
 var state := _state.duplicate()
 var failed: bool = not str(_status.error).is_empty()
 _mutex.unlock()
 if state.is_empty() or failed: return
 # ponytail: this camera effect is monoscopic; use per-view buffers before enabling XR.
 var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
 if buffers == null: return
 var size := buffers.get_internal_size()
 if size.x <= 0 or size.y <= 0: return
 var color := buffers.get_color_layer(0)
 var multisampled := buffers.get_msaa_3d() != RenderingServer.VIEWPORT_MSAA_DISABLED
 var depth := buffers.get_depth_layer(0,multisampled)
 if not color.is_valid() or not depth.is_valid(): return
 var samples := int(_rd.texture_get_format(depth).samples)
 if not _prepare_gpu(color,size,samples): return
 _prepare_density_field(state)
 var scene := data.get_render_scene_data()
 var projection: Projection = scene.get_cam_projection()
 var camera: Transform3D = scene.get_cam_transform()
 var sun: Vector3 = state.sun_direction
 var camera_sun := camera.basis.inverse()*sun
 var clip := projection*Vector4(camera_sun.x,camera_sun.y,camera_sun.z,0)
 var sun_uv := Vector2(-1,-1)
 if clip.w > 0.0: sun_uv = Vector2(clip.x,clip.y)/clip.w*0.5+Vector2(0.5,0.5)
 if state.has("sun_uv"): sun_uv = state.sun_uv
 # Godot4.7 Mobile divides linear lighting by2 for its packed UNORM HDR buffer.
 # get_luminance_multiplier is not script exposed; use the actual attachment format.
 var packed_hdr := _rd.texture_get_format(color).format == RenderingDevice.DATA_FORMAT_A2B10G10R10_UNORM_PACK32
 var luminance_multiplier := 2.0 if packed_hdr else 1.0
 var light: Color = state.get("light_color",Color(1.0,0.55,0.24))
 var ambient: Color = state.get("ambient_color",Color(0.10,0.18,0.30))
 light = light.srgb_to_linear()
 ambient = ambient.srgb_to_linear()
 var sx: Vector3 = state.shadow_x
 var sy: Vector3 = state.shadow_y
 var bounds: Vector4 = state.shadow_bounds
 var values := _matrix_values(projection.inverse())
 values.append_array(_matrix_values(Projection(camera)))
 values.append_array(_matrix_values(Projection(state.cloud_inverse)))
 values.append_array(PackedFloat32Array([sun.x,sun.y,sun.z,float(state.get("sun_enabled",true)),
  sx.x,sx.y,sx.z,0,sy.x,sy.y,sy.z,0,bounds.x,bounds.y,bounds.z,bounds.w,
  light.r,light.g,light.b,float(state.get("sun_strength",1.3)),ambient.r,ambient.g,ambient.b,luminance_multiplier,
  clampf(float(state.get("density",0.00012)),0,0.01),maxf(float(state.get("height_scale",750.0)),1),
  clampf(float(state.get("max_distance",4500.0)),100,10000),clampf(float(state.get("strength",1.0)),0,4),
  state.active,clampf(float(state.get("shadow_strength",1.0)),0,1),sun_uv.x,sun_uv.y,
  size.x,size.y,_low_size.x,_low_size.y]))
 _rd.buffer_update(_frame_buffer,0,FRAME_BYTES,values.to_byte_array())
 var compute := _rd.compute_list_begin()
 if _gpu_cloud_key != int(state.cloud_key):
  _rd.compute_list_end()
  _rd.buffer_update(_cloud_buffer,0,CLOUD_BYTES,state.cloud_bytes)
  compute = _rd.compute_list_begin()
  _dispatch(compute,0,[_buffer_uniform(0,_frame_buffer),_buffer_uniform(1,_cloud_buffer),_image_uniform(3,_shadow_texture),_sample_uniform(7,_density_texture,_density_sampler)],Vector2i(SHADOW_SIZE,SHADOW_SIZE))
  _rd.compute_list_add_barrier(compute)
  _gpu_cloud_key = state.cloud_key
  _mutex.lock()
  _status.shadow_bakes += 1
  _mutex.unlock()
 _dispatch(compute,1,[_buffer_uniform(0,_frame_buffer),_sample_uniform(2,depth),_image_uniform(6,_solar_texture)],Vector2i.ONE)
 var volume_enabled := float(state.get("strength",1.0)) > 0.0
 if volume_enabled: _dispatch(compute,2,[_buffer_uniform(0,_frame_buffer),_sample_uniform(2,depth),_image_uniform(3,_shadow_texture),_image_uniform(4,_fog_texture),_image_uniform(5,_distance_texture)],_low_size)
 _rd.compute_list_end()
 if volume_enabled:
  var uniforms: Array[RDUniform] = [_buffer_uniform(0,_frame_buffer),_sample_uniform(2,depth),_sample_uniform(4,_fog_texture),_sample_uniform(5,_distance_texture)]
  var set := UniformSetCacheRD.get_cache(_shaders[3],0,uniforms)
  var draw := _rd.draw_list_begin(_framebuffer)
  _rd.draw_list_bind_render_pipeline(draw,_pipelines[3])
  _rd.draw_list_bind_uniform_set(draw,set,0)
  _rd.draw_list_draw(draw,false,1,3)
  _rd.draw_list_end()
 _mutex.lock()
 _status.ready = true
 _status.frames += 1
 _status.native_color_format = _rd.texture_get_format(color).format
 _status.native_depth_samples = samples
 _status.quarter_size = _low_size
 _status.luminance_multiplier = luminance_multiplier
 _status.texture_allocations = _texture_allocations
 _status.framebuffer_builds = _framebuffer_builds
 _status.pipeline_builds = _pipeline_builds
 _status.field_uploads = _field_uploads
 _status.field_dimensions = _field_dimensions
 _mutex.unlock()

func _prepare_density_field(state: Dictionary) -> void:
 if _gpu_field_key == int(state.field_key): return
 var dimensions: Vector3i = state.field_dimensions
 if dimensions != _field_dimensions:
  if _density_texture.is_valid(): _rd.free_rid(_density_texture)
  _field_dimensions = dimensions
  var format := RDTextureFormat.new()
  format.texture_type = RenderingDevice.TEXTURE_TYPE_3D
  format.width = dimensions.x
  format.height = dimensions.y
  format.depth = dimensions.z
  format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
  format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
  _density_texture = _rd.texture_create(format,RDTextureView.new(),[state.field_bytes])
  _texture_allocations += 1
 else:
  _rd.texture_update(_density_texture,0,state.field_bytes)
 _field_uploads += 1
 _gpu_field_key = state.field_key

func _prepare_gpu(color: RID, size: Vector2i, samples: int) -> bool:
 if not _frame_buffer.is_valid():
  _frame_buffer = _rd.storage_buffer_create(FRAME_BYTES)
  _cloud_buffer = _rd.storage_buffer_create(CLOUD_BYTES)
  var sampler := RDSamplerState.new()
  sampler.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
  sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
  _sampler = _rd.sampler_create(sampler)
  sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
  sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
  _density_sampler = _rd.sampler_create(sampler)
  _shadow_texture = _texture(Vector2i(SHADOW_SIZE,SHADOW_SIZE),RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
  _solar_texture = _texture(Vector2i.ONE,RenderingDevice.DATA_FORMAT_R16_SFLOAT)
  solar_visibility_texture.texture_rd_rid = _solar_texture
 if _color != color:
  if _framebuffer.is_valid() and _rd.framebuffer_is_valid(_framebuffer): _rd.free_rid(_framebuffer)
  _color = color
  _framebuffer = _rd.framebuffer_create([color])
  _framebuffer_builds += 1
 var low := Vector2i(ceili(size.x/4.0),ceili(size.y/4.0))
 if low != _low_size:
  for texture in [_fog_texture,_distance_texture]:
   if texture.is_valid(): _rd.free_rid(texture)
  _low_size = low
  _fog_texture = _texture(low,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
  _distance_texture = _texture(low,RenderingDevice.DATA_FORMAT_R32_SFLOAT)
 var format := _rd.framebuffer_get_format(_framebuffer)
 if samples == _depth_samples and format == _framebuffer_format and _pipelines.size() == 4: return true
 for shader in _shaders:
  if shader.is_valid(): _rd.free_rid(shader)
 _shaders.clear()
 _pipelines.clear()
 _pipeline_builds += 1
 _depth_samples = samples
 _framebuffer_format = format
 var defines := ""
 if samples > 0: defines = "#define DEPTH_MULTISAMPLED\n#define DEPTH_SAMPLES %d\n" % (1<<samples)
 var compute_code := FileAccess.get_file_as_string(COMPUTE_PATH).replace("#[compute]\n","")
 for mode in ["PASS_SHADOW","PASS_SOLAR","PASS_SCATTER"]:
  var source := RDShaderSource.new()
  source.source_compute = compute_code.replace("#version 450","#version 450\n"+defines+"#define "+mode)
  var shader := _compile(source)
  if not shader.is_valid(): return false
  _shaders.append(shader)
  _pipelines.append(_rd.compute_pipeline_create(shader))
 var raster_code := FileAccess.get_file_as_string(COMPOSITE_PATH)
 var parts := raster_code.split("#[fragment]\n")
 var source := RDShaderSource.new()
 source.source_vertex = parts[0].replace("#[vertex]\n","")
 source.source_fragment = parts[1].replace("#version 450","#version 450\n"+defines)
 var shader := _compile(source)
 if not shader.is_valid(): return false
 _shaders.append(shader)
 var raster := RDPipelineRasterizationState.new()
 raster.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
 var blend := RDPipelineColorBlendState.new()
 var attachment := RDPipelineColorBlendStateAttachment.new()
 attachment.enable_blend = true
 attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
 attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_SRC_ALPHA
 attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ZERO
 attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
 blend.attachments = [attachment]
 _pipelines.append(_rd.render_pipeline_create(shader,format,-1,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend))
 _gpu_cloud_key = -1
 return _pipelines[3].is_valid()

func _compile(source: RDShaderSource) -> RID:
 var spirv := _rd.shader_compile_spirv_from_source(source)
 var error := spirv.compile_error_compute+spirv.compile_error_vertex+spirv.compile_error_fragment
 if not error.is_empty():
  _mutex.lock()
  _status.error = error
  _mutex.unlock()
  push_error(error)
  return RID()
 return _rd.shader_create_from_spirv(spirv)

func _texture(size: Vector2i, format: int) -> RID:
 var description := RDTextureFormat.new()
 description.width = size.x
 description.height = size.y
 description.format = format
 description.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
 _texture_allocations += 1
 return _rd.texture_create(description,RDTextureView.new())

func _dispatch(list: int, index: int, uniforms: Array[RDUniform], size: Vector2i) -> void:
 var set := UniformSetCacheRD.get_cache(_shaders[index],0,uniforms)
 _rd.compute_list_bind_compute_pipeline(list,_pipelines[index])
 _rd.compute_list_bind_uniform_set(list,set,0)
 _rd.compute_list_dispatch(list,ceili(size.x/8.0),ceili(size.y/8.0),1)

func _buffer_uniform(binding: int, buffer: RID) -> RDUniform:
 var uniform := RDUniform.new()
 uniform.binding = binding
 uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
 uniform.add_id(buffer)
 return uniform

func _image_uniform(binding: int, texture: RID) -> RDUniform:
 var uniform := RDUniform.new()
 uniform.binding = binding
 uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
 uniform.add_id(texture)
 return uniform

func _sample_uniform(binding: int, texture: RID, sampler: RID = RID()) -> RDUniform:
 var uniform := RDUniform.new()
 uniform.binding = binding
 uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
 uniform.add_id(sampler if sampler.is_valid() else _sampler)
 uniform.add_id(texture)
 return uniform

func _notification(what: int) -> void:
 if what != NOTIFICATION_PREDELETE or _rd == null: return
 solar_visibility_texture.texture_rd_rid = RID()
 var device := _rd
 var resources: Array[RID] = [_frame_buffer,_cloud_buffer,_shadow_texture,_solar_texture,_fog_texture,_distance_texture,_sampler,_density_texture,_density_sampler]
 resources.append_array(_shaders)
 var framebuffer := _framebuffer
 RenderingServer.call_on_render_thread(func():
  if framebuffer.is_valid() and device.framebuffer_is_valid(framebuffer): device.free_rid(framebuffer)
  for resource in resources:
   if resource.is_valid(): device.free_rid(resource)
 )
