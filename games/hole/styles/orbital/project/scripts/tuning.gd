extends Resource
## All dimensions are Godot world units. Diameter is NEVER radius.
## Definition data only; no mutable object/run state belongs in this resource.

@export_category("Movement")
@export_range(1.0, 14.0, 0.1) var move_speed: float = 7.2
@export_range(4.0, 100.0, 0.5) var acceleration: float = 48.0
@export_range(4.0, 120.0, 0.5) var braking: float = 64.0
@export_category("Waterfront boundary")
@export_range(0.0, 0.60, 0.01) var shore_margin: float = 0.18
@export_category("Scale and capture")
@export_range(0.65, 1.5, 0.01) var diameter_scale: float = 1.0
@export_range(0.6, 1.15, 0.01) var fit_margin: float = 0.85
@export_range(0.45, 1.4, 0.01) var capture_factor: float = 0.9
@export var enforce_tier_gate: bool = false
@export var continuous_growth: bool = true
@export_range(0.4, 2.5, 0.05) var swallow_time_scale: float = 1.0
@export_range(0.0, 0.65, 0.01) var growth_blend: float = 0.12
@export_category("Session and camera")
@export_range(30.0, 120.0, 5.0) var round_seconds: float = 60.0
@export_range(0.7, 1.6, 0.05) var camera_scale: float = 1.0
@export_range(38.0, 70.0, 1.0) var camera_fov: float = 52.0
@export_range(38.0, 72.0, 1.0) var camera_pitch: float = 52.0
@export_range(0.0, 0.35, 0.01) var camera_lookahead: float = 0.16
@export_range(0.04, 0.30, 0.01) var camera_lag: float = 0.09
@export_range(35.0, 110.0, 1.0) var joystick_radius: float = 55.0
@export var sound_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var sfx_volume: float = 0.8
const SAVE_PATH = "user://hole_waterfront_tuning_v03.json"

const KEYS = ["shore_margin", "move_speed", "acceleration", "braking", "diameter_scale", "fit_margin", "capture_factor", "enforce_tier_gate", "swallow_time_scale", "growth_blend", "continuous_growth", "round_seconds", "camera_scale", "camera_fov", "camera_pitch", "camera_lookahead", "camera_lag", "joystick_radius", "sound_enabled", "sfx_volume"]

func snapshot() -> Dictionary:
	var output: Dictionary = {}
	for key in KEYS:
		output[key] = get(key)
	return output

func apply_values(values: Dictionary) -> void:
	for key in KEYS:
		if not values.has(key):
			continue
		if key in ["enforce_tier_gate", "continuous_growth", "sound_enabled"]:
			if typeof(values[key]) == TYPE_BOOL:
				set(key, values[key])
		elif typeof(values[key]) in [TYPE_INT, TYPE_FLOAT]:
			var number: float = float(values[key])
			if is_finite(number):
				set(key, number)
	shore_margin = clampf(shore_margin, 0.0, 0.60)
	move_speed = clampf(move_speed, 1.0, 14.0)
	acceleration = clampf(acceleration, 4.0, 100.0)
	braking = clampf(braking, 4.0, 120.0)
	diameter_scale = clampf(diameter_scale, 0.65, 1.5)
	fit_margin = clampf(fit_margin, 0.6, 1.15)
	capture_factor = clampf(capture_factor, 0.45, 1.4)
	swallow_time_scale = clampf(swallow_time_scale, 0.4, 2.5)
	growth_blend = clampf(growth_blend, 0.0, 0.65)
	round_seconds = clampf(round_seconds, 30.0, 120.0)
	camera_scale = clampf(camera_scale, 0.7, 1.6)
	camera_fov = clampf(camera_fov, 38.0, 70.0)
	camera_pitch = clampf(camera_pitch, 38.0, 72.0)
	camera_lookahead = clampf(camera_lookahead, 0.0, 0.35)
	camera_lag = clampf(camera_lag, 0.04, 0.30)
	joystick_radius = clampf(joystick_radius, 35.0, 110.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)

func save_local() -> Error:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot(), "\t"))
	return OK

func load_local() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		apply_values(parsed)
