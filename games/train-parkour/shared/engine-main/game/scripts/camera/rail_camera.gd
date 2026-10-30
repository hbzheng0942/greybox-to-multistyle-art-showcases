class_name RailCamera
extends Camera3D

var train: TrainController
var route: RailRoute
var tuning: MotionTuning
var comfort: bool = false
var aim: Vector3 = Vector3.ZERO
var bank: float = 0.0
var flight_blend: float = 0.0
var camera_mode: String = "GROUND"


func configure(target: TrainController, new_route: RailRoute, new_tuning: MotionTuning) -> void:
	train = target
	route = new_route
	tuning = new_tuning
	reset_camera()


func reset_camera() -> void:
	bank = 0.0
	flight_blend = 0.0
	camera_mode = "GROUND"
	_update_pose(1.0, true)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if train != null:
		_update_pose(delta, false)


func _update_pose(delta: float, snap: bool) -> void:
	var pose := route.pose_at(train.distance)
	var behind := route.pose_at(train.distance - tuning.camera_distance)
	var desired := behind.origin + Vector3.UP * tuning.camera_height + pose.basis.x * train.lateral * 0.55
	var look_distance := tuning.camera_lookahead + train.speed * 0.24
	if route is FlowRoute:
		# Road preview grows with actual travel speed, with a stable world horizon.
		look_distance += 12.0
		desired.y += 0.7
	var target := route.pose_at(train.distance + look_distance).origin + Vector3.UP * 1.8
	target += pose.basis.x * train.lateral * 0.18
	var airborne := train.state == TrainController.State.AIR
	flight_blend = move_toward(flight_blend, 1.0 if airborne else 0.0, delta * (5.0 if airborne else 3.8))
	camera_mode = "FLIGHT" if airborne else ("LANDING" if train.landing_impact > 0.0 else ("DRIFT" if train.state == TrainController.State.DRIFT else "GROUND"))
	if train.state == TrainController.State.DRIFT:
		desired -= pose.basis.x * train.drift_direction * 1.6
	if flight_blend > 0.0:
		var flight_position := train.global_position - train.air_forward * (tuning.camera_distance + 5.0) + Vector3.UP * (tuning.camera_height + 3.0)
		var forward_aim := train.global_position + train.air_forward * 27.0 + Vector3.UP * 1.8
		var landing := train.landing_target() + Vector3.UP * 1.2
		if (landing - train.global_position).dot(train.air_forward) < 10.0:
			landing = forward_aim
		var flight_aim := forward_aim.lerp(landing, clampf(0.35 + train.air_time * 0.08, 0.35, 0.6))
		desired = desired.lerp(flight_position, flight_blend)
		target = target.lerp(flight_aim, flight_blend)
	if not comfort:
		desired.y -= train.landing_impact * 0.24
		if train is FlowTrain:
			var flow_train := train as FlowTrain
			desired += pose.basis.x * sin(train.elapsed * 65.0) * flow_train.scrape_time * 0.065
	var response := 1.0 if snap else 1.0 - exp(-tuning.camera_response * delta)
	global_position = desired if snap else global_position.lerp(desired, response)
	aim = target if snap else aim.lerp(target, response)
	look_at(aim, Vector3.UP)
	var bend := pose.basis.z.signed_angle_to(route.pose_at(train.distance + 45.0).basis.z, Vector3.UP)
	var wanted_bank := 0.0 if comfort or airborne else clampf(-bend * 0.22, -0.035, 0.035)
	bank = lerpf(bank, wanted_bank, response)
	rotate_object_local(Vector3.FORWARD, bank)
	var speed_factor := clampf((train.speed - 28.0) / 62.0, 0.0, 1.0)
	var target_fov := 78.0 if comfort else lerpf(tuning.fov_slow, tuning.fov_fast, speed_factor) + flight_blend * 2.0 + minf(train.boost_time, 1.0) * 1.5
	fov = target_fov if snap else lerpf(fov, target_fov, 1.0 - exp(-4.0 * delta))
