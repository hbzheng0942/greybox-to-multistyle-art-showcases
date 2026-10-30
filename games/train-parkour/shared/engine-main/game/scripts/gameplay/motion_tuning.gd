class_name MotionTuning
extends Resource
## Metres and seconds. Change these values through the shared .tres resource.

@export var speed_presets: PackedFloat32Array = [40.0, 60.0, 80.0]
@export var acceleration: float = 16.0
@export var braking: float = 52.0
@export var brake_speed: float = 28.0
@export var lane_spacing: float = 4.4
@export var lane_change_seconds: float = 0.24
@export var gate_half_width: float = 1.3
@export var perfect_half_width: float = 0.48
@export var miss_speed_loss: float = 15.0
@export var start_distance: float = 24.0
@export var camera_distance: float = 23.0
@export var camera_height: float = 8.4
@export var camera_lookahead: float = 48.0
@export var camera_response: float = 12.0
@export var fov_slow: float = 72.0
@export var fov_fast: float = 88.0
@export var gravity: float = 24.0
@export var ollie_velocity: float = 13.0
@export var air_acceleration: float = 18.0
@export var air_drag: float = 4.0
@export var air_lateral_limit: float = 7.0
@export var trick_duration: float = 0.66
@export var landing_capture_width: float = 1.6
@export var jump_buffer_seconds: float = 0.14
