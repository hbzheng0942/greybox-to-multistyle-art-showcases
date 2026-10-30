class_name FlowCourse
extends Resource
## Distances in baked route metres. Shared by gameplay, geometry, cues and QA.

@export var course_id: String = "flow_m14_v1"
@export var obstacles: Array[Dictionary] = [
	{"s": 175.0, "lanes": [0], "height": 7.0},
	{"s": 255.0, "lanes": [-1, 1], "height": 7.0},
	{"s": 550.0, "lanes": [0, 1], "height": 1.7},
	{"s": 640.0, "lanes": [-1], "height": 7.0},
	{"s": 975.0, "lanes": [0], "height": 7.0},
	{"s": 1120.0, "lanes": [1], "height": 1.7},
	{"s": 1470.0, "lanes": [-1, 1], "height": 7.0},
	{"s": 1740.0, "lanes": [0, 1], "height": 7.0},
	{"s": 1835.0, "lanes": [-1, 0], "height": 7.0},
]
@export var turns: Array[Dictionary] = [
	{"start": 300.0, "end": 465.0, "direction": 1},
	{"start": 1250.0, "end": 1405.0, "direction": -1},
]
@export var jumps: Array[Dictionary] = [
	{"start": 775.0, "end": 885.0, "window": 76.0, "land_lane": 0},
	{"start": 1540.0, "end": 1640.0, "window": 76.0, "land_lane": 1},
]
@export var fork_start: float = 1040.0
@export var fork_end: float = 1180.0
@export var checkpoints: PackedFloat32Array = [24, 285, 680, 1000, 1210, 1470, 1670]


func jump_near(s: float) -> Dictionary:
	for jump in jumps:
		if s >= jump.start - jump.window - 30.0 and s < jump.end + 45.0:
			return jump
	return {}


func turn_at(s: float) -> Dictionary:
	for turn in turns:
		if s >= turn.start and s < turn.end:
			return turn
	return {}


func deck_width(s: float, lane: int) -> float:
	return 2.9 if s >= fork_start and s < fork_end and lane == 1 else 4.35


func support_width(s: float, lane: int) -> float:
	# Centre tolerance after reserving wheel/support clearance from each edge.
	return deck_width(s, lane) * 0.5 - 0.55
