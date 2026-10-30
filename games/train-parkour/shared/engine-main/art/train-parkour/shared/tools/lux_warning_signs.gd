extends RefCounted
## Visual-only warning/sign replacement; frozen owner/order/poses remain authority.
const REPORT := "lux_warning_signs_report"
const SPACES := ["N01", "N07", "N08"]
const PAD_SIZE := Vector3(3.5,0.08,3.8)
const SIGN_SIZE := Vector3(2.6,1.8,0.2)
const BAR_SIZE := Vector3(1.6,0.2,0.24)
const PAD_TOP := 0.241
var host: RefCounted
var app: Node3D
var world: Node3D
var config: Dictionary
var proxy: RefCounted
var spaces: Dictionary = {}
var assets: Dictionary = {}
var counts: Dictionary = {}
var pending: Array = []
var replacements: Array = []

func build(session: Node3D, target: Node3D, loader: RefCounted, settings: Dictionary) -> Dictionary:
	if target.has_meta(REPORT): return target.get_meta(REPORT)
	app = session; world = target; host = loader; config = settings
	spaces.clear(); assets.clear(); counts.clear(); pending.clear(); replacements.clear()
	var before_errors: int = host.errors.size()
	proxy = host.ProxyWorld.new(); proxy.session = app
	proxy.route = app.lab.get_node("RouteRoot/MainRoute")
	var design: Variant = JSON.parse_string(FileAccess.get_file_as_string(host.CASE+"styles/"+host.sid+"/design/2026-10-20-full-route/spatial-design.json"))
	if not design is Dictionary:
		host.errors.append("Warning/sign spatial design missing")
		return {"passed":false,"errors":["missing design"]}
	for space: Dictionary in design.space_designs:
		for id: String in space.track_ids: spaces[id] = space.space_id
	_prepare("warning_pad"); _prepare("no_entry")
	var warnings: Array = proxy._warning_sources()
	var signs := _sign_records(warnings)
	var inventory := _inventory()
	# Do not shift correspondence after an unknown primitive or unexpected batch size.
	if inventory.warning_pad.size()!=warnings.size() or inventory.no_entry.size()!=signs.size() or inventory.bar.size()!=signs.size():
		host.errors.append("Frozen warning/sign source enumeration mismatch; no originals hidden")
	else:
		for index in warnings.size():
			if _scope(warnings[index].support_track): _warning(inventory.warning_pad[index],warnings[index])
		for index in signs.size():
			if _scope(signs[index].support_track): _sign(inventory.no_entry[index],inventory.bar[index],signs[index])
	var report := {"schema":1,"stage":"S8_PARTIAL_WARNING_SIGNS","passed":host.errors.size()==before_errors,
		"errors":host.errors.slice(before_errors),"counts":counts.duplicate(true),"pending":pending.duplicate(true),"replacements":replacements.duplicate(true),
		"scope":config.get("spaces",[]),"frozen_warning_records":warnings.size(),"frozen_sign_records":signs.size(),
		"new_collision_nodes":0,"pose_authority":"ProxyWorld._warning_sources and exact frozen obstacle/lane enumeration",
		"headless_mapping_only":DisplayServer.get_name()=="headless",
		"limits":"No native visual/readability or H4 acceptance; post checks sample all frozen route decks, not flight/camera sweeps. Ground mounting datum is route-local floor 0."}
	world.set_meta(REPORT,report)
	return report

func _scope(track: String) -> bool:
	return spaces.get(track,"") in SPACES and spaces.get(track,"") in config.get("spaces",[])

func _pending(role: String, reason: String) -> void:
	pending.append({"role":role,"reason":reason}); host.warnings.append("Warning/sign "+role+": "+reason)

func _prepare(role: String) -> void:
	var id: String = str(config.get("roles",{}).get(role,""))
	var template: Node3D = host.sample_templates.get(id+":near")
	if id.is_empty() or template==null or not host.sample_specs.has(id):
		_pending(role,"Missing normalized near template/binding"); return
	var measured: Dictionary = host.measure(template)
	var bounds: AABB = measured.bounds
	if not measured.finite or absf(bounds.size.y-1)>0.015 or absf(bounds.position.y)>0.015 or absf(bounds.get_center().x)>0.015 or absf(bounds.get_center().z)>0.015:
		host.errors.append("Expected height-1 bottom-center warning/sign template: "+id); return
	var spec: Dictionary = host.sample_specs[id]
	if str(spec.get("source",{}).get("sha256","")).length()!=64:
		host.errors.append("Missing warning/sign source hash: "+id); return
	var item := {"id":id,"template":template,"bounds":bounds,"spec":spec}
	if role=="no_entry":
		var foot := _foot_bounds(template,Transform3D.IDENTITY)
		if not foot.valid or foot.bounds.size.x<0.04 or foot.bounds.size.z<0.04:
			_pending(role,"Cannot resolve actual low base footprint"); return
		item["foot_bounds"] = foot.bounds
	assets[role] = item

func _foot_bounds(node: Node, parent: Transform3D) -> Dictionary:
	var pose: Transform3D = parent*node.transform if node is Node3D else parent
	var valid := false; var low := Vector3(INF,INF,INF); var high := Vector3(-INF,-INF,-INF)
	if node is MeshInstance3D and node.mesh!=null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if arrays.size()<=Mesh.ARRAY_VERTEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: continue
			for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var actual := pose*point
				if actual.is_finite() and actual.y<=0.035:
					low=low.min(actual); high=high.max(actual); valid=true
	for child: Node in node.get_children():
		var result := _foot_bounds(child,pose)
		if result.valid: low=low.min(result.bounds.position); high=high.max(result.bounds.end); valid=true
	return {"valid":valid,"bounds":AABB(low,high-low) if valid else AABB()}

func _inventory() -> Dictionary:
	var result := {"warning_pad":[],"no_entry":[],"bar":[]}
	var serial := 0
	var presentation: Node3D = app.lab.get_node("PresentationRoot")
	for source: MultiMeshInstance3D in presentation.find_children("*","MultiMeshInstance3D",true,false):
		var semantic: String = proxy._semantic_name(source)
		var source_id := semantic+":%04d" % serial; serial+=1
		if source.get_parent()!=presentation or source.multimesh==null or not source.multimesh.mesh is BoxMesh: continue
		var size: Vector3 = source.multimesh.mesh.size
		var role := ""
		if size.is_equal_approx(PAD_SIZE): role="warning_pad"
		elif size.is_equal_approx(SIGN_SIZE): role="no_entry"
		elif size.is_equal_approx(BAR_SIZE): role="bar"
		if role.is_empty(): continue
		result[role].append({"node":source,"source_id":source_id,"size":size})
	return result

func _sign_records(warnings: Array) -> Array:
	var records: Array = []; var cursor := 0
	var presentation: Node3D = app.lab.get_node("PresentationRoot")
	for track in proxy.route.tracks.values():
		for obstacle: Dictionary in track.obstacles:
			for lane: int in obstacle.lanes:
				if cursor>=warnings.size(): return []
				var warning: Dictionary = warnings[cursor]
				for ratio_index in 4:
					warnings[cursor+ratio_index]["lane"] = lane
					warnings[cursor+ratio_index]["obstacle_s"] = obstacle.s
				cursor+=4
				var preview := maxf(float(obstacle.get("preview_seconds",1.8))*175.0,170.0)
				var distance := float(obstacle.s)-preview
				var direction := signf(float(lane)) if lane!=0 else 1.0
				var edge: float = direction*(track.width_at(maxf(0,distance))+3.0)
				var base: Transform3D = presentation.global_transform*app.lab._approach_pose(proxy.route,track,distance)
				var record := warning.duplicate()
				record["pose"] = base.translated_local(Vector3(edge,4.4,0))
				record["base_pose"] = base; record["edge"] = edge; record["lane"] = lane
				record["obstacle_s"] = obstacle.s
				records.append(record)
	return records

func _check_source(item: Dictionary, expected: Transform3D) -> bool:
	var source: MultiMeshInstance3D = item.node
	if source.multimesh.instance_count!=1:
		_pending("mapping","Expected one native instance: "+item.source_id); return false
	if not source.is_visible_in_tree():
		_pending("mapping","Original already hidden: "+item.source_id); return false
	if DisplayServer.get_name()!="headless":
		var actual := source.global_transform*source.multimesh.get_instance_transform(0)
		if actual.origin.distance_to(expected.origin)>0.01 or not actual.basis.is_equal_approx(expected.basis):
			host.errors.append("Frozen warning/sign pose mismatch: "+item.source_id); return false
	return true

func _warning(item: Dictionary, provenance: Dictionary) -> void:
	if not assets.has("warning_pad") or not _check_source(item,provenance.pose): return
	var old_id: String = host.sid+":warning-cross:"+item.source_id
	var old: Array[Node3D] = []; host._find_instance(world,old_id,old)
	if old.size()!=1 or not old[0].is_visible_in_tree() or not old[0] is MultiMeshInstance3D or old[0].multimesh.instance_count!=2:
		_pending("warning_pad","Expected exactly one visible S6 two-arm cross: "+old_id); return
	var asset: Dictionary = assets.warning_pad
	var size: Vector3 = asset.bounds.size
	var scalar := minf(3.5/size.x,3.8/size.z)*0.995
	# At most 6cm recess; top never exceeds the original S6 X top (0.241m).
	scalar=minf(scalar,0.301/size.y)
	var height := size.y*scalar
	var local := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scalar),Vector3(0,PAD_TOP-0.18-height,0))
	var fitted: AABB = local*asset.bounds
	if fitted.size.x>3.5 or fitted.size.z>3.8 or fitted.end.y+0.18>PAD_TOP+0.00001 or fitted.position.y+0.18 < -0.06001:
		host.errors.append("Warning pad exceeds frozen footprint/top: "+item.source_id); return
	var id: String = host.sid+":lux-warning:"+item.source_id
	var mount := _model(asset,id,provenance.pose*local,provenance)
	if mount==null: return
	item.node.visible=false; old[0].visible=false
	# Only the exact hidden S6 cross group is removed from active proxy bounds.
	host.replaced_ids.append(old_id)
	var record := _provenance(provenance)
	record.merge({"id":id,"asset_id":asset.id,"role":"warning_pad","uniform_scale":scalar,
		"top_route_local_m":PAD_TOP,"bottom_route_local_m":PAD_TOP-height,
		"footprint_m":[fitted.size.x,fitted.size.z],"hidden_source_node":str(item.node.get_path()),
		"hidden_proxy_bounds_id":old_id,"source_sha256":asset.spec.source.sha256},true)
	replacements.append(record); host.instance_reports.append(record)
	counts["warning_pad"] = int(counts.get("warning_pad",0))+1

func _sign(item: Dictionary, bar: Dictionary, provenance: Dictionary) -> void:
	if not assets.has("no_entry") or not _check_source(item,provenance.pose) or not _check_source(bar,provenance.pose): return
	var asset: Dictionary = assets.no_entry
	var size: Vector3 = asset.bounds.size
	var scalar := minf(1.8/size.y,2.6/size.x)
	var local := Transform3D(Basis(Vector3.UP,PI).scaled(Vector3.ONE*scalar),Vector3(0,-0.9,0))
	var foot: AABB = asset.foot_bounds
	var center := local*Vector3(foot.get_center().x,0,foot.get_center().z)
	var floor: Transform3D = provenance.pose.translated_local(Vector3(center.x,-4.4,center.z))
	var post_size := Vector3(minf(0.16,foot.size.x*scalar*0.5),3.5,minf(0.16,foot.size.z*scalar*0.5))
	var post_pose: Transform3D = floor.translated_local(Vector3(0,1.75,0))
	var candidate: AABB = post_pose*AABB(-post_size*0.5,post_size)
	var conflict := _post_conflict(candidate)
	if not conflict.is_empty():
		_pending("no_entry","New support intersects sampled route corridor "+conflict+": "+item.source_id); return
	var id: String = host.sid+":lux-sign:"+item.source_id
	var mount := _model(asset,id,provenance.pose*local,provenance)
	if mount==null: return
	var pole := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size=post_size
	var material := StandardMaterial3D.new(); material.albedo_color=Color("4e5351"); material.metallic=0.65; material.roughness=0.72
	mesh.material=material; pole.mesh=mesh; world.add_child(pole); pole.global_transform=post_pose
	host._tag_tree(pole,id+":support","local_steel_sign_support","station" if spaces[provenance.support_track]=="N01" else "valley")
	_record(pole,id+":support","local_steel_sign_support","",provenance,"support")
	item.node.visible=false; bar.node.visible=false
	# Native originals have no S6 bounds ID; never invent a removed proxy ID.
	var record := _provenance(provenance)
	record.merge({"id":id,"asset_id":asset.id,"role":"no_entry","uniform_scale":scalar,
		"source_sha256":asset.spec.source.sha256,"height_m":size.y*scalar,"bottom_route_local_m":3.5,
		"facing":"normalized -Z rotated to route +Z", "foot_center_sign_local_m":host.array(center),
		"post_size_m":host.array(post_size),"post_transform":host.transform_array(post_pose),
		"post_contact":"track-local floor 0 to actual model base at 3.5m", "route_decks_checked":proxy.route.tracks.size(),
		"hidden_source_nodes":[str(item.node.get_path()),str(bar.node.get_path())],"hidden_proxy_bounds_ids":[]},true)
	replacements.append(record); host.instance_reports.append(record)
	counts["no_entry"] = int(counts.get("no_entry",0))+1

func _post_conflict(box: AABB) -> String:
	# Conservative world AABB projected into sampled frozen deck frames. Expanded
	# longitudinal reach covers 3m sampling; this is not an airborne/camera test.
	for track in proxy.route.tracks.values():
		if not (proxy.route.global_transform*track.bounds).grow(12).intersects(box): continue
		for i in ceili(track.length/3.0)+1:
			var s := minf(track.length,i*3.0)
			var frame: Transform3D = proxy.route.track_pose(track.id,s)
			var local: AABB = frame.affine_inverse()*box
			var width: float = track.width_at(s)+1.35
			if local.intersects(AABB(Vector3(-width,-0.05,-7.6),Vector3(width*2,3.5,15.2))): return track.id
	return ""

func _model(asset: Dictionary, id: String, pose: Transform3D, provenance: Dictionary) -> Node3D:
	var mount := Node3D.new(); mount.add_child(asset.template.duplicate()); world.add_child(mount)
	mount.global_transform=pose
	host._tag_tree(mount,id,asset.id,"station" if spaces[provenance.support_track]=="N01" else "valley")
	if not host.measure(mount,world.global_transform).finite:
		host.errors.append("Invalid warning/sign model bounds: "+id); mount.free(); return null
	_record(mount,id,asset.id,asset.spec.source.sha256,provenance,"route_surface" if asset==assets.get("warning_pad") else "support")
	return mount

func _record(node: Node3D, id: String, asset: String, sha: String, provenance: Dictionary, category: String) -> void:
	var measured: Dictionary = host.measure(node,world.global_transform)
	for i in measured.meshes.size():
		var row: Dictionary = measured.meshes[i]; var box: Dictionary = row.bounds
		var record := _provenance(provenance)
		record.merge({"id":id+":mesh:"+str(i),"style_id":host.sid,"space_id":spaces[provenance.support_track],
			"category":category,"center_m":host.array(host.vector(box.position_m)+host.vector(box.size_m)*0.5),"size_m":box.size_m,
			"basis_columns":[[1,0,0],[0,1,0],[0,0,1]],"protected_route":category=="route_surface",
			"bounds_kind":row.get("bounds_kind","vertex_aabb_conservative_solid"),"mesh_local_aabb":row.local_aabb,
			"mesh_to_world":row.transform,"source_asset_id":asset,"source_sha256":sha},true)
		host.added_bounds.append(record)

func _provenance(value: Dictionary) -> Dictionary:
	return {"obstacle_id":value.obstacle_id,"obstacle_track":value.obstacle_track,"support_track":value.support_track,"warning_ratio":value.ratio,"lane":value.lane,"obstacle_s":value.obstacle_s,"space_id":spaces[value.support_track]}
