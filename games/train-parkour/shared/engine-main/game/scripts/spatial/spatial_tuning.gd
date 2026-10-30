class_name SpatialTuning
extends Resource

@export var cruise := PackedFloat32Array([40, 60, 100])
@export var speed_cap := 150.0
@export var traction := 32.0
@export var brake := 52.0
@export var brake_floor := 28.0
@export var coast_drag := 0.5
@export var grade_gravity := 20.0
@export var gravity := 24.0
@export var pad_impulse := 30.0
@export var lane_spacing := 4.4
@export var lane_seconds := 0.24
@export var jump_buffer := 0.18
@export var lateral_grip := 45.0
@export var drift_grip := 100.0
@export var steering_rate := 18.0
@export var steering_limit := 15.0
@export var capture_heading := 30.0
@export var capture_normal_speed := 70.0
@export var capture_lane_width := 1.6
@export var assist_time := 0.0
@export var assist_accel := 0.0
@export var assist_max_error := 0.0
@export var assist_settle_error := 1.5
@export var clean_capture_retention := 0.98
@export var assisted_capture_retention := 0.95
@export var rough_capture_retention := 0.92
@export var soft_contact_loss := 7.0
@export var recovery_seconds := 0.65
