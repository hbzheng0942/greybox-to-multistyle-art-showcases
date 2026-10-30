extends RefCounted
## A01-only display pose adaptation. Existing plate rigid bodies remain native;
## visible, separately declared easels support the new initial/reset poses.
const ANGLE:=deg_to_rad(70.0)
const SELECTION:=[[1,4,6],[2,5],[1,4,6]]
func _v(value:Vector3)->Array:return [value.x,value.y,value.z]
func _unpack(value:Array)->Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
func _pose(value:Transform3D)->Dictionary:
	return {"position":_v(value.origin),"basis_x":_v(value.basis.x),"basis_y":_v(value.basis.y),"basis_z":_v(value.basis.z)}
func _metadata(body:RigidBody3D)->Dictionary:
	return {"spawn_transform":_pose(body.get_meta("spawn_transform",body.transform)),"spawn_pos":_v(body.get_meta("spawn_pos",body.position)),"spawn_y":body.get_meta("spawn_y",body.position.y),"kind":body.get_meta("kind"),"value":body.get_meta("value"),"semantic_id":body.get_meta("semantic_id"),"region_id":body.get_meta("region_id"),"mass":body.mass,"collision_layer":body.collision_layer,"collision_mask":body.collision_mask,"freeze":body.freeze,"counted":body.get_meta("counted",false)}
func apply(game,mapping:Dictionary,kits,prototype_only:bool=false)->Dictionary:
	if game.has_node("A01PorcelainDisplay"):
		return game.get_node("A01PorcelainDisplay").get_meta("display_report",{})
	var root:=Node3D.new();root.name="A01PorcelainDisplay";game.add_child(root);root.global_transform=Transform3D.IDENTITY
	var report:={"kind":"declared_a01_native_plate_display_adaptation","changed_props":[],"added_colliders":0,"added_shapes":0,"shared_game_sources_modified":false,"full_scene_physics_unchanged":false,"angle_degrees":70.0,"prototype_only":prototype_only,"plate_count_before":0,"native_visual_validation":"pending"}
	for body in game.props:if body.get_meta("kind","")=="plate":report.plate_count_before+=1
	for group in mapping.groups:
		if str(group.family_id)!="porcelain_shelf":continue
		var shelf_xf:=Transform3D(Basis(Vector3.UP,float(group.placement.rotation_y)),_unpack(group.placement.origin))
		var shelves:Array=[[],[],[]]
		for body in game.props:
			if body.get_meta("kind","")!="plate":continue
			var local:Vector3=shelf_xf.affine_inverse()*body.global_position
			if absf(local.z-.14)>.025 or absf(local.x)>4.0:continue
			var level:int=roundi((local.y-1.017)/.72)
			if level<0 or level>2 or absf(local.y-(1.017+.72*level))>.025:continue
			shelves[level].append({"body":body,"local":local})
		for level in range(3):
			shelves[level].sort_custom(func(a,b):return a.local.x<b.local.x)
			assert(shelves[level].size()==8,"Expected eight original plates on shelf tier: "+str(group.id))
			for slot in SELECTION[level]:
				if prototype_only and not report.changed_props.is_empty():continue
				var item:Dictionary=shelves[level][slot];var body:RigidBody3D=item.body
				var before:=_metadata(body);var original:=body.global_transform
				var top:float=.985+.72*level
				var center:=Vector3(item.local.x,top+.255,.14)
				var plate_xf:=shelf_xf*Transform3D(Basis(Vector3.RIGHT,ANGLE),center)
				body.global_transform=plate_xf
				body.linear_velocity=Vector3.ZERO;body.angular_velocity=Vector3.ZERO;body.sleeping=false
				body.set_meta("a01_display_pose",true)
				body.set_meta("a01_display_original_transform",original)
				body.set_meta("spawn_transform",body.transform)
				body.set_meta("spawn_pos",body.position)
				body.set_meta("spawn_y",body.global_position.y)
				body.reset_physics_interpolation()
				var stand:=_stand(root,str(body.name),shelf_xf,center,top,kits)
				var shapes:Array=[]
				for child in stand.get_children():
					if child is CollisionShape3D:shapes.append({"name":str(child.name),"size":_v(child.shape.size),"local_transform":_pose(child.transform)})
				report.changed_props.append({"node":str(body.get_path()),"semantic_id":body.get_meta("semantic_id"),"shelf":str(group.id),"level":level,"slot":slot,"original_transform":_pose(original),"new_transform":_pose(body.global_transform),"original_meta":before,"new_meta":_metadata(body),"stand_node":str(stand.get_path()),"stand_transform":_pose(stand.global_transform),"stand_shapes":shapes})
				report.added_colliders+=1;report.added_shapes+=shapes.size()
	assert(report.changed_props.size()==(1 if prototype_only else 16),"Unexpected selected plate count")
	root.set_meta("display_report",report)
	return report
func _stand(parent:Node3D,label:String,shelf_xf:Transform3D,center:Vector3,top:float,kits)->StaticBody3D:
	var stand:=StaticBody3D.new();stand.name="A01PlateStand_"+label;parent.add_child(stand)
	stand.global_transform=shelf_xf*Transform3D(Basis.IDENTITY,Vector3(center.x,top,center.z))
	stand.collision_layer=1;stand.collision_mask=0
	stand.set_meta("a01_local_contact",true);stand.set_meta("a01_contact_kind","visible_plate_display_easel")
	var friction:=PhysicsMaterial.new();friction.friction=1.0;friction.rough=true;friction.bounce=0.0;stand.physics_material_override=friction
	var tilt:=Basis(Vector3.RIGHT,ANGLE)
	_pad(stand,"SoftBase",Vector3(.32,.035,.30),Transform3D(Basis.IDENTITY,Vector3(0,.0175,0)),kits.navy,kits)
	_pad(stand,"InclinedBack",Vector3(.28,.028,.38),Transform3D(tilt,Vector3(0,.255,0)+tilt*Vector3(0,-.047,0)),kits.navy,kits)
	_pad(stand,"LowerStop",Vector3(.28,.085,.036),Transform3D(tilt,Vector3(0,.255,0)+tilt*Vector3(0,-.015,.203)),kits.orange,kits)
	return stand
func _pad(parent:StaticBody3D,label:String,size:Vector3,xf:Transform3D,color:Color,kits)->void:
	var shape:=CollisionShape3D.new();shape.name=label+"Contact";shape.shape=BoxShape3D.new();shape.shape.size=size;shape.transform=xf;parent.add_child(shape)
	var visual:Node3D=kits.soft.inflated_case(parent,size,color,false)
	visual.name=label+"Visual";visual.transform=xf*Transform3D(Basis.IDENTITY,Vector3(0,-size.y*.5,0))
