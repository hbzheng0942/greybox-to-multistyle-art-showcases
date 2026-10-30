extends Node
## A01-only visual motion, installed after the real generated art.
## No Skeleton, supplier rig, collision or visitor-state mutation. Two shared
## blend targets per garment supply a small stylized walk/clap vocabulary.
## The original down/recovery logic remains the only authority on ragdolls.
const RECIPE := "a01-local-visitor-motion-01"
var game:Node
var actors:Array[Dictionary]=[]
var mesh_cache:Dictionary={}
var failures:Array=[]
var elapsed:float=0.0
var motion_bounds:Array=[]

func setup(source_game:Node)->bool:
	game=source_game
	process_physics_priority=55
	actors.clear()
	failures.clear()
	motion_bounds.clear()
	if game==null or game.get("visual_catalog")==null:
		failures.append("missing_actual_visual_catalog")
		return false
	for visitor in game.visitors:
		var row:Dictionary={"visitor":visitor,"visuals":{},"rests":{},"meshes":{},"phase":0.0,"walk":0.0,"clap":0.0,"previous":visitor.root.global_position,"base_y":float(visitor.spawn.y),"mode":"idle"}
		for part in ["legs","torso","head"]:
			var semantic:String="visitor/%s/%s"%[visitor.name,part]
			var entry:Dictionary=game.visual_catalog.entries.get(semantic,{})
			var visual:Node3D=entry.get("visual")
			var artwork:Node3D=entry.get("artwork")
			if visual==null or artwork==null:
				failures.append({"semantic":semantic,"reason":"missing_installed_artwork"})
				continue
			row.visuals[part]=visual
			row.rests[part]=visual.transform
			row.meshes[part]=[]
			if part=="head":continue
			for candidate in [artwork]+artwork.find_children("*","MeshInstance3D",true,false):
				if not candidate is MeshInstance3D or candidate.mesh==null:continue
				var mesh_node:MeshInstance3D=candidate
				var relative:Transform3D=visual.global_transform.affine_inverse()*mesh_node.global_transform
				var key:String=str(mesh_node.mesh.get_instance_id())+":"+part+":"+str(relative)
				if not mesh_cache.has(key):mesh_cache[key]=_make_motion_mesh(mesh_node.mesh,relative,part)
				var result:Dictionary=mesh_cache[key]
				if result.get("status")!="ready":
					failures.append({"semantic":semantic,"reason":result.get("reason")})
					continue
				mesh_node.mesh=result.mesh
				mesh_node.custom_aabb=result.animated_local_aabb
				mesh_node.set_meta("a01_motion_local_aabb",result.animated_local_aabb)
				mesh_node.set_meta("a01_motion_root_offset_world_max",Vector3(0,.20,0))
				motion_bounds.append({"semantic":semantic,"mesh":str(artwork.get_path_to(mesh_node)),"base_local_aabb":_box(result.base_local_aabb),"animated_local_aabb":_box(result.animated_local_aabb),"maximum_visual_root_world_y_offset":.20,"query_contract":"conservative motion hull; base mesh faces are not live deformed triangles"})
				row.meshes[part].append(mesh_node)
		actors.append(row)
	reset_pose()
	return failures.is_empty()

func _make_motion_mesh(source:Mesh,relative:Transform3D,part:String)->Dictionary:
	if source.get_blend_shape_count()>0:return {"status":"unsupported","reason":"existing_blend_shapes_are_preserved"}
	var bounds:=AABB()
	var first:bool=true
	for surface in range(source.get_surface_count()):
		if source.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:return {"status":"unsupported","reason":"non_triangle_garment"}
		for p in source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var q:Vector3=relative*p
			bounds=AABB(q,Vector3.ZERO) if first else bounds.expand(q)
			first=false
	if first or bounds.size.y<.05:return {"status":"unsupported","reason":"empty_or_unexpected_garment_bounds"}
	var output:=ArrayMesh.new()
	output.resource_name="A01VisualMotion_"+part
	output.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED
	output.add_blend_shape("StepLeft" if part=="legs" else "HandsReady")
	output.add_blend_shape("StepRight" if part=="legs" else "HandsTogether")
	var inverse:Transform3D=relative.affine_inverse()
	var animated_local_aabb:AABB=source.get_aabb()
	for surface in range(source.get_surface_count()):
		var arrays:Array=source.surface_get_arrays(surface)
		var original:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in range(original.size()):indices.append(i)
		var targets:Array=[]
		for pose in range(2):
			var points:=PackedVector3Array()
			var coordinates:=PackedVector3Array()
			for point in original:coordinates.append(relative*point)
			for point in coordinates:
				points.append(_leg_pose(point,bounds,1.0 if pose==0 else -1.0) if part=="legs" else _arm_pose(point,bounds,pose==1))
			if part=="legs":_protect_soles(points,coordinates,bounds,pose)
			for i in range(points.size()):
				points[i]=inverse*points[i]
				animated_local_aabb=animated_local_aabb.expand(points[i])
			var normals:PackedVector3Array=_normals(points,indices,arrays[Mesh.ARRAY_NORMAL],original)
			var target:Array=[]
			target.resize(Mesh.ARRAY_MAX)
			target[Mesh.ARRAY_VERTEX]=points
			target[Mesh.ARRAY_NORMAL]=normals
			if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
				var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT].duplicate()
				if tangents.size()==points.size()*4:
					for i in range(points.size()):
						var t:=Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])
						t=(t-normals[i]*t.dot(normals[i])).normalized()
						tangents[i*4]=t.x;tangents[i*4+1]=t.y;tangents[i*4+2]=t.z
					target[Mesh.ARRAY_TANGENT]=tangents
			targets.append(target)
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,targets)
		output.surface_set_material(surface,source.surface_get_material(surface))
	output.custom_aabb=animated_local_aabb
	return {"status":"ready","mesh":output,"bounds":bounds,"base_local_aabb":source.get_aabb(),"animated_local_aabb":animated_local_aabb,"original_uv_indices_materials_preserved":true}

func _box(box:AABB)->Dictionary:
	return {"min":[box.position.x,box.position.y,box.position.z],"size":[box.size.x,box.size.y,box.size.z]}

func _leg_pose(point:Vector3,bounds:AABB,direction:float)->Vector3:
	var center:Vector3=bounds.get_center()
	var side:float=-1.0 if point.x<center.x else 1.0
	var q:float=(point.y-bounds.position.y)/bounds.size.y
	var weight:float=1.0-smoothstep(.66,.89,q)
	var hip:=Vector3(center.x+side*bounds.size.x*.22,bounds.position.y+bounds.size.y*.85,center.z)
	var turned:Vector3=hip+Basis(Vector3.RIGHT,side*direction*.22)*(point-hip)
	return point.lerp(turned,weight)

func _protect_soles(points:PackedVector3Array,original:PackedVector3Array,bounds:AABB,pose:int)->void:
	var center:Vector3=bounds.get_center()
	var before:Array[float]=[INF,INF]
	var after:Array[float]=[INF,INF]
	for i in range(points.size()):
		var side:int=0 if original[i].x<center.x else 1
		before[side]=minf(before[side],original[i].y)
		after[side]=minf(after[side],points[i].y)
	for i in range(points.size()):
		var side:int=0 if original[i].x<center.x else 1
		var weight:float=1.0-smoothstep(.66,.89,(original[i].y-bounds.position.y)/bounds.size.y)
		var clearance:float=.026 if side==pose else 0.0
		points[i].y+=(maxf(0.0,before[side]-after[side])+clearance)*weight

func _arm_pose(point:Vector3,bounds:AABB,closed:bool)->Vector3:
	var center:Vector3=bounds.get_center()
	var side:float=-1.0 if point.x<center.x else 1.0
	var qy:float=(point.y-bounds.position.y)/bounds.size.y
	var radial:float=absf(point.x-center.x)/maxf(bounds.size.x*.5,.00001)
	# The middle jacket, neck and waist stay in place; deformation blends
	# through the outside sleeve, without cutting the garment or adding a rig.
	var weight:float=smoothstep(.55,.76,radial)*(1.0-smoothstep(.91,1.0,qy))
	var shoulder:=Vector3(center.x+side*bounds.size.x*.275,bounds.position.y+bounds.size.y*.83,center.z)
	var shoulder_turn:=Basis(Vector3.RIGHT,.65)
	var raised:Vector3=shoulder+shoulder_turn*(point-shoulder)
	var elbow:Vector3=shoulder+shoulder_turn*Vector3(0,-bounds.size.y*.39,0)
	var elbow_weight:float=1.0-smoothstep(.36,.54,qy)
	var folded:Vector3=elbow+Basis(Vector3.UP,side*(1.47 if closed else .25))*Basis(Vector3.RIGHT,.85)*(raised-elbow)
	var target:Vector3=raised.lerp(folded,elbow_weight)
	return point.lerp(target,weight)

func _normals(points:PackedVector3Array,indices:PackedInt32Array,old:PackedVector3Array,original:PackedVector3Array)->PackedVector3Array:
	var values:=PackedVector3Array()
	values.resize(points.size())
	for j in range(0,indices.size()-2,3):
		var a:int=indices[j];var b:int=indices[j+1];var c:int=indices[j+2]
		var normal:Vector3=(points[b]-points[a]).cross(points[c]-points[a])
		var source_face:Vector3=(original[b]-original[a]).cross(original[c]-original[a])
		if a<old.size() and source_face.dot(old[a])<0:normal=-normal
		values[a]+=normal;values[b]+=normal;values[c]+=normal
	var welded:Dictionary={}
	var keys:Array[Vector3i]=[]
	for i in range(points.size()):
		var p:Vector3=points[i]*1000000.0
		var key:=Vector3i(roundi(p.x),roundi(p.y),roundi(p.z))
		keys.append(key)
		welded[key]=welded.get(key,Vector3.ZERO)+values[i]
	for i in range(values.size()):
		var n:Vector3=welded[keys[i]]
		values[i]=old[i] if points[i].distance_squared_to(original[i])<.00000000000001 else (n.normalized() if n.length_squared()>.000000000001 else old[i])
	return values

func _physics_process(delta:float)->void:
	if game==null:return
	elapsed+=delta
	for row in actors:
		var v:Dictionary=row.visitor
		var root:Node3D=v.root
		var torso:RigidBody3D=v.torso
		var position:Vector3=root.global_position
		var change:Vector3=position-(row.previous as Vector3)
		change.y=0.0
		row.previous=position
		if bool(v.down) or not torso.freeze:
			_reset_actor(row)
			row.mode="ragdoll_passive"
			continue
		if change.length()>1.0:
			_reset_actor(row)
			row.mode="restored"
			continue
		var clapping:bool=_is_clapping(str(v.name))
		var speed:float=change.length()/maxf(delta,.000001)
		row.walk=move_toward(float(row.walk),clampf(speed/.85,0.0,1.0) if not clapping else 0.0,delta*5.0)
		row.clap=move_toward(float(row.clap),1.0 if clapping else 0.0,delta*5.0)
		row.phase=fposmod(float(row.phase)+minf(change.length()/.52,delta*3.6)*TAU,TAU)
		var stride:float=sin(float(row.phase))*float(row.walk)
		_set_blends(row.meshes.get("legs",[]),maxf(0,stride),maxf(0,-stride))
		var closing:float=.5-.5*cos(elapsed*TAU*3.2)
		_set_blends(row.meshes.get("torso",[]),float(row.clap)*(1.0-closing),float(row.clap)*closing)
		# Shared gag root bob is retained for physics. Cancel it only at the
		# visible art roots while clapping, leaving both feet on the floor.
		var bob:float=clampf(position.y-float(row.base_y),-.2,.2) if clapping or float(row.clap)>.0001 else 0.0
		for part in row.visuals:
			var visual:Node3D=row.visuals[part]
			var pose:Transform3D=row.rests[part]
			var parent:Node3D=visual.get_parent() as Node3D
			pose.origin+=parent.global_basis.inverse()*Vector3(0,-bob,0)
			visual.transform=pose
		row.mode="clap" if clapping else ("walk" if speed>.05 else "idle")
		row["speed"]=speed
		row["visual_bob_cancelled"]=bob

func _is_clapping(who:String)->bool:
	if int(game.gag2_phase)!=0:
		return (int(game.gag2_phase)==3 and who=="小学生甲") or (int(game.gag2_phase)==4 and who in ["小学生甲","保安"])
	return int(game.gag_phase)==3

func _set_blends(meshes:Array,left:float,right:float)->void:
	for mesh_node in meshes:
		mesh_node.set_blend_shape_value(0,left)
		mesh_node.set_blend_shape_value(1,right)

func _reset_actor(row:Dictionary)->void:
	row.walk=0.0;row.clap=0.0;row.phase=0.0
	for part in row.visuals:
		if is_instance_valid(row.visuals[part]):row.visuals[part].transform=row.rests[part]
	for meshes in row.meshes.values():_set_blends(meshes,0.0,0.0)

func reset_pose()->void:
	for row in actors:_reset_actor(row)

func snapshot()->Array:
	var rows:Array=[]
	for row in actors:rows.append({"name":row.visitor.name,"mode":row.mode,"walk":row.walk,"clap":row.clap,"phase":row.phase,"visual_bob_cancelled":row.get("visual_bob_cancelled",0.0)})
	return rows

func motion_contract()->Dictionary:
	return {"recipe":RECIPE,"actors":actors.size(),"cached_meshes":mesh_cache.size(),"failures":failures.duplicate(true),"route":"local_garment_blend_shapes_no_skeleton","source_uv_materials_preserved":true,"motion_bounds":motion_bounds.duplicate(true),"ragdoll_restoration_owner":"unchanged shared game","physics_transforms_written":false,"native_visual_qualification":"pending","limits":["Stylized two-pose walk and applause, not retargeted skeletal animation.","Sleeve mask and palm contact require native visual review.","CPU mesh faces remain rest pose; camera needs conservative blend-target hull and VisualRoot Y margin."]}
