extends "res://themes/performance_lod/optimized_context.gd"
const OutlineMerge = preload("res://themes/performance_lod/exact_outline_merge.gd")
var _outline_merge := OutlineMerge.new()

func _init() -> void:
	exact_merge = _outline_merge

func configure_outline_resources(budget: Dictionary, material_cache: Dictionary, geometry_cache: RefCounted = null) -> void:
	_outline_merge.use_shared_budget(budget)
	_outline_merge.use_shared_material_cache(material_cache)
	_outline_merge.set_geometry_cache(geometry_cache)
