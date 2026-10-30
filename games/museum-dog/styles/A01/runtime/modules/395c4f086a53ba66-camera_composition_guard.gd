extends "res://styles/A01/runtime/modules/71dc66a83d60259e-camera_visual_guard.gd"
## Production-only visual query + same-yaw composition fallback. No gameplay shapes.
const FURNITURE_FADE=preload("res://styles/A01/runtime/modules/f4d7dddaaa4314ba-camera_furniture_fade.gd")
var furniture_fade
var specimen_bounds:Array=[]
var player_meshes:Array=[]
var fade_materials:Array=[]
var last_position:=Vector3.INF
var last_dog:=Vector3.INF
var last_focus:=Vector3.INF
var fade_alpha:=1.0
var composition:Dictionary={}
var composition_stats={"frames":0,"reframed":0,"constrained_frames":0,"faded_frames":0,"restored_frames":0,"specimen_query_bodies":0,"recovery_switches":0}
var last_mode:="normal"
var last_input_yaw:=INF
var last_input_pitch:=INF
var normal_clear_seconds:=0.0
var physics_motion_review:Dictionary={"maximum_step_m":0.0,"rapid_recoveries":[],"dropped_events":0}
var held_presented:RigidBody3D
var held_materials:Array=[]
var held_alpha:=1.0
var held_clear_seconds:=0.0
var held_restore_ready:=false
var held_fade_dwell:=0.0
var held_presentation_stats:Dictionary={}
var player_fade_dwell:=0.0
var player_fade_max_dwell:=0.0
var last_viewport_position:=Vector3.INF
var last_viewport_focus:=Vector3.INF
# Own history survives picking queries that also synchronize the query world.
var bone_pose_history:Dictionary={}
var held_pose_prediction:Dictionary={}
var held_prediction_block_seconds:=0.0
var held_prediction_query_stats:Dictionary={"broadphase_skips":0,"envelope_queries":0}
var visitor_motion_ids:Dictionary={}
var transition_rejections:Array=[]
var continuity_detour:=Vector3.ZERO
var continuity_detour_seconds:=0.0
var last_viewport_dog:=Vector3.INF

func setup(target)->void:
	super.setup(target)
	for id in game.visual_catalog.entries:
		var entry:Dictionary=game.visual_catalog.entries[id]
		var visual:Node3D=entry.artwork if entry.artwork!=null else entry.greybox
		if entry.role=="player":
			for mesh:MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
				if mesh.mesh!=null:player_meshes.append(mesh)
		if entry.role!="specimen_display":continue
		var faces:=PackedVector3Array()
		for mesh:MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh==null or not mesh.is_visible_in_tree():continue
			var relative:Transform3D=entry.owner.global_transform.affine_inverse()*mesh.global_transform
			for point in mesh.mesh.get_faces():faces.append(relative*point)
		if faces.size()<3:continue # Empty absorbed artwork must not restore hidden greybox.
		var shape:=ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision=true
		shapes.append(shape)
		var rid:=PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(rid,PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(rid,query_world.space)
		PhysicsServer3D.body_set_collision_layer(rid,1)
		PhysicsServer3D.body_set_collision_mask(rid,0)
		PhysicsServer3D.body_add_shape(rid,shape.get_rid())
		PhysicsServer3D.body_set_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM,entry.owner.global_transform)
		var bounds:=AABB(faces[0],Vector3.ZERO)
		for point in faces:bounds=bounds.expand(point)
		bodies.append({"rid":rid,"owner":entry.owner,"role":entry.role,"bounds":bounds,"faces":faces,"id":id,"last_synced_transform":entry.owner.global_transform,"motion_rid":create_motion_body(entry.owner,entry.role,visual.find_children("*","MeshInstance3D",true,false))})
		specimen_bounds.append({"owner":entry.owner,"bounds":bounds,"id":id})
	composition_stats.specimen_query_bodies=specimen_bounds.size()
	furniture_fade=FURNITURE_FADE.new()
	furniture_fade.setup(game,self)
	for item in bodies:
		if str(item.get("role","")).begins_with("visitor_"):
			visitor_motion_ids[item.get("motion_rid",RID())]=str(item.get("id","visitor"))

func _physics_process(delta:float)->void:
	if not is_instance_valid(game):
		_restore_held_presentation()
		return
	if is_instance_valid(held_presented) and game.held!=held_presented:
		_restore_held_presentation()
	if not is_instance_valid(game) or not game.is_physics_processing() or not enabled:return
	if not game.shot.is_empty() and not game.cam_follow:return
	_measure_held_pose_motion(delta)
	super._physics_process(delta)
	var focus:Vector3=game.cam_target.global_position
	var original:Vector3=game.cam.global_position
	var points:=_player_points()
	var best:=_candidate(original,focus,"normal",points)
	var base_score:float=best.score
	var changed:=false
	var retained_pose:Dictionary={}
	var anticipated_block:=false
	var lookahead:Vector3=game.dog.velocity*.30
	# Include actual falling/rising motion: retained eye height also follows it.
	# A moving/acquiring bone may have zero RigidBody velocity. Read actual
	# neighboring world poses before it reaches the retained near plane.
	anticipated_block=not _held_motion_clear_ahead(best.position,lookahead)
	var same_input:bool=is_finite(last_input_yaw) and absf(angle_difference(last_input_yaw,game.yaw))<.025 and absf(last_input_pitch-game.pitch)<.015
	normal_clear_seconds=normal_clear_seconds+delta if _normal_return_ready(best) else 0.0
	if same_input:
		retained_pose=_retained_viewport_candidate(points)
		if not retained_pose.is_empty() and retained_pose.good:
			anticipated_block=anticipated_block or not _composition_room_ahead(retained_pose.position,lookahead)
			if not best.good or anticipated_block or (last_mode!="normal" and normal_clear_seconds<.45):
				best=retained_pose
				changed=true
	if anticipated_block:best.score-=2.0
	if anticipated_block or not best.good or not _viewport_safe(best):
		# Preserve horizontal yaw and therefore the existing camera-relative input basis.
		# Low trajectory fits beneath tabletops; steep trajectory uses free space above wallsides.
		var intent_distance:float=minf(game.cam_distance,3.2)
		var low_focus:Vector3=game._camera_safe_position(game.dog.global_position+Vector3(0,.32,0),game.dog.global_position+Vector3(0,.40,0))
		var options:Array=[[low_focus,0.0,"low_horizontal"],[low_focus,.12,"low_gentle"],[focus,1.10,"high_same_yaw"],[focus,1.32,"overhead_same_yaw"],[low_focus,1.48,"wall_overhead_same_yaw"],[low_focus,1.54,"wall_vertical_same_yaw"]]
		# A dog touching the wall can leave no usable boom behind its center.
		# Move the focus into the room while retaining yaw, and admit only poses
		# whose complete player bounds remain in view. The focus shift is itself
		# swept against native geometry; it never teleports through a wall.
		var horizontal:=Vector3(sin(game.yaw),0,cos(game.yaw))
		for inset in [.55,1.0,1.45]:
			var shifted:Vector3=game._camera_safe_position(low_focus,low_focus-horizontal*inset)
			options.append([shifted,1.48,"inward_overhead_same_yaw"])
			if game.cam_distance>intent_distance+.1:
				options.append([shifted,1.48,"inward_overhead_wide_same_yaw",minf(game.cam_distance,4.6)])
		for option in options:
			var at:Vector3=option[0]
			if _inside_specimen(at):continue
			var pitch_value:float=option[1]
			var direction:=Vector3(sin(game.yaw)*cos(pitch_value),sin(pitch_value),cos(game.yaw)*cos(pitch_value))
			var candidate_distance:float=float(option[3]) if option.size()>3 else intent_distance
			var end:Vector3=game._camera_safe_position(at,at+direction*candidate_distance)
			var safe:=_presentation_safe_distance(at,end-at,3,.08)
			if safe<.12:continue
			end=at+(end-at).normalized()*minf(safe,at.distance_to(end))
			end=game._camera_safe_position(at,end)
			if not _camera_endpoint_clear(end):continue
			var candidate:=_candidate(end,at,str(option[2]),points)
			if not _viewport_safe(candidate):continue
			candidate.score-=.08 if str(option[2]).begins_with("low") else .18
			if anticipated_block and not _composition_room_ahead(end,lookahead):candidate.score-=2.0
			if not best.get("endpoint_clear",false) or not _viewport_safe(best) or candidate.score>best.score+.06:
				best=candidate
				changed=true
		# A table leg can block the straight inward focus path at its end. Try a
		# short, swept side step before retreating, without changing input yaw.
		# These are emergency poses only, with the same full-body HUD admission.
		if not best.good or not _viewport_safe(best) or not best.get("endpoint_clear",false) or (anticipated_block and not _composition_room_ahead(best.position,lookahead)):
			var right:=Vector3(cos(game.yaw),0,-sin(game.yaw))
			for side in [-.7,.7,-1.15,1.15]:
				var lateral:Vector3=game._camera_safe_position(low_focus,low_focus+right*side)
				for inset in [.7,1.2,1.65]:
					var at:Vector3=game._camera_safe_position(lateral,lateral-horizontal*inset)
					if _inside_specimen(at):continue
					var direction:=Vector3(sin(game.yaw)*cos(1.48),sin(1.48),cos(game.yaw)*cos(1.48))
					var end:Vector3=game._camera_safe_position(at,at+direction*minf(game.cam_distance,4.6))
					var safe:=_presentation_safe_distance(at,end-at,3,.08)
					if safe<.12:continue
					end=at+(end-at).normalized()*minf(safe,at.distance_to(end))
					end=game._camera_safe_position(at,end)
					if not _camera_endpoint_clear(end):continue
					var candidate:=_candidate(end,at,"lateral_inward_overhead_same_yaw",points)
					if not _viewport_safe(candidate):continue
					candidate.score-=.25
					if anticipated_block and not _composition_room_ahead(end,lookahead):candidate.score-=2.0
					if not best.get("endpoint_clear",false) or not _viewport_safe(best) or candidate.score>best.score+.06:
						best=candidate
						changed=true
	var desired:Vector3=best.position
	var target:Vector3=best.focus
	var reset:bool=not last_position.is_finite() or not last_dog.is_finite() or not last_focus.is_finite() or last_dog.distance_to(game.dog.global_position)>1.0
	transition_rejections.clear()
	var transition_blocked:=false
	var transition_reason:="fixture_or_initial_pose" if reset else "continuous_checked_pose"
	if not reset:
		# Follow player translation in full. Damping that translation every tick
		# makes an otherwise stable retained pose drift behind the player.
		# Keep damping relative composition on every frame, including the frames
		# after the target mode has already become normal.
		var transition:=_continuous_transition(best,points,delta)
		if not transition.is_empty():
			desired=transition.position
			target=transition.focus
		else:
			transition_blocked=true
			transition_reason="no_admissible_continuous_step_radial_recovery"
			composition_stats.recovery_switches+=1
	# If a prior pose has become trapped, use a checked radial recovery and disclose it.
	if desired.distance_to(target)>.10:
		game.cam.global_position=desired
		game.cam.look_at(target,Vector3.UP)
		game.cam_target.global_position=target
	var actual:=_candidate(game.cam.global_position,target,str(best.mode),points)
	var viewport_recovered:=false
	if (not _viewport_safe(actual) or not actual.get("endpoint_clear",false)) and _viewport_safe(best) and best.get("endpoint_clear",false):
		# The admitted centered pose already passed both native/visual sweeps.
		# Do not retain an off-screen interpolation merely because its score rose.
		game.cam.global_position=best.position
		game.cam.look_at(best.focus,Vector3.UP)
		game.cam_target.global_position=best.focus
		actual=_candidate(game.cam.global_position,best.focus,str(best.mode),points)
		viewport_recovered=true
		composition_stats["viewport_recoveries"]=int(composition_stats.get("viewport_recoveries",0))+1
	var retained_recovery:=false
	if not _viewport_safe(actual) or not actual.get("endpoint_clear",false):
		var retained:=_retained_viewport_candidate(points)
		if not retained.is_empty():
			game.cam.global_position=retained.position
			game.cam.look_at(retained.focus,Vector3.UP)
			game.cam_target.global_position=retained.focus
			actual=retained
			viewport_recovered=true
			retained_recovery=true
			composition_stats["retained_viewport_recoveries"]=int(composition_stats.get("retained_viewport_recoveries",0))+1
	var constrained:bool=not actual.good or not _viewport_safe(actual)
	furniture_fade.update(delta,constrained,_viewport_safe(actual))
	var head_points:Array=[Vector3(0,.33,0),Vector3(0,.50,-.31),Vector3(0,.47,-.56)]
	# Compare held/no-held under identical actually faded furniture conditions.
	# Otherwise an opaque table in only the control ray falsely blames the bone.
	var head_presented:=_visible_excluding_held(game.cam.global_position,head_points,false,true)
	var held_clear:=_visible_excluding_held(game.cam.global_position,head_points,true,true)
	# At a wall the two head probes may legitimately meet native wall geometry.
	# Compare three torso probes with/without only the held instance as well;
	# fade only when that instance alone obscures a visible part of the dog.
	var torso_points:Array=[Vector3(-.17,.38,.08),Vector3(.17,.38,.08),Vector3(0,.40,.26)]
	var torso_raw:=_visible_excluding_held(game.cam.global_position,torso_points,false)
	var torso_presented:=_visible_excluding_held(game.cam.global_position,torso_points,false,true)
	var torso_clear:=_visible_excluding_held(game.cam.global_position,torso_points,true,true) if is_instance_valid(game.held) else 0
	var held_only_blocker:bool=maxi(head_presented,torso_presented)<2 and maxi(held_clear,torso_clear)>=2
	var held_fallback:bool=_viewport_safe(actual) and held_only_blocker
	held_restore_ready=_viewport_safe(actual) and actual.get("opaque_endpoint_clear",false) and maxi(head_presented,torso_presented)>=2
	_update_held_presentation(held_fallback,delta)
	_record_held_presentation(delta)
	var requested_alpha:=.24 if constrained and (actual.height_fraction>.75 or actual.distance<.70) else 1.0
	var before:=fade_alpha
	fade_alpha=move_toward(fade_alpha,requested_alpha,delta*5.0)
	_apply_player_alpha(fade_alpha)
	player_fade_dwell=player_fade_dwell+delta if fade_alpha<.999 else 0.0
	player_fade_max_dwell=maxf(player_fade_max_dwell,player_fade_dwell)
	composition_stats.frames+=1
	if changed:composition_stats.reframed+=1
	if constrained:composition_stats.constrained_frames+=1
	if fade_alpha<.999:composition_stats.faded_frames+=1
	if before<.999 and fade_alpha>=.999:composition_stats.restored_frames+=1
	composition={"mode":str(actual.mode),"constrained":constrained,"distance":actual.distance,"player_height_fraction":actual.height_fraction,"player_screen_bounds":actual.screen_bounds,"player_all_corners_front":actual.all_front,"player_inside_screen":actual.inside,"visible_probe_points":actual.visible_points,"player_alpha":fade_alpha,"transition_blocked_recovery":transition_blocked,"same_yaw_input_basis":true,"base_score":base_score,"score":actual.score}
	# Opaque queries retain their original probe positions. Animated visitors use
	# the explicitly reported conservative envelope; held presentation rays are
	# a separate diagnostic, never a fabricated collision pass.
	composition["furniture_presentation"]=furniture_fade.snapshot()
	composition["player_fade_max_dwell_seconds"]=player_fade_max_dwell
	composition["opaque_torso_visible_points"]=actual.get("torso_visible_points",0)
	composition["endpoint_admission_passed"]=actual.get("endpoint_clear",false)
	composition["hud_safe_bottom"]=1.0 if bool(game.nohud) else .91
	composition["visibility_geometry_policy"]="exact_static_and_bones_plus_conservative_visitor_pose_envelopes"
	composition["viewport_recovered"]=viewport_recovered
	composition["retained_viewport_recovery"]=retained_recovery
	composition["viewport_admission_passed"]=_viewport_safe(actual)
	composition["presentation_clearance_excluded_held"]=not _transparent_held_rids().is_empty()
	composition["held_presentation"]={"body_id":str(held_presented.get_meta("semantic_id","")) if is_instance_valid(held_presented) else "","active":not held_materials.is_empty(),"alpha":held_alpha,"current_fade_dwell_seconds":held_fade_dwell,"requested_fallback":held_fallback,"presentation_visible_probe_points":held_clear,"presentation_torso_visible_points":torso_clear,"raw_torso_visible_points":torso_raw,"torso_visible_with_actual_furniture":torso_presented,"head_visible_with_actual_furniture":head_presented,"clear_seconds_before_restore":held_clear_seconds,"raw_visible_probe_points":actual.visible_points,"policy":"centered same-yaw candidates with hard viewport admission; only the actual held instance fades when it is the sole visibility blocker"}
	if held_alpha<.999:composition_stats["held_faded_frames"]=int(composition_stats.get("held_faded_frames",0))+1
	if not reset:
		var camera_step:float=last_position.distance_to(game.cam.global_position)
		physics_motion_review.maximum_step_m=maxf(physics_motion_review.maximum_step_m,camera_step)
		if camera_step>.45:
			var event:Dictionary={"physics_frame":Engine.get_physics_frames(),"step_m":camera_step,"dog_step_m":last_dog.distance_to(game.dog.global_position),"from":[last_position.x,last_position.y,last_position.z],"to":[game.cam.global_position.x,game.cam.global_position.y,game.cam.global_position.z],"mode":str(actual.mode),"previous_mode":last_mode,"reason":transition_reason,"viewport_recovery":viewport_recovered,"retained_recovery":retained_recovery,"anticipated_block":anticipated_block,"held_alpha":held_alpha,"held_pose_prediction":_held_prediction_snapshot(),"input_yaw_delta":angle_difference(last_input_yaw,game.yaw),"dog_position":[game.dog.global_position.x,game.dog.global_position.y,game.dog.global_position.z],"dog_yaw":game.dog.rotation.y,"transition_rejections":transition_rejections.duplicate(true)}
			if physics_motion_review.rapid_recoveries.size()<96:physics_motion_review.rapid_recoveries.append(event)
			else:physics_motion_review.dropped_events+=1
	composition["anticipated_pose_block"]=anticipated_block
	composition["held_pose_prediction"]=_held_prediction_snapshot()
	composition["held_prediction_query_stats"]=held_prediction_query_stats.duplicate()
	last_position=game.cam.global_position
	last_dog=game.dog.global_position
	last_focus=actual.focus
	composition["transition_reason"]=transition_reason
	composition["transition_rejections"]=transition_rejections.duplicate(true)
	composition["visitor_blockers"]=actual.get("visitor_blockers",[])
	last_mode=str(actual.mode)
	last_input_yaw=game.yaw;last_input_pitch=game.pitch
	composition["normal_clear_seconds_before_restore"]=normal_clear_seconds
	if _viewport_safe(actual) and _camera_endpoint_clear(game.cam.global_position):
		last_viewport_position=game.cam.global_position
		last_viewport_focus=actual.focus
		last_viewport_dog=game.dog.global_position

func _candidate(position:Vector3,focus:Vector3,label:String,points:Array)->Dictionary:
	var distance:float=position.distance_to(focus)
	if distance<.01:return {"position":position,"focus":focus,"mode":label,"score":-100.0,"good":false,"distance":distance,"height_fraction":999.0,"screen_bounds":[],"inside":false,"all_front":false,"visible_points":0}
	var inverse:=Transform3D(Basis.looking_at((focus-position).normalized(),Vector3.UP),position).affine_inverse()
	var half_y:=tan(deg_to_rad(game.cam.fov*.5))
	var aspect:float=game.cam.get_viewport().get_visible_rect().size.aspect()
	var min_uv:=Vector2.INF
	var max_uv:=Vector2(-INF,-INF)
	var front:=true
	for point in points:
		var p:Vector3=inverse*point
		if -p.z<=game.cam.near:front=false;continue
		var uv:=Vector2(.5+p.x/(-p.z*half_y*aspect)*.5,.5-p.y/(-p.z*half_y)*.5)
		min_uv=min_uv.min(uv)
		max_uv=max_uv.max(uv)
	var height:=max_uv.y-min_uv.y if min_uv.is_finite() else 999.0
	var inside:bool=front and min_uv.x>=-.04 and min_uv.y>=-.04 and max_uv.x<=1.04 and max_uv.y<=1.04
	var visible:=0
	var visitors:Array=[]
	for local in [Vector3(0,.33,0),Vector3(0,.50,-.31),Vector3(0,.47,-.56)]:
		var point:Vector3=game.dog.to_global(local)
		if not _point_on_screen(point,inverse,half_y,aspect):continue
		var hit:=visual_occlusion_ray(position,point,3)
		if visitor_motion_ids.has(hit.get("rid",RID())):
			var visitor_id:String=visitor_motion_ids[hit.rid]
			if visitor_id not in visitors:visitors.append(visitor_id)
		var native:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position,point,1))
		if hit.is_empty() and native.is_empty():visible+=1
	var torso_visible:=0
	for local in [Vector3(-.17,.38,.08),Vector3(.17,.38,.08),Vector3(0,.40,.26)]:
		var point:Vector3=game.dog.to_global(local)
		if not _point_on_screen(point,inverse,half_y,aspect):continue
		var hit:=visual_occlusion_ray(position,point,3)
		if visitor_motion_ids.has(hit.get("rid",RID())):
			var visitor_id:String=visitor_motion_ids[hit.rid]
			if visitor_id not in visitors:visitors.append(visitor_id)
		var native:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position,point,1))
		if hit.is_empty() and native.is_empty():torso_visible+=1
	var endpoint_clear:bool=_camera_endpoint_clear(position)
	var opaque_endpoint_clear:bool=endpoint_clear and (_transparent_held_rids().is_empty() or _camera_endpoint_clear(position,true))
	var opaque_visible:int=maxi(visible,torso_visible)
	var good:bool=opaque_endpoint_clear and inside and height>=.10 and height<=.68 and opaque_visible>=2 and distance>.65 and not _inside_specimen(position)
	var score:float=(-10.0 if not endpoint_clear else 0.0)+(4.0 if good else 0.0)+(1.0 if inside else -1.0)+float(opaque_visible)*.25-minf(absf(height-.38),3.0)+minf(distance,2.0)*.1
	return {"position":position,"focus":focus,"mode":label,"endpoint_clear":endpoint_clear,"opaque_endpoint_clear":opaque_endpoint_clear,"torso_visible_points":torso_visible,"score":score,"good":good,"distance":distance,"height_fraction":height,"screen_bounds":[min_uv.x,min_uv.y,max_uv.x,max_uv.y],"inside":inside,"all_front":front,"visible_points":visible,"visitor_blockers":visitors}

func _viewport_safe(candidate:Dictionary)->bool:
	var bounds:Array=candidate.get("screen_bounds",[])
	return candidate.get("all_front",false) and bounds.size()==4 and bounds[0]>=0.0 and bounds[1]>=0.0 and bounds[2]<=1.0 and bounds[3]<=(1.0 if bool(game.nohud) else .91) and candidate.height_fraction>=.10 and candidate.height_fraction<=.68

func _normal_return_ready(candidate:Dictionary)->bool:
	# The two-probe rule is a hard visibility floor. Returning from a useful
	# recovery pose requires room to spare before moving toward that floor.
	if not candidate.get("good",false) or not _viewport_safe(candidate):return false
	if int(candidate.get("visible_points",0))+int(candidate.get("torso_visible_points",0))<5:return false
	var bounds:Array=candidate.screen_bounds
	if bounds[0]<.02 or bounds[1]<.02 or bounds[2]>.98 or bounds[3]>(.98 if bool(game.nohud) else .89):return false
	return _held_eye_comfort_clear(candidate.position)

func _point_on_screen(point:Vector3,inverse:Transform3D,half_y:float,aspect:float)->bool:
	var p:Vector3=inverse*point
	if -p.z<=game.cam.near:return false
	var uv:=Vector2(.5+p.x/(-p.z*half_y*aspect)*.5,.5-p.y/(-p.z*half_y)*.5)
	return uv.x>=0.0 and uv.x<=1.0 and uv.y>=0.0 and uv.y<=1.0

func _transparent_held_rids(motion_queries:bool=false)->Array[RID]:
	var excluded:Array[RID]=[]
	# Admission depends on an already applied, visibly translucent instance.
	# Full-geometry base-guard statistics and raw visibility queries stay intact.
	if not is_instance_valid(held_presented) or game.held!=held_presented or held_materials.is_empty() or held_alpha>.25:return excluded
	for item in bodies:
		if item.owner==held_presented:excluded.append(item.motion_rid if motion_queries else item.rid)
	return excluded

func _presentation_safe_distance(focus:Vector3,motion:Vector3,mask:int,radius:float)->float:
	var excluded:=_transparent_held_rids(true)
	if excluded.is_empty():return safe_distance(focus,motion,mask,radius)
	if motion.length()<.0001:return 0.0
	sphere.radius=radius
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=sphere
	query.transform=Transform3D(Basis.IDENTITY,focus)
	query.motion=motion
	query.collision_mask=mask
	query.exclude=excluded
	var cast:=motion_world.direct_space_state.cast_motion(query)
	return maxf(0.0,motion.length()*cast[0]-.025) if cast.size()==2 and cast[0]<1.0 else motion.length()

func _camera_endpoint_clear(position:Vector3,include_opaque_held:bool=false)->bool:
	if _inside_specimen(position):return false
	sphere.radius=.08
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=sphere
	query.transform=Transform3D(Basis.IDENTITY,position)
	# Same three vetoes, cheapest conservative rejections first. During a
	# collapse do not run detailed concave contact tests for an endpoint that
	# native geometry or the conservative art volume already forbids.
	query.collision_mask=1
	if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return false
	query.collision_mask=3
	if not include_opaque_held:query.exclude=_transparent_held_rids(true)
	if not motion_world.direct_space_state.intersect_shape(query,1).is_empty():return false
	var ignored:Array[RID]=[]
	if not include_opaque_held:ignored=_transparent_held_rids()
	ignored.append_array(visitor_exact_rids);query.exclude=ignored
	return query_world.direct_space_state.intersect_shape(query,1).is_empty()

func _retained_viewport_candidate(points:Array)->Dictionary:
	if not last_viewport_position.is_finite() or not last_viewport_dog.is_finite():return {}
	var displacement:Vector3=game.dog.global_position-last_viewport_dog
	if displacement.length()>1.0:return {} # Never inherit a pose across fixture teleport/R.
	var desired:=last_viewport_position+displacement
	var focus:=last_viewport_focus+displacement
	var native_end:Vector3=game._camera_safe_position(last_viewport_position,desired)
	if native_end.distance_to(desired)>.01:return {}
	var motion:=desired-last_viewport_position
	if _presentation_safe_distance(last_viewport_position,motion,3,.08)+.01<motion.length():return {}
	if not _camera_endpoint_clear(desired):return {}
	var candidate:=_candidate(desired,focus,"retained_centered_pose",points)
	if not _viewport_safe(candidate):return {}
	return candidate

func _composition_room_ahead(position:Vector3,motion:Vector3)->bool:
	return _motion_clear_ahead(position,motion.limit_length(.8)) and _held_eye_comfort_clear(position) and _held_motion_clear_ahead(position,motion)

func _measure_held_pose_motion(delta:float)->void:
	held_pose_prediction.clear()
	held_prediction_block_seconds=0.0
	for item in bodies:
		if not is_instance_valid(item.owner) or not bool(item.owner.get_meta("is_bone",false)):continue
		var id:int=item.owner.get_instance_id()
		var current:Transform3D=item.owner.global_transform
		var previous:Transform3D=bone_pose_history.get(id,current)
		var has_history:bool=bone_pose_history.has(id)
		bone_pose_history[id]=current
		if item.owner!=game.held or not has_history or delta<=0.0:continue
		# Fixture/reset teleport is not a measured velocity to extrapolate.
		if current.origin.distance_to(previous.origin)>1.0:continue
		var rotation:Quaternion=(current.basis.orthonormalized().get_rotation_quaternion()*previous.basis.orthonormalized().get_rotation_quaternion().inverse()).normalized()
		if rotation.w<0.0:rotation=-rotation
		var angle:float=rotation.get_angle()
		# get_axis() can drift outside Basis's unit tolerance for tiny rotations.
		var axis:Vector3=rotation.get_axis().normalized() if angle>.00001 else Vector3.UP
		held_pose_prediction={"owner":item.owner,"rid":item.get("motion_rid",RID()),"current":current,"previous":previous,"linear":(current.origin-previous.origin)/delta,"axis":axis,"angular":angle/delta,"delta":delta}
		if item.has("bounds"):
			# The hull includes XYZ support planes padded by1mm. Sum of basis
			# lengths conservatively bounds that padding under rotation/scale.
			var pad:float=.001*(current.basis.x.length()+current.basis.y.length()+current.basis.z.length())
			held_pose_prediction["world_bounds"]=(current*item.bounds).grow(pad)

func _held_motion_clear_ahead(position:Vector3,camera_motion:Vector3)->bool:
	if held_pose_prediction.is_empty() or not is_instance_valid(game.held):return true
	if held_pose_prediction.owner!=game.held or not held_pose_prediction.rid.is_valid():return true
	var linear:Vector3=held_pose_prediction.linear
	var angular:float=held_pose_prediction.angular
	if linear.length_squared()<.0001 and angular<.01:return true
	var current:Transform3D=held_pose_prediction.current
	for ahead in [.10,.20,.30]:
		var rotation:=Basis(held_pose_prediction.axis,angular*ahead)
		var predicted:=Transform3D(rotation*current.basis,current.origin+linear*ahead)
		var eye:Vector3=position+camera_motion*(ahead/.30)
		# Rigid relative transform maps a future eye into the existing held
		# envelope. No body, shape, or query-world pose is moved by prediction.
		var mapped_eye:Vector3=current*(predicted.affine_inverse()*eye)
		if not _held_rid_eye_clear(mapped_eye,held_pose_prediction.rid,.28):
			held_prediction_block_seconds=maxf(held_prediction_block_seconds,ahead)
			return false
	return true

func _held_prediction_snapshot()->Dictionary:
	if held_pose_prediction.is_empty():return {"available":false}
	var item:Dictionary=held_pose_prediction
	var linear:Vector3=item.linear
	var current:Transform3D=item.current
	var previous:Transform3D=item.previous
	var contact:Variant=game.get("a01_held_art_contact")
	var q:Quaternion=current.basis.orthonormalized().get_rotation_quaternion()
	var p:Quaternion=previous.basis.orthonormalized().get_rotation_quaternion()
	return {"available":true,"body_id":str(item.owner.get_meta("bone_id","")),"phase":str(contact.get("mode")) if contact!=null else "unknown","linear_mps":[linear.x,linear.y,linear.z],"angular_radians_per_second":item.angular,"current_rotation_quaternion":[q.x,q.y,q.z,q.w],"previous_rotation_quaternion":[p.x,p.y,p.z,p.w],"current_origin":[current.origin.x,current.origin.y,current.origin.z],"previous_origin":[previous.origin.x,previous.origin.y,previous.origin.z],"predicted_block_horizon_seconds":held_prediction_block_seconds,"policy":"measured_world_pose_linear_and_angular_extrapolation_0.1_0.2_0.3_seconds_query_only"}

func _held_rid_eye_clear(position:Vector3,held_rid:RID,radius:float)->bool:
	if held_pose_prediction.get("rid",RID())==held_rid and held_pose_prediction.has("world_bounds"):
		var broadphase:AABB=held_pose_prediction.world_bounds
		if not broadphase.grow(radius).has_point(position):
			held_prediction_query_stats.broadphase_skips+=1
			return true
	held_prediction_query_stats.envelope_queries+=1
	sphere.radius=radius
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=sphere
	query.transform=Transform3D(Basis.IDENTITY,position);query.collision_mask=3
	var hits:=motion_world.direct_space_state.intersect_shape(query,32)
	for hit in hits:
		if hit.rid==held_rid:return false
	return hits.size()<32 # Saturation fails conservatively; never hides geometry.

func _held_eye_comfort_clear(position:Vector3)->bool:
	# This 28cm preference starts repositioning before a turning held mesh
	# reaches the real 8cm near-plane envelope. It is never a collision bypass
	# and does not enlarge or alter any physical gameplay shape.
	if not is_instance_valid(game.held):return true
	var held_rid:=RID()
	for item in bodies:
		if item.owner==game.held:held_rid=item.get("motion_rid",RID());break
	if not held_rid.is_valid():return true
	return _held_rid_eye_clear(position,held_rid,.28)

func _motion_clear_ahead(position:Vector3,motion:Vector3)->bool:
	# Query only: anticipate the room that a retained pose will need. This never
	# changes collisions or permits a future/actual endpoint through geometry.
	if motion.length()<.025:return true
	var native_end:Vector3=game._camera_safe_position(position,position+motion)
	if native_end.distance_to(position+motion)>.02:return false
	return _presentation_safe_distance(position,motion,3,.08)+.02>=motion.length()

func _continuous_transition(best:Dictionary,points:Array,delta:float)->Dictionary:
	var displacement:Vector3=game.dog.global_position-last_dog
	var anchor:=last_position+displacement
	var focus_anchor:=last_focus+displacement
	var weight:=1.0-exp(-8.0*delta)
	var desired:Vector3=anchor.lerp(best.position,weight)
	desired=anchor.move_toward(desired,6.0*delta)
	var focus:Vector3=focus_anchor.lerp(best.focus,weight)
	# The interpolated focus must move too; changing only position can crop the
	# player and cause the old emergency branch to snap to the distant target.
	# A straight blend may cross the silhouette of a tall carried bone. Before
	# retaining the borderline old view, try a short swept lateral step around
	# it. Keep the chosen side briefly so successive blends do not oscillate.
	continuity_detour_seconds=maxf(0.0,continuity_detour_seconds-delta)
	if not is_instance_valid(game.held):continuity_detour_seconds=0.0
	var step:float=6.0*delta
	var right:=Vector3(cos(game.yaw),0,-sin(game.yaw))
	var poses:Array=[]
	if continuity_detour_seconds>0.0:
		poses.append([desired+continuity_detour*step,focus,"continued_lateral_detour",continuity_detour])
	poses.append([desired,focus,"interpolated",Vector3.ZERO])
	if is_instance_valid(game.held):
		for side in [1.0,-1.0]:
			poses.append([desired+right*side*step,focus,"lateral_visibility_detour",right*side])
	poses.append([anchor,focus_anchor,"translated_prior",Vector3.ZERO])
	for pose in poses:
		var position:Vector3=pose[0]
		var at:Vector3=pose[1]
		var native_end:Vector3=game._camera_safe_position(last_position,position)
		if native_end.distance_to(position)>.01:
			transition_rejections.append({"pose":"interpolated" if transition_rejections.is_empty() else "translated_prior","reason":"native_path","requested":[position.x,position.y,position.z],"native_end":[native_end.x,native_end.y,native_end.z]})
			continue
		var motion:=position-last_position
		var safe_distance_value:float=_presentation_safe_distance(last_position,motion,3,.08)
		if safe_distance_value+.01<motion.length():
			transition_rejections.append({"pose":"interpolated" if transition_rejections.is_empty() else "translated_prior","reason":"visual_motion_sweep","requested_m":motion.length(),"safe_m":safe_distance_value})
			continue
		var candidate:=_candidate(position,at,str(best.mode),points)
		if not candidate.get("endpoint_clear",false) or not _viewport_safe(candidate):
			transition_rejections.append({"pose":"interpolated" if transition_rejections.is_empty() else "translated_prior","reason":"endpoint_or_viewport","endpoint":candidate.get("endpoint_clear",false),"bounds":candidate.screen_bounds,"height":candidate.height_fraction,"all_front":candidate.all_front})
			continue
		# Preserve an opaque readable pose. A safe but occluded interpolation
		# must not replace an available clear target just for a motion statistic.
		if best.good and not candidate.good:
			transition_rejections.append({"pose":"interpolated" if transition_rejections.is_empty() else "translated_prior","reason":"opaque_readability","head":candidate.visible_points,"torso":candidate.torso_visible_points,"distance":candidate.distance,"opaque_endpoint":candidate.opaque_endpoint_clear,"visitor_blockers":candidate.get("visitor_blockers",[])})
			continue
		if str(pose[2])=="lateral_visibility_detour":
			continuity_detour=pose[3];continuity_detour_seconds=.35
		candidate["continuity_path"]=str(pose[2])
		return candidate
	return {}

func _player_points()->Array:
	var points:Array=[]
	for mesh:MeshInstance3D in player_meshes:
		var box:=mesh.mesh.get_aabb()
		for x in [0,1]:
			for y in [0,1]:
				for z in [0,1]:points.append(mesh.global_transform*(box.position+box.size*Vector3(x,y,z)))
	return points

func _inside_specimen(point:Vector3)->bool:
	for item in specimen_bounds:
		# Conservative volume veto for concave query meshes: never trust an empty
		# surface-overlap result as proof that a point inside its bounds is exterior.
		if item.bounds.has_point(item.owner.to_local(point)):return true
	return false

func _apply_player_alpha(alpha:float)->void:
	if alpha>=.999 and fade_materials.is_empty():return
	if fade_materials.is_empty():
		for mesh:MeshInstance3D in player_meshes:
			for surface in range(mesh.mesh.get_surface_count()):
				var source:Material=mesh.get_active_material(surface)
				if source is StandardMaterial3D:
					var material:StandardMaterial3D=source.duplicate()
					fade_materials.append({"mesh":mesh,"surface":surface,"source_override":mesh.get_surface_override_material(surface),"material_override":mesh.material_override,"material":material,"base_alpha":material.albedo_color.a,"base_transparency":material.transparency})
					mesh.material_override=null
					mesh.set_surface_override_material(surface,material)
	for item in fade_materials:
		item.material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if alpha<.999 else item.base_transparency
		item.material.albedo_color.a=item.base_alpha*alpha

func _visible_without_held(position:Vector3)->int:
	return _visible_excluding_held(position,[Vector3(0,.33,0),Vector3(0,.50,-.31),Vector3(0,.47,-.56)],true)

func _visible_excluding_held(position:Vector3,local_points:Array,exclude_held:bool,use_actual_furniture:bool=false)->int:
	if exclude_held and not is_instance_valid(game.held):return 0
	if exclude_held and not bool(game.held.get_meta("is_bone",false)):return 0
	var excluded:Array[RID]=[]
	for item in bodies:
		if item.owner==game.held and exclude_held:excluded.append(item.rid)
	if exclude_held and excluded.is_empty():return 0
	var visible:=0
	var inverse:Transform3D=game.cam.global_transform.affine_inverse()
	var half_y:=tan(deg_to_rad(game.cam.fov*.5))
	var aspect:float=game.cam.get_viewport().get_visible_rect().size.aspect()
	for local in local_points:
		var point:Vector3=game.dog.to_global(local)
		if not _point_on_screen(point,inverse,half_y,aspect):continue
		var hit:=visual_occlusion_ray(position,point,3,excluded)
		var native_ignored:Array[RID]=[]
		if use_actual_furniture and furniture_fade!=null:native_ignored=furniture_fade.native_exclusions(position,point)
		var native:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position,point,1,native_ignored))
		if hit.is_empty() and native.is_empty():visible+=1
	return visible

func _update_held_presentation(needed:bool,delta:float)->void:
	if not is_instance_valid(game.held):
		_restore_held_presentation()
		return
	# A single clear ray frame must not make a nearby held mesh opaque again
	# while the camera is still recovering. Require a short stable clear view.
	held_clear_seconds=held_clear_seconds+delta if not needed and held_restore_ready else 0.0
	if not held_materials.is_empty() and held_clear_seconds<.25:needed=true
	if needed and held_materials.is_empty():
		var id:=str(game.held.get_meta("semantic_id",""))
		if not game.visual_catalog.entries.has(id):return
		var entry:Dictionary=game.visual_catalog.entries[id]
		var visual:Node3D=entry.artwork if entry.artwork!=null else entry.greybox
		for mesh:MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh==null:continue
			var originals:Array=[]
			var materials:Array=[]
			var supported:=true
			for surface in range(mesh.mesh.get_surface_count()):
				var source:Material=mesh.get_active_material(surface)
				if not source is StandardMaterial3D:
					supported=false
					break
				originals.append(mesh.get_surface_override_material(surface))
				var material:StandardMaterial3D=source.duplicate()
				materials.append({"material":material,"base_alpha":material.albedo_color.a})
			if not supported:continue
			held_materials.append({"mesh":mesh,"material_override":mesh.material_override,"surface_overrides":originals,"materials":materials})
			mesh.material_override=null
			for surface in range(materials.size()):mesh.set_surface_override_material(surface,materials[surface].material)
		if not held_materials.is_empty():held_presented=game.held
	if held_materials.is_empty():
		held_alpha=1.0
		return
	held_alpha=move_toward(held_alpha,.18 if needed else 1.0,delta*5.0)
	if held_alpha>=.999 and not needed:
		_restore_held_presentation()
		return
	for item in held_materials:
		for material in item.materials:
			material.material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			material.material.albedo_color.a=material.base_alpha*held_alpha

func _record_held_presentation(delta:float)->void:
	if not is_instance_valid(game.held):return
	var id:=str(game.held.get_meta("semantic_id","unknown"))
	if not held_presentation_stats.has(id):held_presentation_stats[id]={"observed_seconds":0.0,"faded_seconds":0.0,"alpha_at_most_quarter_seconds":0.0,"max_continuous_fade_seconds":0.0}
	var row:Dictionary=held_presentation_stats[id]
	row.observed_seconds+=delta
	held_fade_dwell=held_fade_dwell+delta if held_alpha<.999 else 0.0
	row.faded_seconds+=delta if held_alpha<.999 else 0.0
	row.alpha_at_most_quarter_seconds+=delta if held_alpha<=.25 else 0.0
	row.max_continuous_fade_seconds=maxf(row.max_continuous_fade_seconds,held_fade_dwell)
	row.faded_fraction=row.faded_seconds/row.observed_seconds

func _restore_held_presentation()->void:
	var restored:=not held_materials.is_empty()
	for item in held_materials:
		if not is_instance_valid(item.mesh):continue
		item.mesh.material_override=item.material_override
		for surface in range(item.surface_overrides.size()):item.mesh.set_surface_override_material(surface,item.surface_overrides[surface])
	held_materials.clear()
	held_presented=null
	held_alpha=1.0
	held_clear_seconds=0.0
	held_restore_ready=false
	held_fade_dwell=0.0
	if restored:composition_stats["held_restore_count"]=int(composition_stats.get("held_restore_count",0))+1

func _exit_tree()->void:
	_restore_held_presentation()
	if furniture_fade!=null:furniture_fade.restore()
	super._exit_tree()
