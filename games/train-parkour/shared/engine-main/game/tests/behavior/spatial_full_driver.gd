extends "res://tests/behavior/spatial_driver.gd"
## Physical-key strategy for the full course. Reads state, never writes motion truth.
var fast_canyon := false
var final_upper := false

func tick(train: TrainController) -> void:
	var p := train as SpatialTrain
	var m := p.motion
	var track := p.spatial.current
	if m.phase==SpatialMotionSolver.AIR and m.air_time<.8 and ((m.air_source=="station_ramp" and fast_canyon) or (m.air_source=="final_ramp" and final_upper)):
		# Early opposite steering changes the selected branch in the real game.
		# Correct overshoot after that choice window instead of oscillating routes.
		observation={"seconds":m.clock,"segment":track.id,"s":m.s}
		var prediction:=m.predict()
		var left:=false
		if not prediction.is_empty():
			left=p.get_viewport().get_camera_3d().global_basis.x.dot(prediction.target-prediction.point)<-.38
		set_key(KEY_SHIFT,false);set_key(KEY_A,left);set_key(KEY_D,false);set_key(KEY_SPACE,false)
		return
	if fast_canyon and track.id=="station_carve" and m.s>320.0:
		# The fast launch requires a centered approach. End the carve after the last
		# station hazard and allow a full lane transfer before the short ramp.
		observation={"seconds":m.clock,"segment":track.id,"s":m.s}
		var screen_sign:=signf(p.get_viewport().get_camera_3d().global_basis.x.dot(m.world_pose.basis.x))
		var direction: int=signi(-m.lane)*int(screen_sign)
		if held.get(KEY_A if direction<0 else KEY_D,false):direction=0
		set_key(KEY_SHIFT,false)
		set_key(KEY_A,direction<0)
		set_key(KEY_D,direction>0)
		set_key(KEY_SPACE,false)
		return
	var choose_branch := (track.id == "station_ramp" and fast_canyon) or (track.id == "final_ramp" and final_upper)
	if m.phase != SpatialMotionSolver.AIR and choose_branch:
		# Keep the centre lane with the brake held, then choose SPACE + A at the release window.
		# Do not emit the base driver's opposite steer event in the same frame.
		observation = {"seconds": m.clock, "segment": track.id, "s": m.s}
		set_key(KEY_SHIFT, true)
		set_key(KEY_A, m.s >= 8)
		set_key(KEY_D, false)
		set_key(KEY_SPACE, m.s >= 8)
		return
	super.tick(train)
