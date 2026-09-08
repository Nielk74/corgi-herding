class_name JuniperScenery
extends RefCounted
## Original continuous beach, water and wind-shaped junipers, without textures.

const Profile = preload("res://scripts/juniper_profile.gd")
const Navigation = preload("res://scripts/shore_navigation.gd")

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
	var water_material := host.vertex_material.duplicate() as StandardMaterial3D
	water_material.disable_receive_shadows = true
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
	# Unequal near trees sit off-route; distant small clusters supply scale.
	var trees := [Vector3(-18, 0, -2), Vector3(-17, 0, -6), Vector3(-14.5, 0, -9.0),
		Vector3(-9.5, 0, -10.4), Vector3(-6.8, 0, -11.8), Vector3(-4.2, 0, -12.6),
		Vector3(7.1, 0, -11.2), Vector3(11.3, 0, -9.3), Vector3(15.7, 0, -6.4),
		Vector3(18.2, 0, -3.6), Vector3(18.0, 0, 1.2)]
	for p in trees:
		if Navigation.signed_clearance(Vector2(p.x, p.z)) < -1.2:
			_juniper(host, crowns, p, rng.randf_range(0.7, 1.15), rng)
	var across := Vector3(0.9785, 0, -0.2063)
	var away := Vector3(-0.2063, 0, -0.9785)
	for p: Vector2 in [Vector2(-22, 15), Vector2(-19.5, 16.2), Vector2(-21.4, 18.2), Vector2(-15.2, 18.5),
		Vector2(-4.8, 21.6), Vector2(-2.6, 22.1), Vector2(0.1, 20.5), Vector2(16.8, 20.6), Vector2(19.5, 22.0)]:
		_juniper(host, crowns, across * p.x + away * p.y, rng.randf_range(0.35, 0.53), rng)
	host._finish_surface(crowns, "JuniperWoodland", true)
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

static func _juniper(host, surface: SurfaceTool, p: Vector3, scale_value: float, rng: RandomNumberGenerator) -> void:
	var base: Vector3 = host._grounded(p)
	var lean := Vector3(rng.randf_range(0.18, 0.5), 0, rng.randf_range(-0.16, 0.12)) * scale_value
	var trunk = host.cylinder(host.terrain, base + Vector3(0, 0.65, 0) * scale_value, 0.075 * scale_value, 0.13 * scale_value, 1.3 * scale_value, Color("786a53"), 7)
	trunk.rotation.z = -0.16
	for i in range(4):
		var angle := i * 2.4 + rng.randf_range(-0.25, 0.25)
		var center := base + lean + Vector3(cos(angle) * 0.5, 1.0 + i * 0.18, sin(angle) * 0.35) * scale_value
		var size := Vector3(rng.randf_range(0.68, 0.96), rng.randf_range(0.50, 0.75), rng.randf_range(0.65, 0.9)) * scale_value
		_crown(host, surface, center, size, Color("516e57").lightened(i * 0.025), angle)

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
