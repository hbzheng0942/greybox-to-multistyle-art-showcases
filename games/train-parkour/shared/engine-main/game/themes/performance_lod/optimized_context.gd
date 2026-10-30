extends "res://themes/halloween_07/continuous/continuous_context.gd"
const ExactMerge = preload("res://themes/performance_lod/exact_static_merge.gd")
var exact_merge := ExactMerge.new()

func configure_merge_budget(budget: Dictionary) -> void:
	exact_merge.use_shared_budget(budget)

func _make_batch(mesh: Mesh, poses: Array, key: String, ident: String) -> void:
	var material: Material = mats.get(key)
	if not exact_merge.try_add(mesh, poses, material, key, ident, scene_id):
		super._make_batch(mesh, poses, key, ident)

func _original_batch(mesh: Mesh, poses: Array, key: String, ident: String, source_scene: String) -> void:
	var previous := scene_id; scene_id = source_scene
	super._make_batch(mesh, poses, key, ident)
	scene_id = previous

func _flush() -> void:
	super._flush()
	var audit: Dictionary = exact_merge.flush(world, _original_batch)
	world.set_meta("h07_exact_static_merge", audit)
	world.set_meta("performance_lod_report", audit)
	metrics["exact_static_merge"] = audit
	if not audit.passed: host.models.errors.append("H07 exact static merge failed: " + region_id)
