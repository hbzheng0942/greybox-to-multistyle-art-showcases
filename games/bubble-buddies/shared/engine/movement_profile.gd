class_name MovementProfile
extends RefCounted
## Shared runtime and spatial-audit tuning. Held towels keep empty-hand speed;
## only carrying a pet uses CARRY_SPEED. Horizontal input is applied immediately.

const PROFILE_ID := "salon-fast-screen-walk-v2"
const EMPTY_SPEED := 6.0
const CARRY_SPEED := 5.4
const PUDDLE_MULTIPLIER := 0.78


static func snapshot() -> Dictionary:
	return {"id": PROFILE_ID, "empty_speed_meters_per_second": EMPTY_SPEED,
		"pet_carry_speed_meters_per_second": CARRY_SPEED,
		"puddle_multiplier": PUDDLE_MULTIPLIER, "towels_use_empty_speed": true,
		"horizontal_acceleration": "immediate", "horizontal_release": "immediate", "direction_frame":"screen_aligned"}
