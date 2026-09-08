extends RefCounted
## New dry-wash art recipe only. Does not define or expand walking collision.
## Its heightfield is sampled into the same indexed mesh used for feet/picking.

const BENCH_WIDTH := 2.5
const MESAS := [
	# Kept beyond the fine apron + blend zone, so their tops really appear in
	# the coarse scenic ring instead of being clipped by the near-field blend.
	{"center": Vector2(-184, -116), "radius": Vector2(66, 46), "top": 34.0},
	{"center": Vector2(186, -142), "radius": Vector2(74, 44), "top": 45.0},
	{"center": Vector2(30, -242), "radius": Vector2(88, 54), "top": 52.0}
]

static func height(point: Vector2, grade: float, clearance: float, noise: FastNoiseLite) -> float:
	var outside := maxf(-clearance - BENCH_WIDTH, 0.0)
	var small := noise.get_noise_2d(point.x, point.y)
	# A clean outer bench keeps bank relief outside every one-unit triangle
	# touching legal ground, not just outside legal sampled vertices.
	var exposure := noise.get_noise_2d(point.x * 0.24 + 81, point.y * 0.24 - 37)
	var banks := smoothstep(0, 6.5, outside) * 2.4
	banks += smoothstep(10, 21, outside) * 2.1
	banks += smoothstep(27, 44, outside) * 3.2
	banks *= 0.94 + exposure * 0.18
	return grade + small * (0.28 + minf(outside * 0.018, 0.5)) + banks

static func far_height(point: Vector2, noise: FastNoiseLite) -> float:
	var macro := noise.get_noise_2d(point.x * 0.18 + 23, point.y * 0.18 - 41)
	var ground := -4.0 + macro * 3.0
	var result := ground
	for mesa: Dictionary in MESAS:
		var local := (point - Vector2(mesa.center)) / Vector2(mesa.radius)
		var rim_noise := noise.get_noise_2d(point.x * 0.8 + 19, point.y * 0.8 + 63)
		var radius := local.length() + rim_noise * 0.055
		# Broad tops, an unequal shoulder, then a lower erosion bench. This is
		# not a Gaussian Alpine peak with its snow material removed.
		var cap := 1.0 - smoothstep(0.46, 0.82, radius)
		var skirt := 1.0 - smoothstep(0.82, 1.18, radius)
		var top := float(mesa.top) + macro * 0.8
		var height := ground + (top - ground) * (cap * 0.78 + skirt * 0.22)
		result = maxf(result, height)
	return result

static func fan_wear(point: Vector2, edges: Array[Dictionary], noise: FastNoiseLite) -> float:
	var wear := 0.0
	for edge: Dictionary in edges:
		var delta: Vector2 = edge.b - edge.a
		var length_squared := delta.length_squared()
		if length_squared <= 0 or not is_finite(length_squared):
			continue
		var t := clampf((point - Vector2(edge.a)).dot(delta) / length_squared, 0, 1)
		var distance := point.distance_to(Vector2(edge.a) + delta * t)
		var width := float(edge.width) * (0.48 + sin(t * PI) * 0.16)
		var breakup := 0.82 + noise.get_noise_2d(point.x * 0.31 + 14, point.y * 0.31 - 9) * 0.18
		wear = maxf(wear, (1.0 - smoothstep(width * 0.22, width, distance)) * 0.22 * breakup)
	return clampf(wear, 0, 0.22)
