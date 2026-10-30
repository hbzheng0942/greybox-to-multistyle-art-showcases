extends RefCounted
## Optional authored art sample. Does not alter gameplay or camera transforms.
const ArtMaterials = preload("res://themes/pixel_skyline_v2/pixel_art_materials.gd")

static func station_material(source: BaseMaterial3D, mesh_name: String) -> ShaderMaterial:
	if not enabled() or source == null or not (mesh_name.begins_with("station_") if expanded() else (mesh_name.begins_with("station_01_") or mesh_name.begins_with("station_02_"))):
		return null
	var colors := {"V2_steel": "354f7e", "V2_trim": "7797c9", "V2_dark": "111c36",
		"V2_concrete": "354967", "V2_glass": "23445f", "V2_amber": "ffb94f", "V2_cyan": "50bbd3"}
	if not colors.has(source.resource_name):
		return null
	var emissive := source.resource_name == "V2_amber" or source.resource_name == "V2_cyan"
	var c := Color(colors[source.resource_name])
	return ArtMaterials.solid(c, "cartoon_station_" + source.resource_name,
		c if emissive else Color.BLACK, 0.8 if emissive else 0.0)

static func enabled() -> bool:
	return "--art-shape=cartoon" in OS.get_cmdline_user_args() or expanded()

static func expanded() -> bool:
	return "--art-shape=continuous" in OS.get_cmdline_user_args() or str(ProjectSettings.get_setting("showcase/art_shape", "baseline")) == "continuous"

static func contains_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
		return true
	for child: Node in node.get_children():
		if contains_collision(child):
			return true
	return false

static func install(world: Node3D) -> Dictionary:
	if not enabled():
		return {"mode": "baseline", "replacement_count": 0}
	var path := "res://themes/pixel_skyline_v2/assets/cartoon_station.glb"
	if not ResourceLoader.exists(path, "PackedScene"):
		push_error("Cartoon station trial requires its authored G1 assembly.")
		return {"mode": "cartoon", "error": "missing_station"}
	var packed := load(path) as PackedScene
	var sample := packed.instantiate() as Node3D if packed != null else null
	if sample == null or not sample.transform.is_equal_approx(Transform3D.IDENTITY) or contains_collision(sample):
		if sample != null:
			sample.free()
		return {"mode": "cartoon", "error": "invalid_station_contract"}
	var extension: Node3D = null
	if expanded():
		var extension_path := "res://themes/pixel_skyline_v2/assets/cartoon_concourse.glb"
		var extension_scene := load(extension_path) as PackedScene if ResourceLoader.exists(extension_path, "PackedScene") else null
		extension = extension_scene.instantiate() as Node3D if extension_scene != null else null
		if extension == null or not extension.transform.is_equal_approx(Transform3D.IDENTITY) or contains_collision(extension):
			if extension != null: extension.free()
			sample.free()
			return {"mode": "continuous", "error": "invalid_concourse_contract"}
	var replacement_ids := ["canyon_city_00", "canyon_city_01"]
	if expanded(): replacement_ids.append_array(["canyon_city_02", "canyon_city_03", "canyon_city_04", "canyon_city_05"])
	var replacements: Array[Node3D] = []
	for id: String in replacement_ids:
		var old := world.find_child(id, true, false) as Node3D
		if old == null:
			if extension != null: extension.free()
			sample.free()
			return {"mode": "cartoon", "error": "missing_replacement:" + id}
		replacements.append(old)
	sample.name = "CartoonStationTrial"
	world.add_child(sample)
	if extension != null:
		extension.name = "CartoonConcourse"
		world.add_child(extension)
	for old: Node3D in replacements:
		old.visible = false
	return {"mode": "continuous" if expanded() else "cartoon", "replacement_count": replacements.size(), "expected_replacements": replacement_ids.size(),
		"source": "art/source/pixel-skyline-v2/cartoon_atelier.blend", "g1_task": "4114400"}
