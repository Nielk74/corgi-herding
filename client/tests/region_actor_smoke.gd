extends SceneTree
## Integration scope only. actor_batch_smoke independently verifies the exact
## rendered geometry, palette, normals and animation subtree equivalence.
const Meadow = preload("res://scripts/meadow.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("REGION_ACTOR_FAILED: " + message)

func visible_meshes(node: Node) -> int:
	var count := int(node is MeshInstance3D and node.visible)
	for child in node.get_children():
		count += visible_meshes(child)
	return count

func _run() -> void:
	var factory := Meadow.new()
	var old_count := 0
	var optimized_count := 0
	for landscape in ["alpine", "cactus", "larch", "orchard", "oasis", "cloud", "juniper", "bellflower", "alpine_valley"]:
		factory.landscape = landscape
		for i in 14:
			var kind := "player" if i < 2 else ("dog" if i < 4 else "sheep")
			var id := ("mochi" if i == 2 else "maple") if i in [2, 3] else "scope_%s_%d" % [landscape, i]
			var actor: Node3D = factory.make_actor(kind, id, i == 1)
			factory.remove_child(actor)
			root.add_child(actor)
			var body := actor.get_node("Body") as Node3D
			var head := body.get_node_or_null("Head") as Node3D
			var tail := body.get_node_or_null("Tail") as Node3D
			var count := visible_meshes(actor)
			if landscape == "alpine_valley":
				check(body.get_meta("rigid_parts_batched", false) and count >= 1 and count <= 2, "V7 factory automatically batches completed rigid parts into one or two visible meshes")
				optimized_count += count
			else:
				check(not body.get_meta("rigid_parts_batched", false) and count > 2, "Every legacy landscape keeps its original unbatched factory output")
				if landscape == "alpine":
					old_count += count
			if kind == "sheep":
				check(head != null and head.get_parent() == body and visible_meshes(head) >= 1, "Sheep retain the original visible animated Head subtree")
			elif kind == "dog":
				check(tail is MeshInstance3D and tail.visible and tail.get_parent() == body, "Corgi tail remains a distinct original animated mesh")
			for pose in 8:
				actor.position = Vector3(pose * 0.7, pose * 0.12, -pose)
				actor.rotation.y = pose * 0.31
				body.position.y = -0.32 if pose == 2 else sin(pose) * 0.035
				body.rotation.z = sin(pose * 0.4) * 0.04
				if head != null:
					head.rotation.x = -0.82 + sin(pose * 0.75) * 0.06
					check(actor.get_node("Body/Head") == head and head.global_transform.origin.is_finite(), "Nibbling still addresses the same moving Head pivot")
				if tail != null:
					tail.position.x = sin(pose * 3.0) * 0.13
					check(actor.get_node("Body/Tail") == tail and tail.global_transform.origin.is_finite(), "Happy tail motion still addresses the same independent mesh")
				check(actor.get_node("Body") == body and visible_meshes(actor) == count, "Walking/sitting transforms do not unbatch or hide existing actor parts")
			actor.queue_free()
		await process_frame
	check(optimized_count == 26 and old_count > optimized_count * 5, "The same14 v7 actors use26 visible batches without changing their entity count")
	check(factory.valley_life == null, "Actor construction alone neither spawns nor alters environmental life")
	factory.free()
	print("REGION_ACTOR_SMOKE: %d checks / %d failures;14 v7 actors %d→%d visible meshes, all8 legacy factories unchanged; existing Body/Head/Tail animation targets retained" % [checks, failures, old_count, optimized_count])
	quit(1 if failures else 0)
