extends "res://themes/performance_lod/optimized_presentation.gd"
const OutlineMerge = preload("res://themes/performance_lod/exact_outline_merge.gd")
const OutlineContext = preload("res://themes/performance_lod/optimized_outline_context.gd")
const GeometryCache = preload("res://themes/performance_lod/compiled_geometry_cache.gd")
var _outline_merge := OutlineMerge.new()
var _outline_material_cache: Dictionary = {}
var _geometry_cache: RefCounted

func _init() -> void:
	exact_merge = _outline_merge
	merge_budget = {"used_bytes": 0, "limit_bytes": OutlineMerge.MAX_OUTLINE_GEOMETRY_BYTES}
	_outline_merge.use_shared_budget(merge_budget)
	_outline_merge.use_shared_material_cache(_outline_material_cache)
	var cache_path := OS.get_environment("PARKOUR_H07_GEOMETRY_CACHE")
	if not cache_path.is_empty():
		configure_geometry_cache(cache_path, OS.get_environment("PARKOUR_H07_VERIFY_GEOMETRY_CACHE") == "1")

func configure_geometry_cache(path: String, verify: bool = false) -> bool:
	assert(int(merge_budget.used_bytes) == 0, "Configure the cache before building")
	var cache := GeometryCache.new()
	if not cache.configure(path, verify): return false
	_geometry_cache = cache
	_outline_merge.set_geometry_cache(cache)
	return true

func configure_outline_budget(bytes: int) -> void:
	assert(int(merge_budget.used_bytes) == 0, "Configure the budget before building")
	merge_budget.limit_bytes = clampi(bytes, 1, OutlineMerge.MAX_OUTLINE_GEOMETRY_BYTES)

func create_region_context() -> RefCounted:
	var context := OutlineContext.new()
	context.configure_outline_resources(merge_budget, _outline_material_cache, _geometry_cache)
	return context

func build(session: Node3D) -> Node3D:
	var result: Node3D = super.build(session)
	var report: Dictionary = result.get_meta("performance_lod_report")
	report["variant"] = "v2_original_outline_extrusion"
	report["material_resources_cloned"] = 0
	report["texture_copies_created"] = 0
	report["outline_vertices"] = 0
	report["max_custom0_extrusion_error"] = 0.0
	report["max_outline_position_error_m"] = 0.0
	report["shared_original_materials"] = true
	report["material_semantics_preserved"] = true
	for group: Dictionary in report.groups:
		report.material_resources_cloned += int(group.get("material_resources_cloned", 0))
		report.outline_vertices += int(group.get("outline_vertices", 0))
		report.max_custom0_extrusion_error = maxf(report.max_custom0_extrusion_error, float(group.get("max_custom0_extrusion_error", 0.0)))
		report.max_outline_position_error_m = maxf(report.max_outline_position_error_m, float(group.get("max_outline_position_error_m", 0.0)))
		report.shared_original_materials = report.shared_original_materials and group.shared_original_materials
		report.material_semantics_preserved = report.material_semantics_preserved and group.material_semantics_preserved
	report["material_or_texture_copies"] = report.material_resources_cloned
	report["shared_material_cache_entries"] = _outline_material_cache.size()
	if _geometry_cache != null: report["geometry_cache"] = _geometry_cache.report()
	result.set_meta("performance_lod_report", report)
	var construction: Dictionary = result.get_meta("construction_report")
	construction["exact_outline_merge"] = report
	result.set_meta("construction_report", construction)
	return result
