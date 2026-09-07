class_name MeadowDiorama
extends Node3D
## All meshes are original procedural geometry; no downloaded art dependencies.

const GRASS := Color("96ad78")
const DARK := Color("293f36")
const CREAM := Color("fff0d5")
var camera: Camera3D
var gate: Node3D
var destination: Node3D
var selection: Node3D
var preview: Node3D
var water: MeshInstance3D
var materials: Dictionary = {}
var elapsed := 0.0
var gate_open := false
var marker_age := 100.0
var zoom := 1.0

func _ready() -> void:
	_build_light()
	_build_land()
	_build_bridge()
	_build_fence()
	_build_details()
	_build_camera()
	destination = _ring(self, Vector3.ZERO, Color("fff2c8"), 0.42)
	destination.visible = false
	selection = _ring(self, Vector3.ZERO, Color("fff2c8"), 0.76)
	selection.visible = false
	_build_preview()

func material(color: Color, unshaded := false) -> StandardMaterial3D:
	var key := color.to_html() + str(unshaded)
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = mat
	return mat

func mesh(parent: Node3D, shape: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = material(color)
	instance.position = pos
	parent.add_child(instance)
	return instance

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, pos, color)

func ball(parent: Node3D, pos: Vector3, scale_value: Vector3, color: Color) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 0.5
	shape.height = 1.0
	shape.radial_segments = 12
	shape.rings = 6
	var node := mesh(parent, shape, pos, color)
	node.scale = scale_value
	return node

func cylinder(parent: Node3D, pos: Vector3, top: float, bottom: float, height: float, color: Color, sides := 10) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	shape.radial_segments = sides
	return mesh(parent, shape, pos, color)

func _build_light() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("cad6bd")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff1d8")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_color = Color("fff1d6")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 65
	add_child(sun)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(17, 30, 28)
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0))
	camera.current = true
	camera.near = 0.1
	camera.far = 150.0
	fit_camera()
	get_viewport().size_changed.connect(fit_camera)

func fit_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	camera.size = maxf(32.0, 47.0 / aspect) * zoom

func _build_land() -> void:
	box(self, Vector3(0, -1.2, 0), Vector3(35.5, 2.0, 23.5), Color("8d8865"))
	box(self, Vector3(-9.25, -0.12, 0), Vector3(15.5, 0.4, 22), GRASS)
	box(self, Vector3(9.25, -0.12, 0), Vector3(15.5, 0.4, 22), Color("a6b982"))
	box(self, Vector3(-1.67, -0.03, 0), Vector3(0.35, 0.5, 22), Color("b5bf93"))
	box(self, Vector3(1.67, -0.03, 0), Vector3(0.35, 0.5, 22), Color("b5bf93"))
	water = box(self, Vector3(0, -0.09, 0), Vector3(3.0, 0.14, 22), Color("80b4b1"))
	# An unobtrusive path shows the physical route across the meadow.
	box(self, Vector3(-5.6, 0.092, 0), Vector3(7.8, 0.015, 1.7), Color("bcc399"))
	box(self, Vector3(4.0, 0.092, 0), Vector3(4.65, 0.015, 1.7), Color("c5c59a"))
	box(self, Vector3(8.1, 0.092, 0), Vector3(3.9, 0.015, 1.7), Color("bcc795"))
	for i in range(18):
		var z := -10.5 + i * 1.2
		var stripe := box(self, Vector3(sin(i * 2.6) * 0.7, 0.002, z), Vector3(0.4 + fmod(i * 0.33, 0.5), 0.01, 0.04), Color("afcfbd"))
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_bridge() -> void:
	for i in range(12):
		box(self, Vector3(-1.78 + i * 0.325, 0.13, 0), Vector3(0.305, 0.20, 3.9), Color("cda77a") if i % 3 else Color("bf966b"))
	for z in [-2.0, 2.0]:
		for x in [-1.9, 0.0, 1.9]:
			box(self, Vector3(x, 0.62, z), Vector3(0.14, 1.16, 0.14), Color("8d7656"))
		box(self, Vector3(0, 0.92, z), Vector3(4.0, 0.12, 0.12), Color("b09066"))

func _build_fence() -> void:
	for side in [-1, 1]:
		for i in range(6):
			var z: float = side * (2.0 + i * 1.7)
			box(self, Vector3(6, 0.62, z), Vector3(0.18, 1.18, 0.18), Color("9e8361"))
			if i < 5:
				for y in [0.4, 0.87]:
					box(self, Vector3(6, y, z + side * 0.85), Vector3(0.10, 0.13, 1.7), Color("c5a47a"))
	gate = Node3D.new()
	gate.position = Vector3(6, 0, -2)
	add_child(gate)
	for z in [0.15, 1.0, 2.0, 3.0, 3.85]:
		box(gate, Vector3(0, 0.60, z), Vector3(0.13, 1.0, 0.14), Color("ae8960"))
	for y in [0.25, 0.9]:
		box(gate, Vector3(0, y, 2), Vector3(0.16, 0.15, 4), Color("c7a171"))
	var diagonal := box(gate, Vector3(0, 0.57, 2), Vector3(0.12, 0.12, 3.95), Color("b9966b"))
	diagonal.rotation.x = -0.16

func _build_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42079
	for i in range(105):
		var x := rng.randf_range(-16.5, 16.5)
		var z := rng.randf_range(-10.4, 10.4)
		if absf(x) < 2.2 or absf(z) < 2.0 or absf(x - 6) < 0.8:
			continue
		var grass := cylinder(self, Vector3(x, 0.17, z), 0.0, 0.11, rng.randf_range(0.14, 0.3), Color("7c9966"), 4)
		grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % 3 == 0:
			ball(self, Vector3(x, 0.30, z), Vector3(0.12, 0.10, 0.12), Color("f5e4ae") if i % 2 else Color("d0aec3"))
	for p in [Vector3(-14, 0, -8), Vector3(-10, 0, -9.5), Vector3(-15.2, 0, 5.7), Vector3(13, 0, -8.8), Vector3(15.6, 0, -5.8), Vector3(13.8, 0, 8.3)]:
		_tree(p, rng.randf_range(0.85, 1.15))
	for p in [Vector3(-2.4, 0, 7), Vector3(2.3, 0, -5), Vector3(-2.6, 0, -7.4), Vector3(15, 0, 4)]:
		ball(self, p + Vector3(0, 0.17, 0), Vector3(0.85, 0.50, 0.7), Color("b3b29b"))
		ball(self, p + Vector3(0.45, 0.12, 0.22), Vector3(0.4, 0.30, 0.4), Color("bcbba4"))
	# A place to rest, with no menu or reward machine.
	box(self, Vector3(11.6, 0.12, 5.5), Vector3(2.8, 0.04, 1.8), Color("d6bda0"))
	for x in [10.8, 12.4]:
		box(self, Vector3(x, 0.145, 5.5), Vector3(0.12, 0.03, 1.8), Color("f1dcc0"))
	var basket := cylinder(self, Vector3(12.8, 0.38, 4.9), 0.27, 0.23, 0.55, Color("b68d57"))
	basket.rotation.z = 0.07
	# One small wooden trail sign, shaped in world space.
	box(self, Vector3(4.4, 0.7, -3.1), Vector3(0.12, 1.4, 0.12), Color("9e8361"))
	box(self, Vector3(4.4, 1.15, -3.1), Vector3(1.0, 0.37, 0.12), Color("c6a475"))

func _tree(pos: Vector3, tree_scale: float) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * tree_scale
	add_child(tree)
	cylinder(tree, Vector3(0, 1.0, 0), 0.13, 0.23, 2, Color("8e7e5f"))
	ball(tree, Vector3(0, 2.7, 0), Vector3(2.5, 3.2, 2.5), Color("718d62"))
	ball(tree, Vector3(-0.7, 2.3, 0.2), Vector3(1.8, 1.9, 1.8), Color("88a071"))
	ball(tree, Vector3(0.55, 3.2, -0.15), Vector3(1.9, 2.2, 1.9), Color("91a778"))

func make_actor(kind: String, identity: String, second_herder := false) -> Node3D:
	var actor := Node3D.new()
	actor.name = identity
	add_child(actor)
	var body := Node3D.new()
	body.name = "Body"
	actor.add_child(body)
	match kind:
		"dog": _dog(body, identity == "maple")
		"sheep": _sheep(body, identity)
		"player": _herder(body, second_herder)
	return actor

func _dog(parent: Node3D, maple: bool) -> void:
	var coat := Color("b77d48") if maple else Color("d59b52")
	ball(parent, Vector3(0, 0.48, 0.10), Vector3(0.68, 0.65, 1.15), coat)
	ball(parent, Vector3(0, 0.64, -0.52), Vector3(0.72, 0.72, 0.61), coat)
	ball(parent, Vector3(0, 0.48, -0.25), Vector3(0.59, 0.51, 0.31), CREAM)
	ball(parent, Vector3(0, 0.54, -0.85), Vector3(0.45, 0.3, 0.34), CREAM)
	ball(parent, Vector3(0, 0.6, -1.01), Vector3(0.17, 0.12, 0.10), DARK)
	for side in [-1, 1]:
		var ear := cylinder(parent, Vector3(side * 0.25, 1.06, -0.48), 0.025, 0.18, 0.55, coat, 3)
		ear.rotation.z = side * -0.24
		ball(parent, Vector3(side * 0.23, 1.07, -0.58), Vector3(0.14, 0.27, 0.05), Color("e2b193"))
		ball(parent, Vector3(side * 0.23, 0.72, -0.78), Vector3(0.075, 0.085, 0.065), DARK)
		for z in [-0.25, 0.48]:
			box(parent, Vector3(side * 0.24, 0.17, z), Vector3(0.18, 0.29, 0.23), CREAM)
	var tail := ball(parent, Vector3(0, 0.68, 0.7), Vector3(0.26, 0.32, 0.34), CREAM)
	tail.name = "Tail"
	var collar := cylinder(parent, Vector3(0, 0.58, -0.42), 0.31, 0.31, 0.10, Color("729a97") if maple else Color("aa6970"))
	collar.rotation.x = PI / 2

func _sheep(parent: Node3D, identity: String) -> void:
	var wool := Color("f0e7d2") if identity.hash() % 3 == 0 else Color("fff4df")
	ball(parent, Vector3(0, 0.60, 0.08), Vector3(0.80, 0.85, 1.0), wool)
	for side in [-1, 1]:
		ball(parent, Vector3(side * 0.22, 0.79, 0.22), Vector3(0.5, 0.48, 0.65), wool)
		for z in [-0.23, 0.38]:
			box(parent, Vector3(side * 0.24, 0.21, z), Vector3(0.12, 0.36, 0.12), Color("766b58"))
		ball(parent, Vector3(side * 0.27, 0.78, -0.42), Vector3(0.27, 0.13, 0.18), Color("8d7c65"))
	ball(parent, Vector3(0, 0.66, -0.51), Vector3(0.42, 0.50, 0.45), Color("786c57"))
	ball(parent, Vector3(0, 0.91, -0.37), Vector3(0.48, 0.3, 0.4), wool)
	ball(parent, Vector3(0, 0.65, 0.65), Vector3(0.23, 0.25, 0.28), wool)

func _herder(parent: Node3D, second: bool) -> void:
	var coat := Color("b67764") if second else Color("4f8580")
	for side in [-1, 1]:
		box(parent, Vector3(side * 0.19, 0.34, 0), Vector3(0.24, 0.57, 0.29), Color("526150"))
		ball(parent, Vector3(side * 0.19, 0.10, -0.10), Vector3(0.28, 0.21, 0.42), Color("705d49"))
		ball(parent, Vector3(side * 0.46, 0.94, 0), Vector3(0.21, 0.72, 0.26), coat)
	cylinder(parent, Vector3(0, 0.98, 0), 0.32, 0.43, 0.82, coat)
	ball(parent, Vector3(0, 1.64, 0), Vector3(0.58, 0.60, 0.58), Color("dca77d"))
	cylinder(parent, Vector3(0, 1.90, 0), 0.56, 0.56, 0.08, Color("e5cc95"))
	cylinder(parent, Vector3(0, 2.08, 0), 0.22, 0.34, 0.32, Color("d2b67e"))
	box(parent, Vector3(0, 1.45, -0.25), Vector3(0.22, 0.16, 0.13), Color("d3a15e"))

func _ring(parent: Node3D, pos: Vector3, color: Color, radius: float) -> Node3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - 0.035
	shape.outer_radius = radius + 0.035
	shape.rings = 24
	shape.ring_segments = 6
	var ring := mesh(parent, shape, pos + Vector3(0, 0.18, 0), color)
	ring.material_override = material(color, true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring

func _build_preview() -> void:
	preview = Node3D.new()
	add_child(preview)
	for i in range(10):
		var sheep := make_actor("sheep", "preview_s%d" % i)
		sheep.reparent(preview)
		sheep.position = Vector3(-6.5 + sin(i * 2.3) * 2.9, 0.11, -1.6 + cos(i * 1.6) * 2.7)
		sheep.rotation.y = i * 0.9
	for i in range(2):
		var dog := make_actor("dog", "mochi" if i == 0 else "maple")
		dog.reparent(preview)
		dog.position = Vector3(-10 + i * 3, 0.11, 3.3)
		dog.rotation.y = -0.5 + i

func mark_destination(pos: Vector3) -> void:
	destination.position = pos + Vector3(0, 0.18, 0)
	destination.visible = true
	marker_age = 0.0

func ground_at(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.001:
		return Vector3.INF
	var result := origin + direction * ((0.10 - origin.y) / direction.y)
	if absf(result.x) > 17 or absf(result.z) > 11:
		return Vector3.INF
	return result

func _process(delta: float) -> void:
	elapsed += delta
	marker_age += delta
	destination.visible = marker_age < 2.0
	destination.scale = Vector3.ONE * (1.0 + sin(marker_age * 5) * 0.1)
	gate.rotation.y = lerp_angle(gate.rotation.y, -1.45 if gate_open else 0.0, minf(delta * 4, 1.0))
