class_name JuniperTerrainProfile
extends RefCounted
## A continuous lakeshore, keyed to the exact server capsule/clearing union.

const Navigation = preload("res://scripts/shore_navigation.gd")
const GRID_STEP := 0.75
const WATER_LEVEL := 0.0
var shore: Dictionary
var corridor: Dictionary
var geometry_cache: Dictionary = {}
var normals: Dictionary = {}

func _init(incoming: Dictionary = {}) -> void:
	shore = Navigation.default_shore() if incoming.is_empty() else incoming.duplicate(true)
	corridor = Navigation.corridor(shore)

func geometry(x: float, z: float) -> Vector2:
	var key := Vector2(x, z)
	if geometry_cache.has(key):
		return geometry_cache[key]
	var clearance: float = Navigation.Union._clearance(x, z, corridor)[0]
	var distance := INF
	var side := 0.0
	for i in shore.path.size() - 1:
		var a: Dictionary = shore.path[i]
		var b: Dictionary = shore.path[i + 1]
		var point: Array = Navigation.Union._nearest(x, z, a.x, a.y, b.x, b.y)
		var dx: float = x - point[0]
		var dz: float = z - point[1]
		var d := dx * dx + dz * dz
		if d < distance:
			distance = d
			var tx: float = b.x - a.x
			var tz: float = b.y - a.y
			side = (tx * dz - tz * dx) / sqrt(tx * tx + tz * tz)
	var result := Vector2(clearance, side)
	geometry_cache[key] = result
	return result

func height(x: float, z: float) -> float:
	var shape := geometry(x, z)
	var clearance := float(shape.x)
	var landward := 1.0 - smoothstep(-0.5, 1.7, shape.y)
	var outside := maxf(-clearance, 0.0)
	# The beach remains dry at the exact union boundary. Shallow water begins
	# just beyond it, accounting for the finite triangle grid without a hidden
	# water-covered shortcut through any authoritative walking point.
	var height := 0.22 + minf(clearance, 0.0) * 0.55
	height = maxf(height, -1.65 - 0.08 * sin(x * 0.13 + z * 0.16))
	var inland := smoothstep(0.0, 2.6, maxf(clearance, 0.0))
	var rolling := 0.60 + 0.82 * hill(x, z, -12, 0, 6.2, 4.3)
	rolling += 1.15 * hill(x, z, -1, -7, 5.2, 3.9)
	rolling += 0.86 * hill(x, z, 12, 3, 5.3, 4.6)
	rolling += 0.15 * pow(sin(x * 0.24 - z * 0.17), 2.0)
	height += inland * rolling + landward * 0.44
	# The outer, non-lake edge is a steep grass/stone shoulder, not a second
	# beach or a fence. Gentle playable slopes never inherit these cliffs.
	height += landward * minf(outside * 1.25 + outside * outside * 0.075, 5.8) * smoothstep(0.0, 0.8, outside)
	var u := x * 0.9785 - z * 0.2063
	var depth := -x * 0.2063 - z * 0.9785
	# Foothills overlap at unequal depths, leaving a low open saddle between
	# a near rounded left shoulder and the farther blue country on the right.
	var country := 0.7 + 5.0 * hill(u, depth, -20, 17, 10, 7)
	country += 2.6 * hill(u, depth, 7, 23, 11, 7)
	country += 3.6 * hill(u, depth, 24, 20, 8, 6)
	country += 0.35 * sin(u * 0.26 + depth * 0.3) * hill(u, depth, -3, 21, 32, 9)
	height = lerpf(height, country, smoothstep(13.8, 20.5, depth))
	# Small, asymmetric jagged massifs, separated in depth as well as sideways.
	# They emerge from continuous foothills and recede down behind the skyline.
	var mountain := -9.0
	mountain += 14.0 * hill(u, depth, -12, 33, 7.3, 5.5) * (1.0 + 0.10 * sin(u * 1.36 + depth * 0.19))
	mountain += 12.5 * hill(u, depth, 6, 38, 6.3, 6.0) * (1.0 + 0.09 * sin(u * 1.93))
	mountain += 10.4 * hill(u, depth, 22, 34, 7.5, 5.8)
	mountain -= pow(absf(sin(u * 0.63 + depth * 0.47)), 8.0) * 0.65
	var front := 25.0 + sin(u * 0.15) * 2.2 + u * 0.07
	height = lerpf(height, mountain, smoothstep(front, front + 5.7, depth))
	height = lerpf(height, -28.0, smoothstep(42.0, 52.0, depth))
	# Avoid a near-plane cut at tall-phone corners: the shore extensions taper
	# far beyond the walking bounds. The middle foreground is genuine open bay.
	height = lerpf(height, -1.35 + landward * 1.6, smoothstep(24.0, 39.0, z))
	return height

func normal(x: float, z: float) -> Vector3:
	var key := Vector2(x, z)
	if not normals.has(key):
		var step := 0.3
		var dx := (height(x + step, z) - height(x - step, z)) / (step * 2.0)
		var dz := (height(x, z + step) - height(x, z - step)) / (step * 2.0)
		normals[key] = Vector3(-dx, 1.0, -dz).normalized()
	return normals[key]

static func hill(x: float, z: float, cx: float, cz: float, sx: float, sz: float) -> float:
	return exp(-pow((x - cx) / sx, 2.0) - pow((z - cz) / sz, 2.0))
