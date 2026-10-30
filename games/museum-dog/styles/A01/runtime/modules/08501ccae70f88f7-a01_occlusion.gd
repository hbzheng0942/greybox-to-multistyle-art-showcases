extends RefCounted
## Conservative opaque-wall occluders. Portals, props and characters are excluded.
func apply(game,mapping:Dictionary)->Dictionary:
	var holder:=Node3D.new();holder.name="A01WallOccluders";game.add_child(holder)
	var rows:Array=[]
	for group in mapping.groups:
		if group.family_id!="shell_wall":continue
		for collider in group.get("colliders",[]):
			if collider.shape!="BoxShape3D":continue
			var data:Dictionary=collider.world_aabb
			var low:=Vector3(data.min[0],data.min[1],data.min[2])
			var size:=Vector3(data.size[0],data.size[1],data.size[2])
			# Each surface stays inside the unchanged opaque wall. Recess from
			# every boundary so an imperfect silhouette only loses culling.
			var inset:=Vector3(.08,.08,.08)
			if size.x<.5:inset.x=.10
			if size.z<.5:inset.z=.10
			var shape:=BoxOccluder3D.new();shape.size=size-inset*2
			if shape.size.x<=0 or shape.size.y<=0 or shape.size.z<=0:continue
			var instance:=OccluderInstance3D.new();instance.occluder=shape
			instance.position=low+size*.5;holder.add_child(instance)
			rows.append({"group":group.id,"position":str(instance.position),"size":str(shape.size)})
	game.get_viewport().use_occlusion_culling=true
	return {"kind":"conservative_opaque_wall_occlusion","wall_boxes":rows,"dynamic_occluders":0,"portal_occluders":0,"collision_changes":0,"native_comparison_required":true}
