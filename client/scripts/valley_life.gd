extends Node3D
## Decorative, client-only life: never collision, picking or authoritative AI.
## Attach beside (not inside) the static terrain/occluder subtree.

const BIRD_COUNT := 3
const TRIANGLES_PER_BIRD := 8
const MAX_FRAME_STEP := 0.1
const WING_FLEX := 0.15
const FLIGHT_CLEARANCE := 14.0
const SILHOUETTE_REACH := 1.0
const MATERIAL_CODE := """shader_type spatial;
render_mode unshaded, cull_disabled;
void vertex() {
    VERTEX.y += abs(VERTEX.x) * INSTANCE_CUSTOM.x;
}
void fragment() {
    ALBEDO = vec3(0.28, 0.35, 0.38);
    ROUGHNESS = 1.0;
}
"""
var configured := false
var elapsed := 0.0
var active := true
var foreground := true
var _focused := true
var _resumed := true
var _birds: Array[Dictionary] = []
var _instances: MultiMeshInstance3D
var _buffer := PackedFloat32Array()
var _flight_bounds := AABB()
var _sampling_calls := 0
var _discarded_time := 0.0
var _seed := 0

func _ready() -> void:
	name = "DecorativeValleyLife"
	set_meta("decorative_only", true)
	set_meta("affects_navigation", false)
	_apply_running()

func configure(surface_source: Object, bounds: Rect2, seed_value := 73451) -> bool:
	if configured or surface_source == null or not surface_source.has_method("surface_height"):
		return false
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x < 80 or bounds.size.y < 100 or bounds.size.x > 512 or bounds.size.y > 512:
		return false
	if maxf(bounds.position.abs().x, bounds.position.abs().y) > 1024 or maxf(bounds.end.abs().x, bounds.end.abs().y) > 1024:
		return false
	_seed = seed_value
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var fractions := [Vector2(0.18, 0.71), Vector2(0.55, 0.25), Vector2(0.78, 0.53)]
	var radii := [Vector2(17, 12), Vector2(22, 15), Vector2(16, 11)]
	for i in BIRD_COUNT:
		var center: Vector2 = bounds.position + bounds.size * fractions[i]
		var radius: Vector2 = radii[i]
		center.x = clampf(center.x, bounds.position.x + radius.x + 3, bounds.end.x - radius.x - 3)
		center.y = clampf(center.y, bounds.position.y + radius.y + 3, bounds.end.y - radius.y - 3)
		var maximum := -INF
		# One-unit piecewise-linear triangles cannot exceed their corner heights.
		# Cover the full bounding rectangle, not just sampled points on the orbit.
		# Include the entire banked/wing-flexed silhouette, not just its center.
		for x in range(floori(center.x - radius.x - SILHOUETTE_REACH), ceili(center.x + radius.x + SILHOUETTE_REACH) + 1):
			for z in range(floori(center.y - radius.y - SILHOUETTE_REACH), ceili(center.y + radius.y + SILHOUETTE_REACH) + 1):
				var height: float = surface_source.surface_height(x, z)
				_sampling_calls += 1
				if not is_finite(height):
					_birds.clear()
					return false
				maximum = maxf(maximum, height)
		_birds.append({"center": center, "radius": radius, "height": maximum + FLIGHT_CLEARANCE + i * 2.0,
			"phase": random.randf_range(0, TAU), "speed": 0.036 + i * 0.005,
			"scale": 0.9 + i * 0.1, "wing_offset": random.randf_range(4, 30), "maximum_ground": maximum})
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = _bird_mesh()
	multi.instance_count = BIRD_COUNT
	_buffer.resize(BIRD_COUNT * 16)
	_instances = MultiMeshInstance3D.new()
	_instances.name = "DecorativeGlidingBirds"
	_instances.set_meta("decorative_only", true)
	_instances.multimesh = multi
	_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instances.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_instances.extra_cull_margin = 0.2
	var shader := Shader.new()
	shader.code = MATERIAL_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	_instances.material_override = material
	add_child(_instances)
	for i in BIRD_COUNT:
		var bird: Dictionary = _birds[i]
		var rectangle := AABB(Vector3(bird.center.x - bird.radius.x - 2, bird.height - 2, bird.center.y - bird.radius.y - 2),
			Vector3(bird.radius.x * 2 + 4, 4, bird.radius.y * 2 + 4))
		_flight_bounds = rectangle if i == 0 else _flight_bounds.merge(rectangle)
	multi.custom_aabb = _flight_bounds
	configured = true
	_write_instances()
	_apply_running()
	return true

func _bird_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	# Two slender body faces plus three tapered facets on each swept wing.
	var body := [Vector3(0, 0, -0.40), Vector3(0.065, 0, 0.06), Vector3(0, 0, 0.30), Vector3(-0.065, 0, 0.06)]
	vertices.append_array(PackedVector3Array([body[0], body[1], body[2], body[0], body[2], body[3]]))
	for side in [-1.0, 1.0]:
		var wing := [Vector3(0.04 * side, 0, -0.16), Vector3(0.38 * side, 0.03, -0.06),
			Vector3(0.75 * side, 0.05, 0.14), Vector3(0.48 * side, 0.02, 0.13), Vector3(0.08 * side, 0, 0.08)]
		for ids in [[0, 1, 4], [1, 3, 4], [1, 2, 3]]:
			for index: int in ids:
				vertices.append(wing[index])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func set_active(value: bool) -> void:
	active = value
	_apply_running()

func _apply_running() -> void:
	set_process(configured and active and foreground)
	visible = configured and active

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
	foreground = _focused and _resumed
	if is_inside_tree():
		_apply_running()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not configured or not active or not foreground or not is_visible_in_tree() or not is_finite(delta) or delta <= 0:
		return
	# A resumed application never races through missed minutes of visual motion.
	_discarded_time += maxf(0, delta - MAX_FRAME_STEP)
	elapsed += minf(delta, MAX_FRAME_STEP)
	_write_instances()

func _write_instances() -> void:
	for i in BIRD_COUNT:
		var bird: Dictionary = _birds[i]
		var theta: float = bird.phase + elapsed * bird.speed
		var position := Vector3(bird.center.x + cos(theta) * bird.radius.x,
			bird.height + sin(theta * 1.3) * 0.35, bird.center.y + sin(theta) * bird.radius.y)
		var direction := Vector3(-sin(theta) * bird.radius.x, 0, cos(theta) * bird.radius.y).normalized()
		var basis := Basis.looking_at(direction) * Basis(Vector3.FORWARD, sin(theta * 0.7) * 0.10)
		basis = basis.scaled(Vector3.ONE * bird.scale)
		var values := [basis.x.x, basis.y.x, basis.z.x, position.x,
			basis.x.y, basis.y.y, basis.z.y, position.y,
			basis.x.z, basis.y.z, basis.z.z, position.z]
		for component in 12:
			_buffer[i * 16 + component] = values[component]
		# Almost all flight is a still-wing glide. A brief soft flex is driven by
		# explicit time, so it freezes with the component instead of shader TIME.
		var phase: float = fmod(elapsed + bird.wing_offset, 47.0 + i * 7.0)
		var flex := 0.0
		if phase < 1.8:
			flex = sin(phase * TAU * 2.0) * smoothstep(0, 0.35, phase) * (1.0 - smoothstep(1.3, 1.8, phase)) * WING_FLEX
		_buffer[i * 16 + 12] = flex
	_instances.multimesh.buffer = _buffer

func debug_state() -> Dictionary:
	return {"configured": configured, "birds": _birds.duplicate(true), "count": _birds.size(),
		"draw_batches": 1 if configured else 0, "triangles": BIRD_COUNT * TRIANGLES_PER_BIRD if configured else 0,
		"bounds": _flight_bounds, "sampling_calls": _sampling_calls, "elapsed": elapsed,
		"discarded_time": _discarded_time, "active": active, "foreground": foreground, "seed": _seed}
