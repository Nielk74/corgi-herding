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
var landscape := ""
var terrain: Node3D
var world_environment: Environment
var vertex_material: StandardMaterial3D
var horizon_material: StandardMaterial3D
var camera_focus := Vector3(-4.0, 1.8, -6.0)
var desired_focus := Vector3(-4.0, 1.8, -6.0)
const CAMERA_OFFSET := Vector3(8, 28, 38)

func _ready() -> void:
	_build_light()
	set_landscape("alpine")
	_build_camera()
	destination = _ring(self, Vector3.ZERO, Color("fff2c8"), 0.42)
	destination.visible = false
	selection = _ring(self, Vector3.ZERO, Color("fff2c8"), 0.76)
	selection.visible = false
	_build_preview()

func set_landscape(id: String) -> void:
	var next := "cactus" if id == "cactus" else "alpine"
	if next == landscape and is_instance_valid(terrain):
		return
	landscape = next
	if is_instance_valid(terrain):
		terrain.hide()
		terrain.queue_free()
	terrain = Node3D.new()
	terrain.name = "Landscape_" + landscape
	add_child(terrain)
	if world_environment != null:
		world_environment.background_color = Color("d8c1a1") if landscape == "cactus" else Color("bdcfd0")
	_build_land()
	_build_backdrop()
	_build_boundaries()
	_build_bridge()
	_build_fence()
	_build_details()

func _color(alpine: String, cactus: String) -> Color:
	return Color(cactus if landscape == "cactus" else alpine)

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
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("cad6bd")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e8efeb")
	environment.ambient_light_energy = 0.35
	# Compatibility renders into an LDR buffer: keep the lighting below clipping.
	# Linear tonemapping also preserves the authored grass/water palette on Android.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment = environment
	environment_node.environment = environment
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_color = Color("fffdf6")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 65
	add_child(sun)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = camera_focus + CAMERA_OFFSET
	add_child(camera)
	camera.look_at(camera_focus)
	camera.current = true
	camera.near = 0.1
	camera.far = 150.0
	fit_camera()
	get_viewport().size_changed.connect(fit_camera)

func fit_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	# Preserve animal readability on phones; gentle horizontal following reveals the valley.
	camera.size = maxf(32.0, 25.5 / aspect) * zoom

func follow_player(pos: Vector3) -> void:
	# A broad quiet center means petting and short walks never move the camera.
	var offset := pos.x - desired_focus.x
	if absf(offset) > 5.8:
		desired_focus.x = clampf(pos.x - signf(offset) * 5.8, -6.0, 6.0)

func _build_land() -> void:
	# Continuous terrain goes far beyond the walkable valley; there is no board rim.
	for side in [-1, 1]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ix in range(21):
			for iz in range(44):
				var x0: float = side * (1.5 + ix * 3.0)
				var x1: float = side * (1.5 + (ix + 1) * 3.0)
				var z0 := -68.0 + iz * 3.0
				var z1 := z0 + 3.0
				var a := Vector3(x0, _terrain_height(x0, z0), z0)
				var b := Vector3(x1, _terrain_height(x1, z0), z0)
				var c := Vector3(x1, _terrain_height(x1, z1), z1)
				var d := Vector3(x0, _terrain_height(x0, z1), z1)
				var shade := 0.975 + sin(ix * 4.72 + iz * 1.18) * 0.022
				var color := _color("99b37d", "d9b47f") * Color(shade, shade, shade, 1)
				_ground_triangle(surface, a, b, c, color)
				_ground_triangle(surface, a, c, d, color.lightened(0.008))
		_finish_surface(surface, "ValleyGround")
	# The river disappears into the foothills, not up into the sky behind the range.
	water = box(terrain, Vector3(0, -0.09, 20), Vector3(3.0, 0.14, 80), _color("71aaa9", "83b4a8"))
	# The dry trail continues into the distance on both banks.
	_trail([Vector2(-47, -20), Vector2(-29, -14), Vector2(-22, -6), Vector2(-17, -1), Vector2(-11, 0), Vector2(-5, 0), Vector2(-1.7, 0)], 1.7)
	_trail([Vector2(1.7, 0), Vector2(6, 0), Vector2(10, 0), Vector2(14, 2), Vector2(20, 5), Vector2(32, 3), Vector2(45, -3)], 1.55)
	for i in range(44):
		var z := -19.0 + i * 1.8
		var stripe := box(terrain, Vector3(sin(i * 2.6) * 0.7, 0.002, z), Vector3(0.4 + fmod(i * 0.33, 0.5), 0.01, 0.04), _color("aecdc2", "b5d1b4"))
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1, 1]:
		for i in range(22):
			var z := -18.0 + i * 1.8
			var stone := ball(terrain, Vector3(side * (1.7 + 0.08 * sin(i)), 0.03, z), Vector3(0.36, 0.26, 1.5), _color("b6ba9d", "bea47e"))
			stone.rotation.y = side * 0.16

func _terrain_height(x: float, z: float) -> float:
	var beyond := maxf(maxf(absf(x) - 17.0, absf(z) - 11.0), 0.0)
	if beyond < 0.1 or absf(x) < 2.0:
		return 0.08
	var ripple := (sin(x * 0.12 + z * 0.06) + cos(z * 0.19 - x * 0.09)) * 0.6
	return 0.08 + minf(beyond * 0.19, 1.1) * ripple

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Godot treats clockwise triangles as front-facing. Match winding to the normal,
	# including the mirrored left bank, so two-sided shading cannot invert the light.
	var normal := (c - a).cross(b - a).normalized()
	if normal.y < 0:
		var previous_b := b
		b = c
		c = previous_b
		normal = -normal
	surface.set_color(color)
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.set_normal(normal)
	surface.add_vertex(b)
	surface.set_normal(normal)
	surface.add_vertex(c)

func _ground_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Clip only the distant ground, behind overlapping mountain bases. The foreground
	# still extends past the viewport; the skyline is real silhouette against the sky.
	var polygon: Array[Vector3] = [a, b, c]
	var clipped: Array[Vector3] = []
	var previous := polygon.back() as Vector3
	var previous_depth := -previous.x * 0.2063 - previous.z * 0.9785
	for point in polygon:
		var depth := -point.x * 0.2063 - point.z * 0.9785
		var inside := depth <= 28.0
		var previous_inside := previous_depth <= 28.0
		if inside != previous_inside:
			clipped.append(previous.lerp(point, (28.0 - previous_depth) / (depth - previous_depth)))
		if inside:
			clipped.append(point)
		previous = point
		previous_depth = depth
	for i in range(1, clipped.size() - 1):
		_triangle(surface, clipped[0], clipped[i], clipped[i + 1], color)

func _finish_surface(surface: SurfaceTool, label: String, shadow := false) -> MeshInstance3D:
	if vertex_material == null:
		vertex_material = StandardMaterial3D.new()
		vertex_material.vertex_color_use_as_albedo = true
		vertex_material.roughness = 1.0
		vertex_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = surface.commit()
	node.material_override = vertex_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(node)
	return node

func _trail(points: Array, width: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var from: Vector2 = points[i]
		var to: Vector2 = points[i + 1]
		var side := (to - from).normalized().orthogonal() * width * 0.5
		var a := Vector3(from.x + side.x, _terrain_height(from.x, from.y) + 0.026, from.y + side.y)
		var b := Vector3(from.x - side.x, a.y, from.y - side.y)
		var c := Vector3(to.x - side.x, _terrain_height(to.x, to.y) + 0.026, to.y - side.y)
		var d := Vector3(to.x + side.x, c.y, to.y + side.y)
		_ground_triangle(surface, a, b, c, _color("bdc39c", "e2c390"))
		_ground_triangle(surface, a, c, d, _color("bdc39c", "e2c390"))
	_finish_surface(surface, "WanderingTrail")

func _build_backdrop() -> void:
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	# Soft, distant silhouettes close every gap behind the nearer mountain/canyon range.
	for i in range(9):
		var p := away * (35.0 + sin(i * 1.3) * 1.4) + across * (-46.0 + i * 11.5)
		p.y = -8.0
		_peak(p, 13.0, 10.5 + fmod(i * 1.9, 3.0), i + 101, false, true, true)
	if landscape == "cactus":
		for i in range(7):
			var p := away * (25.0 + sin(i) * 2.0) + across * (-34.0 + i * 11.0)
			p.y = -2.0
			_mesa(p, 6.8 + fmod(i * 1.1, 3.0), 7.0 + fmod(i * 1.7, 3.0), true)
		for p in [Vector3(-22, 0, -8), Vector3(21, 0, -9), Vector3(23, 0, 8), Vector3(-28, 0, 6)]:
			_mesa(p, 3.4, 4.2 + fmod(absf(p.x), 2.0), false)
	else:
		# Different ridge widths, summit offsets and snowlines make a connected range.
		for i in range(7):
			var p := away * (26.0 + sin(i * 1.7) * 2.0) + across * (-34.0 + i * 11.0)
			p.y = -3.2
			_peak(p, 8.5 + fmod(i * 2.1, 4.0), 9.0 + fmod(i * 2.7, 5.0), i + 17, true, true)
		for i in range(6):
			var p := away * (18.5 + cos(i) * 1.5) + across * (-28.0 + i * 11.0)
			p.y = -0.7
			_peak(p, 7.0 + fmod(i * 1.7, 3.0), 4.2 + fmod(i * 1.9, 3.0), i + 53, false, false)
		for p in [Vector3(-23, 0, -3), Vector3(23, 0, -3), Vector3(-25, 0, 10)]:
			_peak(p, 6.5, 3.5, int(absf(p.x) + p.z), false, false)
		for i in range(19):
			var x := -27.0 + i * 3.3
			var z := -14.8 - 1.0 * sin(i * 2.3)
			if absf(x) > 2.6:
				_pine(Vector3(x, _terrain_height(x, z), z), 0.72 + fmod(i * 0.39, 0.45))

func _peak(pos: Vector3, radius: float, height: float, seed_value: int, snow: bool, distant: bool, hazy := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var count := 9
	var summit := Vector3(rng.randf_range(-1.8, 1.8), height, rng.randf_range(-1.2, 1.2))
	for level in range(3):
		var ring: Array[Vector3] = []
		var ring_radius := [1.0, 0.63, 0.25][level] as float
		var elevation := [0.0, 0.36, 0.72][level] as float
		for i in range(count):
			var angle := TAU * i / count + 0.1 * sin(seed_value)
			var stretch := rng.randf_range(0.82, 1.16)
			ring.append(pos + Vector3(cos(angle) * radius * ring_radius * stretch + summit.x * elevation, height * elevation + rng.randf_range(-0.55, 0.55), sin(angle) * radius * ring_radius * stretch * 0.62))
		rings.append(ring)
	var stone := Color("9baeb4") if distant else Color("819181")
	if hazy:
		stone = _color("afc3c7", "c8b59f")
	for level in range(2):
		for i in range(count):
			var j := (i + 1) % count
			var color := stone.lightened(rng.randf_range(-0.025, 0.025) if hazy else rng.randf_range(-0.10, 0.10))
			if level == 0 and not distant:
				color = Color("91a27e").lightened(rng.randf_range(-0.08, 0.05))
			_triangle(surface, rings[level][i], rings[level][j], rings[level + 1][i], color)
			_triangle(surface, rings[level][j], rings[level + 1][j], rings[level + 1][i], color.lightened(0.035))
	for i in range(count):
		var color := Color("edf1e7").lightened(rng.randf_range(-0.06, 0.01)) if snow else stone.lightened(rng.randf_range(-0.025, 0.025) if hazy else rng.randf_range(-0.1, 0.08))
		_triangle(surface, rings[2][i], rings[2][(i + 1) % count], pos + summit, color)
	var ridge := _finish_surface(surface, "DistantHorizon" if hazy else ("SnowRidge" if snow else "Foothill"))
	if hazy:
		if horizon_material == null:
			horizon_material = StandardMaterial3D.new()
			horizon_material.vertex_color_use_as_albedo = true
			horizon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			horizon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		ridge.material_override = horizon_material

func _mesa(pos: Vector3, radius: float, height: float, distant: bool) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 7
	var rings: Array = []
	for level in range(4):
		var ring: Array[Vector3] = []
		var fraction := [0.0, 0.23, 0.78, 1.0][level] as float
		var width := [1.0, 0.78, 0.69, 0.48][level] as float
		for i in range(count):
			var angle := TAU * i / count
			var jagged := 1.0 + sin(i * 3.7 + pos.x) * 0.15
			ring.append(pos + Vector3(cos(angle) * radius * width * jagged, height * fraction, sin(angle) * radius * width * 0.65 * jagged))
		rings.append(ring)
	var palette := [Color("c99774"), Color("b57f66"), Color("d8ab80")] if distant else [Color("b98259"), Color("a57050"), Color("c69264")]
	for level in range(3):
		for i in range(count):
			var j := (i + 1) % count
			_triangle(surface, rings[level][i], rings[level][j], rings[level + 1][i], palette[level])
			_triangle(surface, rings[level][j], rings[level + 1][j], rings[level + 1][i], palette[level])
	for i in range(count):
		_triangle(surface, rings[3][i], rings[3][(i + 1) % count], pos + Vector3(0, height, 0), Color("dfb78a"))
	_finish_surface(surface, "SandstoneMesa")

func _build_boundaries() -> void:
	# Broken boulders and dense low brush mark the actual walkable limits without a wall grid.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9401
	for side in [-1, 1]:
		for i in range(13):
			var z := -10.9 + i * 1.9
			var x: float = side * (17.7 + rng.randf_range(0, 1.4))
			_rock(Vector3(x, 0.2, z), Vector3(rng.randf_range(1.3, 2.8), rng.randf_range(0.7, 2.0), 1.5))
			if i % 2 == 0:
				_shrub(Vector3(side * 17.4, 0.08, z + 0.8), 0.75)
		for i in range(20):
			var x := -17.0 + i * 1.8
			if absf(x) < 2.0:
				continue
			var z: float = side * (11.5 + rng.randf_range(0.0, 0.65))
			_shrub(Vector3(x, 0.08, z), 0.74 if side > 0 else 1.0)
			if i % 3 == 0:
				_rock(Vector3(x + 0.7, 0.12, z + side * 0.5), Vector3(1.8, 0.75 if side > 0 else 1.6, 1.5))
	# A few far foreground details imply that this valley belongs to a larger place.
	for p in [Vector3(-26, 0, 17), Vector3(26, 0, 17), Vector3(-14, 0, 22), Vector3(13, 0, 21)]:
		if landscape == "cactus":
			_cactus(p, 1.3)
		else:
			_pine(p, 1.2)

func _rock(pos: Vector3, scale_value: Vector3) -> void:
	var rock := ball(terrain, pos, scale_value, _color("a1a692", "b88a63"))
	rock.rotation = Vector3(0.2, pos.x * 0.3, -0.14)

func _shrub(pos: Vector3, size: float) -> void:
	ball(terrain, pos + Vector3(0, size * 0.32, 0), Vector3(size * 1.85, size, size * 1.3), _color("72916e", "929b68"))
	if landscape == "cactus":
		_agave(pos + Vector3(0.6, 0, 0.25), size * 0.75)

func _build_bridge() -> void:
	for i in range(12):
		box(terrain, Vector3(-1.78 + i * 0.325, 0.13, 0), Vector3(0.305, 0.20, 3.9), _color("cda77a", "b68e67") if i % 3 else _color("bf966b", "a8805c"))
	for z in [-2.0, 2.0]:
		for x in [-1.9, 0.0, 1.9]:
			box(terrain, Vector3(x, 0.62, z), Vector3(0.14, 1.16, 0.14), Color("8d7656"))
		box(terrain, Vector3(0, 0.92, z), Vector3(4.0, 0.12, 0.12), Color("b09066"))

func _build_fence() -> void:
	for side in [-1, 1]:
		for i in range(6):
			var z: float = side * (2.0 + i * 1.7)
			box(terrain, Vector3(6, 0.62, z), Vector3(0.18, 1.18, 0.18), Color("9e8361"))
			if i < 5:
				for y in [0.4, 0.87]:
					box(terrain, Vector3(6, y, z + side * 0.85), Vector3(0.10, 0.13, 1.7), Color("c5a47a"))
	gate = Node3D.new()
	gate.position = Vector3(6, 0, -2)
	terrain.add_child(gate)
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
		var grass := cylinder(terrain, Vector3(x, 0.17, z), 0.0, 0.11, rng.randf_range(0.14, 0.3), _color("7c9966", "ad9e6d"), 4)
		grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % 3 == 0:
			ball(terrain, Vector3(x, 0.30, z), Vector3(0.12, 0.10, 0.12), Color("f5e4ae") if i % 2 else _color("d0aec3", "ce977e"))
	for p in [Vector3(-14, 0, -8), Vector3(-10, 0, -9.5), Vector3(-15.2, 0, 5.7), Vector3(13, 0, -8.8), Vector3(15.6, 0, -5.8), Vector3(13.8, 0, 8.3)]:
		if landscape == "cactus":
			_cactus(p, rng.randf_range(0.9, 1.25))
			_agave(p + Vector3(1.1, 0.1, 0.6), 0.8)
		else:
			_tree(p, rng.randf_range(0.85, 1.15))
	for p in [Vector3(-2.4, 0, 7), Vector3(2.3, 0, -5), Vector3(-2.6, 0, -7.4), Vector3(15, 0, 4)]:
		ball(terrain, p + Vector3(0, 0.17, 0), Vector3(0.85, 0.50, 0.7), _color("b3b29b", "b99a75"))
		ball(terrain, p + Vector3(0.45, 0.12, 0.22), Vector3(0.4, 0.30, 0.4), _color("bcbba4", "c6a681"))
	# A place to rest, with no menu or reward machine.
	box(terrain, Vector3(11.6, 0.12, 5.5), Vector3(2.8, 0.04, 1.8), _color("d6bda0", "bc8165"))
	for x in [10.8, 12.4]:
		box(terrain, Vector3(x, 0.145, 5.5), Vector3(0.12, 0.03, 1.8), Color("f1dcc0"))
	var basket := cylinder(terrain, Vector3(12.8, 0.38, 4.9), 0.27, 0.23, 0.55, Color("b68d57"))
	basket.rotation.z = 0.07
	# One small wooden trail sign, shaped in world space.
	box(terrain, Vector3(4.4, 0.7, -3.1), Vector3(0.12, 1.4, 0.12), Color("9e8361"))
	box(terrain, Vector3(4.4, 1.15, -3.1), Vector3(1.0, 0.37, 0.12), Color("c6a475"))
	if landscape == "alpine":
		# A distant chalet and hay shelter are quiet hints of life beyond this stop.
		_chalet(Vector3(24, 0.25, -15), 0.85)
		_chalet(Vector3(-26, 0.1, -13), 0.60)
	else:
		for p in [Vector3(-23, 0, -15), Vector3(21, 0, -14), Vector3(-20, 0, 8), Vector3(25, 0, 5), Vector3(9, 0, -17)]:
			_cactus(p, 1.25)
			_agave(p + Vector3(1.2, 0, 0.5), 1.0)

func _tree(pos: Vector3, tree_scale: float) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * tree_scale
	terrain.add_child(tree)
	cylinder(tree, Vector3(0, 1.0, 0), 0.13, 0.23, 2, Color("8e7e5f"))
	ball(tree, Vector3(0, 2.7, 0), Vector3(2.5, 3.2, 2.5), Color("718d62"))
	ball(tree, Vector3(-0.7, 2.3, 0.2), Vector3(1.8, 1.9, 1.8), Color("88a071"))
	ball(tree, Vector3(0.55, 3.2, -0.15), Vector3(1.9, 2.2, 1.9), Color("91a778"))

func _pine(pos: Vector3, tree_scale: float) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3.ONE * tree_scale
	terrain.add_child(tree)
	cylinder(tree, Vector3(0, 0.75, 0), 0.09, 0.16, 1.5, Color("8d8065"), 7)
	for i in range(3):
		cylinder(tree, Vector3(0, 1.6 + i * 0.74, 0), 0.03, 1.10 - i * 0.23, 2.0 - i * 0.26, Color("608271").lightened(i * 0.035), 7)

func _cactus(pos: Vector3, cactus_scale: float) -> void:
	var cactus := Node3D.new()
	cactus.position = pos
	cactus.scale = Vector3.ONE * cactus_scale
	cactus.rotation.y = pos.x * 0.31
	terrain.add_child(cactus)
	var green := Color("779771")
	cylinder(cactus, Vector3(0, 1.35, 0), 0.22, 0.27, 2.7, green, 9)
	ball(cactus, Vector3(0, 2.70, 0), Vector3(0.45, 0.46, 0.45), green)
	for side in [-1, 1]:
		var height := 1.15 if side < 0 else 1.65
		var branch := cylinder(cactus, Vector3(side * 0.40, height, 0), 0.15, 0.18, 0.8, green, 8)
		branch.rotation.z = PI / 2
		cylinder(cactus, Vector3(side * 0.75, height + 0.36, 0), 0.15, 0.17, 0.72, green, 8)
		ball(cactus, Vector3(side * 0.75, height + 0.72, 0), Vector3(0.31, 0.32, 0.31), green)
	# A single small bloom replaces collectible-looking visual noise.
	ball(cactus, Vector3(0.05, 2.96, 0), Vector3(0.19, 0.11, 0.18), Color("d99591"))

func _agave(pos: Vector3, size: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(7):
		var angle := i * TAU / 7
		var tip := pos + Vector3(cos(angle) * 0.7, 0.68, sin(angle) * 0.7) * size
		var side := Vector3(-sin(angle), 0, cos(angle)) * size * 0.13
		_triangle(surface, pos - side, pos + side, tip, Color("8a9e88").lightened((i % 3) * 0.045))
	_finish_surface(surface, "Agave")

func _chalet(pos: Vector3, cabin_scale: float) -> void:
	var cabin := Node3D.new()
	cabin.position = pos
	cabin.scale = Vector3.ONE * cabin_scale
	cabin.rotation.y = 0.24
	terrain.add_child(cabin)
	box(cabin, Vector3(0, 0.9, 0), Vector3(3.0, 1.8, 2.6), Color("c8b796"))
	box(cabin, Vector3(0, 0.55, 1.32), Vector3(0.55, 1.1, 0.06), Color("756c59"))
	for side in [-1, 1]:
		var roof := box(cabin, Vector3(side * 0.87, 2.05, 0), Vector3(2.15, 0.16, 3.1), Color("918c7a"))
		roof.rotation.z = side * -0.5
		box(cabin, Vector3(side * 0.9, 1.13, 1.33), Vector3(0.48, 0.54, 0.07), Color("57716b"))

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
	camera_focus = camera_focus.lerp(desired_focus, 1.0 - exp(-delta * 1.5))
	camera.position = camera_focus + CAMERA_OFFSET
	camera.look_at(camera_focus)
	marker_age += delta
	destination.visible = marker_age < 2.0
	destination.scale = Vector3.ONE * (1.0 + sin(marker_age * 5) * 0.1)
	gate.rotation.y = lerp_angle(gate.rotation.y, -1.45 if gate_open else 0.0, minf(delta * 4, 1.0))
