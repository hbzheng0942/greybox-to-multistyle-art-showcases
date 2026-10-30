extends RefCounted
## Immutable, build-local assembly recipes. No theme-name dispatch or gameplay changes.
const Loader = preload("res://scripts/theme_model_loader.gd")
var recipe: Dictionary = {}
var sources: Dictionary = {}
var texture_cache: Dictionary = {}

func _init() -> void:
	if FileAccess.file_exists("res://data/scene_recipe.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/scene_recipe.json"))
		if parsed is Dictionary and parsed.get("schema", "") == "hole_scene_recipe_v1":
			recipe = parsed

func has_asset(id: String) -> bool:
	return recipe.get("assets", {}).has(id)

func _v(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func build(id: String, envelope: Vector3) -> Node3D:
	if not has_asset(id):
		return null
	var baked: String = str(recipe["assets"][id].get("bakedPath", ""))
	if not baked.is_empty():
		return (load(baked) as PackedScene).instantiate() as Node3D
	var root := Node3D.new()
	root.name = "Visual"
	var assembly := Node3D.new()
	assembly.name = "AuthoredAssembly"
	assembly.scale = _v(recipe["assets"][id].get("assemblyScale", [1,1,1]))
	if assembly.scale.x <= 0.0 or assembly.scale.y <= 0.0 or assembly.scale.z <= 0.0:
		assembly.free()
		root.free()
		push_error("Assembly scale must be positive: " + id)
		return null
	# Scale the complete authored assembly about its bottom, then center in the
	# versioned gameplay envelope. G1 and procedural parts cannot drift apart.
	assembly.position.y = -envelope.y * 0.5
	root.add_child(assembly)
	var materials: Array = []
	var triangles: int = 0
	var slots: int = 0
	for part in recipe["assets"][id]["parts"]:
		var path: String = str(part["path"])
		if not sources.has(path):
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			if document.append_from_file(path, state) != OK:
				root.free()
				push_error("Recipe source import failed: " + path)
				return null
			for gltf_mesh in state.get_meshes():
				var imported: ImporterMesh = gltf_mesh.get_mesh()
				if not part.get("disableAutoLod", false): imported.generate_lods(60.0,60.0,[])
			var original: Node3D = document.generate_scene(state) as Node3D
			var scan: Dictionary = {"min":Vector3.INF,"max":-Vector3.INF,"surfaces":0,"uv_surfaces":0,"material_surfaces":0,"textured_surfaces":0,"triangles":0}
			Loader._scan(original,Transform3D.IDENTITY,scan)
			sources[path] = {"original":original,"info":scan}
		var scene: Node3D = sources[path]["original"].duplicate() as Node3D
		var info: Dictionary = sources[path]["info"]
		triangles += int(info["triangles"])
		slots += int(info["surfaces"])
		var transform_root := Node3D.new()
		transform_root.name = str(part.get("name", "Part"))
		transform_root.position = _v(part.get("position", [0,0,0]))
		transform_root.rotation_degrees = _v(part.get("rotationDegrees", [0,0,0]))
		transform_root.scale = _v(part.get("scale", [1,1,1]))
		if part.has("fitSize"):
			var yaw: float = deg_to_rad(float(part.get("fitYawDegrees",0)))
			var fit_info: Dictionary = {"min":Vector3.INF,"max":-Vector3.INF,"surfaces":0,"uv_surfaces":0,"material_surfaces":0,"textured_surfaces":0,"triangles":0}
			Loader._scan(scene,Transform3D(Basis(Vector3.UP,yaw),Vector3.ZERO),fit_info)
			var extent: Vector3 = fit_info["max"]-fit_info["min"]
			var target: Vector3 = _v(part["fitSize"])
			var ratio: float = minf(target.x/extent.x,minf(target.y/extent.y,target.z/extent.z))
			var correction := Vector3.ONE
			var max_correction: float = float(part.get("maxFootprintCorrection",1.0))
			correction.x = minf(max_correction,target.x/(extent.x*ratio))
			correction.z = minf(max_correction,target.z/(extent.z*ratio))
			var scale_axes: Vector3 = Vector3.ONE*ratio*correction
			scene.transform = Transform3D(Basis.IDENTITY.scaled(scale_axes)*Basis(Vector3.UP,yaw),-Vector3((fit_info["min"].x+fit_info["max"].x)*.5,fit_info["min"].y,(fit_info["min"].z+fit_info["max"].z)*.5)*scale_axes)*scene.transform
		if Loader._runtime_materials(scene, materials, part.get("material", {}), texture_cache) != OK:
			scene.free()
			transform_root.free()
			root.free()
			push_error("Recipe material adaptation failed: " + path)
			return null
		transform_root.add_child(scene)
		assembly.add_child(transform_root)
	root.set_meta("asset_id",id)
	root.set_meta("source","approved_recipe_candidate")
	root.set_meta("status","RECIPE_CANDIDATE")
	root.set_meta("triangles",triangles)
	root.set_meta("material_slots",slots)
	root.set_meta("cutaway_materials",materials)
	root.set_meta("approval_id",recipe.get("approvalId",""))
	return root

func clear_sources() -> void:
	for value in sources.values():
		value["original"].free()
	sources.clear()
	texture_cache.clear()
