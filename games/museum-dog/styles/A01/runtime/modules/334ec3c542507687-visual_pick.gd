extends Node
## Input-target supplement, not a physics collider. Uses exact cached visible
## triangles and each native body's current world transform on every key press.
var game
var visual_world
var bones: Array = []

func setup(target, camera_queries) -> void:
	game = target
	visual_world = camera_queries
	name = "A01VisibleBonePicker"
	for item in visual_world.bodies:
		if item.role == "skeleton_segment": bones.append(item)

func chest() -> Vector3:
	return game.dog.global_position + Vector3(0,.85,0) - game.dog.global_transform.basis.z * .55

func has_native_candidate() -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = .7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY,chest())
	query.collision_mask = 2
	for hit in game.get_world_3d().direct_space_state.intersect_shape(query,16):
		if hit.collider is RigidBody3D and hit.collider.is_in_group("props"):
			return true
	return false

func pick_supplement() -> Dictionary:
	var origin := chest()
	var best: Dictionary = {}
	var best_distance_squared := .7 * .7
	# Stable semantic ID breaks exact-distance ties. At most one body is returned.
	var ordered := bones.duplicate()
	ordered.sort_custom(func(a,b): return str(a.id) < str(b.id))
	for item in ordered:
		var body: RigidBody3D = item.owner
		if not is_instance_valid(body): continue
		var local: Vector3 = body.to_local(origin)
		var bounds: AABB = item.bounds
		if local.distance_squared_to(local.clamp(bounds.position,bounds.end)) > best_distance_squared: continue
		var faces: PackedVector3Array = item.faces
		for i in range(0,faces.size(),3):
			var point := closest_triangle(local,faces[i],faces[i+1],faces[i+2])
			var distance_squared := local.distance_squared_to(point)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best = {"body":body,"bone_id":body.get_meta("bone_id"),"point":body.to_global(point),"surface_distance_m":sqrt(distance_squared),"method":"visible_bone_supplement"}
	if best.is_empty(): return {"method":"none","radius_m":.7}
	var ray := PhysicsRayQueryParameters3D.create(origin,best.point,1|2|4)
	ray.exclude = [game.dog.get_rid(),best.body.get_rid()]
	ray.hit_from_inside = true
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
	var blocker: String = visual_world.visual_blocker(origin,best.point,best.body)
	best["blocked"] = not hit.is_empty() or not blocker.is_empty()
	best["blocker"] = str(hit.collider.name) if not hit.is_empty() else blocker
	return best

func closest_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# Ericson region tests; degenerate primitive pole triangles use edge distances.
	var ab := b-a
	var ac := c-a
	if ab.cross(ac).length_squared() < 1e-16:
		var q := Geometry3D.get_closest_point_to_segment(p,a,b)
		for pair in [[b,c],[c,a]]:
			var candidate := Geometry3D.get_closest_point_to_segment(p,pair[0],pair[1])
			if p.distance_squared_to(candidate) < p.distance_squared_to(q): q = candidate
		return q
	var ap := p-a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0 and d2 <= 0: return a
	var bp := p-b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0 and d4 <= d3: return b
	var vc := d1*d4-d3*d2
	if vc <= 0 and d1 >= 0 and d3 <= 0: return a+ab*(d1/(d1-d3))
	var cp := p-c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0 and d5 <= d6: return c
	var vb := d5*d2-d1*d6
	if vb <= 0 and d2 >= 0 and d6 <= 0: return a+ac*(d2/(d2-d6))
	var va := d3*d6-d5*d4
	if va <= 0 and d4-d3 >= 0 and d5-d6 >= 0: return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6)))
	var denom := 1.0/(va+vb+vc)
	return a+ab*(vb*denom)+ac*(vc*denom)
