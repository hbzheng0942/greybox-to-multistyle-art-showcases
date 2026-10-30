extends Node3D
signal diagnostic_event(event: Dictionary)
## A01-only camera aid. Exact art triangles live in an independent query world,
## never in the museum physics world. This changes camera placement only.
var game
var query_world: World3D
# Keep exact triangles for visibility/picking; swept camera volumes use a
# conservative compound convex envelope of each actual visible mesh.
var motion_world: World3D
var motion_shape_cache: Dictionary = {}
var dynamic_motion_shapes: Array = []
var visitor_exact_rids: Array[RID] = []
var motion_shape_stats := {"method":"per_mesh_26_plane_conservative_hull", "cache_hits":0, "unique_meshes":0, "hull_vertices":0, "padding_m":0.001,"blend_shape_meshes":0,"local_transform_updates":0,"visitor_ray_policy":"conservative_all_normalized_blend_targets_and_current_visual_root"}
const HULL_DIRECTIONS = [Vector3(1,0,0),Vector3(0,1,0),Vector3(0,0,1),Vector3(1,1,0),Vector3(1,-1,0),Vector3(1,0,1),Vector3(1,0,-1),Vector3(0,1,1),Vector3(0,1,-1),Vector3(1,1,1),Vector3(1,1,-1),Vector3(1,-1,1),Vector3(-1,1,1)]
var bodies: Array = []
var shapes: Array = []
var stats := {"frames": 0, "adjusted_frames": 0, "max_retraction_m": 0.0, "invalid_focus_frames": 0, "focus_surface_overlap_frames": 0}
var sphere := SphereShape3D.new()
var previous_focus := Vector3.INF
var previous_yaw := 0.0
var previous_pitch := 0.0
var distance_state := 4.6
var enabled := true
var anomaly_events: Array = []
var body_sync_stats := {"updates":0,"unchanged_skips":0}
var query_stats := {"lookahead_logical_sweeps":0,"lookahead_reused_sweeps":0,"lookahead_casts":0,"cast_motion_calls":0}

func setup(target) -> void:
	game = target
	name = "A01CameraVisualGuard"
	process_physics_priority = 100
	sphere.radius = 0.08 # Circumscribes the actual 66-degree, 16:9, .05 m near plane.
	query_world = World3D.new()
	PhysicsServer3D.space_set_active(query_world.space, true)
	motion_world = World3D.new()
	PhysicsServer3D.space_set_active(motion_world.space, true)
	for id in game.visual_catalog.entries:
		var entry: Dictionary = game.visual_catalog.entries[id]
		# Native layer-1 geometry already participates in the shared camera sweep.
		# These solid-looking visual objects do not: skeleton layer 2, rope visual only.
		if entry.role not in ["skeleton_segment", "interactable_prop", "visitor_legs", "visitor_torso", "visitor_head", "barrier_rope"]:
			continue
		var faces := PackedVector3Array()
		var owner: Node3D = entry.owner
		var art: Node3D = entry.artwork if entry.artwork != null else entry.greybox
		var meshes: Array = art.find_children("*", "MeshInstance3D", true, false)
		for mesh: MeshInstance3D in meshes:
			if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
			var relative := owner.global_transform.affine_inverse() * mesh.global_transform
			for point in mesh.mesh.get_faces():
				faces.append(relative * point)
		if faces.size()<3:continue # Do not create phantom queries for hidden/empty art.
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		shapes.append(shape)
		var rid := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(rid, query_world.space)
		PhysicsServer3D.body_set_collision_layer(rid, 2 if entry.role == "barrier_rope" else 1)
		PhysicsServer3D.body_set_collision_mask(rid, 0)
		PhysicsServer3D.body_add_shape(rid, shape.get_rid())
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, owner.global_transform)
		var bounds := AABB(faces[0],Vector3.ZERO)
		for p in faces: bounds = bounds.expand(p)
		bodies.append({"rid": rid, "owner": owner, "role":entry.role, "bounds":bounds, "faces":faces, "id":id, "last_synced_transform":owner.global_transform, "motion_rid":create_motion_body(owner, entry.role, meshes)})
		if str(entry.role).begins_with("visitor_"):visitor_exact_rids.append(rid)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not game.is_physics_processing():
		return
	if not enabled: return
	if not game.shot.is_empty() and not game.cam_follow:
		return
	sync_bodies()
	var focus: Vector3 = game.cam_target.global_position
	var desired: Vector3 = game.cam.global_position
	var motion := desired - focus
	if motion.length() < 0.01:
		return
	var viewport_size: Vector2 = game.cam.get_viewport().get_visible_rect().size
	var half_height: float = tan(deg_to_rad(game.cam.fov * .5)) * game.cam.near
	var near_radius := maxf(.08, Vector2(half_height * viewport_size.x / viewport_size.y,half_height).length() + .01)
	var reset := not previous_focus.is_finite() or previous_focus.distance_to(focus) > 1.0
	var angular_speed := 0.0 if reset else clampf(angle_difference(previous_yaw, game.yaw) / delta, -3.0, 3.0)
	var pitch_speed := 0.0 if reset else clampf((game.pitch - previous_pitch) / delta, -1.5, 1.5)
	if reset: distance_state = motion.length()
	var target_distance: float = game.cam_distance
	var closest_bone:=_closest_inspection_bone_distance()
	target_distance = minf(target_distance, lerpf(1.4, game.cam_distance, smoothstep(.8,3.5,closest_bone)))
	# Look ahead along measured native motion and camera input. Begin retracting
	# before an exhibit/jamb enters the boom, rather than snapping on contact.
	var lookahead_seen: Array = []
	for ahead in [0.0, 0.10, 0.20, 0.30, 0.45, 0.60]:
		var future_focus: Vector3 = game._camera_safe_position(focus, focus + Vector3(game.dog.velocity.x, 0, game.dog.velocity.z) * ahead)
		var yaw: float = game.yaw + angular_speed * ahead
		var pitch: float = clampf(game.pitch + pitch_speed * ahead, -.12, 1.05)
		var direction := Vector3(sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch))
		var end: Vector3 = game._camera_safe_position(future_focus, future_focus + direction * game.cam_distance)
		var future_motion := end - future_focus
		target_distance = minf(target_distance, maxf(1.1,future_motion.length()))
		query_stats.lookahead_logical_sweeps += 2
		if not _lookahead_query_is_new(lookahead_seen, future_focus, future_motion):
			query_stats.lookahead_reused_sweeps += 2
			continue
		var casts_before: int = query_stats.cast_motion_calls
		for layer in [1, 2]:
			var safe := safe_distance(future_focus, future_motion, layer, .30 if layer == 1 else near_radius)
			if safe >= 1.1:
				target_distance = minf(target_distance, safe)
		query_stats.lookahead_casts += query_stats.cast_motion_calls - casts_before
	distance_state = move_toward(distance_state, target_distance, delta * (6.0 if target_distance < distance_state else 2.5))
	var corrected := focus + motion.normalized() * minf(distance_state, motion.length())
	var available := safe_distance(focus, corrected - focus, 3, near_radius)
	stats.frames += 1
	sphere.radius = near_radius
	var origin_query := PhysicsShapeQueryParameters3D.new()
	origin_query.shape = sphere
	origin_query.transform = Transform3D(Basis.IDENTITY,focus)
	origin_query.collision_mask = 3
	var overlaps := query_world.direct_space_state.intersect_shape(origin_query,8)
	if not overlaps.is_empty(): stats.focus_surface_overlap_frames += 1
	previous_focus = focus
	previous_yaw = game.yaw
	previous_pitch = game.pitch
	if available < .08:
		stats.invalid_focus_frames += 1
		record_anomaly(focus,desired,desired,near_radius,available,overlaps,true)
		return
	corrected = focus + (corrected - focus).normalized() * minf(available, corrected.distance_to(focus))
	# Keep shared layer-1 protection authoritative after the visual-only sweep.
	corrected = game._camera_safe_position(focus, corrected)
	if corrected.distance_to(desired) > .001: stats.adjusted_frames += 1
	stats.max_retraction_m = maxf(stats.max_retraction_m, corrected.distance_to(desired))
	game.cam.global_position = corrected
	game.cam.look_at(focus, Vector3.UP)
	if not overlaps.is_empty(): record_anomaly(focus,desired,corrected,near_radius,available,overlaps,false)

func _closest_inspection_bone_distance()->float:
	var closest_bone := INF
	for item in bodies:
		if item.role != "skeleton_segment" or item.owner==game.held: continue
		# A carried bone is always close to the dog. Do not force a 1.4m
		# inspection preference while carrying it. All query bodies and actual
		# ray/sweep/endpoint protection remain fully present.
		# A gradual close-inspection distance avoids driving a long camera boom
		# through the skeleton before its conservative visual sweep can react.
		var bounds: AABB = item.bounds
		var box := AABB(item.owner.global_transform * bounds.position,Vector3.ZERO)
		for x in [0,1]:
			for y in [0,1]:
				for z in [0,1]: box = box.expand(item.owner.global_transform * (bounds.position + bounds.size * Vector3(x,y,z)))
		var dx := maxf(maxf(box.position.x - game.dog.global_position.x, game.dog.global_position.x - box.end.x),0)
		var dz := maxf(maxf(box.position.z - game.dog.global_position.z, game.dog.global_position.z - box.end.z),0)
		closest_bone = minf(closest_bone, Vector2(dx,dz).length())
	return closest_bone

func _lookahead_query_is_new(seen: Array, focus: Vector3, motion: Vector3) -> bool:
	# Local to one physics callback; no world update occurs between these sweeps.
	# Exact equality only. Any tiny focus/motion difference retains its own query.
	for pair in seen:
		if pair.focus == focus and pair.motion == motion: return false
	seen.append({"focus":focus,"motion":motion})
	return true

func record_anomaly(focus: Vector3, before: Vector3, after: Vector3, radius: float, available: float, overlaps: Array, invalid: bool) -> void:
	# Bounded diagnostic records only: no exclusion, filtering or camera behavior change.
	if anomaly_events.size() >= 5: return
	var owners: Array = []
	for hit in overlaps:
		for item in bodies:
			if item.rid == hit.rid:
				owners.append({"id":item.id,"role":item.role,"world_transform":str(item.owner.global_transform),"local_visual_bounds":str(item.bounds)})
	var event := {"index":anomaly_events.size()+1,"physics_frame":Engine.get_physics_frames(),"guard_frame":stats.frames,"context":game.get_meta("a01_verification_context",{"phase":"live_or_bootstrap"}),"dog_transform":str(game.dog.global_transform),"focus":str(focus),"camera_before":str(before),"camera_after":str(after),"camera_transform_after":str(game.cam.global_transform),"query_radius_m":radius,"available_distance_m":available,"surface_overlap_owners":owners,"invalid_candidate":invalid,"bones_broken":game._broken_count()}
	anomaly_events.append(event)
	diagnostic_event.emit(event)

func sync_bodies() -> void:
	for item in bodies:
		var current: Transform3D = item.owner.global_transform
		# Exact comparison only: even submicron motion and R/reset must reach the
		# query world. Avoid reinserting unchanged high-detail concave bodies.
		if item.has("last_synced_transform") and item.last_synced_transform == current:
			body_sync_stats.unchanged_skips += 1
			continue
		PhysicsServer3D.body_set_state(item.rid, PhysicsServer3D.BODY_STATE_TRANSFORM, current)
		if item.has("motion_rid"):
			PhysicsServer3D.body_set_state(item.motion_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, current)
		item.last_synced_transform = current
		body_sync_stats.updates += 1
	# GPU blend weights stay inside the precomputed pose envelope. Follow the
	# actual artwork roots separately (for example, cancelling the native bob).
	for item in dynamic_motion_shapes:
		if not is_instance_valid(item.mesh) or not is_instance_valid(item.owner):continue
		var relative:Transform3D=item.owner.global_transform.affine_inverse()*item.mesh.global_transform
		if relative==item.last_relative:continue
		PhysicsServer3D.body_set_shape_transform(item.rid,item.index,relative)
		item.last_relative=relative
		motion_shape_stats.local_transform_updates+=1

func visual_occlusion_ray(from:Vector3,to:Vector3,mask:int=3,exclude:Array[RID]=[])->Dictionary:
	# Static art and bones retain exact triangles. GPU-deformed visitors use
	# their conservative pose envelope, never a claim of per-frame GPU triangles.
	var ignored:Array[RID]=exclude.duplicate()
	ignored.append_array(visitor_exact_rids)
	var hit:=query_world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,mask,ignored))
	var visitor:=motion_world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,4))
	if visitor.is_empty():return hit
	if hit.is_empty() or from.distance_squared_to(visitor.position)<from.distance_squared_to(hit.position):return visitor
	return hit

func visual_blocker(from: Vector3, to: Vector3, target: Node3D) -> String:
	sync_bodies()
	var exclude: Array[RID] = []
	for item in bodies:
		if item.owner == target: exclude.append(item.rid)
	var hit := visual_occlusion_ray(from,to,3,exclude)
	if hit.is_empty(): return ""
	for item in bodies:
		if item.rid == hit.rid or item.get("motion_rid")==hit.rid: return item.id
	return "visual blocker"

func safe_distance(focus: Vector3, motion: Vector3, mask: int, radius: float) -> float:
	if motion.length() < .0001: return 0.0
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, focus)
	query.motion = motion
	query.collision_mask = mask
	query_stats.cast_motion_calls += 1
	var cast := motion_world.direct_space_state.cast_motion(query)
	if cast.size() == 2 and cast[0] < 1.0:
		return maxf(0.0, motion.length() * cast[0] - .025)
	return motion.length()

func create_motion_body(owner: Node3D, role: String, meshes: Array) -> RID:
	var rid := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(rid, motion_world.space)
	PhysicsServer3D.body_set_collision_layer(rid, 5 if role.begins_with("visitor_") else (2 if role == "barrier_rope" else 1))
	PhysicsServer3D.body_set_collision_mask(rid, 0)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var relative := owner.global_transform.affine_inverse() * mesh.global_transform
		var shape := conservative_motion_shape(mesh.mesh)
		var index:int=PhysicsServer3D.body_get_shape_count(rid)
		PhysicsServer3D.body_add_shape(rid, shape.get_rid(), relative)
		if role.begins_with("visitor_"):
			dynamic_motion_shapes.append({"rid":rid,"index":index,"owner":owner,"mesh":mesh,"last_relative":relative})
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, owner.global_transform)
	return rid

func conservative_motion_shape(mesh: Mesh) -> ConvexPolygonShape3D:
	var key := mesh.get_instance_id()
	if motion_shape_cache.has(key):
		motion_shape_stats.cache_hits += 1
		return motion_shape_cache[key]
	var vertices := PackedVector3Array()
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		if not arrays.is_empty(): vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
		if mesh is ArrayMesh and mesh.get_blend_shape_count()>0 and mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED:
			# Nonnegative normalized weights summing to at most one remain inside
			# the convex hull of base vertices plus every absolute target pose.
			for target:Array in mesh.surface_get_blend_shape_arrays(surface):
				vertices.append_array(target[Mesh.ARRAY_VERTEX])
	if mesh is ArrayMesh and mesh.get_blend_shape_count()>0:motion_shape_stats.blend_shape_meshes+=1
	var planes: Array[Plane] = []
	for direction: Vector3 in HULL_DIRECTIONS:
		var normal := direction.normalized()
		var low := INF
		var high := -INF
		for vertex in vertices:
			var projection := normal.dot(vertex)
			low = minf(low, projection)
			high = maxf(high, projection)
		planes.append(Plane(normal, high + 0.001))
		planes.append(Plane(-normal, -low + 0.001))
	var points := Geometry3D.compute_convex_mesh_points(planes)
	if points.size() < 4:
		# Degenerate flat artwork retains a thin conservative envelope.
		var box := mesh.get_aabb().grow(0.001)
		for x in [0,1]:
			for y in [0,1]:
				for z in [0,1]: points.append(box.position + box.size * Vector3(x,y,z))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	motion_shape_cache[key] = shape
	motion_shape_stats.unique_meshes += 1
	motion_shape_stats.hull_vertices += points.size()
	return shape

func _exit_tree() -> void:
	for item in bodies:
		PhysicsServer3D.free_rid(item.rid)
		if item.has("motion_rid"): PhysicsServer3D.free_rid(item.motion_rid)
	bodies.clear()
	shapes.clear()
	query_world = null
	motion_world = null
	motion_shape_cache.clear()
	dynamic_motion_shapes.clear()
	visitor_exact_rids.clear()
