extends Node
## Trusted A01-only skeletal playback. No imported scripts/controllers, no writes
## to gameplay roots, bodies, joints or collisions. Each GPU skin follows its own
## Skeleton3D; the original three bodies remain authoritative during knockdowns.
const RECIPE := "a01-lux-humanoid-skin-01"
const DEFAULT_MANIFEST := "res://styles/A01/runtime/animation/visitor-skins.json"
const PALETTE = preload("res://styles/A01/runtime/modules/c55f42a18825edd0-material_palette.gd")
var manifest_path:String=DEFAULT_MANIFEST
var game:Node
var actors:Array[Dictionary]=[]
var failures:Array=[]
var resource_cache:Dictionary={}
var elapsed:float=0.0
var camera_guard:Node
var camera_shapes:Array[Dictionary]=[]
var palette=PALETTE.new()
var manifest:Dictionary={}
var _physics_writes:int=0

func setup(source_game:Node,records:Dictionary={})->bool:
	game=source_game
	process_physics_priority=55
	actors.clear();failures.clear();camera_shapes.clear()
	if game==null or game.get("visual_catalog")==null:
		failures.append("missing_actual_visual_catalog");return false
	if records.is_empty():
		if not FileAccess.file_exists(manifest_path):failures.append("missing_skeletal_manifest");return false
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not parsed is Dictionary or parsed.get("kind")!="a01-visitor-skeletal-motion":
			failures.append("invalid_skeletal_manifest");return false
		manifest=parsed
	else:manifest={"kind":"a01-visitor-skeletal-motion","actors":records}
	var sources:Dictionary=manifest.get("actors",{})
	for visitor:Dictionary in game.visitors:
		var kind:String=actor_kind(str(visitor.name))
		if not sources.has(kind):continue
		var result:Dictionary=_prepare_resource(sources[kind])
		if not result.get("ok",false):failures.append({"actor":kind,"reason":result.get("error")});continue
		var row:Dictionary=_bind_actor(visitor,kind,result,sources[kind])
		if row.is_empty():continue
		actors.append(row)
	reset_pose()
	return not actors.is_empty() and failures.is_empty()

func actor_kind(who:String)->String:
	if who in ["小学生甲","小学生乙"]:return "child"
	if who in ["讲解员","保安"]:return "staff"
	return "adult"

func _prepare_resource(record:Dictionary)->Dictionary:
	var path:String=record.get("path",record.get("scene_path",""))
	var expected:String=record.get("sha256","")
	if not FileAccess.file_exists(path) or expected.length()!=64 or FileAccess.get_sha256(path)!=expected:
		return {"ok":false,"error":"missing_or_changed_skeletal_model"}
	var key:String=path+expected
	if resource_cache.has(key):return resource_cache[key]
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	if document.append_from_file(path,state)!=OK:return {"ok":false,"error":"gltf_import_failed"}
	var asset:Node3D=document.generate_scene(state)
	var skeletons:Array=[];var players:Array=[]
	for node:Node in [asset]+asset.find_children("*","",true,false):
		if node.get_script()!=null:
			asset.free();return {"ok":false,"error":"imported_script_rejected"}
		if node is Skeleton3D:skeletons.append(node)
		elif node is AnimationPlayer:players.append(node)
		elif node.get_class() not in ["Node3D","MeshInstance3D","BoneAttachment3D"]:
			asset.free();return {"ok":false,"error":"unsupported_imported_node_"+node.get_class()}
	if skeletons.size()!=1:
		asset.free();return {"ok":false,"error":"expected_one_skeleton"}
	var skeleton:Skeleton3D=skeletons[0]
	var clips:Dictionary={};var rejected:Array=[]
	for player:AnimationPlayer in players:
		var animation_root:Node=player.get_node(player.root_node)
		for label:StringName in player.get_animation_list():
			if str(label)=="RESET":continue
			var animation:Animation=player.get_animation(label)
			var tracks:Array=[]
			for index:int in range(animation.get_track_count()):
				var path_to:NodePath=animation.track_get_path(index)
				var names:String=path_to.get_concatenated_names()
				var target:Node=animation_root.get_node_or_null(NodePath(names))
				var type:int=animation.track_get_type(index)
				if target!=skeleton or path_to.get_subname_count()!=1 or type not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
					rejected.append({"clip":str(label),"path":str(path_to),"type":type});continue
				var bone:int=skeleton.find_bone(path_to.get_subname(0))
				if bone<0:continue
				tracks.append({"index":index,"bone":bone,"type":type})
			if not tracks.is_empty():clips[str(label)]={"animation":animation,"tracks":tracks,"length":animation.length}
	for player:AnimationPlayer in players:
		player.get_parent().remove_child(player);player.free()
	var neutral_face:Vector3=_neutral_face_vector(asset,skeleton)
	var skeleton_path:NodePath=asset.get_path_to(skeleton)
	var roles:Dictionary=_bone_roles(skeleton)
	var rest:Array[Transform3D]=[]
	var rest_global:Array[Transform3D]=[]
	for index:int in range(skeleton.get_bone_count()):
		rest.append(skeleton.get_bone_pose(index));rest_global.append(skeleton.get_bone_global_pose(index))
	_set_owner(asset,asset)
	var packed:=PackedScene.new()
	if packed.pack(asset)!=OK:asset.free();return {"ok":false,"error":"skin_pack_failed"}
	asset.free()
	var idle:String=_clip_name(clips,str(record.get("idle_animation","Idle_Loop")))
	var walk:String=_clip_name(clips,str(record.get("walk_animation","Walk_Loop")))
	if not bool(record.get("allow_rest_preview",false)) and (idle.is_empty() or walk.is_empty()):
		return {"ok":false,"error":"required_idle_walk_clips_missing","clips":clips.keys()}
	var result:Dictionary={"ok":true,"scene":packed,"skeleton_path":skeleton_path,"clips":clips,"idle":idle,"walk":walk,"roles":roles,"rest":rest,"rest_global":rest_global,"neutral_face_vector":neutral_face,"source_path":path,"source_sha256":expected,"rejected_nonbone_tracks":rejected}
	resource_cache[key]=result
	return result

func _clip_name(clips:Dictionary,wanted:String)->String:
	if clips.has(wanted):return wanted
	for key:String in clips:
		if key.to_lower().contains(wanted.to_lower()):return key
	return ""

func _bone_roles(skeleton:Skeleton3D)->Dictionary:
	var roles:Dictionary={}
	for label:String in ["Hips","Spine","Spine1","Spine2","Neck","Head","LeftShoulder","LeftArm","LeftForeArm","LeftHand","RightShoulder","RightArm","RightForeArm","RightHand","LeftUpLeg","LeftLeg","LeftFoot","LeftToeBase","RightUpLeg","RightLeg","RightFoot","RightToeBase"]:
		roles[label]=-1
		for index:int in range(skeleton.get_bone_count()):
			var clean:String=skeleton.get_bone_name(index).replace(":","_").replace("|","_")
			if clean==label or clean.ends_with("_"+label):roles[label]=index;break
	return roles

func _set_owner(node:Node,owner_root:Node)->void:
	if node!=owner_root:node.owner=owner_root
	node.scene_file_path=""
	for child:Node in node.get_children():_set_owner(child,owner_root)

func _bind_actor(visitor:Dictionary,kind:String,resource:Dictionary,record:Dictionary)->Dictionary:
	var old_roots:Dictionary={};var old_meshes:Array=[]
	for part:String in ["legs","torso","head"]:
		var id:String="visitor/%s/%s"%[visitor.name,part]
		var entry:Dictionary=game.visual_catalog.entries.get(id,{})
		var artwork:Node3D=entry.get("artwork")
		if artwork==null:failures.append({"name":visitor.name,"reason":"missing_existing_art_"+part});return {}
		old_roots[part]=artwork
		for node:Node in [artwork]+artwork.find_children("*","MeshInstance3D",true,false):
			if node is MeshInstance3D:old_meshes.append({"node":node,"visible":node.visible})
	var model:Node3D=(resource.scene as PackedScene).instantiate()
	model.name="A01SkeletalVisitor_"+kind
	(old_roots.torso as Node3D).add_child(model)
	for entry:Dictionary in old_meshes:(entry.node as MeshInstance3D).visible=false
	var skeleton:Skeleton3D=model.get_node(resource.skeleton_path)
	var row:Dictionary={"visitor":visitor,"kind":kind,"model":model,"skeleton":skeleton,"resource":resource,"roles":resource.roles,"old_meshes":old_meshes,"old_roots":old_roots,"phase":0.0,"idle_time":0.0,"walk":0.0,"clap":0.0,"mode":"idle","previous":visitor.root.global_position,"base_y":float(visitor.spawn.y),"was_down":false,"down_bones":[],"down_bodies":[],"meshes":[],"stride_m":float(record.get("stride_m",.52)),"fit":_fit(record),"floor_correction":0.0,"model_origin":Vector3.ZERO,"ragdoll_start_pose_error_m":0.0,"anatomy_only":bool(record.get("anatomy_only",false))}
	(model as Node3D).global_transform=(visitor.root as Node3D).global_transform*row.fit
	palette.apply_imported(model,"visitor_"+kind+"_skeletal")
	for node:Node in [model]+model.find_children("*","MeshInstance3D",true,false):
		if not node is MeshInstance3D or node.mesh==null:continue
		var mesh:MeshInstance3D=node
		if mesh.skin==null:failures.append({"name":visitor.name,"reason":"unskinned_mesh_in_bound_model"});continue
		var bounds:Dictionary=_bind_cells(mesh,skeleton)
		row.meshes.append({"node":mesh,"cells":bounds.cells,"sole_samples":bounds.soles,"rest_local_aabb":mesh.mesh.get_aabb()})
	return row

func _fit(record:Dictionary)->Transform3D:
	var fit:Dictionary=record.get("fit",{})
	var rotation:Array=fit.get("rotation_degrees",[0,0,0])
	var offset:Array=fit.get("offset",[0,0,0])
	var scale_value:float=float(fit.get("scale",1.0))
	return Transform3D(Basis.from_euler(Vector3(rotation[0],rotation[1],rotation[2])*PI/180.0).scaled(Vector3.ONE*scale_value),Vector3(offset[0],offset[1],offset[2]))

func _bind_cells(mesh:MeshInstance3D,skeleton:Skeleton3D)->Dictionary:
	var cells:Dictionary={};var soles:Array=[]
	var floor_y:float=mesh.mesh.get_aabb().position.y
	for surface:int in range(mesh.mesh.get_surface_count()):
		var arrays:Array=mesh.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var joints=arrays[Mesh.ARRAY_BONES];var weights=arrays[Mesh.ARRAY_WEIGHTS]
		if joints==null or weights==null or vertices.is_empty():continue
		var slots:int=joints.size()/vertices.size()
		var sole_candidates:Array=[]
		for index:int in range(vertices.size()):
			var influences:Array=[]
			for slot:int in range(slots):
				var at:int=index*slots+slot;var weight:float=weights[at]
				if weight<=0.0:continue
				var bind:int=joints[at]
				if bind<0 or bind>=mesh.skin.get_bind_count():continue
				var bone:int=mesh.skin.get_bind_bone(bind)
				if bone<0:bone=skeleton.find_bone(mesh.skin.get_bind_name(bind))
				if bone<0:continue
				var local:Vector3=mesh.skin.get_bind_pose(bind)*vertices[index]
				if not cells.has(bone):cells[bone]=AABB(local,Vector3.ZERO)
				else:cells[bone]=(cells[bone] as AABB).expand(local)
				influences.append({"bone":bone,"point":local,"weight":weight})
			if vertices[index].y<=floor_y+.018 and not influences.is_empty():sole_candidates.append(influences)
		# Sole correction uses actual weighted sole vertices, evenly bounded to
		# 80 samples per mesh; no arbitrary foot-center proxy.
		var step:int=maxi(1,ceili(float(sole_candidates.size())/80.0))
		for index:int in range(0,sole_candidates.size(),step):soles.append(sole_candidates[index])
	return {"cells":cells,"soles":soles}

func _physics_process(delta:float)->void:
	if not is_instance_valid(game):return
	elapsed+=delta
	for row:Dictionary in actors:_advance_actor(row,delta)
	if is_instance_valid(camera_guard):sync_camera_hulls(camera_guard)

func _advance_actor(row:Dictionary,delta:float)->void:
	var visitor:Dictionary=row.visitor
	var root:Node3D=visitor.root
	var position:Vector3=root.global_position
	var change:Vector3=position-(row.previous as Vector3);change.y=0.0
	row.previous=position
	var down:bool=bool(visitor.down) or not (visitor.torso as RigidBody3D).freeze
	if down:
		if not bool(row.was_down):_capture_ragdoll(row)
		row.was_down=true;_drive_ragdoll(row);row.mode="ragdoll_skin";return
	if bool(row.was_down) or change.length()>1.0:
		_reset_actor(row);change=Vector3.ZERO
	row.was_down=false
	var clapping:bool=_is_clapping(str(visitor.name))
	var speed:float=change.length()/maxf(delta,.000001)
	row.walk=move_toward(float(row.walk),clampf(speed/.35,0.0,1.0) if not clapping else 0.0,delta*6.0)
	row.clap=move_toward(float(row.clap),1.0 if clapping else 0.0,delta*5.0)
	row.phase=fposmod(float(row.phase)+change.length()/maxf(float(row.stride_m),.1),1.0)
	row.idle_time=float(row.idle_time)+delta
	var model:Node3D=row.model
	var pose:Transform3D=root.global_transform*row.fit
	# Shared gag root bob is gameplay state. Cancel it at the visual model only.
	if clapping or float(row.clap)>.001:pose.origin.y-=clampf(position.y-float(row.base_y),-.2,.2)
	model.global_transform=pose
	_apply_base_pose(row)
	_map_preset_forward(row)
	if not bool(row.anatomy_only):
		_limit_chest_pitch(row)
		_limit_head_pitch(row)
	_retarget_limbs_from_rest(row)
	if float(row.clap)>.001:_apply_clap(row,float(row.clap))
	_correct_sole_height(row)
	_update_render_bounds(row)
	row.mode="clap" if clapping else ("walk" if speed>.025 else "idle")
	row["speed"]=speed

func _sample_clip(resource:Dictionary,name:String,time:float)->Array[Transform3D]:
	var poses:Array[Transform3D]=[]
	poses.assign(resource.rest)
	if name.is_empty() or not resource.clips.has(name):return poses
	var clip:Dictionary=resource.clips[name]
	var animation:Animation=clip.animation
	var t:float=fposmod(time,maxf(float(clip.length),.001))
	for track:Dictionary in clip.tracks:
		var bone:int=track.bone
		var pose:Transform3D=poses[bone]
		match int(track.type):
			Animation.TYPE_POSITION_3D:pose.origin=animation.position_track_interpolate(track.index,t)
			Animation.TYPE_ROTATION_3D:pose.basis=Basis(animation.rotation_track_interpolate(track.index,t)).scaled(pose.basis.get_scale())
			Animation.TYPE_SCALE_3D:pose.basis=Basis(pose.basis.get_rotation_quaternion()).scaled(animation.scale_track_interpolate(track.index,t))
		poses[bone]=pose
	return poses

func _apply_base_pose(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	var resource:Dictionary=row.resource
	var idle:Array[Transform3D]=_sample_clip(resource,resource.idle,float(row.idle_time))
	var walk_length:float=float(resource.clips[resource.walk].length) if not str(resource.walk).is_empty() else 1.0
	var walking:Array[Transform3D]=_sample_clip(resource,resource.walk,float(row.phase)*walk_length)
	for index:int in range(skeleton.get_bone_count()):
		var pose:Transform3D=idle[index].interpolate_with(walking[index],float(row.walk))
		skeleton.set_bone_pose_position(index,pose.origin)
		skeleton.set_bone_pose_rotation(index,pose.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(index,pose.basis.get_scale())
	skeleton.force_update_all_bone_transforms()

func _node_transform(node:Node3D)->Transform3D:
	var result:Transform3D=node.transform
	var parent:Node=node.get_parent()
	while parent is Node3D:
		result=(parent as Node3D).transform*result
		parent=parent.get_parent()
	return result

func _rest_pole(rest:Array[Transform3D],upper:int,lower:int,end:int)->Vector3:
	var a:Vector3=rest[upper].origin;var b:Vector3=rest[lower].origin;var c:Vector3=rest[end].origin
	var line:Vector3=(c-a).normalized()
	return ((b-a)-line*(b-a).dot(line)).normalized()

func _solve_rest_chain(row:Dictionary,upper:int,lower:int,end:int,target:Vector3,pole:Vector3)->void:
	var skeleton:Skeleton3D=row.skeleton
	var rest:Array[Transform3D]=[];rest.assign(row.resource.rest_global)
	var a:Vector3=skeleton.get_bone_global_pose(upper).origin
	var b:Vector3=skeleton.get_bone_global_pose(lower).origin
	var c:Vector3=skeleton.get_bone_global_pose(end).origin
	var len_a:float=rest[upper].origin.distance_to(rest[lower].origin)
	var len_b:float=rest[lower].origin.distance_to(rest[end].origin)
	var axis:Vector3=(target-a).normalized()
	var distance:float=clampf(a.distance_to(target),.02,len_a+len_b-.0005)
	var bend:Vector3=(pole-axis*pole.dot(axis)).normalized()
	var along:float=(len_a*len_a-len_b*len_b+distance*distance)/(2.0*distance)
	var middle:Vector3=a+axis*along+bend*sqrt(maxf(0.0,len_a*len_a-along*along))
	# Rebuild orientation from the target rig's actual bind basis. A shortest
	# rotation of the faulty preset preserves its wrong 180-degree bone roll.
	var first:=Quaternion((rest[lower].origin-rest[upper].origin).normalized(),(middle-a).normalized())*rest[upper].basis.get_rotation_quaternion()
	_global_rotation(skeleton,upper,first)
	b=skeleton.get_bone_global_pose(lower).origin
	var second:=Quaternion((rest[end].origin-rest[lower].origin).normalized(),(target-b).normalized())*rest[lower].basis.get_rotation_quaternion()
	_global_rotation(skeleton,lower,second)

func _map_preset_forward(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	var raw:Array[Transform3D]=[]
	for index:int in range(skeleton.get_bone_count()):raw.append(skeleton.get_bone_global_pose(index))
	row["raw_global_pose"]=raw
	var rest:Array[Transform3D]=[];rest.assign(row.resource.rest_global)
	var mirror:=Basis(Vector3.RIGHT,Vector3.UP,Vector3.BACK*-1.0)
	# The observed service preset walks +Z while this target rig and real face
	# point -Z. Convert deformation deltas, preserving Left/Right and rest axes.
	for label:String in ["Hips","Spine","Spine1","Spine2","Neck","Head","LeftShoulder","RightShoulder"]:
		var bone:int=row.roles.get(label,-1)
		if bone<0:continue
		var delta:Basis=raw[bone].basis*rest[bone].basis.inverse()
		var target:Basis=mirror*delta*mirror*rest[bone].basis
		_global_rotation(skeleton,bone,target.get_rotation_quaternion())
		if label=="Hips":
			var position:Vector3=raw[bone].origin
			position.z=rest[bone].origin.z-(position.z-rest[bone].origin.z)
			skeleton.set_bone_pose_position(bone,position)
			skeleton.force_update_all_bone_transforms()

func _retarget_limbs_from_rest(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	var rest:Array[Transform3D]=[];rest.assign(row.resource.rest_global)
	var hips:int=row.roles.get("Hips",-1);var chest:int=row.roles.get("Spine2",-1)
	for side:String in ["Left","Right"]:
		var thigh:int=row.roles.get(side+"UpLeg",-1);var shin:int=row.roles.get(side+"Leg",-1);var foot:int=row.roles.get(side+"Foot",-1)
		if mini(thigh,mini(shin,foot))>=0:
			var raw:Array[Transform3D]=[];raw.assign(row.raw_global_pose)
			var offset:Vector3=raw[foot].origin-raw[thigh].origin
			offset.z=-offset.z
			var target:Vector3=skeleton.get_bone_global_pose(thigh).origin+offset
			target.x=rest[foot].origin.x*.94
			var pole:Vector3=_rest_pole(rest,thigh,shin,foot)
			if hips>=0:pole=(skeleton.get_bone_global_pose(hips).basis*rest[hips].basis.inverse())*pole
			_solve_rest_chain(row,thigh,shin,foot,target,pole)
			# The plush shoe remains aligned with its own bind sole, so ankle
			# roll from the incompatible preset cannot point both shoes upright.
			_global_rotation(skeleton,foot,rest[foot].basis.get_rotation_quaternion())
		var arm:int=row.roles.get(side+"Arm",-1);var fore:int=row.roles.get(side+"ForeArm",-1);var hand:int=row.roles.get(side+"Hand",-1)
		if mini(arm,mini(fore,hand))>=0:
			var raw:Array[Transform3D]=[];raw.assign(row.raw_global_pose)
			var offset:Vector3=raw[hand].origin-raw[arm].origin
			offset.z=-offset.z
			var shoulder:Vector3=skeleton.get_bone_global_pose(arm).origin
			var target:Vector3=shoulder+offset
			target.x=signf(rest[arm].origin.x)*(absf(rest[arm].origin.x)+.11)
			var pole:Vector3=_rest_pole(rest,arm,fore,hand)
			if chest>=0:pole=(skeleton.get_bone_global_pose(chest).basis*rest[chest].basis.inverse())*pole
			_solve_rest_chain(row,arm,fore,hand,target,pole)
			var rotation:Quaternion=skeleton.get_bone_global_pose(fore).basis.get_rotation_quaternion()*rest[fore].basis.get_rotation_quaternion().inverse()*rest[hand].basis.get_rotation_quaternion()
			_global_rotation(skeleton,hand,rotation)

func _neutral_face_vector(asset:Node3D,skeleton:Skeleton3D)->Vector3:
	# Real head-surface marker, independently measured again in the QA report.
	for node:Node in asset.find_children("*","MeshInstance3D",true,false):
		if not node is MeshInstance3D or node.mesh==null:continue
		var bounds:AABB=node.mesh.get_aabb()
		if bounds.position.y<1.2:continue
		var front:=Vector3.ZERO;var back:=Vector3.ZERO;var nf:int=0;var nb:int=0
		var relative:Transform3D=_node_transform(skeleton).affine_inverse()*_node_transform(node)
		for surface:int in range(node.mesh.get_surface_count()):
			for p:Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if absf(p.x-bounds.get_center().x)>bounds.size.x*.22 or p.y<bounds.position.y+bounds.size.y*.12 or p.y>bounds.position.y+bounds.size.y*.60:continue
				if p.z<bounds.position.z+bounds.size.z*.20:front+=relative*p;nf+=1
				if p.z>bounds.end.z-bounds.size.z*.20:back+=relative*p;nb+=1
		if nf>0 and nb>0:return (front/nf-back/nb).normalized()
	return Vector3.FORWARD

func _global_rotation(skeleton:Skeleton3D,bone:int,rotation:Quaternion)->void:
	var parent:int=skeleton.get_bone_parent(bone)
	var parent_rotation:Quaternion=skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent>=0 else Quaternion.IDENTITY
	skeleton.set_bone_pose_rotation(bone,parent_rotation.inverse()*rotation)
	skeleton.force_update_all_bone_transforms()

func _pitch_limited_forward(forward:Vector3,pitch:float)->Vector3:
	var yaw:float=atan2(forward.x,-forward.z)
	return Vector3(sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))

func _limit_chest_pitch(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	var chest:int=row.roles.get("Spine2",-1);var spine:int=row.roles.get("Spine",-1)
	if mini(chest,spine)<0:return
	var rest:Transform3D=row.resource.rest_global[chest]
	var current:Transform3D=skeleton.get_bone_global_pose(chest)
	var forward:Vector3=(current.basis*rest.basis.inverse())*Vector3.FORWARD
	var pitch:float=atan2(forward.y,Vector2(forward.x,forward.z).length())
	var target:Vector3=_pitch_limited_forward(forward,clampf(pitch,deg_to_rad(-4),deg_to_rad(4)))
	var correction:=Quaternion(forward.normalized(),target.normalized())
	var rotation:Quaternion=correction*skeleton.get_bone_global_pose(spine).basis.get_rotation_quaternion()
	_global_rotation(skeleton,spine,rotation)
	row["chest_pitch_removed_degrees"]=rad_to_deg(pitch-clampf(pitch,deg_to_rad(-4),deg_to_rad(4)))

func _limit_head_pitch(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	var head:int=row.roles.get("Head",-1)
	if head<0:return
	var rest:Transform3D=row.resource.rest_global[head]
	var current:Transform3D=skeleton.get_bone_global_pose(head)
	var neutral:Vector3=row.resource.neutral_face_vector
	var forward:Vector3=(current.basis*rest.basis.inverse())*neutral
	var neutral_pitch:float=atan2(neutral.y,Vector2(neutral.x,neutral.z).length())
	var pitch:float=atan2(forward.y,Vector2(forward.x,forward.z).length())
	var wanted:float=neutral_pitch+clampf(pitch-neutral_pitch,deg_to_rad(-3),deg_to_rad(3))
	var target:Vector3=_pitch_limited_forward(forward,wanted)
	var correction:=Quaternion(forward.normalized(),target.normalized())
	_global_rotation(skeleton,head,correction*current.basis.get_rotation_quaternion())
	row["head_pitch_removed_degrees"]=rad_to_deg(pitch-wanted)

func _stabilize_legs(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	for side:String in ["Left","Right"]:
		var upper:int=row.roles.get(side+"UpLeg",-1);var lower:int=row.roles.get(side+"Leg",-1);var foot:int=row.roles.get(side+"Foot",-1)
		if mini(upper,mini(lower,foot))<0:continue
		var hip:Vector3=skeleton.get_bone_global_pose(upper).origin
		var knee:Vector3=skeleton.get_bone_global_pose(lower).origin
		var ankle:Vector3=skeleton.get_bone_global_pose(foot).origin
		var rest:Transform3D=row.resource.rest_global[foot]
		var target:Vector3=ankle
		target.x=rest.origin.x*.94
		target.z=rest.origin.z+(target.z-rest.origin.z)*.66
		target.y=rest.origin.y+(target.y-rest.origin.y)*.60
		var a:float=hip.distance_to(knee);var b:float=knee.distance_to(ankle)
		var line:Vector3=target-hip;var distance:float=clampf(line.length(),.02,a+b-.0005)
		var direction:Vector3=line.normalized()
		var pole:Vector3=knee-hip
		var bend:Vector3=(pole-direction*pole.dot(direction)).normalized()
		if bend.length_squared()<.1:bend=Vector3.FORWARD
		var along:float=(a*a-b*b+distance*distance)/(2.0*distance)
		var knee_target:Vector3=hip+direction*along+bend*sqrt(maxf(0.0,a*a-along*along))
		_aim_bone(skeleton,upper,knee-hip,knee_target-hip,1.0)
		skeleton.force_update_all_bone_transforms()
		knee=skeleton.get_bone_global_pose(lower).origin;ankle=skeleton.get_bone_global_pose(foot).origin
		_aim_bone(skeleton,lower,ankle-knee,target-knee,1.0)
		skeleton.force_update_all_bone_transforms()
		# Keep a plush shoe's broad sole stable. The supplied foot pitch is
		# attenuated only while the foot is airborne; stance is bind-floor flat.
		var current:Transform3D=skeleton.get_bone_global_pose(foot)
		var other_name:String="RightFoot" if side=="Left" else "LeftFoot"
		var other:int=row.roles.get(other_name,-1)
		var lift:float=maxf(0.0,current.origin.y-skeleton.get_bone_global_pose(other).origin.y) if other>=0 else 0.0
		var keep:float=.22*smoothstep(.025,.15,lift)*float(row.walk)
		var rotation:Quaternion=rest.basis.get_rotation_quaternion().slerp(current.basis.get_rotation_quaternion(),keep)
		var parent:int=skeleton.get_bone_parent(foot)
		var parent_rotation:Quaternion=skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent>=0 else Quaternion.IDENTITY
		skeleton.set_bone_pose_rotation(foot,parent_rotation.inverse()*rotation)
		skeleton.force_update_all_bone_transforms()

func _sleeve_clearance(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	for side:String in ["Left","Right"]:
		var upper:int=row.roles.get(side+"Arm",-1);var lower:int=row.roles.get(side+"ForeArm",-1)
		if mini(upper,lower)<0:continue
		var shoulder:Vector3=skeleton.get_bone_global_pose(upper).origin
		var vector:Vector3=skeleton.get_bone_global_pose(lower).origin-shoulder
		var sign_x:float=signf(shoulder.x)
		var target:Vector3=vector+Vector3(sign_x*.25,0,-.04)*vector.length()
		_aim_bone(skeleton,upper,vector,target,1.0)
		skeleton.force_update_all_bone_transforms()

func _apply_clap(row:Dictionary,weight:float)->void:
	var skeleton:Skeleton3D=row.skeleton
	var roles:Dictionary=row.roles
	var closing:float=.5-.5*cos(elapsed*TAU*2.15)
	# Both targets share the same chest-height plane and approach the midline.
	var chest:int=roles.get("Spine2",-1)
	var chest_y:float=skeleton.get_bone_global_pose(chest).origin.y if chest>=0 else 1.15
	for side:String in ["Left","Right"]:
		var arm:int=roles.get(side+"Arm",-1);var forearm:int=roles.get(side+"ForeArm",-1);var hand:int=roles.get(side+"Hand",-1)
		if mini(arm,mini(forearm,hand))<0:continue
		var shoulder:Vector3=skeleton.get_bone_global_pose(arm).origin
		var elbow:Vector3=skeleton.get_bone_global_pose(forearm).origin
		var wrist:Vector3=skeleton.get_bone_global_pose(hand).origin
		var sign_x:float=signf(shoulder.x)
		var target:=Vector3(sign_x*lerpf(.145,.028,closing),chest_y-.10,-.28)
		var upper:float=shoulder.distance_to(elbow);var lower:float=elbow.distance_to(wrist)
		var line:Vector3=target-shoulder;var distance:float=clampf(line.length(),.02,upper+lower-.001)
		var direction:Vector3=line.normalized()
		var pole:=Vector3(sign_x*.25,-.8,-.05)
		var bend:Vector3=(pole-direction*pole.dot(direction)).normalized()
		var along:float=(upper*upper-lower*lower+distance*distance)/(2.0*distance)
		var height:float=sqrt(maxf(0.0,upper*upper-along*along))
		var desired_elbow:Vector3=shoulder+direction*along+bend*height
		_aim_bone(skeleton,arm,elbow-shoulder,desired_elbow-shoulder,weight)
		skeleton.force_update_all_bone_transforms()
		elbow=skeleton.get_bone_global_pose(forearm).origin;wrist=skeleton.get_bone_global_pose(hand).origin
		_aim_bone(skeleton,forearm,wrist-elbow,target-elbow,weight)
		skeleton.force_update_all_bone_transforms()

func _aim_bone(skeleton:Skeleton3D,bone:int,current:Vector3,target:Vector3,weight:float)->void:
	if current.length_squared()<.000001 or target.length_squared()<.000001:return
	var pose:Transform3D=skeleton.get_bone_global_pose(bone)
	var aimed:Quaternion=Quaternion(current.normalized(),target.normalized())*pose.basis.get_rotation_quaternion()
	var rotation:Quaternion=pose.basis.get_rotation_quaternion().slerp(aimed,weight)
	var parent:int=skeleton.get_bone_parent(bone)
	var parent_rotation:Quaternion=skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent>=0 else Quaternion.IDENTITY
	skeleton.set_bone_pose_rotation(bone,parent_rotation.inverse()*rotation)

func _correct_sole_height(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	var low:float=INF
	for mesh_row:Dictionary in row.meshes:
		for sample:Array in mesh_row.sole_samples:
			var point:=Vector3.ZERO
			for influence:Dictionary in sample:point+=(skeleton.get_bone_global_pose(influence.bone)*influence.point)*float(influence.weight)
			low=minf(low,(skeleton.global_transform*point).y)
	if not is_finite(low):return
	var floor_y:float=(row.visitor.root as Node3D).global_position.y
	if float(row.clap)>.001:floor_y=float(row.base_y)
	var adjustment:float=clampf(floor_y-low,-.25,.25)
	(row.model as Node3D).global_position.y+=adjustment
	row.floor_correction=adjustment
	row["support_error_m"]=low+adjustment-floor_y

func _capture_ragdoll(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	row.down_bones.clear();row.down_bodies.clear()
	for body:RigidBody3D in row.visitor.parts:row.down_bodies.append(body.global_transform)
	for index:int in range(skeleton.get_bone_count()):row.down_bones.append(skeleton.global_transform*skeleton.get_bone_global_pose(index))
	row.walk=0.0;row.clap=0.0

func _ragdoll_bucket(skeleton:Skeleton3D,index:int)->int:
	var name:String=skeleton.get_bone_name(index).to_lower()
	if name.contains("head"):return 2
	if name.contains("hips") or name.contains("pelvis") or name.contains("upleg") or name.contains("foot") or name.contains("toebase") or name.ends_with("_leg"):return 0
	return 1

func _drive_ragdoll(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	var desired:Array[Transform3D]=[]
	var inverse:Transform3D=skeleton.global_transform.affine_inverse()
	for index:int in range(skeleton.get_bone_count()):
		var bucket:int=_ragdoll_bucket(skeleton,index)
		var body:RigidBody3D=row.visitor.parts[bucket]
		var moved:Transform3D=body.global_transform*(row.down_bodies[bucket] as Transform3D).affine_inverse()*(row.down_bones[index] as Transform3D)
		desired.append(inverse*moved)
	for index:int in range(skeleton.get_bone_count()):
		var parent:int=skeleton.get_bone_parent(index)
		var local:Transform3D=(desired[parent].affine_inverse()*desired[index]) if parent>=0 else desired[index]
		skeleton.set_bone_pose_position(index,local.origin);skeleton.set_bone_pose_rotation(index,local.basis.get_rotation_quaternion());skeleton.set_bone_pose_scale(index,local.basis.get_scale())
	skeleton.force_update_all_bone_transforms()
	_update_render_bounds(row)

func _update_render_bounds(row:Dictionary)->void:
	var skeleton:Skeleton3D=row.skeleton
	for mesh_row:Dictionary in row.meshes:
		var mesh:MeshInstance3D=mesh_row.node
		var relative:Transform3D=mesh.global_transform.affine_inverse()*skeleton.global_transform
		var bounds:=AABB();var first:=true
		for bone:int in mesh_row.cells:
			var cell:AABB=mesh_row.cells[bone]
			var moved:AABB=relative*skeleton.get_bone_global_pose(bone)*cell
			bounds=moved if first else bounds.merge(moved);first=false
		if first:continue
		bounds=bounds.grow(.008)
		mesh.custom_aabb=bounds
		mesh.set_meta("a01_motion_local_aabb",bounds)
		mesh.set_meta("a01_motion_root_offset_world_max",Vector3.ZERO)
		mesh_row["current_local_aabb"]=bounds

func bind_camera_guard(guard:Node)->void:
	camera_guard=guard;camera_shapes.clear()
	var ours:Dictionary={}
	for row:Dictionary in actors:
		for mesh_row:Dictionary in row.meshes:ours[mesh_row.node]=mesh_row
	for item:Dictionary in guard.dynamic_motion_shapes:
		if not ours.has(item.mesh):continue
		var shape:=ConvexPolygonShape3D.new()
		shape.points=_box_points((ours[item.mesh] as Dictionary).get("current_local_aabb",item.mesh.mesh.get_aabb()))
		PhysicsServer3D.body_set_shape(item.rid,item.index,shape.get_rid())
		guard.shapes.append(shape)
		camera_shapes.append({"shape":shape,"mesh_row":ours[item.mesh]})
	sync_camera_hulls(guard)

func sync_camera_hulls(_guard:Node)->void:
	for item:Dictionary in camera_shapes:
		var mesh_row:Dictionary=item.mesh_row
		if mesh_row.has("current_local_aabb"):(item.shape as ConvexPolygonShape3D).points=_box_points(mesh_row.current_local_aabb)

func _box_points(bounds:AABB)->PackedVector3Array:
	var result:=PackedVector3Array()
	for x:int in [0,1]:
		for y:int in [0,1]:
			for z:int in [0,1]:result.append(bounds.position+bounds.size*Vector3(x,y,z))
	return result

func _is_clapping(who:String)->bool:
	if int(game.gag2_phase)!=0:return (int(game.gag2_phase)==3 and who=="小学生甲") or (int(game.gag2_phase)==4 and who in ["小学生甲","保安"])
	return int(game.gag_phase)==3

func _reset_actor(row:Dictionary)->void:
	row.phase=0.0;row.idle_time=0.0;row.walk=0.0;row.clap=0.0;row.was_down=false
	row.previous=(row.visitor.root as Node3D).global_position
	(row.model as Node3D).global_transform=(row.visitor.root as Node3D).global_transform*row.fit
	_apply_base_pose(row)
	_map_preset_forward(row)
	if not bool(row.anatomy_only):
		_limit_chest_pitch(row);_limit_head_pitch(row)
	_retarget_limbs_from_rest(row)
	_correct_sole_height(row);_update_render_bounds(row)
	row.mode="idle"

func reset_pose()->void:
	for row:Dictionary in actors:_reset_actor(row)

func snapshot()->Array:
	var output:Array=[]
	for row:Dictionary in actors:output.append({"name":row.visitor.name,"kind":row.kind,"mode":row.mode,"walk":row.walk,"clap":row.clap,"phase":row.phase,"floor_correction":row.floor_correction,"bones":(row.skeleton as Skeleton3D).get_bone_count(),"support_error_m":row.get("support_error_m",0.0)})
	return output

func motion_contract()->Dictionary:
	var sources:Array=[]
	for resource:Dictionary in resource_cache.values():sources.append({"path":resource.source_path,"sha256":resource.source_sha256,"clips":resource.clips.keys(),"ignored_nonbone_tracks":resource.rejected_nonbone_tracks})
	return {"recipe":RECIPE,"actors":actors.size(),"cached_models":resource_cache.size(),"failures":failures.duplicate(true),"route":"Lux_humanoid_skin_and_bone_only_clip_sampling","sources":sources,"physics_transforms_written":false,"physics_write_count":_physics_writes,"ragdoll_owner":"unchanged_three_native_bodies","camera_hulls":"current_skin_influence_cells_in_independent_query_world","camera_shapes":camera_shapes.size(),"native_visual_qualification":"pending","limits":["Per-bone influence-cell bounds are conservative, not GPU triangle readback.","Sole floor correction samples actual sole vertices; stance sliding and hand contact require footage review.","Clap is a local two-bone IK layer over supplier idle/walk."]}

func _exit_tree()->void:
	for row:Dictionary in actors:
		for old:Dictionary in row.old_meshes:
			if is_instance_valid(old.node):old.node.visible=old.visible
		if is_instance_valid(row.model):row.model.queue_free()
