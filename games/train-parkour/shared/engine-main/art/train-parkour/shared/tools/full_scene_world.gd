extends "res://../art/train-parkour/shared/tools/reconstruction_world.gd"
## Full B2 art layer. Frozen native gameplay and the positively reviewed station remain authoritative.
const Regions = preload("res://../art/train-parkour/shared/tools/full_scene_regions.gd")
const FULL_LAYOUT := "res://../art/train-parkour/styles/odd-logistics/runtime/full_scene-layout.json"
const LOD_MANIFEST := "res://../art/train-parkour/styles/odd-logistics/runtime/full_scene-lods.json"
var full_runtime_scene := ""
var full_regions: RefCounted
var full_lod_manifest: Dictionary = {}
var full_lod_meshes: Dictionary = {}
var full_lod_records: Dictionary = {}
var full_import_cache: Dictionary = {}
var full_import_aliases := 0
var track_spaces: Dictionary = {}
var track_scenes: Dictionary = {}
var shared_box_meshes: Dictionary = {}
var initialization_draws := 0
var distance_template: Node3D
const DISTANCE_MANIFEST := "res://../art/train-parkour/styles/odd-logistics/models/lux-g1-v2/B2-LUX-03-rack_bay-squat_loaded/lod-distance-v2/manifest.json"

func _sample_config_path() -> String:
	return CASE+"styles/odd-logistics/runtime/full_scene-assembly.json"

func _box_mesh(size: Vector3) -> BoxMesh:
	# Exact-size immutable resources; transforms, UVs and all clearance records are unchanged.
	if not shared_box_meshes.has(size):
		var mesh:=BoxMesh.new()
		mesh.size=size
		shared_box_meshes[size]=mesh
	return shared_box_meshes[size]

func _active_geometry(original: Dictionary) -> Dictionary:
	# Exact equality/colon-prefix semantics of the parent, indexed instead of items × replacements.
	var removed_ids: Dictionary={}
	for ident:String in replaced_ids:removed_ids[ident]=true
	var active: Dictionary={}
	for key:Variant in original:
		if key not in ["items","placements"]:
			var value:Variant=original[key]
			active[key]=value.duplicate(true) if value is Array or value is Dictionary else value
	var items:Array=[]
	for item:Dictionary in original.get("items",[]):
		var candidate:=str(item.get("id",""))
		var removed:=false
		while not candidate.is_empty():
			if removed_ids.has(candidate):removed=true;break
			var separator:=candidate.rfind(":")
			if separator<0:break
			candidate=candidate.left(separator)
		if not removed:items.append(item)
	items.append_array(added_bounds)
	active.items=items
	active.placements=original.get("placements",[]).filter(func(p):return not removed_ids.has(str(p.get("id",""))))
	active.lux_calibration_placements=instance_reports.filter(func(p):return p.role=="environment")
	active.scope="Visible retained proxy and full-scene art; canonical per-item transforms, no collision edits"
	return active

func build_style(app: Node3D, style_id: String) -> Node3D:
	print("B2_FULL_BUILD_BEGIN ",Time.get_ticks_msec())
	var design: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CASE+"styles/odd-logistics/design/2026-10-20-full-route/spatial-design.json"))
	for space: Dictionary in design.space_designs:
		for track_id: String in space.track_ids:
			track_spaces[track_id]=space.space_id
			track_scenes[track_id]=design.baseline_facts.tracks[track_id].runtime_scene_id
	if FileAccess.file_exists(LOD_MANIFEST):
		full_lod_manifest=JSON.parse_string(FileAccess.get_file_as_string(LOD_MANIFEST))
	var world:=super.build_style(app,style_id)
	print("B2_FULL_BUILD_DONE ",Time.get_ticks_msec())
	var report: Dictionary=world.get_meta("scene_rebuild_report")
	report.scope="N01-N09 complete B2 art candidate; frozen37-track route and all branches retained"
	report.full_scene=world.get_meta("full_scene",{})
	report.real_mesh_lods=full_lod_records
	report.identical_glb_parse_aliases=full_import_aliases
	report.unique_authored_box_meshes=shared_box_meshes.size()
	report.initialization_submission_frames=initialization_draws
	world.set_meta("scene_rebuild_report",report)
	var construction: Dictionary=world.get_meta("construction_report")
	construction.stage="B2_FULL_SCENE_CANDIDATE"
	construction.full_scene=report.full_scene
	world.set_meta("construction_report",construction)
	full_import_cache.clear()
	if is_instance_valid(distance_template):distance_template.free()
	# Break the builder/module RefCounted cycle after all scene work and metadata are complete.
	full_regions=null
	return world

func _load_shared_material_lod(spec: Dictionary, original: Node3D, level: Dictionary) -> Node3D:
	# near/far often point to identical bytes. Each owner receives an independent node tree,
	# while immutable mesh/material resources share one actual GLTF parse.
	var key:=str(spec.id)+":"+str(level.get("path",""))+":"+str(level.get("sha256",""))
	if full_import_cache.has(key):
		full_import_aliases+=1
		return (full_import_cache[key] as Node3D).duplicate()
	var result:=super._load_shared_material_lod(spec,original,level)
	if result!=null:full_import_cache[key]=result
	return result

func _register(node: Node3D, box: AABB, ident: String, asset: String, space: String, kind: String) -> void:
	super._register(node,box,ident,asset,space,kind)
	var scenes:={"N01":"station","N02":"canyon","N03":"vertical","N04":"coaster","N05":"coaster","N06":"tunnel","N07":"valley","N08":"finale","N09":"finale"}
	var scene: String=full_runtime_scene if not full_runtime_scene.is_empty() else scenes.get(space,"finale")
	_tag_tree(node,ident,asset,scene)

func _model(asset: String, pose: Transform3D, scale_value: float, space: String, role: String, clearance := true) -> Node3D:
	var node:=super._model(asset,pose,scale_value,space,role,clearance)
	if node==null or space=="N01":return node
	if asset==LOADED:
		_apply_distance_rack(node)
		return node
	var lods: Dictionary=full_lod_manifest.get("assets",{})
	if not lods.has(asset):return node
	var row: Dictionary=lods[asset]
	if not row.get("mesh") is Dictionary:return node
	if not full_lod_meshes.has(asset):
		var path: String="res://../"+str(row.mesh.path)
		if FileAccess.get_sha256(path)!=str(row.mesh.sha256):
			errors.append("Full-scene LOD cache hash mismatch: "+asset)
			return node
		full_lod_meshes[asset]=load(path)
		full_lod_records[asset]={"mesh":row.mesh,"source_geometry":row.source_geometry,"base_triangles":row.get("base_triangles"),"instances":0,"station_mesh_assignment_unchanged":true}
	var generated: ArrayMesh=full_lod_meshes[asset]
	for mesh_node: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if mesh_node.mesh==null:continue
		var materials_saved:Array[Material]=[]
		for i in mesh_node.mesh.get_surface_count():materials_saved.append(mesh_node.get_active_material(i))
		if generated.get_surface_count()!=materials_saved.size():
			errors.append("Full-scene LOD surface count mismatch: "+asset)
			continue
		mesh_node.mesh=generated
		for i in materials_saved.size():mesh_node.set_surface_override_material(i,materials_saved[i])
		mesh_node.lod_bias=0.75
	full_lod_records[asset].instances+=1
	return node

func _apply_distance_rack(node: Node3D) -> void:
	if not is_instance_valid(distance_template):
		var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DISTANCE_MANIFEST))
		if not manifest.get("passed",false):
			errors.append("Distance rack bake did not pass")
			return
		var far_level: Dictionary=manifest.levels[1]
		distance_template=_load_shared_material_lod(sample_specs[LOADED],source_templates[LOADED],far_level)
		if distance_template==null:return
		full_lod_records[LOADED]={"method":"separate geometry-only distance mesh","near_triangles":34942,"far_triangles":far_level.actual_triangles,"far":far_level.path,"sha256":far_level.sha256,"instances":0,"station_mesh_assignment_unchanged":true,"visual_review":"pending_native_comparison"}
	for mesh: GeometryInstance3D in node.find_children("*","GeometryInstance3D",true,false):
		mesh.visibility_range_end=110.0
		mesh.visibility_range_end_margin=20.0
	var far_node:=distance_template.duplicate()
	node.add_child(far_node)
	for mesh: GeometryInstance3D in far_node.find_children("*","GeometryInstance3D",true,false):
		mesh.visibility_range_begin=110.0
		mesh.visibility_range_begin_margin=20.0
		mesh.visibility_range_end=380.0
		mesh.visibility_range_end_margin=45.0
		mesh.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	full_lod_records[LOADED].instances+=1

func _apply_sample_lighting(app: Node3D, world: Node3D) -> void:
	print("B2_FULL_BASE_READY ",Time.get_ticks_msec())
	# Measure source vertices before submitting GPU work; avoid synchronous Metal readback behind queued draws.
	for asset: String in sample_specs:
		if not source_boxes.has(asset) and sample_templates.has(asset+":near"):
			source_boxes[asset]=measure(sample_templates[asset+":near"]).bounds
	# Release the existing station/canyon authoring nodes before growing downstream districts.
	super._apply_sample_lighting(app,world)
	submit_render_uploads()
	full_regions=Regions.new()
	full_regions.build(self,JSON.parse_string(FileAccess.get_file_as_string(FULL_LAYOUT)))
	full_runtime_scene=""
	flush_full_batch()
	submit_render_uploads()
	full_regions.finish_surfaces()
	# Outdoor sky is part of the approved full-route targets; keep station light/exposure values.
	for environment_node: WorldEnvironment in app.find_children("*","WorldEnvironment",true,false):
		var material:=ProceduralSkyMaterial.new()
		material.sky_top_color=Color("6b96a8")
		material.sky_horizon_color=Color("c3d2cb")
		material.ground_bottom_color=Color("293c39")
		material.ground_horizon_color=Color("a2b4ad")
		material.sky_curve=.22
		var sky:=Sky.new()
		sky.sky_material=material
		environment_node.environment.sky=sky
	# Surface overrides and the sky also enqueue renderer resources; drain these before handing off.
	submit_render_uploads()

func submit_render_uploads() -> void:
	if DisplayServer.get_name()=="headless":return
	# Drain bounded resource uploads while physics remains unadvanced. No partial frame is presented/captured.
	RenderingServer.force_draw(false,0.0)
	initialization_draws+=1

func flush_full_batch() -> void:
	# The original verifier handles each bounded authoring chunk; retain every proof and unique ID.
	var previous: Dictionary=rebuild_world.get_meta("reconstruction_batching",{})
	var existing: Dictionary={}
	for child: Node in rebuild_world.get_children():
		if child is MultiMeshInstance3D:existing[child.get_instance_id()]=true
	rebuild_world.remove_meta("reconstruction_batching")
	var current: Dictionary=Batcher.new().build(self)
	if previous.is_empty():return
	var offset:=int(previous.batch_nodes)
	for child: Node in rebuild_world.get_children():
		if not child is MultiMeshInstance3D or existing.has(child.get_instance_id()):continue
		var ident:=str(child.get_meta("instance_id",""))
		if not ident.begins_with("rebuild:authored_batch:"):continue
		var index:=int(ident.get_slice(":",2))+offset
		child.set_meta("instance_id","rebuild:authored_batch:"+str(index))
		child.name="FullSceneAuthoredBatch_"+str(index)
	for group:Dictionary in current.groups:
		group.batch_id="rebuild:authored_batch:"+str(int(str(group.batch_id).get_slice(":",2))+offset)
	var phases:Array=previous.get("phases",[{"before":previous.added_bounds_sha256_before,"after":previous.added_bounds_sha256_after,"count":previous.added_bounds_count,"passed":previous.passed}])
	phases.append({"before":current.added_bounds_sha256_before,"after":current.added_bounds_sha256_after,"count":current.added_bounds_count,"passed":current.passed})
	current.phases=phases
	for key:String in ["eligible_source_nodes","batched_source_nodes","batch_nodes","singleton_groups_retained","failed_group_count","failed_tested_instance_count","elapsed_ms"]:
		current[key]+=previous.get(key,0)
	for key:String in ["max_corner_error_m","max_transform_component_error","max_normal_error"]:
		current[key]=maxf(float(current[key]),float(previous[key]))
	for key:String in previous.skipped:
		current.skipped[key]=int(current.skipped.get(key,0))+int(previous.skipped[key])
	current.groups=previous.groups+current.groups
	current.passed=previous.passed and current.passed
	current.added_bounds_unchanged=previous.added_bounds_unchanged and current.added_bounds_unchanged
	current.phase_count=phases.size()
	current.phase_policy="Bounded static authoring chunks; existing batches retained, every source ID and per-phase transform proof preserved"
	current.repeated_scan_counters=["eligible_source_nodes","singleton_groups_retained","skipped"]
	rebuild_world.set_meta("reconstruction_batching",current)
	print("B2_FULL_BATCH ",phases.size()," ",Time.get_ticks_msec())
