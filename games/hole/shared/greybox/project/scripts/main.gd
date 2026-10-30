extends Node3D
## Thin input/render adapter around a pure simulation.
const Simulation = preload("res://scripts/simulation.gd")
const Tuning = preload("res://scripts/tuning.gd")
const DefaultTuning = preload("res://data/default_tuning.tres")
const VisualFactory = preload("res://scripts/visual_factory.gd")
const Hud = preload("res://scripts/hud.gd")
const SoundBank = preload("res://scripts/sound_bank.gd")
const WaterfrontStage = preload("res://scripts/waterfront_stage.gd")

var sim
var tuning
var factory
var hud
var sound
var camera: Camera3D
var visuals_root: Node3D
var proxy_root: Node3D
var object_views: Array = []
var proxy_views: Array = []
var hole_views: Array = []
var capture_ring_views: Array = []
var proxy_materials: Array = []
var floor_material: ShaderMaterial
var ground_labels: Node3D
var paused: bool = false
var show_proxies: bool = false
var overview: bool = false
var rival_enabled: bool = false
var hover_index: int = -1
var last_hover_index: int = -1
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_touch_index: int = -1
var touch_position: Vector2 = Vector2.ZERO
var camera_target: Vector3 = Vector3.ZERO
var lab_index: int = -1
var last_run_path: String = ""
var startup_failed: bool = false
var camera_distance: float = 14.0
var camera_lead: Vector3 = Vector3.ZERO
var last_countdown_second: int = -1

func _ready() -> void:
	tuning = DefaultTuning.duplicate(true)
	tuning.load_local()
	sim = Simulation.new()
	var definition = JSON.parse_string(FileAccess.get_file_as_string("res://data/graybox_config.json"))
	if not definition is Dictionary or not sim.initialize(definition, tuning):
		_show_boot_error("Cannot load data/graybox_config.json. " + sim.error_message)
		return
	for key in Tuning.KEYS:
		if key not in ["sound_enabled", "sfx_volume"] and tuning.get(key) != Tuning.new().get(key):
			sim.assisted_run = true
	factory = VisualFactory.new()
	camera = get_node("Camera3D") as Camera3D
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.current = true
	camera.near = 0.05
	camera.far = 160.0
	var preview: Node = get_node_or_null("EditorPreview")
	if preview != null:
		preview.queue_free()
	_build_stage()
	_build_views()
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	layer.add_child(hud)
	sound = SoundBank.new()
	add_child(sound)
	sim.happened.connect(_on_sim_event)
	camera_target = sim.holes[0]["position"] + Vector3(0, 0, -1.5)
	_sync_camera(1.0, true)
	_sync_views()
	get_window().title = "Hole / Waterfront — Godot Graybox v0.3 / LAND + WATER"

func _build_stage() -> void:
	var builder = WaterfrontStage.new()
	var built: Dictionary = builder.build(self, factory, sim.config["map"])
	floor_material = built["floor_material"]
	ground_labels = Node3D.new()
	ground_labels.name = "DebugZoneLabels"
	add_child(ground_labels)
	_add_ground_label(ground_labels, "A / DONUT", Vector3(-15, .025, 7.6), 25)
	_add_ground_label(ground_labels, "B / BOBA + BOOKS", Vector3(-13, .025, -16.7), 25)
	_add_ground_label(ground_labels, "C / DUCK PLAZA", Vector3(0, .025, -8.5), 25)
	_add_ground_label(ground_labels, "D / MARKET", Vector3(13, .025, 16), 25)
	_add_ground_label(ground_labels, "E / DRY QUAY", Vector3(-1, .025, 16), 25)
	_add_ground_label(ground_labels, "F / FLOWERS", Vector3(14, .025, -17.0), 25)
	visuals_root = Node3D.new()
	visuals_root.name = "LogicalUnits_215"
	add_child(visuals_root)
	proxy_root = Node3D.new()
	proxy_root.name = "DebugFootprints"
	add_child(proxy_root)
	for color in [Color("51db9b"), Color("e2a866"), Color("54707c"), Color("76c8f2")]:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		proxy_materials.append(mat)

func _add_ground_label(parent: Node3D, text: String, position: Vector3, font_size: int) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.018
	label.modulate = Color("8499a5")
	label.outline_size = 0
	label.shaded = false
	label.position = position
	label.rotation_degrees.x = -90.0
	parent.add_child(label)

func _build_views() -> void:
	for child in visuals_root.get_children():
		child.free()
	for child in proxy_root.get_children():
		child.free()
	for view in hole_views:
		if is_instance_valid(view):
			view.free()
	object_views.clear()
	proxy_views.clear()
	hole_views.clear()
	capture_ring_views.clear()
	for o in sim.objects:
		var view: Node3D = factory.build(o["definition"], str(o["asset_id"]))
		view.name = str(o["id"])
		visuals_root.add_child(view)
		object_views.append(view)
		var proxy: MeshInstance3D = MeshInstance3D.new()
		proxy.mesh = factory.proxy_mesh(o["definition"])
		proxy.material_override = proxy_materials[2]
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy_root.add_child(proxy)
		proxy_views.append(proxy)
	for index in range(sim.holes.size()):
		var view: Node3D = factory.make_hole(Color("47c9ee") if index == 0 else Color("dc97be"))
		add_child(view)
		hole_views.append(view)
		var capture_ring: MeshInstance3D = MeshInstance3D.new()
		capture_ring.mesh = factory.proxy_mesh({"id": "supported_ball", "size_xyz": [2.0, 0.0, 2.0]})
		capture_ring.material_override = proxy_materials[3]
		capture_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy_root.add_child(capture_ring)
		capture_ring_views.append(capture_ring)

func _physics_process(delta: float) -> void:
	if startup_failed or sim == null or paused:
		return
	sim.tick(delta, _movement_input())
	var remaining: int = int(ceil(tuning.round_seconds - sim.elapsed))
	if sim.stage == Simulation.PLAYING and not sim.lab_unlimited and remaining <= 5 and remaining > 0 and remaining != last_countdown_second:
		last_countdown_second = remaining
		sound.play_event("COUNTDOWN", 0)

func _process(delta: float) -> void:
	if startup_failed or sim == null:
		return
	_sync_camera(delta)
	_sync_views()
	_sync_occlusion(delta)
	_update_hover()
	if sound != null:
		sound.configure(tuning.sound_enabled, tuning.sfx_volume)
		var activity: float = float(sim.count_state(Simulation.CAPTURED))
		var velocity: Vector2 = sim.holes[0]["velocity"]
		sound.update_motion(velocity.length() / maxf(tuning.move_speed, 0.1), activity, sim.stage == Simulation.PLAYING and not paused)

func _movement_input() -> Vector2:
	var x: float = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var y: float = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var direction: Vector2 = Vector2(x, y)
	if direction.length_squared() > 0.0:
		return direction.normalized()
	if dragging:
		var pointer: Vector2 = touch_position if drag_touch_index >= 0 else get_viewport().get_mouse_position()
		var displacement: Vector2 = pointer - drag_start
		if displacement.length() > tuning.joystick_radius:
			drag_start = pointer - displacement.normalized() * tuning.joystick_radius
			displacement = pointer - drag_start
		var strength: float = clampf((displacement.length() / tuning.joystick_radius - 0.06) / 0.94, 0.0, 1.0)
		return displacement.normalized() * strength if strength > 0.0 else Vector2.ZERO
	return Vector2.ZERO

func _input(event: InputEvent) -> void:
	# Release must be observed even if the pointer now rests over a UI control.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
	if event is InputEventScreenTouch and not event.pressed and event.index == drag_touch_index:
		dragging = false
		drag_touch_index = -1
	if event is InputEventScreenDrag and event.index == drag_touch_index:
		touch_position = event.position

func _unhandled_input(event: InputEvent) -> void:
	if startup_failed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		drag_touch_index = -1
		drag_start = event.position
	elif event is InputEventScreenTouch and event.pressed and drag_touch_index < 0:
		dragging = true
		drag_touch_index = event.index
		touch_position = event.position
		drag_start = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var zoom_step: float = -0.05 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.05
		change_tuning("camera_scale", tuning.camera_scale + zoom_step)
		hud.refresh_values()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				command("restart")
			KEY_SPACE:
				command("pause")
			KEY_PERIOD:
				if paused:
					sim.begin()
					sim.tick(1.0 / 60.0, _movement_input())
			KEY_F1:
				hud.panel_visible = not hud.panel_visible
			KEY_F2:
				command("lab:%d" % ((lab_index + 1) % 6))
			KEY_F5:
				command("save_tuning")
			KEY_F6:
				command("baseline")
			KEY_F8:
				command("export")
			KEY_G:
				command("proxies")
			KEY_TAB:
				command("camera_toggle")
			KEY_BRACKETLEFT:
				command("size:%d" % maxi(0, sim.effective_tier() - 1))
			KEY_BRACKETRIGHT:
				command("size:%d" % mini(5, sim.effective_tier() + 1))
			KEY_0:
				command("size:-1")
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				command("size:%d" % (int(event.physical_keycode) - int(KEY_1)))
			KEY_B:
				command("rival")
			KEY_V:
				command("test_sound")
			KEY_M:
				tuning.sound_enabled = not tuning.sound_enabled
				hud.notify("Sound ON" if tuning.sound_enabled else "Sound OFF")
			KEY_K:
				command("reset_group")
			KEY_ESCAPE:
				if hud.panel_visible:
					hud.panel_visible = false
				else:
					command("pause")

func command(action: String) -> void:
	if action.begins_with("size:"):
		sim.force_size(int(action.get_slice(":", 1)))
		hud.notify("Size override / assisted run" if sim.forced_tier >= 0 else "Earned size restored / run remains labelled assisted")
		return
	if action.begins_with("lab:"):
		_enter_lab(int(action.get_slice(":", 1)))
		return
	if action.begins_with("route:"):
		sim.route_mode = int(action.get_slice(":", 1))
		if sim.route_mode > 0:
			sim.assisted_run = true
			sim.begin()
			paused = false
		hud.notify("Automated input / no extra growth or rewards" if sim.route_mode > 0 else "Manual control restored")
		return
	match action:
		"restart":
			_restart()
		"pause":
			paused = not paused
			dragging = false
		"proxies":
			show_proxies = not show_proxies
		"rival":
			rival_enabled = not rival_enabled
			_restart()
			hud.notify("One rival / experimental resource competition" if rival_enabled else "Solo baseline")
		"unlimited":
			sim.lab_unlimited = not sim.lab_unlimited
			sim.assisted_run = true
			hud.notify("Unlimited lab ON" if sim.lab_unlimited else "Unlimited lab OFF")
		"geometry_gate":
			tuning.enforce_tier_gate = not tuning.enforce_tier_gate
			sim.assisted_run = true
			hud.notify("Legacy tier + geometry gate" if tuning.enforce_tier_gate else "Continuous size / geometry gate")
		"growth_toggle":
			tuning.continuous_growth = not tuning.continuous_growth
			sim.assisted_run = true
			hud.notify("Continuous growth" if tuning.continuous_growth else "Stepped growth / comparison only")
		"camera_toggle":
			overview = not overview
			_sync_camera(1.0, true)
			hud.notify("ORTHOGRAPHIC / map inspection" if overview else "PERSPECTIVE / follow camera")
		"test_sound":
			tuning.sound_enabled = true
			sound.configure(true, tuning.sfx_volume)
			sound.test_sequence()
			hud.notify("SFX test / small bite, medium, large, growth, landmark")
		"save_tuning":
			var error: Error = tuning.save_local()
			hud.notify("Tuning saved to user://hole_waterfront_tuning_v03.json" if error == OK else "Could not save tuning: " + error_string(error))
		"baseline":
			tuning.apply_values(Tuning.new().snapshot())
			tuning.save_local()
			hud.refresh_values()
			overview = false
			rival_enabled = false
			_restart()
			hud.notify("v0.3 baseline / waterfront + full-disk land boundary")
		"export":
			_export_run(true)
		"open_logs":
			var path: String = ProjectSettings.globalize_path("user://runs")
			DirAccess.make_dir_recursive_absolute(path)
			OS.shell_open(path)
		"reset_group":
			_reset_selected_group()

func change_tuning(key: String, value: float) -> void:
	tuning.apply_values({key: value})
	if key != "sfx_volume":
		sim.assisted_run = true
	sim._emit("TUNING", {"key": key, "value": tuning.get(key)})
	if key == "diameter_scale" and (paused or sim.stage == Simulation.READY):
		for owner in range(sim.holes.size()):
			sim.holes[owner]["diameter"] = sim.desired_diameter(owner)
	if key in ["diameter_scale", "shore_margin"]:
		sim.constrain_all_holes()

func _restart() -> void:
	if sim.clock > 0.0 and sim.stage != Simulation.FINISHED:
		_export_run(false)
	paused = false
	dragging = false
	hover_index = -1
	last_countdown_second = -1
	if sound != null:
		sound.stop_all()
	last_hover_index = -1
	sim.reset(rival_enabled)
	# Persistent edited tuning is not mislabelled as the original baseline.
	var baseline: Dictionary = Tuning.new().snapshot()
	var live: Dictionary = tuning.snapshot()
	for key in baseline:
		if key not in ["sound_enabled", "sfx_volume"] and live[key] != baseline[key]:
			sim.assisted_run = true
	_build_views()
	camera_target = sim.holes[0]["position"] + Vector3(0, 0, -1.5)
	_sync_camera(1.0, true)

func _enter_lab(index: int) -> void:
	lab_index = clampi(index, 0, 5)
	rival_enabled = false
	_restart()
	var positions: Array = [Vector3(-16.8, 0, 5.5), Vector3(-12.0, 0, -3.4), Vector3(12.0, 0, 7.0), Vector3(11.0, 0, -10.0), Vector3(0, 0, 1.0), Vector3(-5.5, 0, 11.0)]
	var tiers: Array = [0, 2, 2, 3, 5, 5]
	sim.lab_unlimited = true
	sim.force_size(tiers[lab_index])
	sim.teleport(positions[lab_index])
	show_proxies = true
	overview = false
	camera_target = sim.holes[0]["position"] + Vector3(0, 0, -1.0)
	_sync_camera(1.0, true)
	hud.notify("Lab preset / fixed size / unlimited clock / real object ledger")

func _reset_selected_group() -> void:
	var index: int = last_hover_index
	if index < 0 or index >= sim.objects.size():
		hud.notify("Hover a table, payload, fence row or apartment first [G]")
		return
	var group = sim.objects[index]["assembly"]
	if group == null or not sim.reset_assembly(str(group)):
		hud.notify("Selected object has no assembly. R resets the whole map.")
		return
	hud.notify("Assembly restored / reward ledger recomputed / lab only")

func _sync_views() -> void:
	ground_labels.visible = show_proxies or overview
	floor_material.set_shader_parameter("show_grid", show_proxies)
	floor_material.set_shader_parameter("shore_margin", tuning.shore_margin)
	for index in range(sim.objects.size()):
		var o: Dictionary = sim.objects[index]
		var view: Node3D = object_views[index]
		view.visible = int(o["state"]) != Simulation.CONSUMED
		if view.visible:
			view.position = o["position"]
			view.rotation = o["rotation"] if int(o["state"]) == Simulation.CAPTURED else Vector3(0, float(o["yaw"]), 0)
			view.scale = Vector3.ONE * float(o["visual_scale"])
		var proxy: MeshInstance3D = proxy_views[index]
		proxy.visible = show_proxies and int(o["state"]) in [Simulation.AVAILABLE, Simulation.LOCKED, Simulation.FALLING]
		if proxy.visible:
			var position: Vector3 = o["position"]
			proxy.position = Vector3(position.x, 0.03, position.z)
			proxy.rotation.y = float(o["yaw"])
			proxy.material_override = proxy_materials[1 if int(o["state"]) == Simulation.LOCKED else (0 if sim.is_collectible(o) else 2)]
	for owner in range(sim.holes.size()):
		var h: Dictionary = sim.holes[owner]
		var radius: float = float(h["diameter"]) * 0.5
		var view: Node3D = hole_views[owner]
		view.visible = h["alive"]
		view.position = h["position"]
		view.scale = Vector3(radius, 1.0, radius)
		var capture_ring: MeshInstance3D = capture_ring_views[owner]
		capture_ring.visible = show_proxies and h["alive"]
		capture_ring.position = h["position"] + Vector3(0, 0.05, 0)
		capture_ring.scale = Vector3(radius * tuning.capture_factor, 1.0, radius * tuning.capture_factor)
		var position: Vector3 = h["position"]
		floor_material.set_shader_parameter("hole_a" if owner == 0 else "hole_b", Vector4(position.x, position.z, radius, 1.0 if h["alive"] else 0.0))
	if sim.holes.size() < 2:
		floor_material.set_shader_parameter("hole_b", Vector4.ZERO)
	var a: Vector4 = floor_material.get_shader_parameter("hole_a")
	var b: Vector4 = floor_material.get_shader_parameter("hole_b")
	for mat in factory.materials.values():
		mat.set_shader_parameter("hole_a", a)
		mat.set_shader_parameter("hole_b", b)
	for view in object_views:
		for mat in view.get_meta("cutaway_materials", []):
			mat.set_shader_parameter("hole_a", a)
			mat.set_shader_parameter("hole_b", b)

func _sync_camera(delta: float, immediate: bool = false) -> void:
	var player: Dictionary = sim.holes[0]
	var hole_position: Vector3 = player["position"]
	var velocity: Vector2 = player["velocity"]
	var amount: float = 1.0 if immediate else 1.0 - exp(-delta / tuning.camera_lag)
	var desired_lead: Vector3 = Vector3(velocity.x, 0.0, velocity.y) * tuning.camera_lookahead
	camera_lead = camera_lead.lerp(desired_lead, amount)
	var desired_target: Vector3 = hole_position + Vector3(0, 0, -0.65) + camera_lead
	if overview:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera_target = Vector3(0, 0, -0.5)
		camera.position = camera_target + Vector3(0, 34, 19)
		camera.look_at(camera_target, Vector3.UP)
		camera.size = 43.0 * tuning.camera_scale
		return
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera_target = desired_target if immediate else camera_target.lerp(desired_target, amount)
	# Grow the view by far less than the hole grows, preserving screen-space growth.
	# Use actual smoothed diameter, never discrete tier, to avoid camera step jumps.
	var desired_distance: float = (14.0 + maxf(0.0, float(player["diameter"]) - 0.9) * 1.6) * tuning.camera_scale
	var zoom_blend: float = 1.0 if immediate else 1.0 - exp(-delta / 0.30)
	camera_distance = lerpf(camera_distance, desired_distance, zoom_blend)
	var pitch: float = deg_to_rad(tuning.camera_pitch)
	camera.position = camera_target + Vector3(0.0, sin(pitch) * camera_distance, cos(pitch) * camera_distance)
	camera.look_at(camera_target, Vector3.UP)
	# A small smooth expansion while moving; no shake, bob or automatic yaw.
	var desired_fov: float = tuning.camera_fov + clampf(velocity.length() / maxf(tuning.move_speed, 0.1), 0.0, 1.0) * 2.0
	camera.fov = lerpf(camera.fov, desired_fov, amount)

func _sync_occlusion(delta: float) -> void:
	# Screen-space test for the handful of tall buildings, not the hundreds of props.
	# Dissolve only an occluder, and always show the full object while it is swallowed.
	var hp: Vector3 = sim.holes[0]["position"] + Vector3(0, 0.06, 0)
	var screen_hole: Vector2 = camera.unproject_position(hp)
	for index in range(sim.objects.size()):
		var view: Node3D = object_views[index]
		var mats: Array = view.get_meta("cutaway_materials", [])
		if mats.is_empty():
			continue
		var o: Dictionary = sim.objects[index]
		var desired: float = 0.0
		if not overview and int(o["state"]) == Simulation.AVAILABLE and view.visible:
			var center: Vector3 = o["position"]
			var extent: Vector3 = o["size"] * 0.5
			if center.z > hp.z + 0.1 and not camera.is_position_behind(center):
				var top_left: Vector2 = camera.unproject_position(center + Vector3(-extent.x, extent.y, 0.0))
				var bottom_right: Vector2 = camera.unproject_position(center + Vector3(extent.x, -extent.y, 0.0))
				var rect: Rect2 = Rect2(top_left, bottom_right - top_left).abs().grow(12.0)
				if rect.has_point(screen_hole):
					desired = 0.68
		var fade: float = lerpf(float(view.get_meta("cutaway", 0.0)), desired, 1.0 - exp(-delta * 14.0))
		if int(o["state"]) == Simulation.CAPTURED:
			fade = 0.0
		view.set_meta("cutaway", fade)
		for mat in mats:
			mat.set_shader_parameter("occlusion_fade", fade)

func _update_hover() -> void:
	hover_index = -1
	if not show_proxies:
		return
	var cursor: Vector2 = get_viewport().get_mouse_position()
	if hud != null and hud.panel_visible and hud.lab_panel.get_global_rect().has_point(cursor):
		hover_index = last_hover_index
		return
	var plane: Plane = Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
	if not hit is Vector3:
		return
	var nearest: float = INF
	for index in range(sim.objects.size()):
		var o: Dictionary = sim.objects[index]
		if int(o["state"]) == Simulation.CONSUMED:
			continue
		var difference: Vector3 = hit - o["position"]
		difference.y = 0.0
		var distance: float = difference.length()
		var limit: float = maxf(0.28, float(o["definition"]["proxy_flat_span"]) * 0.5)
		if distance <= limit and distance < nearest:
			hover_index = index
			nearest = distance
	if hover_index >= 0:
		last_hover_index = hover_index

func _on_sim_event(event: Dictionary) -> void:
	if hud == null:
		return
	var kind: String = str(event["event"])
	if kind == "CONSUME" and int(event.get("owner", -1)) == 0:
		sound.play_event(kind, int(event.get("object_tier", 0)))
		if str(event.get("archetype", "")) == "landmark":
			sound.play_event("LANDMARK", 5)
			hud.notify("LANDMARK SWALLOWED / keep going!", 2.5)
	elif kind == "LEVEL_UP" and int(event["owner"]) == 0:
		sound.play_event(kind, int(event["tier"]))
		hud.pulse = 0.7
		hud.notify("G%d / growth milestone" % int(event["tier"]), 1.2)
	elif kind == "CAPTURE" and int(event.get("owner", -1)) == 0:
		sound.play_event("CAPTURE", int(event.get("object_tier", 0)))
	elif kind == "RELEASE":
		sound.play_event("RELEASE", 1)
	elif kind == "FINISHED":
		sound.play_event(kind)
		_export_run(false)

func _export_run(show_toast: bool) -> void:
	var directory: String = ProjectSettings.globalize_path("user://runs")
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		if show_toast:
			hud.notify("Could not create telemetry folder: " + error_string(error))
		return
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var filename: String = "%s/run_%s_%03d.json" % [directory, stamp, sim.run_id]
	var file: FileAccess = FileAccess.open(filename, FileAccess.WRITE)
	if file == null:
		if show_toast:
			hud.notify("Could not write telemetry: " + error_string(FileAccess.get_open_error()))
		return
	var report: Dictionary = sim.report()
	report["engine"] = Engine.get_version_info()
	report["rendering_method"] = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	report["source"] = "godot_runtime"
	file.store_string(JSON.stringify(report, "\t"))
	last_run_path = filename
	print("Run telemetry: " + filename)
	if show_toast:
		hud.notify("Run exported / F1 > Open local telemetry folder")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = false
		if sim != null and sim.stage == Simulation.PLAYING:
			paused = true

func _show_boot_error(message: String) -> void:
	startup_failed = true
	push_error(message)
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var label: Label = Label.new()
	label.position = Vector2(32, 32)
	label.text = "HOLE LAB / LOAD ERROR\n\n" + message
	layer.add_child(label)
