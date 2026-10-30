extends Node3D
## Museum Dog — playable greybox v0.2.
## Space/scale owned by MuseumBuilder; this script owns the dog, props, visitors, camera and HUD.

const MOVE_SPEED := 4.2
const ZOOMIES_SPEED := 9.5
const ZOOMIES_TIME := 2.6
const ZOOMIES_COOLDOWN := 6.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 6.9
const MuseumBuilderScript := preload("res://shared/game/museum_builder.gd")
const PropSpecs := preload("res://shared/game/prop_specs.gd")
const VisualCatalogScript := preload("res://shared/game/visual_catalog.gd")
const CAM_MIN := 1.4
const CAM_MAX := 7.0
const DOG_SPAWN := Vector3(0, 0.5, 2.6)
const VISITOR_RECOVERY_TIME := 6.0
const VISITOR_RECOVERY_IMMUNITY := 2.0

## 音效：tools/gen_sfx.py 合成，裸 PCM 直接塞进 AudioStreamWAV，不走资源导入
const SFX_DIR := "res://assets/audio/"
const SFX_KEYS := ["ceramic", "porcelain", "glass", "stone", "wood", "metal",
	"soft", "thud", "bark", "applause", "whoosh", "alarm"]
## 各音色的基准增益（dB）：素材统一按 RMS 归一，这里只做"听起来该多响"的修
const SFX_GAIN := {
	"ceramic": 0.0, "porcelain": -1.0, "glass": -1.5, "stone": 1.0,
	"wood": -2.0, "metal": -2.0, "soft": -3.0, "thud": 0.0,
	"bark": 2.0, "applause": 4.0, "whoosh": -3.0, "alarm": 3.0,
}

var builder: Node3D
var visual_catalog
var dog: CharacterBody3D
var cam: Camera3D
var mouth: Node3D

var yaw := 0.0
var pitch := 0.30
var cam_distance := 4.6
var cam_target: Node3D
var rmb_down := false
var last_safe_dog_transform := Transform3D(Basis.IDENTITY, DOG_SPAWN)
var feedback_text := ""
var feedback_left := 0.0

var held: RigidBody3D = null
var props: Array[RigidBody3D] = []
var visitors: Array[Dictionary] = []

var damage := 0
var heat := 0.0
var zoomies_left := 0.0
var zoomies_cool := 0.0
var bark_cool := 0.0

var ui_font: Font
var loss_label: Label
var heat_label: Label
var heat_bar: ColorRect
var state_label: Label

var sfx: Dictionary = {}
var sfx_3d: Array[AudioStreamPlayer3D] = []
var sfx_2d: Array[AudioStreamPlayer] = []
var was_on_floor := true
var sfx_played := 0
var game_time := 0.0
var last_impact_time := -1.0

var selftest := false
var selftest_frame := 0
var capture_path := ""
var shot := ""
var shots_dir := ""
var shot_queue: Array = []
var shot_index := 0
var shot_warmup := 0
var shot_busy := false
var cam_follow := false
var shot_pos := Vector3.ZERO
var shot_look := Vector3.ZERO
var shot_fov := 64.0
var frames := 0
var captured := false
var trace := false
## --nohud: 出美术取材图时关掉 HUD（HUD 不该进概念图的输入）
var nohud := false
var chaos := false
var chaos_t0 := 0.0
var knocktest := false
var knock_frame := 0
var phys_frames := 0
var skel: Dictionary = {}
var pending_breaks: Array = []

# ---- Gag 1：警报 → 全体僵住 → 鼓掌 ----
# 0=idle 1=alarm 2=stare 3=clap。鼓掌是奖励不是惩罚：heat 只涨不跌。
const GAG_DUR := {"alarm": 0.75, "stare": 1.25, "clap": 2.0}
const GAG_HEAT_TRIGGER := 45.0
const GAG_COOL := 24.0
var gag_phase := 0
var gag_t := 0.0
var gag_cool := 0.0
var gag_count := 0
var gagtest := false
var gag_frame := 0
var bonetest := false
var bone_frame := 0
var gag2test := false
var gag2_frame := 0
var gag_title: Label = null
var gag_sub: Label = null
var gag_tint: ColorRect = null
var gag_band: ColorRect = null

# ---- Gag 2：骨架塌了 → 全场后退 → 小孩先鼓掌 → 保安慢半拍 ----
# 0=idle 1=hush 2=silence 3=kid 4=guard。保安的笑点不是塌，是掌声。
const GAG2_DUR := {"hush": 1.15, "silence": 0.85, "kid": 1.0, "guard": 1.3}
var gag2_phase := 0
var gag2_t := 0.0
var gag2_done := false

## 固定机位：用来看空间，而不是看玩法。--shot=name 时相机脱离狗。
const SHOTS := {
	"hall": {"pos": Vector3(-0.4, 2.9, 4.8), "look": Vector3(-0.4, 2.1, -2.6), "fov": 60.0},
	"skel": {"pos": Vector3(-0.6, 2.5, 1.9), "look": Vector3(0.6, 2.3, -2.4), "fov": 46.0},
	# 出骨架建模取材图用：从 3.9 m 高斜下拍，把狗和围栏让出画面，保住整具骨架的侧影比例
	"skel_side": {"pos": Vector3(-0.5, 3.9, 5.2), "look": Vector3(0.0, 1.3, -2.2), "fov": 40.0},
	"hall_corner": {"pos": Vector3(-5.4, 3.0, 6.9), "look": Vector3(2.6, 1.6, -3.2), "fov": 66.0},
	"porcelain": {"pos": Vector3(-8.6, 2.1, 1.2), "look": Vector3(-16.0, 1.2, 1.2), "fov": 64.0},
	"taxidermy": {"pos": Vector3(9.0, 3.2, 4.8), "look": Vector3(14.6, 1.3, -1.2), "fov": 68.0},
	"kids": {"pos": Vector3(-1.4, 3.4, -6.8), "look": Vector3(0.6, 0.6, -12.8), "fov": 68.0},
	"vestibule": {"pos": Vector3(0.0, 2.0, 10.8), "look": Vector3(0.0, 1.4, 7.6), "fov": 64.0},
	"props": {"pos": Vector3(-12.0, 1.8, -2.6), "look": Vector3(-13.4, 1.1, 2.0), "fov": 58.0},
	"door_play": {"follow": true, "dog": Vector3(-9.6, 0.5, 1.5), "yaw": 1.5708, "pitch": 0.24, "dist": 4.4},
	"hall_play": {"follow": true, "dog": Vector3(0.0, 0.5, 2.6), "yaw": 0.0, "pitch": 0.3, "dist": 4.2},
	"kids_play": {"follow": true, "dog": Vector3(0.6, 0.5, -9.2), "yaw": 0.0, "pitch": 0.12, "dist": 3.8},
	"chaos": {"follow": true, "dog": Vector3(-13.0, 0.5, 0.7), "yaw": 1.5708, "pitch": 0.16, "dist": 4.2},
}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		if arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
		if arg == "--selftest":
			selftest = true
		if arg == "--trace":
			trace = true
		if arg == "--nohud":
			nohud = true
		if arg == "--chaos":
			chaos = true
		if arg == "--knocktest":
			knocktest = true
		if arg == "--gagtest":
			gagtest = true
		if arg == "--bonetest":
			bonetest = true
		if arg == "--gag2test":
			gag2test = true
	ui_font = _load_ui_font()
	_load_sfx()
	_install_input()
	_build_environment()
	_build_space()
	_spawn_props()
	_register_skeleton()
	_spawn_visitors()
	_build_dog()
	_apply_shot()
	_build_camera()
	_build_hud()
	visual_catalog = VisualCatalogScript.new()
	visual_catalog.bind_game(self)
	_log("ready props=%d visitors=%d spots=%d" % [props.size(), visitors.size(), builder.exhibit_spots.size()])
	if shot == "chaos":
		chaos = true
	if not shots_dir.is_empty():
		shot_queue = SHOTS.keys()
		shot_queue.sort()
		shot_queue.erase("chaos")
		_load_shot(shot_queue[0])

func _apply_shot() -> void:
	if shot.is_empty():
		return
	if not SHOTS.has(shot):
		_log("unknown shot: " + shot)
		shot = ""
		return
	_set_shot_conf(shot)
	dog.global_position = Vector3(shot_pos.x, 0.5, shot_pos.z)

func _set_shot_conf(key: String) -> void:
	shot = key
	var conf: Dictionary = SHOTS[key]
	cam_follow = conf.get("follow", false)
	if cam_follow:
		# 玩法机位：把狗放到指定位置，相机仍然走正常的跟随+避障逻辑
		shot_pos = conf["dog"]
		shot_look = conf["dog"]
		yaw = conf["yaw"]
		pitch = conf["pitch"]
		cam_distance = conf["dist"]
	else:
		shot_pos = conf["pos"]
		shot_look = conf["look"]
		shot_fov = conf["fov"]

func _load_shot(key: String) -> void:
	_set_shot_conf(key)
	dog.global_position = Vector3(shot_pos.x, 0.5, shot_pos.z)
	dog.velocity = Vector3.ZERO
	if cam_follow:
		dog.rotation.y = yaw
	cam_target.global_position = dog.global_position + Vector3(0, 1.05, 0)
	_update_camera(1.0, true)
	shot_warmup = 0

func _load_sfx() -> void:
	for key in SFX_KEYS:
		var path: String = SFX_DIR + str(key) + ".pcm"
		if not FileAccess.file_exists(path):
			continue
		var bytes := FileAccess.get_file_as_bytes(path)
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 44100
		stream.stereo = false
		stream.data = bytes
		sfx[key] = stream
		if trace:
			_log("sfx %-9s %.2fs %d bytes" % [str(key), stream.get_length(), bytes.size()])
	for i in range(14):
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 7.0
		player.max_distance = 42.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		sfx_3d.append(player)
	for i in range(4):
		var player2 := AudioStreamPlayer.new()
		add_child(player2)
		sfx_2d.append(player2)
	_log("sfx loaded=%d" % sfx.size())

func _play_sfx(key: String, at: Vector3, extra_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sfx.has(key):
		return
	# Gag 2 的"安静"那一拍：世界先闭嘴，笑点才立得住。只在那一拍压掉，不影响计数
	if gag2_phase == 2:
		return
	sfx_played += 1
	var player: AudioStreamPlayer3D = null
	for candidate in sfx_3d:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = sfx_3d[0]
	player.stream = sfx[key]
	player.global_position = at
	player.volume_db = float(SFX_GAIN.get(key, 0.0)) + extra_db
	player.pitch_scale = pitch
	player.play()

func _play_sfx_flat(key: String, extra_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sfx.has(key):
		return
	if gag2_phase == 2:
		return
	sfx_played += 1
	var player: AudioStreamPlayer = null
	for candidate in sfx_2d:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = sfx_2d[0]
	player.stream = sfx[key]
	player.volume_db = float(SFX_GAIN.get(key, 0.0)) + extra_db
	player.pitch_scale = pitch
	player.play()

## 碰撞取音：靠"速度骤降"判断撞击，比 RigidBody 信号便宜，也不用开 contact_monitor
func _detect_impacts() -> void:
	for prop in props:
		var speed := prop.linear_velocity.length()
		var prev := float(prop.get_meta("prev_speed", 0.0))
		prop.set_meta("prev_speed", speed)
		if prop == held or speed > prev:
			continue
		if prev < 1.7 or speed > prev * 0.6:
			continue
		if game_time - float(prop.get_meta("sfx_t", -9.0)) < 0.14:
			continue
		if game_time - last_impact_time < 0.045:
			continue
		last_impact_time = game_time
		prop.set_meta("sfx_t", game_time)
		var key := _sfx_for_kind(str(prop.get_meta("kind", "")))
		var gain := clampf(linear_to_db(clampf(prev / 7.0, 0.2, 1.0)), -14.0, 0.0)
		_play_sfx(key, prop.global_position, gain, randf_range(0.88, 1.14))

	# 被撞飞的游客砸到地上：这一声是"疼"的关键，不走全局限流
	for v in visitors:
		if not v["down"]:
			continue
		var torso: RigidBody3D = v["torso"]
		var part_speed := torso.linear_velocity.length()
		var part_prev := float(v.get("part_prev", 0.0))
		v["part_prev"] = part_speed
		# 布娃娃是滚动衰减，不像展品那样一帧归零，阈值要放软
		if part_prev < 2.0 or part_speed > part_prev * 0.75:
			continue
		if game_time - float(v.get("part_sfx_t", -9.0)) < 0.3:
			continue
		v["part_sfx_t"] = game_time
		var fall_gain := clampf(linear_to_db(clampf(part_prev / 6.0, 0.25, 1.0)), -10.0, 2.0)
		_play_sfx("thud", torso.global_position, fall_gain, randf_range(0.82, 0.98))

func _sfx_for_kind(kind: String) -> String:
	match kind:
		"plate":
			return "porcelain"
		"vase", "vase_big":
			return "ceramic"
		"ball", "brochure":
			return "soft"
		"rock", "bust":
			return "stone"
		"specimen":
			return "thud"
		"bone", "button", "souvenir", "craft":
			return "wood"
		_:
			return "wood"

func _install_input() -> void:
	var keys := {
		"dog_left": [KEY_A, KEY_LEFT], "dog_right": [KEY_D, KEY_RIGHT],
		"dog_forward": [KEY_W, KEY_UP], "dog_back": [KEY_S, KEY_DOWN],
		"dog_grab": [KEY_E], "dog_throw": [KEY_SPACE],
		"dog_zoomies": [KEY_SHIFT], "dog_bark": [KEY_F],
		"dog_reset": [KEY_R]
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.86)
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -34, 0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 0.22
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

func _build_space() -> void:
	builder = MuseumBuilderScript.new()
	builder.name = "Museum"
	add_child(builder)
	builder.build()

# ---------------- dog ----------------

func _build_dog() -> void:
	dog = CharacterBody3D.new()
	dog.name = "Dog"
	dog.position = DOG_SPAWN
	dog.collision_layer = 8
	dog.collision_mask = 1 | 2 | 4
	add_child(dog)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 0.7
	shape.shape = capsule
	shape.position = Vector3(0, 0.35, 0)
	dog.add_child(shape)

	var fur := _mat(Color(0.86, 0.55, 0.28))
	var dark := _mat(Color(0.25, 0.22, 0.2))
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.23
	body_mesh.height = 0.6
	body.mesh = body_mesh
	body.rotation_degrees = Vector3(90, 0, 0)
	body.position = Vector3(0, 0.33, 0.02)
	body.material_override = fur
	dog.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.18
	head_mesh.height = 0.36
	head.mesh = head_mesh
	head.position = Vector3(0, 0.5, -0.33)
	head.material_override = fur
	dog.add_child(head)

	var snout := MeshInstance3D.new()
	var snout_mesh := BoxMesh.new()
	snout_mesh.size = Vector3(0.15, 0.11, 0.19)
	snout.mesh = snout_mesh
	snout.position = Vector3(0, 0.46, -0.5)
	snout.material_override = dark
	dog.add_child(snout)

	for side in [-1, 1]:
		var ear := MeshInstance3D.new()
		var ear_mesh := BoxMesh.new()
		ear_mesh.size = Vector3(0.09, 0.15, 0.06)
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.1, 0.65, -0.31)
		ear.rotation_degrees = Vector3(0, 0, side * -12)
		ear.material_override = dark
		dog.add_child(ear)

	var tail := MeshInstance3D.new()
	var tail_mesh := CapsuleMesh.new()
	tail_mesh.radius = 0.055
	tail_mesh.height = 0.4
	tail.mesh = tail_mesh
	tail.position = Vector3(0, 0.48, 0.34)
	tail.rotation_degrees = Vector3(55, 0, 0)
	tail.material_override = fur
	dog.add_child(tail)

	mouth = Node3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(0, 0.45, -0.48)
	dog.add_child(mouth)

# ---------------- camera ----------------

func _build_camera() -> void:
	cam_target = Node3D.new()
	cam_target.name = "CameraTarget"
	add_child(cam_target)
	cam = Camera3D.new()
	cam.name = "DogCamera"
	cam.fov = 66.0
	cam.near = 0.05
	cam.current = true
	add_child(cam)
	_update_camera(1.0, true)

func _update_camera(delta: float, snap: bool = false) -> void:
	if dog == null:
		return
	if not shot.is_empty() and not cam_follow:
		cam.global_position = shot_pos
		if shot_pos.distance_to(shot_look) > 0.01:
			cam.look_at(shot_look, Vector3.UP)
		cam.fov = shot_fov
		return
	var anchor := dog.global_position + Vector3(0, 0.45, 0)
	var focus := dog.global_position + Vector3(0, 1.05, 0) - dog.global_transform.basis.z * 0.35
	# The target must stay visible too: a dog can walk under a table whose top
	# lies below the usual shoulder-height focus.
	focus = _camera_safe_position(anchor, focus)
	var smoothed_focus := cam_target.global_position.lerp(focus, 1.0 if snap else clampf(delta * 12.0, 0.0, 1.0))
	cam_target.global_position = _camera_safe_position(anchor, smoothed_focus)

	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * cam_distance
	var desired := cam_target.global_position + offset

	# 焦点先从狗身内扫到安全位置，再以这个已净空的焦点作为轨道中心。
	# 从低矮狗身直接收缩相机会把近墙镜头压到焦点下方，造成突兀仰视。
	# CAM_MIN 只约束滚轮距离；墙边可以更近。插值之后再扫一次。
	var camera_origin := cam_target.global_position
	desired = _camera_safe_position(camera_origin, desired)
	var candidate := desired if snap else cam.global_position.lerp(desired, clampf(delta * 9.0, 0.0, 1.0))
	cam.global_position = _camera_safe_position(camera_origin, candidate)
	if cam.global_position.distance_squared_to(cam_target.global_position) > 0.0001:
		cam.look_at(cam_target.global_position, Vector3.UP)

func _camera_safe_position(anchor: Vector3, desired: Vector3) -> Vector3:
	var motion := desired - anchor
	if motion.length_squared() < 0.0001:
		return anchor
	var sphere := SphereShape3D.new()
	sphere.radius = 0.22
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, anchor)
	query.collision_mask = 1
	query.motion = motion
	var cast := get_world_3d().direct_space_state.cast_motion(query)
	if cast.size() == 2 and cast[0] < 1.0:
		return anchor + motion * maxf(0.0, cast[0] - 0.02 / motion.length())
	return desired

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			rmb_down = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_distance = clampf(cam_distance - 0.45, CAM_MIN, CAM_MAX)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_distance = clampf(cam_distance + 0.45, CAM_MIN, CAM_MAX)
	if event is InputEventMouseMotion and rmb_down:
		yaw -= event.relative.x * 0.0038
		pitch = clampf(pitch + event.relative.y * 0.003, -0.12, 1.05)

# ---------------- loop ----------------

func _physics_process(delta: float) -> void:
	phys_frames += 1
	game_time += delta
	feedback_left = maxf(0.0, feedback_left - delta)
	if chaos and phys_frames == 30:
		_simulate_rampage()
		chaos_t0 = game_time
	if chaos and phys_frames == 150:
		var span := maxf(0.01, game_time - chaos_t0)
		_log("sfx played=%d in %.2fs (%.1f/s)" % [sfx_played, span, float(sfx_played) / span])
		get_tree().quit(0)
	_move_dog(delta)
	_recover_dog_if_needed()
	_handle_grab(delta)
	_handle_zoomies(delta)
	_handle_bark(delta)
	_handle_reset()
	_update_visitors(delta)
	_update_gag(delta)
	_update_gag2(delta)
	_update_bones()
	_detect_impacts()
	_check_props()
	_decay_heat(delta)
	_check_visitor_hits()
	_update_camera(delta)
	_update_hud()
	if selftest:
		_run_selftest()
	if knocktest:
		_run_knocktest()
	if gagtest:
		_run_gagtest()
	if bonetest:
		_run_bonetest()
	if gag2test:
		_run_gag2test()

## Gag 2 验证：直接把骨架撞塌，看四拍是否按 0.7 / 0.85 / 1.0 / 1.3 秒走完
func _run_gag2test() -> void:
	gag2_frame += 1
	var f := gag2_frame
	if f == 1:
		var center := _skel_center()
		shot = "gag2cam"
		cam_follow = false
		shot_pos = Vector3(5.6, 2.7, 2.0)
		shot_look = Vector3(-3.0, 1.0, -2.4)
		shot_fov = 58.0
		dog.global_position = Vector3(0.0, 1.4, -1.6)
		cam_target.global_position = dog.global_position + Vector3(0, 1.05, 0)
		_update_camera(1.0, true)
		_log("gag2test camera, skel at %s" % str(center.snapped(Vector3(0.1, 0.1, 0.1))))
	if f == 3:
		for leg in ["back_leg_l", "back_leg_r", "front_leg_l", "front_leg_r"]:
			_break_bone(str(leg), Vector3(0.3, 0, 0.3))
	if f % 15 == 0:
		_log("gag2test f=%3d phase=%d t=%.2f heat=%.1f sfx=%d" % [f, gag2_phase, gag2_t, heat, sfx_played])
	if f == 320:
		_log("gag2test done phase=%d gag2_done=%s heat=%.1f" % [gag2_phase, str(gag2_done), heat])
		get_tree().quit(0)

## 骨架支撑图验证：先断两条后腿（应只塌骨盆+尾巴），再断两条前腿（应整具垮下）
func _run_bonetest() -> void:
	bone_frame += 1
	var f := bone_frame
	if f == 1:
		# 机位对着骨架，从侧面看整具塌下来
		var origin: Vector3 = skel["pelvis"]["body"].global_position
		shot = "bonecam"
		cam_follow = false
		shot_pos = origin + Vector3(6.6, 2.4, 5.2)
		shot_look = origin + Vector3(0.2, -0.4, 0.0)
		shot_fov = 52.0
		dog.global_position = origin + Vector3(1.2, -1.2, 2.2)
		cam_target.global_position = dog.global_position + Vector3(0, 1.05, 0)
		_update_camera(1.0, true)
		_log("bonetest camera at %s" % str(origin.snapped(Vector3(0.1, 0.1, 0.1))))
	if f == 2:
		# 用「咬」而不是脚本断：验证玩家的第一动作就能拽下一段骨
		dog.global_position = Vector3(-1.25, 1.35, -2.05)
		dog.rotation.y = 0.0
		dog.velocity = Vector3.ZERO
		_try_grab()
	if f == 6:
		# 第二条腿用脚本断：狗站在骨盆正下方时，抓取球会先够到骨盆（体积更大），
		# 那是真实的选取结果，不适合拿来当回归基线
		_break_bone("back_leg_r", Vector3(-0.4, 0, 0.3))
	if f == 12:
		_log("bonetest bite result: %s" % _broken_list())
	if f == 40:
		_log("bonetest after back legs: %s" % _broken_list())
	if f == 44:
		_break_bone("front_leg_l", Vector3(0.4, 0, -0.3))
	if f == 48:
		_break_bone("front_leg_r", Vector3(-0.4, 0, -0.3))
	if f == 90:
		_log("bonetest after front legs: %s" % _broken_list())
	if f == 150:
		_log("bonetest done broken=%d/12 damage=%d" % [_broken_count(), damage])
		get_tree().quit(0)

func _broken_list() -> String:
	var names: Array = []
	for id in skel:
		if skel[id]["broken"]:
			names.append(id)
	return " ".join(names)

func _broken_count() -> int:
	var n := 0
	for id in skel:
		if skel[id]["broken"]:
			n += 1
	return n

## Gag 1 的验证：不靠手打，直接按时间轴跑一遍，看相位、站立人数、音效数
func _run_gagtest() -> void:
	gag_frame += 1
	var f := gag_frame
	if f == 1:
		# 找站得最近的一对游客，把狗摆到他们正前方，机位从侧后方框住三个人
		var best := 999.0
		var pair: Array = []
		for i in range(visitors.size()):
			for j in range(i + 1, visitors.size()):
				var a: Node3D = visitors[i]["root"]
				var b: Node3D = visitors[j]["root"]
				var d := a.global_position.distance_to(b.global_position)
				if d < best:
					best = d
					pair = [a.global_position, b.global_position]
		var mid: Vector3 = (Vector3(pair[0]) + Vector3(pair[1])) * 0.5
		dog.global_position = mid + Vector3(0.5, 0.55, 2.0)
		shot = "gagcam"
		cam_follow = false
		shot_pos = mid + Vector3(6.4, 3.3, 3.2)
		shot_look = mid + Vector3(-0.3, 1.2, 0.5)
		shot_fov = 50.0
		cam_target.global_position = dog.global_position + Vector3(0, 1.05, 0)
		_update_camera(1.0, true)
		_log("gagtest pair dist=%.2f at %s" % [best, str(mid.snapped(Vector3(0.1, 0.1, 0.1)))])
	if f == 3:
		heat = GAG_HEAT_TRIGGER + 8.0
		_log("gagtest trigger heat=%.0f" % heat)
	if f % 15 == 0:
		_log("gagtest f=%3d phase=%d t=%.2f heat=%.1f up=%d sfx=%d"
			% [f, gag_phase, gag_t, heat, _up_count(), sfx_played])
	if f == 268:
		_log("gagtest done phase=%d claps=%d heat=%.1f cool=%.0f" % [gag_phase, gag_count, heat, gag_cool])
		get_tree().quit(0)

func _move_dog(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("dog_right") - Input.get_action_strength("dog_left"),
		Input.get_action_strength("dog_back") - Input.get_action_strength("dog_forward")
	)
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := right * input.x + forward * -input.y
	if dir.length() > 1.0:
		dir = dir.normalized()

	var speed := ZOOMIES_SPEED if zoomies_left > 0.0 else MOVE_SPEED
	dog.velocity.x = dir.x * speed
	dog.velocity.z = dir.z * speed
	dog.velocity.y -= GRAVITY * delta
	dog.move_and_slide()

	if dir.length() > 0.1:
		dog.rotation.y = lerp_angle(dog.rotation.y, atan2(-dir.x, -dir.z), delta * 11.0)

	var on_floor := dog.is_on_floor()
	if on_floor and not was_on_floor and absf(dog.velocity.y) > 1.0:
		_play_sfx("thud", dog.global_position, -9.0, randf_range(1.15, 1.3))
	was_on_floor = on_floor
	if on_floor and dog.global_position.y > -0.5:
		var ray := PhysicsRayQueryParameters3D.create(
			dog.global_position + Vector3(0, 0.08, 0), dog.global_position - Vector3(0, 0.2, 0), 1)
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not floor_hit.is_empty() and Vector3(floor_hit["normal"]).y > 0.65:
			last_safe_dog_transform = dog.global_transform

func _recover_dog_if_needed() -> void:
	var at := dog.global_position
	if at.y >= -4.0 and absf(at.x) <= 40.0 and at.z >= -30.0 and at.z <= 24.0:
		return
	if held != null:
		_release(false)
	var restored := last_safe_dog_transform
	restored.origin += Vector3(0, 0.12, 0)
	if not _dog_recovery_clear(restored):
		restored = Transform3D(Basis.IDENTITY, DOG_SPAWN)
	dog.global_transform = restored
	dog.velocity = Vector3.ZERO
	dog.reset_physics_interpolation()
	was_on_floor = false
	zoomies_left = 0.0
	cam_target.global_position = dog.global_position + Vector3(0, 1.05, 0)
	_update_camera(1.0, true)
	_show_feedback("回到安全位置，馆藏损失保留")
	_log("dog recovered to %s; damage=%d" % [str(dog.global_position), damage])

func _dog_recovery_clear(at: Transform3D) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.27
	shape.height = 0.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = at.translated_local(Vector3(0, 0.35, 0))
	query.collision_mask = 1 | 2 | 4
	query.exclude = [dog.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _show_feedback(message: String) -> void:
	feedback_text = message
	feedback_left = 2.0

func _handle_zoomies(delta: float) -> void:
	zoomies_cool = maxf(0.0, zoomies_cool - delta)
	zoomies_left = maxf(0.0, zoomies_left - delta)
	if Input.is_action_just_pressed("dog_zoomies") and zoomies_cool <= 0.0:
		zoomies_left = ZOOMIES_TIME
		zoomies_cool = ZOOMIES_TIME + ZOOMIES_COOLDOWN
		cam.fov = 78.0
		_play_sfx("whoosh", dog.global_position, 2.0, 1.35)
	if zoomies_left <= 0.0 and cam.fov > 66.0:
		cam.fov = move_toward(cam.fov, 66.0, delta * 40.0)

func _handle_bark(delta: float) -> void:
	bark_cool = maxf(0.0, bark_cool - delta)
	if not Input.is_action_just_pressed("dog_bark") or bark_cool > 0.0:
		return
	bark_cool = 1.4
	var heard := 0
	for v in visitors:
		var root: Node3D = v["root"]
		if root.global_position.distance_to(dog.global_position) < 9.0:
			heard += 1
			v["look"] = 2.0
	_play_sfx("bark", dog.global_position, 3.0, randf_range(0.9, 1.12))
	if heard > 0:
		heat = minf(100.0, heat + 4.0 * float(heard))
	_log("bark heard=%d heat=%.1f" % [heard, heat])

func _handle_grab(_delta: float) -> void:
	if Input.is_action_just_pressed("dog_grab"):
		if held == null:
			_try_grab()
		else:
			_release(false)
	if Input.is_action_just_pressed("dog_throw"):
		if held != null:
			_release(true)
		elif dog.is_on_floor():
			dog.velocity.y = JUMP_VELOCITY
			_play_sfx("whoosh", dog.global_position, -6.0, 1.45)
	if held != null:
		var target := mouth.global_position
		held.linear_velocity = (target - held.global_position) * 14.0
		held.angular_velocity *= 0.85

func _try_grab() -> void:
	# 狗站立扒台时可够到约 1.6 m，避免「展品都在台面上却咬不到」
	var forward := -dog.global_transform.basis.z
	var chest := dog.global_position + Vector3(0, 0.85, 0) + forward * 0.55
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, chest)
	params.collision_mask = 2
	var hits := get_world_3d().direct_space_state.intersect_shape(params, 16)
	var best: RigidBody3D = null
	var best_score := -999.0
	for hit in hits:
		var node: Node = hit["collider"]
		if node is RigidBody3D and (node as RigidBody3D).is_in_group("props"):
			var target: Node3D = node
			var reach := mouth.global_position.distance_to(target.global_position)
			var facing := forward.dot((target.global_position - chest).normalized())
			var score := facing * 1.4 - reach * 0.5
			if score > best_score:
				best = node as RigidBody3D
				best_score = score
	if best == null:
		_show_feedback("靠近展品，再按 E 咬住")
		return
	# 别隔着墙/展台咬：从胸口到目标做一次射线检验
	var ray := PhysicsRayQueryParameters3D.create(chest, best.global_position, 1)
	ray.exclude = [dog.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		_log("grab blocked by wall: " + str(best.name))
		_show_feedback("被挡住了，换个角度咬")
		return
	# 咬骨头＝直接把这一段拽下来。冻结刚体叼着是不会跟着走的，与其让它"叼了个寂寞"，
	# 不如让它像真拆家一样——嘴一合，骨头就下来了
	if bool(best.get_meta("is_bone", false)):
		var bone_id := str(best.get_meta("bone_id", ""))
		if skel.has(bone_id) and not bool(skel[bone_id]["broken"]):
			_break_bone(bone_id, forward * 2.4 + Vector3(0, 0.5, 0))
			_show_feedback("骨头拽下来了，可以再咬住甩出")
			return
	held = best
	held.set_meta("release_epoch", int(held.get_meta("release_epoch", 0)) + 1)
	held.gravity_scale = 0.0
	held.linear_damp = 6.0
	held.add_collision_exception_with(dog)
	_play_sfx("soft", held.global_position, -2.0, randf_range(1.0, 1.2))
	_log("grab " + str(held.name))

func _release(throw: bool) -> void:
	if held == null:
		return
	var body := held
	var release_epoch := int(body.get_meta("release_epoch", 0))
	body.gravity_scale = float(body.get_meta("spawn_gravity_scale", 1.0))
	body.linear_damp = float(body.get_meta("spawn_linear_damp", 0.0))
	if throw:
		var forward := -dog.global_transform.basis.z
		body.apply_impulse(forward * 10.0 + Vector3(0, 2.6, 0))
		_play_sfx("whoosh", dog.global_position, 1.0, randf_range(0.95, 1.1))
	_log("release throw=" + str(throw))
	held = null
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if is_instance_valid(body) and body != held and int(body.get_meta("release_epoch", 0)) == release_epoch:
			body.remove_collision_exception_with(dog))

# ---------------- props ----------------

func _spawn_props() -> void:
	for index in range(builder.exhibit_spots.size()):
		var spot: Dictionary = builder.exhibit_spots[index]
		var pos: Vector3 = spot["pos"]
		var kind: String = spot["kind"]
		var value: int = spot["value"]
		var color: Color = spot["color"]

		var body := RigidBody3D.new()
		body.name = "Prop_%03d_%s" % [index, kind]
		body.position = pos
		body.mass = 1.2
		body.collision_layer = 2
		body.collision_mask = 1 | 2 | 4
		body.add_to_group("props")
		body.set_meta("value", value)
		body.set_meta("kind", kind)
		body.set_meta("semantic_id", spot["id"])
		body.set_meta("region_id", spot["region"])
		body.set_meta("spawn_y", pos.y)
		body.set_meta("spawn_pos", pos)
		body.set_meta("spawn_transform", body.transform)
		body.set_meta("spawn_gravity_scale", body.gravity_scale)
		body.set_meta("spawn_linear_damp", body.linear_damp)
		body.set_meta("counted", false)

		var mesh := MeshInstance3D.new()
		var shape := CollisionShape3D.new()
		mesh.mesh = PropSpecs.mesh_for(kind)
		shape.shape = PropSpecs.shape_for(kind)

		mesh.material_override = _mat(color)
		body.add_child(mesh)
		body.add_child(shape)
		add_child(body)
		props.append(body)

# ---------------- visitors ----------------

func _spawn_visitors() -> void:
	var casts := [
		{"room": "hall", "name": "网红", "color": Color(0.78, 0.3, 0.35)},
		{"room": "hall", "name": "讲解员", "color": Color(0.24, 0.36, 0.58)},
		{"room": "hall", "name": "老爷爷", "color": Color(0.5, 0.45, 0.4)},
		{"room": "porcelain", "name": "瓷器迷", "color": Color(0.3, 0.5, 0.55)},
		{"room": "porcelain", "name": "情侣", "color": Color(0.72, 0.42, 0.55)},
		{"room": "taxidermy", "name": "猎奇青年", "color": Color(0.35, 0.45, 0.3)},
		{"room": "taxidermy", "name": "背包客", "color": Color(0.45, 0.4, 0.3)},
		{"room": "kids", "name": "小学生甲", "color": Color(0.85, 0.6, 0.25)},
		{"room": "kids", "name": "小学生乙", "color": Color(0.4, 0.6, 0.75)},
		# 保安站岗不巡逻；他是 Gag 2 的包袱——不是对塌了有反应，是对掌声有反应
		{"room": "hall", "name": "保安", "color": Color(0.18, 0.22, 0.28),
			"post": Vector3(-6.2, 0, -3.3), "yaw": -1.5708},
	]
	var counter := 0
	for cast in casts:
		var route: Array = builder.visitor_routes[cast["room"]]
		var start: Vector3 = cast["post"] if cast.has("post") else route[counter % route.size()]
		var root := Node3D.new()
		root.name = "Visitor_" + str(cast["name"])
		root.position = start
		root.rotation.y = float(cast.get("yaw", 0.0))
		add_child(root)

		var cloth := _mat(cast["color"])
		var skin := _mat(Color(0.94, 0.8, 0.68))
		var pants := _mat(cast["color"].darkened(0.35))
		var shoe := _mat(Color(0.2, 0.2, 0.22))

		# ---- 3 段 ragdoll：腿 / 躯干 / 头，各自是刚体，用 PinJoint 串起来 ----
		var legs := _make_part(root, Vector3(0, 0.40, 0), 3.2)
		_add_capsule_shape(legs, 0.13, 0.78, Vector3.ZERO)
		for sx in [-0.1, 0.1]:
			_mesh_box(legs, Vector3(0.14, 0.72, 0.17), Vector3(sx, 0.03, 0), pants)
			_mesh_box(legs, Vector3(0.17, 0.09, 0.26), Vector3(sx, -0.35, -0.03), shoe)
		_mesh_box(legs, Vector3(0.38, 0.14, 0.28), Vector3(0, 0.32, 0), _mat(cast["color"].darkened(0.5)))

		var torso := _make_part(root, Vector3(0, 1.10, 0), 9.0)
		_add_capsule_shape(torso, 0.24, 0.62, Vector3.ZERO)
		_mesh_box(torso, Vector3(0.42, 0.64, 0.26), Vector3(0, 0.0, 0), cloth)
		for sx in [-0.26, 0.26]:
			_mesh_box(torso, Vector3(0.11, 0.56, 0.13), Vector3(sx, 0.02, 0), cloth)
			_mesh_box(torso, Vector3(0.11, 0.1, 0.13), Vector3(sx, -0.28, 0), skin)
		_mesh_box(torso, Vector3(0.44, 0.1, 0.28), Vector3(0, -0.32, 0), pants)

		var head := _make_part(root, Vector3(0, 1.56, 0), 1.4)
		_add_sphere_shape(head, 0.16, Vector3.ZERO)
		var head_mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.155
		sphere.height = 0.31
		head_mesh.mesh = sphere
		head_mesh.material_override = skin
		head.add_child(head_mesh)
		_mesh_box(head, Vector3(0.16, 0.08, 0.06), Vector3(0, -0.04, -0.15), _mat(Color(0.85, 0.55, 0.45)))
		_mesh_box(head, Vector3(0.3, 0.07, 0.3), Vector3(0, 0.11, 0.02), _mat(cast["color"].darkened(0.5)))
		# 保安给一顶宽檐帽：站岗的人一眼要认出来，否则"保安慢半拍"这拍没人看得懂
		if cast.has("post"):
			_mesh_box(head, Vector3(0.44, 0.04, 0.44), Vector3(0, 0.09, 0.02), _mat(Color(0.1, 0.11, 0.14)))
			_mesh_box(head, Vector3(0.34, 0.12, 0.2), Vector3(0, 0.17, -0.02), _mat(Color(0.14, 0.16, 0.2)))

		# 自我碰撞关掉，否则三段一解冻就会互相弹开
		_no_collide(legs, torso)
		_no_collide(torso, head)
		_no_collide(legs, head)
		_pin(root, legs, torso, Vector3(0, 0.79, 0), 0.75)
		_pin(root, torso, head, Vector3(0, 1.40, 0), 0.55)
		var joints: Array[Dictionary] = []
		for child in root.get_children():
			if child is Joint3D:
				var joint := child as Joint3D
				joints.append({"node": joint, "rest": joint.transform,
					"a": joint.get_node_a(), "b": joint.get_node_b()})
		var initial_wait := randf() * 2.0

		visitors.append({
			"root": root, "torso": torso, "parts": [legs, torso, head],
			"rest": [legs.transform, torso.transform, head.transform],
			"joints": joints, "down_left": 0.0, "immune_left": 0.0,
			"name": cast["name"], "room": cast["room"], "post": cast.has("post"),
			"route": route, "index": counter % route.size(), "wait": initial_wait,
			"spawn_index": counter % route.size(), "spawn_wait": initial_wait,
			"down": false, "spawn": start, "look": 0.0, "yaw0": root.rotation.y
		})
		counter += 1

func _make_part(parent: Node3D, pos: Vector3, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	body.mass = mass
	body.angular_damp = 2.2
	body.linear_damp = 0.25
	body.collision_layer = 4
	body.collision_mask = 1 | 2
	body.position = pos
	parent.add_child(body)
	return body

func _add_capsule_shape(body: RigidBody3D, radius: float, height: float, offset: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.05)
	cs.shape = shape
	cs.position = offset
	body.add_child(cs)

func _add_sphere_shape(body: RigidBody3D, radius: float, offset: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	cs.shape = shape
	cs.position = offset
	body.add_child(cs)

func _no_collide(a: RigidBody3D, b: RigidBody3D) -> void:
	a.add_collision_exception_with(b)
	b.add_collision_exception_with(a)

func _pin(parent: Node3D, a: Node3D, b: Node3D, at: Vector3, swing: float = 0.9) -> void:
	# PinJoint 不限角度，腿会折进胸腔；ConeTwist 给一个锥形活动范围，剪影更像人
	var joint := ConeTwistJoint3D.new()
	joint.position = at
	parent.add_child(joint)
	joint.set_node_a(joint.get_path_to(a))
	joint.set_node_b(joint.get_path_to(b))
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, swing)
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, swing * 0.8)
	joint.set_param(ConeTwistJoint3D.PARAM_BIAS, 0.3)

func _update_visitors(delta: float) -> void:
	for v in visitors:
		v["immune_left"] = maxf(0.0, float(v.get("immune_left", 0.0)) - delta)
		if v["down"]:
			v["down_left"] = maxf(0.0, float(v.get("down_left", VISITOR_RECOVERY_TIME)) - delta)
			if float(v["down_left"]) <= 0.0:
				if _visitor_recovery_clear(v):
					_restore_visitor(v, VISITOR_RECOVERY_IMMUNITY)
				else:
					v["down_left"] = 0.5
			continue
		var root: Node3D = v["root"]
		var torso: RigidBody3D = v["torso"]
		if not torso.freeze:
			continue
		# 警报/塌方期间全场停步：Gag 1 转身对着狗，Gag 2 后退对着骨架
		if gag_phase != 0 or gag2_phase != 0:
			_visitor_react(v, root, delta)
			continue
		if float(v["look"]) > 0.0:
			v["look"] = float(v["look"]) - delta
			var to_dog := dog.global_position - root.global_position
			to_dog.y = 0
			if to_dog.length() > 0.05:
				root.rotation.y = lerp_angle(root.rotation.y, atan2(-to_dog.x, -to_dog.z), clampf(delta * 6.0, 0.0, 1.0))
			continue

		# 站岗的（保安）不巡逻，只守着位置
		if bool(v.get("post", false)):
			continue

		var route: Array = v["route"]
		var target: Vector3 = route[int(v["index"])]
		var to := target - root.global_position
		to.y = 0.0
		if to.length() < 0.35:
			v["wait"] = float(v["wait"]) - delta
			if float(v["wait"]) <= 0.0:
				v["index"] = (int(v["index"]) + 1) % route.size()
				v["wait"] = 1.6 + randf() * 2.2
		else:
			var dir := to.normalized()
			root.global_position += dir * 0.85 * delta
			root.rotation.y = lerp_angle(root.rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 5.0, 0.0, 1.0))

func _visitor_recovery_clear(v: Dictionary) -> bool:
	var root_at := Transform3D(Basis(Vector3.UP, float(v.get("yaw0", 0.0))), v["spawn"])
	var excluded: Array[RID] = []
	for part in v["parts"]:
		excluded.append((part as RigidBody3D).get_rid())
	for i in range(v["parts"].size()):
		var body: RigidBody3D = v["parts"][i]
		for shape_node in body.get_children():
			if not shape_node is CollisionShape3D:
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape_node.shape
			query.transform = root_at * v["rest"][i] * shape_node.transform
			# Authored standing capsules slightly meet the floor; only dynamic
			# occupants can newly obstruct this known-safe authored position.
			query.collision_mask = 2 | 4 | 8
			query.exclude = excluded
			if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				return false
	return true

func _restore_visitor(v: Dictionary, immunity: float = 0.0) -> void:
	var root: Node3D = v["root"]
	var parts: Array = v["parts"]
	var rests: Array = v["rest"]
	# 先固定整个布娃娃并解除关节，再恢复作者定义的局部姿态，最后重建关节锚点。
	# 不用落地后的世界坐标当下一次初始姿态，反复撞倒不会积累漂移。
	for part in parts:
		(part as RigidBody3D).freeze = true
	for entry in v["joints"]:
		var joint: Joint3D = entry["node"]
		joint.set_node_a(NodePath())
		joint.set_node_b(NodePath())
	root.global_position = v["spawn"]
	root.rotation = Vector3(0.0, float(v.get("yaw0", 0.0)), 0.0)
	for i in range(parts.size()):
		var body: RigidBody3D = parts[i]
		body.transform = rests[i]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.reset_physics_interpolation()
	for entry in v["joints"]:
		var joint: Joint3D = entry["node"]
		joint.transform = entry["rest"]
		joint.set_node_a(entry["a"])
		joint.set_node_b(entry["b"])
	v["down"] = false
	v["down_left"] = 0.0
	v["immune_left"] = immunity
	v["index"] = v["spawn_index"]
	v["wait"] = v["spawn_wait"]
	v["look"] = 0.0
	v["bob"] = 0.0
	v["recoil"] = 0.0
	v["part_prev"] = 0.0
	v["part_sfx_t"] = -9.0

func _update_gag(delta: float) -> void:
	gag_cool = maxf(0.0, gag_cool - delta)
	if gag_phase == 0:
		# 两个 Gag 不叠加：塌方的余韵还在，就别再拉警报
		if gag_cool <= 0.0 and heat >= GAG_HEAT_TRIGGER and gag2_phase == 0 \
				and pending_breaks.is_empty() and not (_skeleton_down() and not gag2_done):
			_gag_enter(1)
		return
	gag_t += delta
	_update_gag_ui()
	var dur: float = float(GAG_DUR[["", "alarm", "stare", "clap"][gag_phase]])
	if gag_t < dur:
		return
	match gag_phase:
		1:
			_gag_enter(2)
		2:
			_gag_enter(3)
		_:
			_gag_enter(0)

func _gag_enter(phase: int) -> void:
	gag_phase = phase
	gag_t = 0.0
	match phase:
		1:
			_play_sfx_flat("alarm", 2.0, 1.0)
			_log("gag alarm (heat=%.0f)" % heat)
		2:
			# 全场安静下来这一拍是笑点的支点，不要在这里塞音效
			_log("gag stare standing=%d" % _up_count())
		3:
			gag_count += 1
			_play_sfx_flat("applause", 1.0, 1.0)
			heat = minf(100.0, heat + 18.0)
			_log("gag clap +18 heat -> %.0f" % heat)
		_:
			gag_cool = GAG_COOL
			for v in visitors:
				var root: Node3D = v["root"]
				if is_instance_valid(root):
					root.position.y = 0.0
			_log("gag end")
	_update_gag_ui()

func _up_count() -> int:
	var total := 0
	for v in visitors:
		if not v["down"]:
			total += 1
	return total

func _gag_lines() -> Array:
	var up := _up_count()
	var down := visitors.size() - up
	match gag_phase:
		1:
			return ["⚠ 全馆警报 ⚠", "「有人碰了展品！」"]
		2:
			if down == 0:
				return ["%d 位游客同时停住，一起看向你。" % up, ""]
			return ["%d 位游客同时停住，一起看向你。" % up, "还有 %d 位躺在地上看着天花板。" % down]
		3:
			if down == 0:
				return ["……然后他们鼓起了掌。", "围观热度 +18%"]
			return ["……站着的 %d 位鼓起了掌。" % up, "躺着的 %d 位鼓不了，但也在拍地板。 · 围观热度 +18%%" % down]
	return ["", ""]

func _visitor_react(v: Dictionary, root: Node3D, delta: float) -> void:
	if gag2_phase != 0:
		_visitor_react_bones(v, root, delta)
		return
	var to_dog := dog.global_position - root.global_position
	to_dog.y = 0.0
	if to_dog.length() > 0.05:
		root.rotation.y = lerp_angle(root.rotation.y, atan2(-to_dog.x, -to_dog.z), clampf(delta * 7.0, 0.0, 1.0))
	if gag_phase != 3:
		return
	# 鼓掌＝整人上下颠。灰盒阶段没有手臂骨骼，这就是最省事又读得懂的「欢呼」剪影
	v["bob"] = float(v.get("bob", 0.0)) + delta * 9.0
	root.position.y = absf(sin(float(v["bob"]))) * 0.12

# ---------------- Gag 2：塌方之后的四拍 ----------------

func _update_gag2(delta: float) -> void:
	if gag2_phase == 0:
		if not gag2_done and gag_phase == 0 and _skeleton_down():
			_gag2_enter(1)
		return
	gag2_t += delta
	_update_gag_ui()
	var dur: float = float(GAG2_DUR[["", "hush", "silence", "kid", "guard"][gag2_phase]])
	if gag2_t < dur:
		return
	match gag2_phase:
		1:
			_gag2_enter(2)
		2:
			_gag2_enter(3)
		3:
			_gag2_enter(4)
		_:
			_gag2_enter(0)

## 玩家可以直接咬断脊柱，因此必须逐段确认完整骨架都已断开。
func _skeleton_down() -> bool:
	return skel.size() == 12 and _broken_count() == skel.size()

func _skel_center() -> Vector3:
	if skel.has("pelvis"):
		return skel["pelvis"]["body"].get_meta("spawn_pos", Vector3.ZERO)
	return Vector3.ZERO

func _gag2_enter(phase: int) -> void:
	gag2_phase = phase
	gag2_t = 0.0
	match phase:
		1:
			gag2_done = true
			# 一声闷响压住场面：碎骨头的木头声已经有了，这里要的是"沉重"
			_play_sfx_flat("thud", 4.0, 0.62)
			for v in visitors:
				v["recoil"] = 1.15
			_log("gag2 hush")
		2:
			# 第二拍必须是静音，全场只剩呼吸声才成立
			_log("gag2 silence")
		3:
			# 小孩：又快又薄的掌声（accelerando 一点，显得急）
			if _visitor_available("小学生甲"):
				_play_sfx_flat("applause", -6.0, 1.55)
			_log("gag2 kid clap")
		4:
			# 保安：慢半拍、更厚。他不是对骨头有反应，是对掌声有反应
			if _visitor_available("保安"):
				_play_sfx_flat("applause", 0.0, 0.86)
			heat = minf(100.0, heat + 25.0)
			gag_count += 1
			_log("gag2 guard clap +25 heat -> %.0f" % heat)
		_:
			for v in visitors:
				var root: Node3D = v["root"]
				if is_instance_valid(root):
					root.position.y = 0.0
					v["recoil"] = 0.0
			_log("gag2 end")
	_update_gag_ui()

func _gag2_lines() -> Array:
	match gag2_phase:
		1:
			return ["整具骨架塌了。", "站着的游客一起后退了一步。" if _up_count() > 0 else "观众还没爬起来，骨架也倒了。"]
		2:
			return ["……没有人出声。", ""]
		3:
			if _visitor_available("小学生甲"):
				return ["角落里，一个小学生先鼓了掌。", ""]
			return ["小学生还趴在地上。", "这一拍，没人敢先鼓掌。"]
		4:
			if _visitor_available("保安"):
				if _visitor_available("小学生甲"):
					return ["保安这才反应过来。", "他不是对骨头有反应，是对掌声有反应。 · 围观热度 +25%"]
				return ["保安试探着鼓了掌。", "总得有人先开始。 · 围观热度 +25%"]
			return ["保安还没爬起来。", "这场事故已经够精彩了。 · 围观热度 +25%"]
	return ["", ""]

func _visitor_available(visitor_name: String) -> bool:
	for v in visitors:
		if str(v["name"]) == visitor_name:
			return not bool(v["down"])
	return false

## Gag 2 的游客反应：看的是骨架而不是狗 —— 这一层差别就是笑点
func _visitor_react_bones(v: Dictionary, root: Node3D, delta: float) -> void:
	var center := _skel_center()
	var to := center - root.global_position
	to.y = 0.0
	if to.length() > 0.05:
		root.rotation.y = lerp_angle(root.rotation.y, atan2(-to.x, -to.z), clampf(delta * 8.0, 0.0, 1.0))
	if gag2_phase == 1:
		var away := root.global_position - center
		away.y = 0.0
		var left := float(v.get("recoil", 0.0))
		if away.length() > 0.2 and left > 0.0:
			var step := minf(delta * 2.4, left)
			root.global_position += away.normalized() * step
			v["recoil"] = left - step
		return
	var who := str(v["name"])
	var clapping := gag2_phase == 4 and (who == "小学生甲" or who == "保安")
	if gag2_phase == 3 and who == "小学生甲":
		clapping = true
	if not clapping:
		return
	v["bob"] = float(v.get("bob", 0.0)) + delta * 9.0
	root.position.y = absf(sin(float(v["bob"]))) * 0.12

func _knock(v: Dictionary, impulse: Vector3) -> void:
	if v["down"] or float(v.get("immune_left", 0.0)) > 0.0:
		return
	v["down"] = true
	v["down_left"] = VISITOR_RECOVERY_TIME
	var torso: RigidBody3D = v["torso"]
	var parts: Array = v["parts"]
	for part in parts:
		(part as RigidBody3D).freeze = false
	# 直接给速度而不是冲量：三段质量差 6 倍，用冲量会散得不像一个人
	torso.linear_velocity = impulse * 0.85 + Vector3(0, 2.6, 0)
	torso.angular_velocity = Vector3(randf_range(-5, 5), randf_range(-3, 3), randf_range(-5, 5))
	for part in parts:
		var body: RigidBody3D = part
		if body == torso:
			continue
		body.linear_velocity = torso.linear_velocity * randf_range(0.65, 1.15)
		body.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-7, 7), randf_range(-10, 10))
	heat = minf(100.0, heat + 7.0)
	_play_sfx("thud", torso.global_position, 1.0, randf_range(0.88, 1.08))
	_log("visitor knocked: " + str(v["name"]))

func _check_visitor_hits() -> void:
	var dog_speed := Vector2(dog.velocity.x, dog.velocity.z).length()
	for v in visitors:
		if v["down"]:
			continue
		var root: Node3D = v["root"]
		if dog_speed > 3.0 and dog.global_position.distance_to(root.global_position) < 1.25:
			var push := Vector3(dog.velocity.x, 0.5, dog.velocity.z).normalized() * (dog_speed * 0.55)
			_knock(v, push)
			continue
		for prop in props:
			if prop.linear_velocity.length() > 3.0 and prop.global_position.distance_to(root.global_position) < 1.0:
				_knock(v, prop.linear_velocity.normalized() * 2.4)
				break


## 只用于取证截图：把狗周围的展品朝里掀一遍，制造一个真实的破坏现场
func _simulate_rampage() -> void:
	var center := dog.global_position
	var hit := _rampage_at(center)
	if hit == 0:
		# 狗出生在中庭空地，周围没有展品：自动挪到展品最密的位置再掀
		center = _densest_prop_spot()
		dog.global_position = Vector3(center.x, 0.55, center.z)
		hit = _rampage_at(center)
	_log("rampage props=%d at %s" % [hit, str(center.snapped(Vector3(0.1, 0.1, 0.1)))])

func _rampage_at(center: Vector3) -> int:
	var hit := 0
	for prop in props:
		var d := prop.global_position.distance_to(center)
		if d > 4.6 or d < 0.2:
			continue
		# 朝狗所在的位置掀，碎片会落在走道里，截图才看得出「一片狼藉」
		var push := center - prop.global_position
		push.y = 0.0
		push = push.normalized() if push.length() > 0.05 else Vector3.ZERO
		prop.apply_impulse(push * 3.2 + Vector3(0, 2.6, 0))
		prop.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		hit += 1
	return hit

## 在 3 m 邻域里数邻居，取最密的那一片展区（149 件展品，两两比一次也就 2 万次）
func _densest_prop_spot() -> Vector3:
	var best := Vector3.ZERO
	var best_n := -1
	for a in props:
		var n := 0
		for b in props:
			if a.global_position.distance_squared_to(b.global_position) < 9.0:
				n += 1
		if n > best_n:
			best_n = n
			best = a.global_position
	return best

# ---------------- scoring ----------------

# ---------------- skeleton support graph ----------------

## 骨架段登记进 props，同时建一张 id → 段 的表，供支撑图坍塌用
func _register_skeleton() -> void:
	for entry in builder.skel_bones:
		var body: RigidBody3D = entry["body"]
		body.set_meta("is_bone", true)
		body.set_meta("spawn_gravity_scale", body.gravity_scale)
		body.set_meta("spawn_linear_damp", body.linear_damp)
		body.add_to_group("props")
		props.append(body)
		skel[entry["id"]] = entry
	# 相邻骨段互相重叠（脊柱插在骨盆和胸廓里），解冻瞬间会被穿透解算弹飞，
	# 直接两两免碰撞：塌下来时骨头穿插一点没人看得出来，炸开就很难看
	var bodies: Array = []
	for id in skel:
		bodies.append(skel[id]["body"])
	for i in range(bodies.size()):
		for j in range(i + 1, bodies.size()):
			_no_collide(bodies[i], bodies[j])

func _break_bone(id: String, impulse: Vector3) -> void:
	if not skel.has(id):
		return
	var entry: Dictionary = skel[id]
	if entry["broken"]:
		return
	entry["broken"] = true
	var body: RigidBody3D = entry["body"]
	body.freeze = false
	body.linear_velocity = impulse + Vector3(randf_range(-0.6, 0.6), 0.4, randf_range(-0.6, 0.6))
	body.angular_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(-2.0, 2.0), randf_range(-2.5, 2.5))
	damage += int(body.get_meta("value", 1000))
	body.set_meta("counted", true)
	heat = minf(100.0, heat + 5.0)
	_play_sfx("wood", body.global_position, 1.0, randf_range(0.8, 1.0))
	_log("bone broken: %s" % id)
	# 支撑图判定：支撑全断的段才跟着掉，而且晚半拍，塌下来才有"连锁"的节奏
	for other_id in skel:
		var other: Dictionary = skel[other_id]
		if other["broken"]:
			continue
		var sup: Array = other["sup"]
		if sup.is_empty() or not sup.has(id):
			continue
		var held := false
		for s in sup:
			if not skel[s]["broken"]:
				held = true
				break
		if held:
			continue
		pending_breaks.append({"id": other_id, "at": game_time + 0.16})

## 排队中的连锁坍塌：到点就断，顺序由支撑图决定
func _update_bones() -> void:
	if not pending_breaks.is_empty():
		var still: Array = []
		for item in pending_breaks:
			if game_time >= float(item["at"]):
				_break_bone(str(item["id"]), Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5)))
			else:
				still.append(item)
		pending_breaks = still
	_update_bone_hits()

func _update_bone_hits() -> void:
	var dog_speed := Vector2(dog.velocity.x, dog.velocity.z).length()
	if dog_speed < 3.2:
		return
	for id in skel:
		if skel[id]["broken"]:
			continue
		var body: RigidBody3D = skel[id]["body"]
		if dog.global_position.distance_to(body.global_position) > float(body.get_meta("reach", 1.0)):
			continue
		var push := Vector3(dog.velocity.x, 0.0, dog.velocity.z).normalized() * (dog_speed * 0.35)
		_break_bone(id, push)
		break

func _check_props() -> void:
	for prop in props:
		if prop.get_meta("counted", false):
			continue
		var spawn_y: float = float(prop.get_meta("spawn_y", 0.0))
		# 「从展台/搁板上掉下来了」才算损毁，避免轻微碰擦就计入账本
		if prop.global_position.y < spawn_y - 0.4:
			prop.set_meta("counted", true)
			var value: int = int(prop.get_meta("value", 100))
			damage += value
			if trace:
				_log("counted %s value=%d y=%.2f spawn_y=%.2f" % [str(prop.name), value, prop.global_position.y, spawn_y])
			if _nearest_visitor_distance(prop.global_position) < 9.0:
				heat = minf(100.0, heat + 6.0)

func _nearest_visitor_distance(pos: Vector3) -> float:
	var best := 999.0
	for v in visitors:
		var root: Node3D = v["root"]
		if is_instance_valid(root):
			best = minf(best, root.global_position.distance_to(pos))
	return best

func _decay_heat(delta: float) -> void:
	# 演出期间不衰减：四秒钟的戏不该先把奖励吃掉
	if gag_phase != 0 or gag2_phase != 0:
		return
	heat = maxf(0.0, heat - delta * 1.4)

func _handle_reset() -> void:
	if not Input.is_action_just_pressed("dog_reset"):
		return
	_reset_run()

func _reset_run() -> void:
	if held != null:
		_release(false)
	damage = 0
	heat = 0.0
	game_time = 0.0
	zoomies_left = 0.0
	zoomies_cool = 0.0
	bark_cool = 0.0
	gag_count = 0
	feedback_text = ""
	feedback_left = 0.0
	last_impact_time = -1.0
	sfx_played = 0
	for player in sfx_3d:
		player.stop()
	for player in sfx_2d:
		player.stop()
	yaw = 0.0
	pitch = 0.30
	cam_distance = 4.6
	rmb_down = false
	dog.global_transform = Transform3D(Basis.IDENTITY, DOG_SPAWN)
	dog.velocity = Vector3.ZERO
	dog.reset_physics_interpolation()
	last_safe_dog_transform = dog.global_transform
	was_on_floor = false
	for prop in props:
		prop.set_meta("release_epoch", int(prop.get_meta("release_epoch", 0)) + 1)
		if not bool(prop.get_meta("is_bone", false)):
			prop.transform = prop.get_meta("spawn_transform", prop.transform)
		prop.gravity_scale = float(prop.get_meta("spawn_gravity_scale", 1.0))
		prop.linear_damp = float(prop.get_meta("spawn_linear_damp", 0.0))
		prop.linear_velocity = Vector3.ZERO
		prop.angular_velocity = Vector3.ZERO
		prop.sleeping = false
		prop.remove_collision_exception_with(dog)
		prop.set_meta("counted", false)
		prop.set_meta("prev_speed", 0.0)
		prop.set_meta("sfx_t", -9.0)
		prop.reset_physics_interpolation()
	for v in visitors:
		_restore_visitor(v)
	_reset_skeleton()
	gag_phase = 0
	gag_t = 0.0
	gag_cool = 0.0
	gag2_phase = 0
	gag2_t = 0.0
	gag2_done = false
	cam.fov = 66.0
	cam_target.global_position = dog.global_position + Vector3(0, 1.05, 0)
	_update_camera(1.0, true)
	_update_gag_ui()
	_log("reset")

func _reset_skeleton() -> void:
	pending_breaks.clear()
	for id in skel:
		var entry: Dictionary = skel[id]
		entry["broken"] = false
		var body: RigidBody3D = entry["body"]
		body.freeze = true
		body.gravity_scale = float(body.get_meta("spawn_gravity_scale", 1.0))
		body.linear_damp = float(body.get_meta("spawn_linear_damp", 0.0))
		body.global_position = body.get_meta("spawn_pos", body.global_position)
		body.transform.basis = body.get_meta("spawn_basis", body.transform.basis)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.set_meta("counted", false)

# ---------------- hud ----------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.visible = not nohud
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)

	var left := _panel(ui, Vector2(20, 20), Vector2(252, 86))
	_text(left, Vector2(16, 10), 12, Color(0.38, 0.36, 0.33), "馆藏损失")
	loss_label = _text(left, Vector2(16, 30), 28, Color(0.12, 0.1, 0.08), "¥ 0")

	var right := _panel(ui, Vector2(1280 - 272, 20), Vector2(252, 86))
	_text(right, Vector2(16, 10), 12, Color(0.38, 0.36, 0.33), "围观热度")
	heat_label = _text(right, Vector2(16, 30), 28, Color(0.12, 0.1, 0.08), "0%")
	var track := ColorRect.new()
	track.color = Color(0.84, 0.83, 0.8, 1)
	track.position = Vector2(16, 70)
	track.size = Vector2(220, 6)
	right.add_child(track)
	heat_bar = ColorRect.new()
	heat_bar.color = Color(0.9, 0.42, 0.18, 1)
	heat_bar.position = Vector2(16, 70)
	heat_bar.size = Vector2(0, 6)
	right.add_child(heat_bar)

	var bottom := _panel(ui, Vector2(20, 720 - 54), Vector2(1240, 38))
	_text(bottom, Vector2(16, 10), 13, Color(0.32, 0.3, 0.28),
		"WASD 移动 · 右键拖动转视角 · 滚轮缩放 · E 咬住/松口 · Space 跳/甩 · Shift 疯跑 · F 吠叫 · R 重置")

	state_label = Label.new()
	state_label.position = Vector2(20, 720 - 82)
	state_label.add_theme_font_size_override("font_size", 13)
	if ui_font != null:
		state_label.add_theme_font_override("font", ui_font)
	state_label.add_theme_color_override("font_color", Color(0.98, 0.97, 0.94))
	state_label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1, 0.85))
	state_label.add_theme_constant_override("outline_size", 5)
	ui.add_child(state_label)
	_build_gag_ui(ui)
	_update_hud()

func _build_gag_ui(ui: Control) -> void:
	gag_tint = ColorRect.new()
	gag_tint.color = Color(0.86, 0.14, 0.1, 0.0)
	gag_tint.position = Vector2.ZERO
	gag_tint.size = Vector2(1280, 720)
	gag_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(gag_tint)

	# 字幕底衬：白字压在白色骨架/墙上会糊掉，垫一条半透明深色带
	gag_band = ColorRect.new()
	gag_band.color = Color(0.06, 0.06, 0.07, 0.0)
	gag_band.position = Vector2(0, 84)
	gag_band.size = Vector2(1280, 96)
	gag_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(gag_band)

	gag_title = Label.new()
	gag_title.position = Vector2(0, 96)
	gag_title.size = Vector2(1280, 48)
	gag_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gag_title.add_theme_font_size_override("font_size", 34)
	if ui_font != null:
		gag_title.add_theme_font_override("font", ui_font)
	gag_title.add_theme_color_override("font_color", Color(0.99, 0.98, 0.95))
	gag_title.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.09, 0.9))
	gag_title.add_theme_constant_override("outline_size", 10)
	ui.add_child(gag_title)

	gag_sub = Label.new()
	gag_sub.position = Vector2(0, 138)
	gag_sub.size = Vector2(1280, 30)
	gag_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gag_sub.add_theme_font_size_override("font_size", 17)
	if ui_font != null:
		gag_sub.add_theme_font_override("font", ui_font)
	gag_sub.add_theme_color_override("font_color", Color(0.97, 0.94, 0.88))
	gag_sub.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.09, 0.9))
	gag_sub.add_theme_constant_override("outline_size", 7)
	ui.add_child(gag_sub)
	_update_gag_ui()

func _update_gag_ui() -> void:
	if gag_title == null:
		return
	if gag_phase == 0 and gag2_phase == 0:
		gag_title.text = ""
		gag_sub.text = ""
		gag_tint.color.a = 0.0
		gag_band.color.a = 0.0
		return
	var lines: Array = _gag2_lines() if gag2_phase != 0 else _gag_lines()
	var dur: float = (float(GAG2_DUR[["", "hush", "silence", "kid", "guard"][gag2_phase]])
		if gag2_phase != 0 else float(GAG_DUR[["", "alarm", "stare", "clap"][gag_phase]]))
	var t: float = gag2_t if gag2_phase != 0 else gag_t
	# 进场 0.12 s 淡入、退场 0.3 s 淡出，字幕不要硬切
	var alpha := clampf(t / 0.12, 0.0, 1.0) * clampf((dur - t) / 0.3, 0.0, 1.0)
	gag_title.text = str(lines[0])
	gag_sub.text = str(lines[1])
	gag_title.modulate.a = alpha
	gag_sub.modulate.a = alpha
	gag_band.color.a = alpha * 0.5
	# 只有 Gag 1 的警报阶段泛红；塌方那一下不闪红，靠声音和后退说话
	if gag_phase == 1 and gag2_phase == 0:
		gag_tint.color.a = (0.06 + 0.07 * absf(sin(t * 16.0))) * alpha
	else:
		gag_tint.color.a = 0.0

func _panel(parent: Control, pos: Vector2, size: Vector2) -> Control:
	var panel := ColorRect.new()
	panel.color = Color(0.99, 0.98, 0.96, 0.92)
	panel.position = pos
	panel.size = size
	parent.add_child(panel)
	return panel

func _text(parent: Control, pos: Vector2, font_size: int, color: Color, content: String) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = content
	label.add_theme_font_size_override("font_size", font_size)
	if ui_font != null:
		label.add_theme_font_override("font", ui_font)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _update_hud() -> void:
	if loss_label == null:
		return
	loss_label.text = "¥ " + _thousands(damage)
	heat_label.text = "%d%%" % int(round(heat))
	heat_bar.size.x = 220.0 * clampf(heat / 100.0, 0.0, 1.0)
	state_label.text = "状态：%s%s" % [
		"疯跑中" if zoomies_left > 0.0 else ("疯跑冷却 %.1fs" % zoomies_cool if zoomies_cool > 1.5 else "就绪"),
		("   |   咬住：" + str(held.name)) if held != null else ""
	]
	if feedback_left > 0.0:
		state_label.text += "   |   " + feedback_text

# ---------------- utilities ----------------

func _thousands(value: int) -> String:
	var text := str(value)
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out

func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

func _load_ui_font() -> Font:
	var candidates := PackedStringArray(["Noto Sans CJK SC", "Microsoft YaHei", "Arial Unicode MS", "Arial", "DejaVu Sans"])
	var available := OS.get_system_fonts()
	for family in candidates:
		if family in available:
			var font := SystemFont.new()
			font.font_names = PackedStringArray([family])
			return font
	return ThemeDB.fallback_font

func _log(line: String) -> void:
	print("[museum-dog] ", line)

func _run_selftest() -> void:
	selftest_frame += 1
	var f := selftest_frame
	if f == 1:
		Input.action_press("dog_forward")
	if f == 40:
		Input.action_release("dog_forward")
		# 传送到瓷器馆的展台前，正对三个花瓶
		dog.global_position = Vector3(-16.2, 0.5, -2.45)
		dog.velocity = Vector3.ZERO
		dog.rotation.y = PI
	if f == 46:
		Input.action_press("dog_grab")
	if f == 49:
		Input.action_release("dog_grab")
	if f == 54:
		dog.rotation.y = 0.0
	if f == 62:
		Input.action_press("dog_throw")
	if f == 65:
		Input.action_release("dog_throw")
	if f == 150:
		_log("[selftest] damage=%d heat=%.1f held=%s visitors_down=%d" % [damage, heat, str(held), _down_count()])
		get_tree().quit(0)

func _run_knocktest() -> void:
	knock_frame += 1
	var f := knock_frame
	if f == 1:
		# 直接调 _knock：_move_dog 每帧会把 velocity 重置，喂速度是喂不进去的
		var target: Dictionary = visitors[2]
		var root: Node3D = target["root"]
		# 站到游客侧前方，斜着看，被撞的人往画面里飞
		dog.global_position = root.global_position + Vector3(1.6, 0.1, 1.4)
		dog.rotation.y = 0.852
		# 证据图用固定机位单独框住被撞的人，不跟着狗走
		shot = "knockcam"
		cam_follow = false
		shot_pos = root.global_position + Vector3(-2.35, 2.5, 2.9)
		shot_look = root.global_position + Vector3(0.35, 1.05, -0.9)
		shot_fov = 54.0
		cam_target.global_position = dog.global_position + Vector3(0, 1.05, 0)
		_update_camera(1.0, true)
		_log("knocktest setup at %s" % str(root.global_position))
	if f == 2:
		_knock(visitors[2], Vector3(-1.2, 0, -4.4))
	if f >= 2 and f <= 120 and f % 12 == 0:
		var v: Dictionary = visitors[2]
		var torso: RigidBody3D = v["torso"]
		var head: RigidBody3D = v["parts"][2]
		var legs: RigidBody3D = v["parts"][0]
		_log("f=%3d down=%s torso=%s v=%.1f pp=%.2f pst=%.2f head_d=%.2f legs_d=%.2f"
			% [f, str(v["down"]), str(torso.global_position.snapped(Vector3(0.01, 0.01, 0.01))),
				torso.linear_velocity.length(),
				float(v.get("part_prev", -1.0)), float(v.get("part_sfx_t", -1.0)),
				head.global_position.distance_to(torso.global_position),
				legs.global_position.distance_to(torso.global_position)])
	if f == 60:
		_log("knocktest sfx=%d" % sfx_played)
	if f == 130:
		get_tree().quit(0)

func _down_count() -> int:
	var total := 0
	for v in visitors:
		if v["down"]:
			total += 1
	return total

func _process(_delta: float) -> void:
	frames += 1
	if not shots_dir.is_empty():
		_run_shot_sequence()
		return
	if capture_path.is_empty():
		return
	var capture_frame := 100 if selftest else (110 if chaos else (150 if gagtest else (28 if knocktest else (125 if bonetest else (242 if gag2test else 50)))))
	# --fixed-fps 下一渲染帧会跑多个物理步，测试模式的帧号是物理帧，必须跟着物理时钟走
	var tick := Engine.get_physics_frames() if (selftest or chaos or gagtest or knocktest or bonetest or gag2test) else frames
	if tick >= capture_frame and not captured:
		captured = true
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(capture_path)
		_log("capture %s -> %s" % [capture_path, str(error)])
		get_tree().quit(0)

func _run_shot_sequence() -> void:
	if shot_busy or shot_index >= shot_queue.size():
		return
	shot_warmup += 1
	# 切机位后等几帧，让阴影和材质缓存稳定下来再截
	if shot_warmup < 5:
		return
	shot_busy = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var key: String = shot_queue[shot_index]
	var path := shots_dir.path_join("%02d_%s.png" % [shot_index, key])
	var error := image.save_png(path)
	_log("shot %s -> %s" % [path, str(error)])
	shot_index += 1
	shot_busy = false
	if shot_index >= shot_queue.size():
		get_tree().quit(0)
		return
	_load_shot(shot_queue[shot_index])
