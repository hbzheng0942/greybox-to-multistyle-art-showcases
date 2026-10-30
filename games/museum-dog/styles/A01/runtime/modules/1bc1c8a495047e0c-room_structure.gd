extends RefCounted
## A01 gallery-only visual construction. Derives its corners from native ceiling
## bounds. New A01 corner contacts are explicitly reported; native owners stay unchanged.
const REGIONS:Array[String]=["porcelain","taxidermy","kids","vestibule"]
# Visual corner treatment is intentionally broader than the original garnish.
# Centred at the native corner, it exposes a readable arc on both room faces.
# The report records the excess beyond physical wall faces for playtest review.
const MAX_RADIUS:=.48
const INSIDE_BIAS:=.12

func _v(a:Array)->Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func apply(game,mapping,kits)->Dictionary:
	if game.has_node("A01RoomStructure"):
		return game.get_node("A01RoomStructure").get_meta("construction_report",{})
	var root:=Node3D.new();root.name="A01RoomStructure";game.add_child(root)
	root.global_transform=Transform3D.IDENTITY
	var report:={"kind":"gallery_structure_with_declared_local_contacts","regions":[],"added_colliders":0,"native_owner_mutations":0,"derived_from":"semantic-bindings ceiling/wall bounds","native_visual_validation":"pending"}
	for region in REGIONS:
		var ceiling:Dictionary={}
		var wall_ids:Array=[]
		var floor_top:=.05
		for group in mapping.groups:
			if str(group.region)!=region:continue
			if str(group.family_id)=="shell_ceiling":ceiling=group
			if str(group.family_id)=="shell_wall":wall_ids.append_array(group.semantic_ids)
			if str(group.family_id)=="shell_floor":
				floor_top=float(group.primary_world_aabb.min[1])+float(group.primary_world_aabb.size[1])
		if ceiling.is_empty():
			report.regions.append({"region":region,"status":"missing_native_ceiling_bounds"});continue
		var box:=AABB(_v(ceiling.primary_world_aabb.min),_v(ceiling.primary_world_aabb.size))
		var low:=box.position;var high:=box.end
		var roof_y:=low.y
		var container:=Node3D.new();container.name=region
		var column:Node3D=_round_column(roof_y-floor_top,kits)
		# Radius is measured from actual generated surface vertices, including
		# base/capital/buckles; a square AABB width would underestimate corners.
		var source_radius:=_radial_extent(column,Transform3D.IDENTITY)
		var factor:=minf(1.0,MAX_RADIUS/maxf(source_radius,.001))
		column.scale=Vector3(factor,1,factor)
		var corners:Array=[]
		var contacts:Array=[]
		var skipped:Array=[]
		for sx in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				var at:=Vector3((low.x if sx<0 else high.x)-sx*INSIDE_BIAS,floor_top,(low.z if sz<0 else high.z)-sz*INSIDE_BIAS)
				var door:=_doorway_conflict(at,MAX_RADIUS,mapping)
				if not door.is_empty():
					skipped.append({"candidate":[at.x,at.y,at.z],"portal":door,"reason":"visual pillar envelope would narrow doorway"});continue
				var copy:Node3D=column.duplicate();copy.position=at
				container.add_child(copy)
				corners.append([at.x,at.y,at.z])
				var contact_radius:float=source_radius*factor
				var contact:Dictionary=_add_corner_contact(root,region+"_"+str(corners.size()),at,contact_radius,roof_y-floor_top,low,high)
				contact["approach"]=[at.x-sx*.95,floor_top+.01,at.z-sz*.95]
				contact["old_wall_corner_target"]=[at.x-sx*.30,floor_top+.01,at.z-sz*.30]
				contact["expected_stop_on_diagonal"]=[at.x-sx*(contact_radius+.27)/sqrt(2.0),floor_top+.01,at.z-sz*(contact_radius+.27)/sqrt(2.0)]
				contact["portal_clearances"]=_portal_clearances(at,contact_radius,mapping)
				contacts.append(contact)
				report.added_colliders+=1
		column.free()
		var beam_radius:=.18 if region=="vestibule" else .38
		var beam_y:=roof_y-.02 if region=="vestibule" else roof_y-.08
		var x0:=low.x+INSIDE_BIAS;var x1:=high.x-INSIDE_BIAS
		var z0:=low.z+INSIDE_BIAS;var z1:=high.z-INSIDE_BIAS
		kits.soft.padded_roof_beam(container,Vector3(x0,beam_y,z0),Vector3(x1,beam_y,z0),beam_radius,kits.orange)
		kits.soft.padded_roof_beam(container,Vector3(x0,beam_y,z1),Vector3(x1,beam_y,z1),beam_radius,kits.orange)
		kits.soft.padded_roof_beam(container,Vector3(x0,beam_y,z0),Vector3(x0,beam_y,z1),beam_radius,kits.orange)
		kits.soft.padded_roof_beam(container,Vector3(x1,beam_y,z0),Vector3(x1,beam_y,z1),beam_radius,kits.orange)
		var baked:Node3D=kits.soft.bake_static_visual(container)
		_clip_room(baked,low+Vector3(.151,0,.151),high-Vector3(.151,0,.151))
		baked.name=region+"_CornerColumnsAndPerimeter"
		root.add_child(baked);container.free()
		report.regions.append({"region":region,"ceiling_group":str(ceiling.id),"wall_semantic_sources":wall_ids,"column_centers":corners,"columns":corners.size(),"local_contacts":contacts,"skipped_corners":skipped,"max_radial_envelope":MAX_RADIUS,"source_column_radius":source_radius,"column_xz_scale":factor,"shaft_radius":.465*factor,"column_geometry":"dedicated_round_shaft_and_circular_end_collars","wall_half_depth":.15,"max_axis_intrusion":source_radius*factor-.15+INSIDE_BIAS,"dog_capsule_radius":.27,"ideal_corner_capsule_gap":sqrt(2.0)*(.15-INSIDE_BIAS+.27)-.27-MAX_RADIUS,"corner_visual_contact_requires_playtest":true,"native_collision_owners_unchanged":true,"full_scene_physics_unchanged":false,"beam_radius":beam_radius,"beam_bottom":beam_y-beam_radius,"beam_count":4,"status":"constructed_pending_native_review"})
	root.set_meta("construction_report",report)
	return report

func _round_column(height:float,kits)->Node3D:
	# Broad inflated shaft: large radius at mid-height, compressed at the orange
	# end boots. No tiny wall-external tube scaled down by a square capital.
	var column:=Node3D.new();column.name="RoundGalleryPressureColumn"
	var shaft:Node3D=kits.soft.inflated_pillar(column,.95,height-.32,.95,kits.cream,[.24],.25)
	shaft.position.y=.16
	kits.soft.collar(column,.95,.95,.25,.145,Vector3.ZERO,kits.orange)
	kits.soft.collar(column,.95,.95,.70,height-.45,Vector3.ZERO,kits.orange)
	kits.soft.collar(column,.93,.93,.055,.040,Vector3.ZERO,kits.navy)
	return column

func _radial_extent(node:Node3D,parent_xform:Transform3D)->float:
	var xf:Transform3D=parent_xform*node.transform
	var radius:=0.0
	if node is MeshInstance3D and node.mesh!=null:
		for vertex in node.mesh.get_faces():
			var point:Vector3=xf*vertex
			radius=maxf(radius,Vector2(point.x,point.z).length())
	for child in node.get_children():
		if child is Node3D:radius=maxf(radius,_radial_extent(child,xf))
	return radius

func _doorway_conflict(at:Vector3,radius:float,mapping)->String:
	for group in mapping.groups:
		if str(group.family_id)!="portal_frame":continue
		var origin:=_v(group.placement.origin)
		var basis:=Basis(Vector3.UP,float(group.placement.rotation_y))
		var local:Vector3=basis.inverse()*(at-origin)
		if absf(local.z)<radius+.18 and absf(local.x)<float(group.portal.clear_width)*.5+radius+.03:
			return str(group.id)
	return ""

func _clip_room(root:Node3D,low:Vector3,high:Vector3)->void:
	# Trim shared-wall decorations to their own room. This prevents gallery
	# corner shafts / perimeter tubes from appearing as floating hall beams.
	for node in root.get_children():
		if not node is MeshInstance3D:continue
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emitted:=0
		for si in range(node.mesh.get_surface_count()):
			var a:Array=node.mesh.surface_get_arrays(si)
			var verts:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
			var ns:PackedVector3Array=a[Mesh.ARRAY_NORMAL]
			var ids:PackedInt32Array=a[Mesh.ARRAY_INDEX]
			if ids.is_empty():
				for j in range(verts.size()):ids.append(j)
			for j in range(0,ids.size(),3):
				var poly:Array=[]
				for k in range(3):poly.append({"p":verts[ids[j+k]],"n":ns[ids[j+k]]})
				for plane in [[0,low.x,1.0],[0,high.x,-1.0],[2,low.z,1.0],[2,high.z,-1.0]]:
					if poly.is_empty():break
					var out:Array=[];var prev:Dictionary=poly.back()
					var pd:float=(prev.p[plane[0]]-plane[1])*plane[2]
					for cur in poly:
						var cd:float=(cur.p[plane[0]]-plane[1])*plane[2]
						if (pd>=0)!=(cd>=0):
							var t:float=pd/(pd-cd)
							out.append({"p":prev.p.lerp(cur.p,t),"n":prev.n.lerp(cur.n,t).normalized()})
						if cd>=0:out.append(cur)
						prev=cur;pd=cd
					poly=out
				for k in range(1,poly.size()-1):
					for v in [poly[0],poly[k],poly[k+1]]:
						st.set_normal(v.n);st.set_uv(Vector2(v.p.x+v.p.z,v.p.y));st.add_vertex(v.p);emitted+=1
		if emitted>0:node.mesh=st.commit()
		else:node.visible=false


func _add_corner_contact(root:Node3D,label:String,at:Vector3,radius:float,height:float,low:Vector3,high:Vector3)->Dictionary:
	# A full CylinderShape would protrude through a shared wall into the next
	# room, where its visual has been clipped. Clip the circular prism to the
	# same inner wall faces and use one convex shape for its exposed arc.
	var poly:=PackedVector2Array()
	for i in range(48):
		var a:float=TAU*i/48.0
		poly.append(Vector2(cos(a)*radius,sin(a)*radius))
	for plane in [[0,low.x+.151-at.x,1.0],[0,high.x-.151-at.x,-1.0],[1,low.z+.151-at.z,1.0],[1,high.z-.151-at.z,-1.0]]:
		var result:=PackedVector2Array()
		if poly.is_empty():break
		var prev:Vector2=poly[poly.size()-1]
		var pd:float=(prev[int(plane[0])]-float(plane[1]))*float(plane[2])
		for cur in poly:
			var cd:float=(cur[int(plane[0])]-float(plane[1]))*float(plane[2])
			if (pd>=0)!=(cd>=0):result.append(prev.lerp(cur,pd/(pd-cd)))
			if cd>=0:result.append(cur)
			prev=cur;pd=cd
		poly=result
	assert(poly.size()>=3,"A01 corner contact clipped to empty shape")
	var points:=PackedVector3Array()
	for y in [0.0,height]:
		for p in poly:points.append(Vector3(p.x,y,p.y))
	var shape:=ConvexPolygonShape3D.new();shape.points=points
	var body:=StaticBody3D.new();body.name="A01CornerContact_"+label
	body.position=at;body.collision_layer=1;body.collision_mask=0
	body.set_meta("a01_local_contact",true)
	body.set_meta("a01_contact_kind","room_clipped_corner_column")
	body.set_meta("a01_contact_radius",radius)
	var node:=CollisionShape3D.new();node.name="ClippedCircularPrism";node.shape=shape
	body.add_child(node);root.add_child(body)
	var polygon:Array=[]
	for p in poly:polygon.append([p.x,p.y])
	return {"node":str(body.get_path()),"a01_local_contact":true,"shape":"48-sided_cylinder_clipped_to_room_convex","center":[at.x,at.y,at.z],"radius":radius,"height":height,"collision_layer":1,"polygon_xz_local":polygon,"bounds_clip_world":{"low_xz":[low.x+.151,low.z+.151],"high_xz":[high.x-.151,high.z-.151]}}

func _portal_clearances(at:Vector3,radius:float,mapping)->Array:
	var results:Array=[]
	for group in mapping.groups:
		if str(group.family_id)!="portal_frame":continue
		var origin:=_v(group.placement.origin)
		var basis:=Basis(Vector3.UP,float(group.placement.rotation_y))
		var local:Vector3=basis.inverse()*(at-origin)
		var dx:float=maxf(0.0,absf(local.x)-float(group.portal.clear_width)*.5)
		var dz:float=maxf(0.0,absf(local.z)-.18)
		results.append({"portal":str(group.id),"conservative_circle_clearance":Vector2(dx,dz).length()-radius})
	return results
