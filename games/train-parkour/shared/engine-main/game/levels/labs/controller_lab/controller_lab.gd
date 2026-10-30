extends Node3D
## Deterministic greybox built from the same Curve3D used by the train.

const CHUNK_LENGTH: float = 192.0
const STEP: float = 6.0
const TUNING: MotionTuning = preload("res://resources/tuning/motion_default.tres")
const GATE_PATTERN: Array[int] = [0, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0]
var gates: Array[LaneGate] = []
@onready var route: RailRoute = $RouteRoot/MainRoute
@onready var presentation: Node3D = $PresentationRoot
@onready var environment_root: Node3D = $EnvironmentRoot


func _ready() -> void:
	_build_track()
	_build_gates()
	$PlayerSpawn.global_transform = route.pose_at(24.0)


func _build_track() -> void:
	var deck := _material(Color(0.22, 0.27, 0.32))
	var rail := _material(Color(0.72, 0.78, 0.8))
	var sleeper := _material(Color(0.13, 0.17, 0.2))
	var posts := _material(Color(0.88, 0.55, 0.23))
	var structures := _material(Color(0.29, 0.35, 0.40))
	for index in range(ceili(route.length / CHUNK_LENGTH)):
		var start := index * CHUNK_LENGTH
		var end := minf(start + CHUNK_LENGTH, route.length)
		var chunk := Node3D.new()
		chunk.name = "TrackChunk_%03d" % index
		presentation.add_child(chunk)
		chunk.position = _level_pose((start + end) * 0.5).origin
		var decks: Array[Transform3D] = []
		var rails: Array[Transform3D] = []
		var ties: Array[Transform3D] = []
		var markers: Array[Transform3D] = []
		var supports: Array[Transform3D] = []
		var frames: Array[Transform3D] = []
		var s := start
		while s < end:
			var a := s
			var b := minf(s + STEP, end)
			if route.stunts != null:
				if a < route.stunts.gap_start:
					b = minf(b, route.stunts.gap_start)
				elif a < route.stunts.gap_end:
					a = maxf(a, route.stunts.gap_end)
			if a >= b:
				s += STEP
				continue
			var middle := (a + b) * 0.5
			var lanes := route.lanes_at(middle)
			var center := lanes[0] * TUNING.lane_spacing if lanes.size() == 1 else 0.0
			var width := 5.4 if lanes.size() == 1 else 16.6
			var pose := _level_pose(middle)
			pose.origin -= chunk.position
			var span := (b - a + (0.0 if route.stunts != null and (b == route.stunts.gap_start or a == route.stunts.gap_end) else 0.4)) / (STEP + 0.4)
			decks.append(pose.translated_local(Vector3(center, -0.5, 0)).scaled_local(Vector3(width / 16.6, 1, span)))
			for lane in lanes:
				for side in [-1, 1]:
					rails.append(pose.translated_local(Vector3(lane * TUNING.lane_spacing + side * 0.72, 0.04, 0)).scaled_local(Vector3(1, 1, span)))
				ties.append(pose.translated_local(Vector3(lane * TUNING.lane_spacing, -0.08, 0)))
			if int(s) % 18 == 0:
				for side in [-1, 1]:
					markers.append(pose.translated_local(Vector3(center + side * (width * 0.5 - 0.3), 1.4, 0)))
			if int(s) % 48 == 0:
				var level_center := _level_pose(s).translated_local(Vector3(center, 0, 0)).origin
				var height := level_center.y + 25.0
				supports.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.0, height, 2.0)), level_center - Vector3(0, height * 0.5, 0) - chunk.position))
			# Narrow portals provide optic flow without blocking the camera corridor.
			var ratio := s / route.length
			if route.stunts == null and int(s) % 48 == 0 and ((ratio > 0.14 and ratio < 0.26) or (ratio > 0.63 and ratio < 0.77)):
				for side in [-1, 1]:
					frames.append(pose.translated_local(Vector3(side * 10, 7, 0)).scaled_local(Vector3(1.2, 14, 1.2)))
				frames.append(pose.translated_local(Vector3(0, 14, 0)).scaled_local(Vector3(21.0, 1.0, 1.2)))
			s += STEP
		_batch(chunk, "Deck", Vector3(16.6, 0.7, STEP + 0.4), deck, decks)
		_batch(chunk, "Rails", Vector3(0.14, 0.18, STEP + 0.4), rail, rails)
		_batch(chunk, "Sleepers", Vector3(2.25, 0.15, 0.45), sleeper, ties)
		_batch(chunk, "SpeedMarkers", Vector3(0.22, 2.8, 0.4), posts, markers)
		_batch(chunk, "Supports", Vector3.ONE, structures, supports)
		_batch(chunk, "Portals", Vector3.ONE, structures, frames)
	_build_horizon(structures)


func _build_horizon(material: Material) -> void:
	var ground := MeshInstance3D.new()
	ground.name = "DistantGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 11000)
	plane.material = _material(Color(0.19, 0.26, 0.28))
	ground.mesh = plane
	ground.position = Vector3(0, -25, -2500)
	environment_root.add_child(ground)
	var buildings: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 220922
	for i in range(92):
		var s := i * route.length / 92.0
		var pose := _level_pose(s)
		var side := -1.0 if i % 2 == 0 else 1.0
		var height := rng.randf_range(30, 170)
		var position := pose.origin + pose.basis.x * side * rng.randf_range(100, 320)
		position.y = height * 0.5 - 25.0
		buildings.append(Transform3D(Basis.IDENTITY.scaled(Vector3(rng.randf_range(24, 60), height, rng.randf_range(30, 80))), position))
	_batch(environment_root, "ScaleSkyline", Vector3.ONE, material, buildings, 0.0)


func _build_gates() -> void:
	var index := 0
	var s := 230.0
	while s < route.length - 150.0:
		var gate := LaneGate.new()
		gate.name = "LaneGate_%02d" % index
		$GameplayRoot.add_child(gate)
		var lane := GATE_PATTERN[index % GATE_PATTERN.size()]
		gate.build(s, lane, route.pose_at(s, lane * TUNING.lane_spacing))
		gates.append(gate)
		index += 1
		s += 142.0 if index < 6 else 126.0


func _batch(parent: Node3D, label: String, size: Vector3, material: Material, poses: Array[Transform3D], range_end: float = 1100.0) -> void:
	if poses.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = poses.size()
	for i in poses.size():
		batch.set_instance_transform(i, poses[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = batch
	instance.visibility_range_end = range_end
	parent.add_child(instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	return material


func _level_pose(distance: float) -> Transform3D:
	return global_transform.affine_inverse() * route.pose_at(distance)
