extends RefCounted
## Optional festival presentation. The underlying H07 remains independently editable.
const Base = preload("res://themes/halloween_07/continuous/continuous_presentation.gd")
const Festival = preload("res://themes/halloween_festival/festival_layer.gd")
var base_builder = Base.new()
var festival: Node3D
var light_controller: Node3D

func build(session: Node3D) -> Node3D:
	var world: Node3D = base_builder.build(session)
	light_controller = base_builder.light_controller
	festival = Festival.new()
	festival.name = "FestivalLayer"
	festival.set_meta("scene_id", "station")
	festival.set_meta("asset_id", "h07_authored_festival")
	festival.set_meta("instance_id", "h07_festival_v2")
	world.add_child(festival)
	festival.setup(session)
	world.set_meta("festival_scope", "Authored animated presentation; no gameplay collision or camera changes")
	return world

func sync_view(camera: Camera3D) -> void:
	base_builder.sync_view(camera)
	if is_instance_valid(festival): festival.sync_sky(camera)
