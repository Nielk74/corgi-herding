extends Node
## Optional camera-owned visual study. No environment, sky, geometry or input
## resource is edited. Cloud motion uses a local clock, not shader TIME.
const EFFECT = preload("res://shaders/landscape_atmosphere.gdshader")
const MAX_ACTORS := 14
const MAX_STEP := 0.1
var camera: Camera3D
var screen: MeshInstance3D
var material: ShaderMaterial
var actors: Array[Node3D] = []
var clouds := false
var blur := false
var passthrough := false
var active := true
var focused := true
var foreground := true
var skip_step := true
var elapsed := 0.0
var rects := PackedVector4Array()

func configure(view: Camera3D, protected_actors: Array[Node3D], desert := false) -> bool:
	if camera != null or not is_instance_valid(view) or protected_actors.size() > MAX_ACTORS:
		return false
	camera = view
	process_priority = 100 # After ordinary actor interpolation/camera following.
	actors.assign(protected_actors)
	material = ShaderMaterial.new()
	material.shader = EFFECT
	# The screen copy contains opaque geometry. Draw BEFORE ordinary transparent
	# world labels/markers, otherwise an opaque screen pass would erase them.
	material.render_priority = -128
	material.set_shader_parameter("desert_warmth", 1.0 if desert else 0.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(3, -1, 0), Vector3(-1, 3, 0)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	screen = MeshInstance3D.new()
	screen.name = "AtmosphereStudyScreen"
	screen.mesh = mesh
	screen.material_override = material
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	screen.extra_cull_margin = 2.0
	camera.add_child(screen)
	screen.position.z = -1.0
	_sync()
	return true

func set_effects(show_clouds: bool, soften_distance: bool, show_passthrough := false) -> void:
	clouds = show_clouds
	blur = soften_distance
	passthrough = show_passthrough
	skip_step = true
	if material != null:
		material.set_shader_parameter("clouds_enabled", clouds)
		material.set_shader_parameter("blur_enabled", blur)
		if clouds or blur:
			_update_protection()
	_sync()

func set_active(value: bool) -> void:
	active = value
	skip_step = true
	_sync()

func _sync() -> void:
	var running := is_instance_valid(camera) and active and focused and foreground
	if is_instance_valid(screen):
		screen.visible = running and (clouds or blur or passthrough)
	set_process(running and (clouds or blur))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		foreground = false
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		foreground = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
	else:
		return
	skip_step = true
	_sync()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not active or not focused or not foreground or not is_instance_valid(camera) or not (clouds or blur):
		return
	if clouds or blur:
		_update_protection()
	if not is_finite(delta) or delta <= 0:
		return
	if skip_step:
		skip_step = false
		return
	if clouds:
		elapsed += minf(delta, MAX_STEP)
		material.set_shader_parameter("drift_time", elapsed)

func _update_protection() -> void:
	rects.resize(MAX_ACTORS)
	rects.fill(Vector4(-2, -2, -1, -1))
	var count := 0
	var size := camera.get_viewport().get_visible_rect().size
	if size.x <= 0 or size.y <= 0:
		material.set_shader_parameter("blur_enabled", false)
		material.set_shader_parameter("clouds_enabled", false)
		return
	for actor: Node3D in actors:
		if not is_instance_valid(actor) or not actor.is_visible_in_tree():
			continue
		var low := Vector2.INF
		var high := -Vector2.INF
		for node: Node in actor.find_children("*", "MeshInstance3D", true, false):
			if not node.is_visible_in_tree() or node.mesh == null:
				continue
			var bounds: AABB = node.get_aabb()
			for i in 8:
				var point: Vector3 = node.global_transform * bounds.get_endpoint(i)
				if camera.is_position_behind(point):
					# A partly clipped actor is safer with all blur disabled.
					material.set_shader_parameter("blur_enabled", false)
					material.set_shader_parameter("clouds_enabled", false)
					return
				var pixel := camera.unproject_position(point)
				low = low.min(pixel)
				high = high.max(pixel)
		if low.is_finite():
			low = (low - Vector2.ONE * 4.0) / size
			high = (high + Vector2.ONE * 4.0) / size
			rects[count] = Vector4(low.x, low.y, high.x, high.y)
			count += 1
	material.set_shader_parameter("actor_rects", rects)
	material.set_shader_parameter("actor_count", count)
	material.set_shader_parameter("blur_enabled", blur)
	material.set_shader_parameter("clouds_enabled", clouds)

func _exit_tree() -> void:
	if is_instance_valid(screen):
		screen.hide()
		screen.queue_free()
	screen = null
	material = null
	actors.clear()
	camera = null
