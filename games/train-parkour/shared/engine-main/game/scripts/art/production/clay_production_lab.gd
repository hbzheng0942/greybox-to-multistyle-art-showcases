extends "res://scripts/art/clay_pilot_lab.gd"
## Candidate production presentation. Original route/collision/camera construction stays authoritative.
const Kit = preload("res://scripts/art/production/clay_kit.gd")
const RECIPE := "res://../art/workflows/clay-pilot/production-v1/recipe.json"
var kit := Kit.new()
var recipe: Dictionary
var production_instances: Array[Dictionary] = []
var kit_scenes: Dictionary = {}
var production_root: Node3D

func _ready() -> void:
	var recipe_path := RECIPE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--art-recipe="): recipe_path = arg.trim_prefix("--art-recipe=")
	recipe = JSON.parse_string(FileAccess.get_file_as_string(recipe_path))
	assert(recipe.schema_version == 1)
	super._ready()
	production_root = Node3D.new()
	production_root.name = "ProductionPresentation"
	add_child(production_root)
	var env: Environment = $EnvironmentRoot/WorldEnvironment.environment
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e5daee")
	env.ambient_light_energy = 0.28
	env.tonemap_exposure = 0.9
	env.fog_light_color = Color("c3dedb")
	env.fog_density = 0.00011
	env.ssao_enabled = true
	env.ssao_radius = 1.8
	env.ssao_intensity = 1.0
	$EnvironmentRoot/Sun.light_color = Color("fff0dc")
	$EnvironmentRoot/Sun.light_energy = 0.9
	$EnvironmentRoot/Sun.light_angular_distance = 0.8
	kit.step_max_m = recipe.rail.step_max_m
	_build_exact_rails()
	_build_gallery()
	_build_station_furniture()
	print("CLAY_PRODUCTION_READY meshes=",kit.built_meshes," triangles=",kit.triangles," instances=",production_instances.size())

func _batch(parent: Node3D, label: String, size: Vector3, material: Material, poses: Array[Transform3D], range_end: float = 1100.0) -> void:
	var before := parent.get_child_count()
	super._batch(parent,label,size,material,poses,range_end)
	var replaces := label in ["Bed","Rail","Ties"] or (str(parent.name).begins_with("tunnel_") and label in ["ContactStructure","TunnelLamps","TunnelDecorFrames"])
	if replaces:
		for i in range(before,parent.get_child_count()):
			var node := parent.get_child(i)
			if node is MultiMeshInstance3D: node.hide()

func _pilot_chunk(chunk: String) -> bool:
	# Existing validated mass positions are reused for the first coherent rough pass.
	return not chunk.begins_with("tunnel_")

func _build_exact_rails() -> void:
	var deck := kit.clay("Deck",recipe.rail.deck_color)
	var rail := kit.clay("Rail",recipe.rail.rail_color)
	var gold := kit.clay("GoldRail","e7b341",0.04)
	var sleeper := kit.clay("Sleeper",recipe.rail.sleeper_color)
	for t: SpatialTrack in (route as SpatialRoute).tracks.values():
		for index in ceili(t.length/120.0):
			var a := index*120.0
			var b := minf(a+120,t.length)
			var chunk := Node3D.new()
			chunk.name = "Precise_"+t.id+"_"+str(index)
			production_root.add_child(chunk)
			chunk.position = t.pose(a).origin
			kit.sweep(chunk,"ClayDeck",t,a,b,kit.round_rect(1.0,-0.7,-0.08,0.10),deck,Vector2.ZERO,false,true)
			for lane in t.lanes():
				for side in [-1,1]:
					kit.sweep(chunk,"ClayRail",t,a,b,kit.round_rect(0.095,-0.015,0.165,0.035),gold if t.single_lane else rail,Vector2(lane*4.4+side*(0.26 if t.kind=="grind" else 0.72),0))
			var ties: Array[Transform3D] = []
			for n in range(ceili(a/8.0),ceili(b/8.0)):
				for lane in t.lanes():
					var pose := t.pose(n*8.0,lane*4.4)
					pose.origin -= chunk.position
					ties.append(pose)
			_rigid_instances(chunk,"Sleepers","rail-sleeper",ties,sleeper)
			if t.kind in ["loop","wall","inverted","grind"]:
				kit.sweep(chunk,"StructuralSpine",t,a,b,kit.round_rect(0.9,-1.6,-0.73,0.15),kit.clay("Spine","dcaa96"))

func _rigid_instances(parent: Node3D, label: String, id: String, poses: Array[Transform3D], material: Material) -> void:
	if poses.is_empty(): return
	var source = load("res://assets/clay-production/"+id+".glb").instantiate()
	var part := source.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = part.mesh
	mm.instance_count = poses.size()
	# The exported mesh node carries its authored offset. Preserve it once.
	for i in poses.size(): mm.set_instance_transform(i,poses[i]*part.transform)
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = mm
	node.material_override = material
	node.visibility_range_end = 900
	parent.add_child(node)
	source.free()

func _kit_asset(parent: Node3D, id: String, pose: Transform3D) -> Node3D:
	if not kit_scenes.has(id): kit_scenes[id] = load("res://assets/clay-production/"+id+".glb")
	var node: Node3D = kit_scenes[id].instantiate()
	parent.add_child(node)
	node.transform = pose
	for part: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		for s in part.mesh.get_surface_count():
			var old := part.get_active_material(s) as StandardMaterial3D
			if old != null:
				var key := str(old.resource_name)
				part.set_surface_override_material(s,kit.clay(key,old.albedo_color.to_html(false),0.9 if key.contains("WarmGlobe") else 0.0))
		part.visibility_range_end = 480 if id != "vault-rib" else 1000
	production_instances.append({"asset":id,"world_position":[node.global_position.x,node.global_position.y,node.global_position.z],"scale":[1,1,1]})
	return node

func _build_gallery() -> void:
	var t: SpatialTrack = route.tracks.tunnel
	var config: Dictionary = recipe.tunnel
	var wall := kit.clay("GalleryWall",config.wall_color,0.04)
	wall.cull_mode = BaseMaterial3D.CULL_BACK
	var floor_mat := kit.clay("GalleryFloor",config.floor_color,0.03)
	var rib_mat := kit.clay("GalleryRib",config.rib_color,0.035)
	for index in ceili(t.length/120.0):
		var a := index*120.0
		var b := minf(a+120,t.length)
		var chunk := Node3D.new()
		chunk.name = "Gallery_"+str(index)
		production_root.add_child(chunk)
		chunk.position = t.pose(a).origin
		kit.sweep(chunk,"Vault",t,a,b,kit.tunnel_profile(t.enclosure_half_width-1.1,t.ceiling-4.5),wall,Vector2.ZERO,true)
		kit.sweep(chunk,"Floor",t,a,b,kit.round_rect(t.enclosure_half_width-1.1,-.8,-.43,.08),floor_mat)
		for side in [-1,1]:
			kit.sweep(chunk,"ServiceWalkway",t,a,b,kit.round_rect(6.0,-.4,.18,.12),kit.clay("Walkway","c7b4a8"),Vector2(side*29.0,0))
			kit.sweep(chunk,"WallPlinth",t,a,b,kit.round_rect(.48,-.3,1.2,.16),kit.clay("Plinth","efcfab"),Vector2(side*35.6,0))
			kit.sweep(chunk,"ServicePipe",t,a,b,kit.round_rect(.22,2.9,3.34,.12),kit.clay("ServiceTeal","77aaa4"),Vector2(side*36.35,0))
		# Longitudinal ceramic bands and inset ceiling coffers provide scale between ribs.
		for x in [-24.0,-12.0,0.0,12.0,24.0]:
			var y := 7.2+sqrt(1.0-pow(x/36.9,2))*(t.ceiling-11.7)
			kit.sweep(chunk,"CeilingBand",t,a,b,kit.round_rect(.28,y-.7,y+.02,.1),rib_mat,Vector2(x,0))
		var poses: Array[Transform3D] = []
		for n in range(ceili(a/float(config.rib_spacing_m)),ceili(b/float(config.rib_spacing_m))):
			var pose := t.pose(n*float(config.rib_spacing_m))
			pose.origin -= chunk.position
			poses.append(pose)
		_rigid_instances(chunk,"VaultRibs","vault-rib",poses,rib_mat)
	if config.dressing:
		var spacing: float = config.lamp_spacing_m
		for n in range(ceili(t.length/spacing)):
			var s := minf(n*spacing+18,t.length-8)
			for side in [-1,1]:
				var pose := t.pose(s).translated_local(Vector3(side*20,0.18,0))
				_kit_asset(production_root,"ceramic-lantern",pose)
				var pier_pose := t.pose(s-10).translated_local(Vector3(side*22,0,0))
				_kit_asset(production_root,"gallery-pier",pier_pose)
				var bay_pose := t.pose(s+12).translated_local(Vector3(side*31,0.18,0)).rotated_local(Vector3.UP,-side*PI/2)
				_kit_asset(production_root,"service-bay",bay_pose)
				var light := OmniLight3D.new()
				light.name = "WarmPool_"+str(n)+"_"+str(side)
				production_root.add_child(light)
				light.position = t.pose(s)*Vector3(side*17,7.5,0)
				light.light_color = Color(config.lantern_color)
				light.light_energy = config.lamp_energy
				light.omni_range = 40
				light.omni_attenuation = 0.7
				light.shadow_enabled = false
				light.distance_fade_enabled = true
				light.distance_fade_begin = 240
				light.distance_fade_length = 90
			var pendant := t.pose(s).translated_local(Vector3(0,10.85,0))
			kit.mesh_piece(production_root,kit.sphere(.58,1.16),pendant,kit.clay("PendantGlobe","ffdda0",1.2),"CeilingPendant")
			var fill := OmniLight3D.new()
			production_root.add_child(fill)
			fill.position = pendant.origin-Vector3(0,1.0,0)
			fill.light_color = Color(config.lantern_color)
			fill.light_energy = config.lamp_energy*1.7
			fill.omni_range = 34
			fill.omni_attenuation = 0.65
			fill.distance_fade_enabled = true
			fill.distance_fade_begin = 160
			fill.distance_fade_length = 80
			if n%3 != 1:
				var sign_side := -1 if n%2==0 else 1
				var pos := t.pose(s+14).translated_local(Vector3(sign_side*31,.22,0))
				_kit_asset(production_root,"service-cabinet",pos)
				_kit_asset(production_root,"ventilation-fan",pos.translated_local(Vector3(-sign_side*2,0,6)))
	# Both mouths have physical thickness and the same gallery language.
	for s in [0.0,t.length]:
		_kit_asset(production_root,"vault-rib",t.pose(s))
		for side in [-1,1]:
			var frame := Node3D.new()
			production_root.add_child(frame)
			frame.transform = t.pose(s)
			_asset(frame,"rock",Vector3(side*54,-14,0),2.8)
			_asset(frame,"cypress",Vector3(side*59,6,3),1.25)

func _build_station_furniture() -> void:
	for id in ["station_start","victory_run"]:
		var t: SpatialTrack = route.tracks[id]
		for n in range(1,ceili(t.length/80.0)):
			for side in [-1,1]:
				var pose := t.pose(n*80.0).translated_local(Vector3(side*17,0,0))
				_kit_asset(production_root,"platform-bench",pose)
				_kit_asset(production_root,"ceramic-lantern",pose.translated_local(Vector3(0,0,-7)))
