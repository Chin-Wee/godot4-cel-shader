@tool
extends CompositorEffect

const SHADER_FILE := "ror2-sobel.glsl"
const WORKGROUP_SIZE := 8

@export_range(0.0, 4.0, 0.01) var edge_threshold := 0.2
@export_range(0.0, 8.0, 0.01) var depth_weight := 1.0
@export_range(0.0, 8.0, 0.01) var normal_weight := 1.0
@export_range(1.0, 8.0, 1.0) var outline_width_px := 1.0
@export var outline_color := Color.BLACK

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _compile_attempted := false


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	needs_normal_roughness = true
	_rd = RenderingServer.get_rendering_device()


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _rd == null:
		return
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
	if _sampler.is_valid():
		_rd.free_rid(_sampler)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if _rd == null or callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null or not buffers.has_texture("forward_clustered", "normal_roughness"):
		return
	if not _ensure_pipeline():
		return

	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return

	var push_constants := PackedFloat32Array([
		edge_threshold, depth_weight, normal_weight, outline_width_px,
		float(size.x), float(size.y), 0.0, 0.0,
		outline_color.r, outline_color.g, outline_color.b, outline_color.a,
	])
	var groups_x := ceili(float(size.x) / WORKGROUP_SIZE)
	var groups_y := ceili(float(size.y) / WORKGROUP_SIZE)

	for view in range(buffers.get_view_count()):
		var color_image := buffers.get_color_layer(view)
		var depth_texture := buffers.get_depth_layer(view)
		var normal_texture := buffers.get_texture_slice(
			"forward_clustered", "normal_roughness", view, 0, 1, 1
		)
		if not color_image.is_valid() or not depth_texture.is_valid() or not normal_texture.is_valid():
			continue

		var uniforms: Array[RDUniform] = []
		var color_uniform := RDUniform.new()
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color_uniform.binding = 0
		color_uniform.add_id(color_image)
		uniforms.append(color_uniform)
		uniforms.append(_sampler_uniform(1, depth_texture))
		uniforms.append(_sampler_uniform(2, normal_texture))
		var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, uniforms)

		var compute_list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
		_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		_rd.compute_list_set_push_constant(
			compute_list, push_constants.to_byte_array(), push_constants.size() * 4
		)
		_rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
		_rd.compute_list_end()


func _sampler_uniform(binding: int, texture: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(_sampler)
	uniform.add_id(texture)
	return uniform


func _ensure_pipeline() -> bool:
	if _pipeline.is_valid() and _sampler.is_valid():
		return true
	if _compile_attempted:
		return false
	_compile_attempted = true

	var shader_path: String = get_script().resource_path.get_base_dir().path_join(SHADER_FILE)
	var shader_file := load(shader_path) as RDShaderFile
	if shader_file == null:
		push_error("Could not load Sobel RDShaderFile at %s" % shader_path)
		return false
	if not shader_file.base_error.is_empty():
		push_error(shader_file.base_error)
		return false

	var spirv := shader_file.get_spirv()
	if spirv == null:
		push_error("Sobel shader has no compiled SPIR-V version")
		return false
	if not spirv.compile_error_compute.is_empty():
		push_error(spirv.compile_error_compute)
		return false

	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		return false
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		return false

	var sampler_state := RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(sampler_state)
	return _sampler.is_valid()
