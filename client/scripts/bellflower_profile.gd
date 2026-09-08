class_name BellflowerTerrainProfile
extends RefCounted
## One continuous Alpine common, branching toward unequal-height resting places.
## Heights are presentation only; the exact v6 walking union remains authoritative.

const Navigation = preload("res://scripts/commons_navigation.gd")
const GRID_STEP := 0.75
# Across-view position, receding depth, crest height. A slanting broken crest
# gives both portrait follow extremes a shared landmark and an open lower col.
const FAR_CREST := [
	Vector3(-26, 32, -20), Vector3(-15, 33, -11),
	Vector3(-5, 35, -3), Vector3(0, 39, -2.5),
	Vector3(4.5, 37, -8), Vector3(8, 41, -7),
	Vector3(17, 38, -13), Vector3(28, 42, -20)]
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
	# A broad low bank avoids a narrow double crest and its hairline self-shadow.
	ground += 1.35 * hill(x, z, 9.0, 0.0, 6.0, 1.5) * smoothstep(0.0, 1.5, outside)
	var folds := sin(x * 0.66 + z * 0.32 + sin(z * 0.22) * 0.7)
	ground += folds * smoothstep(0.7, 3.5, outside) * 0.43 * hill(x, z, 0, -4, 27, 16)
	var u := x * 0.9785 - z * 0.2063
	var depth := -x * 0.2063 - z * 0.9785
	# Diagonal buttresses open onto a long central valley. Their toe line and
	# depth differ, so the near grass connects to rock rather than a peak row.
	var country := -5.8 + 6.9 * hill(u, depth, -5, 23, 9, 8)
	country += 4.6 * hill(u, depth, 12, 27, 8, 8)
	country -= 1.7 * hill(u, depth, 3, 26, 3.6, 7)
	country += 0.45 * sin(u * 0.43 + depth * 0.48) * hill(u, depth, -5, 23, 13, 10)
	country -= 0.35 * pow(absf(sin(u * 0.38 - depth * 0.42)), 4.0) * hill(u, depth, 12, 26, 14, 9)
	# The common's farthest point is depth 8.608, including its full disks.
	# Start beyond even its interpolation cells, lowering only scenic ground.
	ground = lerpf(ground, country, smoothstep(11.0, 18.0, depth))
	# Orthographic depth also raises the skyline on screen. A genuinely low
	# valley floor is needed between massifs, not a pale high connecting curtain.
	var ridge := far_crest(u)
	var flank := exp(-pow((depth - ridge.x) / 6.0, 2.0))
	var mountain := -21.0 + (ridge.y + 21.0) * flank
	# Fold channels run diagonally down the flanks. They affect the actual mesh
	# and normals, not a noise texture pasted over a smooth mountain silhouette.
	mountain -= pow(absf(sin(u * 0.72 - depth * 0.38)), 6.0) * flank * 0.9
	mountain -= pow(absf(sin(u * 0.41 + depth * 0.23)), 6.0) * flank * 0.45
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

static func far_crest(u: float) -> Vector2:
	for i in range(FAR_CREST.size() - 1):
		var a: Vector3 = FAR_CREST[i]
		var b: Vector3 = FAR_CREST[i + 1]
		if u <= b.x:
			var t := clampf((u - a.x) / (b.x - a.x), 0.0, 1.0)
			return Vector2(lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))
	var last: Vector3 = FAR_CREST[-1]
	return Vector2(last.y, last.z)

static func hill(x: float, z: float, cx: float, cz: float, sx: float, sz: float) -> float:
	return exp(-pow((x - cx) / sx, 2.0) - pow((z - cz) / sz, 2.0))
