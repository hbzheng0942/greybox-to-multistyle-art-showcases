extends "res://themes/halloween_festival/presentation.gd"
## Build static H07 with exact batching before attaching the animated festival layer.
const BatchedWorld = preload("res://themes/halloween_07/performance_presentation.gd")

func _init() -> void:
	base_builder = BatchedWorld.new()
