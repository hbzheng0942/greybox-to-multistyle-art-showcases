extends "res://scripts/presentation/flow_fx.gd"
## New support feedback is opt-in; the old Flow particle scene remains unchanged.

func _process(delta: float) -> void:
	super._process(delta)
	if sparks != null and train.active and (train as NetworkTrain).support_kind == "grind":
		sparks.emitting = true
