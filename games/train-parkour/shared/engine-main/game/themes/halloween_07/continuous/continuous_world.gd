extends RefCounted
const Context = preload("res://themes/halloween_07/continuous/continuous_context.gd")
const Field = preload("res://themes/halloween_07/continuous/ground_field.gd")
const Infrastructure = preload("res://themes/halloween_07/continuous/infrastructure.gd")
const CoreRegions = preload("res://themes/halloween_07/continuous/regions_core.gd")
const Bridge = preload("res://themes/halloween_07/continuous/shared_bridge.gd")
const LegacyClearance = preload("res://themes/halloween_07/continuous/legacy_clearance.gd")
const PROGRAM = "res://themes/halloween_07/continuous/program.json"

static func build_extension(host: RefCounted) -> void:
	var program: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROGRAM))
	var field := Field.new(); field.configure(host.route,program)
	var shared := {"field":field,"claims":{},"program":program}
	var report := {"schema_version":1,"program_sha256":FileAccess.get_sha256(PROGRAM),"regions":[],"interfaces":[],"technical_coverage":{},"native_visual_review":"pending_current_76_views","human_acceptance":false,"new_paid_generations":0,"canonical_model_cache_shared":true}
	report.relocated_legacy_groups=[]
	for move:Dictionary in host.legacy_relocations:
		var actual:=move.duplicate(true);var point:=Vector3(move.relocated_root[0],move.foundation_floor_y,move.relocated_root[2])
		actual.ground_y_at_root=field.height_at(point)
		actual.foundation_embeds_ground_at_root=point.y<=float(actual.ground_y_at_root)+0.01
		actual.foundation_sample_minimum_embed_m=INF
		for sample:Array in move.foundation_footprint_samples:
			var foot:=Vector3(sample[0],sample[1],sample[2])
			actual.foundation_sample_minimum_embed_m=minf(actual.foundation_sample_minimum_embed_m,field.height_at(foot)-foot.y)
		actual.foundation_footprint_samples_grounded=float(actual.foundation_sample_minimum_embed_m)>=-0.01
		report.relocated_legacy_groups.append(actual)
	report.retired_sample_ground = _retire_station_ground(host)
	report.retired_legacy_skyline = LegacyClearance.build(host,field)
	var infrastructure := Infrastructure.new(); var core := CoreRegions.new()
	var valley_script = load("res://themes/halloween_07/continuous/regions_valley.gd")
	var finale_script = load("res://themes/halloween_07/continuous/regions_finale.gd")
	assert(valley_script != null and finale_script != null,"All region authors must finish before integration")
	var valley: RefCounted = valley_script.new(); var finale: RefCounted = finale_script.new()
	var added_beds := []; var hard_added := 0; var warnings_added := 0
	for region: Dictionary in program.regions:
		# Optional performance adapter; original scene authoring keeps its context.
		var ctx: Context = host.call("create_region_context") as Context if host.has_method("create_region_context") else Context.new()
		assert(ctx != null, "Region context factory must return the canonical Context type")
		ctx.configure(host,region,shared)
		var authored := {}
		if region.id == "N01":
			ctx.world.name = "H07SharedGround"
			report.terrain = field.emit_ground(ctx)
		elif region.id in ["N02","N03","N04","N05"]: authored = core.build(ctx,region)
		elif region.id in ["N06","N07","N08"]: authored = valley.build(ctx,region)
		elif region.id == "N09": authored = finale.build(ctx,region)
		var infra: Dictionary = infrastructure.build(ctx,region,program)
		added_beds.append_array(infra.new_track_beds); hard_added += int(infra.hard_objects); warnings_added += int(infra.warning_boards)
		if region.id == "N07": report.shared_bridge = Bridge.new().build(ctx)
		var actual := ctx.finish()
		report.regions.append({"id":region.id,"tracks":region.tracks,"authored":authored,"infrastructure":infra,"emitted":actual})
	var hard_original := 0; var warnings_original := 0; var hard_sample := 0; var warnings_sample := 0
	for id: String in host.route.tracks:
		var track: SpatialTrack = host.route.tracks[id]
		for ob: Dictionary in track.obstacles:
			for lane: int in ob.lanes:
				warnings_original += 4
				if id in program.sample_objects: warnings_sample += 4
				if str(ob.get("kind","block")) != "soft":
					hard_original += 1
					if id in program.sample_objects: hard_sample += 1
	for edge: Dictionary in program.interfaces:
		var source: SpatialTrack = host.route.tracks[edge.source]; var target: SpatialTrack = host.route.tracks[edge.target]
		var row := {"id":edge.id,"source":edge.source,"target":edge.target,"relation":edge.relation,"source_region":field.region_for_track[edge.source],"target_region":field.region_for_track[edge.target],"shared_terrain_field":true,"material_palette_shared":true,"source_and_target_dressed":true,"visual_review":"pending_current_native_views","dynamic_reachability":"not_asserted"}
		if edge.relation == "declared_next":
			row.endpoint_gap_m = source.pose(source.length).origin.distance_to(target.pose(0).origin)
			row.join = "uncapped_rail_local_bed_endpoints"
		else: row.join = "preserved_candidate_flight_void"
		report.interfaces.append(row)
	report.technical_coverage = {"frozen_tracks":host.route.tracks.size(),"sample_beds_retained":program.sample_track_beds,"added_track_beds":added_beds,"total_track_beds":program.sample_track_beds.size()+added_beds.size(),"declared_interfaces":report.interfaces.size(),"hard_functional_original":hard_original,"hard_sample_retained":hard_sample,"hard_added":hard_added,"hard_covered":hard_sample+hard_added,"warning_original":warnings_original,"warning_sample_retained":warnings_sample,"warning_added":warnings_added,"warning_covered":warnings_sample+warnings_added,"physical_claims":shared.claims.size(),"geometry_coverage_is_visual_pass":false}
	report.canonical_asset_manifest = []
	for asset_id: String in host.models.sources:
		var asset: Dictionary = host.models.sources[asset_id]
		report.canonical_asset_manifest.append({"asset_id":asset_id,"path":asset.path,"sha256":asset.sha256,"copied":false})
	report.shared_cache_entries = host.models.cache.size()
	report.limits = ["Static sampled geometry and declared topology coverage; native whole-view/transition review remains separate.","The inherited inverted-to-loop_entry direct-air candidate is not forced reachable.","No gameplay, route, contact, camera, solver, collision or speed source is changed."]
	host.world.set_meta("h07_continuity",report)

static func _retire_station_ground(host: RefCounted) -> Dictionary:
	var center := Vector3(0,10,1325); var size := Vector3(800,16,2250)
	var replaced := 0
	# Bind the exact retained source pose to its spatial batch. Dummy headless
	# RenderingServer does not provide reliable MultiMesh transform readback.
	var cell := Vector3i(floori(center.x/128.0),floori(center.y/96.0),floori(center.z/128.0))
	var in_cell := []; var target_index := -1
	for p: Transform3D in host.batches.get("far",[]):
		var candidate_cell := Vector3i(floori(p.origin.x/128.0),floori(p.origin.y/96.0),floori(p.origin.z/128.0))
		if candidate_cell != cell: continue
		if p.origin.is_equal_approx(center) and p.basis.get_scale().is_equal_approx(size): target_index = in_cell.size()
		in_cell.append(p)
	if target_index >= 0:
		for node in host.world.get_children():
			if not node is MultiMeshInstance3D or not str(node.name).begins_with("H07_far_") or not node.position.is_equal_approx(Vector3(cell)*Vector3(128,96,128)): continue
			if in_cell.size() == 1: node.visible = false
			else: node.multimesh.set_instance_transform(target_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
			replaced += 1
	for i in range(host.record.size()-1,-1,-1):
		var row: Dictionary = host.record[i]
		if row.get("kind","") != "box": continue
		var origin: Array = row.get("center",[]); var dimensions: Array = row.get("size",[])
		if origin.size()==3 and dimensions.size()==3 and Vector3(origin[0],origin[1],origin[2]).is_equal_approx(center) and Vector3(dimensions[0],dimensions[1],dimensions[2]).is_equal_approx(size): host.record.remove_at(i)
	return {"retired_instances":replaced,"exact_center":[0,10,1325],"exact_size":[800,16,2250],"replacement":"shared continuous terrain at the same Y18; no coplanar duplicate or floating foundation offset"}
