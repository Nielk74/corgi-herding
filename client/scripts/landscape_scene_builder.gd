extends RefCounted
## Full offline visual scene assembly. No actors, camera, light rig or collision.
## Gameplay must separately negotiate/validate the immutable server layout.
const Chunks = preload("res://scripts/landscape_chunk_builder.gd")
const Backdrop = preload("res://scripts/landscape_backdrop.gd")
const Props = preload("res://scripts/landscape_props.gd")
var profile: RefCounted

func _init(recipe: RefCounted) -> void:
	profile = recipe

func build() -> Node3D:
	var chunks := Chunks.new(profile, true, true)
	var world := chunks.build_scene(true)
	world.set_meta("full_visual_scene", true)
	world.set_meta("source_recipe", profile.data.duplicate(true))
	var backdrop := Backdrop.new(profile)
	var props := Props.new(profile, true)
	var keys: Array[Vector2i] = profile.chunk_keys()
	var prop_triangles := 0
	var prop_instances := 0
	for key in keys:
		var chunk := props.build_chunk(key)
		prop_triangles += int(chunk.get_meta("triangles"))
		prop_instances += int(chunk.get_meta("instances"))
		world.add_child(chunk)
		Props.set_scene_owner(chunk, world)
	# The apron protects lower phone rays from a cut mesh; it does not enlarge
	# the walking region. Its outer edge exactly matches the stitched scenic ring.
	for x in range(keys[0].x - 2, keys[-1].x + 3):
		for z in range(keys[0].y - 2, keys[-1].y + 3):
			var key := Vector2i(x, z)
			if not keys.has(key):
				var chunk := chunks.build_chunk(key)
				world.add_child(chunk)
				chunk.owner = world
	for chunk in world.get_children():
		if chunk is MeshInstance3D:
			chunk.material_override = backdrop.surface_material
	var ring := backdrop.build()
	world.add_child(ring)
	Props.set_scene_owner(ring, world)
	world.set_meta("scenic_triangles", ring.get_meta("triangle_count"))
	world.set_meta("prop_triangles", prop_triangles)
	world.set_meta("prop_instances", prop_instances)
	world.set_meta("fine_rect", backdrop.inner)
	return world

## CI verifies the complete source/asset fingerprint before export. Runtime also
## checks the embedded art recipe, so a mismatched prepared scene is never used.
static func load_or_build(recipe: RefCounted) -> Node3D:
	var path := "res://generated/%s.scn" % String(recipe.data.id)
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var scene := packed.instantiate() as Node3D
			if scene != null:
				if scene.get_meta("full_visual_scene", false) and scene.get_meta("source_recipe", {}) == recipe.data:
					return scene
				scene.free()
	# Development-only fallback; release CI always cooks and checks both scenes.
	return load("res://scripts/landscape_scene_builder.gd").new(recipe).build()
