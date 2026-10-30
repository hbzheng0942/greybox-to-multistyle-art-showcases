extends RefCounted
## A01 carry adapter. The native bone keeps identity, mass and shape resources.
## Acquisition is swept; while carried its original shapes form one temporary
## CharacterBody compound with the dog. Release restores native dynamic physics.
const RECIPE:="a01-swept-compound-carry-01"
const ACQUIRE_SPEED:float=5.0
const ANGULAR_STEP:float=.015
var active:RigidBody3D
var epoch:int=-1
var mode:String="idle"
var local_anchor:=Vector3.ZERO
var local_direction:=Vector3.ZERO
var grip_relative_basis:=Basis.IDENTITY
var relative_pose:=Transform3D.IDENTITY
var bite_local:=Vector3(0,.45,-.48)
var bite_calibrated:=false
var bite_calibration_attempted:=false
var bite_measurement:Dictionary={}
var item:Dictionary={}
var query_helper
var query_excludes:Array[RID]=[]
var collision_shapes:Array=[]
var temporary_shapes:Array[CollisionShape3D]=[]
var saved:Dictionary={}
var before_input_states:Dictionary={}
var transport_linear:=Vector3.ZERO
var transport_angular:=Vector3.ZERO
var step_delta:float=1.0/60.0
var requested_motion:=Vector3.ZERO
var movement_origin:=Vector3.ZERO
var last_motion_fraction:float=1.0
var acquire_elapsed:float=0
var rejecting:=false
var last:Dictionary={}
var totals:Dictionary={"grabs":0,"frames":0,"first_solve_usec":[],"attached":0,"restored":0,"rejected_acquisitions":0,"maximum_bite_error_m":0.0,"yaw_limited_frames":0}

func contract()->Dictionary:
	return {"recipe":RECIPE,"mode":mode,"scope":"original skeleton RigidBodies with exact installed visible mesh cache","native_identity_mass_shape_resources":"preserved","held_physics_mode":"swept acquisition then temporary original-shape compound on native CharacterBody; original body frozen and its shape nodes disabled only while carried","translation":"native CharacterBody move_and_slide with dog plus held original shapes","rotation":"carried yaw capped at 3.2 rad/s; short continuous arc steps with original-shape center sweeps and overlap admission","carried_max_yaw_radians_per_second":3.2,"release":"remove temporary compound; restore original shape disabled states, freeze mode, dog mask; return actual transport velocity before inherited release/throw/reset","mouth_transform_changed":false,"permanent_fixed_grip":true,"bite_calibration":bite_measurement,"temporary_shape_count":temporary_shapes.size(),"totals":totals,"last":last}

func before_native_input(game)->void:
	if not Input.is_action_just_pressed("dog_grab") or game.held!=null:return
	before_input_states.clear()
	for body in game.props:
		if body is RigidBody3D and bool(body.get_meta("is_bone",false)):
			before_input_states[body.get_instance_id()]={"linear_velocity":body.linear_velocity,"angular_velocity":body.angular_velocity}

func update(game,delta:float)->void:
	if not bite_calibration_attempted and game.a01_picker!=null:_calibrate_bite(game)
	var body:RigidBody3D=game.held
	if body==null or not bool(body.get_meta("is_bone",false)):
		if active!=null:_restore(game)
		return
	if body!=active or epoch!=int(body.get_meta("release_epoch",0)):
		if active!=null:_restore(game)
		if not _begin(game,body):
			_reject_new_grip(game,"这个角度咬不稳，换个位置")
			return
	step_delta=delta;totals.frames+=1
	if mode=="acquiring":
		acquire_elapsed+=delta
		var wanted:=active.global_transform
		wanted.origin=game.dog.to_global(bite_local)-wanted.basis*local_anchor
		var motion:Vector3=wanted.origin-active.global_position
		var travel:Vector3=motion.limit_length(ACQUIRE_SPEED*delta)
		var fraction:float=_safe_motion(game,active,travel)
		last_motion_fraction=fraction
		var proposed:=active.global_transform;proposed.origin+=travel*fraction
		if fraction<.999 or not _body_pose_dog_clear(game,proposed):
			_reject_new_grip(game,"吸近路线被挡住了，换个位置咬")
			return
		transport_linear=travel/maxf(delta,.001);transport_angular=Vector3.ZERO
		active.global_transform=proposed
		active.linear_velocity=Vector3.ZERO;active.angular_velocity=Vector3.ZERO
		if motion.length()<=ACQUIRE_SPEED*delta+.0001:_attach(game)
		elif acquire_elapsed>.8:
			_reject_new_grip(game,"距离太远，靠近后再咬")
			return
	if mode=="carrying":
		active.linear_velocity=transport_linear;active.angular_velocity=transport_angular
	_record(game)

func limit_translation(game,requested:Vector3,delta:float)->Vector3:
	step_delta=delta
	requested_motion=Vector3(requested.x,0,requested.z)*delta
	movement_origin=game.dog.global_position
	if active==null or game.held!=active:return requested
	# Brief first-grab approach is swept before the compound is installed.
	# Once attached, the unchanged native motor sees every held shape itself.
	if mode=="acquiring":return Vector3(0,requested.y,0)
	return requested

func limit_dog_yaw(game,previous_yaw:float,physics_delta:float=1.0/60.0)->void:
	if active==null or game.held!=active:return
	if mode=="acquiring":
		game.dog.rotation.y=previous_yaw
		return
	if mode!="carrying":return
	var requested:float=game.dog.rotation.y
	# An instantaneous reverse input used to swing a held metre-scale bone
	# at >26 rad/s. Bound carried turns for readable motion and stable framing;
	# the native empty-handed controller and every collision sweep are unchanged.
	var delta:float=clampf(angle_difference(previous_yaw,requested),-3.2*physics_delta,3.2*physics_delta)
	var previous:float=previous_yaw
	var old_body:=active.global_transform
	var base:Transform3D=game.dog.global_transform
	base.basis=Basis(Vector3.UP,-delta)*base.basis
	var steps:int=maxi(1,ceili(absf(delta)/ANGULAR_STEP))
	for i in range(1,steps+1):
		var candidate:float=previous_yaw+delta*float(i)/float(steps)
		var from_pose:=base;from_pose.basis=Basis(Vector3.UP,previous-previous_yaw)*base.basis
		var candidate_pose:=base;candidate_pose.basis=Basis(Vector3.UP,candidate-previous_yaw)*base.basis
		if _compound_arc_clear(game,from_pose,candidate_pose):
			previous=candidate
			continue
		var low:=previous;var high:=candidate
		for refine in range(8):
			var middle:float=(low+high)*.5
			candidate_pose.basis=Basis(Vector3.UP,middle-previous_yaw)*base.basis
			if _compound_arc_clear(game,from_pose,candidate_pose):low=middle
			else:high=middle
		previous=low
		break
	game.dog.rotation.y=previous
	if absf(angle_difference(previous,requested))>.00001:totals.yaw_limited_frames+=1
	# Translation has already been solved by move_and_slide using these same
	# temporary shapes; the owner's art follows that admitted compound pose.
	active.global_transform=game.dog.global_transform*relative_pose
	var actual_motion:Vector3=game.dog.global_position-movement_origin;actual_motion.y=0
	last_motion_fraction=clampf(actual_motion.dot(requested_motion)/requested_motion.length_squared(),0.0,1.0) if requested_motion.length_squared()>1e-10 else 1.0
	transport_linear=(active.global_position-old_body.origin)/maxf(step_delta,.001)
	var turn:Quaternion=(active.global_basis*old_body.basis.inverse()).get_rotation_quaternion().normalized()
	if turn.w<0:turn=Quaternion(-turn.x,-turn.y,-turn.z,-turn.w)
	transport_angular=turn.get_axis()*turn.get_angle()/maxf(step_delta,.001) if turn.get_angle()>.000001 else Vector3.ZERO
	_record(game)

func before_release(game)->void:
	if active==null:return
	_restore(game)

func _attach(game)->void:
	relative_pose=game.dog.global_transform.affine_inverse()*active.global_transform
	for row in collision_shapes:
		var shape:=CollisionShape3D.new();shape.name="A01HeldCompound_"+str(temporary_shapes.size())
		shape.shape=row.shape;shape.transform=relative_pose*row.relative
		shape.set_meta("a01_local_contact",true);shape.set_meta("a01_held_compound",true)
		shape.set_meta("a01_source_body",str(active.get_path()));shape.set_meta("a01_source_shape",str(row.node.get_path()))
		game.dog.add_child(shape);temporary_shapes.append(shape)
		row.node.disabled=true
	game.dog.collision_mask=int(saved.dog_mask)|active.collision_mask
	mode="carrying";totals.attached+=1
	transport_linear=Vector3.ZERO;transport_angular=Vector3.ZERO

func _restore(game)->void:
	if active==null:return
	for shape in temporary_shapes:
		if is_instance_valid(shape):
			shape.disabled=true
			shape.get_parent().remove_child(shape);shape.free()
	temporary_shapes.clear()
	for row in collision_shapes:
		if is_instance_valid(row.node):row.node.disabled=bool(row.disabled)
	if not saved.is_empty():
		game.dog.collision_mask=int(saved.dog_mask)
		active.freeze_mode=int(saved.freeze_mode);active.freeze=bool(saved.freeze)
		active.linear_velocity=saved.linear_velocity if rejecting else transport_linear
		active.angular_velocity=saved.angular_velocity if rejecting else transport_angular
	active.sleeping=false
	totals.restored+=1
	active=null;epoch=-1;mode="idle";saved={};collision_shapes.clear()

func _reject_new_grip(game,message:String)->void:
	rejecting=true;totals.rejected_acquisitions+=1
	if game.held!=null:game._release(false)
	else:_restore(game)
	rejecting=false
	game._show_feedback(message)
	last={"admission_rejected":true,"reason":message,"physics_restored":active==null and game.held==null}

func _compound_arc_clear(game,from_pose:Transform3D,to_pose:Transform3D)->bool:
	var query:=PhysicsShapeQueryParameters3D.new();query.collision_mask=game.dog.collision_mask;query.margin=.001
	var excludes:Array[RID]=[game.dog.get_rid(),active.get_rid()]
	for other in game.dog.get_collision_exceptions():
		if is_instance_valid(other):excludes.append(other.get_rid())
	query.exclude=excludes
	var space=game.get_world_3d().direct_space_state
	for shape in temporary_shapes:
		query.shape=shape.shape
		query.transform=from_pose*shape.transform
		query.motion=(to_pose*shape.transform).origin-query.transform.origin
		if query.motion.length_squared()>1e-12:
			var fraction:PackedFloat32Array=space.cast_motion(query)
			if fraction.size()==2 and fraction[0]<.999:return false
		query.motion=Vector3.ZERO;query.transform=to_pose*shape.transform
		if not space.intersect_shape(query,1).is_empty():return false
	return true

func _body_pose_dog_clear(game,pose:Transform3D)->bool:
	PhysicsServer3D.body_set_state(item.rid,PhysicsServer3D.BODY_STATE_TRANSFORM,pose)
	var query:=PhysicsShapeQueryParameters3D.new();query.collision_mask=1;query.exclude=query_excludes;query.margin=.001
	var clear:=true
	for child in game.dog.find_children("*","CollisionShape3D",true,false):
		if child.disabled or child.get_meta("a01_held_compound",false):continue
		query.shape=child.shape;query.transform=child.global_transform
		if not query_helper.query_world.direct_space_state.intersect_shape(query,1).is_empty():clear=false;break
	PhysicsServer3D.body_set_state(item.rid,PhysicsServer3D.BODY_STATE_TRANSFORM,active.global_transform)
	return clear

func physical_sample(game)->Dictionary:
	if active==null or game.held!=active:return {}
	var anchor:Vector3=active.to_global(local_anchor);var bite:Vector3=game.dog.to_global(bite_local)
	return {"mode":mode,"bite_error_m":bite.distance_to(anchor),"anchor_world":_v(anchor),"bite_world":_v(bite),"dog_shape_clear":_body_pose_dog_clear(game,active.global_transform),"measured":"actual transforms at caller phase","physics_interpolation_enabled":bool(ProjectSettings.get_setting("physics/common/physics_interpolation",false))}

func _record(game)->void:
	var anchor:Vector3=active.to_global(local_anchor);var bite:Vector3=game.dog.to_global(bite_local)
	var error:float=bite.distance_to(anchor)
	totals.maximum_bite_error_m=maxf(totals.maximum_bite_error_m,error)
	last={"body":str(active.name),"bone_id":str(active.get_meta("bone_id","")),"mode":mode,"epoch":epoch,"surface_anchor_local":_v(local_anchor),"anchor_world":_v(anchor),"bite_world":_v(bite),"bite_error_m":error,"fixed_grip_for_epoch":true,"anchor_is_exact_triangle_surface":true,"temporary_shape_count":temporary_shapes.size(),"transport_linear_velocity":_v(transport_linear),"transport_angular_velocity":_v(transport_angular),"safe_motion_fraction":last_motion_fraction,"motion_fraction_measurement":"actual CharacterBody displacement projected onto requested horizontal displacement"}

func _begin(game,body:RigidBody3D)->bool:
	var start:int=Time.get_ticks_usec()
	active=body;epoch=int(body.get_meta("release_epoch",0));item={};collision_shapes.clear()
	var prior:Dictionary=before_input_states.get(body.get_instance_id(),{"linear_velocity":body.linear_velocity,"angular_velocity":body.angular_velocity})
	saved={"freeze":body.freeze,"freeze_mode":body.freeze_mode,"dog_mask":game.dog.collision_mask,"linear_velocity":prior.linear_velocity,"angular_velocity":prior.angular_velocity}
	if game.a01_picker==null:return false
	query_helper=game.a01_picker.visual_world
	for row in query_helper.bodies:
		if row.owner==body:item=row;break
	if item.is_empty():return false
	if not bite_calibrated:_calibrate_bite(game)
	query_excludes.clear()
	for row in query_helper.bodies:
		if row.owner!=body:query_excludes.append(row.rid)
	for child in body.find_children("*","CollisionShape3D",true,false):
		if not child.disabled:collision_shapes.append({"node":child,"disabled":child.disabled,"shape":child.shape,"relative":body.global_transform.affine_inverse()*child.global_transform})
	var local:Vector3=body.to_local(game.dog.to_global(bite_local))
	var faces:PackedVector3Array=item.faces
	var best:=INF;var nearest:=Vector3.ZERO
	var support_scores:Array[float]=[INF,INF,INF,INF]
	var support_points:Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
	var forward:Vector3=-game.dog.global_basis.z.normalized()
	var minimum_y:=INF
	var support_seen:Dictionary={}
	# One exact nearest-triangle solve per grab/epoch, never in the held loop.
	for i in range(0,faces.size(),3):
		var point:Vector3=game.a01_picker.closest_triangle(local,faces[i],faces[i+1],faces[i+2])
		var distance:float=point.distance_squared_to(local)
		if distance<best:best=distance;nearest=point
		for vertex in [faces[i],faces[i+1],faces[i+2]]:
			if support_seen.has(vertex):continue
			support_seen[vertex]=true
			var rotated:Vector3=body.global_basis*vertex
			minimum_y=minf(minimum_y,rotated.y)
			var projection:float=rotated.dot(forward)
			var scores:Array[float]=[projection,projection+rotated.y*.35,projection+rotated.y,projection+rotated.y*3.0]
			for k in range(4):
				if scores[k]<support_scores[k]:support_scores[k]=scores[k];support_points[k]=vertex
	# A tilted original box may reach below the sculpted surface. Both the
	# visible skin and the unchanged native shape must fit above the support.
	for row in collision_shapes:
		var shape_box:AABB=Transform3D(body.global_basis,Vector3.ZERO)*row.relative*row.shape.get_debug_mesh().get_aabb()
		minimum_y=minf(minimum_y,shape_box.position.y)
	grip_relative_basis=game.dog.global_basis.inverse()*body.global_basis
	local_direction=(body.global_basis.inverse()*(-game.dog.global_basis.z)).normalized()
	var exterior:Dictionary=_surface_ray(body,_surface_guide(body,body.to_global(nearest)),body.global_basis*local_direction)
	local_anchor=body.to_local(exterior.position) if not exterior.is_empty() else nearest
	var candidates:Array[Vector3]=[local_anchor,nearest]
	candidates.append_array(support_points)
	var viable:Array=[];var candidates_report:Array=[]
	var bite:Vector3=game.dog.to_global(bite_local)
	for candidate in candidates:
		var pose:=body.global_transform;pose.origin=bite-body.global_basis*candidate
		var admission:Dictionary=_grip_admission(game,body,pose,minimum_y)
		admission["anchor"]=_v(candidate)
		admission["requested_origin_travel_m"]=body.global_position.distance_to(pose.origin)
		candidates_report.append(admission)
		if admission.clear:viable.append({"anchor":candidate,"distance":body.global_position.distance_squared_to(pose.origin)})
	if not viable.is_empty():
		viable.sort_custom(func(a,b):return a.distance<b.distance)
		local_anchor=viable[0].anchor
	PhysicsServer3D.body_set_state(item.rid,PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	totals.grabs+=1
	totals.first_solve_usec.append({"body":str(body.name),"bone_id":str(body.get_meta("bone_id","")),"triangles":faces.size()/3,"usec":Time.get_ticks_usec()-start,"nearest_surface_distance_m":sqrt(best),"external_ray_resolved":not exterior.is_empty(),"anchor_local":_v(local_anchor),"grip_admission_passed":not viable.is_empty(),"actual_surface_candidates":candidates_report})
	if viable.is_empty():return false
	body.freeze_mode=RigidBody3D.FREEZE_MODE_KINEMATIC;body.freeze=true
	body.linear_velocity=Vector3.ZERO;body.angular_velocity=Vector3.ZERO
	acquire_elapsed=0;mode="acquiring"
	return true

func _grip_admission(game,body:RigidBody3D,pose:Transform3D,minimum_y:float)->Dictionary:
	PhysicsServer3D.body_set_state(item.rid,PhysicsServer3D.BODY_STATE_TRANSFORM,pose)
	var query:=PhysicsShapeQueryParameters3D.new();query.collision_mask=1;query.exclude=query_excludes;query.margin=.003
	var intersections:=0
	for child in game.dog.find_children("*","CollisionShape3D",true,false):
		if child.disabled:continue
		query.shape=child.shape;query.transform=child.global_transform
		intersections+=query_helper.query_world.direct_space_state.intersect_shape(query,1).size()
	var ray:=PhysicsRayQueryParameters3D.create(pose.origin+Vector3.UP*.2,pose.origin+Vector3.DOWN*3.0,1)
	ray.exclude=[body.get_rid(),game.dog.get_rid()]
	var floor_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	var floor_clearance:float=pose.origin.y+minimum_y-float(floor_hit.position.y) if not floor_hit.is_empty() else INF
	var native_query:=PhysicsShapeQueryParameters3D.new();native_query.collision_mask=body.collision_mask;native_query.exclude=[body.get_rid(),game.dog.get_rid()];native_query.margin=.001
	var environment_intersections:=0
	for row in collision_shapes:
		native_query.shape=row.shape;native_query.transform=pose*row.relative
		environment_intersections+=game.get_world_3d().direct_space_state.intersect_shape(native_query,1).size()
	return {"clear":intersections==0 and floor_clearance>=-.005 and environment_intersections==0,"original_shape_environment_intersections":environment_intersections,"dog_shape_surface_intersections":intersections,"actual_art_floor_clearance_m":floor_clearance,"query_only_pose":true}

func _surface_guide(body:RigidBody3D,near:Vector3)->Vector3:
	# Interior ray guide only; it is never the grip point. Rotating a ray through
	# the old surface point itself would stick there until a discontinuous flip.
	var guide:Vector3=body.to_global((item.bounds as AABB).get_center())
	guide.y=near.y
	return guide

func _surface_ray(body:RigidBody3D,through:Vector3,direction:Vector3)->Dictionary:
	# Existing query-world concave triangles, not the native primitive or AABB.
	# Bounds only determine ray length; every accepted point is an actual hit.
	PhysicsServer3D.body_set_state(item.rid,PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	var span:float=(item.bounds as AABB).size.length()+1.0
	var ray:=PhysicsRayQueryParameters3D.create(through-direction.normalized()*span,through+direction.normalized()*span,1)
	ray.exclude=query_excludes;ray.hit_back_faces=true;ray.hit_from_inside=true
	return query_helper.query_world.direct_space_state.intersect_ray(ray)

func _safe_motion(game,body:RigidBody3D,motion:Vector3,margin:float=.001,start_offset:Vector3=Vector3.ZERO)->float:
	if motion.length_squared()<1e-10:return 1.0
	var query:=PhysicsShapeQueryParameters3D.new()
	query.collision_mask=body.collision_mask
	var exclude:Array[RID]=[body.get_rid(),game.dog.get_rid()]
	for other in body.get_collision_exceptions():
		if is_instance_valid(other):exclude.append(other.get_rid())
	query.exclude=exclude;query.motion=motion;query.margin=margin
	var safe:=1.0
	for row in collision_shapes:
		query.shape=row.shape;query.transform=body.global_transform*row.relative
		query.transform.origin+=start_offset
		var result:PackedFloat32Array=game.get_world_3d().direct_space_state.cast_motion(query)
		if result.size()==2 and result[0]<1.0:safe=minf(safe,maxf(0.0,result[0]-.002))
	return safe

func _calibrate_bite(game)->void:
	var entry:Dictionary=game.visual_catalog.entries.get("player/dog",{})
	var art:Node3D=entry.get("artwork") as Node3D
	if art==null:return
	bite_calibration_attempted=true
	var calibration_start:int=Time.get_ticks_usec()
	var origin:Vector3=game.mouth.position+Vector3(0,0,-2.0)
	var nearest:=INF;var face_point:=Vector3.INF;var nose_tip:=Vector3.INF;var triangles:=0
	for node in art.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree():continue
		var relative:Transform3D=game.dog.global_transform.affine_inverse()*node.global_transform
		var faces:PackedVector3Array=node.mesh.get_faces()
		for i in range(0,faces.size(),3):
			triangles+=1
			var a:Vector3=relative*faces[i];var b:Vector3=relative*faces[i+1];var c:Vector3=relative*faces[i+2]
			for vertex in [a,b,c]:
				if absf(vertex.x)<.055 and vertex.y>.35 and vertex.y<.65 and vertex.z<nose_tip.z:nose_tip=vertex
			if minf(a.x,minf(b.x,c.x))>0 or maxf(a.x,maxf(b.x,c.x))<0 or minf(a.y,minf(b.y,c.y))>origin.y or maxf(a.y,maxf(b.y,c.y))<origin.y:continue
			var hit=Geometry3D.ray_intersects_triangle(origin,Vector3.BACK,a,b,c)
			if hit!=null and origin.distance_squared_to(hit)<nearest:
				nearest=origin.distance_squared_to(hit);face_point=hit
	if face_point.is_finite() and nose_tip.is_finite():
		bite_local=nose_tip+Vector3(0,0,-.010)
		bite_calibrated=true
		bite_measurement={"method":"frontmost actual nose-surface vertex in central muzzle, with original Mouth-height ray recorded separately","mesh_triangles_tested":triangles,"original_mouth_local":_v(game.mouth.position),"actual_mouth_height_surface_local":_v(face_point),"actual_nose_tip_local":_v(nose_tip),"bite_local":_v(bite_local),"mouth_to_bite_m":bite_local.distance_to(game.mouth.position),"skin_clearance_m":.010,"one_time_idle_calibration_usec":Time.get_ticks_usec()-calibration_start}

func _v(value:Vector3)->Array:return [value.x,value.y,value.z]
