extends Node
## Speed-matched locomotion for one imported character.
##
## Why this exists: the rig pilot produced Idle/Walk clips, but a clip that plays
## unconditionally is worse than no clip at all -- a clerk standing at a station
## would walk in place, and a body that never turns reads as a prop rather than a
## character. This node is the missing link between gameplay motion and the
## imported AnimationPlayer.
##
## Contract, deliberately narrow:
##   * It owns no transforms. It never touches position/rotation of the art, the
##     owner or the pivot -- placement stays art_layer's business and the pivot's
##     yaw stays gameplay's business.
##   * It reads ground truth from the controller (`get_real_velocity()`), not
##     from input. Blocked-by-a-wall and standing-still therefore look the same,
##     which is correct: both mean no ground travel.
##   * It is inert unless a binding declares `gait`. A manifest without `gait`
##     allocates nothing and plays nothing, so every existing binding behaves
##     exactly as before.
##
## Speed matching, stated plainly: playback rate is `actual_speed / nominal_speed`
## of whichever clip is active, clamped. `nominal_speed` is the ground speed at
## which the clip was authored to read correctly. That makes the three real
## speeds in this game (6.0 empty-handed, 5.4 carrying, 4.68 on a puddle)
## distinguishable by cadence instead of looking identical.
const FADE := 0.18
const STILL := 0.12

var config: Dictionary = {}
var controller: Node3D
var player: AnimationPlayer
var errors: Array = []
var current := ""
var current_speed := 0.0
var last_sample := {"clip": "", "speed": 0.0, "scale": 0.0}


## `host` is the node the imported GLB was instantiated under; the AnimationPlayer
## lives inside it. `body` is the CharacterBody3D whose real velocity we follow.
func setup(host: Node3D, body: Node3D, spec: Dictionary) -> void:
	config = spec
	controller = body
	player = _find_player(host)
	if player == null:
		errors.append("gait: no AnimationPlayer under " + str(host.name))
		set_physics_process(false)
		return
	var clips: Dictionary = config.get("clips", {})
	var known := player.get_animation_list()
	for role in ["idle", "walk", "run"]:
		var clip := str(clips.get(role, ""))
		if clip != "" and not known.has(clip):
			errors.append("gait: clip '%s' (%s) not in %s" % [clip, role, known])
	if _clip("idle") == "" and _clip("walk") == "":
		errors.append("gait: neither idle nor walk clip resolved")
		set_physics_process(false)
		return
	_play(_clip("idle") if _clip("idle") != "" else _clip("walk"), 0.0)


func _find_player(host: Node) -> AnimationPlayer:
	if host is AnimationPlayer:
		return host
	for child in host.find_children("*", "AnimationPlayer", true, false):
		return child as AnimationPlayer
	return null


func _clip(role: String) -> String:
	return str(config.get("clips", {}).get(role, ""))


func _nominal(role: String) -> float:
	var value := float(config.get("nominal_speed", {}).get(role, 0.0))
	return value if value > 0.0 else 0.0


func _physics_process(delta: float) -> void:
	if player == null or controller == null:
		return
	var speed := 0.0
	if controller is CharacterBody3D:
		var v: Vector3 = (controller as CharacterBody3D).get_real_velocity()
		speed = Vector2(v.x, v.z).length()
	var want := _clip("idle")
	var role := "idle"
	if speed > STILL and _clip("walk") != "":
		want = _clip("walk")
		role = "walk"
		var threshold := float(config.get("run_speed_min", 0.0))
		if threshold > 0.0 and speed >= threshold and _clip("run") != "":
			want = _clip("run")
			role = "run"
	if want == "":
		return
	if want != current:
		_play(want, FADE)
	# Rate follows ground truth, so cadence carries the speed difference instead
	# of every speed playing at the same rate.
	var rate := 1.0
	if speed > STILL:
		var nominal := _nominal(role)
		if nominal > 0.0:
			rate = speed / nominal
	rate = clampf(rate, float(config.get("scale_min", 0.55)), float(config.get("scale_max", 1.65)))
	player.speed_scale = rate
	current_speed = speed
	last_sample = {"clip": current, "role": role, "speed": speed, "scale": rate}


func _play(clip: String, fade: float) -> void:
	if clip == "":
		return
	current = clip
	player.speed_scale = 1.0
	if fade > 0.0:
		player.play(clip, fade)
	else:
		player.play(clip)
