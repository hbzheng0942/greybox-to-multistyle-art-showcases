extends Control
## Immediate HUD + native tuning widgets. Default engine font only.
var game
var font: Font
var lab_panel: PanelContainer
var sliders: Dictionary = {}
var value_labels: Dictionary = {}
var result_buttons: HBoxContainer
var toast: String = ""
var toast_left: float = 0.0
var pulse: float = 0.0
var panel_visible: bool = false
const INK = Color("14252d")
const MINT = Color("91e6bf")
const WHITE = Color("e8efeb")
const MUTED = Color("a0b4b6")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	_build_panel()
	_build_result_buttons()

func _process(delta: float) -> void:
	toast_left = maxf(0.0, toast_left - delta)
	pulse = maxf(0.0, pulse - delta)
	queue_redraw()
	if is_instance_valid(lab_panel):
		lab_panel.position = Vector2(size.x - 350.0, 114.0)
		lab_panel.size = Vector2(326.0, maxf(250.0, size.y - 204.0))
		lab_panel.visible = panel_visible
	if game != null and game.sim != null:
		result_buttons.visible = game.sim.stage == game.Simulation.FINISHED
		result_buttons.position = Vector2(size.x * 0.5 - 176.0, size.y * 0.5 + 112.0)

func _text(p: Vector2, text: String, font_size: int = 16, color: Color = WHITE) -> void:
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _card(rect: Rect2, alpha: float = 0.94) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(INK, alpha)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_color = Color(WHITE, 0.09)
	style.set_border_width_all(1)
	draw_style_box(style, rect)

func _draw() -> void:
	if game == null or game.sim == null or game.sim.holes.is_empty():
		return
	var sim = game.sim
	var player: Dictionary = sim.holes[0]
	var width: float = size.x
	var height: float = size.y
	var tier: int = sim.effective_tier(0)
	var presentation: Dictionary = game.factory.recipe_library.recipe.get("presentation", {})
	if not presentation.is_empty():
		_draw_presentation(presentation, player, width, height)
	else:
		_card(Rect2(24, 20, 288, 84))
		var theme_title: String = str(game.factory.theme_id).to_upper()
		_text(Vector2(40, 49), "HOLE / " + theme_title, 23)
		var mode: String = "SOLO / %ds" % int(game.tuning.round_seconds)
		if sim.holes.size() > 1:
			mode = "RIVAL / EXPERIMENTAL"
		if sim.assisted_run:
			mode = "LAB / ASSISTED RUN"
		if sim.route_mode > 0:
			mode = "AUTO ROUTE / NOT A HUMAN TEST"
		_text(Vector2(40, 76), mode, 12, MINT)
		_text(Vector2(40, 94), "215 units / dry land + water / v0.3", 11, MUTED)
		var camera_label: String = "MAP / ORTHO" if game.overview else "FOLLOW / PERSPECTIVE"
		_text(Vector2(40, 120), camera_label, 10, MUTED)
		_card(Rect2(width * 0.5 - 58.0, 20, 116, 84))
		var remaining: float = maxf(0.0, game.tuning.round_seconds - sim.elapsed)
		var seconds_left: int = int(ceil(remaining))
		_text(Vector2(width * 0.5 - 35.0, 63), "%02d:%02d" % [seconds_left / 60, seconds_left % 60], 29, MINT if remaining > 10.0 else Color("f2bf8a"))
		_text(Vector2(width * 0.5 - 34.0, 86), "FREE LAB" if sim.lab_unlimited else "REMAINING", 10, MUTED)
		_card(Rect2(width - 262, 20, 238, 84))
		_text(Vector2(width - 244, 49), "%04d" % int(player["score"]), 26)
		_text(Vector2(width - 160, 47), "/ %d" % int(sim.config["summary"]["score_total"]), 13, MUTED)
		_text(Vector2(width - 244, 76), "%d eaten    %d / 3 landmarks" % [int(player["count"]), int(player["landmarks"])], 13, MINT)
		_text(Vector2(width - 244, 94), "F1  OPEN TUNING" if not panel_visible else "F1  CLOSE TUNING", 10, MUTED)
		_text(Vector2(width - 244, 120), "%.1f u/s  /  SFX %s [M]" % [game.tuning.move_speed, "ON" if game.tuning.sound_enabled else "OFF"], 10, MUTED)

		_card(Rect2(24, height - 147, 312, 70))
		_text(Vector2(40, height - 120), "G%d" % tier, 23, MINT)
		_text(Vector2(93, height - 121), "DIAMETER  %.2f u" % float(player["diameter"]), 15)
		var thresholds: Array = sim.config["recipe"]["growth_thresholds_cumulative"]
		var lower: int = int(thresholds[int(player["tier"])])
		var upper: int = int(thresholds[mini(int(player["tier"]) + 1, 5)])
		if int(player["tier"]) == 5 and game.tuning.continuous_growth:
			upper = int(sim.config["recipe"].get("continuous_growth_tail_score", 1000))
		var progress: float = 1.0
		if upper > lower:
			progress = clampf(float(int(player["growth"]) - lower) / float(upper - lower), 0.0, 1.0)
		draw_rect(Rect2(40, height - 103, 276, 5), Color("31464b"))
		draw_rect(Rect2(40, height - 103, 276 * progress, 5), MINT)
		var progress_text: String = "%d / %d growth" % [int(player["growth"]), upper] if int(player["tier"]) < 5 else "%d / %d  / GIANT" % [int(player["growth"]), upper]
		_text(Vector2(40, height - 83), progress_text, 10, MUTED)

		_card(Rect2(24, height - 62, width - 48, 40))
		_text(Vector2(40, height - 36), "WASD / DRAG    R restart    SPACE pause    G proxies    TAB camera    SCROLL zoom    V sound test    F1 tuning", 12)
		if game.overview:
			_draw_minimap(Rect2(width - 230, height - 254, 206, 178))
	if game.show_proxies and game.hover_index >= 0:
		_draw_inspection(Rect2(24, height - 258, 366, 96), sim.objects[game.hover_index])
	elif sim.stage == sim.PLAYING and not game.paused:
		_draw_capture_feedback(height, not presentation.is_empty())

	if sim.stage == sim.READY:
		var r: Rect2 = Rect2(width * 0.5 - 196, height * 0.39 - 65, 392, 129)
		_card(r, 0.93)
		_text(r.position + Vector2(24, 37), "START SMALL. END HUGE.", 23)
		_text(r.position + Vector2(24, 66), "Swallow small objects. Grow into the city.", 14, MUTED)
		_text(r.position + Vector2(24, 103), "MOVE TO BEGIN  /  the timer starts with you", 13, MINT)
	elif sim.stage == sim.DRAINING:
		_text(Vector2(width * 0.5 - 94, height * 0.40), "FINISHING CAPTURES...", 15)
	elif sim.stage == sim.FINISHED:
		_draw_result()
	elif game.paused:
		_card(Rect2(width * 0.5 - 141, height * 0.39 - 35, 282, 90))
		_text(Vector2(width * 0.5 - 102, height * 0.39), "PAUSED / INSPECT SCALE", 18)
		_text(Vector2(width * 0.5 - 104, height * 0.39 + 27), "SPACE resume   . single physics step", 12, MUTED)

	# Tiny screen-space locator remains visible when tall buildings occlude the hole.
	if player["alive"] and sim.stage != sim.FINISHED:
		var on_screen: Vector2 = game.camera.unproject_position(player["position"] + Vector3(0, 0.08, 0))
		draw_circle(on_screen, 2.2, MINT)
		if game.show_proxies:
			_text(on_screen + Vector2(10, -10), "G%d / %.2fu" % [tier, float(player["diameter"])], 12, INK)
	if toast_left > 0.0:
		_card(Rect2(width * 0.5 - 255, 120, 510, 40), 0.93)
		_text(Vector2(width * 0.5 - 235, 146), toast, 13, MINT)
	if pulse > 0.0:
		var flash: Color = Color(MINT, pulse * 0.05)
		draw_rect(Rect2(Vector2.ZERO, size), flash)

func _draw_capture_feedback(height: float, styled: bool) -> void:
	var feedback: Dictionary = game.capture_feedback
	if feedback.is_empty():
		return
	var reason: String = str(feedback.get("reason", ""))
	var message: String = ""
	var accent: Color = Color("f2bf8a")
	match reason:
		"size": message = "Grow to %.2f m" % (ceilf(float(feedback["required_diameter"]) * 100.0) / 100.0)
		"center": message = "Move over the center"
		"support": message = "Swallow the support first"
		"falling": message = "Let it fall into the opening"
		"tier": message = "Reach the next growth stage"
		"capturing":
			message = "Swallowing"
			accent = MINT
	if message.is_empty():
		return
	var top: float = height - (151.0 if styled else 190.0)
	_card(Rect2(24, top, 270, 32), 0.86)
	_text(Vector2(39, top + 21), message, 12, accent)
	# A small positive ring means actual capture. An outlined diamond locates the
	# blocked target; neither follows the material's screen-space occlusion fade.
	var target: Vector3 = feedback["position"]
	if reason == "support" and feedback.get("root_support") != null:
		var support: Dictionary = game.sim.item(str(feedback["root_support"]))
		if not support.is_empty():
			target = support["position"]
	target.y = 0.09
	if game.camera.is_position_behind(target):
		return
	var p: Vector2 = game.camera.unproject_position(target)
	if p.x < 20 or p.x > size.x - 20 or p.y < 110 or p.y > size.y - 160:
		return
	if reason == "capturing":
		draw_arc(p, 8, 0, TAU, 20, accent, 2.0, true)
	else:
		draw_polyline(PackedVector2Array([p+Vector2(0,-6),p+Vector2(6,0),p+Vector2(0,6),p+Vector2(-6,0),p+Vector2(0,-6)]), accent, 1.5, true)

func _draw_presentation(presentation: Dictionary, player: Dictionary, width: float, height: float) -> void:
	var sim = game.sim
	var rgb: Array = presentation.get("accent", [0.98, 0.76, 0.31])
	var accent := Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
	_card(Rect2(24, 20, 252, 62), 0.91)
	_text(Vector2(40, 47), str(presentation.get("title", "HOLE PARK")), 21, accent)
	var mode := "SWALLOW · GROW · EXPLORE"
	if sim.holes.size() > 1:
		mode = "RIVAL / EXPERIMENTAL"
	if sim.assisted_run:
		mode = "LAB / ASSISTED RUN"
	if sim.route_mode > 0:
		mode = "AUTO ROUTE / NOT A HUMAN TEST"
	_text(Vector2(40, 68), mode, 10, MUTED)
	_card(Rect2(width * 0.5 - 52, 20, 104, 62), 0.91)
	var remaining: int = int(ceil(maxf(0.0, game.tuning.round_seconds - sim.elapsed)))
	_text(Vector2(width * 0.5 - 35, 50), "%02d:%02d" % [remaining / 60, remaining % 60], 27, accent)
	_text(Vector2(width * 0.5 - 31, 69), "FREE LAB" if sim.lab_unlimited else "REMAINING", 10, MUTED)
	_card(Rect2(width - 234, 20, 210, 62), 0.91)
	_text(Vector2(width - 218, 49), "%04d" % int(player["score"]), 26)
	_text(Vector2(width - 138, 47), "/ %d" % int(sim.config["summary"]["score_total"]), 12, MUTED)
	_text(Vector2(width - 218, 69), "%d eaten   ·   %d / 3 landmarks" % [int(player["count"]), int(player["landmarks"])], 11, accent)
	_card(Rect2(24, height - 108, 240, 64), 0.91)
	_text(Vector2(40, height - 82), "G%d" % sim.effective_tier(0), 21, accent)
	_text(Vector2(85, height - 84), "HOLE  %.2f m" % float(player["diameter"]), 12)
	var thresholds: Array = sim.config["recipe"]["growth_thresholds_cumulative"]
	var lower := int(thresholds[int(player["tier"])])
	var upper := int(thresholds[mini(int(player["tier"]) + 1, 5)])
	if int(player["tier"]) == 5 and game.tuning.continuous_growth:
		upper = int(sim.config["recipe"].get("continuous_growth_tail_score", 1000))
	var progress := clampf(float(int(player["growth"]) - lower) / maxf(1.0, float(upper-lower)), 0, 1)
	draw_rect(Rect2(40, height - 70, 208, 4), Color("31464b"))
	draw_rect(Rect2(40, height - 70, 208 * progress, 4), accent)
	_text(Vector2(40, height - 52), "%d / %d growth" % [int(player["growth"]), upper], 10, MUTED)
	_card(Rect2(width * 0.5 - 262, height - 36, 524, 24), 0.80)
	_text(Vector2(width * 0.5 - 248, height - 20), "WASD / DRAG move   R restart   H character   SPACE pause   M sound   F1 tools", 11)
	if game.overview:
		_draw_minimap(Rect2(width - 190, height - 184, 166, 140))

func _draw_minimap(rect: Rect2) -> void:
	_card(rect, 0.92)
	_text(rect.position + Vector2(12, 20), "LAND / WATER / FOOD", 10, MUTED)
	var content: Rect2 = Rect2(rect.position + Vector2(12, 30), rect.size - Vector2(24, 42))
	draw_rect(content, Color("25566b"))
	var land_points: PackedVector2Array = PackedVector2Array()
	for pair in game.sim.config["map"]["land_polygon_xz"]:
		land_points.append(content.position + Vector2((float(pair[0])+22.0)/44.0,(float(pair[1])+18.0)/36.0)*content.size)
	draw_colored_polygon(land_points, Color("3c4c52"))
	var outline: PackedVector2Array = land_points.duplicate()
	outline.append(land_points[0])
	draw_polyline(outline, Color("a9b7ac"), 1.0, true)
	for o in game.sim.objects:
		if int(o["state"]) == game.Simulation.CONSUMED:
			continue
		var position: Vector3 = o["position"]
		var p: Vector2 = content.position + Vector2((position.x + 22.0) / 44.0, (position.z + 18.0) / 36.0) * content.size
		var color: Color = Color("677a80")
		if int(o["state"]) == game.Simulation.LOCKED:
			color = Color("c0a078")
		elif game.sim.is_collectible(o):
			color = MINT
		var radius: float = 2.6 if game.sim.gameplay_family(o) == "landmark" else 1.25
		draw_circle(p, radius, color)
	for h in game.sim.holes:
		if not h["alive"]:
			continue
		var position: Vector3 = h["position"]
		var p: Vector2 = content.position + Vector2((position.x + 22.0) / 44.0, (position.z + 18.0) / 36.0) * content.size
		draw_arc(p, maxf(3.5, float(h["diameter"]) * content.size.x / 88.0), 0.0, TAU, 32, MINT if int(h["id"]) == 0 else Color("ef9983"), 1.4, true)

func _draw_inspection(rect: Rect2, o: Dictionary) -> void:
	_card(rect)
	var a: Dictionary = o["definition"]
	_text(rect.position + Vector2(14, 23), str(o["id"]), 13, WHITE)
	_text(rect.position + Vector2(14, 46), "Fit circle %.2fu  / class G%d / reward %d" % [game.sim.fit_span(o), int(a["min_tier"]), int(a["score"])], 12, MUTED)
	var status: String = game.Simulation.STATE_NAMES[int(o["state"])]
	status += " / FIT" if game.sim.can_fit(o) else " / TOO LARGE"
	_text(rect.position + Vector2(14, 70), status, 12, MINT)
	_text(rect.position + Vector2(14, 87), "K resets this assembly in lab mode", 10, MUTED)

func _draw_result() -> void:
	var h: Dictionary = game.sim.holes[0]
	var rect: Rect2 = Rect2(size.x * 0.5 - 218, size.y * 0.5 - 180, 436, 332)
	_card(rect, 0.98)
	var title: String = "A BIGGER APPETITE."
	if int(h["landmarks"]) > 0:
		title = "LANDMARK SWALLOWED."
	if game.sim.result_reason == "EATEN":
		title = "THE RIVAL GOT YOU."
	_text(rect.position + Vector2(24, 42), title, 22, MINT)
	_text(rect.position + Vector2(24, 90), "%04d" % int(h["score"]), 40)
	_text(rect.position + Vector2(142, 88), "/ %d world points" % int(game.sim.config["summary"]["score_total"]), 14, MUTED)
	_text(rect.position + Vector2(24, 127), "%d objects  /  G%d  /  %d landmarks" % [int(h["count"]), int(h["tier"]), int(h["landmarks"])], 15)
	_text(rect.position + Vector2(24, 163), "GROWTH SPLITS", 11, MUTED)
	var line: String = ""
	for split in h["levels"]:
		if int(split["tier"]) > 0:
			line += "G%d %.1fs   " % [int(split["tier"]), float(split["time"])]
	_text(rect.position + Vector2(24, 185), line if not line.is_empty() else "No level-up yet. Follow the small-object rows.", 12)
	_text(rect.position + Vector2(24, 216), "Assisted / tuning run: not a baseline result." if game.sim.assisted_run else "Try the other route. Keep the same parameters.", 12, MUTED)
	_text(rect.position + Vector2(24, 239), "Run telemetry is saved locally at the end of each round.", 11, MUTED)

func notify(message: String, seconds: float = 2.8) -> void:
	toast = message
	toast_left = seconds

func _build_panel() -> void:
	lab_panel = PanelContainer.new()
	add_child(lab_panel)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(INK, 0.98)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	lab_panel.add_theme_stylebox_override("panel", style)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lab_panel.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	scroll.add_child(box)
	_label(box, "SCALE / FEEL CONTROLS", 17, MINT)
	_label(box, "Changes are live. R keeps current tuning.", 11, MUTED)
	_add_slider(box, "move_speed", "Move speed", 1.0, 14.0, 0.1)
	_add_slider(box, "acceleration", "Acceleration", 4.0, 100.0, 1.0)
	_add_slider(box, "braking", "Braking", 4.0, 120.0, 1.0)
	_add_slider(box, "diameter_scale", "Diameter multiplier", 0.65, 1.5, 0.01)
	_add_slider(box, "fit_margin", "Object-fit margin", 0.6, 1.15, 0.01)
	_add_slider(box, "shore_margin", "Shore margin beyond hole radius", 0.0, 0.60, 0.01)
	_add_slider(box, "capture_factor", "Capture radius factor", 0.45, 1.4, 0.01)
	_add_slider(box, "swallow_time_scale", "Swallow duration multiplier", 0.4, 2.5, 0.05)
	_add_slider(box, "growth_blend", "Growth smoothing (seconds)", 0.0, 0.65, 0.01)
	_add_slider(box, "joystick_radius", "Drag full-speed distance (px)", 35.0, 110.0, 1.0)
	_add_slider(box, "camera_scale", "Camera distance multiplier", 0.7, 1.6, 0.05)
	_add_slider(box, "camera_fov", "Perspective FOV (degrees)", 38.0, 70.0, 1.0)
	_add_slider(box, "camera_pitch", "Camera pitch (degrees)", 38.0, 72.0, 1.0)
	_add_slider(box, "camera_lookahead", "Movement look-ahead (s)", 0.0, 0.35, 0.01)
	_add_slider(box, "camera_lag", "Follow smoothing (seconds)", 0.04, 0.30, 0.01)
	_add_slider(box, "sfx_volume", "SFX volume", 0.0, 1.0, 0.05)
	_button(box, "Test sound effects [V]", "test_sound")
	_button(box, "Review map [TAB in tools]", "camera_toggle")
	_button(box, "Continuous / stepped growth (A-B)", "growth_toggle")
	_add_slider(box, "round_seconds", "Round seconds", 30.0, 120.0, 5.0)
	_button(box, "Toggle legacy tier gate (default OFF)", "geometry_gate")
	_label(box, "FIX SIZE / NO FREE GROWTH POINTS", 11, MINT)
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	for tier in range(6):
		_button(row, "G%d" % tier, "size:%d" % tier)
	_button(box, "Return to earned size", "size:-1")
	_label(box, "LAB PRESETS / RESET + TELEPORT", 11, MINT)
	_button(box, "A / Donut corner + first bites", "lab:0")
	_button(box, "B / Boba street + long objects", "lab:1")
	_button(box, "D / Market tables + cargo stacks", "lab:2")
	_button(box, "F / North independent shop units", "lab:3")
	_button(box, "C / Giant duck + landmark scale", "lab:4")
	_button(box, "E / Water boundary + giant radius", "lab:5")
	_button(box, "Unlimited clock: toggle", "unlimited")
	_button(box, "Proxies: toggle [G]", "proxies")
	_button(box, "Rival mode: restart [B]", "rival")
	_button(box, "Auto-route WEST / assisted", "route:1")
	_button(box, "Auto-route EAST / assisted", "route:2")
	_button(box, "Stop auto-route / manual input", "route:0")
	_button(box, "Save tuning locally [F5]", "save_tuning")
	_button(box, "Restore baseline + restart [F6]", "baseline")
	_button(box, "Export current run [F8]", "export")
	_button(box, "Open local telemetry folder", "open_logs")
	_label(box, "Green: collectible  /  Amber: support-locked\nSlate: size-blocked. Blue ring: capture radius.\nGrid = 1 unit. Cyan safe line includes radius + shore gap.\nScripted sinking + release. No full rigid-body sim.", 11, MUTED)

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _add_slider(parent: VBoxContainer, key: String, title: String, low: float, high: float, step: float) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var label: Label = _label(row, title, 12, WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label: Label = _label(row, "%.2f" % float(game.tuning.get(key)), 12, MINT)
	value_labels[key] = value_label
	var slider: HSlider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = float(game.tuning.get(key))
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size.y = 20
	slider.value_changed.connect(_slider_changed.bind(key))
	parent.add_child(slider)
	sliders[key] = slider

func _slider_changed(value: float, key: String) -> void:
	value_labels[key].text = "%.2f" % value
	game.change_tuning(key, value)

func refresh_values() -> void:
	for key in sliders:
		sliders[key].set_value_no_signal(float(game.tuning.get(key)))
		value_labels[key].text = "%.2f" % float(game.tuning.get(key))

func _button(parent: Node, title: String, action: String) -> Button:
	var button: Button = Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 28
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(Callable(game, "command").bind(action))
	parent.add_child(button)
	return button

func _build_result_buttons() -> void:
	result_buttons = HBoxContainer.new()
	result_buttons.add_theme_constant_override("separation", 12)
	add_child(result_buttons)
	_button(result_buttons, " AGAIN [R] ", "restart")
	_button(result_buttons, " EXPORT RUN ", "export")
	_button(result_buttons, " SCALE LAB ", "lab:2")
	result_buttons.visible = false
