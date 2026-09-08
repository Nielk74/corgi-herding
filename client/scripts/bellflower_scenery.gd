class_name BellflowerScenery
extends RefCounted
## Sparse low flowers and off-path groves leave the common itself open.

const Profile = preload("res://scripts/bellflower_profile.gd")
const Navigation = preload("res://scripts/commons_navigation.gd")
const Foliage = preload("res://scripts/juniper_scenery.gd")

static func build_land(host) -> void:
	var near := SurfaceTool.new()
	near.begin(Mesh.PRIMITIVE_TRIANGLES)
	var far := SurfaceTool.new()
	far.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := Profile.GRID_STEP
	for ix in range(-72, 72):
		for iz in range(-72, 64):
			var x := ix * step
			var z := iz * step
			var a := Vector3(x, host.profile.node_height(x, z), z)
			var b := Vector3(x + step, host.profile.node_height(x + step, z), z)
			var c := Vector3(x + step, host.profile.node_height(x + step, z + step), z + step)
			var d := Vector3(x, host.profile.node_height(x, z + step), z + step)
			var depth := -(x + step * 0.5) * 0.2063 - (z + step * 0.5) * 0.9785
			var surface := far if depth > 14.0 else near
			host._ground_triangle(surface, a, b, c, Color.WHITE, true)
			host._ground_triangle(surface, a, c, d, Color.WHITE, true)
	var ground: MeshInstance3D = host._finish_surface(near, "ValleyGroundBellflower", true)
	var combined := ground.mesh as ArrayMesh
	far.commit(combined)
	ground.material_override = null
	combined.surface_set_material(0, host.vertex_material)
	var far_material := host.vertex_material.duplicate() as StandardMaterial3D
	far_material.disable_receive_shadows = true
	combined.surface_set_material(1, far_material)

static func ground_color(host, point: Vector3, normal: Vector3) -> Color:
	var u := point.x * 0.9785 - point.z * 0.2063
	var depth := -point.x * 0.2063 - point.z * 0.9785
	var outside := maxf(-host.profile.bellflower.clearance(point.x, point.z), 0.0)
	var sunny := smoothstep(-0.5, 7.0, -point.z) * smoothstep(-4.0, 8.0, point.x)
	var grass := Color("78964f").lerp(Color("9dad62"), sunny * 0.60)
	var hollow := Profile.hill(point.x, point.z, 9.5, 6.0, 6.0, 5.0)
	grass = grass.lerp(Color("6c8d60"), hollow * 0.5)
	var fold := sin(point.x * 0.30 + point.z * 0.17 + sin(point.z * 0.28) * 0.6)
	var color := grass.lightened(fold * 0.035)
	var stone := smoothstep(0.14, 0.44, 1.0 - normal.y) * smoothstep(0.15, 1.3, outside)
	color = color.lerp(Color("858878"), stone * 0.92)
	var spur := Profile.hill(point.x, point.z, 9.0, 0.0, 6.0, 1.5) * smoothstep(0.2, 0.8, outside)
	color = color.lerp(Color("93917e"), spur * 0.70)
	var distant := smoothstep(11.0, 20.0, depth)
	var country := Color("728c77").lerp(Color("91a699"), smoothstep(18.0, 29.0, depth))
	country = country.lightened(sin(u * 0.29 + depth * 0.36) * 0.025)
	country = country.lerp(Color("738996"), smoothstep(0.12, 0.5, 1.0 - normal.y) * 0.70)
	color = color.lerp(country, distant * 0.88)
	var toe := 24.0 + sin(u * 0.13) * 2.0 + u * 0.06
	var mountain := Color("788c91").lerp(Color("adbec4"), smoothstep(30.0, 43.0, depth))
	var snow := smoothstep(-4.8 + sin(u * 0.73) * 0.35, -2.9, point.y)
	mountain = mountain.lerp(Color("e0e8e1"), snow * 0.93)
	return color.lerp(mountain, smoothstep(toe, toe + 6.0, depth))

static func build_details(host) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 681407
	var flowers := SurfaceTool.new()
	flowers.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(220):
		var point := Vector2(rng.randf_range(-12.5, 14.5), rng.randf_range(-10.5, 10.5))
		if not Navigation.contains(point) or Navigation.signed_clearance(point) < 0.85:
			continue
		# Loose patches with broad empty grass between them, never a dotted trail.
		var patch := sin(point.x * 0.47 + point.y * 0.23) + cos(point.y * 0.52 - point.x * 0.17)
		if patch < 0.35:
			continue
		var base: Vector3 = host._grounded(Vector3(point.x, 0.02, point.y))
		var size := rng.randf_range(0.045, 0.085)
		host._triangle(flowers, base + Vector3(-size, 0, 0), base + Vector3(size, 0, 0), base + Vector3(0, 0.16, 0.025), Color("67814b"))
		if i % 3 == 0:
			var petal := Color("b5b4cc") if i % 2 == 0 else Color("d8cc8e")
			host._triangle(flowers, base + Vector3(-0.055, 0.16, 0), base + Vector3(0.055, 0.16, 0), base + Vector3(0, 0.23, 0.025), petal)
	host._finish_surface(flowers, "BellflowerPatches")
	# Outcrops drape over the slope. Conservative radius rejection keeps their
	# whole footprint off the exact walkable union, including the small divider.
	for p in [Vector2(-14.5, -3.8), Vector2(-10.5, -8.8), Vector2(3.5, -10.0), Vector2(8.5, 0.0), Vector2(14.0, 0.0), Vector2(16.8, 7.8)]:
		var radius := 0.65 if p.y == 0.0 else 1.10
		if Navigation.signed_clearance(p) < -radius - 0.20:
			host._cloud_outcrop(Vector3(p.x, 0, p.y), Vector2(radius, radius * 0.63), 0.27)
	# Three unequal off-path groups with asymmetric branching crowns. Reuse the
	# existing original crown primitive, not a row of identical spherical trees.
	var foliage := SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tree_index := 0
	for group in [
		[Vector2(-16.7, -2.0), Vector2(-18.2, -5.3), Vector2(-15.2, -7.0)],
		[Vector2(17.8, 6.0), Vector2(19.8, 10.2)],
		[Vector2(-8.0, -16.0), Vector2(-6.6, -18.8), Vector2(5.1, -19.0)]]:
		for point: Vector2 in group:
			var scale_value := rng.randf_range(0.54, 0.84)
			if Navigation.signed_clearance(point) < -2.0 * scale_value - 0.35:
				_rowan(host, foliage, point, scale_value, tree_index)
				tree_index += 1
	host._finish_surface(foliage, "BellflowerRowanCrowns", true)

static func _rowan(host, foliage: SurfaceTool, point: Vector2, scale_value: float, variant: int) -> void:
	var base: Vector3 = host._grounded(Vector3(point.x, 0, point.y))
	var phase := point.x * 0.17 + point.y * 0.23
	var green := Color("637e4f").lerp(Color("8c9e60"), (variant % 3) * 0.21)
	var centers := [Vector3(-0.65, 1.15, -0.15), Vector3(0.18, 2.1, 0.13), Vector3(0.82, 1.65, 0.23)]
	if variant % 2 == 0:
		centers = [Vector3(-0.92, 0.90, 0.0), Vector3(-0.10, 1.52, -0.16), Vector3(0.72, 1.18, 0.25)]
	for i in centers.size():
		var offset: Vector3 = centers[i]
		var center := base + offset.rotated(Vector3.UP, phase) * scale_value
		var fork := base + Vector3(0.08, 0.68, -0.02) * scale_value
		Foliage._branch(host, fork, center, 0.055 * scale_value)
		if i == 0:
			Foliage._branch(host, base, fork, 0.095 * scale_value)
		var size := Vector3(0.89 + i * 0.05, 0.58 + (i % 2) * 0.2, 0.78) * scale_value
		Foliage._crown(host, foliage, center, size, green.lightened(i * 0.025), phase + i * 1.8)
