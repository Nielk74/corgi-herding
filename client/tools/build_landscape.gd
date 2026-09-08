extends SceneTree
## Run through tools/run-godot-check.sh. Source recipes remain small and reviewed;
## generated binary scenes belong in an ignored build directory until accepted.

const Recipe = preload("res://scripts/landscape_recipe.gd")
const Builder = preload("res://scripts/landscape_chunk_builder.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source := ""
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--recipe="):
			source = argument.trim_prefix("--recipe=")
		elif argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if source.is_empty() or not output.ends_with(".scn") or FileAccess.file_exists(output):
		printerr("Supply --recipe=<json> and --out=<new .scn file>; existing scenes are never overwritten.")
		quit(1)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
	var errors: Array[String] = Recipe.validate(data)
	if not errors.is_empty():
		printerr("Invalid recipe: " + "; ".join(errors))
		quit(1)
		return
	var start := Time.get_ticks_msec()
	var builder := Builder.new(Recipe.new(data), true)
	var scene := builder.build_scene(true)
	var packed := PackedScene.new()
	if packed.pack(scene) != OK or ResourceSaver.save(packed, output, ResourceSaver.FLAG_COMPRESS) != OK:
		scene.free()
		printerr("Could not save prototype landscape")
		quit(1)
		return
	print("Built %s: %d terrain/detail nodes in %dms → %s. Prototype art, not an accepted multiplayer map." % [data.id, scene.get_child_count(), Time.get_ticks_msec() - start, output])
	scene.free()
	quit(0)
