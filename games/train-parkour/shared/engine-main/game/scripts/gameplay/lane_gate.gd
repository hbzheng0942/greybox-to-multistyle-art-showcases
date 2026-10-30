class_name LaneGate
extends Node3D

var distance: float = 0.0
var lane: int = 0
var resolved: bool = false
var frame_material: StandardMaterial3D


func build(at_distance: float, target_lane: int, pose: Transform3D) -> void:
	distance = at_distance
	lane = target_lane
	global_transform = pose
	frame_material = StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.13, 0.95, 0.85)
	frame_material.emission_enabled = true
	frame_material.emission = Color(0.06, 0.55, 0.45)
	frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var outline := StandardMaterial3D.new()
	outline.albedo_color = Color(0.025, 0.08, 0.10)
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_piece(Vector3(-2.05, 2.8, -0.18), Vector3(0.48, 5.85, 0.2), outline)
	_piece(Vector3(2.05, 2.8, -0.18), Vector3(0.48, 5.85, 0.2), outline)
	_piece(Vector3(0, 5.6, -0.18), Vector3(4.58, 0.48, 0.2), outline)
	_piece(Vector3(-2.05, 2.8, 0), Vector3(0.25, 5.6, 0.25))
	_piece(Vector3(2.05, 2.8, 0), Vector3(0.25, 5.6, 0.25))
	_piece(Vector3(0, 5.6, 0), Vector3(4.25, 0.25, 0.25))
	_piece(Vector3(0, 0.16, 0), Vector3(4.0, 0.06, 1.2))
	_piece(Vector3(0, 6.3, 0), Vector3(0.6, 0.6, 0.22))


func resolve(hit: bool) -> void:
	resolved = true
	frame_material.albedo_color = Color(1.0, 0.8, 0.32) if hit else Color(1.0, 0.24, 0.22)


func reset_gate() -> void:
	resolved = false
	frame_material.albedo_color = Color(0.13, 0.95, 0.85)


func _piece(at: Vector3, size: Vector3, material: Material = null) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = frame_material if material == null else material
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.position = at
	add_child(piece)
