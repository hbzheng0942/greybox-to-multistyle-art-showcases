class_name NetworkCamera
extends RailCamera
## Short prop impulse accent only; original follow response and comfort stay intact.
var pulse_fov := 0.0

func _update_pose(delta: float, snap: bool) -> void:
	fov -= pulse_fov
	super._update_pose(delta, snap)
	pulse_fov = 0.0 if comfort else (train as NetworkTrain).pad_pulse * 5.0
	fov += pulse_fov
