extends "res://levels/labs/spatial_full_lab/spatial_full_lab.gd"
## Isolated visual layer. super builds the identical route, camera solids and
## baseline slot records first. Art replacements never register new collisions.
const PALETTE := {"cream": Color("f2d5a8"), "lavender": Color("b6a0d8"), "gold": Color("eda83c"), "teal": Color("68c7be"), "peach": Color("eaaa83"), "orange": Color("e98948")}
const PILOT := ["wall", "inverted", "drop", "rollout", "loop_entry", "loop", "loop_out", "exit_ramp", "grind", "relay", "high", "high_merge"]
var clay_materials: Dictionary = {}
var rounded_mesh: Mesh
var art_instances: Array[Dictionary] = []
var semantic_replacements := 0
var lantern_roots: Array[Node3D] = []

func _ready() -> void:
	super._ready()
	_bake_lanterns()
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var environment: Environment = $EnvironmentRoot/WorldEnvironment.environment.duplicate(true)
	$EnvironmentRoot/WorldEnvironment.environment = environment
	var sky_material: ProceduralSkyMaterial = environment.sky.sky_material
	sky_material.sky_top_color = Color("75b5df")
	sky_material.sky_horizon_color = Color("76b1d9")
	sky_material.ground_horizon_color = Color("a6d3d2")
	sky_material.ground_bottom_color = Color("70babb")
	environment.ambient_light_color = Color("c9dfef")
	environment.ambient_light_energy = 0.32
	environment.fog_light_color = Color("c6ddda")
	environment.fog_density = 0.00019
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.8
	$EnvironmentRoot/Sun.light_color = Color("fff0cd")
	$EnvironmentRoot/Sun.light_energy = 0.82
	$EnvironmentRoot/Sun.directional_shadow_max_distance = 300.0
	for node in environment_root.get_children():
		if node is MeshInstance3D and node.mesh is PlaneMesh:
			var water := _clay("teal").duplicate()
			water.albedo_color = Color("398fa1")
			node.material_override = water
	_clouds()

func _clay(key: String) -> StandardMaterial3D:
	if clay_materials.has(key): return clay_materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = PALETTE[key]
	m.roughness = 0.93
	m.metallic_specular = 0.15
	var noise := FastNoiseLite.new()
	noise.frequency = 0.045
	noise.fractal_octaves = 2
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.noise = noise
	texture.seamless = true
	texture.as_normal_map = true
	texture.bump_strength = 0.15
	m.normal_enabled = true
	m.normal_texture = texture
	m.normal_scale = 0.25
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.15
	clay_materials[key] = m
	return m

func _rounded() -> Mesh:
	if rounded_mesh == null:
		var source = load("res://assets/clay-pilot/rounded-unit.glb").instantiate()
		rounded_mesh = (source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		source.free()
	return rounded_mesh

func _batch(parent: Node3D, label: String, size: Vector3, material: Material, poses: Array[Transform3D], range_end: float = 1100.0) -> void:
	super._batch(parent, label, size, material, poses, range_end)
	if poses.is_empty(): return
	var instance := parent.get_child(parent.get_child_count() - 1) as MultiMeshInstance3D
	if instance == null: return
	var key := "cream"
	if label in ["NearMasses", "ValleyWalls", "FinalRidges", "DistantPiers", "ContactStructure", "LoopRibs"]: key = "lavender"
	elif label in ["Pickets", "PulseArrows", "CatchGate", "CatchRunway", "TunnelLamps"]: key = "teal"
	elif label in ["ReleaseWindow", "GoldGrindCatch", "CoilStation", "HubBeacon"]: key = "gold"
	elif label == "Rail" and (material as BaseMaterial3D).albedo_color.r > 0.9: key = "gold"
	elif label in ["TrackPiers", "BridgePiers", "VerticalStationFrame", "StationPlatforms", "TerminalStation"]: key = "peach"
	# Gameplay red, warning signs and low beams retain their functional colours.
	if label not in ["Block", "LowBeam", "NoEntrySign", "NoEntryBar", "ApproachMarks"]: instance.material_override = _clay(key)
	if label in ["NearMasses", "DistantPiers", "VerticalStationFrame", "LoopRibs", "TrackPiers", "BridgePiers", "CoilStation", "TerminalStation", "ValleyWalls", "FinalRidges"] and size == Vector3.ONE:
		instance.multimesh.mesh = _rounded()
	if label == "GoldGrindCatch":
		for i in poses.size():
			if poses[i].basis.get_scale().y > 5.0:
				instance.multimesh.set_instance_transform(i, poses[i].scaled_local(Vector3.ZERO))
				var transform := poses[i].orthonormalized()
				transform.origin -= transform.basis.y * 4.5
				_lantern(parent, transform, "gold", 1.0, "receiver_lantern")
	if label in ["Pickets", "NearSpeedMarkers"]:
		instance.visible = false
		for i in poses.size():
			# Replace every post with a semantic ceramic way-light, preserving rhythm.
			var transform := poses[i].orthonormalized()
			transform.origin -= transform.basis.y * poses[i].basis.get_scale().y * 0.5
			_lantern(parent, transform, "teal", 0.12 if label == "Pickets" else 0.45, "way_light")
	if label == "NearMasses" and _pilot_chunk(str(parent.name)):
		instance.visible = false
		for i in poses.size():
			var lower := poses[i].scaled_local(Vector3(0.75,0.96,0.82))
			instance.multimesh.set_instance_transform(i, lower)
			_decorate_mass(parent, poses[i], i)
	if label == "DistantPiers":
		instance.visible = false
		for pose in poses:
			var dims := pose.basis.get_scale()
			var tower_base := Node3D.new()
			parent.add_child(tower_base)
			tower_base.transform = pose.orthonormalized()
			var factor := minf(dims.x/5.94,minf(dims.y/18.0,dims.z/5.89))
			_asset(tower_base,"tower",Vector3(0,-dims.y*0.5,0),factor)

func _pilot_chunk(chunk: String) -> bool:
	for id in PILOT:
		if chunk.begins_with(id + "_"): return true
	return false

func _piece(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = mat
	piece.position = pos
	parent.add_child(piece)
	return piece

func _cylinder(parent: Node3D, radius: float, height: float, y: float, mat: Material, top_ratio: float = 1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * top_ratio
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	_piece(parent, mesh, Vector3(0,y,0), mat)

func _lantern(parent: Node3D, transform: Transform3D, color: String, factor: float, semantic: String) -> void:
	var lamp := Node3D.new()
	lamp.name = "ClayLantern"
	parent.add_child(lamp)
	lantern_roots.append(lamp)
	lamp.transform = transform.scaled_local(Vector3.ONE * factor)
	# Ceramic plinth, fluted post, saucer and cream globe: an identifiable prop.
	_cylinder(lamp,0.7,0.9,0.45,_clay(color),0.7)
	_cylinder(lamp,0.25,5.5,3.35,_clay("peach"),0.82)
	_cylinder(lamp,1.05,0.28,6.2,_clay(color),0.82)
	var globe := SphereMesh.new()
	globe.radius = 0.84
	globe.height = 1.68
	globe.radial_segments = 16
	globe.rings = 8
	_piece(lamp,globe,Vector3(0,7.05,0),_clay("cream"))
	_cylinder(lamp,1.05,0.7,8.0,_clay(color),0.14)
	semantic_replacements += 1
	art_instances.append({"semantic":semantic,"source":"procedural-clay-lantern-v1","position":[lamp.global_position.x,lamp.global_position.y,lamp.global_position.z],"uniform_scale":factor})

func _bake_lanterns() -> void:
	var groups := {}
	for lamp in lantern_roots:
		for i in lamp.get_child_count():
			var part := lamp.get_child(i) as MeshInstance3D
			var key := str(i) + ":" + str(part.material_override.get_instance_id())
			if not groups.has(key): groups[key] = {"mesh":part.mesh,"material":part.material_override,"poses":[]}
			groups[key].poses.append(global_transform.affine_inverse() * part.global_transform)
		lamp.queue_free()
	for group: Dictionary in groups.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = group.mesh
		mm.instance_count = group.poses.size()
		for i in group.poses.size(): mm.set_instance_transform(i,group.poses[i])
		var node := MultiMeshInstance3D.new()
		node.name = "ClayLanternBatch"
		node.multimesh = mm
		node.material_override = group.material
		add_child(node)
	lantern_roots.clear()

func _asset(parent: Node3D, id: String, pos: Vector3, scale_factor: float, yaw: float = 0.0) -> void:
	var asset = load("res://assets/clay-pilot/" + id + ".glb").instantiate()
	parent.add_child(asset)
	asset.position = pos
	asset.rotation.y = yaw
	asset.scale = Vector3.ONE * scale_factor
	var world: Transform3D = asset.global_transform
	art_instances.append({"asset":id,"parent":str(parent.name),"position":[pos.x,pos.y,pos.z],"uniform_scale":scale_factor,"yaw":yaw,"world_matrix":[world.basis.x.x,world.basis.x.y,world.basis.x.z,0,world.basis.y.x,world.basis.y.y,world.basis.y.z,0,world.basis.z.x,world.basis.z.y,world.basis.z.z,0,world.origin.x,world.origin.y,world.origin.z,1]})

func _clouds() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("fff1dc")
	mat.roughness = 1
	for i in 9:
		var sphere := SphereMesh.new()
		sphere.radius = 28
		sphere.height = 48
		sphere.radial_segments = 20
		sphere.rings = 12
		var cloud_center: Vector3 = (route as SpatialRoute).tracks.grind.pose(300).origin + Vector3((i % 3 - 1)*340,220+float(i%2)*80,-350-float(i/3)*420)
		for k in 5:
			var cloud := _piece(environment_root,sphere,cloud_center+Vector3((k-2)*25,sin(k*2.0)*10,0),mat)
			cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _decorate_mass(parent: Node3D, pose: Transform3D, index: int) -> void:
	var dims := pose.basis.get_scale()
	var base := Node3D.new()
	parent.add_child(base)
	base.transform = pose.orthonormalized()
	# A parameterized clay landform gives the rock kit a continuous foundation.
	# Extension toward water is accepted only outside all route/camera corridors.
	var bottom := -dims.y * 0.5
	var water_bottom := -46.0 - base.global_position.y
	if water_bottom < bottom and _foundation_clear(base.global_transform, dims, water_bottom, bottom): bottom = water_bottom
	_terrain_column(base,dims,bottom,dims.y*0.25,index)
	var scale_factor := minf(dims.x / 9.39, minf(dims.y*0.24/12.551,dims.z/16.0)) * 0.9
	for sign in [-1,1]:
		_asset(base,"rock",Vector3(0,dims.y*0.23,sign*dims.z*0.22),scale_factor)
	var tower_scale := minf(dims.x/8.0,minf(dims.y*0.3/18.0,dims.z/8.0)) * 0.85
	_asset(base,"tower",Vector3(0,dims.y*0.5-18.0*tower_scale,dims.z*0.5-4.1*tower_scale),tower_scale)
	for sign in [-1,1]:
		var tree_scale := minf(dims.x/8.0,minf(dims.y*0.3/6.77,dims.z/8.0)) * 0.8
		_asset(base,"cypress",Vector3(sign*dims.x*0.28,dims.y*0.2,0),tree_scale, float(index)*0.47)

func _foundation_clear(world: Transform3D, dims: Vector3, bottom: float, old_bottom: float) -> bool:
	var inverse := world.affine_inverse()
	for track: SpatialTrack in (route as SpatialRoute).tracks.values():
		for i in ceili(track.length / 12.0) + 1:
			var point := inverse * track.pose(minf(i*12.0,track.length)).origin
			if absf(point.x) < dims.x*0.5+20 and absf(point.z) < dims.z*0.5+30 and point.y > bottom-16 and point.y < old_bottom+16: return false
	return true

func _terrain_column(parent: Node3D, dims: Vector3, bottom: float, top: float, seed_index: int) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	var rings: Array[PackedVector3Array] = []
	for j in 9:
		var ring := PackedVector3Array()
		var y := lerpf(bottom,top,j/8.0)
		for i in 48:
			var angle := TAU * float(i)/48.0
			var wave := 0.88 + 0.045*sin(angle*5.0+j*0.7+seed_index) + 0.025*cos(angle*3.0-j*0.8)
			var x := signf(cos(angle))*pow(absf(cos(angle)),0.55)*dims.x*0.5*wave
			var z := signf(sin(angle))*pow(absf(sin(angle)),0.55)*dims.z*0.5*wave
			ring.append(Vector3(x,y,z))
		rings.append(ring)
	for j in 8:
		for i in 48:
			var next := (i+1)%48
			for vertex in [rings[j][i],rings[j][next],rings[j+1][i],rings[j][next],rings[j+1][next],rings[j+1][i]]: surface.add_vertex(vertex)
	for i in 48:
		for vertex in [Vector3(0,top,0),rings[8][i],rings[8][(i+1)%48]]: surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := surface.commit()
	_piece(parent,mesh,Vector3.ZERO,_clay("lavender"))
