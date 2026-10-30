extends RefCounted
## A single continuous world-space terrain field and conservative sampled exclusion index.
const STEP := 64.0
const CELL := 64.0
var terrain_samples: Array[Vector3] = []
var envelopes: Dictionary = {}
var heights: Dictionary = {}
var bounds := AABB()
var envelope_count := 0
var camera_count := 0
var flight_count := 0
var region_for_track: Dictionary = {}
var scene_for_track: Dictionary = {}
var track_samples: Dictionary = {}

func configure(route: Node3D, program: Dictionary) -> void:
	for region: Dictionary in program.regions:
		for id: String in region.tracks:
			region_for_track[id] = region.id
			scene_for_track[id] = program.track_scene_overrides.get(id, region.catalog_scene_ids[0])
	var first := true
	for id: String in route.tracks:
		var track: SpatialTrack = route.tracks[id]
		track_samples[id] = []
		var divisions := ceili(track.length / 5.0)
		for i in divisions + 1:
			var s := track.length * float(i) / float(divisions)
			var p := track.pose(s)
			if first: bounds = AABB(p.origin, Vector3.ONE); first = false
			else: bounds = bounds.expand(p.origin)
			# Full local up preserves wall/inverted envelopes as well as upright tracks.
			_insert_obb(p.translated_local(Vector3(0,3.0,0)),Vector3(track.width_at(s)*2.0+4.0,10.0,20.0))
			track_samples[id].append({"s": s, "p": p.origin})
			if i % 4 == 0 or i == divisions: terrain_samples.append(p.origin)
	for row: Array in program.camera_points:
		var p := Vector3(float(row[0]), float(row[1]), float(row[2]))
		_insert(AABB(p-Vector3.ONE*1.5, Vector3.ONE*3.0)); camera_count += 1
	for row: Array in program.flight_points:
		var p := Vector3(float(row[0]), float(row[1]), float(row[2]))
		_insert(AABB(p-Vector3(10, 6, 10), Vector3(20, 12, 20))); flight_count += 1
	# Declared candidate transitions retain a broad connecting void, without claiming reachability.
	for edge: Dictionary in program.interfaces:
		if edge.relation != "declared_air_connection": continue
		var source: SpatialTrack = route.tracks[edge.source]
		var target: SpatialTrack = route.tracks[edge.target]
		var sw: Array = edge.source_window_s_m; var tw: Array = edge.target_capture_s_m
		for fraction in [0.0, 0.5, 1.0]:
			var a: Vector3 = source.pose(lerpf(float(sw[0]), minf(float(sw[1]), source.length), fraction)).origin
			var b: Vector3 = target.pose(lerpf(float(tw[0]), minf(float(tw[1]), target.length), fraction)).origin
			var pieces := maxi(1, ceili(a.distance_to(b)/16.0))
			for i in pieces + 1:
				var p := a.lerp(b, float(i)/float(pieces))
				_insert(AABB(p-Vector3(12, 8, 12), Vector3(24, 16, 24))); flight_count += 1
	bounds = bounds.grow(512.0)

func _cell(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x/CELL), floori(point.y/CELL), floori(point.z/CELL))

func _insert(box: AABB) -> void:
	_insert_obb(Transform3D(Basis.IDENTITY,box.get_center()),box.size)

func _insert_obb(p: Transform3D, size: Vector3) -> void:
	var box: AABB = p*AABB(-size*0.5,size)
	if not _orthogonal(p.basis):
		_insert(box); return
	var entry := {"bounds":box,"pose":p,"size":size}
	var lo := _cell(box.position); var hi := _cell(box.end)
	for x in range(lo.x, hi.x+1):
		for y in range(lo.y, hi.y+1):
			for z in range(lo.z, hi.z+1):
				var key := Vector3i(x,y,z)
				if not envelopes.has(key): envelopes[key] = []
				envelopes[key].append(entry)
	envelope_count += 1

func can_place(box: AABB, margin: float) -> bool:
	return can_place_obb(Transform3D(Basis.IDENTITY,box.get_center()),box.size,margin)

func can_place_obb(p: Transform3D, size: Vector3, margin: float) -> bool:
	# Keep real boxes through the narrow phase. Broad world AABBs only select cells.
	if not _orthogonal(p.basis):
		return can_place(p*AABB(-size.abs()*0.5,size.abs()),margin)
	var scale := p.basis.get_scale().abs()
	var unit := p.basis.orthonormalized()
	var inflated := size.abs()*scale+Vector3.ONE*(2.0*maxf(0.0,margin))
	var query_pose := Transform3D(unit,p.origin)
	var query: AABB = query_pose*AABB(-inflated*0.5,inflated)
	var broad := query.grow(0.00001)
	var lo := _cell(broad.position); var hi := _cell(broad.end)
	for x in range(lo.x, hi.x+1):
		for y in range(lo.y, hi.y+1):
			for z in range(lo.z, hi.z+1):
				for envelope: Dictionary in envelopes.get(Vector3i(x,y,z), []):
					if broad.intersects(envelope.bounds) and boxes_intersect(query_pose,inflated,envelope.pose,envelope.size): return false
	return true

static func _orthogonal(basis: Basis) -> bool:
	if minf(basis.x.length_squared(),minf(basis.y.length_squared(),basis.z.length_squared()))<0.00000001: return false
	var x := basis.x.normalized(); var y := basis.y.normalized(); var z := basis.z.normalized()
	return maxf(absf(x.dot(y)),maxf(absf(x.dot(z)),absf(y.dot(z))))<0.00001

static func boxes_intersect(a: Transform3D, a_size: Vector3, b: Transform3D, b_size: Vector3) -> bool:
	# OBB SAT: 3 face normals for each box plus the 9 edge cross products.
	# Equality and tiny gaps remain blocked, preserving conservative boundary behavior.
	var aa: Array[Vector3] = [a.basis.x.normalized(),a.basis.y.normalized(),a.basis.z.normalized()]
	var ba: Array[Vector3] = [b.basis.x.normalized(),b.basis.y.normalized(),b.basis.z.normalized()]
	var ah := a_size.abs()*a.basis.get_scale().abs()*0.5
	var bh := b_size.abs()*b.basis.get_scale().abs()*0.5
	var axes: Array[Vector3] = []; axes.append_array(aa); axes.append_array(ba)
	for x: Vector3 in aa:
		for y: Vector3 in ba:
			var axis := x.cross(y)
			if axis.length_squared()>0.0000000001: axes.append(axis.normalized())
	var delta := b.origin-a.origin
	for axis: Vector3 in axes:
		var ar := ah.x*absf(axis.dot(aa[0]))+ah.y*absf(axis.dot(aa[1]))+ah.z*absf(axis.dot(aa[2]))
		var br := bh.x*absf(axis.dot(ba[0]))+bh.y*absf(axis.dot(ba[1]))+bh.z*absf(axis.dot(ba[2]))
		if absf(delta.dot(axis))>ar+br+0.00001: return false
	return true

func _height(key: Vector2i) -> float:
	if heights.has(key): return float(heights[key])
	var point := Vector2(key)*STEP
	var y := 18.0
	for sample: Vector3 in terrain_samples:
		var distance := point.distance_to(Vector2(sample.x, sample.z))
		y = minf(y, sample.y-29.0 + maxf(0.0, distance-90.0)*0.12)
	heights[key] = y
	return y

func height_at(point: Vector3) -> float:
	var x := floori(point.x/STEP); var z := floori(point.z/STEP)
	var fx := point.x/STEP-float(x); var fz := point.z/STEP-float(z)
	var a := _height(Vector2i(x,z)); var b := _height(Vector2i(x+1,z))
	var c := _height(Vector2i(x+1,z+1)); var d := _height(Vector2i(x,z+1))
	# Match the exact two terrain triangles, rather than a different bilinear surface.
	return a+fx*(b-a)+fz*(c-b) if fx>=fz else a+fx*(c-d)+fz*(d-a)

func nearest_track(point: Vector3) -> String:
	var nearest := "station_start"; var best := INF
	for id: String in track_samples:
		var samples: Array = track_samples[id]
		for i in range(0, samples.size(), 4):
			var candidate: Vector3 = samples[i].p
			var distance := Vector2(point.x,point.z).distance_squared_to(Vector2(candidate.x,candidate.z))
			if distance < best: best = distance; nearest = id
	return nearest

func emit_ground(ctx: RefCounted) -> Dictionary:
	var xmin := floori(bounds.position.x/(STEP*4)); var xmax := ceili(bounds.end.x/(STEP*4))
	var zmin := floori(bounds.position.z/(STEP*4)); var zmax := ceili(bounds.end.z/(STEP*4))
	var tiles := 0
	for x in range(xmin,xmax):
		for z in range(zmin,zmax):
			var center := Vector3((float(x)+0.5)*STEP*4,0,(float(z)+0.5)*STEP*4)
			var track_id := nearest_track(center)
			ctx.use_scene(str(scene_for_track[track_id]))
			var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in 4:
				for j in 4:
					var key := Vector2i(x*4+i,z*4+j)
					var a := Vector3(key.x*STEP,_height(key),key.y*STEP)
					var b := Vector3((key.x+1)*STEP,_height(key+Vector2i.RIGHT),key.y*STEP)
					var c := Vector3((key.x+1)*STEP,_height(key+Vector2i.ONE),(key.y+1)*STEP)
					var d := Vector3(key.x*STEP,_height(key+Vector2i.DOWN),(key.y+1)*STEP)
					for vertex: Vector3 in [a,c,b,a,d,c]: st.add_vertex(vertex)
			st.generate_normals(); ctx._mesh(st.commit(),Transform3D.IDENTITY,"far2","shared_terrain_"+str(x)+"_"+str(z)); tiles += 1
	var clearance := INF
	for id: String in track_samples:
		for row: Dictionary in track_samples[id]:
			var p: Vector3 = row.p; clearance = minf(clearance,p.y-height_at(p))
	return {"tiles":tiles,"sample_grid_m":STEP,"shared_field":true,"minimum_sampled_ground_below_rail_m":clearance,"camera_envelopes":camera_count,"flight_envelopes":flight_count,"track_sample_m":5.0,"box_narrow_phase":"15-axis OBB SAT after spatial-cell/world-AABB broad phase; envelope sizes unchanged","limits":"Conservative static sampled exclusion; candidate corridors are not dynamic reachability or all-input clearance proof."}
