class_name MeadowDiorama
extends Node3D
## All meshes are original procedural geometry; no downloaded art dependencies.

const GRASS := Color("96ad78")
const DARK := Color("293f36")
const CREAM := Color("fff0d5")
const TerrainProfile = preload("res://scripts/terrain_profile.gd")
const SceneryBatch = preload("res://scripts/static_scenery_batch.gd")
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
var camera_focus := Vector3(-4.0, 1.8, -6.0)
var desired_focus := Vector3(-4.0, 1.8, -6.0)
const CAMERA_OFFSET := Vector3(8, 28, 38)
const TERRAIN_HORIZON_DEPTH := 22.0
var profile: ValleyTerrainProfile

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
	profile = TerrainProfile.new(landscape)
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
	# Scenery is immutable after construction; the animated gate stays separate.
	SceneryBatch.merge(terrain, [gate])
	if is_instance_valid(preview):
		for actor in preview.get_children():
			actor.position.y = surface_height(actor.position.x, actor.position.z) + 0.03

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
	var rig = load("res://scripts/valley_lighting.gd").new()
	add_child(rig)
	world_environment = rig.environment

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
	# One continuous sampled heightfield: hills are places the herders walk over.
	for side in [-1, 1]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ix in range(44):
			for iz in range(85):
				var x0: float = side * (1.5 + ix)
				var x1: float = side * (2.5 + ix)
				var z0 := -40.0 + iz
				var z1 := z0 + 1.0
				var a := Vector3(x0, profile.node_height(x0, z0), z0)
				var b := Vector3(x1, profile.node_height(x1, z0), z0)
				var c := Vector3(x1, profile.node_height(x1, z1), z1)
				var d := Vector3(x0, profile.node_height(x0, z1), z1)
				_ground_triangle(surface, a, b, c, Color.WHITE, true)
				_ground_triangle(surface, a, c, d, Color.WHITE, true)
		_finish_surface(surface, "ValleyGround%d" % (0 if side < 0 else 1), true)
	_build_river()
	_trail([Vector2(-31, -13), Vector2(-24, -7), Vector2(-18, -2), Vector2(-13, -1), Vector2(-8, 0.7), Vector2(-4, 0.3), Vector2(-1.7, 0)], 1.1)
	_trail([Vector2(1.7, 0), Vector2(6, 0), Vector2(10, 0.8), Vector2(14, 2), Vector2(19, 4), Vector2(27, 3), Vector2(35, -2)], 1.05)

func _build_river() -> void:
	var channel := SurfaceTool.new()
	channel.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(65):
		var z0 := -20.0 + iz
		var z1 := z0 + 1.0
		var w0 := profile.river_width(z0)
		var w1 := profile.river_width(z1)
		_triangle(channel, Vector3(-w0, 0, z0), Vector3(w0, 0, z0), Vector3(w1, 0, z1), Color.WHITE)
		_triangle(channel, Vector3(-w0, 0, z0), Vector3(w1, 0, z1), Vector3(-w1, 0, z1), Color.WHITE)
	water = mesh(terrain, channel.commit(), Vector3(0, TerrainProfile.WATER_LEVEL, 0), _color("477f88", "638f88"))
	water.name = "RiverSurface"
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1, 1]:
		var bank := SurfaceTool.new()
		bank.begin(Mesh.PRIMITIVE_TRIANGLES)
		for iz in range(32):
			var z0 := -20.0 + iz
			var z1 := z0 + 1.0
			var x0: float = side * profile.river_width(z0)
			var x1: float = side * profile.river_width(z1)
			var a := Vector3(x0, profile.sample(x0, z0), z0)
			var b := Vector3(x1, profile.sample(x1, z1), z1)
			var c := Vector3(x1 - side * 0.13, -0.82, z1)
			var d := Vector3(x0 - side * 0.13, -0.82, z0)
			_triangle(bank, a, b, c, _color("7e8875", "a18162"))
			_triangle(bank, a, c, d, _color("858d78", "ad8a67"))
		_finish_surface(bank, "CutRiverbank")
	for i in range(29):
		var z := -18.0 + i * 2.05
		var x := sin(i * 2.6) * profile.river_width(z) * 0.60
		var stripe := box(terrain, Vector3(x, TerrainProfile.WATER_LEVEL + 0.018, z), Vector3(0.35 + fmod(i * 0.33, 0.5), 0.008, 0.025), _color("8fb5b1", "a8bca4"))
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _terrain_height(x: float, z: float) -> float:
	return profile.sample(x, z)

func surface_height(x: float, z: float) -> float:
	return profile.surface_height(x, z)

func surface_normal(x: float, z: float) -> Vector3:
	if profile.bridge_at(x, z) or absf(x) < profile.river_width(z):
		return Vector3.UP
	var step := 0.06
	var dx := (surface_height(x + step, z) - surface_height(x - step, z)) / (step * 2.0)
	var dz := (surface_height(x, z + step) - surface_height(x, z - step)) / (step * 2.0)
	return Vector3(-dx, 1, -dz).normalized()

func place_marker(marker: Node3D, pos: Vector3) -> void:
	var normal := surface_normal(pos.x, pos.z)
	var right := Vector3.RIGHT.slide(normal).normalized()
	marker.basis = Basis(right, normal, right.cross(normal).normalized())
	marker.position = Vector3(pos.x, surface_height(pos.x, pos.z) + 0.13, pos.z)

func _grounded(pos: Vector3) -> Vector3:
	return Vector3(pos.x, surface_height(pos.x, pos.z) + pos.y, pos.z)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Godot treats clockwise triangles as front-facing. Match winding to the normal,
	# including the mirrored left bank, so two-sided shading cannot invert the light.
	var normal := (c - a).cross(b - a).normalized()
	if normal.y < 0:
		var previous_b := b
		b = c
		c = previous_b
		normal = -normal
	# Compatibility converts the final albedo from sRGB inside scene.glsl.
	# Converting here as well crushes the greens and turns rock shadows black.
	surface.set_color(color)
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.set_normal(normal)
	surface.add_vertex(b)
	surface.set_normal(normal)
	surface.add_vertex(c)

func _ground_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, smooth_terrain := false) -> void:
	# Clip only the distant ground, behind overlapping mountain bases. The foreground
	# still extends past the viewport; the skyline is real silhouette against the sky.
	var polygon: Array[Vector3] = [a, b, c]
	var clipped: Array[Vector3] = []
	var previous := polygon.back() as Vector3
	var previous_depth := -previous.x * 0.2063 - previous.z * 0.9785
	for point in polygon:
		var depth := -point.x * 0.2063 - point.z * 0.9785
		var inside := depth <= TERRAIN_HORIZON_DEPTH
		var previous_inside := previous_depth <= TERRAIN_HORIZON_DEPTH
		if inside != previous_inside:
			clipped.append(previous.lerp(point, (TERRAIN_HORIZON_DEPTH - previous_depth) / (depth - previous_depth)))
		if inside:
			clipped.append(point)
		previous = point
		previous_depth = depth
	for i in range(1, clipped.size() - 1):
		if smooth_terrain:
			_terrain_triangle(surface, clipped[0], clipped[i], clipped[i + 1])
		else:
			_triangle(surface, clipped[0], clipped[i], clipped[i + 1], color)

func _terrain_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (c - a).cross(b - a).y < 0:
		var previous_b := b
		b = c
		c = previous_b
	for point in [a, b, c]:
		var normal := profile.normal_at(point.x, point.z)
		var color := _color("88a46a", "c4a06f")
		var flank := smoothstep(0.12, 0.45, 1.0 - normal.y)
		color = color.lerp(_color("798273", "a67b58"), flank * 0.78)
		var high_meadow := smoothstep(1.0, 5.0, point.y)
		color = color.lerp(_color("71905c", "b58e62"), high_meadow * 0.30)
		color = color.lightened(sin(point.x * 0.12 + point.z * 0.08) * 0.014)
		surface.set_color(color)
		surface.set_normal(normal)
		surface.add_vertex(point)

func _finish_surface(surface: SurfaceTool, label: String, shadow := false) -> MeshInstance3D:
	if vertex_material == null:
		vertex_material = StandardMaterial3D.new()
		vertex_material.vertex_color_use_as_albedo = true
		vertex_material.vertex_color_is_srgb = true
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
		var start: Vector2 = points[i]
		var finish: Vector2 = points[i + 1]
		var count := maxi(1, int(ceil(start.distance_to(finish) / 0.45)))
		var side := (finish - start).normalized().orthogonal() * width * 0.5
		for segment in range(count):
			var from := start.lerp(finish, float(segment) / count)
			var to := start.lerp(finish, float(segment + 1) / count)
			var a := _grounded(Vector3(from.x + side.x, 0.035, from.y + side.y))
			var b := _grounded(Vector3(from.x - side.x, 0.035, from.y - side.y))
			var c := _grounded(Vector3(to.x - side.x, 0.035, to.y - side.y))
			var d := _grounded(Vector3(to.x + side.x, 0.035, to.y + side.y))
			_ground_triangle(surface, a, b, c, _color("b1b593", "d5b384"))
			_ground_triangle(surface, a, c, d, _color("b1b593", "d5b384"))
	_finish_surface(surface, "WanderingTrail")

func _build_backdrop() -> void:
	# Connected, asymmetric ridges and gullies follow the reference valleys. A large
	# crag on one flank faces a lower saddle; there is no row of separate cones.
	_ridge_strip(29.5, 36.5, -1.9, 7.3, 0.9, false, true)
	_ridge_strip(15.5, 25.5, 3.0, 7.0 if landscape == "alpine" else 5.0, 0.0, landscape == "alpine", false)
	if landscape == "alpine":
		for i in range(27):
			var z := -15.0 + sin(i * 1.7) * 2.1
			var x := -25.0 + i * 2.1
			if absf(x) > 3.5:
				_pine(Vector3(x, 0, z), 0.66 + fmod(i * 0.33, 0.42), i % 4 == 0)
		for i in range(15):
			var p := Vector3(-21.5 + sin(i * 1.7) * 1.9, 0, -12.0 + i * 1.9)
			_pine(p, 0.9 + fmod(i * 0.23, 0.35), i % 3 == 0)

func _ridge_strip(front_depth: float, crest_depth: float, base_height: float, amplitude: float, phase: float, snow: bool, hazy: bool) -> void:
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	var sections: Array = []
	var count := 131
	var bands: Array[float] = [0.0, 0.16, 0.32, 0.48, 0.62, 0.74, 0.84, 0.91, 1.0]
	for i in range(count):
		var u := -52.0 + i * 0.8
		var structure := 0.48 + 0.66 * exp(-pow((u + 12.0) / 9.0, 2)) + 0.98 * exp(-pow((u - 10.0) / 5.0, 2)) + 0.62 * exp(-pow((u - 29.0) / 10.0, 2))
		var jagged := 0.22 * pow(maxf(sin(u * 0.93 + phase), 0.0), 4) + 0.11 * sin(u * 2.03 - phase)
		if landscape == "cactus":
			structure = 0.56 + 0.65 * smoothstep(-0.2, 0.6, sin(u * 0.17 + phase))
			jagged *= 0.35
		var crest_height := base_height + amplitude * (structure + jagged)
		var front := across * u + away * (front_depth + sin(u * 0.23) * 1.8)
		front.y = base_height - 1.4 if hazy else profile.sample(front.x, front.z)
		var crest := across * (u + sin(u * 0.7) * 0.20) + away * (crest_depth + sin(u * 0.31 + phase) * 2.9)
		crest.y = maxf(crest_height, front.y + (0.6 if hazy else 1.4))
		var row: Array[Vector3] = []
		for band in bands:
			var point := front.lerp(crest, band)
			var middle := sin(band * PI)
			var gully := pow(absf(sin(u * 0.61 + phase)), 10)
			point.y -= gully * middle * (2.1 if not hazy else 0.65)
			point.y += sin(u * 1.16 + band * 5.1) * middle * 0.45
			point += across * sin(u * 0.91 + band * 4.0) * middle * 0.24
			point += away * sin(u * 0.71 + band * 4.6) * middle * 1.05
			row.append(point)
		var back := crest + away * 8.0
		back.y = base_height - 2.5
		row.append(back)
		sections.append(row)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(count - 1):
		for band in range(bands.size()):
			var color := _color("6e7a79", "a57755")
			if band <= 1:
				color = _color("738d62", "b48b62")
			elif band <= 4:
				color = _color("727d79", "986e51")
			else:
				color = _color("8d9897", "bc946c")
			var u := -52.0 + (i + 0.5) * 0.8
			var gully := pow(absf(sin(u * 0.61 + phase)), 10)
			color = color.darkened(gully * 0.15)
			var height: float = (sections[i][band].y + sections[i + 1][mini(band + 1, bands.size() - 1)].y) * 0.5
			var fraction := bands[band]
			var snowline := 9.4 + sin(u * 0.49) * 1.0
			var snow_patch := sin(u * 0.68 + fraction * 3.4) + 0.42 * cos(u * 1.37 - fraction * 4.1)
			if snow and band < bands.size() - 1 and height > snowline and fraction > lerpf(0.88, 0.67, gully) and snow_patch > 0.05:
				color = Color("e3e9e2").darkened(gully * 0.08)
			if hazy:
				color = _color("9eb5bd", "c1ac97").lightened(sin(i * 0.4) * 0.025)
			_triangle(surface, sections[i][band], sections[i + 1][band], sections[i + 1][band + 1], color)
			_triangle(surface, sections[i][band], sections[i + 1][band + 1], sections[i][band + 1], color.lightened(0.018))
	_finish_surface(surface, "DistantRidgeline" if hazy else ("AlpineCrags" if snow else "ErodedCanyon"))

func _build_boundaries() -> void:
	# Scattered outcrops follow the rising slopes. No rectangular necklace of shrubs.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9401
	for p in [Vector3(-18, 0, -8), Vector3(-20, 0, -3), Vector3(-18.5, 0, 8), Vector3(18.7, 0, -7), Vector3(21, 0, 3), Vector3(18, 0, 9.5), Vector3(-12, 0, 12.7), Vector3(13, 0, 13.5)]:
		_rock(p + Vector3(0, 0.25, 0), Vector3(rng.randf_range(1.4, 2.8), rng.randf_range(0.8, 1.7), rng.randf_range(1.3, 2.4)))
		_shrub(p + Vector3(rng.randf_range(-1.0, 1.0), 0.05, 0.75), rng.randf_range(0.6, 0.9))
	for p in [Vector3(-25, 0, 17), Vector3(25, 0, 17), Vector3(-15, 0, 20), Vector3(14, 0, 22)]:
		if landscape == "cactus":
			_cactus(p, 1.3)
		else:
			_pine(p, 1.2, p.x < 0)

func _rock(pos: Vector3, scale_value: Vector3) -> void:
	var rock := ball(terrain, _grounded(pos), scale_value, _color("8b9383", "b18a63"))
	rock.rotation = Vector3(0.2, pos.x * 0.3, -0.14)

func _shrub(pos: Vector3, size: float) -> void:
	ball(terrain, _grounded(pos) + Vector3(0, size * 0.32, 0), Vector3(size * 1.85, size, size * 1.3), _color("66825c", "929b68"))
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
			box(terrain, _grounded(Vector3(6, 0.62, z)), Vector3(0.18, 1.18, 0.18), Color("9e8361"))
			if i < 5:
				for y in [0.4, 0.87]:
					var from := _grounded(Vector3(6, y, z))
					var to := _grounded(Vector3(6, y, z + side * 1.7))
					var beam := box(terrain, (from + to) * 0.5, Vector3(0.10, 0.13, from.distance_to(to)), Color("c5a47a"))
					beam.look_at(to, Vector3.UP)
	gate = Node3D.new()
	gate.position = _grounded(Vector3(6, 0, -2))
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
		var grass := cylinder(terrain, _grounded(Vector3(x, 0.12, z)), 0.0, 0.11, rng.randf_range(0.14, 0.3), _color("708957", "ad9e6d"), 4)
		grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i % 3 == 0:
			ball(terrain, _grounded(Vector3(x, 0.25, z)), Vector3(0.12, 0.10, 0.12), Color("f5e4ae") if i % 2 else _color("d0aec3", "ce977e"))
	for p in [Vector3(-14, 0, -8), Vector3(-10, 0, -9.5), Vector3(-15.2, 0, 5.7), Vector3(13, 0, -8.8), Vector3(15.6, 0, -5.8), Vector3(13.8, 0, 8.3)]:
		if landscape == "cactus":
			_cactus(p, rng.randf_range(0.9, 1.25))
			_agave(p + Vector3(1.1, 0.1, 0.6), 0.8)
		else:
			_tree(p, rng.randf_range(0.85, 1.15))
	for p in [Vector3(-2.4, 0, 7), Vector3(2.3, 0, -5), Vector3(-2.6, 0, -7.4), Vector3(15, 0, 4)]:
		ball(terrain, _grounded(p + Vector3(0, 0.12, 0)), Vector3(0.85, 0.50, 0.7), _color("a4a58f", "b99a75"))
		ball(terrain, _grounded(p + Vector3(0.45, 0.09, 0.22)), Vector3(0.4, 0.30, 0.4), _color("b0b09a", "c6a681"))
	# A place to rest, with no menu or reward machine.
	_draped_patch(Vector2(11.6, 5.5), Vector2(2.8, 1.8), _color("d6bda0", "bc8165"), 0.035)
	for x in [10.8, 12.4]:
		_draped_patch(Vector2(x, 5.5), Vector2(0.12, 1.8), Color("f1dcc0"), 0.050)
	var basket := cylinder(terrain, _grounded(Vector3(12.8, 0.28, 4.9)), 0.27, 0.23, 0.55, Color("b68d57"))
	basket.rotation.z = 0.07
	# One small wooden trail sign, shaped in world space.
	box(terrain, _grounded(Vector3(4.4, 0.7, -3.1)), Vector3(0.12, 1.4, 0.12), Color("9e8361"))
	box(terrain, _grounded(Vector3(4.4, 1.15, -3.1)), Vector3(1.0, 0.37, 0.12), Color("c6a475"))
	if landscape == "alpine":
		# A distant chalet and hay shelter are quiet hints of life beyond this stop.
		_chalet(Vector3(24, 0, -15), 0.85)
		_chalet(Vector3(-26, 0, -13), 0.60)
	else:
		for p in [Vector3(-23, 0, -15), Vector3(21, 0, -14), Vector3(-20, 0, 8), Vector3(25, 0, 5), Vector3(9, 0, -17)]:
			_cactus(p, 1.25)
			_agave(p + Vector3(1.2, 0, 0.5), 1.0)

func _tree(pos: Vector3, tree_scale: float) -> void:
	var tree := Node3D.new()
	tree.position = _grounded(pos)
	tree.scale = Vector3.ONE * tree_scale
	terrain.add_child(tree)
	cylinder(tree, Vector3(0, 1.0, 0), 0.13, 0.23, 2, Color("8e7e5f"))
	ball(tree, Vector3(0, 2.7, 0), Vector3(2.5, 3.2, 2.5), Color("718d62"))
	ball(tree, Vector3(-0.7, 2.3, 0.2), Vector3(1.8, 1.9, 1.8), Color("88a071"))
	ball(tree, Vector3(0.55, 3.2, -0.15), Vector3(1.9, 2.2, 1.9), Color("91a778"))

func _pine(pos: Vector3, tree_scale: float, autumn := false) -> void:
	var tree := Node3D.new()
	tree.position = _grounded(pos)
	tree.scale = Vector3.ONE * tree_scale
	terrain.add_child(tree)
	cylinder(tree, Vector3(0, 0.75, 0), 0.09, 0.16, 1.5, Color("8d8065"), 7)
	for i in range(3):
		var needles := Color("b5a14d") if autumn else Color("476b59")
		if autumn and pos.x > 0:
			needles = Color("ac7845")
		cylinder(tree, Vector3(0, 1.6 + i * 0.74, 0), 0.03, 1.10 - i * 0.23, 2.0 - i * 0.26, needles.lightened(i * 0.035), 7)

func _cactus(pos: Vector3, cactus_scale: float) -> void:
	var cactus := Node3D.new()
	cactus.position = _grounded(pos)
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
	pos = _grounded(pos)
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
	cabin.position = _grounded(pos)
	cabin.scale = Vector3.ONE * cabin_scale
	cabin.rotation.y = 0.24
	terrain.add_child(cabin)
	box(cabin, Vector3(0, 0.9, 0), Vector3(3.0, 1.8, 2.6), Color("c8b796"))
	box(cabin, Vector3(0, 0.55, 1.32), Vector3(0.55, 1.1, 0.06), Color("756c59"))
	for side in [-1, 1]:
		var roof := box(cabin, Vector3(side * 0.87, 2.05, 0), Vector3(2.15, 0.16, 3.1), Color("918c7a"))
		roof.rotation.z = side * -0.5
		box(cabin, Vector3(side * 0.9, 1.13, 1.33), Vector3(0.48, 0.54, 0.07), Color("57716b"))

func _draped_patch(center: Vector2, size: Vector2, color: Color, lift: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count_x := maxi(1, int(ceil(size.x / 0.35)))
	var count_z := maxi(1, int(ceil(size.y / 0.35)))
	for ix in range(count_x):
		for iz in range(count_z):
			var x0 := center.x - size.x * 0.5 + size.x * ix / count_x
			var x1 := center.x - size.x * 0.5 + size.x * (ix + 1) / count_x
			var z0 := center.y - size.y * 0.5 + size.y * iz / count_z
			var z1 := center.y - size.y * 0.5 + size.y * (iz + 1) / count_z
			var a := _grounded(Vector3(x0, lift, z0))
			var b := _grounded(Vector3(x1, lift, z0))
			var c := _grounded(Vector3(x1, lift, z1))
			var d := _grounded(Vector3(x0, lift, z1))
			_triangle(surface, a, b, c, color)
			_triangle(surface, a, c, d, color)
	_finish_surface(surface, "PicnicCloth")

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
		sheep.position = _grounded(Vector3(-6.5 + sin(i * 2.3) * 2.9, 0.03, -1.6 + cos(i * 1.6) * 2.7))
		sheep.rotation.y = i * 0.9
	for i in range(2):
		var dog := make_actor("dog", "mochi" if i == 0 else "maple")
		dog.reparent(preview)
		dog.position = _grounded(Vector3(-10 + i * 3, 0.03, 3.3))
		dog.rotation.y = -0.5 + i

func mark_destination(pos: Vector3) -> void:
	place_marker(destination, pos)
	destination.visible = true
	marker_age = 0.0

func ground_at(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.001:
		return Vector3.INF
	var previous_t := 0.0
	var previous_gap := origin.y - surface_height(origin.x, origin.z)
	for step in range(1, 601):
		var t := step * 0.25
		var point := origin + direction * t
		var gap := point.y - surface_height(point.x, point.z)
		if gap <= 0.0 and previous_gap > 0.0:
			var low := previous_t
			var high := t
			for iteration in range(15):
				var middle := (low + high) * 0.5
				var sample_point := origin + direction * middle
				if sample_point.y > surface_height(sample_point.x, sample_point.z):
					low = middle
				else:
					high = middle
			var result := origin + direction * ((low + high) * 0.5)
			if absf(result.x) > 17 or absf(result.z) > 11:
				return Vector3.INF
			result.y = surface_height(result.x, result.z)
			return result
		previous_t = t
		previous_gap = gap
	return Vector3.INF

func _process(delta: float) -> void:
	elapsed += delta
	camera_focus = camera_focus.lerp(desired_focus, 1.0 - exp(-delta * 1.5))
	camera.position = camera_focus + CAMERA_OFFSET
	camera.look_at(camera_focus)
	marker_age += delta
	destination.visible = marker_age < 2.0
	destination.scale = Vector3.ONE * (1.0 + sin(marker_age * 5) * 0.1)
	gate.rotation.y = lerp_angle(gate.rotation.y, -1.45 if gate_open else 0.0, minf(delta * 4, 1.0))
