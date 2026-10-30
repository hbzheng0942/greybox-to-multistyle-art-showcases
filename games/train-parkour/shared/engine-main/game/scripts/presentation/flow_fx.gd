extends Node3D
## Short-lived world-space sparks; no effect mutates the train or camera root.

var train: FlowTrain
var sparks: GPUParticles3D
var boost: GPUParticles3D
var landing: GPUParticles3D
var ring: MeshInstance3D
var ring_time := 0.0
var ring_material: StandardMaterial3D


func _ready() -> void:
	train = get_parent() as FlowTrain
	if DisplayServer.get_name() == "headless": return
	sparks = _emitter(Color(1, 0.67, 0.18), 80, 0.27, 18)
	boost = _emitter(Color(0.25, 0.95, 1), 50, 0.24, 25)
	landing = _emitter(Color(0.85, 1, 1), 40, 0.24, 22)
	landing.one_shot = true
	landing.explosiveness = 1.0
	boost.position.z = 5.5
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.90
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	ring_material = StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = Color(0.65, 1.0, 0.95, 0.85)
	torus.material = ring_material
	ring.mesh = torus
	add_child(ring)
	ring.top_level = true
	ring.visible = false
	train.stunt_event.connect(_event)


func _emitter(color: Color, count: int, lifetime: float, speed: float) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.amount = count
	node.lifetime = lifetime
	node.local_coords = false
	node.emitting = false
	node.visibility_aabb = AABB(Vector3(-40, -30, -60), Vector3(80, 90, 140))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.7)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	node.draw_pass_1 = mesh
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(1.3, 0.1, 4.0)
	process.direction = Vector3(0, 0.35, 1)
	process.spread = 35
	process.initial_velocity_min = speed * 0.6
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, -15, 0)
	node.process_material = process
	add_child(node)
	return node


func _process(delta: float) -> void:
	if sparks == null: return
	sparks.emitting = train.active and (train.state == TrainController.State.DRIFT or train.scrape_time > 0)
	boost.emitting = train.active and train.boost_time > 0 and train.state != TrainController.State.AIR
	if not train.active and train.state != TrainController.State.CRASHED:
		landing.emitting = false
	ring_time = maxf(0, ring_time - delta)
	ring.visible = ring_time > 0
	if ring.visible:
		var phase := 1.0 - ring_time / 0.28
		ring.scale = Vector3.ONE * (1.0 + phase * 7.0)
		ring_material.albedo_color.a = (1.0 - phase) * 0.8


func _event(kind: String, _value: float) -> void:
	if kind in ["PERFECT LANDING", "LANDED", "ROUGH LANDING", "CRASH"]:
		landing.restart()
		if kind != "CRASH":
			ring_time = 0.28
			ring.global_transform = train.route.pose_at(train.distance, train.lateral).translated_local(Vector3(0, 0.25, 0))
