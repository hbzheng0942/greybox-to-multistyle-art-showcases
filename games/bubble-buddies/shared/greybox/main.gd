extends Node3D

const Model = preload("res://shared/engine/salon_model.gd")
const V = preload("res://shared/greybox/salon_visuals.gd")
const Audio = preload("res://shared/engine/salon_audio.gd")
const CareStrip = preload("res://shared/engine/care_strip.gd")
const Motion = preload("res://shared/engine/movement_profile.gd")
const COLORS := [Color("f7b85f"), Color("77cce3")]
const REACH := 1.85
const TURN_SPEED := 30.0 # Radians/sec; a full reversal settles in about 105 ms.
const STEP_DISTANCE := 1.05
var model = Model.new()
var players: Array[CharacterBody3D] = []
var camera: Camera3D
var station_positions: Dictionary = {
	"intake0": Vector3(-4.6, 0, -3.3), "intake1": Vector3(-3.0, 0, -3.3),
	"intake2": Vector3(-1.4, 0, -3.3), "wash0": Vector3(-4.7, 0, -0.4),
	"wash1": Vector3(-4.7, 0, 2.2), "dryer": Vector3(5.0, 0, -1.6),
	"bench0": Vector3(0, 0, -0.55), "bench1": Vector3(0, 0, 1.25),
	"brush": Vector3(5.0, 0, 0.5), "laundry": Vector3(-2.35, 0, 3.25),
	"exit": Vector3(5.0, 0, 2.5), "rack": Vector3(5.0, 0, -3.7),
	"treatment": Vector3(-5.6, 0, -1.8),
	"intake_dry": Vector3(1.35, 0, -3.5), "paws": Vector3(2.85, 0, -3.5),
	"buffer_wet": Vector3(-4.8, 0, 4.1), "buffer_dry": Vector3(5.7, 0, 4.1)
}
const STATION_NAMES := {"intake0":"接待 1", "intake1":"接待 2", "intake2":"接待 3", "wash0":"洗 / 冲 A", "wash1":"洗 / 冲 B", "dryer":"自动吹干", "bench0":"交接窗 A", "bench1":"交接窗 B", "brush":"修毛美容", "laundry":"洗烘毛巾", "exit":"交还", "rack":"毛巾架", "treatment":"除虫泡泡罩", "intake_dry":"干宠接待", "paws":"爪爪护理", "buffer_wet":"暂存 1只", "buffer_dry":"暂存 1只"}
var station_bodies: Dictionary = {}
var station_labels: Dictionary = {}
var station_frames: Dictionary = {}
var pet_views: Dictionary = {}
var towel_views: Dictionary = {}
var loose_positions: Dictionary = {}
var loose_routes: Dictionary = {}
var shake_warned: Dictionary = {}
var player_rooms: Array[int] = [-1, 1]
var facings: Array[Vector3] = [Vector3.FORWARD, Vector3.FORWARD]
var targets: Array[String] = ["", ""]
var interact_targets: Array[String] = ["", ""]
var work_targets: Array[String] = ["", ""]
var input_telemetry: Array[Dictionary] = []
var movement_inputs: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var movement_active: Array[bool] = [false, false]
var stride_distance: Array[float] = [0.0, 0.0]
var footstep_distance: Array[float] = [0.0, 0.0]
var gait_amount: Array[float] = [0.0, 0.0]
var work_inputs: Array[bool] = [false, false]
var work_productive: Array[bool] = [false, false]
var work_blocked_until_release: Array[bool] = [false, false]
var last_work_targets: Array[String] = ["", ""]
var shift_seed := 20261018
var paused := false
var game_started := false
var duo_mode := true
var active_player := 0
var animation_time := 0.0
var puddles: Array[Dictionary] = []
var bursts: Array[Dictionary] = []
var shake_anim: Dictionary = {}
var hud: CanvasLayer
var score_label: Label
var timer_label: Label
var seed_label: Label
var orders_label: Label
var order_row: HBoxContainer
var order_cards: Dictionary = {}
var resource_label: Label
var pending_label: Label
var next_orders_label: Label
var treatment_view: Node3D
var care_working: Array[bool] = [false, false]
var recent_departures: Array[String] = []
var reunion_pets: Array[Dictionary] = []
var waiting_owner: Node3D
var help_labels: Array[Label] = []
var warning_rings: Dictionary = {}
var session_events: Array[Dictionary] = []
var context_panels: Array[PanelContainer] = []
var context_labels: Array[Label] = []
var context_progress: Array[ProgressBar] = []
var local_feedback := ["", ""]
var local_feedback_until := [0.0, 0.0]
var hint_label: Label
var toast_label: Label
var toast_time := 0.0
var menu_panel: PanelContainer
var menu_title: Label
var menu_body: Label
var solo_button: Button
var duo_button: Button
var resume_button: Button
var salon_audio: Node
var audio_muted := false
var last_clock_tick := -1

func _ready() -> void:
	# Select a reproducible shift before the menu; never change a running clock.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shift-seed="):
			var value := argument.get_slice("=", 1)
			if value.is_valid_int() and int(value) >= 0 and int(value) < 100000000:
				shift_seed = int(value)
	_register_input()
	_build_room()
	_build_ui()
	_build_audio()
	model.reset(true, shift_seed)
	model.running = false
	model.drain_events()
	_render_pets(0.0)
	_update_hud()
	_show_menu()

func _register_input() -> void:
	var mapping := {
		"p1_left": KEY_A, "p1_right": KEY_D, "p1_up": KEY_W, "p1_down": KEY_S,
		"p2_left": KEY_LEFT, "p2_right": KEY_RIGHT, "p2_up": KEY_UP, "p2_down": KEY_DOWN,
		"p1_work": KEY_F, "p2_work": KEY_L
	}
	for action in mapping:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = mapping[action]
		InputMap.action_add_event(action, event)

func _build_room() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("172b36")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d3e2ef")
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, -28, 0)
	sun.light_energy = 0.32
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-45, 145, 0)
	fill.light_energy = 0.07
	add_child(fill)
	camera = Camera3D.new()
	camera.name = "SharedCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15.2
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(1.1, 17, 12.5)
	add_child(camera)
	camera.look_at(Vector3(1.1, 0, -0.4))
	camera.current = true
	_static_box("Floor", Vector3(0, -0.20, 0), Vector3(13.3, 0.40, 9.9), Color("c4cace"))
	for x in range(-6, 7):
		V.box(self, "GridX", Vector3(x, 0.007, 0), Vector3(0.018, 0.01, 9.6), Color("b5bfc5"))
	for z in range(-4, 5):
		V.box(self, "GridZ", Vector3(0, 0.009, z), Vector3(13, 0.01, 0.018), Color("b5bfc5"))
	_static_box("BackWall", Vector3(0, 1.3, -4.95), Vector3(13.6, 2.6, 0.3), Color("e0e1dc"))
	_static_box("LeftWall", Vector3(-6.65, 0.35, 0), Vector3(0.3, 0.7, 10.0), Color("c5d2d7"))
	var right_wall := _static_box("RightWall", Vector3(6.65, 0.35, 0), Vector3(0.3, 0.7, 10.0), Color("c5d2d7"))
	right_wall.get_node("Visual").hide()
	V.box(self, "RightWallBack", Vector3(6.65, 0.35, -1.8), Vector3(0.3, 0.7, 6.4), Color("c5d2d7"))
	V.box(self, "RightWallFront", Vector3(6.65, 0.35, 4.2), Vector3(0.3, 0.7, 1.6), Color("c5d2d7"))
	# The low pet gate keeps players inside; delivered pets use a presentation-only exit.
	V.box(self, "PetGate", Vector3(6.65, 0.22, 2.4), Vector3(0.16, 0.44, 2.0), Color("9bb3a8"))
	for z in [1.4, 3.4]:
		V.box(self, "PetDoorPost", Vector3(6.65, 0.6, z), Vector3(0.22, 1.2, 0.22), Color("e2dfcf"))
	_static_box("FrontWall", Vector3(0, 0.15, 4.95), Vector3(13.6, 0.3, 0.3), Color("afbdc6"))
	V.box(self, "WetZone", Vector3(-3.2, 0.012, 0), Vector3(6.3, 0.01, 9.6), Color("b5d4da"))
	V.box(self, "DryZone", Vector3(3.2, 0.013, 0), Vector3(6.3, 0.01, 9.6), Color("e0d9bc"))
	V.label(self, "洗护室", Vector3(-2.9, 0.05, -2.1), Color("447787"), 23)
	V.label(self, "整理室", Vector3(2.5, 0.05, -4.4), Color("947657"), 23)
	_build_partition()
	_build_pickup_court()
	for key in station_positions:
		var p: Vector3 = station_positions[key]
		var color := Color("e1d4ab")
		var size := Vector3(1.45, 0.64, 1.45)
		if key.begins_with("wash"):
			color = Color("83c5d5")
		elif key == "dryer":
			color = Color("e5a38c")
			size = Vector3(1.8, 0.64, 1.65)
		elif key.begins_with("bench"):
			color = Color("e0d1a0")
			size = Vector3(1.25, 0.64, 1.55)
		elif key == "brush":
			color = Color("b7acd7")
		elif key == "paws":
			color = Color("ddafbf")
			size = Vector3(1.15, 0.64, 1.15)
		elif key.begins_with("buffer"):
			color = Color("aac4b7")
			size = Vector3(0.9, 0.64, 0.9)
		elif key == "rack":
			size = Vector3(1.0, 0.64, 1.0)
		elif key == "treatment":
			color = Color("a9c99c")
			size = Vector3(1.15, 0.64, 1.15)
		elif key == "laundry":
			color = Color("96beb2")
		elif key == "exit":
			color = Color("9acaa3")
		elif key.begins_with("intake"):
			color = Color("b3bfc7")
			if key == "intake_dry":
				size = Vector3(1.15, 0.64, 1.15)
		var station := _static_box(key, p + Vector3(0, 0.32, 0), size, color.darkened(0.12))
		station_bodies[key] = station
		V.box(self, key + "Top", p + Vector3(0, 0.67, 0), Vector3(size.x + 0.06, 0.10, size.z + 0.06), color)
		if key.begins_with("wash"):
			V.box(self, "Water", p + Vector3(0, 0.73, 0), Vector3(1.1, 0.04, 1.05), Color("c3e8ef"))
			V.box(self, "TapStem", p + Vector3(-0.48, 1.0, -0.48), Vector3(0.09, 0.58, 0.09), Color("e1e6e8"))
			V.box(self, "Tap", p + Vector3(-0.30, 1.27, -0.48), Vector3(0.42, 0.09, 0.09), Color("e1e6e8"))
		if key == "dryer":
			V.box(self, "DryerBack", p + Vector3(0, 1.12, -0.67), Vector3(1.7, 0.8, 0.22), color)
			for i in range(5):
				V.box(self, "Vent", p + Vector3(-0.48 + i * 0.24, 1.1, -0.54), Vector3(0.08, 0.32, 0.03), Color("815f54"))
		if key == "brush":
			V.box(self, "BrushHandle", p + Vector3(0.4, 0.82, 0.1), Vector3(0.12, 0.12, 0.6), Color("75587d"))
			for tooth in range(5):
				V.box(self, "CombTooth", p + Vector3(0.22, 0.85, -0.1 + tooth * 0.1), Vector3(0.3, 0.12, 0.04), Color("eee2f6"))
			# A crossed pair of blades distinguishes the grooming station by shape.
			for side in [-1, 1]:
				var blade := V.box(self, "ScissorBlade", p + Vector3(-0.35, 0.82, 0), Vector3(0.07, 0.05, 0.60), Color("eee7f4"))
				blade.rotation.y = side * 0.4
		if key == "treatment":
			treatment_view = V.treatment_station(self, p)
		if key == "paws":
			V.paw_station(self, p)
		if key.begins_with("buffer"):
			V.box(self, "RestMat", p + Vector3(0, 0.745, 0), Vector3(0.72, 0.04, 0.72), Color("d5e2c9"))
			for side in [-1, 1]:
				V.box(self, "RestRail", p + Vector3(side * 0.40, 0.85, 0), Vector3(0.06, 0.17, 0.85), color)
		if key == "intake_dry":
			V.label(self, "干宠入口", p + Vector3(0, 1.9, -0.48), Color("eee5bc"), 24)
		if key == "laundry":
			V.ball(self, "LaundryDoor", p + Vector3(0, 0.47, 0.75), Vector3(0.36, 0.3, 0.03), Color("d2e6ea"))
		if key == "rack":
			V.box(self, "TowelRail", p + Vector3(0, 1.05, -0.42), Vector3(0.9, 0.08, 0.08), Color("b5c7bc"))
		var frame := Node3D.new()
		frame.name = key + "Highlight"
		add_child(frame)
		frame.position = p
		for side in [-1, 1]:
			V.box(frame, "Edge", Vector3(side * (size.x / 2 + 0.055), 0.76, 0), Vector3(0.07, 0.05, size.z + 0.16), Color("fff2ba"))
			V.box(frame, "Edge", Vector3(0, 0.76, side * (size.z / 2 + 0.055)), Vector3(size.x + 0.16, 0.05, 0.07), Color("fff2ba"))
		frame.visible = false
		station_frames[key] = frame
		var label_pos := p + Vector3(0, 0.28, 0.94)
		var label_text: String = STATION_NAMES[key]
		if key.begins_with("bench"):
			label_pos = p + Vector3(0, 2.2, 0)
			label_text = "窗 A" if key == "bench0" else "窗 B"
		station_labels[key] = V.label(self, label_text, label_pos, color.lightened(0.65), 38 if key.begins_with("bench") else 25)
		_build_access_marker(key)
	for i in range(2):
		var body := V.player(self, i, COLORS[i])
		players.append(body)
	players[0].position = get_station_access("wash0")
	players[1].position = get_station_access("brush")

func _build_access_marker(slot: String) -> void:
	# Floor marks show a reachable standing point; they never add collision.
	var points: Array[Vector3] = [get_station_access(slot)]
	if slot.begins_with("bench"):
		points = [station_positions[slot] + Vector3(-1.18, 0.02, 0), station_positions[slot] + Vector3(1.18, 0.02, 0)]
	var marker_color := Color("eaf0e4")
	if slot.begins_with("bench"):
		marker_color = Color("68c7c4") if slot == "bench0" else Color("cf9de3")
	for point in points:
		for side in [-1, 1]:
			V.box(self, "AccessMark", point + Vector3(side * 0.32, 0.015, 0), Vector3(0.045, 0.012, 0.48), marker_color)
			V.box(self, "AccessMark", point + Vector3(0, 0.015, side * 0.24), Vector3(0.68, 0.012, 0.045), marker_color)

func _build_partition() -> void:
	# Two rooms share a full-height wall: counter windows pass pets, an open door passes staff.
	var spans := [Vector2(-4.8, -1.325), Vector2(0.225, 0.475), Vector2(2.025, 2.4)]
	for i in range(spans.size()):
		var span: Vector2 = spans[i]
		var center := Vector3(0, 1.3, (span.x + span.y) * 0.5)
		var wall := _static_box("SplashDivider%d" % i, center, Vector3(0.24, 2.6, span.y - span.x), Color("c6d0c8"))
		wall.collision_layer = 5
		V.box(self, "DividerCap", center + Vector3(0, 1.34, 0), Vector3(0.32, 0.09, span.y - span.x + 0.06), Color("e7e1cc"))
	for key in ["bench0", "bench1"]:
		var p: Vector3 = station_positions[key]
		var lintel := _static_box("HandoffWindowLintel", Vector3(0, 2.275, p.z), Vector3(0.24, 0.65, 1.55), Color("c6d0c8"))
		lintel.collision_layer = 5
		V.cutaway(lintel.get_node("Visual"))
		V.cutaway(V.box(self, "WindowFrameTop", Vector3(0, 1.96, p.z), Vector3(0.34, 0.10, 1.55), Color("e9dfc2")), 0.30)
		for side in [-1, 1]:
			V.box(self, "WindowFrameSide", Vector3(0, 1.34, p.z + side * 0.735), Vector3(0.34, 1.24, 0.08), Color("e9dfc2"))
	var doorway := _static_box("StaffDoorLintel", Vector3(0, 2.4, 3.6), Vector3(0.26, 0.4, 2.4), Color("c6d0c8"))
	doorway.collision_layer = 5
	# Keep the open doorway flush with the divider. Swinging leaves previously
	# protruded into the dry-side exit-to-window lane and trapped an axis turn.
	for z in [2.45, 4.75]:
		var jamb := _static_box("StaffDoorJamb", Vector3(0, 1.0, z), Vector3(0.30, 2.0, 0.12), Color("adbbb0"))
		jamb.collision_layer = 5
	V.box(self, "StaffDoorThreshold", Vector3(0, 0.03, 3.55), Vector3(0.7, 0.035, 2.3), Color("c1c4b6"))
	V.label(self, "↔ 换区门", Vector3(0.55, 0.08, 4.15), Color("5c716a"), 20)

func _build_pickup_court() -> void:
	V.box(self, "PickupCourt", Vector3(8.0, -0.17, 0), Vector3(2.4, 0.32, 9.8), Color("bdc2b6"))
	V.box(self, "OutsideCurb", Vector3(9.25, 0.08, 0), Vector3(0.18, 0.18, 9.8), Color("84958e"))
	V.box(self, "WaitingBench", Vector3(8.15, 0.35, -0.45), Vector3(1.45, 0.16, 0.75), Color("9dafa4"))
	V.box(self, "WaitingBenchBack", Vector3(8.15, 0.65, -0.77), Vector3(1.45, 0.62, 0.13), Color("9dafa4"))
	V.label(self, "主人等候", Vector3(8.0, 0.1, -1.65), Color("64796c"), 23)
	V.label(self, "接宠回家", Vector3(7.8, 0.08, 3.55), Color("627a69"), 20)
	waiting_owner = Node3D.new()
	waiting_owner.name = "WaitingOwner"
	add_child(waiting_owner)
	waiting_owner.position = Vector3(8.2, 0, 1.35)
	V.cylinder(waiting_owner, "Coat", Vector3(0, 0.61, 0), 0.22, 0.65, Color("a0aaa2"))
	V.ball(waiting_owner, "Head", Vector3(0, 1.14, 0), Vector3.ONE * 0.23, Color("d5c4ad"))
	for side in [-1, 1]:
		V.box(waiting_owner, "Leg", Vector3(side * 0.12, 0.16, 0), Vector3(0.13, 0.32, 0.17), Color("7d8a85"))
		V.ball(waiting_owner, "Hand", Vector3(side * 0.29, 0.72, -0.06), Vector3(0.09, 0.18, 0.1), Color("d5c4ad"))

func _show_reunion(id: int, pet_name: String, quality: Dictionary = {}) -> void:
	var pet := V.pet(self, id)
	pet.name = "ReunionPet%d" % id
	pet.position = station_positions.exit + Vector3(0, 0.77, 0)
	pet.get_node("Visual/Dirt").hide()
	V.apply_pet_cosmetics(pet.get_node("Visual"), quality)
	pet.get_node("Status").position.y = 1.60 if quality.get("frizzy", false) or quality.get("crooked", false) else 1.32
	pet.get_node("Status").text = "%s %s" % [pet_name, "新发型回家啦" if quality.get("frizzy", false) or quality.get("crooked", false) else "回家啦"]
	pet.get_node("Visual").rotation.y = -PI / 2.0
	reunion_pets.append({"node":pet, "age":0.0, "start":pet.position, "quality":quality.duplicate(true)})

func _update_reunions(delta: float) -> void:
	for i in range(reunion_pets.size() - 1, -1, -1):
		reunion_pets[i].age += delta
		var item: Dictionary = reunion_pets[i]
		var age: float = item.age
		var pet: Node3D = item.node
		V.apply_pet_cosmetics(pet.get_node("Visual"), item.quality, animation_time)
		if age > 6.0:
			pet.queue_free()
			reunion_pets.remove_at(i)
			continue
		var destination := Vector3(7.9, 0, 2.4)
		pet.position = (item.start as Vector3).lerp(destination, minf(age / 2.2, 1.0))
		pet.get_node("Visual").position.y = absf(sin(age * 14)) * (0.1 if age < 2.2 else 0.04)
		pet.get_node("Visual/Tail").rotation.z = sin(age * 18) * 0.5
		if age > 4.0:
			pet.position.z += (age - 4.0) * 1.0
			pet.get_node("Visual").rotation.y = PI
	if is_instance_valid(waiting_owner):
		waiting_owner.rotation.z = sin(animation_time * 8) * 0.06 if not reunion_pets.is_empty() else 0.0

func _static_box(title: String, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = title
	add_child(body)
	body.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	V.box(body, "Visual", Vector3.ZERO, size, color)
	return body

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	if game_started and model.running:
		var pid := -1
		if key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_F, KEY_Q]:
			pid = 0 if duo_mode else active_player
		elif duo_mode and key in [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT, KEY_K, KEY_L, KEY_O]:
			pid = 1
		if pid != -1:
			_record_input({"type":"key", "player_id":pid, "key":OS.get_keycode_string(key), "pressed":event.pressed, "paused":paused})
	if not event.pressed:
		if key == KEY_F:
			# In solo mode a held key may have spanned a Tab switch. Close both
			# players on the real hardware release; changing targets never does this.
			for pid in range(2) if not duo_mode else [0]:
				_release_player_work(pid, "key_release")
				work_blocked_until_release[pid] = false
		elif key == KEY_L and duo_mode:
			_release_player_work(1, "key_release")
			work_blocked_until_release[1] = false
		return
	if key == KEY_M:
		audio_muted = not audio_muted
		salon_audio.set_muted(audio_muted)
		_toast("全部声音已静音" if audio_muted else "声音已开启", 1.5)
	elif key == KEY_B:
		salon_audio.set_music_muted(not salon_audio.music_muted)
		_toast("背景音乐已关闭 · 音效保留" if salon_audio.music_muted else "背景音乐已开启", 1.5)
	elif key == KEY_1 and (not game_started or model.ended):
		start_shift(false)
	elif key in [KEY_SPACE, KEY_2] and (not game_started or model.ended):
		start_shift(true)
	elif key == KEY_ESCAPE and game_started and not model.ended:
		paused = not paused
		if paused:
			_close_input_intervals("pause")
			salon_audio.set_activity(false, false, 0, true)
			_show_pause()
		else:
			menu_panel.hide()
	elif key == KEY_R and model.ended:
		start_shift(duo_mode)
	elif key == KEY_N and (not game_started or model.ended):
		shift_seed = posmod(shift_seed + 1, 100000000)
		start_shift(duo_mode)
	elif key == KEY_TAB and not duo_mode and game_started and model.running and not paused:
		_release_player_work(active_player, "solo_switch")
		active_player = 1 - active_player
		work_blocked_until_release[active_player] = Input.is_action_pressed("p1_work")
		_toast("正在控制 P%d" % (active_player + 1), 1.5)
	elif game_started and model.running and not paused:
		if key == KEY_E:
			_try_interact(0 if duo_mode else active_player)
		elif key == KEY_K and duo_mode:
			_try_interact(1)
		elif key == KEY_Q:
			_call_help(0 if duo_mode else active_player)
		elif key == KEY_O and duo_mode:
			_call_help(1)

func start_shift(duo: bool = true, seed_value: int = -1) -> void:
	_close_input_intervals("restart")
	if seed_value >= 0:
		shift_seed = seed_value
	duo_mode = duo
	active_player = 0
	paused = false
	game_started = true
	model.reset(duo, shift_seed)
	salon_audio.reset()
	salon_audio.set_activity(false, false, 0, false)
	last_clock_tick = -1
	loose_positions.clear()
	loose_routes.clear()
	shake_warned.clear()
	player_rooms = [-1, 1]
	for view in pet_views.values():
		view.queue_free()
	pet_views.clear()
	for ring in warning_rings.values():
		ring.queue_free()
	warning_rings.clear()
	session_events.clear()
	input_telemetry.clear()
	movement_inputs = [Vector2.ZERO, Vector2.ZERO]
	movement_active = [false, false]
	stride_distance = [0.0, 0.0]
	footstep_distance = [0.0, 0.0]
	gait_amount = [0.0, 0.0]
	work_inputs = [false, false]
	work_productive = [false, false]
	last_work_targets = ["", ""]
	work_blocked_until_release = [Input.is_action_pressed("p1_work"), Input.is_action_pressed("p2_work") if duo_mode else Input.is_action_pressed("p1_work")]
	_record_input({"type":"shift_start", "seed":shift_seed, "duo":duo_mode,
		"movement_profile":Motion.snapshot()})
	recent_departures.clear()
	for reunion in reunion_pets:
		reunion.node.queue_free()
	reunion_pets.clear()
	for puddle in puddles:
		puddle.node.queue_free()
	puddles.clear()
	for burst in bursts:
		burst.node.queue_free()
	bursts.clear()
	shake_anim.clear()
	facings = [Vector3.LEFT, Vector3.RIGHT]
	targets = ["", ""]
	interact_targets = ["", ""]
	work_targets = ["", ""]
	care_working = [false, false]
	players[0].position = get_station_access("wash0")
	players[1].position = get_station_access("brush")
	for player in players:
		player.velocity = Vector3.ZERO
		player.get_node("Visual").rotation = Vector3.ZERO
	menu_panel.hide()
	_toast("开店！吹干可按护理强风加速，完成请松手；炸毛 / 歪刘海可补救或低分交付", 5.0)
	_render_pets(0.0)
	_update_hud()

func _physics_process(delta: float) -> void:
	if not game_started or paused or not model.running:
		return
	var washing := false
	care_working = [false, false]
	for i in range(2):
		var direction := Vector2.ZERO
		if duo_mode:
			var prefix := "p%d_" % (i + 1)
			direction = Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")
		elif i == active_player:
			direction = Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
		var speed: float = Motion.EMPTY_SPEED if model.carried[i] == -1 else Motion.CARRY_SPEED
		var on_puddle := false
		for puddle in puddles:
			if _flat_distance(players[i].position, puddle.node.position) < 1.05:
				speed *= Motion.PUDDLE_MULTIPLIER
				on_puddle = true
				break
		var world_direction := input_to_world(direction)
		players[i].velocity.x = world_direction.x * speed
		players[i].velocity.z = world_direction.z * speed
		players[i].velocity.y = -1.0 if players[i].is_on_floor() else players[i].velocity.y - 20.0 * delta
		var before := players[i].position
		players[i].move_and_slide()
		var travel := _flat_distance(before, players[i].position)
		stride_distance[i] += travel
		footstep_distance[i] += travel
		gait_amount[i] = move_toward(gait_amount[i], clampf(travel / maxf(delta * speed, 0.001), 0.0, 1.0), delta * 18.0)
		if footstep_distance[i] >= STEP_DISTANCE:
			footstep_distance[i] = fmod(footstep_distance[i], STEP_DISTANCE)
			salon_audio.play_event("step_wet" if on_puddle else "step_dry", clampf(players[i].position.x / 6.0, -0.8, 0.8), int(stride_distance[i] / STEP_DISTANCE) + i)
		var moving := Vector2(players[i].get_real_velocity().x, players[i].get_real_velocity().z).length() > 0.05
		if not direction.is_equal_approx(movement_inputs[i]) or moving != movement_active[i]:
			_record_input({"type":"movement", "player_id":i, "direction":[direction.x, direction.y], "moving":moving, "position":[players[i].position.x, players[i].position.z]})
			movement_inputs[i] = direction
			movement_active[i] = moving
		var room := -1 if players[i].position.x < -0.9 else (1 if players[i].position.x > 1.4 else 0)
		if room != 0 and room != player_rooms[i]:
			session_events.append({"type":"room_crossed", "player_id":i, "elapsed":model.elapsed, "room":room})
			player_rooms[i] = room
		if direction.length() > 0.05:
			facings[i] = world_direction.normalized()
		var pivot: Node3D = players[i].get_node("Visual")
		pivot.rotation.y = rotate_toward(pivot.rotation.y, atan2(-facings[i].x, -facings[i].z), delta * TURN_SPEED)
		var raw_working := Input.is_action_pressed("p%d_work" % (i + 1)) if duo_mode else (i == active_player and Input.is_action_pressed("p1_work"))
		if not raw_working:
			# Covers action-based diagnostic input as well as OS key-up events.
			work_blocked_until_release[i] = false
			if work_inputs[i]:
				_release_player_work(i, "action_release")
		var working: bool = raw_working and not work_blocked_until_release[i]
		interact_targets[i] = _nearest_station(i, "interact")
		work_targets[i] = _nearest_station(i, "work")
		targets[i] = work_targets[i] if working and model.carried[i] == -1 else interact_targets[i]
		care_working[i] = working and model.held_item(i).kind == "none" and model.can_work(i, work_targets[i])
		V.animate_player(players[i], stride_distance[i] / STEP_DISTANCE * PI, gait_amount[i], model.held_item(i).kind != "none", care_working[i], animation_time, duo_mode or i == active_player)
		var work_target := "" if model.carried[i] != -1 else work_targets[i]
		var productive: bool = working and model.can_work(i, work_target)
		if working != work_inputs[i] or productive != work_productive[i] or (working and work_target != last_work_targets[i]):
			_record_input({"type":"work", "player_id":i, "pressed":working, "target":work_target, "productive":productive})
			work_inputs[i] = working
			work_productive[i] = productive
			last_work_targets[i] = work_target
		if working:
			if model.carried[i] != -1:
				model.work(i, "", delta)
			elif targets[i] != "":
				var pet_id: int = model.slots.get(targets[i], -1)
				if targets[i].begins_with("wash") and pet_id != -1 and model.held_towels[i] == -1:
					var pet: Dictionary = model.pets[pet_id]
					washing = washing or (pet.stage == "dirty" and pet.wash_phase != "soak")
				model.work(i, targets[i], delta)
	model.tick(delta)
	_handle_events()
	_update_loose_pets(delta)
	_update_audio(washing)
	if model.ended:
		_show_end()

func input_to_world(direction: Vector2) -> Vector3:
	# The fixed camera keeps its oblique view; keys follow what players see.
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var down := Vector3(-right.z, 0, right.x)
	return right * direction.x + down * direction.y

func world_to_input(offset: Vector3) -> Vector2:
	return Vector2(offset.dot(input_to_world(Vector2.RIGHT)), offset.dot(input_to_world(Vector2.DOWN)))

func _record_input(data: Dictionary) -> void:
	# Edge/transition telemetry only. Never feeds the game or automates navigation.
	if input_telemetry.size() >= 12000:
		return
	data["elapsed"] = model.elapsed
	data["engine_usec"] = Time.get_ticks_usec()
	data["wall_unix_ms"] = roundi(Time.get_unix_time_from_system() * 1000.0)
	input_telemetry.append(data)

func _release_player_work(pid: int, reason: String) -> void:
	model.release_work(pid)
	if work_inputs[pid]:
		_record_input({"type":"work", "player_id":pid, "pressed":false, "productive":false, "target":last_work_targets[pid], "reason":reason})
	work_inputs[pid] = false
	work_productive[pid] = false
	last_work_targets[pid] = ""
	care_working[pid] = false

func _close_input_intervals(reason: String) -> void:
	for pid in range(2):
		if movement_active[pid] or not movement_inputs[pid].is_zero_approx():
			_record_input({"type":"movement", "player_id":pid, "direction":[0, 0], "moving":false, "reason":reason})
		_release_player_work(pid, reason)
		work_blocked_until_release[pid] = Input.is_action_pressed("p%d_work" % (pid + 1)) if duo_mode else Input.is_action_pressed("p1_work")
	movement_inputs = [Vector2.ZERO, Vector2.ZERO]
	movement_active = [false, false]
	work_inputs = [false, false]
	work_productive = [false, false]
	last_work_targets = ["", ""]

func _process(delta: float) -> void:
	if not paused:
		animation_time += delta
		_update_effects(delta)
		_update_reunions(delta)
		_render_pets(delta)
		_render_towels()
		_render_treatment()
	if toast_time > 0:
		toast_time -= delta
		toast_label.visible = toast_time > 0
	_update_hud()

func _try_interact(pid: int) -> void:
	var loose_id := _nearest_loose_pet(pid)
	if loose_id != -1 and model.held_item(pid).kind == "none":
		_record_input({"type":"interact", "player_id":pid, "target":"loose", "pet_id":loose_id, "legal":true})
		_toast(catch_pet_with(pid, loose_id), 2.0)
		return
	var slot := _nearest_station(pid)
	_record_input({"type":"interact", "player_id":pid, "target":slot, "legal":not slot.is_empty() and model.can_interact(pid, slot)})
	if slot == "":
		local_feedback[pid] = "再靠近一点，站到工位标记处"
		local_feedback_until[pid] = animation_time + 1.0
		_toast("靠近工位拿放；靠近跑动的宠物可抱回", 2.0)
		return
	var legal: bool = model.can_interact(pid, slot)
	var message := interact_with(pid, slot)
	if not legal:
		local_feedback[pid] = message
		local_feedback_until[pid] = animation_time + 1.0
	if not message.is_empty():
		_toast(message, 1.8)

func interact_with(pid: int, slot: String) -> String:
	if pid < 0 or pid >= players.size() or not model.running or paused:
		return "现在不能操作"
	if not station_positions.has(slot) or not _can_reach(pid, slot):
		return "离工位太远了"
	var result: String = model.interact(pid, slot)
	_handle_events()
	return result

func _can_reach(pid: int, slot: String) -> bool:
	if _flat_distance(players[pid].global_position, station_positions[slot]) > REACH:
		return false
	var from := players[pid].global_position + Vector3(0, 0.5, 0)
	var to: Vector3 = station_positions[slot] + Vector3(0, 0.5, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [players[0].get_rid(), players[1].get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == station_bodies[slot]

func _can_catch(pid: int, id: int) -> bool:
	if pid < 0 or pid >= players.size() or not model.pets.has(id) or model.pets[id].location != "loose":
		return false
	var position := get_pet_position(id)
	if _flat_distance(players[pid].position, position) > 1.45:
		return false
	var query := PhysicsRayQueryParameters3D.create(players[pid].position + Vector3(0, 0.5, 0), position + Vector3(0, 0.5, 0), 1)
	query.exclude = [players[0].get_rid(), players[1].get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _nearest_loose_pet(pid: int) -> int:
	for id in model.pets:
		if _can_catch(pid, id):
			return id
	return -1

func catch_pet_with(pid: int, id: int) -> String:
	if not model.running or paused or not _can_catch(pid, id):
		return "靠近宠物，别隔着墙或工位抓"
	var result: String = model.catch_pet(pid, id)
	_handle_events()
	return result

func _update_loose_pets(delta: float) -> void:
	# This lane stays clear of baths, intake, laundry and the divider. A short hop
	# gets the pet off its bath; the following patrol never crosses furniture.
	var lane := [Vector3(-3.4, 0, 0.35), Vector3(-1.3, 0, 0.35), Vector3(-1.3, 0, 1.65), Vector3(-3.3, 0, 1.45)]
	for id in loose_positions.keys():
		if not model.pets.has(id) or model.pets[id].location != "loose":
			loose_positions.erase(id)
			loose_routes.erase(id)
			continue
		var route: Dictionary = loose_routes[id]
		var destination: Vector3 = route.landing if route.hop else lane[route.index]
		var p: Vector3 = loose_positions[id]
		p = p.move_toward(destination, delta * (3.4 if route.hop else 1.65))
		loose_positions[id] = p
		if p.distance_to(destination) < 0.03:
			if route.hop:
				route.hop = false
			else:
				route.index = (int(route.index) + 1) % lane.size()

func _render_towels() -> void:
	var laundry_index := 0
	for id in model.towels:
		var towel: Dictionary = model.towels[id]
		if not towel_views.has(id):
			var node := Node3D.new()
			node.name = "PhysicalTowel%d" % id
			add_child(node)
			V.box(node, "Fabric", Vector3.ZERO, Vector3(0.62, 0.12, 0.42), Color("f4ebcd"))
			V.box(node, "Stripe", Vector3(0.14, 0.067, 0), Vector3(0.06, 0.015, 0.43), Color("84afa7"))
			V.label(node, "", Vector3(0, 0.33, 0), Color("edf4e8"), 20).name = "Status"
			towel_views[id] = node
		var node: Node3D = towel_views[id]
		var location: String = towel.location
		node.visible = not location.begins_with("pet:")
		if not node.visible:
			continue
		if location in ["p0", "p1"]:
			var pid := int(location.right(1))
			node.position = players[pid].position + _visual_facing(pid) * 0.55 + Vector3(0, 0.91, 0)
			node.rotation.y = players[pid].get_node("Visual").rotation.y
		elif station_positions.has(location):
			node.position = station_positions[location] + Vector3(0, 0.82, 0)
			if location == "laundry":
				node.position.y += laundry_index * 0.16
				laundry_index += 1
		var wet: bool = towel.state in ["wet", "washing"]
		if node.get_meta("state", "") != towel.state:
			node.get_node("Fabric").material_override = V.material(Color("77afbd") if wet else Color("f4ebcd"))
			node.set_meta("state", towel.state)
		node.get_node("Status").text = model.towel_label(id)
		node.rotation.z = sin(animation_time * 14) * 0.045 if towel.state == "washing" else 0.0

func _update_audio(washing: bool) -> void:
	var drying := false
	var grooming := false
	var toweling := false
	for pid in range(2):
		if not care_working[pid]:
			continue
		var slot: String = work_targets[pid]
		var id: int = model.slots.get(slot, -1)
		if id == -1 or not model.pets.has(id):
			continue
		grooming = grooming or slot in ["brush", "paws"] or (slot.begins_with("bench") and model.pets[id].stage == "dry")
		toweling = toweling or (slot.begins_with("bench") and model.pets[id].stage == "wet")
	var dry_id: int = model.slots.get("dryer", -1)
	if dry_id != -1:
		drying = model.pets[dry_id].stage == "wet"
	var urgency := 0
	for id in model.pets:
		var pet: Dictionary = model.pets[id]
		var warning: bool = pet.stage == "wet" and pet.location != "dryer" and not pet.towel_active and pet.shake <= 4
		if warning and not shake_warned.get(id, false):
			salon_audio.play_event("shake_warning", clampf(get_pet_position(id).x / 6.0, -0.8, 0.8))
			shake_warned[id] = true
		elif not warning:
			shake_warned.erase(id)
		if warning or pet.get("escape_warning", false) or _cosmetic_stop_required(pet):
			urgency = 1
	var pressure := maxf(clampf((model.pets.size() - 2.0) / 4.0, 0.0, 1.0), 1.0 if model.remaining <= 30.0 else 0.0)
	salon_audio.set_activity(washing, drying, urgency, paused or not model.running, grooming, toweling, pressure)
	var seconds := int(ceil(model.remaining))
	if seconds <= 10 and seconds > 0 and seconds != last_clock_tick:
		salon_audio.play_event("tick")
	last_clock_tick = seconds

func _visual_facing(pid: int) -> Vector3:
	return -players[pid].get_node("Visual").basis.z

func _render_treatment() -> void:
	if not is_instance_valid(treatment_view):
		return
	var id: int = model.slots.get("treatment", -1)
	var phase := ""
	if id != -1:
		phase = model.pets[id].get("treatment_phase", "")
	treatment_view.get_node("Bubbles").visible = phase == "treating"
	treatment_view.get_node("ReadyMarker").visible = phase == "ready"
	for bubble: Node3D in treatment_view.get_node("Bubbles").get_children():
		var rest: Vector3 = bubble.get_meta("rest_position", bubble.position)
		bubble.position = rest + Vector3(0, sin(animation_time * 4 + bubble.get_index()) * 0.07, 0)

func _nearest_station(pid: int, action: String = "interact") -> String:
	var best := ""
	var best_distance := 100.0
	var usable := ""
	var usable_distance := 100.0
	var previous := work_targets[pid] if action == "work" else interact_targets[pid]
	var previous_distance := 100.0
	var previous_usable := false
	var previous_reachable := false
	for key in station_positions:
		if not _can_reach(pid, key):
			continue
		var offset: Vector3 = station_positions[key] - players[pid].position
		offset.y = 0
		var face := get_station_access(key)
		if key.begins_with("bench"):
			face = station_positions[key] + Vector3(-1.18 if players[pid].position.x < 0 else 1.18, 0, 0)
		# At the marked operating face, docking is more stable than center distance.
		var score := offset.length() * 0.65 + _flat_distance(players[pid].position, face) * 0.35 + (1.0 - offset.normalized().dot(facings[pid])) * 0.3
		if score < best_distance:
			best_distance = score
			best = key
		var can_use: bool = model.can_work(pid, key) if action == "work" else model.can_interact(pid, key)
		if key == previous:
			previous_reachable = true
			previous_distance = score
			previous_usable = can_use
		if can_use and score < usable_distance:
			usable_distance = score
			usable = key
	# A small dead band prevents flicker at adjacent windows. Legal targets always
	# beat stale/illegal selections; no reach or line-of-sight exception is added.
	var choice: String = usable if not usable.is_empty() else best
	if previous_reachable and previous_usable and previous_distance <= usable_distance + 0.12:
		choice = previous
	elif previous_reachable and usable.is_empty() and previous_distance <= best_distance + 0.12:
		choice = previous
	if action == "work":
		work_targets[pid] = choice
	else:
		interact_targets[pid] = choice
	return choice

func get_station_access(slot: String) -> Vector3:
	var p: Vector3 = station_positions[slot]
	if slot == "treatment":
		return p + Vector3(1.1, 0.02, 0)
	if slot.begins_with("wash"):
		return p + Vector3(1.18, 0.02, 0)
	if slot == "buffer_wet":
		return p + Vector3(1.1, 0.02, 0)
	if slot == "buffer_dry":
		return p + Vector3(-1.1, 0.02, 0)
	if slot == "rack":
		return p + Vector3(-1.15, 0.02, 0)
	if slot == "dryer" or slot == "exit" or slot == "brush":
		return p + Vector3(-1.30, 0.02, 0)
	if slot.begins_with("bench"):
		return p + Vector3(-1.1 if slot == "bench0" else 1.1, 0.02, 0)
	if slot == "laundry":
		return p + Vector3(0, 0.02, -1.15)
	return p + Vector3(0, 0.02, 1.18)

func _call_help(pid: int) -> void:
	var target := _nearest_station(pid)
	var place: String = STATION_NAMES.get(target, "我这边")
	_toast("P%d：%s 帮一下！" % [pid + 1, place], 3.0)
	session_events.append({"type":"help", "player":pid, "target":target, "elapsed":model.elapsed})
	salon_audio.play_event("help", -0.55 if pid == 0 else 0.55)

func get_pet_position(id: int) -> Vector3:
	if not model.pets.has(id):
		return Vector3.ZERO
	var pet: Dictionary = model.pets[id]
	var location: String = pet.location
	if location == "loose":
		return loose_positions.get(id, Vector3(-2, 0, 0))
	if location == "p0" or location == "p1":
		var pid := int(location.right(1))
		return players[pid].position + facings[pid] * 0.58 + Vector3(0, 0.90, 0)
	if station_positions.has(location):
		return station_positions[location] + Vector3(0, 0.75, 0)
	return Vector3.ZERO

func _handle_events() -> void:
	for event in model.drain_events():
		var recorded: Dictionary = event.duplicate(true)
		recorded["elapsed"] = model.elapsed
		if event.get("type") in ["decision", "escaped", "caught", "towel_pickup", "towel_placed"]:
			recorded["player_positions"] = [[players[0].position.x, players[0].position.z], [players[1].position.x, players[1].position.z]]
		session_events.append(recorded)
		var type: String = event.get("type", "")
		var id: int = event.get("pet_id", -1)
		var pan := clampf(get_pet_position(id).x / 6.0, -0.8, 0.8) if model.pets.has(id) else 0.0
		if type == "decision":
			var action: String = event.get("action", "")
			if action in ["pickup", "place", "choose_dryer"]:
				salon_audio.play_event("pickup" if action == "pickup" else "place", pan, id % 3)
		elif type in ["towel_pickup", "towel_placed", "towel_wrapped"]:
			salon_audio.play_event("towel", -0.55 if event.get("player_id", 0) == 0 else 0.55)
		elif type == "soaking":
			salon_audio.play_event("soak", -0.65)
		elif type == "bath_ready":
			salon_audio.play_event("bath_ready", -0.65)
		elif type == "treatment_started":
			salon_audio.play_event("treatment_start", -0.5)
			_toast("泡泡罩开始护理；先接下一只，稍后转浴池冲净", 2.5)
		elif type == "treatment_ready":
			salon_audio.play_event("treatment_ready", -0.5)
			_toast("%s 除虫护理好了！腾个浴池，只需冲净" % model.pets.get(id, {}).get("name", "宠物"), 3.0)
		elif type == "order_waiting":
			salon_audio.play_event("order_waiting")
		elif type == "escape_warning":
			salon_audio.play_event("escape_warning", pan)
			_toast("%s 扭来扭去：泡好了，回来冲净！" % model.pets.get(id, {}).get("name", "宠物"), 2.0)
		elif type == "escaped":
			var source: Vector3 = station_positions[event.from_slot]
			loose_positions[id] = source + Vector3(0, 0.75, 0)
			loose_routes[id] = {"hop":true, "landing":source + Vector3(1.5, 0, 0), "index":0 if source.z < 0 else 1}
			salon_audio.play_event("escaped", -0.65)
			_toast("%s 溜下来了！空手靠近按拿放抱回，队友顶一下工位！" % model.pets.get(id, {}).get("name", "宠物"), 3.0)
		elif type == "caught":
			salon_audio.play_event("caught", pan)
		if type == "shake" and model.pets.has(id):
			var source := get_pet_position(id)
			var rewetted := 0
			for other_id in model.pets.keys():
				if other_id != id and model.pets[other_id].stage == "dry" and _flat_distance(source, get_pet_position(other_id)) <= 2.5 and _splash_can_reach(source, get_pet_position(other_id)):
					model.rewet(other_id)
					rewetted += 1
			_splash(source)
			shake_anim[id] = 0.7
			_toast("噗噜噜！%s" % ("溅湿了 %d 只，毛巾救一下！" % rewetted if rewetted else "离干宠远一点就能躲过！"), 3.0)
			salon_audio.play_event("shake", pan)
		elif type == "comic_warning":
			_toast("%s：完成啦，快松开护理！再按会%s" % [model.pets.get(id, {}).get("name", "宠物"), "炸毛" if event.get("incident") == "frizzed" else "剪歪刘海"], 2.0)
			salon_audio.play_event("comic_warning", pan)
		elif type in ["frizzed", "crooked"]:
			shake_anim[id] = 0.45
			_toast("噗！%s%s · 递到窗口让队友补梳，或去美容台；也能65%%基础分交还" % [model.pets.get(id, {}).get("name", "宠物"), "变毛球了" if type == "frizzed" else "剪成歪刘海了"], 3.5)
			salon_audio.play_event(type, pan)
		elif type == "cosmetic_repaired":
			_toast("队友救回造型！接着赶下一单" if event.get("teammate_rescue", false) else "梳顺啦！接着赶下一单", 2.4)
			salon_audio.play_event("cosmetic_repaired", pan)
		elif type == "delivered":
			var types: Array = event.get("cosmetic_types", [])
			var quality := {"stage":"dry", "frizzy":"frizzed" in types or "frizzy" in types, "crooked":"crooked" in types}
			_show_reunion(id, event.get("name", "宠物"), quality)
			var imperfect: bool = event.get("cosmetic", false)
			_toast("造型有点歪，护理已完成！基础分65%，赶上下单啦" if imperfect else "干干净净，交还成功！", 2.5)
			salon_audio.play_event("imperfect_delivery" if imperfect else "success", 0.65, model.delivered % 3)
		elif type == "washed":
			_toast("洗好了，过窗交给队友！烘干或拿干毛巾包上擦干", 2.5)
			salon_audio.play_event("washed", pan)
		elif type == "dried" or type == "towel_dried":
			var dry_pet: Dictionary = model.pets.get(id, {})
			var dry_message := "吹干了，请松开护理！" if _cosmetic_stop_required(dry_pet) else "蓬松了！"
			_toast(dry_message + (model.next_step(dry_pet) if not dry_pet.is_empty() else "看订单继续护理"), 2.5)
			salon_audio.play_event("dried", pan)
		elif type == "brushed":
			_toast("造型好了，请松开护理！%s" % model.next_step(model.pets.get(id, {})), 2.0)
			salon_audio.play_event("brushed", pan)
		elif type == "paws_done":
			_toast("爪爪护理好了！%s" % model.next_step(model.pets.get(id, {})), 2.0)
			salon_audio.play_event("brush", pan, 2)
		elif type == "laundry_started":
			_toast("毛巾洗烘中，先照顾宠物吧", 2.0)
			salon_audio.play_event("laundry_start", -0.55)
		elif type == "laundry_ready":
			_toast("干毛巾洗好了！到洗烘机拿，再从窗口递过去", 2.0)
			salon_audio.play_event("laundry_ready", -0.55)
		elif type == "missed":
			var pet_name: String = event.get("name", "宠物")
			recent_departures.append(pet_name)
			if recent_departures.size() > 2:
				recent_departures.pop_front()
			var reason: String = event.get("reason", "patience")
			var cause := "等候队列满了" if reason == "queue_full" else ("等接待超时" if reason == "waiting_timeout" else "护理超时")
			_toast("%s %s，跟主人先回家了" % [pet_name, cause], 3.0)
			salon_audio.play_event("queue_loss" if event.get("waiting", false) else "missed")

func _splash_can_reach(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(Vector3(from.x, 0.85, from.z), Vector3(to.x, 0.85, to.z), 4)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _render_pets(delta: float) -> void:
	for id in pet_views.keys():
		if not model.pets.has(id):
			pet_views[id].queue_free()
			pet_views.erase(id)
			if warning_rings.has(id):
				warning_rings[id].queue_free()
				warning_rings.erase(id)
	for id in model.pets:
		var pet: Dictionary = model.pets[id]
		if not pet_views.has(id):
			pet_views[id] = V.pet(self, id)
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 2.40
			torus.outer_radius = 2.47
			ring.mesh = torus
			var ring_material := StandardMaterial3D.new()
			ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ring_material.albedo_color = Color("e7a453")
			ring.material_override = ring_material
			add_child(ring)
			warning_rings[id] = ring
		var view: Node3D = pet_views[id]
		view.position = get_pet_position(id)
		var pivot: Node3D = view.get_node("Visual")
		pivot.rotation.y = PI
		if pet.location in ["p0", "p1"]:
			var pid := int(pet.location.right(1))
			view.position = players[pid].position + _visual_facing(pid) * 0.58 + Vector3(0, 0.9, 0)
			pivot.rotation.y = players[pid].get_node("Visual").rotation.y + PI
		pivot.position.y = sin(animation_time * 3.0 + id) * 0.025
		pivot.rotation.z = 0.0
		pivot.get_node("Tail").rotation.z = sin(animation_time * 8 + id) * 0.35
		if shake_anim.get(id, 0.0) > 0:
			shake_anim[id] -= delta
			pivot.rotation.z = sin(animation_time * 52) * 0.22
		view.get_node("Visual/Dirt").visible = pet.stage == "dirty"
		view.get_node("Visual/Foam").visible = pet.stage == "dirty" and pet.wash > 0.03
		view.get_node("Visual/Ribbon").visible = pet.get("brushed", false)
		view.get_node("Visual/PawBadge").visible = pet.get("paws_done", false)
		view.get_node("Visual/TowelWrap").visible = pet.get("towel_id", -1) != -1
		view.get_node("Visual/WetDrops").visible = pet.stage == "wet"
		var fleas: Node3D = view.get_node("Visual/Fleas")
		fleas.visible = pet.service == "deflea" and pet.get("treatment_phase", "") != "ready"
		for flea: Node3D in fleas.get_children():
			var rest: Vector3 = flea.get_meta("rest_position", flea.position)
			flea.position = rest + Vector3(0, absf(sin(animation_time * 7 + flea.get_index())) * 0.07, 0)
		var clipping := false
		var paw_care := false
		var repairing := false
		for pid in range(2):
			clipping = clipping or (care_working[pid] and work_targets[pid] == "brush" and pet.location == "brush" and pet.stage == "dry" and pet.needs_brush and not pet.brushed)
			repairing = repairing or (care_working[pid] and work_targets[pid] == pet.location and (pet.location == "brush" or String(pet.location).begins_with("bench")) and pet.stage == "dry" and (pet.get("frizzy", false) or pet.get("crooked", false)))
			paw_care = paw_care or (care_working[pid] and work_targets[pid] == "paws" and pet.location == "paws" and pet.stage == "dry" and pet.get("needs_paws", false) and not pet.get("paws_done", false))
		V.apply_pet_cosmetics(pivot, pet, animation_time, repairing)
		var paw_sparks: Node3D = view.get_node("Visual/PawSparkles")
		paw_sparks.visible = paw_care
		for spark: Node3D in paw_sparks.get_children():
			var rest: Vector3 = spark.get_meta("rest_position", spark.position)
			spark.position = rest + Vector3(0, sin(animation_time * 14 + spark.get_index()) * 0.055, 0)
		var clips: Node3D = view.get_node("Visual/TrimTuft")
		clips.visible = clipping
		for clip: Node3D in clips.get_children():
			var rest: Vector3 = clip.get_meta("rest_position", clip.position)
			clip.position = rest + Vector3(0, sin(animation_time * 12 + clip.get_index()) * 0.08, 0)
		var warning: bool = pet.stage == "wet" and pet.location != "dryer" and not pet.towel_active and pet.shake <= 4.0
		var cosmetic: String = model.cosmetic_status(pet)
		view.get_node("Visual/Alert").visible = warning or pet.get("escape_warning", false) or pet.location == "loose" or _cosmetic_stop_required(pet, cosmetic)
		var ring: MeshInstance3D = warning_rings[id]
		ring.position = Vector3(view.position.x, 0.05, view.position.z)
		ring.scale = Vector3(1, 0.1, 1)
		ring.visible = warning and sin(animation_time * 8) > -0.4
		var state_text := "待洗"
		var color := Color("f0d49d")
		if pet.stage == "dirty":
			state_text = model.wash_status(pet)
			if pet.service == "deflea" and pet.get("treatment_phase", "") != "ready":
				state_text = model.next_step(pet)
				color = Color("c8efab")
			if pet.wash_phase == "soap" and pet.soap > 0:
				state_text = "搓泡泡 %d%%" % int(pet.soap * 100)
			elif pet.wash_phase == "rinse" and pet.rinse > 0:
				state_text = "冲净 %d%%" % int(pet.rinse * 100)
			if pet.get("escape_warning", false):
				color = Color("ffbf6b")
				pivot.rotation.z = sin(animation_time * 18) * 0.12
		elif pet.stage == "wet":
			color = Color("b6efff")
			if pet.get("towel_active", false):
				state_text = "擦干 %d%%" % int(pet.towel_progress * 100)
			elif pet.location == "dryer":
				state_text = "烘干 %d%%" % int(pet.dry * 100)
			else:
				state_text = "%ds 甩水" % int(ceil(pet.shake))
				if pet.shake <= 3.0:
					color = Color("ffbf6b")
					pivot.rotation.z = sin(animation_time * 18) * 0.07
		elif pet.stage == "dry":
			if not model.is_ready(pet):
				state_text = model.next_step(pet)
				if pet.location == "brush" and pet.needs_brush and not pet.brushed and pet.brush > 0:
					state_text = "修毛 %d%%" % int(pet.brush * 100)
				elif pet.location == "paws" and pet.get("needs_paws", false) and not pet.get("paws_done", false) and pet.get("paws", 0.0) > 0:
					state_text = "爪护 %d%%" % int(pet.paws * 100)
				color = Color("dcc6ff")
			else:
				state_text = "可交还"
				color = Color("bbefb9")
		if pet.location == "loose":
			state_text = "溜下来啦！抱我回去"
			color = Color("ffbf6b")
			pivot.position.y = absf(sin(animation_time * 16)) * 0.10
			pivot.rotation.z = sin(animation_time * 8) * 0.10
		if cosmetic != "造型正常" and not cosmetic.is_empty():
			state_text += "\n" + _quality_hint(pet)
			color = Color("ffd19a") if _cosmetic_stop_required(pet, cosmetic) else Color("efc8e5")
		var status: Label3D = view.get_node("Status")
		status.position.y = 1.60 if pet.get("frizzy", false) or pet.get("crooked", false) else 1.32
		# Full route belongs on the order card. Keep world labels to one urgent cue.
		var urgent: bool = pet.location == "loose" or _cosmetic_stop_required(pet, cosmetic) or pet.stage == "wet"
		urgent = urgent or (pet.stage == "dirty" and pet.get("wash_phase", "") == "rinse")
		# A dry-looking pet may still need grooming. Show the remaining dry task
		# or explicit ready cue at the animal, not only in a distant order card.
		urgent = urgent or pet.stage == "dry"
		status.text = "%s · %s" % [pet.name, state_text.split("\n")[0]] if urgent else String(pet.name)
		status.modulate = color

func _splash(pos: Vector3) -> void:
	var patch := V.cylinder(self, "SplashPatch", Vector3(pos.x, 0.025, pos.z), 1.05, 0.025, Color("83bbc9"))
	puddles.append({"node": patch, "time": 7.0})
	if puddles.size() > 5:
		puddles[0].node.queue_free()
		puddles.pop_front()
	for i in range(12):
		var angle := TAU * i / 12.0
		var drop := V.ball(self, "SplashDrop", pos + Vector3(0, 0.5, 0), Vector3.ONE * 0.09, Color("c4eff7"))
		bursts.append({"node": drop, "velocity": Vector3(cos(angle) * 3, 2.5, sin(angle) * 3), "time": 0.65})

func _update_effects(delta: float) -> void:
	for i in range(puddles.size() - 1, -1, -1):
		puddles[i].time -= delta
		if puddles[i].time < 0:
			puddles[i].node.queue_free()
			puddles.remove_at(i)
	for i in range(bursts.size() - 1, -1, -1):
		bursts[i].time -= delta
		bursts[i].velocity.y -= 9 * delta
		bursts[i].node.position += bursts[i].velocity * delta
		if bursts[i].time < 0:
			bursts[i].node.queue_free()
			bursts.remove_at(i)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _build_ui() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var theme := Theme.new()
	theme.default_font = V.ui_font()
	theme.default_font_size = 20
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	hud.add_child(root)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 12
	top.offset_bottom = 130
	top.add_theme_stylebox_override("panel", _panel(Color("203a49"), 9))
	root.add_child(top)
	var rows := VBoxContainer.new()
	top.add_child(rows)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := _ui_label("泡泡搭档", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	score_label = _ui_label("", 20)
	score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(score_label)
	seed_label = _ui_label("", 15)
	header.add_child(seed_label)
	timer_label = _ui_label("", 25)
	header.add_child(timer_label)
	var forecast := HBoxContainer.new()
	rows.add_child(forecast)
	resource_label = _ui_label("", 16)
	resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forecast.add_child(resource_label)
	next_orders_label = _ui_label("", 16)
	forecast.add_child(next_orders_label)
	order_row = HBoxContainer.new()
	order_row.add_theme_constant_override("separation", 8)
	rows.add_child(order_row)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -55
	bottom.offset_bottom = -12
	bottom.add_theme_stylebox_override("panel", _panel(Color("203a49")))
	root.add_child(bottom)
	var bottom_rows := VBoxContainer.new()
	bottom.add_child(bottom_rows)
	pending_label = _ui_label("", 17)
	pending_label.clip_text = true
	bottom_rows.add_child(pending_label)
	hint_label = _ui_label("", 20)
	bottom_rows.add_child(hint_label)
	hint_label.hide()

	toast_label = _ui_label("", 18)
	root.add_child(toast_label)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast_label.offset_left = 40
	toast_label.offset_right = -40
	toast_label.offset_top = -164
	toast_label.offset_bottom = -126
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_color", Color("233f4a"))
	toast_label.add_theme_color_override("font_outline_color", Color("f5f6ed"))
	toast_label.add_theme_constant_override("outline_size", 4)
	for pid in range(2):
		var context := PanelContainer.new()
		context.mouse_filter = Control.MOUSE_FILTER_IGNORE
		context.custom_minimum_size = Vector2(218, 0)
		var style := _panel(Color(0.09, 0.17, 0.22, 0.91), 7)
		style.border_color = COLORS[pid]
		style.set_border_width_all(2)
		context.add_theme_stylebox_override("panel", style)
		root.add_child(context)
		var label := _ui_label("", 15)
		label.custom_minimum_size.x = 204
		label.clip_text = true
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		context.add_child(column)
		column.add_child(label)
		var progress := ProgressBar.new()
		progress.show_percentage = false
		progress.custom_minimum_size.y = 6
		progress.add_theme_stylebox_override("background", _panel(Color("253d46"), 0))
		progress.add_theme_stylebox_override("fill", _panel(COLORS[pid], 0))
		column.add_child(progress)
		progress.hide()
		context_progress.append(progress)
		context_panels.append(context)
		context_labels.append(label)
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu_panel.offset_left = -365
	menu_panel.offset_right = 365
	menu_panel.offset_top = -225
	menu_panel.offset_bottom = 225
	menu_panel.add_theme_stylebox_override("panel", _panel(Color(0.09, 0.17, 0.22, 0.97), 28))
	root.add_child(menu_panel)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 20)
	menu_panel.add_child(menu)
	menu_title = _ui_label("", 36)
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(menu_title)
	menu_body = _ui_label("", 23)
	menu_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_body.custom_minimum_size = Vector2(660, 180)
	menu.add_child(menu_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	menu.add_child(buttons)
	solo_button = _button("1 · 单人练习", func(): start_shift(false))
	duo_button = _button("2 · 双人开店", func(): start_shift(true))
	resume_button = _button("继续营业", func(): paused = false; menu_panel.hide())
	buttons.add_child(solo_button)
	buttons.add_child(duo_button)
	buttons.add_child(resume_button)
	resume_button.hide()

func _panel(color: Color, margin: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _ui_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("e9f0f3"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(185, 52)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	button.add_theme_stylebox_override("normal", _panel(Color("3b6575"), 10))
	button.add_theme_stylebox_override("hover", _panel(Color("50889a"), 10))
	button.add_theme_stylebox_override("pressed", _panel(Color("2c4f60"), 10))
	return button

func _show_menu() -> void:
	menu_title.text = "泡泡搭档"
	menu_body.text = "单人：WASD 快跑 · E 拿放 · 按住 F 护理\nTab 切换两名店员；另一人停下，机器继续运行\n双人：P1 WASD / E / F · P2 方向键 / K / L\n快洗 / 除虫从左接；修毛 / 爪护从右接\n窗口传宠和毛巾；干了 / 修好了要松开护理键\n1 单人 · 2 / 空格双人 · Esc 暂停\nB 背景音乐 · M 全部静音 · 种子 %d" % shift_seed
	menu_panel.show()

func _show_pause() -> void:
	menu_title.text = "歇一小会儿"
	menu_body.text = ("WASD 移动 · E 拿放 · 按住 F 护理 · Tab 换人\n另一人停下；浸洗、除虫、吹干、洗巾自动继续。\n" if not duo_mode else "P1 WASD / E / F · P2 方向键 / K / L\n") + "订单、护理和声音已暂停。\n恢复后先松开护理键；修好了 / 干了也要松手。\n炸毛 / 歪刘海：窗口或美容台补梳1.8秒。\nEsc 继续 · B 音乐 · M 全部静音"
	solo_button.hide()
	duo_button.hide()
	resume_button.show()
	menu_panel.show()

func _show_end() -> void:
	_close_input_intervals("shift_end")
	salon_audio.set_activity(false, false, 0, true)
	if "--playtest-evidence" in OS.get_cmdline_user_args():
		var evidence_path := ProjectSettings.globalize_path("user://playtest-evidence/current-session.json")
		DirAccess.make_dir_recursive_absolute(evidence_path.get_base_dir())
		var evidence := FileAccess.open(evidence_path, FileAccess.WRITE)
		if evidence:
			evidence.store_string(JSON.stringify({"scope":"Runtime events/input transitions only; not an experience verdict", "seed":model.shift_seed, "schedule":model.order_schedule, "score":model.score, "stars":model.stars(), "goal":model.goal, "delivered":model.delivered, "missed":model.missed, "offered":model.arrivals_total, "refused":model.refused, "pending":model.pending_orders.size(), "active":model.pets.size(), "stats":model.stats, "events":session_events, "input_telemetry":input_telemetry, "input_telemetry_capped":input_telemetry.size() >= 12000}, "\t"))
	menu_title.text = "%s 服务星级" % ("★".repeat(model.stars()) + "☆".repeat(3 - model.stars())) if model.has_won() else "收工啦，再来一班？"
	var shakes := 0
	var towel_uses := 0
	var frizz_count := 0
	var crooked_count := 0
	var repair_count := 0
	var imperfect_count := 0
	for event in session_events:
		shakes += int(event.get("type") == "shake")
		towel_uses += int(event.get("type") == "towel_dried")
		frizz_count += int(event.get("type") == "frizzed")
		crooked_count += int(event.get("type") == "crooked")
		repair_count += int(event.get("type") == "cosmetic_repaired")
		imperfect_count += int(event.get("type") == "delivered" and event.get("cosmetic", false))
	menu_body.text = "服务积分 %d / %d   ·   交还 %d 只\n本班到店 %d   ·   离店 %d（满队 %d）\n甩水 %d · 毛巾擦干 %d · 接力 %d\n炸毛 %d · 歪刘海 %d · 补梳 %d · 瑕疵交还 %d\n种子 %d · R 同班重试 · N 换个班次" % [model.score, model.goal, model.delivered, model.arrivals_total, model.missed, model.refused, shakes, towel_uses, model.stats.handoffs, frizz_count, crooked_count, repair_count, imperfect_count, shift_seed]
	solo_button.text = "单人再来"
	duo_button.text = "双人再来"
	solo_button.show()
	duo_button.show()
	resume_button.hide()
	menu_panel.show()

func _update_hud() -> void:
	if not is_instance_valid(score_label):
		return
	score_label.text = "%s  %d/%d分 · 交还%d" % ["★".repeat(model.stars()) + "☆".repeat(3 - model.stars()), model.score, model.star_thresholds()[mini(2, model.stars())], model.delivered]
	score_label.tooltip_text = "星级门槛：%s" % str(model.star_thresholds())
	seed_label.text = "种子 %d  " % shift_seed
	var seconds := maxi(0, int(ceil(model.remaining)))
	timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	timer_label.modulate = Color("ffbf8b") if seconds < 30 else Color.WHITE
	var laundry: String = "洗烘中 %ds" % int(ceil(model.laundry_remaining)) if model.laundry_count > 0 else "湿毛巾 %d → 拿回左侧洗烘" % model.towels_wet
	resource_label.text = "干巾 %d/3 · 使用中 %d · %s · 到店 %d · 离店 %d" % [model.towels_clean, model.towel_active, laundry, model.arrivals_total, model.missed]
	resource_label.modulate = Color("ffca86") if model.towels_clean == 0 else Color("c6e4dd")
	var next_in: float = model.next_arrival_in()
	next_orders_label.text = "%s · %s" % [model.shift_phase(), "下一单 %ds" % int(ceil(next_in)) if next_in >= 0 else "停止接单，抓紧收尾"]
	var waiting: Array[String] = []
	for ticket: Dictionary in model.pending_orders:
		waiting.append("%s/%s %ds" % [ticket.name, model.service_label(ticket), int(ceil(ticket.patience))])
	pending_label.text = "等候 %d/4  %s" % [waiting.size(), "  ｜  ".join(waiting)]
	if waiting.is_empty():
		pending_label.text += "接待位可选下一只" if recent_departures.is_empty() else "最近离店：%s" % "、".join(recent_departures)
	pending_label.modulate = Color("ffd29a") if waiting.size() >= 3 else Color("c6e4dd")
	for id in order_cards.keys():
		if not model.pets.has(id):
			order_cards[id].panel.queue_free()
			order_cards.erase(id)
	for id in model.pets:
		var pet: Dictionary = model.pets[id]
		if not order_cards.has(id):
			var card := PanelContainer.new()
			card.custom_minimum_size.x = 178
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.add_theme_stylebox_override("panel", _panel(Color("365361"), 7))
			order_row.add_child(card)
			var lines := VBoxContainer.new()
			lines.add_theme_constant_override("separation", 1)
			card.add_child(lines)
			var name_label := _ui_label("", 16)
			name_label.clip_text = true
			var route_label := _ui_label("", 15)
			route_label.clip_text = true
			route_label.modulate = Color("bacdd2")
			var quality_label := _ui_label("", 14)
			quality_label.clip_text = true
			quality_label.modulate = Color("ffd19a")
			var state_label := _ui_label("", 16)
			state_label.clip_text = true
			state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var state_row := HBoxContainer.new()
			state_row.add_theme_constant_override("separation", 4)
			var deadline_label := _ui_label("", 14)
			lines.add_child(name_label)
			lines.add_child(route_label)
			route_label.hide()
			var strip := CareStrip.new()
			lines.add_child(strip)
			lines.add_child(state_row)
			lines.add_child(quality_label)
			state_row.add_child(state_label)
			state_row.add_child(deadline_label)
			var patience := ProgressBar.new()
			patience.custom_minimum_size.y = 5
			patience.show_percentage = false
			patience.add_theme_stylebox_override("background", _panel(Color("253d46"), 0))
			patience.add_theme_stylebox_override("fill", _panel(Color("a4d6b1"), 0))
			lines.add_child(patience)
			order_cards[id] = {"panel":card, "name":name_label, "route":route_label, "strip":strip, "state":state_label, "quality":quality_label, "deadline":deadline_label, "patience":patience}
		var card: Dictionary = order_cards[id]
		card.name.text = "%s · %s %d分" % [pet.name, model.service_label(pet), model.SERVICE_BASE_POINTS[pet.service]]
		card.route.text = model.route_label(pet)
		var state: String = model.next_step(pet)
		if pet.location == "loose":
			state = "跑动中 · 快抱回"
		card.state.text = state
		var quality_status: String = _quality_hint(pet)
		card.quality.visible = not quality_status.is_empty()
		# Use the route line budget for urgent quality information; six active
		# cards must not grow the HUD into the north-side stations.
		card.route.visible = false
		card.strip.visible = quality_status.is_empty()
		card.strip.set_pet(pet)
		card.quality.text = quality_status
		card.quality.tooltip_text = model.cosmetic_status(pet)
		card.deadline.text = "%ds" % maxi(0, int(ceil(minf(pet.patience, model.remaining))))
		card.deadline.modulate = Color("ffc29c") if minf(pet.patience, model.remaining) < 20 else Color("e9f0f3")
		card.state.modulate = Color("bce4b6") if model.is_ready(pet) else (Color("ffc29c") if pet.patience < 20 else Color("e9f0f3"))
		card.patience.value = 100.0 * float(pet.patience) / float(pet.max_patience)
	if not game_started:
		hint_label.text = "强风快干2倍速 · 吹干 / 修毛完成请松手 · 造型翻车可补梳或低分交还"
	elif not duo_mode:
		hint_label.text = "P%d [Tab 换人]  %s" % [active_player + 1, _hint(active_player)]
	else:
		hint_label.text = "P1  %s\nP2  %s" % [_hint(0), _hint(1)]
	for key in station_labels:
		var color := Color("e9f1f3")
		if key == targets[0]:
			color = COLORS[0]
		if key == targets[1]:
			color = COLORS[1]
		station_labels[key].modulate = color
		var selected := false
		for pid in range(2):
			if not duo_mode and pid != active_player:
				continue
			selected = selected or (key == targets[pid] and not (_nearest_loose_pet(pid) != -1 and model.held_item(pid).kind == "none"))
		station_frames[key].visible = selected and game_started
		for edge: MeshInstance3D in station_frames[key].get_children():
			var material: StandardMaterial3D = edge.material_override
			material.albedo_color = color
	_update_context_prompts()

func _update_context_prompts() -> void:
	for pid in range(2):
		var panel := context_panels[pid]
		panel.visible = game_started and model.running and not paused and (duo_mode or pid == active_player)
		context_progress[pid].hide()
		if not panel.visible:
			continue
		var take := "E" if pid == 0 or not duo_mode else "K"
		var care := "F" if pid == 0 or not duo_mode else "L"
		var slot: String = interact_targets[pid]
		var work: String = work_targets[pid]
		var title := "P%d · %s" % [pid + 1, STATION_NAMES.get(slot, "靠近工位")]
		var action := "%s 拿放" % take
		if model.can_work(pid, work):
			action += "   %s %s" % [care, "护理" if slot == work else STATION_NAMES.get(work, "护理")]
		elif model.carried[pid] != -1:
			var held: Dictionary = model.pets[model.carried[pid]]
			title = "P%d 抱%s → %s" % [pid + 1, held.name, STATION_NAMES.get(slot, "靠近工位")]
			action += " · " + model.next_step(held)
			var cloth: int = model.towel_at(slot)
			if slot.begins_with("bench") and cloth != -1 and model.can_interact(pid, slot):
				action = "%s 放宠，湿巾换到手里" % take if model.towels[cloth].state == "wet" else "%s 放宠并包上预铺干巾" % take
		var id: int = int(model.slots.get(work if work_inputs[pid] else slot, -1))
		if id != -1 and model.pets.has(id):
			var pet: Dictionary = model.pets[id]
			title = "P%d · %s · %s" % [pid + 1, STATION_NAMES.get(work if work_inputs[pid] else slot, "工位"), pet.name]
			var progress := _care_progress(pet, work if work_inputs[pid] else slot)
			if not progress.is_empty():
				context_progress[pid].show()
				context_progress[pid].value = float(progress.value) * 100.0
				action = "%s %d%% · %s" % [progress.label, int(progress.value * 100.0), care + "护理" if model.can_work(pid, work) else take + "拿放"]
			var quality := _quality_hint(pet)
			if not quality.is_empty():
				action = quality
				if float(progress.get("value", -1)) >= 0 and pet.stage == "wet":
					action = "%s %d%% · 干了松手" % [progress.get("label", "护理"), int(progress.value * 100.0)]
		if model.held_towels[pid] != -1:
			action = "%s · %s 放下/包上" % [model.towel_label(model.held_towels[pid]), take]
		if _nearest_loose_pet(pid) != -1 and model.held_item(pid).kind == "none":
			title = "P%d · %s" % [pid + 1, model.pets[_nearest_loose_pet(pid)].name]
			action = "%s 抱回逃跑宠物！" % take
			context_progress[pid].hide()
		var invalid: bool = animation_time < local_feedback_until[pid]
		if not duo_mode:
			title = "正在控制 " + title + " · Tab 换人"
		context_labels[pid].text = title + "\n" + (local_feedback[pid] if invalid else action)
		context_labels[pid].modulate = Color("ffb59c") if invalid else COLORS[pid]
		var viewport := get_viewport().get_visible_rect().size
		# Dock below the playfield; prompts must never cover a pet or window.
		panel.size.x = (viewport.x - 64.0) / 2.0 if duo_mode else viewport.x - 48.0
		panel.position = Vector2(24.0 + pid * (viewport.x / 2.0 - 16.0) if duo_mode else 24.0, viewport.y - 124.0)

func _care_progress(pet: Dictionary, slot: String) -> Dictionary:
	if slot.begins_with("bench") and pet.stage == "dry" and (pet.get("frizzy", false) or pet.get("crooked", false)):
		return {"label":"救场补梳", "value":pet.repair_progress}
	if slot.begins_with("wash"):
		match pet.get("wash_phase", ""):
			"soap": return {"label":"搓泡", "value":pet.soap}
			"soak": return {"label":"浸洗", "value":1.0 - float(pet.soak_remaining) / model.SOAK_SECONDS}
			"rinse": return {"label":"冲净", "value":pet.rinse}
			"done": return {"label":"洗好", "value":1.0}
	if slot == "dryer":
		return {"label":"吹干", "value":pet.dry}
	if slot == "brush":
		if pet.get("frizzy", false) or pet.get("crooked", false):
			return {"label":"补梳", "value":pet.repair_progress}
		return {"label":"修毛", "value":pet.brush}
	if slot == "paws":
		return {"label":"爪护", "value":pet.paws}
	if slot == "treatment":
		return {"label":"除虫", "value":1.0 - float(pet.treatment_remaining) / model.TREATMENT_SECONDS} if pet.treatment_phase == "treating" else {"label":"启动", "value":pet.treatment_progress}
	if slot.begins_with("bench") and int(pet.get("towel_id", -1)) != -1:
		return {"label":"擦干", "value":pet.towel_progress}
	return {}

func _cosmetic_stop_required(pet: Dictionary, status: String = "") -> bool:
	# During wet boost, "干了要松手" is advance guidance, not a demand to stop.
	if pet.get("stage", "") != "dry":
		return false
	return "松手" in (model.cosmetic_status(pet) if status.is_empty() else status)

func _quality_hint(pet: Dictionary) -> String:
	var status: String = model.cosmetic_status(pet)
	if _cosmetic_stop_required(pet, status):
		return status
	if pet.get("frizzy", false) or pet.get("crooked", false):
		var defect := "毛球＋歪刘海" if pet.get("frizzy", false) and pet.get("crooked", false) else ("炸毛" if pet.get("frizzy", false) else "歪刘海")
		if pet.get("repair_progress", 0.0) > 0:
			return "补梳%d%% · %s" % [int(pet.repair_progress * 100), defect]
		return "%s · 补梳/65%%分" % defect if model.is_ready(pet) else "%s · 必需护理未完" % defect
	if "强风" in status:
		return "强风2倍 · 干了松手"
	return "" if status == "造型正常" else status

func _hint(pid: int) -> String:
	var message := _hint_state(pid)
	var work_target: String = work_targets[pid]
	if work_target != targets[pid] and model.held_item(pid).kind == "none" and model.can_work(pid, work_target):
		var care := "F" if pid == 0 or not duo_mode else "L"
		message += " · %s→%s" % [care, STATION_NAMES.get(work_target, "护理")]
	return message

func _hint_state(pid: int) -> String:
	var target: String = targets[pid]
	var place: String = STATION_NAMES.get(target, "靠近工位")
	var take: String = "E" if pid == 0 or not duo_mode else "K"
	var care: String = "F" if pid == 0 or not duo_mode else "L"
	var towel_id: int = model.held_towels[pid]
	if towel_id != -1:
		var task := "递给湿宠包上 / 空窗放下" if model.towels[towel_id].state == "clean" else "放到空窗退回 / 送回洗烘机"
		return "%s在手 · %s  ｜ %s：%s" % [model.towel_label(towel_id), task, take, place]
	if model.carried[pid] != -1:
		var pet: Dictionary = model.pets.get(model.carried[pid], {})
		if pet.is_empty():
			return ""
		var task: String = model.next_step(pet)
		if pet.get("frizzy", false) or pet.get("crooked", false):
			task += " · 可补梳 / 65%基础分交付" if model.is_ready(pet) else " · 造型可补梳，必需护理仍须完成"
		return "抱着%s · %s  ｜ %s：%s" % [pet.name, task, take, place]
	var loose_id := _nearest_loose_pet(pid)
	if loose_id != -1:
		return "%s：抱回 %s！护理进度还在" % [take, model.pets[loose_id].name]
	if target == "laundry":
		return "%s 取干巾 · %s 洗已投入的湿巾%s" % [take, care, " · 还需%ds" % int(ceil(model.laundry_remaining)) if model.laundry_count > 0 else ""]
	towel_id = model.towel_at(target)
	if towel_id != -1:
		return "%s：拿起%s · %s" % [take, model.towel_label(towel_id), place]
	var id: int = model.slots.get(target, -1)
	if id == -1:
		if target.begins_with("buffer"):
			return "%s · 可临时放一只，护理进度保留" % place
		return "%s · 空位" % place
	var pet: Dictionary = model.pets.get(id, {})
	var cosmetic: String = model.cosmetic_status(pet)
	if _cosmetic_stop_required(pet, cosmetic):
		return "%s · %s！%s 抱走" % [pet.name, cosmetic, take]
	if (target == "brush" or target.begins_with("bench")) and pet.stage == "dry" and (pet.get("frizzy", false) or pet.get("crooked", false)):
		var choice := " · 可%s抱走低分交还" % take if model.is_ready(pet) else " · 必需护理仍须完成"
		return "%s · 松手后按 %s 补梳1.8秒%s" % [pet.name, care, choice]
	if target == "treatment":
		var phase: String = pet.get("treatment_phase", "")
		if phase == "treating":
			return "%s · 除虫护理 %ds，先忙别的" % [pet.name, int(ceil(pet.treatment_remaining))]
		if phase == "ready":
			return "%s：抱走 %s，去浴池只需冲净" % [take, pet.name]
		return "%s · 按住 %s 启动除虫护理" % [pet.name, care]
	if target.begins_with("wash") and pet.get("stage") == "dirty":
		return "%s · %s · %s 护理" % [pet.name, model.wash_status(pet), care]
	if target == "brush" and pet.needs_brush and not pet.brushed:
		if pet.stage != "dry":
			return "%s · 先吹干或毛巾擦干，再修毛" % pet.name
		return "%s · 按住 %s 修毛美容" % [pet.name, care]
	if target == "paws" and pet.get("needs_paws", false) and not pet.get("paws_done", false):
		if pet.stage != "dry":
			return "%s · 先吹干或毛巾擦干，再做爪爪护理" % pet.name
		return "%s · 按住 %s 爪爪护理" % [pet.name, care]
	if target == "dryer" and pet.get("stage") == "wet":
		return "%s · 自动12秒 / 按住%s强风2倍速，干了请松手" % [pet.name, care]
	if target.begins_with("bench") and pet.get("stage") == "wet":
		if pet.towel_active:
			return "%s · 按住 %s 擦干，完成才能抱走" % [pet.name, care]
		return "%s · 先拿干巾按 %s 包上 / %s 抱去吹干" % [pet.name, take, take]
	if pet.get("frizzy", false) or pet.get("crooked", false):
		return "%s · %s 抱去补梳%s" % [pet.name, take, " / 交还预计%d分（基础65%%）" % model.delivery_points(pet) if model.is_ready(pet) else "，先完成必需护理"]
	return "%s：抱起 %s · %s" % [take, pet.get("name", "宠物"), place]

func _toast(message: String, duration: float = 2.0) -> void:
	if not is_instance_valid(toast_label):
		return
	toast_label.text = message
	toast_label.show()
	toast_time = duration

func _build_audio() -> void:
	salon_audio = Audio.new()
	salon_audio.name = "SalonAudio"
	add_child(salon_audio)
