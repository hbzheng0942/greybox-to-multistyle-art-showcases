extends RefCounted
## Appearance only. Frozen SpatialTrack frames and actor parent transforms are authority.
## No collision, route, camera, scoring or motion nodes are created or changed.
const PAPER = preload("transport_paper.gdshader")
const TRAIN_MATERIALS = preload("material_adapter.gd")
const TRAIN_ASSET_SPEC := "res://themes/paper_atlas/train_visual.json"
const CHUNK_M := 160.0
const SAMPLE_M := 1.6
const TRANSFER_TRACKS = ["rush", "carve", "wall", "inverted", "drop", "rollout"]
const TRACK_SCENES = {"station_start": "station", "station_carve": "station", "station_ramp": "canyon", "canyon_safe": "canyon", "canyon_fast_catch": "canyon", "canyon_fast": "canyon", "canyon_merge": "canyon", "rush": "vertical", "carve": "vertical", "wall": "vertical", "inverted": "vertical", "drop": "vertical", "rollout": "vertical", "loop_entry": "coaster", "loop": "coaster", "loop_out": "coaster", "exit_ramp": "coaster", "grind": "coaster", "relay": "coaster", "high": "coaster", "high_merge": "coaster", "tunnel": "tunnel", "cliff_turn": "valley", "cliff_lip": "valley", "upper": "valley", "rescue": "valley", "rescue_merge": "valley", "finish": "valley", "landmark_return": "valley", "underpass": "finale", "return_switchback": "finale", "final_approach": "finale", "final_ramp": "finale", "final_receiver": "finale", "final_upper_catch": "finale", "final_upper": "finale", "victory_run": "finale"}
const TRAIN_LIMIT := AABB(Vector3(-1.30, 0.02, -5.98), Vector3(2.60, 3.26, 11.96))
var material: ShaderMaterial
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var palette := {}
var report := {}
var edge_corridors := {}
var edge_corridor_count := 0
var edge_kept_spans := 0
var edge_omitted_spans := 0
const EDGE_GRID_M := 32.0
var train_asset_report := {"mode":"procedural_fallback", "validated":false}

func prepare_material() -> void:
	var values := {"ivory":"eadfc6", "edge":"f6e8cd", "fold":"cdbfa5", "coral":"cc654b", "coral_dark":"ab4d39", "teal":"235558", "glass":"173c4c", "glass_light":"2c5361", "deck":"334756", "dark":"21333c", "cyan":"46b7bf", "gold":"daa741", "gold_light":"f3ca65", "rail_side":"758887", "rail_head":"c9d4cd", "joint":"22383f", "tie":"bdbaa9"}
	for key in values: palette[key] = Color(values[key]).srgb_to_linear()
	material = ShaderMaterial.new()
	material.shader = PAPER

func install(session: Node3D, root: Node3D) -> Dictionary:
	if root.has_node("PaperTransport"):
		return root.get_node("PaperTransport").get_meta("transport_report", {})
	prepare_material()
	var transport := Node3D.new()
	transport.name = "PaperTransport"
	_tag(transport, "transport", "transport_package", "paper_transport_r3", "decorative")
	root.add_child(transport)
	var geometry := session.get_node("Actors/Train/VisualRoot/TrickPivot/Geometry") as Node3D
	for child in geometry.get_children():
		if child is Node3D: child.visible = false
	_build_train(geometry)
	for child in root.get_children():
		if str(child.name).ends_with("_PaperTrack"): child.visible = false
		if str(child.get_meta("asset_id", "")) == "GT_solid_folded_hazard": child.visible = false
	var lab = session.get_node("ControllerLab")
	var prior := lab.get_node("PresentationRoot") as Node3D
	_hide_legacy(prior, lab.route.tracks)
	var release_cues := _replace_inverted_release_cues(prior, transport, lab.route.tracks.inverted, lab.geometry_step)
	_prepare_edge_clearance(lab.route.tracks)
	var rollout_support := _replace_rollout_support(prior, transport, lab.route.tracks.rollout)
	var tracks := 0
	var chunks := 0
	var gate_poses: Array[Transform3D] = []
	var gate_ids := []
	var gate_groups := {}
	for key in lab.route.tracks:
		if not _owns_track(str(key)): continue
		var track: SpatialTrack = lab.route.tracks[key]
		chunks += _build_track(transport, track)
		tracks += 1
		for obstacle in track.obstacles:
			if str(obstacle.get("kind", "block")) != "block": continue
			# Preserve actual obstacle dimensions. Current full route uses H=5m.
			for lane in obstacle.lanes:
				var pose := track.pose(float(obstacle.s), float(lane) * 4.4)
				pose.basis = pose.basis.scaled(Vector3(1, float(obstacle.height) / 5.0, 1))
				gate_poses.append(pose)
				gate_ids.append(str(track.id) + ":" + str(obstacle.get("id", obstacle.s)) + ":" + str(lane))
				var region := _scene(track)
				if not gate_groups.has(region): gate_groups[region] = {"poses":[],"ids":[]}
				gate_groups[region].poses.append(pose)
				gate_groups[region].ids.append(gate_ids.back())
	var gate_mesh := _gate_mesh()
	# Seven small gates span 1.66 km. Batch-centre distance must not cull a near gate.
	for region in gate_groups:
		var poses: Array[Transform3D] = []
		poses.assign(gate_groups[region].poses)
		var gates := _multimesh(transport, "SolidFoldedGates_"+region, gate_mesh, poses, region, "GT_solid_folded_hazard", "paper_solid_gates_"+region, 0.0)
		if gates != null:
			gates.set_meta("instance_ids", gate_groups[region].ids)
			gates.set_meta("clearance_role", "authored_gameplay_obstacle_visual")
	report = {"revision":"paper_transport_r3", "scope":"All 37 frozen tracks and authored block obstacles across N01-N07; actor art follows unchanged full route", "tracks":tracks, "track_chunks":chunks, "block_gate_instances":gate_poses.size(), "train_bounds_m":{"min":[-1.30,0.02,-5.98],"max":[1.30,3.28,5.98]}, "train_actual_bounds":_box_dict(_train_bounds), "train_asset":train_asset_report, "inverted_release_cues":release_cues, "rollout_open_support":rollout_support, "edge_clearance":{"corridors":edge_corridor_count,"kept_spans":edge_kept_spans,"omitted_spans":edge_omitted_spans,"max_local_y":-.42,"grind_side_detail":"omitted across narrow airborne catch surfaces; full contact rail assembly retained","method":"All 37 frozen track frames, full rail width plus vehicle half-width; conservative nearby oriented corridors omit interfering closed decorative spans"}, "track_frame_source":"SpatialTrack.pose / width_at / lanes; grind gauge 0.26 otherwise 0.72", "track_contact_asset_id":"RT01_03", "collision_added":false, "geometry":"profiled rail head/web/foot, seated fastenings, bevelled sleepers, 16m recessed deck joints, closed below-bed edge folds with route-aware merge gaps and shallow underdeck ribs", "decoration_clearance_role":"transport_decoration", "limits":"Visual candidate; side_detail and underdeck require native recorded-path clearance. Train validates all imported mesh vertices inside frozen appearance envelope; not concept acceptance."}
	transport.set_meta("transport_report", report)
	root.set_meta("paper_transport_report", report)
	return report

func _owns_track(id: String) -> bool:
	return TRACK_SCENES.has(id)

func _hide_legacy(prior: Node3D, tracks: Dictionary) -> void:
	var source_track := ""
	for child in prior.get_children():
		for key in tracks:
			if str(child.name).begins_with(str(key)+"_"): source_track = str(key)
		if not _owns_track(source_track): continue
		# Shared root Block batches have no per-track identity. presentation.build
		# already hides exactly the seven N01/N02 block sources before this install.
		# Replace its tagged Paper hazards above; never infer shared-batch ownership.
		if _owns_track(source_track) and child is MultiMeshInstance3D:
			var mm: MultiMesh = child.multimesh
			if mm != null and mm.instance_count == 1 and mm.mesh is BoxMesh and mm.mesh.size == Vector3.ONE:
				var old_mat := mm.mesh.material as StandardMaterial3D
				if old_mat != null and old_mat.albedo_color.is_equal_approx(Color(1,0.18,0.11)):
					child.visible = false
		if _owns_track(source_track):
			# The full rolled paper sweep replaces the old rectangular enclosure visually.
			for label in ["ContactStructure", "Clamps"]:
				var obsolete := child.get_node_or_null(label) as GeometryInstance3D
				if obsolete != null: obsolete.visible = false
			var pier := child.get_node_or_null("TrackPiers") as GeometryInstance3D
			if pier != null:
				var finish := StandardMaterial3D.new()
				finish.albedo_color = Color("eadfc6")
				finish.roughness = 0.96
				finish.metallic_specular = 0.10
				pier.material_override = finish
		for key in ["Bed", "Rail", "Ties", "EdgeCurbs", "NearMasses", "NearSpeedMarkers"]:
			var node := child.get_node_or_null(key)
			if node is GeometryInstance3D: node.visible = false

func _support_member(parent: Node3D, label: String, a: Vector3, b: Vector3, width_a: float, width_b: float, tint: String) -> MeshInstance3D:
	# One closed eight-sided tapered solid, with caps. Adjacent members overlap;
	# these are real structural volumes, never a camera-facing facade or mask.
	_reset_mesh()
	var axis := (b-a).normalized()
	var right := axis.cross(Vector3.FORWARD).normalized()
	if right.length_squared()<.5: right=axis.cross(Vector3.RIGHT).normalized()
	var up := axis.cross(right).normalized()
	var rings := []
	for endpoint in [[a,width_a],[b,width_b]]:
		var ring := []
		for i in 8:
			var angle := TAU*(float(i)+.5)/8.0
			ring.append(endpoint[0]+(right*cos(angle)+up*sin(angle))*float(endpoint[1])*.5)
		rings.append(ring)
	_face(rings[0],tint,-axis); _face(rings[1],tint,axis)
	for i in 8:
		var j := (i+1)%8
		_face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],tint,(rings[0][i]+rings[0][j])*.5-a)
	var node := _node(parent,label,_mesh(),"vertical","RT05_OPEN_BEARING","rollout_00:open_bearing:"+label,850.0)
	node.set_meta("clearance_role","transport_decoration")
	return node

func _replace_rollout_support(prior: Node3D, parent: Node3D, track: SpatialTrack) -> Dictionary:
	# Native R8 exact rays identified rollout_00/TrackPiers instance 1, only
	# 1.42m from the camera. The retained baseline pair is appearance only.
	# Replace both by a genuine open support, not by recolouring or disabling QA.
	var old := prior.get_node_or_null("rollout_00/TrackPiers") as GeometryInstance3D
	if old==null: return {"replaced":false,"reason":"known baseline support absent"}
	var pose := track.pose(60.0)
	var horizontal := Vector3(pose.basis.x.x,0,pose.basis.x.z).normalized()
	var frame := Node3D.new(); frame.name="RolloutOpenBearing"; parent.add_child(frame)
	_tag(frame,"vertical","RT05_OPEN_BEARING","rollout_00:open_bearing","transport_decoration")
	var witnesses := []
	for side in [-1,1]:
		var center := pose.origin+horizontal*float(side)*30.0
		var foot := Vector3(center.x,-36.0,center.z)
		var footing_top := Vector3(center.x,-20.0,center.z)
		_support_member(frame,"SubmergedFooting_"+str(side),foot,footing_top,7.0,4.6,"teal")
		_support_member(frame,"PierBase_"+str(side),footing_top-Vector3.UP*.4,Vector3(center.x,8.3,center.z),3.9,2.7,"fold")
		_support_member(frame,"PierShaft_"+str(side),Vector3(center.x,8.0,center.z),Vector3(center.x,69.0,center.z),2.7,2.3,"ivory")
		witnesses.append({"side":side,"foundation_bottom":[foot.x,foot.y,foot.z],"foundation_top_y":-20.0,"pillar_bottom_y":-20.4,"foundation_embed_m":.4,"water_surface_y":-21.5,"lateral_m":30.0})
	# At s60 local -Y points upward in world space. Put the arch above the
	# inverted train, with a short hanger joining the existing real keel.
	var arch := []
	for row in [[-30.0,68.5],[-17.0,80.0],[0.0,84.0],[17.0,80.0],[30.0,68.5]]:
		var point := pose.origin+horizontal*float(row[0]); point.y=float(row[1]); arch.append(point)
	for i in range(arch.size()-1):
		var axis:Vector3=(arch[i+1]-arch[i]).normalized()
		_support_member(frame,"CrownFold_"+str(i),arch[i]-axis*.32,arch[i+1]+axis*.32,2.6,2.6,"ivory")
	# FoldedBridgeRibs use translate_local y=-.72, scale y=1.7, and a
	# keel polygon y=-1.9 -> actual local keel y=-3.95, at exact s=60.
	# The endpoint y=-3.76 embeds in that existing lower solid by .19m.
	var keel := pose*Vector3(0,-3.95,0)
	var connection := pose*Vector3(0,-3.76,0)
	_support_member(frame,"KeelHanger",connection,arch[2]+Vector3.UP*.3,1.12,1.7,"gold")
	old.visible=false
	return {"replaced":true,"hidden_source":"ControllerLab/PresentationRoot/rollout_00/TrackPiers","hidden_instances":2,"source_anchor_s":60.0,"new_mesh_nodes":frame.get_child_count(),"foundation":"New closed submerged footings: bottom -36, top -20, water -21.5. No existing seabed contact is claimed.","footing_witnesses":witnesses,"actual_keel_world":[keel.x,keel.y,keel.z],"hanger_connection_world":[connection.x,connection.y,connection.z],"keel_embed_m":.19,"source_rib":"rollout_PaperTransport_0/FoldedBridgeRibs at s=60 (sixth instance)","clearance_role":"transport_decoration","collision_added":false,"native_acceptance":false}

func _replace_inverted_release_cues(prior: Node3D, parent: Node3D, track: SpatialTrack, geometry_step: float) -> Dictionary:
	# These are authored Space/coil hints, not obsolete track or collision meshes.
	# Retain the exact four pad intervals and the old release-strip sampling, but
	# seat the art below the rail head instead of hiding the train's contact rails.
	if track.id != "inverted" or track.release_windows.is_empty():
		return {"replaced":false,"reason":"no inverted release window"}
	var old_pads: Array[GeometryInstance3D] = []
	for pad_index in 4:
		for side in [-1,0,1]:
			var pad := prior.get_node_or_null("InvertedEjectPad_%02d_%d" % [pad_index,side]) as GeometryInstance3D
			if pad != null: old_pads.append(pad)
	# Keep the original display intact if the known source layout has changed.
	if old_pads.size()!=12 or geometry_step<=0.0:
		return {"replaced":false,"reason":"authored cue layout differs","source_pads":old_pads.size()}
	var old_strips: Array[GeometryInstance3D] = []
	for chunk in prior.get_children():
		if not str(chunk.name).begins_with("inverted_"): continue
		var strip := chunk.get_node_or_null("ReleaseWindow") as GeometryInstance3D
		if strip!=null: old_strips.append(strip)
	var release: Vector2 = track.release_windows[0]
	var cue_origin := track.pose((release.x+release.y)*.5).origin
	_reset_mesh()
	var pad_intervals := []
	for pad_index in 4:
		var pad_start := release.x+float(pad_index)*22.0
		var pad_length := minf(18.0,release.y-pad_start)
		if pad_length<=0.0:continue
		pad_intervals.append([pad_start,pad_start+pad_length])
		var pose := track.pose(pad_start+pad_length*.5)
		pose.origin-=cue_origin
		# The central 0.90m arrow leaves 0.16m to the closest rail foot.
		# Two edge arrows sit inside the existing curb, with their bases in the slab.
		_release_arrow(pose,.90,pad_length)
		for side in [-1,1]:
			_release_arrow(pose.translated_local(Vector3(side*(track.half_width-.60),0,0)),.40,pad_length)
	var strip_positions := []
	for chunk_index in ceili(track.length/120.0):
		for j in ceili(120.0/geometry_step):
			var s := chunk_index*120.0+j*geometry_step
			if s>=track.length:break
			if j%3!=0 or not track.can_release(s):continue
			var span := minf(geometry_step,track.length-s)
			var at := s+span*.5
			strip_positions.append(at)
			var pose := track.pose(at);pose.origin-=cue_origin
			# Split the continuous legal-window cue around both rail feet. The old
			# metre-tall powered blocks become seated low inlays, not orphan cubes.
			for limits in [Vector2(-track.half_width*.85,-.90),Vector2(-.50,.50),Vector2(.90,track.half_width*.85)]:
				_box(Vector3((limits.x+limits.y)*.5,-.09,0),Vector3(limits.y-limits.x,.18,.50),"gold",pose)
	if pad_intervals.size()!=4 or strip_positions.is_empty():
		_reset_mesh()
		return {"replaced":false,"reason":"incomplete replacement cue"}
	var cue := _node(parent,"SeatedInvertedReleaseCues",_mesh(),"vertical","RT_RELEASE_CUE","inverted:release_cues")
	cue.position=cue_origin
	cue.set_meta("clearance_role","authored_gameplay_cue_visual")
	cue.set_meta("authored_release_window",release)
	cue.set_meta("authored_pad_intervals",pad_intervals)
	for old in old_pads+old_strips:old.visible=false
	return {"replaced":true,"source":"spatial_full_lab.gd InvertedEjectPad and inverted-only ReleaseWindow", "source_pad_nodes":old_pads.size(),"source_strip_nodes":old_strips.size(),"pad_intervals":pad_intervals,"strip_positions":strip_positions,"release_window":[release.x,release.y],"arrow_top_y":.035,"rail_head_y":.16,"arrow_to_rail_foot_gap_m":.16,"added_collision":false,"role":"authored_gameplay_cue_visual","scope":"Display-only replacement; Space, impulse, action zones and full-roll poses unchanged"}

func _release_arrow(pose: Transform3D, width: float, length: float) -> void:
	# Closed shallow bevelled pentagon, embedded 0.02m into the existing slab.
	# Its arrow points along the frozen track's local -Z direction.
	var shape := [Vector2(-width*.5,length*.5),Vector2(width*.5,length*.5),Vector2(width*.5,-length*.20),Vector2(0,-length*.5),Vector2(-width*.5,-length*.20)]
	var bottom := [];var rim := [];var top := []
	for p in shape:
		bottom.append(pose*Vector3(p.x,-.18,p.y))
		rim.append(pose*Vector3(p.x,.005,p.y))
		top.append(pose*Vector3(p.x*.88,.035,p.y*.994))
	_face(bottom,"gold",-pose.basis.y)
	_face(top,"gold_light",pose.basis.y)
	for i in shape.size():
		var j := (i+1)%shape.size()
		var outward: Vector3 = pose.basis*Vector3((shape[i].x+shape[j].x)*.5,0,(shape[i].y+shape[j].y)*.5)
		_face([bottom[i],bottom[j],rim[j],rim[i]],"gold",outward)
		_face([rim[i],rim[j],top[j],top[i]],"gold_light",outward+pose.basis.y)

func _tag(node: Node, scene: String, asset: String, identity: String, role := "contact_transport") -> void:
	node.set_meta("scene_id", scene)
	node.set_meta("asset_id", asset)
	node.set_meta("instance_id", identity)
	node.set_meta("clearance_role", role)

func _scene(track: SpatialTrack) -> String:
	return str(TRACK_SCENES.get(track.id, "unknown"))

func _reset_mesh() -> void:
	vertices = PackedVector3Array()
	normals = PackedVector3Array()
	colors = PackedColorArray()

func _face(points: Array, color_key: String, outward: Vector3) -> void:
	if points.size() < 3: return
	var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var reverse := normal.dot(outward) < 0.0
	if reverse: normal = -normal
	var color: Color = palette[color_key]
	# Alpha is a roughness channel, not transparency; all geometry stays opaque.
	color.a = 0.76 if color_key.begins_with("glass") else 0.96
	for i in range(1, points.size()-1):
		# Godot fronts are clockwise; explicit outward normals stay unchanged.
		var order := [0, i, i+1] if reverse else [0, i+1, i]
		for index in order:
			vertices.append(points[index]); normals.append(normal); colors.append(color)

func _mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if vertices.is_empty(): return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

func _box(center: Vector3, size: Vector3, color: String, pose := Transform3D.IDENTITY) -> void:
	var p := []
	for z in [-0.5,0.5]:
		for y in [-0.5,0.5]:
			for x in [-0.5,0.5]: p.append(pose * (center + Vector3(x,y,z)*size))
	for face in [[0,2,3,1],[4,5,7,6],[0,4,6,2],[1,3,7,5],[0,1,5,4],[2,6,7,3]]:
		var points := [p[face[0]],p[face[1]],p[face[2]],p[face[3]]]
		var middle: Vector3 = (points[0]+points[1]+points[2]+points[3])*.25
		_face(points, color, middle - pose*center)

func _node(parent: Node3D, name: String, mesh: Mesh, scene: String, asset: String, identity: String, range_end := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name; node.mesh = mesh
	_tag(node, scene, asset, identity)
	if range_end > 0.0:
		node.visibility_range_end = range_end
		node.visibility_range_end_margin = 70.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(node)
	return node

func _multimesh(parent: Node3D, name: String, mesh: Mesh, poses: Array[Transform3D], scene: String, asset: String, identity: String, range_end := 700.0) -> MultiMeshInstance3D:
	if poses.is_empty(): return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh; mm.instance_count = poses.size()
	for i in poses.size(): mm.set_instance_transform(i, poses[i])
	var node := MultiMeshInstance3D.new()
	node.name = name; node.multimesh = mm
	# The headless dummy renderer does not retain MultiMesh transforms for readback.
	node.set_meta("paper_instance_transforms", poses.duplicate())
	_tag(node, scene, asset, identity)
	node.visibility_range_end = range_end
	node.visibility_range_end_margin = 70.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(node)
	return node

var _train_bounds := AABB()
func _build_train(parent: Node3D) -> void:
	if _try_build_generated_train(parent): return
	_reset_mesh()
	var sections := [
		[-5.95,1.08,.66,1.48,.80,1.70],[-5.38,1.25,.60,2.60,.86,2.90],[-4.45,1.27,.60,2.64,.94,3.06],
		[4.45,1.27,.60,2.64,.94,3.06],[5.38,1.25,.60,2.60,.86,2.90],[5.95,1.08,.66,1.48,.80,1.70]]
	var rings := []
	for s in sections:
		rings.append([Vector3(-s[1],s[2],s[0]),Vector3(s[1],s[2],s[0]),Vector3(s[1],s[3],s[0]),Vector3(s[4],s[5],s[0]),Vector3(-s[4],s[5],s[0]),Vector3(-s[1],s[3],s[0])])
	for i in range(rings.size()-1):
		for j in range(6):
			var k := (j+1)%6
			var points := [rings[i][j],rings[i][k],rings[i+1][k],rings[i+1][j]]
			var middle: Vector3 = (points[0]+points[1]+points[2]+points[3])*.25
			var tint := "fold" if j==0 else ("edge" if j==3 else "ivory")
			_face(points,tint,Vector3(middle.x,middle.y-1.5,0))
	_face(rings[0],"coral",Vector3.FORWARD)
	_face(rings[-1],"coral",Vector3.BACK)
	# Layered lower paper belt follows the tapered nose, not a floating decal box.
	for sign in [-1,1]:
		for i in range(sections.size()-1):
			var a: Array = sections[i]; var b: Array = sections[i+1]
			_face([Vector3(sign*(a[1]+.012),.67,a[0]),Vector3(sign*(a[1]+.012),1.15,a[0]),Vector3(sign*(b[1]+.012),1.15,b[0]),Vector3(sign*(b[1]+.012),.67,b[0])],"coral",Vector3(sign,0,0))
		_box(Vector3(sign*1.285,1.19,0),Vector3(.022,.055,8.7),"edge")
		# Four inset windows, separated by two complete door panels.
		for z in [-3.95,-.92,.92,3.95]:
			_side_panel(sign,z,1.69,2.56,1.22,"dark",1.283)
			_side_panel(sign,z,1.76,2.49,1.08,"glass",1.291)
			_face([Vector3(sign*1.296,1.78,z-.49),Vector3(sign*1.296,2.47,z+.49),Vector3(sign*1.296,2.47,z-.49)],"glass_light",Vector3(sign,0,0))
		for z in [-2.56,2.56]:
			_side_panel(sign,z,.78,2.65,.97,"fold",1.282)
			_side_panel(sign,z,.84,2.60,.85,"edge",1.288)
			_side_panel(sign,z,1.69,2.45,.63,"glass",1.296)
			_box(Vector3(sign*1.299,1.44,z+.26),Vector3(.002,.055,.13),"gold")
			_box(Vector3(sign*1.297,.83,z),Vector3(.004,.035,.72),"coral_dark")
		# Lamination on the roof edge, restrained at actual metre scale.
		_box(Vector3(sign*.955,2.99,0),Vector3(.035,.07,8.4),"fold")
	for end in [-1,1]:
		var lower_z: float = end*5.935; var upper_z: float = end*5.46
		var outward := Vector3(0,.48,end*.88)
		_face([Vector3(-.89,1.805,lower_z),Vector3(.89,1.805,lower_z),Vector3(.78,2.765,upper_z),Vector3(-.78,2.765,upper_z)],"dark",outward)
		_face([Vector3(-.80,1.87,lower_z-end*.035),Vector3(.80,1.87,lower_z-end*.035),Vector3(.70,2.68,upper_z+end*.035),Vector3(-.70,2.68,upper_z+end*.035)],"glass",outward)
		_face([Vector3(-.79,1.88,lower_z-end*.04),Vector3(.69,2.69,upper_z+end*.03),Vector3(-.69,2.69,upper_z+end*.03)],"glass_light",outward)
		_box(Vector3(0,1.26,end*5.976),Vector3(1.82,.075,.006),"edge")
		for side in [-1,1]:
			_box(Vector3(side*.76,.99,end*5.978),Vector3(.23,.12,.004),"gold_light")
			_box(Vector3(side*.76,.96,end*5.973),Vector3(.31,.22,.006),"coral_dark")
	# Roof hatch / folded ventilation box, maximum Y remains below 3.28m.
	_box(Vector3(0,3.10,-.35),Vector3(1.35,.08,3.3),"fold")
	_box(Vector3(0,3.18,-.35),Vector3(1.14,.16,2.9),"dark")
	for z in [-1.45,-1.13,-.81,-.49,-.17,.15,.47,.79]:
		_box(Vector3(0,3.267,z),Vector3(.96,.018,.075),"teal")
	_box(Vector3(0,.46,0),Vector3(1.85,.28,10.0),"dark")
	for z in [-3.65,3.65]:
		_box(Vector3(0,.37,z),Vector3(2.16,.38,1.40),"teal")
		for side in [-1,1]: _wheel(Vector3(side*1.15,.34,z),.31,.12)
	var mesh := _mesh()
	_train_bounds = mesh.get_aabb()
	assert(TRAIN_LIMIT.grow(.001).encloses(_train_bounds), "Paper train exceeded frozen appearance envelope")
	var train := _node(parent,"PaperTransportTrain",mesh,"station","TR01_03","paper_transport_train")
	train.set_meta("clearance_role","actor_visual")
	train.set_meta("source_envelope",_box_dict(TRAIN_LIMIT))
	train_asset_report = {"mode":"procedural_fallback", "validated":true, "bounds":_box_dict(_train_bounds)}

func _try_build_generated_train(parent: Node3D) -> bool:
	if not FileAccess.file_exists(TRAIN_ASSET_SPEC): return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRAIN_ASSET_SPEC))
	if not value is Dictionary or str(value.get("state","pending")) != "ready": return false
	var spec: Dictionary = value
	var path: String = str(spec.get("runtime_path",""))
	if path.begins_with("game/"): path = "res://"+path.trim_prefix("game/")
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(spec.get("runtime_sha256","")):
		push_error("Train source absent or differs from measured runtime GLB: "+path)
		return false
	var source := load(path) as PackedScene
	if source == null: return false
	var train := source.instantiate() as Node3D
	if train == null: return false
	var points := PackedVector3Array()
	_train_vertices(train,Transform3D.IDENTITY,points)
	if points.is_empty():
		train.free()
		push_error("Prepared train has no measurable mesh vertices")
		return false
	var bounds := AABB(points[0],Vector3.ZERO)
	for point in points: bounds = bounds.expand(point)
	if not TRAIN_LIMIT.grow(.001).encloses(bounds):
		train.free()
		push_error("Prepared G1 train exceeds frozen appearance envelope: "+str(bounds))
		return false
	_train_bounds = bounds
	train.name = "PaperTransportTrain"
	_tag(train,"station",str(spec.get("asset_id","TRAIN_HERO")),"paper_transport_train","actor_visual")
	train.set_meta("source_envelope",_box_dict(TRAIN_LIMIT))
	parent.add_child(train)
	var adapter: RefCounted = TRAIN_MATERIALS.new()
	_train_materials(train,adapter)
	train_asset_report = {"mode":"canonical_g1", "validated":true, "asset_id":spec.get("asset_id","TRAIN_HERO"), "runtime_path":path, "runtime_sha256":spec.runtime_sha256, "source_sha256":spec.get("source_sha256",""), "measured_vertices":points.size(), "bounds":_box_dict(bounds), "fit":spec.get("fit",{}), "collision_added":false}
	return true

func _train_vertices(node: Node, parent_pose: Transform3D, points: PackedVector3Array) -> void:
	var pose := parent_pose
	if node is Node3D: pose = parent_pose*(node as Node3D).transform
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(i)
			for point in arrays[Mesh.ARRAY_VERTEX]: points.append(pose*point)
	for child in node.get_children(): _train_vertices(child,pose,points)

func _train_materials(node: Node, adapter: RefCounted) -> void:
	_tag(node,"station","TRAIN_HERO","paper_transport_train","actor_visual")
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(i)
			if original != null: node.set_surface_override_material(i,adapter.convert(original))
	for child in node.get_children(): _train_materials(child,adapter)

func _side_panel(sign: int, z: float, bottom: float, top: float, width: float, tint: String, x: float) -> void:
	var bevel := .07
	var points := [Vector3(sign*x,bottom,z-width/2+bevel),Vector3(sign*x,bottom,z+width/2-bevel),Vector3(sign*x,bottom+bevel,z+width/2),Vector3(sign*x,top-bevel,z+width/2),Vector3(sign*x,top,z+width/2-bevel),Vector3(sign*x,top,z-width/2+bevel),Vector3(sign*x,top-bevel,z-width/2),Vector3(sign*x,bottom+bevel,z-width/2)]
	_face(points,tint,Vector3(sign,0,0))

func _wheel(center: Vector3, radius: float, depth: float) -> void:
	var rings := []
	for side in [-1,1]:
		var ring := []
		for i in range(10):
			var angle := TAU*i/10.0
			ring.append(center+Vector3(side*depth*.5,sin(angle)*radius,cos(angle)*radius))
		rings.append(ring)
	_face(rings[0],"dark",Vector3.LEFT); _face(rings[1],"dark",Vector3.RIGHT)
	for i in range(10):
		var j := (i+1)%10
		_face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],"dark",rings[0][i]-center)

func _build_track(parent: Node3D, track: SpatialTrack) -> int:
	var scene := _scene(track)
	var parts := ceili(track.length/CHUNK_M)
	for part_index in range(parts):
		var start := part_index*CHUNK_M
		var finish := minf(track.length,start+CHUNK_M)
		var origin := track.pose((start+finish)*.5).origin
		var chunk := Node3D.new()
		chunk.name = track.id+"_PaperTransport_"+str(part_index)
		chunk.position = origin
		_tag(chunk,scene,"RT01_03",chunk.name)
		parent.add_child(chunk)
		_reset_mesh()
		var sleepers: Array[Transform3D] = []
		var fastenings: Array[Transform3D] = []
		var ribs: Array[Transform3D] = []
		var count := ceili((finish-start)/SAMPLE_M)
		for i in range(count):
			var s0 := start+i*SAMPLE_M
			var s1 := minf(finish,s0+SAMPLE_M)
			var p0 := track.pose(s0); var p1 := track.pose(s1)
			p0.origin -= origin; p1.origin -= origin
			var w0 := track.width_at(s0); var w1 := track.width_at(s1)
			# Real shallow slab recess, not a coplanar stripe; rails remain continuous.
			if absf(s1/16.0-roundf(s1/16.0))<.0001 and s1-s0>.10:
				var joint := track.pose(s1-.08); joint.origin -= origin
				var joint_width := track.width_at(s1-.08)
				_deck_sweep(p0,joint,w0,joint_width,-.16,"deck")
				_deck_sweep(joint,p1,joint_width,w1,-.22,"joint")
				_face([joint*Vector3(-joint_width,-.16,0),joint*Vector3(joint_width,-.16,0),joint*Vector3(joint_width,-.22,0),joint*Vector3(-joint_width,-.22,0)],"fold",-joint.basis.z)
				_face([p1*Vector3(-w1,-.16,0),p1*Vector3(w1,-.16,0),p1*Vector3(w1,-.22,0),p1*Vector3(-w1,-.22,0)],"fold",p1.basis.z)
			else:
				_deck_sweep(p0,p1,w0,w1,-.16,"deck")
		_build_profiled_rails(track,start,finish,origin)
		# Repeated sleepers are real shallow bevelled solids, phase-stable per track.
		var tie_s := ceilf(start/2.8)*2.8
		while tie_s<finish:
			var pose := track.pose(tie_s); pose.origin -= origin
			for lane in track.lanes():
				var w := minf(2.28,track.width_at(tie_s)*1.88)
				sleepers.append(pose.translated_local(Vector3(lane*4.4,-.075,0)).scaled_local(Vector3(w,.17,.42)))
				fastenings.append(pose.translated_local(Vector3(lane*4.4,0,0)))
			tie_s+=2.8
		var rib_s := ceilf(start/12.0)*12.0
		while rib_s<finish:
			var pose := track.pose(rib_s); pose.origin -= origin
			var width := track.width_at(rib_s)*2.0
			# Shallow fold braces stay entirely below the contact bed, not giant piers.
			if track.kind not in ["grind","wall","inverted"] and track.enclosure!="tunnel":
				ribs.append(pose.translated_local(Vector3(0,-.72,0)).scaled_local(Vector3(width,1.7,.70)))
			rib_s+=12.0
		_node(chunk,"SweptLaminatedTrack",_mesh(),scene,"RT01_03",chunk.name+":sweep",850.0)
		_reset_mesh()
		_bevel_unit("tie")
		_multimesh(chunk,"PaperSleepers",_mesh(),sleepers,scene,"RT01_03",chunk.name+":sleepers",620.0)
		_reset_mesh()
		_rail_seats(.26 if track.kind=="grind" else .72)
		_multimesh(chunk,"RailSeats",_mesh(),fastenings,scene,"RT01_03",chunk.name+":contact_seats",360.0)
		_build_track_edges(chunk,track,start,finish,origin,scene)
		_reset_mesh()
		# Keep the transverse beam below the swept train envelope on banked curves.
		# Thin outer hangers join it to the deck without a full-width solid at -0.72m.
		var rib := [Vector2(-.5,-.9),Vector2(.5,-.9),Vector2(.33,-1.26),Vector2(.12,-1.9),Vector2(-.12,-1.9),Vector2(-.33,-1.26)]
		_extrude(rib,-.5,.5,"ivory")
		for side in [-1,1]:
			_box(Vector3(side*.4875,-.45,0),Vector3(.025,.90,.82),"ivory")
		_multimesh(chunk,"FoldedBridgeRibs",_mesh(),ribs,scene,"RT01_03",chunk.name+":underdeck",750.0)
	return parts

func _deck_sweep(a: Transform3D,b: Transform3D,wa: float,wb: float,top: float,tint: String) -> void:
	var pa := [Vector2(-wa,top),Vector2(wa,top),Vector2(wa,-.48),Vector2(wa*.92,-.57),Vector2(wa*.75,-1.0),Vector2(-wa*.75,-1.0),Vector2(-wa*.92,-.57),Vector2(-wa,-.48)]
	var pb := [Vector2(-wb,top),Vector2(wb,top),Vector2(wb,-.48),Vector2(wb*.92,-.57),Vector2(wb*.75,-1.0),Vector2(-wb*.75,-1.0),Vector2(-wb*.92,-.57),Vector2(-wb,-.48)]
	_sweep(a,b,pa,pb,[tint,"ivory","edge","fold","teal","fold","edge","ivory"])

func _rail_profile(x: float) -> Array:
	# A bevelled head, narrow web and broad foot fit the unchanged contact height.
	return [Vector2(x-.11,-.055),Vector2(x+.11,-.055),Vector2(x+.11,-.012),Vector2(x+.034,.015),Vector2(x+.034,.095),Vector2(x+.074,.112),Vector2(x+.063,.16),Vector2(x-.063,.16),Vector2(x-.074,.112),Vector2(x-.034,.095),Vector2(x-.034,.015),Vector2(x-.11,-.012)]

func _build_profiled_rails(track: SpatialTrack,start: float,finish: float,origin: Vector3) -> void:
	var at := start
	while at<finish-.00001:
		# Straight runs need no 1.6m duplication of the full twelve-edge profile.
		# Sample quarter points at both outer rail positions; bent/rolled spans
		# fall back to the original 1.6m resolution rather than moving the route.
		var span := minf(6.4,finish-at)
		var a := track.pose(at)
		while span>SAMPLE_M+.00001:
			var candidate := track.pose(at+span)
			var acceptable := a.basis.y.angle_to(candidate.basis.y)<deg_to_rad(2.0) and a.basis.z.angle_to(candidate.basis.z)<deg_to_rad(2.0)
			for fraction in [.25,.5,.75]:
				var actual := track.pose(at+span*fraction)
				for x in [-5.4,0.0,5.4]:
					var point := Vector3(x,0,0)
					if (actual*point).distance_to((a*point).lerp(candidate*point,fraction))>.025:acceptable=false
			if acceptable:break
			span=maxf(SAMPLE_M,span*.5)
		var b := track.pose(minf(finish,at+span))
		a.origin-=origin;b.origin-=origin
		for lane in track.lanes():
			var gauge := .26 if track.kind=="grind" else .72
			for side in [-1,1]:
				var profile := _rail_profile(lane*4.4+side*gauge)
				_sweep(a,b,profile,profile,["rail_side","rail_side","rail_side","rail_head","rail_head","rail_head","rail_head","rail_side","rail_side","rail_side","rail_side","rail_side"])
		at+=span

func _rail_seats(gauge: float) -> void:
	for side in [-1,1]:
		# Shaped spring seats flank the foot; this belongs to the contact assembly.
		for outer in [-1,1]:
			var ring := [Vector2(.10,-.07),Vector2(.17,-.07),Vector2(.17,-.025),Vector2(.13,.005),Vector2(.10,-.015)]
			for i in range(ring.size()): ring[i].x = ring[i].x*outer+side*gauge
			_extrude(ring,-.17,.17,"rail_side")

func _prepare_edge_clearance(tracks: Dictionary) -> void:
	# Decoration placement uses every frozen route, including inactive neighbours.
	# This never changes the route, vehicle shape, collision mask or audit tags.
	edge_corridors.clear(); edge_corridor_count=0
	edge_kept_spans=0; edge_omitted_spans=0
	for key in tracks:
		var track: SpatialTrack = tracks[key]
		var count := ceili(track.length/4.0)
		for i in range(count+1):
			var at := minf(track.length,float(i)*4.0)
			var pose := track.pose(at)
			# Full legal centre corridor plus the unchanged 1.30m vehicle half-width.
			# 8.2m half-length covers 6m train overhang and sample interpolation.
			var half_width := maxf(track.width_at(maxf(0,at-6)),track.width_at(minf(track.length,at+6)))+1.35
			var lo := Vector3(-half_width,-.12,-8.2)
			var hi := Vector3(half_width,4.7,8.2)
			var bounds := AABB(pose*lo,Vector3.ZERO)
			for x in [lo.x,hi.x]:
				for y in [lo.y,hi.y]:
					for z in [lo.z,hi.z]: bounds=bounds.expand(pose*Vector3(x,y,z))
			var row := {"inverse":pose.affine_inverse(),"lo":lo,"hi":hi,"bounds":bounds,"track":str(key),"s":at,"id":edge_corridor_count}
			edge_corridor_count+=1
			var first := Vector3i((bounds.position/EDGE_GRID_M).floor())
			var last := Vector3i((bounds.end/EDGE_GRID_M).floor())
			for x in range(first.x,last.x+1):
				for y in range(first.y,last.y+1):
					for z in range(first.z,last.z+1):
						var cell := Vector3i(x,y,z)
						if not edge_corridors.has(cell):edge_corridors[cell]=[]
						edge_corridors[cell].append(row)

func _edge_span_clear(a: Transform3D,b: Transform3D,x0: float,x1: float,half_width: float) -> bool:
	# Test the complete swept cross-section, not a centre point. Testing the
	# neighbour's three axes conservatively over-removes corners; it cannot
	# admit a span whose convex hull overlaps the protected oriented box.
	var points := PackedVector3Array()
	for endpoint in [[a,x0],[b,x1]]:
		var pose: Transform3D=endpoint[0]
		for x in [-half_width,half_width]:
			for y in [-.92,-.42]:points.append(pose*Vector3(float(endpoint[1])+x,y,0))
	var bounds:=AABB(points[0],Vector3.ZERO)
	for point in points:bounds=bounds.expand(point)
	bounds=bounds.grow(.015)
	var first:=Vector3i((bounds.position/EDGE_GRID_M).floor())
	var last:=Vector3i((bounds.end/EDGE_GRID_M).floor())
	var checked:={}
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			for z in range(first.z,last.z+1):
				for row in edge_corridors.get(Vector3i(x,y,z),[]):
					if checked.has(row.id):continue
					checked[row.id]=true
					if not bounds.intersects(row.bounds):continue
					var low:=Vector3(INF,INF,INF);var high:=-low
					for point in points:
						var local:Vector3=row.inverse*point
						low=low.min(local);high=high.max(local)
					if high.x<row.lo.x or low.x>row.hi.x or high.y<row.lo.y or low.y>row.hi.y or high.z<row.lo.z or low.z>row.hi.z:continue
					return false
	return true

func _closed_edge_sweep(a: Transform3D,b: Transform3D,ra: Array,rb: Array,tint: String) -> void:
	_sweep(a,b,ra,rb,[tint])
	var front:=[];var back:=[]
	for point in ra:front.append(a*Vector3(point.x,point.y,0))
	for point in rb:back.append(b*Vector3(point.x,point.y,0))
	_face(front,tint,a.basis.z);_face(back,tint,-b.basis.z)

func _build_track_edges(chunk: Node3D,track: SpatialTrack,start: float,finish: float,origin: Vector3,scene: String) -> void:
	_reset_mesh()
	var count := ceili((finish-start)/SAMPLE_M)
	# A 1.2m-half-width grind is narrower than the 1.3m train half-width and
	# receives airborne catches along its length. Leave its sides open instead
	# of fitting fascia to one recorded landing. Profiled contact rails remain.
	if track.kind=="grind":
		edge_omitted_spans+=count*2
		return
	for i in range(count):
		var s0:=start+i*SAMPLE_M;var s1:=minf(finish,s0+SAMPLE_M)
		var world0:=track.pose(s0);var world1:=track.pose(s1)
		var p0:=world0;var p1:=world1;p0.origin-=origin;p1.origin-=origin
		var w0:=track.width_at(s0);var w1:=track.width_at(s1)
		if minf(w0,w1)<=.85:continue
		var wide:=minf(w0,w1)>5.0
		var half_width:=.45 if wide else .22
		for side in [-1,1]:
			var x0:float=side*(w0+.16);var x1:float=side*(w1+.16)
			if not _edge_span_clear(world0,world1,x0,x1,half_width):
				edge_omitted_spans+=1
				continue
			edge_kept_spans+=1
			# The old 0.81m parapet was inside 12m turning/merge envelopes.
			# This closed folded edge joins the deck underside (top -0.46m),
			# while the cyan lamination stays below the -0.16m contact bed.
			var shape:=[Vector2(-half_width,-.66),Vector2(half_width,-.66),Vector2(half_width,-.56),Vector2(half_width*.86,-.46),Vector2(-half_width*.86,-.46),Vector2(-half_width,-.56)]
			var a:=[];var b:=[]
			for point in shape:
				a.append(Vector2(point.x+x0,point.y));b.append(Vector2(point.x+x1,point.y))
			_closed_edge_sweep(p0,p1,a,b,"ivory")
			var lip:=minf(.16,half_width*.6)
			_closed_edge_sweep(p0,p1,[Vector2(x0-lip,-.46),Vector2(x0+lip,-.46),Vector2(x0+lip,-.42),Vector2(x0-lip,-.42)],[Vector2(x1-lip,-.46),Vector2(x1+lip,-.46),Vector2(x1+lip,-.42),Vector2(x1-lip,-.42)],"cyan")
	if vertices.is_empty():return
	var edge:=_node(chunk,"OpenPaperParapet",_mesh(),scene,"RT04_EDGE",chunk.name+":side_detail",750.0)
	if edge!=null:
		edge.set_meta("clearance_role","transport_decoration")
		edge.set_meta("edge_form","closed below-bed folded fascia with true closed caps at merge gaps")

func _sweep(a: Transform3D, b: Transform3D, ra: Array, rb: Array, tints: Array) -> void:
	var area := 0.0
	for j in range(ra.size()):
		var next := (j+1)%ra.size()
		area += ra[j].x*ra[next].y-ra[next].x*ra[j].y
	for j in range(ra.size()):
		var k := (j+1)%ra.size()
		var points := [a*Vector3(ra[j].x,ra[j].y,0),a*Vector3(ra[k].x,ra[k].y,0),b*Vector3(rb[k].x,rb[k].y,0),b*Vector3(rb[j].x,rb[j].y,0)]
		# Edge normal also handles the rail's re-entrant foot/head faces.
		var delta: Vector2 = ((ra[k]-ra[j])+(rb[k]-rb[j]))*.5
		var outward: Vector3 = ((a.basis.x+b.basis.x)*delta.y-(a.basis.y+b.basis.y)*delta.x)*signf(area)
		_face(points,str(tints[j%tints.size()]),outward)

func _strip(a: Transform3D,b: Transform3D,x0: float,x1: float,width: float,bottom: float,top: float,tint: String) -> void:
	var ra := [Vector2(x0-width/2,bottom),Vector2(x0+width/2,bottom),Vector2(x0+width/2,top),Vector2(x0-width/2,top)]
	var rb := [Vector2(x1-width/2,bottom),Vector2(x1+width/2,bottom),Vector2(x1+width/2,top),Vector2(x1-width/2,top)]
	_sweep(a,b,ra,rb,[tint,tint,tint,tint])

func _extrude(ring: Array, front: float, back: float, tint: String) -> void:
	var a := []; var b := []
	for p in ring:
		a.append(Vector3(p.x,p.y,front)); b.append(Vector3(p.x,p.y,back))
	_face(a,tint,Vector3.FORWARD); _face(b,tint,Vector3.BACK)
	for i in range(ring.size()):
		var j := (i+1)%ring.size()
		var center: Vector3 = (a[i]+a[j]+b[j]+b[i])*.25
		_face([a[i],a[j],b[j],b[i]],tint,Vector3(center.x,center.y+.3,0))

func _bevel_unit(tint: String) -> void:
	_extrude([Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.25),Vector2(.40,.5),Vector2(-.40,.5),Vector2(-.5,.25)],-.5,.5,tint)

func _gate_mesh() -> ArrayMesh:
	_reset_mesh()
	# Entire 3 x 5 x 2m blocking envelope stays visually sealed. No open portal.
	_box(Vector3(0,2.5,0),Vector3(3,5,1.60),"coral_dark")
	for sign in [-1,1]:
		var z: float = sign*.82
		var boundary := [Vector3(-1.5,0,z),Vector3(1.5,0,z),Vector3(1.5,5,z),Vector3(-1.5,5,z)]
		var ridge := Vector3(.12,2.7,sign*.98)
		for i in range(4):
			_face([boundary[i],boundary[(i+1)%4],ridge],"gold_light" if i%2==0 else "gold",Vector3(0,0,sign))
		# Layered border and crossed coral seal express a solid blocked lane.
		for side in [-1,1]:
			_box(Vector3(side*1.39,2.5,sign*.94),Vector3(.20,4.72,.08),"edge")
		for y in [.12,4.88]: _box(Vector3(0,y,sign*.94),Vector3(2.78,.20,.08),"edge")
		_face([Vector3(-1.15,2.20,sign*.99),Vector3(1.15,2.20,sign*.99),Vector3(1.15,2.63,sign*.99),Vector3(-1.15,2.63,sign*.99)],"coral",Vector3(0,0,sign))
		_face([Vector3(-.85,3.24,sign*.99),Vector3(0,2.72,sign*.99),Vector3(.85,3.24,sign*.99),Vector3(.85,3.52,sign*.99),Vector3(0,3.0,sign*.99),Vector3(-.85,3.52,sign*.99)],"coral",Vector3(0,0,sign))
	return _mesh()

func _box_dict(box: AABB) -> Dictionary:
	return {"min":[box.position.x,box.position.y,box.position.z],"max":[box.end.x,box.end.y,box.end.z]}
