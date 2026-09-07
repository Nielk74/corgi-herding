class_name ValleyTerrainProfile
extends RefCounted
## One height source for the visible mesh, feet, props, trails and touch picking.
## World gameplay still uses the server's X/Z plane; heights are presentation only.

const GRID_STEP := 1.0
const WATER_LEVEL := -0.34
const BRIDGE_HEIGHT := 0.23
const PLAY_BOUNDS := Rect2(-17, -11, 34, 22)
var landscape := "alpine"
var samples: Dictionary = {}

func _init(kind := "alpine") -> void:
	landscape = kind

func river_width(z: float) -> float:
	# Beyond the playable meadow the stream opens into a small lake / desert wash.
	return 1.5 + smoothstep(12.0, 28.0, z) * (5.3 if landscape == "alpine" else 2.8)

func bridge_at(x: float, z: float) -> bool:
	return absf(x) <= 1.93 and absf(z) <= 1.95

func surface_height(x: float, z: float) -> float:
	if bridge_at(x, z):
		return BRIDGE_HEIGHT
	if absf(x) < river_width(z):
		return WATER_LEVEL
	return sample(x, z)

func sample(x: float, z: float) -> float:
	if absf(x) < 1.5:
		return raw_height(x, z)
	var sign_x := -1.0 if x < 0 else 1.0
	var index_x := floorf((absf(x) - 1.5) / GRID_STEP)
	var x0 := 1.5 + index_x * GRID_STEP
	var z0 := floorf(z / GRID_STEP) * GRID_STEP
	var fx := (absf(x) - x0) / GRID_STEP
	var fz := (z - z0) / GRID_STEP
	var a := node_height(sign_x * x0, z0)
	var b := node_height(sign_x * (x0 + GRID_STEP), z0)
	var c := node_height(sign_x * (x0 + GRID_STEP), z0 + GRID_STEP)
	var d := node_height(sign_x * x0, z0 + GRID_STEP)
	# Match exactly the a-b-c / a-c-d diagonal used by the rendered heightfield.
	if fx >= fz:
		return a + (b - a) * fx + (c - b) * fz
	return a + (c - d) * fx + (d - a) * fz

func node_height(x: float, z: float) -> float:
	var key := Vector2(x, z)
	if not samples.has(key):
		samples[key] = raw_height(x, z)
	return float(samples[key])

func normal_at(x: float, z: float) -> Vector3:
	var step := 0.35
	var width := river_width(z)
	if absf(x) < width:
		return Vector3.UP
	# Ground stops at the cut bank: its normal must not sample the submerged bed.
	var low_x := maxf(x - step, width) if x > 0 else x - step
	var high_x := x + step if x > 0 else minf(x + step, -width)
	var dx := (raw_height(high_x, z) - raw_height(low_x, z)) / maxf(high_x - low_x, 0.01)
	var dz := (raw_height(x, z + step) - raw_height(x, z - step)) / (step * 2.0)
	return Vector3(-dx, 1.0, -dz).normalized()

func raw_height(x: float, z: float) -> float:
	var width := river_width(z)
	var bank_distance := absf(x) - width
	if bank_distance < 0:
		return -0.86 + 0.035 * sin(z * 0.55)
	var bank := 0.16 + 0.16 * (1.0 - exp(-z * z / 45.0))
	var rise := smoothstep(0.0, 4.5, bank_distance)
	var rolling: float
	if landscape == "alpine":
		rolling = 0.40
		rolling += 1.85 * _hill(x, z, -10, -4, 7, 5)
		rolling += 1.95 * _hill(x, z, -16, 7, 7, 6)
		rolling += 2.50 * _hill(x, z, 12, 5, 7, 6)
		rolling += 2.95 * _hill(x, z, 15, -9, 7, 5)
		rolling += 0.28 * pow(sin(x * 0.19 + z * 0.16), 2)
	else:
		rolling = 0.35
		rolling += 2.15 * _hill(x, z, -12, -5, 7, 6)
		rolling += 1.30 * _hill(x, z, -14, 8, 6, 5)
		rolling += 2.65 * _hill(x, z, 13, 7, 8, 5)
		rolling += 1.75 * _hill(x, z, 13, -9, 7, 6)
		rolling += 0.30 * pow(sin(x * 0.23 - z * 0.17), 2)
	var height := bank + rise * rolling
	# Continuous, asymmetric valley flanks start gently inside the playable area
	# and become steep shoulders beyond it. They replace a rectangular shrub rim.
	var flank := maxf(absf(x) - 15.0, 0.0)
	var side_strength := 0.34 if x < 0 else 0.24
	height += rise * minf(pow(flank, 1.22) * side_strength, 13.0)
	var back := maxf(-z - 10.0, 0.0)
	height += rise * minf(back * 0.46, 6.5) * (0.65 + 0.35 * pow(sin(x * 0.14), 2))
	var front := maxf(z - 11.0, 0.0)
	height += rise * minf(front * 0.08, 1.4)
	if landscape == "cactus" and flank > 1:
		# Erosion terraces emerge in the canyon flanks, while the walking floor stays smooth.
		height += minf(flank * 0.08, 0.6) * smoothstep(-0.5, 0.5, sin(height * 3.4 + z * 0.20))
	var gate_flat := (1.0 - smoothstep(0.85, 2.6, absf(x - 6.0))) * (1.0 - smoothstep(2.1, 3.9, absf(z)))
	height = lerpf(height, 0.30, gate_flat)
	var bridge_flat := (1.0 - smoothstep(1.93, 3.4, absf(x))) * (1.0 - smoothstep(1.95, 3.1, absf(z)))
	height = lerpf(height, BRIDGE_HEIGHT, bridge_flat)
	return height

func _hill(x: float, z: float, cx: float, cz: float, sx: float, sz: float) -> float:
	return exp(-pow((x - cx) / sx, 2) - pow((z - cz) / sz, 2))
