class_name BellflowerTerrainProfile
extends RefCounted
## One continuous Alpine common, branching toward unequal-height resting places.
## Heights are presentation only; the exact v6 walking union remains authoritative.

const Navigation = preload("res://scripts/commons_navigation.gd")
const GRID_STEP := 0.75
var commons: Dictionary
var clearances: Dictionary = {}
var normals: Dictionary = {}

func _init(incoming: Dictionary = {}) -> void:
	commons = Navigation.default_commons() if incoming.is_empty() else incoming.duplicate(true)

func clearance(x: float, z: float) -> float:
	var key := Vector2(x, z)
	if not clearances.has(key):
		clearances[key] = Navigation.signed_clearance(key, commons)
	return float(clearances[key])

func height(x: float, z: float) -> float:
	var outside := maxf(-clearance(x, z), 0.0)
	# Broad oblique contours, not three raised circular pads. The central hollow
	# is shallow; the northern shoulder rises while the southern arm stays low.
	var ground := 1.28 + x * 0.065 - z * 0.075
	ground -= 0.46 * hill(x, z, -4.5, 0.5, 6.2, 4.4)
	ground += 0.65 * hill(x, z, 9.0, -6.5, 6.1, 4.2)
	ground -= 0.32 * hill(x, z, 9.5, 6.0, 5.4, 4.6)
	ground += 0.25 * sin(x * 0.32 + z * 0.15) * cos(z * 0.24)
	ground += 0.16 * sin(x * 0.57 - z * 0.24) * hill(x, z, -4.0, -1.0, 13.0, 9.0)
	# The rear flank rises; the foreground falls away. This cannot become a
	# uniform retaining wall around the common. A low exposed spur separates
	# the actual branches, rather than drawing a misleading path across the gap.
	var rear := smoothstep(-1.0, 8.0, -z)
	var edge := smoothstep(0.0, 0.8, outside)
	ground += lerpf(-minf(outside * 0.92, 5.1), minf(outside * 0.94, 4.3), rear) * edge
	ground += 2.1 * hill(x, z, 9.0, 0.0, 6.0, 1.5) * edge
	var folds := sin(x * 0.66 + z * 0.32 + sin(z * 0.22) * 0.7)
	ground += folds * smoothstep(0.7, 3.5, outside) * 0.43 * hill(x, z, 0, -4, 27, 16)
	var u := x * 0.9785 - z * 0.2063
	var depth := -x * 0.2063 - z * 0.9785
	# Diagonal buttresses open onto a long central valley. Their toe line and
	# depth differ, so the near grass connects to rock rather than a peak row.
	var country := -1.8 + 5.4 * hill(u, depth, -19, 18, 10, 9)
	country += 3.8 * hill(u, depth, 22, 21, 12, 9)
	country += 0.7 * sin(u * 0.43 + depth * 0.48) * hill(u, depth, -15, 19, 13, 10)
	country -= 0.6 * pow(absf(sin(u * 0.38 - depth * 0.42)), 4.0) * hill(u, depth, 12, 23, 22, 9)
	ground = lerpf(ground, country, smoothstep(14.7, 21.5, depth))
	var mountain := -8.0
	var left_spine := -14.0 + (depth - 34.0) * 0.35
	var left := hill(u, depth, left_spine, 34.0, 7.3, 5.8)
	var right := hill(u, depth, 18.0, 40.0, 7.0, 5.7)
	mountain += 16.5 * left * (1.0 + sin(u * 0.71 + depth * 0.36) * 0.09)
	mountain += 14.5 * right * (1.0 + sin(u * 0.94 - depth * 0.18) * 0.07)
	mountain += 10.8 * hill(u, depth, 1.0, 43.0, 7.0, 5.0)
	# Fold channels run diagonally down the flanks. They affect the actual mesh
	# and normals, not a noise texture pasted over a smooth mountain silhouette.
	mountain -= pow(absf(sin(u * 0.72 - depth * 0.38)), 6.0) * left * 1.35
	mountain -= pow(absf(sin(u * 0.61 + depth * 0.31)), 6.0) * right * 0.95
	var toe := 24.0 + sin(u * 0.13) * 2.0 + u * 0.06
	ground = lerpf(ground, mountain, smoothstep(toe, toe + 6.0, depth))
	ground = lerpf(ground, -28.0, smoothstep(44.0, 52.0, depth))
	# Continue the foreground well beyond the playable ground and portrait rays.
	var near_country := -3.4 + 0.7 * sin(u * 0.14) + 0.35 * sin(z * 0.22 + u * 0.21)
	return lerpf(ground, near_country, smoothstep(20.0, 38.0, z))

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
