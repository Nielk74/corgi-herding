extends SceneTree
## Authoring toggles must not leak material state through the PackedScene cache.
const Studio = preload("res://tools/landscape_studio.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("STUDY_FAILED: " + message)

func button(scene: Node, text: String) -> Button:
	for control: Node in scene.find_children("*", "Button", true, false):
		if control.text == text:
			return control
	return null

func _run() -> void:
	var packed := load("res://tools/landscape_studio.tscn") as PackedScene
	for cycle in 3:
		Studio.recipe_index = 0
		var scene := packed.instantiate()
		root.add_child(scene)
		await process_frame
		check(scene.pine_surfaces.size() == 3 and scene.pine_drivers.size() == 1, "Three shared crowns use one bounded clock")
		check(scene.ground_materials.size() == 1, "One shared ground material, no per-chunk shader copies")
		var surfaces: Array = scene.pine_surfaces.duplicate()
		var arrays := {}
		for record: Dictionary in surfaces:
			check(record.mesh.surface_get_material(1) == record.original, "Reload begins with exact original needles")
			arrays[record.mesh] = [record.mesh.surface_get_arrays(0), record.mesh.surface_get_arrays(1), record.mesh.surface_get_material(0)]
		var pine := button(scene, "Pine study · original")
		check(pine != null, "Isolated pine comparison control exists")
		pine.pressed.emit()
		for record: Dictionary in surfaces:
			var candidate := record.mesh.surface_get_material(1) as ShaderMaterial
			check(candidate != null and candidate.get_shader_parameter("wind_strength") == 0.0, "Still candidate permits actual zero-motion color comparison")
		for driver: Node in scene.pine_drivers.values():
			check(not driver.is_processing(), "Still shader does not advance time")
		pine.pressed.emit()
		for record: Dictionary in surfaces:
			check(record.mesh.surface_get_material(1).get_shader_parameter("wind_strength") == 1.0, "Wind comparison explicitly enabled")
		for driver: Node in scene.pine_drivers.values():
			check(driver.is_processing(), "One clock advances active wind")
		pine.pressed.emit()
		for record: Dictionary in surfaces:
			check(record.mesh.surface_get_material(1) == record.original, "Original comparison restores source, not approximate shader")
			check(record.mesh.surface_get_arrays(0) == arrays[record.mesh][0] and record.mesh.surface_get_arrays(1) == arrays[record.mesh][1], "Comparisons do not rewrite mesh arrays")
			check(record.mesh.surface_get_material(0) == arrays[record.mesh][2], "Bark material unchanged")
		var grass := button(scene, "Grass study · original")
		check(grass != null, "Isolated ground comparison exists")
		grass.pressed.emit()
		for material: ShaderMaterial in scene.ground_materials:
			check(material.get_shader_parameter("ground_detail_contrast") == 0.76 and material.get_shader_parameter("ground_saturation") == 0.72, "Calmer grass is opt-in only")
		var ground: Array = scene.ground_materials.duplicate()
		var original_ground: Dictionary = scene.ground_originals.duplicate(true)
		# Leave while both studies are active: no cached state may leak on reload.
		pine.pressed.emit()
		pine.pressed.emit()
		scene.queue_free()
		await process_frame
		for record: Dictionary in surfaces:
			check(record.mesh.surface_get_material(1) == record.original, "Exit restores cached crown material")
		for material: ShaderMaterial in ground:
			check(material.get_shader_parameter("ground_detail_contrast") == original_ground[material][0] and material.get_shader_parameter("ground_saturation") == original_ground[material][1], "Exit restores exact earlier parameters, including null or the game preset")
	Studio.recipe_index = 1
	var cactus := packed.instantiate()
	root.add_child(cactus)
	await process_frame
	check(cactus.pine_surfaces.is_empty() and cactus.pine_drivers.is_empty(), "Cactus does not acquire pine motion")
	check(button(cactus, "Pine study · original") == null and button(cactus, "Grass study · original") == null, "Alpine studies do not recolor cactus")
	cactus.queue_free()
	await process_frame
	Studio.recipe_index = 0
	check(not FileAccess.get_file_as_string("res://scripts/main.gd").contains("Grass study"), "Authoring controls do not enter the game HUD")
	print("LANDSCAPE_STUDY: %d checks/%d failures; isolated visual studies, no GPU equivalence claim" % [checks, failures])
	quit(0 if failures == 0 else 1)
