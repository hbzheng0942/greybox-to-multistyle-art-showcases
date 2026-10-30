extends "res://themes/halloween_07/continuous/continuous_presentation.gd"
const ExactMerge = preload("res://themes/performance_lod/exact_static_merge.gd")
const OptimizedContext = preload("res://themes/performance_lod/optimized_context.gd")
var exact_merge := ExactMerge.new()
var merge_budget := {"used_bytes": 0, "limit_bytes": ExactMerge.MAX_EXPANDED_BYTES}

func _init() -> void:
	exact_merge.use_shared_budget(merge_budget)

func create_region_context() -> RefCounted:
	var context := OptimizedContext.new()
	context.configure_merge_budget(merge_budget)
	return context

func _make_batch(mesh: Mesh, poses: Array, key: String, ident: String) -> void:
	var material: Material = mats.get(key)
	if not exact_merge.try_add(mesh, poses, material, key, ident):
		super._make_batch(mesh, poses, key, ident)

func _original_batch(mesh: Mesh, poses: Array, key: String, ident: String, _source_scene: String) -> void:
	super._make_batch(mesh, poses, key, ident)

func _flush() -> void:
	super._flush()
	var audit: Dictionary = exact_merge.flush(world, _original_batch)
	world.set_meta("h07_exact_static_merge", audit)
	if not audit.passed: models.errors.append("H07 exact static merge failed: retained sample")

func build(session: Node3D) -> Node3D:
	var result: Node3D = super.build(session)
	var audits := []
	for node: Node in [result] + result.find_children("*", "Node3D", true, false):
		if node.has_meta("h07_exact_static_merge"): audits.append(node.get_meta("h07_exact_static_merge"))
	var summary := {"groups": audits, "source_instances": 0, "source_legacy_chunks": 0, "merged_batches": 0, "triangles_before": 0, "triangles_after": 0, "fallback_triangles": 0, "expanded_geometry_bytes": 0, "retained_outline_source_batches": 0, "retained_outline_instances": 0, "retained_outline_legacy_chunks": 0, "retained_original_source_batches": 0, "retained_original_instances": 0, "retained_original_legacy_chunks": 0, "passed": true, "visibility_distance_added": false, "native_visual_acceptance": "pending_same_view_review"}
	for audit: Dictionary in audits:
		for field: String in ["source_instances", "source_legacy_chunks", "merged_batches", "triangles_before", "triangles_after", "fallback_triangles", "expanded_geometry_bytes", "retained_outline_source_batches", "retained_outline_instances", "retained_outline_legacy_chunks", "retained_original_source_batches", "retained_original_instances", "retained_original_legacy_chunks"]: summary[field] += int(audit[field])
		summary.passed = summary.passed and audit.passed
	var construction: Dictionary = result.get_meta("construction_report")
	construction["exact_static_merge"] = summary
	summary["shared_geometry_budget"] = merge_budget.duplicate()
	result.set_meta("construction_report", construction)
	result.set_meta("performance_lod_report", summary)
	return result
