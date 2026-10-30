extends "res://tests/behavior/spatial_full_driver.gd"
## Supplemental short-high approach: normal brake/steer/jump inputs only.
## The frozen full-speed driver intentionally lands on high_merge in R2.
var high_short := false
func tick(train: TrainController) -> void:
	var p := train as SpatialTrain
	var m := p.motion
	var id: String = p.spatial.current.id
	if high_short and m.phase != SpatialMotionSolver.AIR and id in ["loop_out","exit_ramp"]:
		observation = {"seconds":m.clock,"segment":id,"s":m.s}
		var jump := id=="exit_ramp" and m.s>=11.0
		set_key(KEY_SHIFT,true)
		set_key(KEY_A,jump)
		set_key(KEY_D,false)
		set_key(KEY_SPACE,jump)
		return
	super.tick(train)
