extends RefCounted
## Reusable offline mesh builder. Chunks share one sampling lattice and normals.
## Generated scenes are prototype art until their server layout is negotiated.

var recipe: RefCounted
var terrain_material: StandardMaterial3D
var textured := false
var grass_material: ShaderMaterial
var grass_mesh: ArrayMesh

func _init(profile: RefCounted, use_textures := false) -> void:
	recipe = profile
	textured = use_textures
	terrain_material = StandardMaterial3D.new()
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.vertex_color_is_srgb = true
	terrain_material.roughness = 0.95
	if textured:
		var id := "coast_sand_03" if recipe.data.biome == "cactus" else "aerial_grass_rock"
		var base := "res://assets/materials/%s/%s" % [id, id]
		terrain_material.albedo_texture = load(base + "_diff_1k.jpg")
		terrain_material.normal_enabled = true
		terrain_material.normal_texture = load(base + "_nor_gl_1k.png")
		terrain_material.normal_scale = 0.65
		terrain_material.roughness_texture = load(base + "_rough_1k.jpg")
		terrain_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		terrain_material.uv1_triplanar = true
		terrain_material.uv1_world_triplanar = true
		terrain_material.uv1_scale = Vector3.ONE * 0.25
		terrain_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	grass_material = ShaderMaterial.new()
	grass_material.shader = load("res://shaders/meadow_grass.gdshader")
	grass_mesh = _grass_mesh()

func build_chunk(key: Vector2i) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in range(17):
		for x in range(17):
			var wx := float(key.x * 16 + x)
			var wz := float(key.y * 16 + z)
			var normal: Vector3 = recipe.normal(wx, wz)
			vertices.append(Vector3(wx, recipe.node_height(wx, wz), wz))
			normals.append(normal)
			var tint: Color = recipe.color(wx, wz, normal.y)
			colors.append(Color.WHITE.lerp(tint, 0.12) if textured else tint)
			uv.append(Vector2(wx, wz) * 0.25)
			# Unique nonoverlapping atlas per chunk, ready for a later real bake.
			# A UV2 channel alone is not a lightmap and is never described as GI.
			uv2.append(Vector2(x, z) / 16.0 * 0.96 + Vector2.ONE * 0.02)
	for z in range(16):
		for x in range(16):
			var a := z * 17 + x
			indices.append_array(PackedInt32Array([a, a + 1, a + 18, a, a + 18, a + 17]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, terrain_material)
	var instance := MeshInstance3D.new()
	instance.name = "Ground_%d_%d" % [key.x, key.y]
	instance.mesh = mesh
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	return instance

func build_scene(include_details := false) -> Node3D:
	var world := Node3D.new()
	world.name = String(recipe.data.id).to_pascal_case()
	world.set_meta("recipe_version", recipe.data.recipe_version)
	world.set_meta("recipe_id", recipe.data.id)
	world.set_meta("prototype_not_network_layout", true)
	for key: Vector2i in recipe.chunk_keys():
		var chunk := build_chunk(key)
		world.add_child(chunk)
		chunk.owner = world
		if include_details:
			var detail := build_grass(key)
			if detail != null:
				world.add_child(detail)
				detail.owner = world
	return world

func build_grass(key: Vector2i) -> MultiMeshInstance3D:
	var placements: Array = recipe.scatter(key).filter(func(p: Dictionary) -> bool: return p.kind in ["grass", "scrub"])
	if placements.is_empty():
		return null
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = grass_mesh
	multi.instance_count = placements.size()
	# Populate the CPU buffer directly: the headless dummy renderer retains this
	# buffer but intentionally ignores per-instance setters. Offline packed scenes
	# must contain the same transforms/colors as a live GPU build.
	var buffer := PackedFloat32Array()
	buffer.resize(placements.size() * 20)
	var bounds := AABB()
	for i in placements.size():
		var placement: Dictionary = placements[i]
		var scale_value := float(placement.scale)
		var basis := Basis(Vector3.UP, placement.yaw).scaled(Vector3.ONE * scale_value)
		var transform := Transform3D(basis, placement.position)
		var green := Color("70864b") if placement.kind == "grass" else Color("918362")
		var color := green.lightened(float(i % 5) * 0.025)
		var row := PackedFloat32Array([
			basis.x.x, basis.y.x, basis.z.x, transform.origin.x,
			basis.x.y, basis.y.y, basis.z.y, transform.origin.y,
			basis.x.z, basis.y.z, basis.z.z, transform.origin.z,
			color.r, color.g, color.b, color.a, placement.phase, 0, 0, 0,
		])
		for column in range(20):
			buffer[i * 20 + column] = row[column]
		var instance_bounds: AABB = transform * grass_mesh.get_aabb()
		bounds = instance_bounds if i == 0 else bounds.merge(instance_bounds)
	multi.buffer = buffer
	multi.custom_aabb = bounds
	var instance := MultiMeshInstance3D.new()
	instance.name = "WindGrass_%d_%d" % [key.x, key.y]
	instance.multimesh = multi
	instance.material_override = grass_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 0.20
	# Bound detail rendering spatially. No all-world MultiMesh and no per-blade
	# nodes. Terrain remains independently visible beyond the vegetation range.
	instance.visibility_range_end = 80.0
	return instance

func _grass_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in range(4):
		var angle := blade * 2.399963
		var side := Vector3(cos(angle), 0, sin(angle)) * 0.028
		var root := Vector3(sin(angle), 0, cos(angle)) * 0.055
		var bend := Vector3(cos(angle), 0, sin(angle)) * 0.06
		var tip := root + bend + Vector3.UP * (0.18 + blade * 0.028)
		var middle := root + bend * 0.25 + Vector3.UP * 0.12
		for point in [root - side, root + side, middle + side * 0.6, root - side, middle + side * 0.6, middle - side * 0.6, middle - side * 0.6, middle + side * 0.6, tip]:
			surface.set_normal(Vector3.UP)
			surface.set_color(Color.WHITE)
			surface.add_vertex(point)
	return surface.commit()
