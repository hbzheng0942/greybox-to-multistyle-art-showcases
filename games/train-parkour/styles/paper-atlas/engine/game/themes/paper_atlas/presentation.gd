extends RefCounted
## Paper sample only: all route, collision, camera and motion sources stay frozen.
const WORLD = preload("res://themes/paper_atlas/assets/sample_world.glb")
const TRAIN = preload("res://themes/paper_atlas/assets/paper_train.glb")
const HAZARD = preload("res://themes/paper_atlas/assets/paper_hazard.glb")
const PAPER = preload("res://themes/paper_atlas/paper.gdshader")
var materials: Dictionary = {}
var paper_materials: Dictionary = {}

func build(session: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "PaperAtlas"
	root.set_meta("instance_id", "paper_sample")
	root.set_meta("asset_id", "paper_world")
	root.set_meta("scene_id", "station")
	session.add_child(root)
	for key in {"ivory":"eadfc6", "coral":"bd614b", "teal":"235558", "edge":"f4ead2", "ochre":"bb8a33", "cyan":"51b8c2", "dark":"263c46"}:
		var colors = {"ivory":"eadfc6", "coral":"bd614b", "teal":"235558", "edge":"f4ead2", "ochre":"bb8a33", "cyan":"51b8c2", "dark":"263c46"}
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(colors[key])
		mat.roughness = 0.95
		mat.metallic_specular = 0.12
		materials[key] = mat
	var world := WORLD.instantiate()
	root.add_child(world)
	_register(world)
	var geo := session.get_node("Actors/Train/VisualRoot/TrickPivot/Geometry")
	for child in geo.get_children():
		if child is GeometryInstance3D: child.visible = false
	var train := TRAIN.instantiate()
	train.name = "PaperTrain"
	train.set_meta("instance_id", "paper_train")
	train.set_meta("asset_id", "TR01_03")
	train.set_meta("scene_id", "station")
	geo.add_child(train)
	_register(train)
	var lab = session.get_node("ControllerLab")
	for id in lab.route.tracks:
		if not (id.begins_with("station_") or id.begins_with("canyon_")): continue
		_track(root, lab.route.tracks[id])
		var track: SpatialTrack = lab.route.tracks[id]
		for ob in track.obstacles:
			if ob.get("kind", "block") != "block": continue
			assert(is_equal_approx(float(ob.height), 5.0), "Hazard source height changed")
			for lane in ob.lanes:
				var hazard := HAZARD.instantiate()
				root.add_child(hazard)
				hazard.transform = track.pose(float(ob.s), lane * 4.4)
				hazard.set_meta("asset_id", "GT_solid_folded_hazard")
				hazard.set_meta("instance_id", track.id + ":" + str(ob.id) + ":" + str(lane))
				hazard.set_meta("scene_id", "station" if id.begins_with("station_") else "canyon")
	var prior := session.get_node("ControllerLab/PresentationRoot")
	# Frozen builder appends each track's obstacles after its 120 m chunks.
	# RenderingServer's dummy backend does not retain MultiMesh transforms, so
	# identify these source batches by construction context and mesh/material.
	var source_track := ""
	var hidden_hazards := 0
	for old in prior.get_children():
		for id in lab.route.tracks:
			if str(old.name).begins_with(id + "_"): source_track = id
		if not (source_track.begins_with("station_") or source_track.begins_with("canyon_")): continue
		if not old is MultiMeshInstance3D: continue
		var mm: MultiMesh = old.multimesh
		if mm.instance_count != 1 or not mm.mesh is BoxMesh or mm.mesh.size != Vector3.ONE: continue
		var mat := mm.mesh.material as StandardMaterial3D
		if mat != null and mat.albedo_color.is_equal_approx(Color(1,0.18,0.11)):
			old.visible = false
			hidden_hazards += 1
	assert(hidden_hazards == 7, "Frozen first-sample hazard count changed")
	for chunk in prior.get_children():
		if not (str(chunk.name).begins_with("station_") or str(chunk.name).begins_with("canyon_")): continue
		for key in ["Bed", "Rail", "Ties", "EdgeCurbs", "NearMasses", "NearSpeedMarkers"]:
			var visual = chunk.get_node_or_null(key)
			if visual is GeometryInstance3D: visual.visible = false
		for key in ["TrackPiers", "TrackBraces"]:
			var visual = chunk.get_node_or_null(key)
			if visual is GeometryInstance3D: visual.material_override = materials.teal
	var env := session.get_node("ControllerLab/EnvironmentRoot")
	for key in ["StationGround", "StationPlatforms"]:
		var visual = env.get_node_or_null(key)
		if visual is GeometryInstance3D: visual.visible = false
	var we := env.get_node("WorldEnvironment") as WorldEnvironment
	var atmosphere := we.environment.duplicate() as Environment
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("8bbdc9")
	sky_mat.sky_horizon_color = Color("e0e2d4")
	sky_mat.ground_horizon_color = Color("e0e2d4")
	sky_mat.ground_bottom_color = Color("9bb9b8")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	atmosphere.sky = sky
	atmosphere.ambient_light_color = Color("d9e3df")
	atmosphere.ambient_light_energy = 0.45
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	atmosphere.fog_light_color = Color("c0d8d9")
	atmosphere.fog_density = 0.00038
	atmosphere.ssao_enabled = true
	atmosphere.ssao_radius = 1.8
	atmosphere.ssao_intensity = 1.2
	we.environment = atmosphere
	var sun := env.get_node("Sun") as DirectionalLight3D
	sun.light_color = Color("fff0d4")
	sun.light_energy = 1.0
	sun.directional_shadow_max_distance = 340.0
	return root

func _register(node: Node) -> void:
	var extras: Dictionary = node.get_meta("extras", {})
	for key in ["scene_id", "asset_id", "instance_id"]:
		if extras.has(key): node.set_meta(key, str(extras[key]))
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var source := node.mesh.surface_get_material(i) as BaseMaterial3D
			if source == null: continue
			if not paper_materials.has(source):
				var paper := ShaderMaterial.new()
				paper.shader = PAPER
				paper.set_shader_parameter("tint", source.albedo_color)
				paper_materials[source] = paper
			node.set_surface_override_material(i, paper_materials[source])
	for child in node.get_children(): _register(child)

func _batch(root: Node3D, name: String, mesh: Mesh, poses: Array[Transform3D], material: Material) -> void:
	if poses.is_empty(): return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = poses.size()
	for i in poses.size(): mm.set_instance_transform(i, poses[i])
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = mm
	node.material_override = material
	root.add_child(node)

func _track(root: Node3D, track: SpatialTrack) -> void:
	var part := Node3D.new()
	part.name = track.id + "_PaperTrack"
	part.set_meta("scene_id", "station" if track.id in ["station_start", "station_carve"] else "canyon")
	part.set_meta("asset_id", "RT01_03")
	part.set_meta("instance_id", track.id + "_paper_track")
	root.add_child(part)
	var bed: Array[Transform3D] = []
	var edge: Array[Transform3D] = []
	var cyan: Array[Transform3D] = []
	var rail: Array[Transform3D] = []
	var ties: Array[Transform3D] = []
	# Mesh dimensions are authored per instance, transforms remain positive.
	for i in ceili(track.length / 2.0):
		var s := i * 2.0
		var span := minf(2.0, track.length - s)
		var pose := track.pose(s + span * 0.5)
		var w := track.width_at(s + span * 0.5)
		bed.append(pose.translated_local(Vector3(0,-0.42,0)).scaled_local(Vector3(w*2,0.68,span+0.03)))
		for side in [-1,1]:
			edge.append(pose.translated_local(Vector3(side*(w-.2),-.1,0)).scaled_local(Vector3(.4,.45,span+.03)))
			cyan.append(pose.translated_local(Vector3(side*(w-.2),.14,0)).scaled_local(Vector3(.24,.025,span+.03)))
		for lane in track.lanes():
			for side in [-1,1]: rail.append(pose.translated_local(Vector3(lane*4.4+side*.72,.06,0)).scaled_local(Vector3(.16,.20,span+.02)))
			if i%2==0: ties.append(pose.translated_local(Vector3(lane*4.4,-.07,0)).scaled_local(Vector3(2.3,.17,.38)))
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_batch(part,"RT01_FoldBed",_fold_profile(),bed,materials.dark)
	_batch(part,"RT02_CutEdge",_fold_profile(),edge,materials.ivory)
	_batch(part,"RT02_FunctionLine",cube,cyan,materials.cyan)
	_batch(part,"RT02_Rails",cube,rail,materials.edge)
	_batch(part,"RT03_Sleepers",cube,ties,materials.ivory)

func _fold_profile() -> ArrayMesh:
	# Laminated folded channel: bevelled lower corners, full legal top width.
	var ring := [Vector2(-.5,.5),Vector2(.5,.5),Vector2(.5,-.1),Vector2(.32,-.5),Vector2(-.32,-.5),Vector2(-.5,-.1)]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i+1)%ring.size()]
		for p in [Vector3(a.x,a.y,-.5),Vector3(b.x,b.y,-.5),Vector3(b.x,b.y,.5),Vector3(a.x,a.y,-.5),Vector3(b.x,b.y,.5),Vector3(a.x,a.y,.5)]: tool.add_vertex(p)
	for side in [-1,1]:
		for i in range(1,ring.size()-1):
			var order := [0,i,i+1] if side<0 else [0,i+1,i]
			for at in order: tool.add_vertex(Vector3(ring[at].x,ring[at].y,side*.5))
	tool.generate_normals()
	return tool.commit()
