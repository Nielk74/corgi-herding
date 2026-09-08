class_name JuniperScenery
extends RefCounted
## Original continuous beach, water and wind-shaped junipers, without textures.

const Profile = preload("res://scripts/juniper_profile.gd")
const Navigation = preload("res://scripts/shore_navigation.gd")
const WaterShader = preload("res://shaders/juniper_water.gdshader")

static func build_land(host) -> void:
	var near := SurfaceTool.new()
	near.begin(Mesh.PRIMITIVE_TRIANGLES)
	var far := SurfaceTool.new()
	far.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lake := SurfaceTool.new()
	lake.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := Profile.GRID_STEP
	# Same origins/diagonals as TerrainProfile.sample; water is clipped against
	# these actual triangles, never placed as an oval over a walking shortcut.
	for ix in range(-72, 72):
		for iz in range(-72, 64):
			var x := ix * step
			var z := iz * step
			var a := Vector3(x, host.profile.node_height(x, z), z)
			var b := Vector3((ix + 1) * step, host.profile.node_height((ix + 1) * step, z), z)
			var c := Vector3((ix + 1) * step, host.profile.node_height((ix + 1) * step, (iz + 1) * step), (iz + 1) * step)
			var d := Vector3(x, host.profile.node_height(x, (iz + 1) * step), (iz + 1) * step)
			var depth := -(x + step * 0.5) * 0.2063 - (z + step * 0.5) * 0.9785
			var target := far if depth > 14.0 else near
			host._ground_triangle(target, a, b, c, Color.WHITE, true)
			host._ground_triangle(target, a, c, d, Color.WHITE, true)
			if depth < 13.0:
				_clip_water(lake, [a, b, c])
				_clip_water(lake, [a, c, d])
	var ground: MeshInstance3D = host._finish_surface(near, "ValleyGroundJuniper", true)
	var combined := ground.mesh as ArrayMesh
	far.commit(combined)
	ground.material_override = null
	combined.surface_set_material(0, host.vertex_material)
	var far_material := host.vertex_material.duplicate() as StandardMaterial3D
	far_material.disable_receive_shadows = true
	combined.surface_set_material(1, far_material)
	host.water = host._finish_surface(lake, "JuniperLake")
	var water_material := ShaderMaterial.new()
	water_material.shader = WaterShader
	host.water.material_override = water_material

static func ground_color(host, point: Vector3, normal: Vector3) -> Color:
	var depth := -point.x * 0.2063 - point.z * 0.9785
	var u := point.x * 0.9785 - point.z * 0.2063
	var geometry: Vector2 = host.profile.juniper.geometry(point.x, point.z)
	var inland := smoothstep(0.15, 1.9, geometry.x)
	var landward := 1.0 - smoothstep(-0.5, 1.7, geometry.y)
	var grass := Color("88a267").lerp(Color("71885d"), landward * 0.25)
	var sand := Color("c4b994").lerp(Color("a6ae94"), smoothstep(-0.15, 0.55, point.y) * 0.25)
	var color := sand.lerp(grass, maxf(inland, landward * 0.85))
	var stone := smoothstep(0.12, 0.42, 1.0 - normal.y)
	color = color.lerp(Color("7e8575"), stone * 0.83)
	color = color.lightened(sin(point.x * 0.29 + sin(point.z * 0.31)) * 0.025)
	var distant := smoothstep(13.0, 26.0, depth)
	color = color.lerp(Color("819587").lerp(Color("99aaa0"), smoothstep(16.0, 29.0, depth)), distant * 0.75)
	var front := 25.0 + sin(u * 0.15) * 2.2 + u * 0.07
	var mountain_mix := smoothstep(front, front + 5.7, depth)
	var mountain := Color("758b99").lerp(Color("aac0c8"), smoothstep(31.0, 43.0, depth))
	var snow := smoothstep(3.6 + sin(u * 0.82) * 0.45, 6.0, point.y)
	mountain = mountain.lerp(Color("e2ece7"), snow * 0.92)
	return color.lerp(mountain, mountain_mix)

static func _clip_water(surface: SurfaceTool, polygon: Array) -> void:
	var clipped: Array[Vector3] = []
	var previous: Vector3 = polygon[-1]
	for point: Vector3 in polygon:
		var inside := point.y < Profile.WATER_LEVEL
		var previous_inside := previous.y < Profile.WATER_LEVEL
		if inside != previous_inside:
			clipped.append(previous.lerp(point, (Profile.WATER_LEVEL - previous.y) / (point.y - previous.y)))
		if inside:
			clipped.append(point)
		previous = point
	for i in range(1, clipped.size() - 1):
		var a := clipped[0]
		var b := clipped[i]
		var c := clipped[i + 1]
		if (c - a).cross(b - a).y < 0:
			var swap := b
			b = c
			c = swap
		for p in [a, b, c]:
			var depth := maxf(Profile.WATER_LEVEL - p.y, 0.0)
			var color := Color("9ab7aa").lerp(Color("527e8b"), smoothstep(0.0, 1.5, depth))
			# Quiet light bands belong to the water vertices, not floating decals.
			var ripple := sin(p.z * 1.15 + sin(p.x * 0.14) * 0.8)
			color = color.lightened(ripple * 0.012 + sin(p.x * 0.12) * 0.018)
			surface.set_color(color)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(p.x, Profile.WATER_LEVEL, p.z))

static func build_details(host) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 579321
	var crowns := SurfaceTool.new()
	crowns.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Broad gaps and depth offsets matter more than the number of trees. Each
	# conservative crown disk is wholly outside the true walking union, not an
	# approximate oval shoreline. Rejection sampling avoids a planted tree row.
	var plantings: Array[Dictionary] = []
	_plant_group(host, crowns, plantings, Vector2(-18.0, -7.3), Vector2(4.3, 4.0), 5, Vector2(0.62, 1.02), 0, rng)
	_plant_group(host, crowns, plantings, Vector2(-3.5, -14.4), Vector2(4.4, 2.7), 3, Vector2(0.66, 0.92), 1, rng)
	_plant_group(host, crowns, plantings, Vector2(19.0, -4.7), Vector2(3.5, 4.5), 4, Vector2(0.68, 1.08), 2, rng)
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	var distant_centers := [Vector2(-22, 18), Vector2(-0.5, 23), Vector2(20, 20)]
	for i in distant_centers.size():
		var p: Vector2 = distant_centers[i]
		var center := across * p.x + away * p.y
		_plant_group(host, crowns, plantings, Vector2(center.x, center.z), Vector2(3.3, 2.4), [3, 2, 4][i], Vector2(0.32, 0.55), i + 3, rng)
	var woodland: MeshInstance3D = host._finish_surface(crowns, "JuniperWoodland", true)
	woodland.set_meta("plantings", plantings)
	for p in [Vector3(-16, 0, -4), Vector3(-11, 0, -10), Vector3(5.5, 0, -11.5), Vector3(15.8, 0, -5), Vector3(17.4, 0, 8.6)]:
		if Navigation.signed_clearance(Vector2(p.x, p.z)) < -0.8:
			host._rock(p + Vector3(0, 0.16, 0), Vector3(1.1, 0.5, 0.85))
	var tufts := SurfaceTool.new()
	tufts.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(110):
		var p := Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-10.5, 8.7))
		if not Navigation.contains(p) or Navigation.signed_clearance(p) < 1.05:
			continue
		var base: Vector3 = host._grounded(Vector3(p.x, 0.025, p.y))
		var size := rng.randf_range(0.06, 0.12)
		host._triangle(tufts, base + Vector3(-size, 0, 0), base + Vector3(size, 0, 0), base + Vector3(0, size * 1.7, 0.025), Color("718453"))
		if i % 4 == 0:
			host._triangle(tufts, base + Vector3(-0.05, 0.13, 0), base + Vector3(0.05, 0.13, 0), base + Vector3(0, 0.19, 0), Color("d5c896"))
	host._finish_surface(tufts, "JuniperMeadowFlowers")

static func _plant_group(host, surface: SurfaceTool, plantings: Array[Dictionary], center: Vector2,
		spread: Vector2, count: int, scales: Vector2, group: int, rng: RandomNumberGenerator) -> void:
	var placed := 0
	for attempt in range(count * 80):
		if placed == count:
			break
		var angle := rng.randf() * TAU
		var offset := Vector2(cos(angle), sin(angle)) * sqrt(rng.randf()) * spread
		var point := center + offset
		var scale_value := rng.randf_range(scales.x, scales.y)
		var radius := 2.25 * scale_value
		if Navigation.signed_clearance(point) >= -radius - 0.35:
			continue
		var separated := true
		for previous in plantings:
			if point.distance_to(previous.position) < (radius + float(previous.radius)) * 0.8:
				separated = false
				break
		if not separated:
			continue
		var form: String = ["spreading", "crooked", "windward"][(group + placed) % 3]
		_juniper(host, surface, Vector3(point.x, 0, point.y), scale_value, form, rng)
		plantings.append({"position": point, "radius": radius, "form": form, "group": group})
		placed += 1

static func _juniper(host, surface: SurfaceTool, p: Vector3, scale_value: float, form: String, rng: RandomNumberGenerator) -> void:
	var base: Vector3 = host._grounded(p)
	var phase := rng.randf_range(-0.65, 0.65)
	var green := Color("4c6655").lerp(Color("687c5b"), rng.randf_range(0.0, 0.7))
	for i in range(3):
		var side := float(i - 1)
		var offset: Vector3
		var size: Vector3
		var fork: Vector3
		if form == "spreading":
			offset = Vector3(side * 0.57, 0.43 + i * 0.09, sin(i * 2.2 + phase) * 0.22)
			size = Vector3(rng.randf_range(0.97, 1.26), rng.randf_range(0.31, 0.46), 0.73)
			fork = Vector3(0.03, 0.13, 0)
		elif form == "crooked":
			offset = Vector3(side * 0.54 + 0.24, 1.35 + i * 0.21, side * 0.22)
			size = Vector3(rng.randf_range(0.64, 0.84), rng.randf_range(0.55, 0.78), 0.73)
			fork = Vector3(0.2, 0.72, -0.06)
		else:
			offset = Vector3(0.12 + i * 0.37, 0.73 + i * 0.17, sin(i * 2.4 + phase) * 0.18)
			size = Vector3(0.85 + i * 0.10, rng.randf_range(0.36, 0.54), 0.68)
			fork = Vector3(-0.08, 0.28, 0)
		var center := base + offset * scale_value
		_branch(host, base + fork * scale_value, center, scale_value * (0.047 if form == "spreading" else 0.064))
		if i == 0:
			_branch(host, base, base + fork * scale_value, scale_value * 0.09)
		_crown(host, surface, center, size * scale_value, green.lightened(i * 0.018), phase + i * 2.3)

static func _branch(host, from: Vector3, to: Vector3, radius: float) -> void:
	var direction := to - from
	var branch = host.cylinder(host.terrain, (from + to) * 0.5, radius * 0.65, radius,
		direction.length(), Color("786a53"), 6)
	branch.quaternion = Quaternion(Vector3.UP, direction.normalized())

static func _crown(host, surface: SurfaceTool, center: Vector3, size: Vector3, color: Color, phase: float) -> void:
	var lower: Array[Vector3] = []
	var upper: Array[Vector3] = []
	for i in range(8):
		var angle := i * TAU / 8.0 + phase
		var radius := 0.88 + sin(i * 2.36 + phase) * 0.12
		lower.append(center + Vector3(cos(angle), -0.18, sin(angle)) * size * radius)
		upper.append(center + Vector3(cos(angle) * 0.66, 0.62 + sin(i * 1.8) * 0.1, sin(angle) * 0.7) * size)
	var top := center + Vector3(-size.x * 0.12, size.y, size.z * 0.08)
	var bottom := center - Vector3.UP * size.y * 0.55
	for i in range(8):
		var next := (i + 1) % 8
		host._triangle(surface, lower[i], lower[next], upper[next], color.darkened(0.025))
		host._triangle(surface, lower[i], upper[next], upper[i], color)
		host._triangle(surface, upper[i], upper[next], top, color.lightened(0.035))
		host._triangle(surface, lower[next], lower[i], bottom, color.darkened(0.10))
