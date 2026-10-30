extends RefCounted
## S8 finite visual-slot dressing. Never writes route, collisions, camera or triggers.
var host: RefCounted
var session: Node3D
var world: Node3D
var config: Dictionary
var proxy: RefCounted
var spaces: Dictionary = {}
var assets: Dictionary = {}
var counts: Dictionary = {}
var pending: Array = []
var records: Array = []
const REPORT := "lux_route_dressing_report"
const EPS := 0.002
const SUPPORTED_SPACES := ["N01", "N07", "N08"]

func build(app: Node3D, target: Node3D, loader: RefCounted, settings: Dictionary) -> Dictionary:
	if target.has_meta(REPORT): return target.get_meta(REPORT)
	session = app
	world = target
	host = loader
	config = settings
	spaces.clear(); assets.clear(); counts.clear(); pending.clear(); records.clear()
	var error_start: int = host.errors.size()
	proxy = host.ProxyWorld.new()
	proxy.session = session
	proxy.route = session.lab.get_node("RouteRoot/MainRoute")
	var design_path: String = host.CASE + "styles/" + host.sid + "/design/2026-10-20-full-route/spatial-design.json"
	var design: Variant = JSON.parse_string(FileAccess.get_file_as_string(design_path))
	if not design is Dictionary:
		host.errors.append("Route dressing: missing spatial design")
		return {"errors":["missing spatial design"],"passed":false}
	for space: Dictionary in design.get("space_designs", []):
		for track: String in space.track_ids: spaces[track] = space.space_id
	for role: String in ["track_dress", "track_bracket", "release", "boost", "receiver"]:
		_prepare_asset(role)
	var serial := 0
	for source: MultiMeshInstance3D in session.lab.get_node("PresentationRoot").find_children("*", "MultiMeshInstance3D", true, false):
		var semantic: String = proxy._semantic_name(source)
		var source_id := semantic + ":%04d" % serial
		serial += 1
		var track: String = str(source.get_parent().name).rsplit("_", true, 1)[0]
		if not spaces.get(track, "") in SUPPORTED_SPACES or not spaces.get(track, "") in config.get("spaces", []): continue
		if not source.visible or source.multimesh == null: continue
		if semantic == "EdgeCurbs": _dress_slots(source, source_id, track, "track_dress")
		elif semantic == "ReleaseWindow": _dress_slots(source, source_id, track, "release")
		elif semantic == "PulseArrows": _dress_slots(source, source_id, track, "boost")
		elif semantic == "TrackPiers": _bracket_slots(source, source_id, track)
	if int(counts.get("release_slot_too_shallow",0)) > 0:
		_pending("release", "Flat gold signals retained: slot cannot contain a readable >=0.35m tall clamp. Side/under-track mounting needs separate 37-track and flight clearance proof.")
	if assets.has("track_bracket") and int(counts.get("track_bracket",0)) == 0:
		_pending("track_bracket", "No eligible enabled/readable upper-pier crown; keep existing support. A1 sleeper must first have generated rails removed with UV/PBR preserved.")
	# Frozen CatchGate exists only on drop/relay (N03/N05), outside these samples.
	# A portal's whole AABB is not a solid; no inferred cross-track gate is created.
	if assets.has("receiver"):
		_pending("receiver", "No frozen CatchGate slot in N01/N07/N08. Keep native capture rails/cues; reviewed aperture and foot-support placement still required.")
	var report := {"schema":1, "stage":"S8_PARTIAL_ROUTE_DRESSING", "spaces":config.get("spaces", []),
		"counts":counts.duplicate(), "instances":records.duplicate(), "pending":pending.duplicate(),
		"errors":host.errors.slice(error_start), "passed":host.errors.size() == error_start,
		"uniform_scale_only":true, "new_collision_nodes":0,
		"authority":"Native MultiMesh transforms, or count-checked exact frozen chunk loop reconstructed from live track.pose in dummy headless mode; model bounds contained in original oriented visual slots.",
		"unchanged":"Rail, Bed, Ties, release windows, pad triggers, route frames, collision objects and camera solids",
		"limits":"Pending native visual/readability review. Slot containment is not H4 or a receiver-aperture proof. Existing signal underlays remain visible."}
	world.set_meta(REPORT, report)
	return report

func _pending(role: String, reason: String) -> void:
	pending.append({"role":role,"reason":reason})
	host.warnings.append("Route dressing " + role + ": " + reason)

func _prepare_asset(role: String) -> void:
	var ident: String = str(config.get("roles", {}).get(role, ""))
	if ident.is_empty():
		_pending(role, "No source binding supplied")
		return
	var model: Node3D = host.sample_templates.get(ident + ":near")
	if model == null or not host.sample_specs.has(ident):
		_pending(role, "Normalized near template unavailable: " + ident)
		return
	var spec: Dictionary = host.sample_specs[ident]
	var result: Dictionary = host.measure(model)
	if not result.finite or result.mesh_count == 0:
		host.errors.append("Route dressing invalid measured source: " + ident)
		return
	var box: AABB = result.bounds
	var declared: Vector3 = host.vector(spec.get("result_size_m", [0,0,0]))
	if box.size.x <= 0 or box.size.y <= 0 or box.size.z <= 0:
		host.errors.append("Route dressing empty model: " + ident)
		return
	if absf(box.position.y) > 0.01 or absf(box.get_center().x) > 0.01 or absf(box.get_center().z) > 0.01 or absf(box.size.y - 1.0) > 0.01 or (box.size-declared).abs().length() > 0.025:
		host.errors.append("Route dressing expected measured height-1 bottom-center normalization: " + ident)
		return
	if spec.get("source_to_normalized", []).size() != 16 or str(spec.get("source", {}).get("sha256", "")).length() != 64:
		host.errors.append("Route dressing missing source provenance: " + ident)
		return
	var pieces: Array = []
	_collect_meshes(model, Transform3D.IDENTITY, pieces)
	assets[role] = {"id":ident,"box":box,"pieces":pieces,"spec":spec}

func _collect_meshes(node: Node, parent: Transform3D, output: Array) -> void:
	var pose: Transform3D = parent * node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh != null:
		# Resource duplication only when overrides exist; vertex/texture data remains shared.
		var mesh: Mesh = node.mesh
		if node.material_override != null or node.get_surface_override_material_count() > 0:
			mesh = mesh.duplicate(false)
			for surface in mesh.get_surface_count(): mesh.surface_set_material(surface, node.get_active_material(surface))
		output.append({"mesh":mesh,"pose":pose,"name":str(node.name)})
	for child: Node in node.get_children(): _collect_meshes(child, pose, output)

func _slot_signature(size: Vector3, role: String) -> bool:
	if role == "track_dress": return absf(size.x-0.18)<EPS and absf(size.y-0.4)<EPS and size.z>0 and size.z<=4.03
	if role == "boost": return size.is_equal_approx(Vector3(1.9,0.12,0.38))
	if role == "release": return (absf(size.y-0.14)<EPS and absf(size.z-0.5)<EPS) or size.is_equal_approx(Vector3(0.5,1,0.65))
	if role == "track_bracket": return absf(size.x-2.4)<EPS and absf(size.z-2.4)<EPS and size.y>6
	return false

func _frozen_poses(source: MultiMeshInstance3D, track_id: String, role: String) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var readable := true
	for index in source.multimesh.instance_count:
		var value := source.multimesh.get_instance_transform(index)
		readable = readable and _slot_signature(value.basis.get_scale(),role)
		result.append(value)
	if readable: return result
	# Dummy rendering returns identity for MM instance reads. Reconstruct only the
	# three exact frozen chunk loops, from the LIVE route frame and geometry_step.
	# The source count and primitive signature must match; piers use a filtered loop
	# and are intentionally not guessed in headless mode.
	result.clear()
	if DisplayServer.get_name() != "headless" or role == "track_bracket":
		_pending(role,"Frozen MM transform unavailable or signature mismatch: " + str(source.get_path()))
		return result
	if proxy.route.get("tracks") == null or not proxy.route.tracks.has(track_id):
		_pending(role,"No live route authority for headless MM reconstruction")
		return result
	var step: float = session.lab.get("geometry_step")
	if step <= 0 or step > 4.0:
		_pending(role,"Unsupported frozen geometry_step")
		return result
	var chunk := source.get_parent() as Node3D
	var chunk_index := int(str(chunk.name).rsplit("_",true,1)[1])
	var track = proxy.route.tracks[track_id]
	for j in ceili(120.0/step):
		var s := chunk_index*120.0+j*step
		if s>=track.length: break
		var span := minf(step,track.length-s)
		var pose: Transform3D = track.pose(s+span*0.5)
		pose.origin -= chunk.position
		if role == "track_dress" and not track.single_lane:
			for sign_value in [-1,1]: result.append(pose.translated_local(Vector3(sign_value*(track.width_at(s)-0.05),0.2,0)).scaled_local(Vector3(0.18,0.4,span+0.025)))
		elif role == "boost":
			for pad in track.pads:
				if s>=pad.a and s<=pad.b:
					for sign_value in [-1,1]: result.append(pose.translated_local(Vector3(pad.lane*4.4+sign_value*0.65,0.19,0)).rotated_local(Vector3.UP,sign_value*0.65).scaled_local(Vector3(1.9,0.12,0.38)))
		elif role == "release" and track.can_release(s) and j%3==0:
			result.append(pose.translated_local(Vector3(0,0.12,0)).scaled_local(Vector3(track.half_width*1.7,0.14,0.5)))
			if track.impulse.length()>0.1:
				for sign_value in [-1,1]: result.append(pose.translated_local(Vector3(sign_value*1.9,0.55,0)).scaled_local(Vector3(0.5,1.0,0.65)))
	if result.size()!=source.multimesh.instance_count:
		host.errors.append("Route dressing headless frozen enumeration mismatch: "+str(source.get_path()))
		result.clear()
	else:
		counts["cpu_reconstructed_source_batches"] = int(counts.get("cpu_reconstructed_source_batches",0))+1
	return result

func _isolate(source: MultiMeshInstance3D, original_poses: Array[Transform3D]) -> MultiMesh:
	# Do not mutate a shared native resource or rely on headless GPU-buffer reads.
	var old := source.multimesh
	var isolated := MultiMesh.new()
	isolated.transform_format = old.transform_format
	isolated.use_colors = old.use_colors
	isolated.use_custom_data = old.use_custom_data
	isolated.mesh = old.mesh
	isolated.instance_count = old.instance_count
	isolated.visible_instance_count = old.visible_instance_count
	isolated.custom_aabb = old.custom_aabb
	for index in old.instance_count:
		isolated.set_instance_transform(index, original_poses[index])
		if old.use_colors: isolated.set_instance_color(index, old.get_instance_color(index))
		if old.use_custom_data: isolated.set_instance_custom_data(index, old.get_instance_custom_data(index))
	return isolated

func _dress_slots(source: MultiMeshInstance3D, source_id: String, track: String, role: String) -> void:
	if not assets.has(role): return
	if not source.multimesh.mesh is BoxMesh or not source.multimesh.mesh.size.is_equal_approx(Vector3.ONE):
		_pending(role, "Unrecognized frozen primitive: " + source_id)
		return
	var asset: Dictionary = assets[role]
	var size: Vector3 = asset.box.size
	var poses: Array[Transform3D] = []
	var ids: Array[String] = []
	var replacement: MultiMesh
	var originals := _frozen_poses(source, track, role)
	if originals.is_empty(): return
	# Edge refinement is finite, repeated every four frozen segments by default; original curbs fill gaps.
	var stride := maxi(1, int(config.get("edge_stride_segments", 4))) if role == "track_dress" else 1
	for index in source.multimesh.instance_count:
		if role == "track_dress" and (index / 2) % stride != 0: continue
		var original: Transform3D = originals[index]
		var frozen: Transform3D = source.global_transform * original
		var envelope := frozen.basis.get_scale()
		if envelope.x <= 0 or envelope.y <= 0 or envelope.z <= 0: continue
		var rigid := Transform3D(frozen.basis.orthonormalized(), frozen.origin)
		# Keep the original material as a thin signal/plinth underlay. Its X/Z footprint
		# and orientation survive, including cyan arrows, gold release and purple rescue.
		var underlay := minf(0.025, envelope.y * 0.15)
		var allowed := Vector3(envelope.x, envelope.y - underlay, envelope.z) * 0.98
		var scalar := minf(allowed.x / size.x, minf(allowed.y / size.y, allowed.z / size.z))
		if role == "release" and (envelope.y < 0.4 or scalar * size.y < 0.35):
			var skip_key := "release_slot_too_shallow"
			counts[skip_key] = int(counts.get(skip_key,0)) + 1
			continue
		var local := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scalar), Vector3(0,-envelope.y*0.5 + underlay,0))
		var bounds: AABB = local * asset.box
		var original_box := AABB(-envelope * 0.5, envelope)
		if not original_box.grow(EPS).encloses(bounds):
			host.errors.append("Route dressing slot containment failed: " + source_id + ":" + str(index))
			continue
		if replacement == null: replacement = _isolate(source, originals)
		var signal_pose := Transform3D(rigid.basis.scaled_local(Vector3(envelope.x,underlay,envelope.z)), rigid.origin - rigid.basis.y*(envelope.y-underlay)*0.5)
		replacement.set_instance_transform(index, source.global_transform.affine_inverse() * signal_pose)
		var ident: String = host.sid + ":lux-route:" + source_id + ":" + str(index)
		poses.append(rigid * local)
		ids.append(ident)
		var record := {"id":ident,"asset_id":asset.id,"role":role,"space_id":spaces[track],"track_id":track,
			"source_visual_slot":str(source.get_path()) + ":" + str(index),
			"frozen_transform":host.transform_array(frozen), "original_slot_size_m":host.array(envelope),
			"uniform_scale":scalar,"model_size_m":host.array(size*scalar),"underlay_height_m":underlay,
			"source_sha256":asset.spec.source.sha256,"source_to_normalized_applied_once":true,
			"native_geometry_scope":"Visual MM instance only; original signal footprint and all gameplay retained", "pending_native_visual_review":true}
		records.append(record); host.instance_reports.append(record)
	if replacement != null: source.multimesh = replacement
	_emit(asset, poses, ids, spaces[track], role)

func _bracket_slots(source: MultiMeshInstance3D, source_id: String, track: String) -> void:
	if not assets.has("track_bracket"): return
	if track != "upper" or host.sid != "odd-logistics": return
	if not bool(config.get("enable_upper_pier_brackets", false)): return
	var asset: Dictionary = assets.track_bracket
	# Reject the A1 sleeper asset with baked generated rails; it needs rail-free extraction.
	if not str(asset.id).contains("single_rail_bracket"):
		_pending("track_bracket", "Only reviewed B2 single_rail_bracket can occupy the original upper pier crown")
		return
	var size: Vector3 = asset.box.size
	var poses: Array[Transform3D] = []
	var ids: Array[String] = []
	var replacement: MultiMesh
	var originals := _frozen_poses(source, track, "track_bracket")
	if originals.is_empty(): return
	for index in source.multimesh.instance_count:
		var frozen: Transform3D = source.global_transform * originals[index]
		var old_size := frozen.basis.get_scale()
		if not old_size.x > 2.39 or not old_size.x < 2.41 or not old_size.z > 2.39 or not old_size.z < 2.41 or old_size.y < 8: continue
		var rigid := Transform3D(frozen.basis.orthonormalized(),frozen.origin)
		var scalar := minf(1.6 / size.y, minf(2.35 / size.x,2.35 / size.z))
		var height := size.y * scalar
		var local := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scalar),Vector3(0,old_size.y*0.5-height,0))
		if not AABB(-old_size*0.5,old_size).grow(EPS).encloses(local*asset.box): continue
		var ident: String = host.sid + ":lux-route:" + source_id + ":" + str(index)
		if _existing_near_asset(asset.id,(rigid*local).origin):
			_pending("track_bracket", "Existing asset already occupies crown: " + ident)
			continue
		if replacement == null: replacement = _isolate(source, originals)
		var remaining := Transform3D(rigid.basis.scaled_local(Vector3(old_size.x,old_size.y-height,old_size.z)),rigid.origin-rigid.basis.y*height*0.5)
		replacement.set_instance_transform(index,source.global_transform.affine_inverse()*remaining)
		poses.append(rigid*local); ids.append(ident)
		var record := {"id":ident,"asset_id":asset.id,"role":"track_bracket","space_id":spaces[track],
			"uniform_scale":scalar,"frozen_transform":host.transform_array(frozen),"old_pier_size_m":host.array(old_size),
			"source_sha256":asset.spec.source.sha256,"source_to_normalized_applied_once":true,
			"contact":"Bottom rests on shortened visual pier; highest bracket reaches original pier top", "camera_solid":"Original full pier unchanged", "pending_native_visual_review":true}
		records.append(record); host.instance_reports.append(record)
	if replacement != null: source.multimesh = replacement
	_emit(asset,poses,ids,spaces[track],"track_bracket")

func _existing_near_asset(asset: String, at: Vector3) -> bool:
	for report: Dictionary in host.instance_reports:
		if str(report.get("asset_id", "")) == asset and report.has("position") and host.vector(report.position).distance_to(at) < 2.0: return true
	return false

func _emit(asset: Dictionary, poses: Array[Transform3D], ids: Array[String], space: String, role: String) -> void:
	if poses.is_empty(): return
	var root_inverse := world.global_transform.affine_inverse()
	for piece: Dictionary in asset.pieces:
		for first in range(0,poses.size(),24):
			var amount := mini(24,poses.size()-first)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = piece.mesh
			mm.instance_count = amount
			var node := MultiMeshInstance3D.new()
			node.multimesh = mm
			node.visibility_range_end = float(config.get("visibility_range_end", 240.0))
			world.add_child(node)
			host._tag_tree(node,ids[first] + ":batch:" + piece.name,asset.id,"station" if space == "N01" else "valley")
			for offset in amount:
				var index := first + offset
				var global_pose: Transform3D = poses[index] * piece.pose
				mm.set_instance_transform(offset,root_inverse * global_pose)
				var box: AABB = global_pose * piece.mesh.get_aabb()
				host.added_bounds.append({"id":ids[index]+":"+piece.name,"style_id":host.sid,"space_id":space,
					"category":"support" if role in ["track_bracket","track_dress"] else "route_surface",
					"center_m":host.array(box.get_center()),"size_m":host.array(box.size),"basis_columns":[[1,0,0],[0,1,0],[0,0,1]],
					"protected_route":role != "track_bracket","bounds_kind":"conservative_mesh_aabb",
					"source_asset_id":asset.id,"source_sha256":asset.spec.source.sha256,
					"mesh_local_aabb":host.box_record(piece.mesh.get_aabb()),"mesh_to_world":host.transform_array(global_pose),
					"clearance_basis":"Contained inside the exact existing oriented visual slot; no new gameplay clearance claim"})
	counts[role] = int(counts.get(role,0)) + poses.size()
