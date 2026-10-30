extends "res://scripts/presentation/flow_fx.gd"
func _process(delta: float) -> void:
	super._process(delta)
	if sparks == null: return
	var motion := (train as SpatialTrain).motion
	boost.emitting = motion.active and motion.pulse > 0
	sparks.emitting = motion.active and motion.phase != SpatialMotionSolver.AIR and (motion.route.current.kind in ["grind", "wall", "inverted", "loop"] or motion.phase == SpatialMotionSolver.DRIFT)
