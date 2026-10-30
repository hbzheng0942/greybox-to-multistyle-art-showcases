extends "res://../art/train-parkour/shared/tools/lux_sample_world.gd"
## Complete, scoped composition experiment. Canonical G1 sources and gameplay unchanged.
const SURFACE = preload("res://../art/train-parkour/shared/tools/scene_rebuild_surface.gdshader")
const RACK := "B2-LUX-03-rack_bay-tall_open"
const WAREHOUSE := "B2-LUX-04-warehouse_bay-high_storage"
const RECEIVING := "B2-LUX-04-warehouse_bay-low_receiving"
const FREIGHT := "B2-LUX-06-locked_freight-squat_strapped"
const CART := "B2-LUX-08-cage_cart-dented_cage"
var rebuild_session: Node3D
var rebuild_route: Node
var rebuild_world: Node3D
var serial := 0
var parts: Array = []
var rejected_parts: Array = []
var source_boxes: Dictionary = {}
var protected_samples: Array[Vector3] = []
var material_cache: Dictionary = {}
var rebuild_lights: Array[Vector3] = []

func build_style(session: Node3D, style_id: String) -> Node3D:
	var started := Time.get_ticks_msec()
	rebuild_session = session
	rebuild_route = session.lab.get_node("RouteRoot/MainRoute")
	for track: Variant in rebuild_route.tracks.values():
		for i in range(ceili(track.length / 10.0) + 1):
			protected_samples.append(rebuild_route.track_pose(track.id, minf(i*10.0,track.length),0).origin)
	var world := super.build_style(session, style_id)
	world.set_meta("scene_rebuild_report", {"schema":1,"scope":"N01 and N02 first flight/landing; downstream remains historical context",
		"parts":parts,"rejected_parts":rejected_parts,"light_emitters":rebuild_lights.size(),"generated_mesh_jobs":0,
		"route_samples_m":protected_samples.map(func(p): return array(p)),"route_sample_spacing_m":10.0,
		"assembly_wall_ms":Time.get_ticks_msec()-started,
		"source_policy":"Canonical image-conditioned G1 sources and shared geometry LODs; controlled architecture for exact floor/roof interfaces",
		"new_collision_nodes":0,"human_acceptance":"pending","visual_status":"requires current native comparison"})
	return world

func _sample_config_path() -> String:
	return CASE + "styles/odd-logistics/runtime/scene-rebuild-assembly.json"

func _apply_sample(world: Node3D, config: Dictionary) -> void:
	rebuild_world = world
	_load_sample_assets(config.assets)
	for ident: String in sample_specs:
		if sample_templates.has(ident+":near"):
			source_boxes[ident] = measure(sample_templates[ident+":near"]).bounds
	_remove_superseded_environment(world)
	_build_station("station_start")
	_build_station("station_carve")
	_build_canyon()
	_track_details()
	world.set_meta("scene_rebuild_parts", parts)

func _remove_superseded_environment(world: Node3D) -> void:
	var remove: Dictionary = {}
	for item: Dictionary in world.get_meta("proxy_geometry_before_calibration", {}).get("items", []):
		var space: String = str(item.get("space_id", ""))
		if space not in ["N01", "N02"] or item.get("category", "") not in ["background_mass","roof","bank"]: continue
		var ident: String = str(item.id).split("/")[0].split(":mesh:")[0]
		if space == "N02":
			var center := vector(item.center_m)
			if not _near_first_canyon(center): continue
		remove[ident] = true
	for node: Node3D in world.get_children():
		var ident := str(node.get_meta("instance_id", ""))
		if remove.has(ident) or str(node.get_meta("asset_id", "")) == RACK:
			node.visible = false
			if not ident in replaced_ids: replaced_ids.append(ident)
	# Only the existing station scenery floor is replaced; its physics is untouched.
	for node: GeometryInstance3D in rebuild_session.lab.get_node("EnvironmentRoot").find_children("*", "GeometryInstance3D", true, false):
		if str(node.name).begins_with("StationGround") or str(node.name).begins_with("StationPlatforms"): node.visible = false

func _near_first_canyon(p: Vector3) -> bool:
	for track_id: String in ["station_ramp","canyon_safe","canyon_fast_catch"]:
		var track: Variant = rebuild_route.tracks[track_id]
		var limit := minf(track.length, 500.0)
		for i in range(ceili(limit/60.0)+1):
			var q: Vector3 = rebuild_route.track_pose(track_id,minf(i*60.0,limit),0).origin
			if Vector2(p.x-q.x,p.z-q.z).length() < 170.0: return true
	return false

func _pose(track_id: String, s: float) -> Transform3D:
	return rebuild_route.track_pose(track_id,clampf(s,0,rebuild_route.tracks[track_id].length),0)

func _flat(pose: Transform3D) -> Basis:
	var forward := -pose.basis.z
	forward.y = 0
	return Basis.looking_at(forward.normalized(),Vector3.UP)

func _unbanked(pose: Transform3D) -> Transform3D:
	var x := _flat(pose).x
	var z := pose.basis.z.normalized()
	return Transform3D(Basis(x,z.cross(x).normalized(),z),pose.origin)

func _mat(color: String, floor_surface := false, metal := 0.1) -> Material:
	var key := color+str(floor_surface)+str(metal)
	if material_cache.has(key): return material_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE
	mat.set_shader_parameter("base_color", Color(color))
	mat.set_shader_parameter("floor_surface",floor_surface)
	mat.set_shader_parameter("metalness",metal)
	material_cache[key] = mat
	return mat

func _register(node: Node3D, local_box: AABB, ident: String, asset: String, space: String, kind: String) -> void:
	var box: AABB = node.global_transform * local_box
	_tag_tree(node,ident,asset,"station" if space=="N01" else "canyon")
	var row := {"id":ident,"asset":asset,"space_id":space,"kind":kind,"position":array(node.global_position),
		"basis":transform_array(node.global_transform),"bounds":box_record(box)}
	parts.append(row)
	added_bounds.append({"id":ident,"style_id":sid,"space_id":space,"category":"background_mass",
		"center_m":array(box.get_center()),"size_m":array(box.size),"basis_columns":[[1,0,0],[0,1,0],[0,0,1]],
		"protected_route":false,"mesh_local_aabb":box_record(local_box),"mesh_to_world":transform_array(node.global_transform),
		"bounds_kind":"scene_rebuild_oriented_box","source_asset_id":asset})

func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _solid(size: Vector3, pose: Transform3D, color: String, space: String, role: String, floor_surface := false) -> Node3D:
	var node := MeshInstance3D.new()
	var mesh := _box_mesh(size)
	node.mesh = mesh
	node.material_override = _mat(color,floor_surface,0.55 if "beam" in role or "rail" in role else 0.08)
	serial += 1
	node.name = "SceneRebuild_%s_%d" % [role,serial]
	rebuild_world.add_child(node)
	node.global_transform = pose
	_register(node,mesh.get_aabb(),"rebuild:"+space+":"+role+":"+str(serial),"authored_"+role,space,"structure")
	return node

func _route_clear(box: AABB, pose: Transform3D, margin := 6.8) -> bool:
	var inv := pose.affine_inverse()
	var expanded := box.grow(margin / pose.basis.x.length())
	for p: Vector3 in protected_samples:
		if expanded.has_point(inv*p): return false
	return true

func _model(asset: String, pose: Transform3D, scale_value: float, space: String, role: String, clearance := true) -> Node3D:
	if not sample_templates.has(asset+":near") or not source_boxes.has(asset): return null
	pose.basis = pose.basis.scaled(Vector3.ONE*scale_value)
	var box: AABB = source_boxes[asset]
	if clearance and not _route_clear(box,pose):
		rejected_parts.append({"asset":asset,"space":space,"role":role,"position":array(pose.origin),"reason":"sampled frozen route envelope"})
		return null
	var node := Node3D.new()
	node.add_child(sample_templates[asset+":near"].duplicate())
	serial += 1
	node.name = "SceneRebuild_%s_%d" % [role,serial]
	rebuild_world.add_child(node)
	node.global_transform = pose
	for mesh: GeometryInstance3D in node.find_children("*","GeometryInstance3D",true,false):
		mesh.visibility_range_end = 850.0
	_register(node,box,"rebuild:"+space+":"+role+":"+str(serial),asset,space,"reused_G1")
	return node

func _at(pose: Transform3D, offset: Vector3) -> Transform3D:
	return pose.translated_local(offset)

func _fixture(pose: Transform3D, space: String) -> void:
	_solid(Vector3(7,0.32,1.6),pose,"30372d",space,"lamp_housing")
	var face := _solid(Vector3(6.5,0.1,1.25),_at(pose,Vector3(0,-0.2,0)),"c6bb81",space,"lamp_diffuser") as MeshInstance3D
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("f6e3b3")
	glow.emission_enabled = true
	glow.emission = Color("ffe0a1")
	glow.emission_energy_multiplier = 2.2
	face.material_override = glow
	rebuild_lights.append(pose.origin-Vector3.UP*0.5)

func _loaded_rack(pose: Transform3D, space: String, variant: int) -> void:
	# Complete cargo-and-shelf assemblies, with explicit support instead of loose floating cargo.
	for layer in range(2):
		var shelf_y := 6.2 + layer*7.0
		_solid(Vector3(16.8,0.28,6.8),_at(pose,Vector3(0,shelf_y,0)),"5a5846",space,"loaded_shelf")
		for side: float in [-1.0,1.0]:
			if variant%3==1 and layer==1 and side<0: continue
			var cargo_at := _at(pose,Vector3(side*4.0,shelf_y+0.14,0.2))
			_model(FREIGHT,cargo_at,1.9 if variant%3==2 else 2.15,space,"rack_cargo")

func _detail_batch(size: Vector3, color: String, poses: Array[Transform3D], role: String) -> void:
	if poses.is_empty(): return
	var shape := BoxMesh.new()
	shape.size = size
	for first in range(0,poses.size(),80):
		var count := mini(80,poses.size()-first)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = shape
		mm.instance_count = count
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = _mat(color,false,0.5)
		node.visibility_range_end = 450
		rebuild_world.add_child(node)
		for i in count: mm.set_instance_transform(i,poses[first+i])
		_tag_tree(node,"rebuild:detail:"+role+":"+str(first),"authored_rail_fasteners","station")
	parts.append({"kind":"in_track_visual_detail","role":role,"count":poses.size(),"size":array(size),
		"constraint":"Original track poses; top <=0.16m above rail frame; no collision or topology change"})

func _track_details() -> void:
	var ties: Array[Transform3D] = []
	var clips: Array[Transform3D] = []
	for track_id: String in ["station_start","station_carve","station_ramp","canyon_safe","canyon_fast_catch"]:
		var length: float = rebuild_route.tracks[track_id].length
		if track_id == "canyon_safe": length = minf(length,560)
		for i in range(ceili(length/4.2)):
			var pose := _pose(track_id,i*4.2+1.0)
			ties.append(_at(pose,Vector3(0,0.06,0)))
			for x: float in [-6.3,-2.1,2.1,6.3]: clips.append(_at(pose,Vector3(x,0.12,0)))
	_detail_batch(Vector3(13.3,0.1,0.42),"66685c",ties,"sleepers")
	_detail_batch(Vector3(0.45,0.08,0.65),"b29a4b",clips,"clips")

func _build_station(track_id: String) -> void:
	var length: float = rebuild_route.tracks[track_id].length
	var bay := 22.0
	for i in range(ceili(length/bay)):
		var s := minf(i*bay+bay*0.5,length-0.5)
		var pose := _pose(track_id,s)
		var deck := _unbanked(pose)
		var horizontal := Transform3D(_flat(pose),pose.origin)
		var span := minf(bay,length-i*bay)+0.5
		for side: float in [-1.0,1.0]:
			# Continuous deck lies below the original rail, independent of functional collision.
			_solid(Vector3(30,1.2,span),_at(deck,Vector3(side*23.0,-1.1,0)),"555443","N01","loading_deck",true)
			_solid(Vector3(0.65,0.7,span),_at(deck,Vector3(side*8.35,-0.85,0)),"b39a44","N01","platform_edge")
			var rack_at := horizontal.origin + horizontal.basis.x * side * (24.0 if i%7 in [2,3] else 20.0)
			rack_at.y += 0.8
			var face := Basis.looking_at(-horizontal.basis.x*side,Vector3.UP)
			if _model(RACK,Transform3D(face,rack_at),1.2,"N01","storage_wall") != null:
				_solid(Vector3(8.0,2.0,17.4),Transform3D(horizontal.basis,rack_at-Vector3.UP),"555443","N01","rack_plinth",true)
				if i%3 != 1: _loaded_rack(Transform3D(face,rack_at),"N01",i)
			# A second depth band of warehouse bays forms the enclosure, not a distant proxy grid.
			if i%2==0:
				var warehouse_at := horizontal.origin + horizontal.basis.x*side*42.0
				warehouse_at.y += 0.8
				if _model(WAREHOUSE,Transform3D(face,warehouse_at),1.12,"N01","warehouse_enclosure") != null:
					_solid(Vector3(25.2,2.4,26.2),Transform3D(horizontal.basis,warehouse_at-Vector3.UP*1.2),"555443","N01","warehouse_plinth",true)
			if i%7 in [2,3]:
				var cart_at := horizontal.origin+horizontal.basis.x*side*13.0
				cart_at.y += 0.1
				if _model(CART if i%2==0 else FREIGHT,Transform3D(face,cart_at),1.0,"N01","receiving_group") != null:
					_solid(Vector3(3.4,0.9,3.2),Transform3D(horizontal.basis,cart_at-Vector3.UP*0.45),"4c4d3d","N01","cargo_pad")
			# Load-bearing side piers reach the known station foundation, rather than float.
			if i%2==0:
				var top := pose.origin.y-1.7
				var height := maxf(1.0,top-73.0)
				_solid(Vector3(2.0,height,2.5),Transform3D(horizontal.basis,horizontal.origin+horizontal.basis.x*side*33.0+Vector3(0,-1.7-height*0.5,0)),"494c3e","N01","lower_pier")
			# Framing and roof are attached at the same bay, with actual feet and heads.
			_solid(Vector3(1.1,29,1.4),_at(horizontal,Vector3(side*34,14,0)),"4b5243","N01","column")
			_solid(Vector3(1.6,0.5,2.0),_at(horizontal,Vector3(side*34,-0.25,0)),"9e873e","N01","column_shoe")
		_solid(Vector3(70,0.5,span+3.0),_at(deck,Vector3(0,29.5,0)),"393e34","N01","roof_panel")
		_solid(Vector3(69,1.5,0.8),_at(horizontal,Vector3(0,28.3,0)),"4a5143","N01","roof_beam")
		for x: float in [-22.0,22.0]:
			_solid(Vector3(0.55,1.1,span+3.0),_at(deck,Vector3(x,28.9,0)),"434a3b","N01","roof_purlin")
		if i%2==0:
			_fixture(_at(horizontal,Vector3(0,27,0)),"N01")
			# Floor loading markings are quiet and stay outside the functional lanes.
			for side: float in [-1.0,1.0]:
				_solid(Vector3(9,0.025,0.22),_at(deck,Vector3(side*14,-0.48,4)),"b9a455","N01","loading_mark")

func _build_canyon() -> void:
	# A shared tall storage hall surrounds both original branches; route geometry remains authority.
	var track_id := "canyon_safe"
	for i in range(22):
		var pose := _pose(track_id,i*25.0)
		var horizontal := Transform3D(_flat(pose),pose.origin)
		var column_offsets: Array[float] = []
		for side: float in [-1.0,1.0]:
			var offset := side*(47.0 if side<0 else 37.0)
			var facing := Basis.looking_at(-horizontal.basis.x*side,Vector3.UP)
			# Fit the whole six-level column; never omit a supporting level to clear a route.
			var floor_y := 16.0
			var stack_box := AABB(Vector3(-8.4,0,-3.6),Vector3(16.8,129.6,7.2))
			var stack_at := horizontal.origin + horizontal.basis.x*offset
			stack_at.y = floor_y
			for attempt in range(6):
				if _route_clear(stack_box,Transform3D(facing,stack_at),10.0): break
				offset += side*14
				stack_at = horizontal.origin + horizontal.basis.x*offset
				stack_at.y = floor_y
			for level in range(6):
				var at := horizontal.origin + horizontal.basis.x*offset
				at.y = floor_y+level*21.6
				var rack := _model(RACK,Transform3D(facing,at),1.2,"N02","canyon_storage")
				if rack != null:
					_solid(Vector3(8.0,0.5,17.1),Transform3D(horizontal.basis,at+Vector3(0,-0.25,0)),"575548","N02","shelf_landing")
					if i%2==0 and level in [2,3,4]: _loaded_rack(Transform3D(facing,at),"N02",i+level)
			if i%3==0:
				var lamp_at := horizontal.origin+horizontal.basis.x*(offset-side*7)
				lamp_at.y += 9
				_solid(Vector3(9,0.35,0.45),Transform3D(horizontal.basis,lamp_at+horizontal.basis.x*side*4),"494f42","N02","wall_lamp_bracket")
				_fixture(Transform3D(horizontal.basis,lamp_at),"N02")
			if i%2==0:
				var p := horizontal.origin+horizontal.basis.x*side*65
				p.y = floor_y
				_model(WAREHOUSE,Transform3D(facing,p),2.7,"N02","deep_warehouse")
			# Fit the entire load-bearing column against every frozen branch before placing it.
			var column_x := side*83.0
			var column_pose := Transform3D(horizontal.basis,horizontal.origin+horizontal.basis.x*column_x+Vector3(0,87-horizontal.origin.y,0))
			var column_box := AABB(Vector3(-0.8,-71,-1),Vector3(1.6,142,2))
			for attempt in range(16):
				if _route_clear(column_box,column_pose,12.0): break
				column_x += side*14.0
				column_pose.origin = horizontal.origin+horizontal.basis.x*column_x+Vector3(0,87-horizontal.origin.y,0)
			assert(_route_clear(column_box,column_pose,12.0),"No clear column position within authored hall envelope")
			column_offsets.append(column_x)
			_solid(Vector3(1.6,142,2.0),column_pose,"4e5444","N02","hall_column")
		# Extend the roof beam to both adjusted supports; retain open skylight bays.
		var beam := Transform3D(horizontal.basis,Vector3(horizontal.origin.x,158,horizontal.origin.z))
		var beam_mid := (column_offsets[0]+column_offsets[1])*0.5
		_solid(Vector3(column_offsets[1]-column_offsets[0]+2,1.8,1.5),_at(beam,Vector3(beam_mid,0,0)),"4b5445","N02","skylight_beam")
		if i%3==0:
			_fixture(_at(beam,Vector3(0,-1.4,0)),"N02")
	# Far floor only establishes a deep warehouse well; it never fills the airborne gap.
	for i in range(10):
		var pose := _pose(track_id,i*55+27.5)
		pose.origin.y = 14.0
		pose.basis = _flat(pose)
		_solid(Vector3(125,2,56),pose,"3d453d","N02","well_floor",true)

func _apply_sample_lighting(session: Node3D, world: Node3D) -> void:
	for node: WorldEnvironment in session.find_children("*","WorldEnvironment",true,false):
		var env := node.environment.duplicate() as Environment
		node.environment = env
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("7b959d")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("aab6b6")
		env.ambient_light_energy = 0.34
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.fog_enabled = true
		env.fog_light_color = Color("889d9c")
		env.fog_light_energy = 0.45
		env.fog_density = 0.0022
		env.ssao_enabled = true
		env.ssao_intensity = 2.1
		env.ssao_radius = 2.4
		env.glow_enabled = true
		env.glow_intensity = 0.24
	for sun: DirectionalLight3D in session.find_children("*","DirectionalLight3D",true,false):
		sun.light_color = Color("d7e9ef")
		sun.light_energy = 1.4
		sun.rotation_degrees = Vector3(-52,-28,0)
	for at: Vector3 in rebuild_lights:
		var light := OmniLight3D.new()
		light.light_color = Color("ffe3a9")
		light.light_energy = 15
		light.omni_range = 46
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 180
		light.distance_fade_length = 80
		world.add_child(light)
		light.global_position = at
