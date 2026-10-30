extends RefCounted
## H07 collisionless authored environment and canonical G1 presentation. Human art acceptance remains pending.
const CEL = preload("res://themes/halloween_07/acid_cel.gdshader")
const TRACK_SURFACE = preload("res://themes/halloween_07/track_surface.gdshader")
const WINDOW_GLASS = preload("res://themes/halloween_07/window_glass.gdshader")
const WindowDetail = preload("res://themes/halloween_07/window_detail.gd")
const INK = preload("res://themes/halloween_07/outline.gdshader")
const SKY = preload("res://themes/halloween_07/night_sky.gdshader")
const SEGMENTS = ["station_start","station_carve","station_ramp","canyon_safe","canyon_fast_catch"]
const ModelLibrary=preload("res://themes/halloween_07/model_library.gd")
var models=ModelLibrary.new()
var model_buildings:=0
var model_lanterns:=0
var world: Node3D
var route: Node3D
var app: Node3D
var mats := {}
var batches := {}
var custom_batches := {}
var count := 0
var lights := 0
var shape_cache := {}
var wedge_merge_checks := []
var light_candidates := []
var city_anchors := []
var foundation_facades := []
var bridge_pier_interfaces := {}
var light_controller: Node3D
var record := []
var rng := RandomNumberGenerator.new()

func build(session: Node3D) -> Node3D:
	app=session
	rng.seed=20261028
	world=Node3D.new();world.name="H07CompositionProbe"
	world.set_meta("scene_id","station");world.set_meta("asset_id","h07_procedural_probe");world.set_meta("instance_id","h07_world")
	app.add_child(world)
	route=app.get_node("ControllerLab/RouteRoot/MainRoute")
	_materials();_reskin();_lighting();_tracks();_rail_hardware();_warning_marks();_streets();_facade_variants();_landmarks();_castle_network();_lower_city();_city_atmosphere();_skyline();_hazards();_train();_flush();_place_practicals()
	world.set_meta("construction_report",{"errors":models.errors,"probe_only":false,"production_stage":"authored_native_refinement_not_H4_accepted","mesh_instances":count,"practical_lights":lights,"paid_batch":"production-02 approved 7 G1; source canonical GLBs","route_and_camera_unchanged":true})
	world.set_meta("h07_geometry",record)
	world.set_meta("h07_fit_records",models.fits)
	world.set_meta("h07_city_anchors",city_anchors)
	world.set_meta("h07_wedge_merge",wedge_merge_checks)
	return world

func _mat(key: String,color: String,glow := 0.0,brick := false,ink := true) -> void:
	var m:=ShaderMaterial.new();m.shader=CEL;m.set_shader_parameter("paint",Color(color));m.set_shader_parameter("glow",glow);m.set_shader_parameter("masonry",1.0 if brick else 0.0)
	if ink:
		var edge:=ShaderMaterial.new();edge.shader=INK;m.next_pass=edge
	mats[key]=m
	m.set_shader_parameter("surface_kind",1.0 if key=="roof" else (2.0 if key in ["ink","edge"] else (3.0 if key=="stone" else (4.0 if key=="road" else 0.0))))

func _materials() -> void:
	_mat("gold","eab333",0.12,false,false);_mat("ink","110d28",0,false,false);_mat("violet","50376a",0,true);_mat("plum","6c3f78",0,true);_mat("brick","935d65",0,true);_mat("ochre","ac7864",0,true)
	_mat("roof","252f51");_mat("edge","293e62");_mat("cyan","79ced8",0.18);_mat("acid","d9ef29",0.28);_mat("pink","ee286f",0.4);_mat("warm","ff650c",0.45);_mat("window","ff7515",0.8)
	_mat("stone","736287",0,true);_mat("road","30283e",0,false,false);_mat("rail","9eaac6",0.05,false,false);_mat("far","222e43",0.018,false,false);_mat("far2","30304a",0.025,false,false)
	for spec in [["road",0],["sleeper",1],["rail",2]]:
		var m:=ShaderMaterial.new();m.shader=TRACK_SURFACE;m.set_shader_parameter("finish",spec[1]);mats[spec[0]]=m
	_mat("timber","9b633a",0.0);_mat("flag","b95b20",0.05);_mat("flag_purple","6b326c",0.0);_mat("warm_stone","8f6968",0.0,true);_mat("soffit","463346",0.0,false);
	_mat("hazard_trim","8a7f2d",0.035,false,false);_mat("window_dim","c96824",0.25);_mat("window_dark","4c3e59",0.015);_mat("warning_paint","d9367e",0.18,false,false);_mat("train_orange","b95d2f",0.10,false,false);_mat("worn_warm","96563f",0.015,false,false);_mat("ghost","70416c",0.0,false,false);mats.ghost.set_shader_parameter("graphic",1.0)
	mats.warning_paint.set_shader_parameter("brush_mark",1.0);mats.worn_warm.set_shader_parameter("brush_mark",1.0)
	_mat("window_frame","67505e",0.0,false,false);_mat("window_lead","160f22",0.0,false,false)
	for spec in [["glazing_lit","ec8c31",1.05],["glazing_dim","ae581f",.48],["glazing_dark","38304c",0.0]]:
		var m:=ShaderMaterial.new();m.shader=WINDOW_GLASS;m.set_shader_parameter("glass_color",Color(spec[1]));m.set_shader_parameter("interior_light",spec[2]);mats[spec[0]]=m
	var masonry_image:=Image.load_from_file(ProjectSettings.globalize_path("res://../art/train-parkour/styles/halloween-comic/materials/h07-painted-violet-masonry-v1.png"))
	var slate_image:=Image.load_from_file(ProjectSettings.globalize_path("res://../art/train-parkour/styles/halloween-comic/materials/h07-painted-blue-slate-v1.png"))
	var masonry_texture:=ImageTexture.create_from_image(masonry_image)
	var slate_texture:=ImageTexture.create_from_image(slate_image)
	for key in ["violet","plum","brick","ochre","stone","warm_stone"]:
		mats[key].set_shader_parameter("city_surface_light",1.0);mats[key].set_shader_parameter("paint_texture",masonry_texture);mats[key].set_shader_parameter("texture_mode",1.0)
	mats.roof.set_shader_parameter("paint_texture",slate_texture);mats.roof.set_shader_parameter("texture_mode",2.0)

func _box(p: Transform3D,size: Vector3,key: String) -> void:
	if not batches.has(key):batches[key]=[]
	batches[key].append(p.scaled_local(size));count+=1
	if key not in ["window","warm","cyan"]:record.append({"kind":"box","material":key,"center":[p.origin.x,p.origin.y,p.origin.z],"size":[size.x,size.y,size.z]})

func _at(p: Transform3D,pos: Vector3,size: Vector3,key: String) -> void:
	_box(p.translated_local(pos),size,key)

func _mesh(mesh: Mesh,p: Transform3D,key: String,ident: String) -> void:
	var m:=MeshInstance3D.new();m.mesh=mesh;m.material_override=mats[key];m.transform=p;m.name=ident
	m.set_meta("instance_id","h07_"+ident+"_"+str(count));world.add_child(m);count+=1

func _inst(mesh: Mesh,p: Transform3D,key: String,tag: String) -> void:
	var id:=tag+"_"+key
	if not custom_batches.has(id):custom_batches[id]={"mesh":mesh,"poses":[],"material":key}
	custom_batches[id].poses.append(p);count+=1

func _flush() -> void:
	for key: String in batches:
		var mesh:=BoxMesh.new();mesh.size=Vector3.ONE
		_make_batch(mesh,batches[key],key,"H07_"+key)
	for id: String in custom_batches:
		var row: Dictionary=custom_batches[id]
		_make_batch(row.mesh,row.poses,row.material,id)

func _make_batch(mesh: Mesh,poses: Array,key: String,id: String) -> void:
	# Spatial cells retain all authored detail while permitting meaningful native frustum culling.
	var chunks: Dictionary={}
	for pose: Transform3D in poses:
		var cell:=Vector3i(floori(pose.origin.x/128.0),floori(pose.origin.y/96.0),floori(pose.origin.z/128.0))
		if not chunks.has(cell):chunks[cell]=[]
		chunks[cell].append(pose)
	for cell: Vector3i in chunks:
		var origin:=Vector3(cell)*Vector3(128,96,128)
		var local_poses: Array=chunks[cell]
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=local_poses.size()
		for i in mm.instance_count:
			var pose: Transform3D=local_poses[i];pose.origin-=origin;mm.set_instance_transform(i,pose)
		var node:=MultiMeshInstance3D.new();node.name=id+"_"+str(cell);node.position=origin;node.multimesh=mm;node.set_meta("instance_id","h07_"+node.name);world.add_child(node)
		if not key.is_empty():node.material_override=mats[key]

func _tri(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3) -> void:
	st.add_vertex(a);st.add_vertex(b);st.add_vertex(c)

func _profile(p: Transform3D,w: float,d: float,levels: Array,key: String) -> void:
	var id:="profile_"+str(w)+"_"+str(d)+"_"+str(levels)
	if not shape_cache.has(id):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rings:=[]
		for level: Vector2 in levels:
			var x:=w*0.5*level.y;var z:=d*0.5*level.y;var c:=minf(x,z)*0.22
			rings.append([Vector3(-x+c,level.x,-z),Vector3(x-c,level.x,-z),Vector3(x,level.x,-z+c),Vector3(x,level.x,z-c),Vector3(x-c,level.x,z),Vector3(-x+c,level.x,z),Vector3(-x,level.x,z-c),Vector3(-x,level.x,-z+c)])
		for k in rings.size()-1:
			for j in 8:
				var n:=(j+1)%8
				_tri(st,rings[k][j],rings[k+1][n],rings[k][n]);_tri(st,rings[k][j],rings[k+1][j],rings[k+1][n])
		for j in range(1,7):
			_tri(st,rings[0][0],rings[0][j],rings[0][j+1]);_tri(st,rings[-1][0],rings[-1][j+1],rings[-1][j])
		st.generate_normals();shape_cache[id]=st.commit()
	_inst(shape_cache[id],p,key,id)

func _prism(p: Transform3D,points: PackedVector2Array,depth: float,key: String,tag: String) -> void:
	_inst(_prism_mesh(points,depth,tag),p,key,tag+"_"+str(points)+"_"+str(depth))

func _prism_mesh(points: PackedVector2Array,depth: float,tag: String) -> ArrayMesh:
	var id:=tag+"_"+str(points)+"_"+str(depth)
	if not shape_cache.has(id):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tri:=Geometry2D.triangulate_polygon(points)
		for i in range(0,tri.size(),3):
			var a: Vector2=points[tri[i]];var b: Vector2=points[tri[i+1]];var c: Vector2=points[tri[i+2]]
			_tri(st,Vector3(a.x,a.y,-depth/2),Vector3(c.x,c.y,-depth/2),Vector3(b.x,b.y,-depth/2));_tri(st,Vector3(a.x,a.y,depth/2),Vector3(b.x,b.y,depth/2),Vector3(c.x,c.y,depth/2))
		for i in points.size():
			var a: Vector2=points[i];var b: Vector2=points[(i+1)%points.size()]
			_tri(st,Vector3(a.x,a.y,-depth/2),Vector3(b.x,b.y,-depth/2),Vector3(b.x,b.y,depth/2));_tri(st,Vector3(a.x,a.y,-depth/2),Vector3(b.x,b.y,depth/2),Vector3(a.x,a.y,depth/2))
		st.generate_normals()
		var source_arrays:=st.commit_to_arrays()
		if tag in ["rough_flush_warning_brush","dry_track_wear","window_glazing_v2"]:
			var uv:=PackedVector2Array();var minp:=points[0];var maxp:=points[0]
			for point: Vector2 in points:minp=minp.min(point);maxp=maxp.max(point)
			for vertex: Vector3 in source_arrays[Mesh.ARRAY_VERTEX]:uv.append((Vector2(vertex.x,vertex.y)-minp)/(maxp-minp))
			source_arrays[Mesh.ARRAY_TEX_UV]=uv
			var painted_mesh:=ArrayMesh.new();painted_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source_arrays);shape_cache[id]=painted_mesh
		else:shape_cache[id]=st.commit()
		if tag=="radial_voussoir":shape_cache[id].set_meta("unpacked_normal_source",source_arrays[Mesh.ARRAY_NORMAL])
	return shape_cache[id]

func _wedge_bay(radius: float,spring: float,depth: float,cx: float) -> ArrayMesh:
	var id:="merged_wedge_bay_"+str(radius)+"_"+str(spring)+"_"+str(depth)+"_"+str(cx)
	if shape_cache.has(id):return shape_cache[id]
	var expected: Dictionary={}
	for key in ["stone","warm_stone"]:
		expected[key]={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"input_normals":PackedVector3Array()}
	for i in 25:
		var a0:=i*PI/25.0+0.007;var a1:=(i+1)*PI/25.0-0.007;var outer:=radius+1.65
		var points:=PackedVector2Array([Vector2(cx+cos(a0)*radius,spring+sin(a0)*radius),Vector2(cx+cos(a1)*radius,spring+sin(a1)*radius),Vector2(cx+cos(a1)*outer,spring+sin(a1)*outer),Vector2(cx+cos(a0)*outer,spring+sin(a0)*outer)])
		var key: String="stone" if i%4 else "warm_stone"
		var original:=_prism_mesh(points,depth+0.65,"radial_voussoir")
		var arrays:=original.surface_get_arrays(0)
		expected[key].vertices.append_array(arrays[Mesh.ARRAY_VERTEX]);expected[key].normals.append_array(arrays[Mesh.ARRAY_NORMAL]);expected[key].input_normals.append_array(original.get_meta("unpacked_normal_source"))
	var mesh:=ArrayMesh.new();var valid:=true;var vertices:=0
	for key in ["stone","warm_stone"]:
		var inputs: Array=[];inputs.resize(Mesh.ARRAY_MAX);inputs[Mesh.ARRAY_VERTEX]=expected[key].vertices;inputs[Mesh.ARRAY_NORMAL]=expected[key].input_normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,inputs);mesh.surface_set_material(mesh.get_surface_count()-1,mats[key])
		var arrays:=mesh.surface_get_arrays(mesh.get_surface_count()-1)
		var vertex_equal:=var_to_bytes(arrays[Mesh.ARRAY_VERTEX])==var_to_bytes(expected[key].vertices)
		var normal_equal:=var_to_bytes(arrays[Mesh.ARRAY_NORMAL])==var_to_bytes(expected[key].normals)
		var max_v:=0.0;var max_n:=0.0
		for j in arrays[Mesh.ARRAY_VERTEX].size():
			max_v=maxf(max_v,arrays[Mesh.ARRAY_VERTEX][j].distance_to(expected[key].vertices[j]));max_n=maxf(max_n,arrays[Mesh.ARRAY_NORMAL][j].distance_to(expected[key].normals[j]))
		if not (vertex_equal and normal_equal):print("MERGE_ARRAY_DIAGNOSTIC ",key," maxV=",max_v," maxN=",max_n)
		valid=valid and vertex_equal and normal_equal
		vertices+=arrays[Mesh.ARRAY_VERTEX].size()
	assert(valid,"Wedge batching changed vertices/normals")
	wedge_merge_checks.append({"id":id,"original_wedges":25,"surfaces":mesh.get_surface_count(),"vertices":vertices,"triangles":vertices/3,"vertex_and_normal_bytes_equal":valid,"seams_and_barrel_faces_retained":true})
	shape_cache[id]=mesh;return mesh

func _brace(p: Transform3D,side: float) -> void:
	var poly:=PackedVector2Array()
	for i in 17:
		var a:=i*PI/32;poly.append(Vector2(side*(0.2+4.8*sin(a)),15.7-4.8*cos(a)))
	for i in range(16,-1,-1):
		var a:=i*PI/32;poly.append(Vector2(side*(0.2+4.35*sin(a)),15.7-4.35*cos(a)))
	_prism(p,poly,0.48,"ink","curved_canopy_brace")
	_at(p,Vector3(side*2.2,14.9,0),Vector3(0.22,1.5,0.65),"edge")

func _place_practicals() -> void:
	for id in ["station_carve","canyon_safe"]:
		var track: SpatialTrack=route.tracks[id]
		for i in int(track.length/64.0):
			for side in [-1.0,1.0]:
				var p:=_level(track,25+i*64,side*17).translated_local(Vector3(0,3.8,0))
				light_candidates.append({"p":p.origin,"energy":23.0,"range":33.0})
	light_controller=preload("res://themes/halloween_07/practical_lights.gd").new();light_controller.name="H07WarmLightPool";world.add_child(light_controller)
	light_controller.configure(light_candidates,app.get_node("RailCamera"));lights=24

func sync_view(camera: Camera3D) -> void:
	if is_instance_valid(light_controller):light_controller.sync_view(camera)

func _level(track: SpatialTrack,s: float,side := 0.0) -> Transform3D:
	var p:=track.pose(s,side);var forward:=-p.basis.z;forward.y=0;forward=forward.normalized()
	return Transform3D(Basis.looking_at(forward,Vector3.UP),p.origin)

func _pose_key(p: Transform3D) -> String:
	return str(p.origin.snapped(Vector3.ONE*0.001))+":"+str(p.basis.get_scale().snapped(Vector3.ONE*0.001))

func _reskin() -> void:
	# Duplicate gameplay-owned batch names are anonymous in Godot; identify the seven replaced blocks by their frozen poses.
	var block_poses: Dictionary={}
	for id in ["station_start","station_carve","canyon_safe"]:
		var track: SpatialTrack=route.tracks[id]
		for ob: Dictionary in track.obstacles:
			if ob.get("kind","")!="block":continue
			for lane in ob.lanes:
				var p:=track.pose(ob.s,lane*4.4).translated_local(Vector3(0,float(ob.height)*0.5,0)).scaled_local(Vector3(3,float(ob.height),2))
				block_poses[_pose_key(p)]=true
	for n: Node in app.get_node("ControllerLab/EnvironmentRoot").get_children():
		if n is GeometryInstance3D:n.visible=false
	for n: Node in app.get_node("ControllerLab/PresentationRoot").find_children("*","GeometryInstance3D",true,false):
		var name:=str(n.name)
		if n is MultiMeshInstance3D and n.multimesh.instance_count==1 and n.multimesh.mesh is BoxMesh and n.multimesh.mesh.size.is_equal_approx(Vector3.ONE):
			if block_poses.has(_pose_key(n.global_transform*n.multimesh.get_instance_transform(0))):n.visible=false;continue
		if name.begins_with("NearMasses") or name.begins_with("NearSpeedMarkers") or name.begins_with("StationGround") or name.begins_with("DistantPiers"):n.visible=false
		elif name.begins_with("Bed"):n.material_override=mats.road
		elif name.begins_with("Rail"):
			n.material_override=mats.gold if str(n.get_parent().name).begins_with("canyon_fast_catch") else mats.rail
		elif name.begins_with("EdgeCurbs"):n.material_override=mats.rail
		elif name.begins_with("Ties"):n.material_override=mats.sleeper
		elif name.begins_with("TrackPiers") or name.begins_with("ContactStructure"):n.material_override=mats.ink
		elif name.begins_with("ApproachMarks") or name.begins_with("NoEntrySign"):n.material_override=mats.pink
		elif name.begins_with("SoftProp"):n.material_override=mats.warm

func _lighting() -> void:
	var node: WorldEnvironment=app.get_node("ControllerLab/EnvironmentRoot/WorldEnvironment")
	var env:=node.environment.duplicate() as Environment
	var sky:=Sky.new();var sm:=ShaderMaterial.new();sm.shader=SKY;sky.sky_material=sm
	var moon_image:=Image.load_from_file(ProjectSettings.globalize_path("res://../art/train-parkour/styles/halloween-comic/materials/continuation-v3/h07-painted-moon-v2.png"))
	sm.set_shader_parameter("moon_paint",ImageTexture.create_from_image(moon_image))
	var cloud_image:=Image.load_from_file(ProjectSettings.globalize_path("res://../art/train-parkour/styles/halloween-comic/materials/continuation-v3/h07-painted-cloud-v1.png"))
	sm.set_shader_parameter("cloud_paint",ImageTexture.create_from_image(cloud_image))
	env.background_mode=Environment.BG_SKY;env.sky=sky;env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("7942a9");env.ambient_light_energy=0.20
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env.tonemap_exposure=0.95
	env.fog_enabled=true;env.fog_light_color=Color("674a94");env.fog_density=0.00048;env.fog_sky_affect=0.0
	env.ssao_enabled=true;env.ssao_radius=1.8;env.ssao_intensity=1.8
	env.ssil_enabled=true;env.ssil_radius=4.0;env.ssil_intensity=0.85
	env.glow_enabled=true;env.glow_intensity=0.45;env.glow_bloom=0.08
	env.ssr_enabled=true
	env.volumetric_fog_enabled=false
	node.environment=env
	var sun: DirectionalLight3D=app.get_node("ControllerLab/EnvironmentRoot/Sun")
	sun.rotation_degrees=Vector3(-38,-30,0);sun.light_color=Color("82d8ef");sun.light_energy=0.50;sun.shadow_enabled=true;sun.directional_shadow_max_distance=230.0

func _tracks() -> void:
	var ramp: SpatialTrack=route.tracks.station_ramp
	for s in [8.0,24.0,40.0]:
		var p:=ramp.pose(minf(s,ramp.length))
		for side in [-1.0,1.0]:
			_at(p,Vector3(side*ramp.half_width*0.78,0.12,0),Vector3(0.48,0.22,0.6),"ink")
			_at(p,Vector3(side*1.9,0.62,0),Vector3(0.55,0.18,0.71),"edge")
	for id: String in SEGMENTS:
		var t: SpatialTrack=route.tracks[id];var limit:=t.length
		for i in ceili(limit/8.0):
			var s:=minf((i+0.5)*8.0,limit);var p:=t.pose(s);var half:=t.width_at(s)
			_at(p,Vector3(0,-1.05,0),Vector3(half*2.0+0.6,1.25,8.04),"ink")
			for side in [-1.0,1.0]:
				_at(p,Vector3(side*(half+0.5),-0.45,0),Vector3(0.75,0.65,8.04),"stone")
				if i%3==0:
					_at(p,Vector3(side*(half+0.55),1.0,0),Vector3(0.16,2.3,0.17),"ink")
					_at(p,Vector3(side*(half+0.55),1.95,0),Vector3(0.25,0.14,24.0),"ink")
					_at(p,Vector3(side*(half+0.55),1.25,0),Vector3(0.12,0.1,24.0),"edge")
			if i%3==1:
				for lane in [-1.0,0.0,1.0]:
					# Irregular narrow wear follows one rail contact; it is not an extra transverse route marking.
					var patch:=p.translated_local(Vector3(lane*4.4+(-1.57 if i%2 else 1.57),0.065,-2.5+float((i+int(lane))%3)));patch.basis=patch.basis*Basis(Vector3.RIGHT,-PI/2)
					_prism(patch,PackedVector2Array([Vector2(-0.10,-1.6),Vector2(-0.04,-2.0),Vector2(0.10,-1.2),Vector2(0.07,-0.3),Vector2(0.14,0.8),Vector2(0.04,1.8),Vector2(-0.08,1.2),Vector2(-0.05,0.0)]),0.008,"worn_warm","dry_track_wear")
			if i%5==0 and id not in ["station_ramp","canyon_fast_catch"]:
				_at(p,Vector3(0,-6.0,0),Vector3(half*2.0+1.0,0.7,1.3),"violet")
				for side in [-1.0,1.0]:_at(p,Vector3(side*(half-1),-18,0),Vector3(1.3,34,1.8),"violet")

func _rail_hardware() -> void:
	for track: SpatialTrack in route.tracks.values():
		if track.single_lane:continue
		for i in ceili(track.length/2.0):
			var s := float(i)*2.0
			if s>=track.length:continue
			var p := track.pose(s)
			for lane: int in track.lanes():
				if i%4!=1:_at(p,Vector3(lane*4.4,-.04,0),Vector3(2.1,.10,.30),"sleeper")
				for side: float in [-1.0,1.0]:
					_at(p,Vector3(lane*4.4+side*.72,.022,0),Vector3(.39,.025,.28),"ink")
					_at(p,Vector3(lane*4.4+side*.90,.048,0),Vector3(.065,.055,.10),"rail")

func _roof(p: Transform3D,w: float,h: float,d: float,key: String) -> void:
	var mesh:=PrismMesh.new();mesh.size=Vector3(w,h,d);mesh.left_to_right=0.5
	_mesh(mesh,p,key,"crooked_roof")

func _building(p: Transform3D,side: float,w: float,h: float,depth: float,index: int,distant := false) -> void:
	if distant:
		var base:=p.translated_local(Vector3(0,-34,0));var key: String="far" if index%2==0 else "far2"
		_profile(base,depth,w,[Vector2(0,1.1),Vector2(3,1.1),Vector2(5,1),Vector2(h*0.48,1),Vector2(h*0.48+1,1.04),Vector2(h*0.48+2,1),Vector2(h-3,0.91),Vector2(h,1.03)],key)
		_roof(base.translated_local(Vector3(0,h+7,0)),depth+2,14,w+2,key)
		for sign in [-1.0,1.0]:
			_profile(base.translated_local(Vector3(sign*depth*0.32,h+5,sign*w*0.2)),3,3,[Vector2(0,1),Vector2(10+index%3*3,0.8),Vector2(11+index%3*3,1.15)],key)
		return
	if not distant and model_buildings<24:
		var house:=models.place("h07_facade_a",world,p.translated_local(Vector3(side*9,-18,0)),Vector3(depth+18,h+8,w+2),PI/2 if side<0 else -PI/2,"H07HouseA_"+str(model_buildings),420.0)
		if house!=null:
			_ghost_wall(p.translated_local(Vector3(-side*7.4,-18.0,-2.0)),side,13.0,30.0,"house_mural_field")
			model_buildings+=1
			var foundation_height:=maxf(1.0,p.origin.y-36.0)
			_profile(p.translated_local(Vector3(side*9,-18-foundation_height,0)),depth+18,w+2,[Vector2(0,1.05),Vector2(2.0,1.05),Vector2(foundation_height-0.7,1),Vector2(foundation_height,1.03)],"violet")
			_lantern(p.translated_local(Vector3(-side*(depth*0.5+1.0),2.5,-w*0.28)),index)
			return
	var key: String=["brick","ochre","plum","violet"][index%4] if not distant else ("far" if index%2==0 else "far2")
	var bottom:=-34.0;var top:=bottom+h
	var base:=p;var lean:=deg_to_rad(float((index%5)-2)*1.15);base.basis=base.basis.rotated(Vector3.FORWARD,lean)
	_at(base,Vector3(0,bottom+h*0.5,0),Vector3(depth,h,w),key)
	# A visible lower masonry footing joins every street mass to the common valley floor.
	var foundation_height:=maxf(0.0,p.origin.y+bottom-18.0)
	if not distant and foundation_height>1.0:_at(base,Vector3(0,bottom-foundation_height*0.5,0),Vector3(depth+0.2,foundation_height,w+0.2),"violet")
	_at(base,Vector3(0,bottom+1.8,0),Vector3(depth+1.2,3.6,w+1.0),"stone" if not distant else key)
	_at(base,Vector3(0,top-0.5,0),Vector3(depth+0.9,0.8,w+1.0),"ink" if not distant else key)
	_roof(base.translated_local(Vector3(0,top+3,0)),depth+1.9,6,w+2,"roof" if not distant else key)
	_at(base,Vector3(depth*0.21,top+7,-w*0.23),Vector3(1.6,6,2),"brick" if not distant else key)
	_at(base,Vector3(depth*0.21,top+10,-w*0.23),Vector3(2.2,0.7,2.7),"ink" if not distant else key)
	if distant:return
	var face:=-side*(depth*0.5+0.04)
	for floor_id in maxi(1,int(h/6.0)-1):
		var y:=bottom+5+float(floor_id)*6.2
		for column in 3:
			var z:=(float(column)-1.0)*w*0.27
			WindowDetail.build(self,base.translated_local(Vector3(face,y,z)),side,2.7,4.1,"window" if (index+floor_id+column)%4!=0 else "window_dark",false)
	for y in [top-1.7,top-6.7]:_at(base,Vector3(face,y,0),Vector3(0.65,0.42,w+0.3),"edge")
	# Street-facing ghost mural with a recessed frame; geometry stays outside the lane envelope.
	if index%3==0:
		var quad:=QuadMesh.new();quad.size=Vector2(5.0,9.0)
		var qp:=base.translated_local(Vector3(face-side*0.5,2.0,w*0.25));qp.basis=qp.basis*Basis(Vector3.UP,-side*PI/2.0)
		_mesh(quad,qp,"ghost","ghost_mural")
		_at(base,Vector3(face-side*1.0,-3.4,w*0.25),Vector3(2.3,0.35,5.7),"pink")
	if index%2==0:
		var awn:=base.translated_local(Vector3(face-side*0.9,0.5,-w*0.26));awn.basis=awn.basis*Basis(Vector3.FORWARD,side*0.18)
		for stripe in 5:_at(awn,Vector3(0,0,(stripe-2)*0.85),Vector3(2.5,0.35,0.84),"pink" if stripe%2==0 else "violet")
	_lantern(base.translated_local(Vector3(face-side*2.1,5.2,-w*0.38)),index)
	# Three visually varied rooftop fins, kept above the playable/camera volume.
	for fin in 3:
		_at(base,Vector3(face+side*0.3,top+3.0,(fin-1)*w*0.32),Vector3(0.18,3.0,0.18),"ink")

func _lantern(p: Transform3D,index: int) -> void:
	if model_lanterns<96:
		var lantern:=models.place("h07_lantern",world,p.translated_local(Vector3(0,-0.85,0)),Vector3(2.1,3.1,2.1),0,"H07Lantern_"+str(model_lanterns),150.0)
		if lantern!=null:
			model_lanterns+=1
			_at(p,Vector3(0,2.6,0),Vector3(0.14,2.0,0.14),"ink")
			light_candidates.append({"p":p.origin,"energy":38.0,"range":30.0,"role":"lantern"})
			return
	_at(p,Vector3(0,2.5,0),Vector3(0.12,2.2,0.12),"ink")
	_at(p,Vector3(0,1.3,0),Vector3(1.8,0.25,1.8),"ink")
	var ball:=SphereMesh.new();ball.radius=1.0;ball.height=1.65;ball.radial_segments=12;ball.rings=6
	_mesh(ball,p,"warm","pumpkin_lantern")
	for k in 8:
		var a:=float(k)*TAU/8;_at(p,Vector3(cos(a)*0.98,0,sin(a)*0.98),Vector3(0.065,1.62,0.065),"ink")
	_at(p,Vector3(0,-0.8,0),Vector3(1.8,0.2,1.8),"ink")
	# Eyes/mouth on both approach directions, readable in a fast rear chase camera.
	for side in [-1.0,1.0]:
		for eye in [-1.0,1.0]:
			var ep:=p.translated_local(Vector3(eye*0.33,0.24,side*0.86));ep.basis=ep.basis*Basis(Vector3.FORWARD,eye*0.35)
			_box(ep,Vector3(0.35,0.15,0.06),"ink")
		_at(p,Vector3(0,-0.32,side*0.86),Vector3(0.72,0.18,0.06),"ink")
	light_candidates.append({"p":p.origin,"energy":38.0,"range":30.0,"role":"lantern"})

func _festival_flag(pp: Transform3D,key: String) -> void:
	var flag:=PackedVector2Array([Vector2(-1.15,1.2),Vector2(1.15,1.2),Vector2(1.15,-1.2),Vector2(0,-0.58),Vector2(-1.15,-1.2)])
	_prism(pp,flag,0.055,key,"swallowtail_festival_flag")
	var bat:=PackedVector2Array([Vector2(-0.94,0.0),Vector2(-0.66,0.35),Vector2(-0.38,0.16),Vector2(-0.18,0.28),Vector2(-0.10,0.55),Vector2(0,0.30),Vector2(0.10,0.55),Vector2(0.18,0.28),Vector2(0.38,0.16),Vector2(0.66,0.35),Vector2(0.94,0),Vector2(0.70,-0.08),Vector2(0.50,-0.06),Vector2(0.37,-0.26),Vector2(0.18,-0.09),Vector2(0,-0.22),Vector2(-0.18,-0.09),Vector2(-0.37,-0.26),Vector2(-0.50,-0.06),Vector2(-0.70,-0.08)])
	for face in [-1.0,1.0]:_prism(pp.translated_local(Vector3(0,0,face*0.04)),bat,0.012,"ink","bat_flag_graphic")

func _station_festival() -> void:
	var track: SpatialTrack=route.tracks.station_start
	for i in 25:
		var p:=_level(track,12+i*24)
		for side in [-1.0,1.0]:
			_at(p,Vector3(side*22.7,14.55,0),Vector3(21.5,0.13,0.13),"ink")
			for k in 5:
				var flag:=p.translated_local(Vector3(side*(14.5+k*4.0),12.9,0)).scaled_local(Vector3.ONE*1.25)
				_festival_flag(flag,"flag" if (i+k)%2==0 else "flag_purple")
	for distance in [72.0,168.0,264.0,320.0,416.0,512.0]:
		for side in [-1.0,1.0]:
			var p:=_level(track,distance,side*25)
			_station_bench(p,side)
			_barrel(p.translated_local(Vector3(side*2.2,0,-4.1)))
			var crate:=p.translated_local(Vector3(side*4.6,1.15,-3.5))
			_at(crate,Vector3.ZERO,Vector3(2.0,2.2,2.0),"timber")
			for y in [-0.8,0.8]:_at(crate,Vector3(0,y,0),Vector3(2.15,0.18,2.15),"ink")
func _station_bench(p: Transform3D,side: float) -> void:
	for i in 5:_at(p,Vector3((i-2)*0.34,1.18,0),Vector3(0.29,0.18,5.8),"timber")
	for y in [1.65,2.02,2.39]:_at(p,Vector3(side*0.91,y,0),Vector3(0.18,0.27,5.8),"timber")
	for z in [-2.35,2.35]:
		for x in [-0.68,0.68]:_profile(p.translated_local(Vector3(x,0,z)),0.24,0.34,[Vector2(0,1.35),Vector2(0.2,1.35),Vector2(1.15,0.8)],"ink")
		_at(p,Vector3(0,0.99,z),Vector3(2.0,0.18,0.3),"ink")
		_at(p,Vector3(side*0.86,1.86,z),Vector3(0.22,1.8,0.26),"ink")
		_at(p,Vector3(0,1.65,z),Vector3(2.0,0.16,0.24),"ink")

func _barrel(p: Transform3D) -> void:
	_profile(p,2.25,2.25,[Vector2(0,0.80),Vector2(0.18,0.88),Vector2(0.65,1),Vector2(2.0,1),Vector2(2.6,0.84),Vector2(2.72,0.84)],"timber")
	for y in [0.38,2.22]:_profile(p.translated_local(Vector3(0,y,0)),2.32,2.32,[Vector2(0,0.95),Vector2(0.2,0.97)],"ink")
	_profile(p.translated_local(Vector3(0,2.72,0)),1.9,1.9,[Vector2(0,1),Vector2(0.1,1)],"timber")

func _warning_marks() -> void:
	var lab: Node=app.get_node("ControllerLab")
	for id in ["station_start","station_carve","canyon_safe"]:
		var track: SpatialTrack=route.tracks[id]
		for ob: Dictionary in track.obstacles:
			var preview:=maxf(float(ob.get("preview_seconds",1.8))*175.0,170.0)
			for ratio in [1.0,0.72,0.48,0.28]:
				var p: Transform3D=lab.call("_approach_pose",route,track,float(ob.s)-preview*ratio)
				for lane in ob.lanes:
					for sign in [-1.0,1.0]:
						var x:=p.translated_local(Vector3(float(lane)*4.4,0.235,0));x.basis=x.basis*Basis(Vector3.UP,sign*PI/4)
						x.basis=x.basis*Basis(Vector3.RIGHT,-PI/2)
						var brush:=PackedVector2Array([Vector2(-0.24,-1.90),Vector2(-0.17,-2.07),Vector2(-0.12,-1.76),Vector2(-0.06,-2.02),Vector2(0,-1.73),Vector2(0.08,-2.10),Vector2(0.14,-1.82),Vector2(0.21,-2.01),Vector2(0.25,-1.60),Vector2(0.18,-0.8),Vector2(0.25,-0.1),Vector2(0.19,0.65),Vector2(0.24,1.36),Vector2(0.22,1.84),Vector2(0.12,2.05),Vector2(0.08,1.72),Vector2(0,2.10),Vector2(-0.08,1.84),Vector2(-0.16,2.04),Vector2(-0.24,1.64),Vector2(-0.18,0.80),Vector2(-0.25,0.19),Vector2(-0.19,-0.54),Vector2(-0.25,-1.30)])
						_prism(x,brush,0.018,"warning_paint","rough_flush_warning_brush")

func _station_platforms() -> void:
	_station_festival()
	var t: SpatialTrack=route.tracks.station_start
	var pitch:=t.length/75.0
	for i in 75:
		var p:=_level(t,(i+0.5)*pitch)
		for side in [-1.0,1.0]:
			_at(p,Vector3(side*21.5,-0.4,0),Vector3(25,1.8,pitch+0.03),"stone")
			_at(p,Vector3(side*9.28,0.55,0),Vector3(0.55,0.16,pitch+0.03),"ochre")
			_at(p,Vector3(side*9.02,0.3,0),Vector3(0.14,0.6,pitch+0.03),"warm_stone")
			_at(p,Vector3(side*34,7.5,0),Vector3(2.4,17.5,pitch+0.03),"plum" if i%5 else "violet")
			_at(p,Vector3(side*21.4,17.2,0),Vector3(26,1.9,pitch+0.03),"roof")
			# Multi-course cornice with underside rebate and a narrow cool exposed cap.
			for course in [[15.85,0.8,0.38],[16.2,1.05,0.22],[16.65,0.7,0.65],[17.25,0.78,0.48],[17.65,1.15,0.24]]:
				var y: float=course[0];var w: float=course[1];var h: float=course[2]
				_at(p,Vector3(side*8.65,y,0),Vector3(w,h,pitch+0.03),"stone" if y>16 else "ink")
			_at(p,Vector3(side*8.4,18.4,0),Vector3(0.18,0.16,pitch+0.03),"edge")
			# Deep soffit panels show transverse weight and coffer rhythm at actual viewing scale.
			for k in 5:
				_at(p,Vector3(side*(10.8+k*4.75),16.18,0),Vector3(4.35,0.2,pitch-0.65),"soffit")
				_at(p,Vector3(side*(10.8+k*4.75),15.98,-pitch*0.47),Vector3(4.6,0.28,0.22),"ink")
			_at(p,Vector3(side*21.5,15.92,-pitch*0.49),Vector3(25.2,0.6,0.55),"ink")
			if i%4!=0:_gothic_window(p.translated_local(Vector3(side*32.68,6.35,0)),side,4.3,8.2,"window_dark" if (i+int(side>0)*3)%11 in [5,6] else ("window_dim" if i%7 in [3,4] else "window"))
			for y in [1.2,12.7,15.1]:_at(p,Vector3(side*32.6,y,0),Vector3(0.55,0.4,pitch+0.03),"warm_stone")
			if i%3==1:
				# Fixture at a front-bracket socket, with separate real rear-window light pool.
				_lantern(p.translated_local(Vector3(side*16.5,12.4,0)),i*2+int(side>0))
				light_candidates.append({"p":p.translated_local(Vector3(side*27.5,4.8,0)).origin,"energy":18.0,"range":15.0})
			if i%4==0:
				# Full-length ragged mural directly on the recessed back wall, between window bays.
				_mural(p.translated_local(Vector3(side*32.63,7.8,0)),side,7.4,14.6,"platform_ghost")
				for y in [1.0,2.2]:_at(p,Vector3(side*27,y,0),Vector3(1.35,0.18,3.7),"soffit")
				for z in [-1.3,1.3]:_at(p,Vector3(side*27,0.7,z),Vector3(0.24,1.4,0.35),"ink")
			var h:=maxf(1,p.origin.y-20)
			_at(p,Vector3(side*22,-h*0.5-1.3,0),Vector3(24,h,pitch+0.03),"violet")
	for i in 76:
		var p:=_level(t,i*pitch)
		for side in [-1.0,1.0]:
			var post:=p.translated_local(Vector3(side*12.2,0,0))
			_profile(post,2.45,2.45,[Vector2(0.45,1),Vector2(0.7,1),Vector2(1.05,0.86),Vector2(1.5,0.86),Vector2(1.8,0.64),Vector2(2.1,0.52)],"stone")
			_profile(post,1.15,1.15,[Vector2(2.0,1),Vector2(2.35,1),Vector2(2.5,0.83),Vector2(13.8,0.83),Vector2(14.05,1),Vector2(14.45,1.05)],"edge")
			_profile(post,2.25,2.25,[Vector2(14.3,0.58),Vector2(14.55,0.68),Vector2(14.8,0.75),Vector2(15.2,1),Vector2(15.55,1),Vector2(15.75,1.15)],"stone")
			_brace(post,side)
			_at(p,Vector3(side*32.62,7.8,0),Vector3(0.9,16.5,0.85),"warm_stone")

func _gothic_window(p: Transform3D,side: float,w: float,h: float,glass: String="window") -> void:
	WindowDetail.build(self,p,side,w,h,glass,true)


func _streets() -> void:
	_station_platforms()
	var index:=0
	var carve: SpatialTrack=route.tracks.station_carve
	for i in ceili(carve.length/34.0):
		for side in [-1.0,1.0]:
			# The bend opens between castle groups; repeated full-height walls hid the city.
			var s:=i*34.0+6
			if i==6:s+=24.0 # Move the last wall field into the bend view, outside the frozen route envelope.
			if i%4==3 or i>=7:continue
			_building(_level(carve,s,side*(29.0 if i<6 else 35.0)),side,28,48+rng.randf_range(-5,10),14,index)
			index+=1
	var ramp: SpatialTrack=route.tracks.station_ramp
	for side in [-1.0,1.0]:
		# Tower-framed release with broad side voids, rather than a continuous alley.
		_tower(_level(ramp,10,side*43),side,87+side*7,index,false,true);index+=1
	var safe: SpatialTrack=route.tracks.canyon_safe
	for i in 28:
		var s:=i*30.0+5
		# Right-hand thick city; left side is a supported open viaduct.
		if i%4!=3 and i not in [3,4,5,6,8,9,10]:
			_building(_level(safe,s,34.0 if i<5 else 28.0),1,25,58+rng.randf_range(-6,12),17,index);index+=1
		if i%4==0:_tower(_level(safe,s,-46),-1,77+float(i%3)*8,index,false,true,27.0)
		if i%3==0:_viaduct(_level(safe,s,-34).rotated_local(Vector3.UP,PI/2),3,30,27,-74,6,"violet",i==0)

	# Paired near gate towers and thick buttressed keep; expose both air-side voids.
	_gatehouse(_level(safe,180,43),1,0)
	_viaduct(_level(safe,90,57).rotated_local(Vector3.UP,PI/2),4,40,16,-86,8,"violet")
	_gatehouse(_level(safe,275,38),1,1)

func _facade_variants() -> void:
	var slots: Array=[]
	for distance in [96.0,288.0,480.0]:
		for side in [-1.0,1.0]:slots.append({"track":"station_start","s":distance,"side":side*51,"floor":0.5})
	for side in [-1.0,1.0]:slots.append({"track":"station_carve","s":300.0,"side":side*65,"floor":-55.0})
	for distance in [190.0,520.0]:
		for side in [-1.0,1.0]:slots.append({"track":"canyon_safe","s":distance,"side":side*78,"floor":-62.0})
	for i in slots.size():
		var slot: Dictionary=slots[i];var track: SpatialTrack=route.tracks[slot.track]
		var p:=_level(track,slot.s,slot.side).translated_local(Vector3(0,slot.floor,0))
		var house:=models.place("h07_facade_b",world,p,Vector3(28,31,40),PI/2 if slot.side<0 else -PI/2,"H07HouseB_"+str(i),440.0)
		if house!=null:
			var height:=maxf(8,p.origin.y-18)
			_profile(p.translated_local(Vector3(0,-height,0)),29,41,[Vector2(0,1.1),Vector2(2,1.1),Vector2(height-1,1),Vector2(height+0.6,1.02)],"violet")

func _gatehouse(p: Transform3D,side: float,index: int) -> void:
	var keep:=models.place("h07_castle_keep",world,p.translated_local(Vector3(side*14,-38,0)),Vector3(35,90,70),PI/2 if side<0 else -PI/2,"H07ReceiveKeep_"+str(index),500.0)
	if keep!=null:
		var height:=maxf(4.0,p.origin.y-56.0)
		_profile(p.translated_local(Vector3(side*14,-38-height,0)),36,71,[Vector2(0,1.08),Vector2(2,1.08),Vector2(height-1.8,1),Vector2(height,1.02)],"violet")
		for z in [-14.0,14.0]:_profile(p.translated_local(Vector3(side*14-side*17.5,-38-height,z)),4.5,5.0,[Vector2(0,1.3),Vector2(height+7,1.1),Vector2(height+46,0.65),Vector2(height+48,0.9)],"warm_stone")
		_ghost_wall(p.translated_local(Vector3(side*14-side*18.0,-38.0,-8.0)),side,20.0,63.0,"keep_mural_field")
		_lantern(p.translated_local(Vector3(-side*18,7,25)),index)
		return
	_at(p,Vector3(0,-3,0),Vector3(27,70,28),"plum")
	_roof(p.translated_local(Vector3(0,39,0)),30,14,31,"roof")
	for z in [-13.0,13.0]:
		_at(p,Vector3(-side*14.3,-7,z),Vector3(4.5,67,4.5),"violet")
		for y in [-30.0,-12.0,10.0,25.0]:_at(p,Vector3(-side*14.5,y,z),Vector3(6,1.8,6),"stone")
		_tower(p.translated_local(Vector3(side*8,0,z)),side,86+index*7,index,false)
	for y in [-24.0,-9.0,6.0,21.0]:
		for z in [-7.0,7.0]:_gothic_window(p.translated_local(Vector3(-side*13.7,y,z)),side,4.3,9.5)
	for y in [-20.0,9.0,28.0]:_at(p,Vector3(-side*14.2,y,0),Vector3(1.5,1.3,32),"edge")
	var quad:=QuadMesh.new();quad.size=Vector2(10,20)
	var qp:=p.translated_local(Vector3(-side*14.1,-2,0));qp.basis=qp.basis*Basis(Vector3.UP,-side*PI/2)
	_mesh(quad,qp,"ghost","gatehouse_ghost")
	var foundation:=maxf(1,p.origin.y-58)
	_at(p,Vector3(0,-38-foundation*0.5,0),Vector3(30,foundation,31),"violet")
	_lantern(p.translated_local(Vector3(-side*17,10,8)),index)

func _tower(p: Transform3D,side: float,height: float,index: int,clock_face := true,front_mural := false,gallery_deck: float=-1000.0) -> void:
	if clock_face:
		var q:=Transform3D(p.basis.orthonormalized(),p.origin).translated_local(Vector3(0,-30,0))
		var clock:=models.place("h07_clocktower",world,q,Vector3(52,154,52),0,"H07Clock_"+str(index),1800.0)
		if clock!=null:
			_profile(q.translated_local(Vector3(0,-15,0)),52,52,[Vector2(0,1.08),Vector2(2,1.08),Vector2(13,1),Vector2(15,1)],"violet")
			return
	var base:=p.translated_local(Vector3(0,-30,0));var top:=height-30
	var ground_height:=maxf(1.0,base.origin.y-18.0)
	var annex:=base.translated_local(Vector3(side*4,-ground_height,0))
	_profile(annex,24,22,[Vector2(0,1.12),Vector2(2,1.12),Vector2(4,1.04),Vector2(ground_height+height*0.30,1),Vector2(ground_height+height*0.30+1.1,1.06),Vector2(ground_height+height*0.52,0.94),Vector2(ground_height+height*0.55,1.03)],"violet")
	for row in 3:
		for z in [-5.2,5.2]:_gothic_window(base.translated_local(Vector3(-side*8.45,8.0+row*11.0,z)),side,3.2,6.4)
	_mural(base.translated_local(Vector3(-side*8.46,22.0,0)),side,7.2,21.0,"tower_long_ghost")
	var terrace:=base.translated_local(Vector3(side*4,height*0.55,0))
	_profile(terrace,25,23,[Vector2(0,1),Vector2(0.5,1.04),Vector2(1.1,1.04)],"stone")
	for front in [-1.0,1.0]:
		_at(terrace,Vector3(0,3.0,front*10.8),Vector3(24,0.18,0.2),"ink")
		for i in 9:_at(terrace,Vector3(-11.5+i*2.9,2.1,front*10.8),Vector3(0.18,2.2,0.18),"ink")
	if gallery_deck>-999.0:
		# Match the raised side gallery to a full tower landing, not a bridge edge entering a window.
		var landing:=base.translated_local(Vector3(-side*11.0,gallery_deck+30.0,0))
		_profile(landing,10,8,[Vector2(-1.4,0.94),Vector2(-0.6,1),Vector2(0.2,1),Vector2(0.8,1.03),Vector2(1.2,1.03)],"stone")
		var corbel:=PackedVector2Array([Vector2(-side*7.0,gallery_deck+24.0),Vector2(-side*7.0,gallery_deck+30.0),Vector2(-side*15.0,gallery_deck+30.0)])
		_prism(base,corbel,6.0,"stone","bonded_gallery_corbel")
		for z in [-3.8,3.8]:
			_at(landing,Vector3(0,3.2,z),Vector3(9.6,0.2,0.22),"ink")
			for x in [-4.3,4.3]:_at(landing,Vector3(x,2.2,z),Vector3(0.2,2.4,0.2),"ink")
		_gothic_window(base.translated_local(Vector3(-side*7.12,gallery_deck+36.0,0)),side,4.3,8.0,"ink")
	var turret:=base.translated_local(Vector3(side*14,height*0.47,5.0))
	_profile(turret,8,8,[Vector2(0,1.1),Vector2(1.3,1.1),Vector2(height*0.20,0.92),Vector2(height*0.23,1.18)],"warm_stone")
	var roof:=CylinderMesh.new();roof.bottom_radius=6.2;roof.top_radius=0.04;roof.height=15;roof.radial_segments=8
	_inst(roof,turret.translated_local(Vector3(0,height*0.23+7.3,0)),"roof","shoulder_turret")
	_profile(base,14,14,[Vector2(0,1.25),Vector2(2,1.25),Vector2(4,1.05),Vector2(height*0.36,1),Vector2(height*0.36+1.1,1.12),Vector2(height*0.36+2,1),Vector2(height-15,0.94),Vector2(height-14,1.08),Vector2(height-13,1),Vector2(height-2,1),Vector2(height,1.22),Vector2(height+1.6,1.22)],"violet")
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			var corner:=base.translated_local(Vector3(sx*6.4,0,sz*6.4))
			_profile(corner,1.8,1.8,[Vector2(0,1.5),Vector2(3,1.5),Vector2(height*0.45,1.0),Vector2(height-10,0.68),Vector2(height+4,0.85)],"warm_stone")
	for direction in [-1.0,1.0]:
		for row in maxi(3,int(height/13)):
			var y:=8.0+row*11.5
			if y>height-8:continue
			if not (gallery_deck>-999.0 and direction==-side and absf(y-(gallery_deck+36.0))<10.0):_gothic_window(base.translated_local(Vector3(direction*7.05,y,0)),-direction,3.1,6.4)
			if not (front_mural and direction>0 and y>44 and y<76):
				var face:=base.translated_local(Vector3(0,y,direction*7.05));face.basis=face.basis*Basis(Vector3.UP,PI/2)
				_gothic_window(face,direction,3.1,6.4)
	if front_mural:
		var quad:=QuadMesh.new();quad.size=Vector2(18.0,25.0)
		_mesh(quad,base.translated_local(Vector3(0,58.0,7.13)),"ghost","front_tower_long_ghost")
		for x in [-5.8,5.8]:_lantern(base.translated_local(Vector3(x,60.0,8.8)),index+int(x>0))
		light_candidates.append({"p":base.translated_local(Vector3(0,55.0,13.0)).origin,"energy":24.0,"range":28.0})
	var lower:=CylinderMesh.new();lower.bottom_radius=10;lower.top_radius=2.8;lower.height=17;lower.radial_segments=8
	var roof_pose:=p.translated_local(Vector3(0,top+10.0,0));roof_pose.basis=roof_pose.basis*Basis(Vector3.FORWARD,side*0.05)
	_inst(lower,roof_pose,"roof","tiered_octagonal_spire_lower")
	var upper:=CylinderMesh.new();upper.bottom_radius=4.0;upper.top_radius=0.04;upper.height=14;upper.radial_segments=8
	_inst(upper,p.translated_local(Vector3(side*1.0,top+22.0,0)),"roof","tiered_octagonal_spire_upper")
	_profile(p.translated_local(Vector3(0,top+0.3,0)),17,17,[Vector2(0,1.0),Vector2(0.7,1.08),Vector2(1.3,1.08)],"edge")
	_at(p,Vector3(side*1.0,top+30.5,0),Vector3(0.18,4,0.18),"ink")
	_lantern(p.translated_local(Vector3(-side*8,6,4)),index)

func _arch(p: Transform3D) -> void:
	_viaduct(p,1,42,32,-36,7,"violet")

func _viaduct(p: Transform3D,arches: int,span: float,deck_y: float,bottom: float,depth: float,key: String,mural_back_pier := false) -> void:
	# Solid spandrel and physical inner arch reveal; never a horizontal token bar.
	bottom=minf(bottom,18.0-p.origin.y)
	var radius:=span*0.43
	var spring:=deck_y-radius-4.5
	var half_depth:=depth*0.5
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bay in arches:
		var cx:=(float(bay)-(arches-1)*0.5)*span
		for i in 20:
			var x0:=-radius+radius*2.0*i/20.0
			var x1:=-radius+radius*2.0*(i+1)/20.0
			var y0:=spring+sqrt(maxf(0,radius*radius-x0*x0))
			var y1:=spring+sqrt(maxf(0,radius*radius-x1*x1))
			var a:=Vector3(cx+x0,y0,-half_depth);var b:=Vector3(cx+x1,y1,-half_depth)
			var c:=Vector3(cx+x1,deck_y,-half_depth);var d:=Vector3(cx+x0,deck_y,-half_depth)
			var e:=Vector3(cx+x0,y0,half_depth);var f:=Vector3(cx+x1,y1,half_depth)
			var g:=Vector3(cx+x1,deck_y,half_depth);var h:=Vector3(cx+x0,deck_y,half_depth)
			for v in [a,c,b,a,d,c,e,f,g,e,g,h,a,b,f,a,f,e,d,h,g,d,g,c]:st.add_vertex(v)
		# Two material surfaces preserve all25 wedge meshes byte-for-byte, including normals, caps and gaps.
		var ring:=_wedge_bay(radius,spring,depth,cx)
		_inst(ring,p,"","merged_wedge_bay_"+str(radius)+"_"+str(spring)+"_"+str(depth)+"_"+str(cx))

	st.generate_normals();_mesh(st.commit(),p,key,"open_arch_spandrel")
	for i in arches+1:
		var x:=(float(i)-arches*0.5)*span;var pw:=span-radius*2
		var pp:=p.translated_local(Vector3(x,bottom,0));var height:=spring-bottom
		var interface_key:=str(pp.origin.snapped(Vector3.ONE*0.5))+":"+str(snappedf(p.origin.y+deck_y,0.5))+":"+str(span)+":"+str(depth)
		if bridge_pier_interfaces.has(interface_key):continue
		bridge_pier_interfaces[interface_key]=true
		if mural_back_pier and i==0:
			# The actual visible approach pier face remains clear when the raised gallery occludes a farther tower.
			_mural(pp.translated_local(Vector3(-pw*0.5-0.035,height*0.78,0)),1.0,depth*1.55,minf(35.0,height*0.40),"approach_pier_ghost")
			light_candidates.append({"p":pp.translated_local(Vector3(-pw*0.5-5.5,height*0.76,2.0)).origin,"energy":18.0,"range":18.0})
		_profile(pp,pw,depth+1.0,[Vector2(0,1.3),Vector2(1.2,1.3),Vector2(2.6,1.12),Vector2(3.6,1.08),Vector2(4.8,1),Vector2(height-2.5,1),Vector2(height-1.6,1.15),Vector2(height-0.5,1.22),Vector2(height+0.35,1.22)],key)
		for side in [-1.0,1.0]:
			_profile(pp.translated_local(Vector3(0,0,side*(depth*0.5+0.65))),pw*0.55,1.3,[Vector2(3.5,1.3),Vector2(5,1.1),Vector2(height-3.2,0.7),Vector2(height-1.8,1.0)],"violet")
			for sy in [height*0.25,height*0.58]:_at(pp,Vector3(0,sy,side*(depth*0.5+0.75)),Vector3(pw*0.8,0.5,1.2),"stone")
	var width:=arches*span+span-radius*2
	for course in [[deck_y-0.35,0.3,width+0.9],[deck_y+0.2,0.6,width+1.2],[deck_y+0.75,0.4,width+1.7]]:
		_at(p,Vector3(0,float(course[0]),0),Vector3(float(course[2]),float(course[1]),depth+1.5),"stone")
	for side in [-1.0,1.0]:
		var z: float=side*(half_depth+0.4)
		_at(p,Vector3(0,deck_y+3.25,z),Vector3(width,0.24,0.26),"ink")
		_at(p,Vector3(0,deck_y+1.5,z),Vector3(width,0.16,0.2),"ink")
		for i in int(width/2.4):
			var x:=-width*0.5+i*2.4
			_at(p,Vector3(x,deck_y+2.1,z),Vector3(0.16,2.8,0.16),"ink")
			var tip:=PrismMesh.new();tip.size=Vector3(0.35,0.55,0.22);_inst(tip,p.translated_local(Vector3(x,deck_y+3.65,z)),"ink","railing_spear")
		for x in [-width*0.5,width*0.5]:_profile(p.translated_local(Vector3(x,deck_y+0.5,z)),1.3,1.3,[Vector2(0,1),Vector2(2.9,0.85),Vector2(3.15,1.1),Vector2(3.5,1.1)],"violet")

func _castle_group(p: Transform3D,index: int,scale_factor:=1.0) -> void:
	scale_factor*= [0.91,0.82,1.0][index%3]
	var model_pose:=Transform3D(p.basis,p.origin).translated_local(Vector3(0,-28*scale_factor,0))
	var keep:=models.place("h07_castle_keep",world,model_pose,Vector3(84,110,46)*scale_factor,(0.09 if index%2==0 else PI-0.11),"H07Castle_"+str(index)+"_"+str(snappedf(p.origin.x,0.1)),1600.0)
	if keep!=null:
		var foundation_height:=maxf(12.0,model_pose.origin.y-18.0)
		foundation_facades.append({"pose":model_pose.translated_local(Vector3(0,-foundation_height,0)),"size":Vector3(85*scale_factor,foundation_height,47*scale_factor)})
		_profile(model_pose.translated_local(Vector3(0,-foundation_height,0)),85*scale_factor,47*scale_factor,[Vector2(0,1.10),Vector2(2,1.10),Vector2(5,1.04),Vector2(foundation_height*0.50,1.02),Vector2(foundation_height*0.50+1,1.06),Vector2(foundation_height*0.50+2,1.02),Vector2(foundation_height-2,1),Vector2(foundation_height+4,1.02)],"violet")
		for x in [-1.0,1.0]:
			for z in [-1.0,1.0]:
				var buttress:=model_pose.translated_local(Vector3(x*40*scale_factor,-foundation_height,z*21*scale_factor))
				_profile(buttress,7*scale_factor,6*scale_factor,[Vector2(0,1.3),Vector2(3,1.3),Vector2(foundation_height*0.6,1),Vector2(foundation_height+13*scale_factor,0.72),Vector2(foundation_height+14*scale_factor,0.9)],"stone")
		return
	var q:=p.scaled_local(Vector3.ONE*scale_factor)
	# Connected keep, steep gables, crenellated gate and four unequal spires.
	_at(q,Vector3(0,4,0),Vector3(38,64,32),"plum" if index%2 else "violet")
	_roof(q.translated_local(Vector3(0,41,0)),43,15,37,"roof")
	for side in [-1.0,1.0]:
		for front in [-1.0,1.0]:
			var tp:=q.translated_local(Vector3(side*21,0,front*18))
			_tower(tp,side,73+float((index+int(side+front))%3)*13,index,false)
		for row in 5:
			for z in [-10.0,0.0,10.0]:_gothic_window(q.translated_local(Vector3(side*19.2,-19+row*11,z)),-side,3.4,6.5)
	_at(q,Vector3(0,-47,0),Vector3(45,40,40),"violet")

func _castle_network() -> void:
	var carve: SpatialTrack=route.tracks.station_carve
	# Midground architecture is close enough to contribute at the recorded bend pose.
	_tower(_level(carve,365,43).scaled_local(Vector3(1.8,1.0,1.5)),1,120,0)
	for i in 5:
		for side in [-1.0,1.0]:
			var s: float=[180.0,275.0,385.0,470.0,570.0][i]
			_castle_group(_level(carve,s,side*(88.0+float(i%2)*34)),i,0.82+float(i%3)*0.12)
	# Cross-city bridges are backed by castle groups, at several depths/elevations.
	_viaduct(_level(carve,385),3,56,46,-78,10,"violet")
	for side in [-1.0,1.0]:
		_viaduct(_level(carve,300,side*72).rotated_local(Vector3.UP,PI/2),4,42,8,-85,9,"violet")
		for j in 4:
			var low:=_level(carve,245+j*55,side*(48.0+float(j%2)*16)).translated_local(Vector3(0,-34,0))
			_building(low,side,27,43+float(j%3)*7,20,j+30)
	var ramp: SpatialTrack=route.tracks.station_ramp
	for side in [-1.0,1.0]:
		_viaduct(_level(ramp,70,side*80).rotated_local(Vector3.UP,PI/2),4,43,9,-99,9,"violet")
	var safe: SpatialTrack=route.tracks.canyon_safe
	for i in 5:
		for side in [-1.0,1.0]:
			_castle_group(_level(safe,[30.0,180.0,390.0,540.0,690.0][i],side*(95+float(i%2)*48)),i+5,0.8+float(i%3)*0.16)
	# Lower towers and roofs remain visible through the bridge openings during flight.
	for i in 10:
		for side in [-1.0,1.0]:
			var s:=25.0+i*67
			var low:=_level(safe,s,side*(56.0+float(i%3)*18)).translated_local(Vector3(0,-36,0))
			_building(low,side,27,43+float(i%3)*8,20,i+40)
			if i%3==1:_tower(low.translated_local(Vector3(side*12,0,16)),side,67,i,false)
	_viaduct(_level(safe,180,150),3,70,32,-85,10,"far2")
	_viaduct(_level(safe,390),3,58,55,-84,10,"violet")
	_viaduct(_level(safe,690),5,60,69,-100,10,"far2")

func _landmarks() -> void:
	var start: SpatialTrack=route.tracks.station_start
	_tower(_level(start,710,-20).scaled_local(Vector3(2.6,1.1,2.0)),-1,125,2)
	_viaduct(_level(start,640),3,46,40,-65,8,"violet")
	# Keep festival strings beside the line; station chains attach under the canopy.
	var t: SpatialTrack=route.tracks.station_carve
	for i in int(t.length/56):
		for side in [-1.0,1.0]:
			var p:=_level(t,i*56+14,side*16.2)
			_at(p,Vector3(0,13,0),Vector3(0.08,0.08,26),"ink")
			for k in 7:
				var pp:=p.translated_local(Vector3(0,11.8,k*3.5-10.5));pp.basis=pp.basis*Basis(Vector3.UP,PI/2)
				_festival_flag(pp,"flag" if k%2==0 else "flag_purple")

func _mural(p: Transform3D,side: float,w: float,h: float,ident: String) -> void:
	var quad:=QuadMesh.new();quad.size=Vector2(w,h)
	var face:=p;face.basis=face.basis*Basis(Vector3.UP,-side*PI/2)
	_mesh(quad,face,"ghost",ident)

func _ghost_wall(p: Transform3D,side: float,w: float,h: float,ident: String) -> void:
	# A bonded masonry wall bay, rising from the existing source base. It supplies a real clean paint field
	# where the G1 front is crowded by recessed windows; no floating poster or projection across lamps.
	_profile(p,1.8,w,[Vector2(0,1.10),Vector2(0.7,1.10),Vector2(1.5,1),Vector2(h-1.3,1),Vector2(h-0.8,1.08),Vector2(h,1.08)],"violet")
	for z in [-w*0.5,w*0.5]:
		_profile(p.translated_local(Vector3(-side*0.2,0,z)),2.3,1.4,[Vector2(0,1.2),Vector2(1.3,1.2),Vector2(h*0.62,0.9),Vector2(h-1.5,0.78),Vector2(h,1.15)],"warm_stone")
	for y in [1.5,h-1.0]:_at(p,Vector3(-side*0.2,y,0),Vector3(2.3,0.6,w+1.1),"stone")
	var mural_h:=minf(h*0.86,31.0)
	_mural(p.translated_local(Vector3(-side*0.94,h*0.59,0)),side,w*1.18,mural_h,ident)
	if h>45:
		for z in [-w*0.36,w*0.36]:_gothic_window(p.translated_local(Vector3(-side*0.98,h-6,z)),side,2.8,7.0,"window_dim")
	light_candidates.append({"p":p.translated_local(Vector3(-side*6.0,h*0.25,w*0.18)).origin,"energy":21.0,"range":minf(30.0,maxf(22,h*0.52))})

func _city_house(p: Transform3D,side: float,w: float,d: float,h: float,index: int,far: bool,window_offsets: Dictionary={}) -> void:
	city_anchors.append({"id":index,"base":p.origin,"roof":p.translated_local(Vector3(0,h+5,0)).origin,"far":far,"size":Vector3(d,h,w)})
	# Grounded small roof/window silhouettes behind the bridge planes: real open arch voids stay untouched.
	var key: String=("plum" if index%3==0 else "violet") if not far else "far2"
	_profile(p,d,w,[Vector2(0,1.08),Vector2(1.0,1.08),Vector2(2.0,1),Vector2(h-2.0,1),Vector2(h-1.5,1.05),Vector2(h,1.05)],key)
	_roof(p.translated_local(Vector3(0,h+5,0)),d+1.8,10,w+1.6,"roof" if not far else "edge")
	for z in [-w*0.32,w*0.32]:
		_profile(p.translated_local(Vector3(-side*(d*0.5+0.16),0,z)),1.0,1.1,[Vector2(0,1.4),Vector2(1.7,1.4),Vector2(h*0.65,0.9),Vector2(h+0.4,0.8)],"warm_stone" if not far else "far")
	var rows:=3 if h>32.0 else 2
	for row in rows:
		for z in [-w*0.23,w*0.23]:
			var glass: String="window_dim" if (index+row)%3 else "window_dark"
			_gothic_window(p.translated_local(Vector3(-side*(d*0.5+0.2),5+row*(h-10)/rows+float(window_offsets.get(str(row)+":"+str(int(z>0)),0.0)),z)),side,2.3,4.7 if h>32.0 else 3.5,glass)
	_at(p,Vector3(d*0.22,h+8,w*0.15),Vector3(1.5,6,1.7),"violet")
	_at(p,Vector3(d*0.22,h+11,w*0.15),Vector3(2.0,0.5,2.2),"stone")
	if not far:
		# The concept's city glow originates below the roofs, rather than from orange
		# lamps halfway up every facade. Keep the four existing unshadowed city slots.
		light_candidates.append({"p":p.translated_local(Vector3(-side*(d*0.5+15),minf(8.0,h*0.18),0)).origin,"focus":p.translated_local(Vector3(0,h*0.65,0)).origin,"energy":24.0,"range":48.0,"role":"lower_city","color":Color("ef3fca") if index%3 else Color("ad40ed"),"attenuation":1.25,"specular":0.25})

func _lower_city() -> void:
	# Two deliberately unequal depth rows. Widths and heights stay below the existing principal keeps.
	var index:=0
	for id in ["station_carve","station_ramp","canyon_safe"]:
		var track: SpatialTrack=route.tracks[id]
		var distances: Array=[190.0,245.0,310.0,370.0,435.0] if id=="station_carve" else ([0.0,48.0,96.0] if id=="station_ramp" else [5.0,35.0,75.0,115.0,155.0,220.0,250.0,280.0,340.0,400.0,460.0,520.0,580.0,640.0])
		for distance: float in distances:
			for side in [-1.0,1.0]:
				for layer in 2:
					var offset: float=side*((78.0 if side<0 else 94.0)+layer*(38.0 if side<0 else 20.0))
					if id=="station_ramp":offset=side*(101.0+layer*40.0)
					if id=="station_carve":offset=side*(92.0+layer*44.0)
					var p:=_level(track,minf(distance+layer*19.0,track.length),offset)
					p.origin.y=18.0
					var height:=(34.0+float(index%4)*4.0) if layer==0 else (20.0+float(index%4)*5.0)
					_city_house(p,side,(18.0+float(index%3)*3.0) if layer==0 else (14.0+float(index%3)*2.0),14.0 if layer==0 else 11.0,height,index,layer>0)
					index+=1

func _city_atmosphere() -> void:
	# Entity/lighting first: the rejected magenta fog fill is deliberately disabled.
	pass

func _skyline() -> void:
	for i in 38:
		var p:=Transform3D(Basis.IDENTITY,Vector3(-620+i*34,30+float(i%3)*8,-310+float(i%5)*31))
		_building(p,1,28,95+float(i%7)*12,34,i,true)
	for side in [-1.0,1.0]:
		for i in 14:
			var p:=Transform3D(Basis.IDENTITY,Vector3(side*(240+float(i%3)*23),20,2250-float(i)*95))
			_building(p,side,45,90+float(i%5)*13,40,i,true)
	_box(Transform3D(Basis.IDENTITY,Vector3(0,10,1325)),Vector3(800,16,2250),"far")

func _hazards() -> void:
	for id: String in ["station_start","station_carve","canyon_safe"]:
		var t: SpatialTrack=route.tracks[id]
		for ob: Dictionary in t.obstacles:
			if ob.get("kind","")!="block":continue
			for lane in ob.lanes:
				var p:=t.pose(float(ob.s),float(lane)*4.4);var h:=float(ob.height)
				var hazard:=models.place("h07_hazard",world,p.translated_local(Vector3(0,0.7365269661,0)),Vector3(3,h-0.7365269661,2),0,"H07Hazard_"+id+"_"+str(ob.s)+"_"+str(lane),270.0)
				if hazard!=null:
					_profile(p,3,2,[Vector2(0,0.96),Vector2(0.12,1.0),Vector2(0.24,1.0),Vector2(0.61,0.93),Vector2(0.7365269661,0.98)],"ink")
					_at(p,Vector3(0,h*0.5,-0.91),Vector3(2.88,h-0.14,0.16),"ink")

					# Native base and narrow perimeter complete the exact unchanged 3x5x2 functional boundary.
					for x in [-1.0,1.0]:_at(p,Vector3(x*1.44,h*0.5,0.92),Vector3(0.10,h,0.10),"hazard_trim")
					_at(p,Vector3(0,h-0.06,0.92),Vector3(2.98,0.12,0.10),"hazard_trim")
					continue
				# Existing fallback preserves the same functional boundary.
				_at(p,Vector3(0,h/2,1.012),Vector3(2.88,h-0.14,0.035),"ink")
				for x in [-1.0,1.0]:_at(p,Vector3(x*1.42,h/2,1.02),Vector3(0.13,h,0.1),"acid")
				for y in [0.15,h-0.15]:_at(p,Vector3(0,y,1.02),Vector3(2.95,0.18,0.10),"acid")
				for a in [-0.57,0.57]:
					var xp:=p.translated_local(Vector3(0,h/2,1.075));xp.basis=xp.basis*Basis(Vector3.FORWARD,a);_box(xp,Vector3(0.44,h*0.81,0.08),"pink")
				for x in [-1.0,1.0]:
					for y in [0.38,h-0.38]:_at(p,Vector3(x*1.15,y,1.12),Vector3(0.32,0.32,0.12),"window")

func _train() -> void:
	var geometry: Node3D=app.get_node("Actors/Train/VisualRoot/TrickPivot/Geometry")
	var train_source: Dictionary=models.sources.get("h07_train",{})
	var train_yaw: float=deg_to_rad(float(train_source.get("fit_yaw_degrees",90.0)))
	var train:=models.place("h07_train",geometry,Transform3D.IDENTITY,Vector3(2.65,3.51,12.07),train_yaw,"H07TrainCanonical",2000.0)
	if train!=null:
		for n in geometry.get_children():
			if n!=train and n is GeometryInstance3D:n.visible=false
		if str(train_source.get("visual_variant",""))=="t2-ghost":
			# Preserve the source faces/buffers; light their surfaces and inset lamp cores.
			var fit: Dictionary=models.fits.back()
			var fitted: Array=fit.achieved_size_m
			preload("res://themes/halloween_07/train_readability.gd").new().apply(train,Vector3(fitted[0],fitted[1],fitted[2]))
			return
		var lamp_mat:=StandardMaterial3D.new();lamp_mat.albedo_color=Color("ffe6a6");lamp_mat.emission_enabled=true;lamp_mat.emission=Color("ffcb6a");lamp_mat.emission_energy_multiplier=2.2
		for direction in [-1.0,1.0]:
			for side in [-1.0,1.0]:
				var lens:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(0.34,0.32,0.045);lens.mesh=mesh;lens.material_override=lamp_mat;lens.position=Vector3(side*0.84,1.02,direction*4.385);train.add_child(lens)
		for direction in [-1.0,1.0]:
			var lower_nose:=MeshInstance3D.new();lower_nose.mesh=_prism_mesh(PackedVector2Array([Vector2(-1.16,0.44),Vector2(1.16,0.44),Vector2(1.12,0.72),Vector2(0.84,0.78),Vector2(-0.84,0.78),Vector2(-1.12,0.72)]),0.055,"painted_lower_nose")
			lower_nose.material_override=mats.train_orange;lower_nose.position.z=direction*4.41;train.add_child(lower_nose)
		for side in [-1.0,1.0]:
			var head:=SpotLight3D.new();head.position=Vector3(side*0.84,1.05,-4.40);head.light_color=Color("ffe0a1");head.light_energy=2.0;head.spot_range=42;head.spot_angle=29;head.spot_attenuation=1.0;head.rotation_degrees.x=-5;head.shadow_enabled=false;train.add_child(head)
		return
	for n: Node in geometry.get_children():
		if n is MeshInstance3D:
			var name:=str(n.name)
			n.material_override=mats.acid if name=="Body" else (mats.ink if "Window" in name or "Roof" in name or "Wheel" in name else mats.warm)
	var trim:=Node3D.new();trim.name="H07TrainTrim";trim.set_meta("instance_id","h07_train_trim");trim.set_meta("asset_id","h07_train_wrap");trim.set_meta("scene_id","station");geometry.add_child(trim)
	for side in [-1.0,1.0]:
		var m:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(1.85,0.15,0.08);m.mesh=mesh;m.material_override=mats.window;m.position=Vector3(0,2.8,side*6.04);trim.add_child(m)
		for x in [-1.0,1.0]:
			var lens:=MeshInstance3D.new();var lm:=BoxMesh.new();lm.size=Vector3(0.42,0.38,0.08);lens.mesh=lm;lens.material_override=mats.window;lens.position=Vector3(x*0.91,0.84,side*6.04);trim.add_child(lens)
		var bumper:=MeshInstance3D.new();var bm:=BoxMesh.new();bm.size=Vector3(2.4,0.27,0.12);bumper.mesh=bm;bumper.material_override=mats.ink;bumper.position=Vector3(0,0.5,side*6.02);trim.add_child(bumper)
	for i in 5:
		var m:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(1.7,0.1,0.12);m.mesh=mesh;m.material_override=mats.rail;m.position=Vector3(0,3.55,-2.0+i);trim.add_child(m)
