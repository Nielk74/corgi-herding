extends RefCounted
## Merge only rigid pieces inside each existing animated body/head subtree.
## Actor roots, sheep Head and dog Tail remain the original animation targets.
const StaticBatch = preload("res://scripts/static_scenery_batch.gd")

static func optimize(actor: Node3D) -> int:
	var body := actor.get_node_or_null("Body") as Node3D
	if body == null or body.get_meta("rigid_parts_batched", false):
		return 0
	var excluded: Array[Node] = []
	var head := body.get_node_or_null("Head") as Node3D
	var tail := body.get_node_or_null("Tail") as Node3D
	if head != null:
		excluded.append(head)
	if tail != null:
		excluded.append(tail)
	var merged := StaticBatch.merge(body, excluded)
	if head != null:
		merged += StaticBatch.merge(head, [])
	body.set_meta("rigid_parts_batched", true)
	return merged
