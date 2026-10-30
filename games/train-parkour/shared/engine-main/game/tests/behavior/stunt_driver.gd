extends RefCounted
## Synthetic physical keys shared by headless behavior and native visual validation.
## Steers from observed state; never changes train position, velocity or scoring.

var jump_enabled := true
var aim_enabled := true
var tricks_enabled := true
var late_trick := false
var use_landing_hint := false
var held: Dictionary = {}
var late_started := -1.0


func tick(train: TrainController) -> void:
	var air := train.state == TrainController.State.AIR
	var drift := not air and train.distance >= 205.0 and train.distance < 515.0
	var side := 0
	if drift:
		side = 1
	elif air and aim_enabled:
		# Predict the stopping position under the same drag a player can learn.
		var predicted := train.lateral + train.air_side_speed / train.tuning.air_drag
		var error := train.landing_steering_error() if use_landing_hint else 4.4 - predicted
		if absf(error) > (0.7 if use_landing_hint else 0.18):
			side = 1 if error > 0.0 else -1
	set_key(KEY_SHIFT, drift)
	set_key(KEY_D, side > 0)
	set_key(KEY_A, side < 0)
	set_key(KEY_SPACE, jump_enabled and not air and train.distance >= 628.0 and train.distance < 640.0)
	if late_trick and air and train.landing_eta() < 0.26 and late_started < 0.0:
		late_started = train.air_time
	set_key(KEY_J, air and ((late_started >= 0.0 and train.air_time < late_started + 0.1) if late_trick else (tricks_enabled and train.air_time >= 0.12 and train.air_time < 0.22)))
	set_key(KEY_K, air and tricks_enabled and not late_trick and train.air_time >= 1.0 and train.air_time < 1.1)


func set_key(code: Key, pressed: bool) -> void:
	if held.get(code, false) == pressed:
		return
	held[code] = pressed
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func release() -> void:
	for code: Key in held.keys():
		set_key(code, false)
