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
var bridge_y := 0.0
var gate_y := 0.0

func _init(kind := "alpine", layout: Dictionary = {}) -> void:
	landscape = kind
	bridge_y = float(layout.get("bridge_y", 3.0 if kind == "orchard" else (-4.0 if kind == "larch" else 0.0)))
	gate_y = float(layout.get("gate_y", 2.0 if kind == "orchard" else (4.0 if kind == "larch" else 0.0)))

func river_width(z: float) -> float:
	# Beyond the playable meadow the stream opens into a small lake / desert wash.
	if landscape == "orchard":
		return 1.5 + smoothstep(12.0, 33.0, z) * 1.7
	return 1.5 + smoothstep(12.0, 28.0, z) * (2.8 if landscape == "cactus" else (3.9 if landscape == "larch" else 5.3))

func river_center(z: float) -> float:
	if landscape != "orchard":
		return 0.0
	if z < -12.0:
		return smoothstep(12.0, 23.0, -z) * (1.0 + 2.5 * sin((-z - 12.0) * 0.14))
	if z > 12.0:
		return smoothstep(12.0, 27.0, z) * 2.1 * sin((z - 12.0) * 0.14)
	return 0.0

func bridge_at(x: float, z: float) -> bool:
	return absf(x) <= 1.93 and absf(z - bridge_y) <= 1.95

func surface_height(x: float, z: float) -> float:
	if bridge_at(x, z):
		return BRIDGE_HEIGHT
	if absf(x - river_center(z)) < river_width(z):
		return WATER_LEVEL
	return sample(x, z)

func sample(x: float, z: float) -> float:
	if landscape == "orchard" and absf(z) > 12.0:
		return raw_height(x, z) # The non-playable shoreline uses a finer visual mesh.
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
	var center := river_center(z)
	var bank_distance := absf(x - center) - width
	if bank_distance < (-0.00001 if landscape == "orchard" else 0.0):
		return Vector3.UP
	# Ground stops at the cut bank: its normal must not sample the submerged bed.
	var low_x := maxf(x - step, center + width) if x > center else x - step
	var high_x := x + step if x > center else minf(x + step, center - width)
	var dx := (raw_height(high_x, z) - raw_height(low_x, z)) / maxf(high_x - low_x, 0.01)
	var dz := (raw_height(x, z + step) - raw_height(x, z - step)) / (step * 2.0)
	if landscape == "orchard":
		# At a curved bank, fixed-X samples can fall into the submerged bed and
		# produce wildly alternating normals. Follow the bank at constant distance,
		# then convert that tangent gradient back to world X/Z with the chain rule.
		var side := -1.0 if x < center else 1.0
		var distance := maxf(0.0, bank_distance)
		var before_x := river_center(z - step) + side * (river_width(z - step) + distance)
		var after_x := river_center(z + step) + side * (river_width(z + step) + distance)
		var tangent_gradient := (raw_height(after_x, z + step) - raw_height(before_x, z - step)) / (step * 2.0)
		dz = tangent_gradient - dx * (after_x - before_x) / (step * 2.0)
	return Vector3(-dx, 1.0, -dz).normalized()

func raw_height(x: float, z: float) -> float:
	var width := river_width(z)
	var bank_distance := absf(x - river_center(z)) - width
	if bank_distance < (-0.00001 if landscape == "orchard" else 0.0):
		return -0.86 + 0.035 * sin(z * 0.55)
	bank_distance = maxf(0.0, bank_distance)
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
	elif landscape == "larch":
		# A sheltered clearing, with a diagonal rising forest shoulder on the left
		# and a broad, quieter shelf past the offset gate on the right.
		rolling = 0.30
		rolling += 2.65 * _hill(x, z, -15, -5, 6, 7)
		rolling += 1.65 * _hill(x, z, -11, 8, 8, 6)
		rolling += 1.60 * _hill(x, z, 13, 6, 8, 6)
		rolling += 0.90 * _hill(x, z, 15, -8, 8, 6)
		rolling += 0.22 * pow(sin(x * 0.14 - z * 0.21), 2)
	elif landscape == "orchard":
		# Two shallow curving terrace risers, with generous gently sloping shelves.
		# The windfall clearing sits between them rather than at the bottom of a pit.
		var contour := -z + 0.025 * pow(x + 8.0, 2)
		var shoulder := 1.0 - smoothstep(-2.0, 15.0, x)
		rolling = 0.24 + 0.84 * smoothstep(-1.5, 2.0, contour)
		rolling += 0.95 * smoothstep(6.0, 9.3, contour) * (0.45 + shoulder * 0.55)
		rolling += 0.80 * _hill(x, z, -13, 4, 8, 8)
		rolling += 0.68 * _hill(x, z, 14, 5, 7, 6)
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
	if landscape == "larch":
		side_strength = 0.52 if x < 0 else 0.14
	elif landscape == "orchard":
		side_strength = 0.18 if x < 0 else 0.09
	height += rise * minf(pow(flank, 1.22) * side_strength, 13.0)
	var back := maxf(-z - 10.0, 0.0)
	var back_strength := 0.46
	if landscape == "larch":
		back_strength = 0.49 if x < -5.0 else 0.23
	elif landscape == "orchard":
		back_strength = 0.025
	height += rise * minf(back * back_strength, 6.5) * (0.65 + 0.35 * pow(sin(x * 0.14), 2))
	var front := maxf(z - 11.0, 0.0)
	height += rise * minf(front * 0.08, 1.4)
	if landscape == "cactus" and flank > 1:
		# Erosion terraces emerge in the canyon flanks, while the walking floor stays smooth.
		height += minf(flank * 0.08, 0.6) * smoothstep(-0.5, 0.5, sin(height * 3.4 + z * 0.20))
	if landscape == "larch":
		var rest_shelf := (1.0 - smoothstep(2.3, 5.1, absf(x - 12.5))) * (1.0 - smoothstep(1.3, 4.0, absf(z - 6.3)))
		height = lerpf(height, 1.35, rest_shelf * 0.85)
	elif landscape == "orchard":
		# Outside the walking bounds, the hill opens into distant low farmland.
		# Do not leave a high terrain slab behind the much lower orchard skyline.
		var depth := -x * 0.2063 - z * 0.9785
		var across := x * 0.9785 - z * 0.2063
		var low_country := 0.70
		low_country += 3.4 * exp(-pow((across + 11.0) / 8.0, 2) - pow((depth - 21.5) / 8.0, 2))
		low_country += 2.4 * exp(-pow((across - 10.0) / 10.0, 2) - pow((depth - 27.0) / 8.0, 2))
		low_country += 0.32 * pow(sin(across * 0.16 + depth * 0.07), 2)
		height = lerpf(height, bank + rise * low_country, smoothstep(14.4, 21.0, depth))
	var gate_flat := (1.0 - smoothstep(0.85, 2.6, absf(x - 6.0))) * (1.0 - smoothstep(2.1, 3.9, absf(z - gate_y)))
	height = lerpf(height, 0.30, gate_flat)
	var bridge_flat := (1.0 - smoothstep(1.93, 3.4, absf(x))) * (1.0 - smoothstep(1.95, 3.1, absf(z - bridge_y)))
	height = lerpf(height, BRIDGE_HEIGHT, bridge_flat)
	return height

func _hill(x: float, z: float, cx: float, cz: float, sx: float, sz: float) -> float:
	return exp(-pow((x - cx) / sx, 2) - pow((z - cz) / sz, 2))
