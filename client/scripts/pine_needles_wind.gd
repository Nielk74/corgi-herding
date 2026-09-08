extends Node
## Optional pine-crown material/clock prototype. Does not discover or modify
## props, meshes, buffers, cull bounds, scenes or cooked resources. A future
## explicitly approved caller may assign selected_material() to crown surface 1.

const SHADER = preload("res://shaders/pine_needles_wind.gdshader")
const MAX_DISPLACEMENT := 0.08
const ROOT_HEIGHT := 1.7
const BEND_SPAN := 3.8
const MAX_FRAME_STEP := 0.1
const DIRECTION := Vector3(0.8, 0, 0.6)

var _source: StandardMaterial3D
var _candidate: ShaderMaterial
var _enabled := false
var _active := true
var _focused := true
var _resumed := true
var _elapsed := 0.0
var _discarded := 0.0
var _skip_next_step := false

func _ready() -> void:
	_apply_running()

func configure(source: StandardMaterial3D) -> bool:
	if _source != null or source == null:
		return false
	# This narrow candidate deliberately does not approximate arbitrary PBR
	# materials. Only the current untextured, opaque pine-needle setup is valid.
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or source.cull_mode != BaseMaterial3D.CULL_BACK:
		return false
	if not source.vertex_color_use_as_albedo or not source.vertex_color_is_srgb or source.metallic != 0 or source.albedo_texture != null or source.normal_enabled or source.emission_enabled or source.next_pass != null:
		return false
	if source.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY or source.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX:
		return false
	_source = source
	return true

func set_enabled(value: bool) -> void:
	if _source == null:
		return
	if value and _candidate == null:
		_candidate = ShaderMaterial.new()
		_candidate.shader = SHADER
		_candidate.set_shader_parameter("needle_tint", _source.albedo_color)
		_candidate.set_shader_parameter("needle_roughness", _source.roughness)
		_candidate.set_shader_parameter("needle_specular", _source.metallic_specular)
		_candidate.set_shader_parameter("wind_time", _elapsed)
	if value != _enabled:
		_skip_next_step = true
	_enabled = value
	if _candidate != null:
		_candidate.set_shader_parameter("wind_strength", 1.0 if _enabled else 0.0)
	_apply_running()

func selected_material() -> Material:
	return _candidate if _enabled else _source

func set_active(value: bool) -> void:
	if value != _active:
		_skip_next_step = true
	_active = value
	_apply_running()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_resumed = false
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_resumed = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
	else:
		return
	_skip_next_step = true
	_apply_running()

func _apply_running() -> void:
	set_process(_enabled and _active and _focused and _resumed)

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not _enabled or not _active or not _focused or not _resumed or not is_finite(delta) or delta <= 0:
		return
	# First returned frame may contain background wall time. Discard it entirely;
	# subsequent long stalls advance at most one tenth of a second, never catch up.
	if _skip_next_step:
		_skip_next_step = false
		_discarded += delta
		return
	_discarded += maxf(0, delta - MAX_FRAME_STEP)
	_elapsed += minf(delta, MAX_FRAME_STEP)
	_candidate.set_shader_parameter("wind_time", _elapsed)

static func deformed(point: Vector3, normal: Vector3, model: Transform3D, time: float, strength := 1.0) -> Dictionary:
	# CPU reference for tests/authoring only; never called per vertex at runtime.
	var result := {"point": point, "normal": normal}
	if strength <= 0:
		return result
	var direction_scale := (model.basis * DIRECTION).length()
	if direction_scale <= 0.000001:
		return result
	var phase := model.origin.x * 0.37 + model.origin.z * 0.19
	var wave := 0.72 * sin(time * 0.63 + phase) + 0.28 * sin(time * 0.91 + phase * 1.7)
	var u := clampf((point.y - ROOT_HEIGHT) / BEND_SPAN, 0, 1)
	var weight := u * u * (3 - 2 * u)
	var derivative := 6 * u * (1 - u) / BEND_SPAN
	var shear := MAX_DISPLACEMENT * clampf(strength, 0, 1) * wave / direction_scale
	result.point = point + DIRECTION * shear * weight
	var n := normal
	n.y -= normal.dot(DIRECTION) * shear * derivative
	result.normal = n.normalized()
	return result

static func expanded_bounds(bounds: AABB, world_basis := Basis.IDENTITY) -> AABB:
	# A world-space displacement sphere mapped to batch space. This also handles
	# a transformed scene parent without assuming that its basis is uniform.
	var inverse := world_basis.inverse()
	var reach := Vector3(Vector3(inverse.x.x, inverse.y.x, inverse.z.x).length(),
		Vector3(inverse.x.y, inverse.y.y, inverse.z.y).length(),
		Vector3(inverse.x.z, inverse.y.z, inverse.z.z).length()) * MAX_DISPLACEMENT
	return AABB(bounds.position - reach, bounds.size + reach * 2)

func debug_state() -> Dictionary:
	return {"configured": _source != null, "enabled": _enabled, "active": _active,
		"focused": _focused, "resumed": _resumed, "elapsed": _elapsed,
		"discarded_time": _discarded, "materials_created": 1 if _candidate != null else 0,
		"added_meshes": 0, "added_draw_batches": 0, "maximum_displacement": MAX_DISPLACEMENT}
