extends Node3D
## Optional authoring-only ambient seeds/dust. Attach beside terrain in the
## same recipe coordinates; never inside its picking/occluder subtree.
## No camera/player tracking, shader TIME, collision, audio or gameplay state.

const MAX_MOTES := 12
const TYPICAL_MAX := 4
const TRIANGLES_PER_MOTE := 8
const MAX_FRAME_STEP := 0.1
const CYCLE_SECONDS := 136.0
const MESH_REACH := 0.14
const BURST_STARTS := [6.0, 39.0, 72.0, 106.0]
const BURST_DURATIONS := [7.2, 8.6, 6.8, 8.0]
var configured := false
var _enabled := false
var _active := true
var _focused := true
var _resumed := true
var _tree_paused := false
var _skip_next_step := true
var _phase := 0.0
var _discarded := 0.0
var _bursts: Array[Dictionary] = []
var _instances: MultiMeshInstance3D
var _buffer := PackedFloat32Array()
var _bounds := AABB()
var _area := Rect2()
var _ground_min := INF
var _ground_max := -INF
var _minimum_clearance := INF
var _maximum_clearance := 0.0
var _sampling_calls := 0
var _visible_count := 0
var _biome := ""

func _ready() -> void:
	name = "OptionalLandscapeMotes"
	set_meta("decorative_only", true)
	set_meta("affects_navigation", false)
	# A packed decorative pose is not a saved simulation clock. A reloaded
	# optional helper starts empty/disabled and requires explicit configuration.
	if not configured:
		var saved_pose := get_node_or_null("OpaqueWindMotes")
		if saved_pose is MultiMeshInstance3D and saved_pose.get_meta("decorative_only", false):
			remove_child(saved_pose)
			saved_pose.free()
	_apply_running()

func configure(surface_source: Object, authoring_focus: Vector2, biome: String, seed_value := 62841, half_extent := Vector2(6, 4)) -> bool:
	if configured or surface_source == null or not surface_source.has_method("surface_height") or biome not in ["alpine", "cactus"]:
		return false
	if not authoring_focus.is_finite() or not half_extent.is_finite() or minf(half_extent.x, half_extent.y) < 2 or maxf(half_extent.x, half_extent.y) > 12:
		return false
	var area := Rect2(authoring_focus - half_extent, half_extent * 2)
	if maxf(area.position.abs().x, area.position.abs().y) > 1024 or maxf(area.end.abs().x, area.end.abs().y) > 1024:
		return false
	_ground_min = INF
	_ground_max = -INF
	_sampling_calls = 0
	# Actual one-unit triangle meshes cannot exceed their vertex heights. Sample
	# the whole covered rectangle, including each possible rotated tiny vertex,
	# once; no per-frame terrain queries or estimated analytic ground.
	for x in range(floori(area.position.x), ceili(area.end.x) + 1):
		for z in range(floori(area.position.y), ceili(area.end.y) + 1):
			var height: float = surface_source.surface_height(x, z)
			_sampling_calls += 1
			if not is_finite(height) or absf(height) > 256:
				return false
			_ground_min = minf(_ground_min, height)
			_ground_max = maxf(_ground_max, height)
	_area = area
	_biome = biome
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	_bursts.clear()
	_minimum_clearance = INF
	_maximum_clearance = 0.0
	for index in BURST_STARTS.size():
		var tracks: Array[Dictionary] = []
		for track in random.randi_range(2, TYPICAL_MAX):
			var drift := Vector2(random.randf_range(1.0, 2.0), random.randf_range(0.25, 0.7))
			var crosswind := Vector2(-drift.y, drift.x).normalized()
			var bend := random.randf_range(0.2, 0.5)
			var margin := drift.abs() * 0.5 + crosswind.abs() * bend + Vector2.ONE * MESH_REACH
			var center := authoring_focus + Vector2(random.randf_range(-half_extent.x + margin.x, half_extent.x - margin.x), random.randf_range(-half_extent.y + margin.y, half_extent.y - margin.y))
			var height := random.randf_range(0.65, 1.15) if biome == "alpine" else random.randf_range(0.4, 0.65)
			var lift := random.randf_range(0.12, 0.25) if biome == "alpine" else random.randf_range(0.05, 0.12)
			var tint := Color("697150") if biome == "alpine" else Color("8b7357")
			tint = tint.darkened(random.randf_range(0.0, 0.12))
			tracks.append({"center": center, "drift": drift, "crosswind": crosswind, "bend": bend,
				"height": _ground_max + height, "lift": lift, "phase": random.randf_range(0, TAU),
				"yaw": random.randf_range(-PI, PI), "scale": random.randf_range(0.7, 1.0), "color": tint})
			_minimum_clearance = minf(_minimum_clearance, height - 0.03 - MESH_REACH)
			_maximum_clearance = maxf(_maximum_clearance, _ground_max - _ground_min + height + lift + 0.03 + MESH_REACH)
		_bursts.append({"start": BURST_STARTS[index], "duration": BURST_DURATIONS[index], "tracks": tracks})
	var mesh := _mote_mesh(biome)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.metallic_specular = 0.0
	mesh.surface_set_material(0, material)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = MAX_MOTES
	multi.visible_instance_count = 0
	_buffer.resize(MAX_MOTES * 16)
	_buffer.fill(0.0)
	_bounds = AABB(Vector3(area.position.x, _ground_min, area.position.y), Vector3(area.size.x, _ground_max - _ground_min + 2.0, area.size.y))
	multi.custom_aabb = _bounds
	_instances = MultiMeshInstance3D.new()
	_instances.name = "OpaqueWindMotes"
	_instances.multimesh = multi
	_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instances.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_instances.visibility_range_end = 75.0
	_instances.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	_instances.set_meta("decorative_only", true)
	add_child(_instances)
	_instances.owner = self
	configured = true
	_write_instances()
	_apply_running()
	return true

func _mote_mesh(biome: String) -> ArrayMesh:
	var dimensions := Vector3(0.105, 0.012, 0.032) if biome == "alpine" else Vector3(0.047, 0.016, 0.039)
	var points := [Vector3(-dimensions.x, 0, 0), Vector3(0, 0, -dimensions.z), Vector3(dimensions.x * 0.7, 0, 0), Vector3(0, 0, dimensions.z * 0.8), Vector3(0, dimensions.y, 0), Vector3(0, -dimensions.y, 0)]
	var vertices := PackedVector3Array()
	for i in 4:
		vertices.append_array(PackedVector3Array([points[i], points[(i + 1) % 4], points[4], points[(i + 1) % 4], points[i], points[5]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func set_enabled(value: bool) -> void:
	if value != _enabled: _skip_next_step = true
	_enabled = value
	_apply_running()

func set_active(value: bool) -> void:
	if value != _active: _skip_next_step = true
	_active = value
	_apply_running()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED: _resumed = false
		NOTIFICATION_APPLICATION_RESUMED: _resumed = true
		NOTIFICATION_APPLICATION_FOCUS_OUT: _focused = false
		NOTIFICATION_APPLICATION_FOCUS_IN: _focused = true
		NOTIFICATION_PAUSED: _tree_paused = true
		NOTIFICATION_UNPAUSED: _tree_paused = false
		NOTIFICATION_VISIBILITY_CHANGED: pass
		_: return
	_skip_next_step = true
	_apply_running()

func _apply_running() -> void:
	var running := configured and _enabled and _active and _focused and _resumed and not _tree_paused
	if is_instance_valid(_instances): _instances.visible = running
	set_process(running and is_visible_in_tree())

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not configured or not _enabled or not _active or not _focused or not _resumed or _tree_paused or not is_visible_in_tree() or not is_finite(delta) or delta <= 0:
		return
	if _skip_next_step:
		_skip_next_step = false
		_discarded = minf(_discarded + delta, 1.0e9)
		return
	_discarded = minf(_discarded + maxf(0, delta - MAX_FRAME_STEP), 1.0e9)
	_phase = fmod(_phase + minf(delta, MAX_FRAME_STEP), CYCLE_SECONDS)
	_write_instances()

func _write_instances() -> void:
	_buffer.fill(0.0)
	_visible_count = 0
	for burst in _bursts:
		var age: float = _phase - burst.start
		if age <= 0 or age >= burst.duration: continue
		var u: float = age / burst.duration
		var envelope := smoothstep(0, 1.3, age) * (1.0 - smoothstep(burst.duration - 1.8, burst.duration, age))
		for track: Dictionary in burst.tracks:
			var flat: Vector2 = track.center + track.drift * (u - 0.5) + track.crosswind * track.bend * sin(PI * u)
			var position := Vector3(flat.x, track.height + track.lift * sin(PI * u) + sin(u * TAU + track.phase) * 0.03, flat.y)
			var basis := Basis.from_euler(Vector3(0.12 * sin(u * PI + track.phase), track.yaw + 0.2 * u, 0.1 * sin(u * PI))).scaled(Vector3.ONE * track.scale * envelope)
			var values := [basis.x.x, basis.y.x, basis.z.x, position.x, basis.x.y, basis.y.y, basis.z.y, position.y, basis.x.z, basis.y.z, basis.z.z, position.z, track.color.r, track.color.g, track.color.b, 1.0]
			for component in 16: _buffer[_visible_count * 16 + component] = values[component]
			_visible_count += 1
		break
	_instances.multimesh.buffer = _buffer
	# Retain the CPU payload for headless inspection/resource serialization too.
	_instances.multimesh.set_meta("cpu_instance_buffer", _buffer)
	_instances.multimesh.visible_instance_count = _visible_count

func debug_state() -> Dictionary:
	return {"configured": configured, "enabled": _enabled, "active": _active, "focused": _focused, "resumed": _resumed, "tree_paused": _tree_paused,
		"phase": _phase, "discarded_time": _discarded, "biome": _biome, "bursts": _bursts.duplicate(true), "area": _area, "bounds": _bounds,
		"ground_min": _ground_min, "ground_max": _ground_max, "minimum_clearance_bound": _minimum_clearance, "maximum_clearance_bound": _maximum_clearance,
		"terrain_samples": _sampling_calls, "visible_motes": _visible_count if is_instance_valid(_instances) and _instances.visible and is_visible_in_tree() else 0,
		"retained_motes": _visible_count, "max_instances": MAX_MOTES, "max_triangles": MAX_MOTES * TRIANGLES_PER_MOTE,
		"draw_batches": 1 if configured else 0, "cpu_buffer_floats": _buffer.size(), "minimum_global_gap": 24.4}
