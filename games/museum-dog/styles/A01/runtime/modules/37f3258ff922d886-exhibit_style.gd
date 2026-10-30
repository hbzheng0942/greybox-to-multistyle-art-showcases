extends RefCounted
## Reversible visual-only refinement. Source GLB, fitting transforms and physics stay canonical.
## One refined ArrayMesh per source/recipe is shared by all instances.
const CLOTH=preload("res://styles/A01/runtime/modules/d8b33df473ba85e4-exhibit_cloth_finish.gd")
const SOCKET_DATA=preload("res://styles/A01/runtime/modules/c2793d3a2246a98f-exhibit_socket_data.gd")
var _mesh_cache:Dictionary = {}
var _material_cache:Dictionary = {}
const RECIPE := "soft-exhibits-20261030-r8"
const BODY_ALBEDO := {
	"specimen_bear":"res://styles/A01/assets/exhibit_refinement/specimen_bear-fur-albedo-2a939a944a350c7b.png",
	"specimen_wolf":"res://styles/A01/assets/exhibit_refinement/specimen_wolf-fur-albedo-0ffd994a7d0e250a.png"
}

func apply(root:Node3D,asset_id:String)->Dictionary:
	if not asset_id.begins_with("mammoth_") and asset_id not in ["specimen_bear","specimen_deer","specimen_wolf"]:
		return {"status":"not_applicable"}
	if asset_id.begins_with("mammoth_") and asset_id not in ["mammoth_ribs","mammoth_front_leg","mammoth_back_leg","mammoth_neck","mammoth_chest","mammoth_pelvis","mammoth_head"]:
		return {"status":"retained_existing_geometry","asset_id":asset_id,"reason":"existing jaw, spine and tail identity retained; material integration remains separate"}
	if root.has_meta("a01_exhibit_style"):
		return {"status":"already_applied"}
	root.set_meta("a01_exhibit_style",true)
	var report:Dictionary = {"status":"applied_visual_only","recipe":RECIPE,"asset_id":asset_id,"changed_meshes":0,"source_vertices":0,"added_detail_meshes":0,"hidden_visual_nodes":[],"rib_profile":[],"geometry_recipes":[],"endpoint_policy":"bone native height extrema and animal feet/face protected","physics_changed":false,"source_files_changed":false,"native_visual_review":"pending"}
	var nodes:Array[MeshInstance3D] = []
	_collect(root,nodes)
	for node in nodes:
		if asset_id == "mammoth_ribs" and str(node.name).contains("LowerLongitudinalConnector"):
			node.visible = false
			report.hidden_visual_nodes.append({"path":str(root.get_path_to(node)),"reason":"non-collision visual crossbar removed to expose individual curved ribs","node_type":node.get_class()})
			continue
		if node.mesh == null: continue
		var source:Mesh = node.mesh
		var is_hoop:bool = asset_id == "mammoth_ribs" and (str(node.name).begins_with("RibHoop") or str(source.resource_name).contains("SourceRing"))
		if asset_id == "mammoth_ribs" and not is_hoop: continue
		var fitted:Transform3D = _relative_transform(node,root)
		var fitted_basis:Basis = fitted.basis
		var fitted_up := Vector3(fitted_basis.x.y,fitted_basis.y.y,fitted_basis.z.y)
		var rib_index:int=_rib_index(node) if is_hoop else 0
		var key:String = RECIPE+":"+str(source.get_instance_id())+":"+asset_id+":"+str(is_hoop)+":"+str(fitted_basis)+":"+str(rib_index)
		if not _mesh_cache.has(key):
			_mesh_cache[key] = _round_rib(source,fitted,rib_index) if is_hoop else _refine(source,asset_id,false,fitted_up)
		var refined:Dictionary = _mesh_cache[key]
		node.mesh = refined.mesh
		report.changed_meshes += 1
		report.source_vertices += refined.vertices
		report.geometry_recipes.append({"path":str(root.get_path_to(node)),"recipe":refined.get("recipe","protected_local_deformation"),"maximum_displacement":refined.get("maximum_displacement",0.0),"output_vertices":refined.get("output_vertices",refined.vertices),"removed_detached_neck_fragments":refined.get("removed_detached_neck_fragments",[]),"seated_socket_rims":refined.get("seated_socket_rims",[])})
		if is_hoop: report.rib_profile.append(_profile_rib(node,root))
		if asset_id.begins_with("specimen_"):
			if BODY_ALBEDO.has(asset_id):report["body_albedo_cleanup"]=_apply_body_albedo(node,asset_id)
			report.added_detail_meshes += _animal_seams(node,asset_id)
		elif asset_id in ["mammoth_chest","mammoth_pelvis"]:
			var liners:Dictionary = _socket_liners(node,asset_id,source.get_aabb(),fitted)
			report["socket_liners"] = liners
			report.added_detail_meshes += int(liners.get("added_meshes",0))
		elif asset_id in ["mammoth_front_leg","mammoth_back_leg"]:
			report.added_detail_meshes += _limb_seams(node)
	if asset_id in ["specimen_bear","specimen_wolf"]:
		report["remaining_limit"] = "Torso uses 14 bounded adjacency passes; outer cheek/neck adds 10 local passes, removes only eligible tiny detached components and the added collar welt. Fine original per-texel fur retained by multiplicative albedo correction. Protected facial core, ears and paws unchanged. Connected fur folds may still read too coarse: native review required."
	elif asset_id in ["mammoth_head","mammoth_chest","mammoth_pelvis"]:
		report["remaining_limit"] = "Chest/pelvis large side sockets receive convex shell-matched cloth patches covering the original hard rims inside source bounds. Other small bronze pins, skull recesses and rib mount topology remain; not a full soft-joint remesh."
	return report

func _socket_liners(node:MeshInstance3D,asset_id:String,source_bounds:AABB,fitted:Transform3D)->Dictionary:
	# The old inner insert was cropped by the source's hard polygonal rim.
	# This patch covers that rim, returns to sampled ORIGINAL outer-shell
	# points and uses adjacent actual UV cloth colours. No source file edits.
	var key:String=RECIPE+":socket_liners:"+asset_id
	if not _mesh_cache.has(key):_mesh_cache[key]=_make_socket_liners(SOCKET_DATA.CAPS[asset_id],source_bounds,fitted.basis)
	var result:Dictionary=_mesh_cache[key]
	if not result.within_source_aabb:return {"status":"bounds_rejected","added_meshes":0}
	var detail:=MeshInstance3D.new()
	detail.name="A01ShellMatchedCanvasSocketPatches"
	detail.mesh=result.mesh
	var material_key:String="source_sampled_socket_canvas"
	if not _material_cache.has(material_key):
		var cloth:=StandardMaterial3D.new()
		cloth.resource_name="A01ShellSampledCanvas"
		cloth.albedo_color=Color.WHITE
		cloth.vertex_color_use_as_albedo=true
		cloth.vertex_color_is_srgb=true
		cloth.roughness=.88
		cloth.metallic=0.0
		CLOTH.apply(cloth)
		_material_cache[material_key]=cloth
	detail.material_override=_material_cache[material_key]
	detail.set_meta("exhibit_style_detail",true)
	detail.set_meta("a01_socket_liners",true)
	node.add_child(detail)
	var stitch_key:String=key+":stitches"
	if not _mesh_cache.has(stitch_key):_mesh_cache[stitch_key]=CLOTH.stitches(SOCKET_DATA.CAPS[asset_id],source_bounds,fitted,_socket_surface)
	var stitches:Dictionary=_mesh_cache[stitch_key]
	var sewn:=MeshInstance3D.new();sewn.name="A01StitchedSocketPerimeters";sewn.mesh=stitches.mesh
	var thread:=StandardMaterial3D.new();thread.albedo_color=Color.WHITE;thread.vertex_color_use_as_albedo=true;thread.vertex_color_is_srgb=true
	thread.roughness=.94;thread.metallic_specular=.22;sewn.material_override=thread
	sewn.set_meta("exhibit_style_detail",true);sewn.set_meta("a01_socket_stitches",true);node.add_child(sewn)
	return {"status":"applied_visual_only","added_meshes":2,"stitch_count":stitches.stitches,"thread_diameter_m":stitches.thread_diameter_m,"stitch_length_m":stitches.stitch_length_m,"cloth_patch_m":CLOTH.PATCH_M,"socket_count":SOCKET_DATA.CAPS[asset_id].size(),"triangles":result.triangles,"within_source_local_aabb":result.within_source_aabb,"source_aabb":str(source_bounds),"liner_aabb":str(result.mesh.get_aabb()),"surface_policy":"convex patch covering original rim, boundary and cloth colour sampled from canonical shell","native_visual_review":"pending","physics_changed":false}

func _make_socket_liners(specs:Array,source_bounds:AABB,fitted_basis:Basis=Basis.IDENTITY)->Dictionary:
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var colors:=PackedColorArray()
	var uvs:=PackedVector2Array()
	var indices:=PackedInt32Array()
	for spec in specs:
		var offset:int=vertices.size()
		var axis:Vector3=spec.axis
		var sides:int=spec.sides
		var rings:int=spec.rings
		vertices.append_array(spec.points)
		colors.append_array(spec.colors)
		var metric_u:Vector3=(fitted_basis*Vector3.UP.cross(axis)).normalized()
		var metric_v:Vector3=(fitted_basis*Vector3.UP).normalized()
		for i in range(spec.points.size()):
			normals.append(-axis if i==spec.points.size()-1 else axis)
			var metric:Vector3=fitted_basis*(spec.points[i]-spec.center)
			uvs.append(Vector2(metric.dot(metric_u),metric.dot(metric_v))/CLOTH.PATCH_M)
		var back:int=vertices.size()-1
		# Split normals at the hidden back/cloth perimeter. A closed cap may
		# share positions without averaging its visible face with the back cone.
		var back_edge:int=vertices.size()
		for side in range(sides):
			var original:int=offset+1+(rings-1)*sides+side
			vertices.append(vertices[original]);colors.append(colors[original])
			normals.append(-axis);uvs.append(uvs[original])
		for side in range(sides):
			var next:int=(side+1)%sides
			indices.append_array(PackedInt32Array([offset,offset+1+side,offset+1+next]))
			for ring in range(rings-1):
				var a:int=offset+1+ring*sides+side
				var b:int=offset+1+ring*sides+next
				var c:int=a+sides
				var d:int=b+sides
				indices.append_array(PackedInt32Array([a,c,b,b,c,d]))
			indices.append_array(PackedInt32Array([back,back_edge+next,back_edge+side]))
	normals=_closed_normals(vertices,indices)
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices;arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TANGENT]=CLOTH.tangents(vertices,normals,uvs,indices)
	var mesh:=ArrayMesh.new()
	mesh.resource_name="A01ShellMatchedCanvasPatches"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	CLOTH.record_basis_packing(mesh,normals,arrays[Mesh.ARRAY_TANGENT])
	var inside:bool=true
	for p in vertices:inside=inside and source_bounds.grow(.0000001).has_point(p)
	return {"mesh":mesh,"triangles":indices.size()/3,"within_source_aabb":inside}

func _socket_surface(spec:Dictionary,t:float,theta:float)->Vector3:
	var slot:float=fposmod(theta,TAU)/TAU*float(spec.sides)
	var a:int=int(floor(slot))%int(spec.sides);var b:int=(a+1)%int(spec.sides)
	var radius:float=lerpf(spec.edge_radii[a],spec.edge_radii[b],slot-floor(slot))
	var radial:Vector3=Vector3.UP*cos(theta)+Vector3.UP.cross(spec.axis)*sin(theta)
	return spec.center+radial*radius*t+spec.axis*_socket_depth(spec,t,theta)

func _socket_depth(spec:Dictionary,t:float,theta:float)->float:
	var slot:float=fposmod(theta,TAU)/TAU*float(spec.sides)
	var a:int=int(floor(slot))%int(spec.sides)
	var b:int=(a+1)%int(spec.sides)
	var edge:float=lerpf(spec.edge_depths[a],spec.edge_depths[b],slot-floor(slot))
	if spec.power==2:
		var plane:Vector3=spec.plane
		var slope:float=plane.y*cos(theta)+plane.z*sin(theta)
		return plane.x+t*slope+(float(spec.peak)-plane.x)*(1.0-t*t)+(edge-plane.x-slope)*pow(t,8)
	return float(spec.peak)+(edge-float(spec.peak))*pow(t,float(spec.power))

func _seat_socket_rims(vertices:PackedVector3Array,asset_id:String,bounds:AABB)->Dictionary:
	# The opaque convex patch replaces only the visible hole-rim region. Seat
	# underlying hard high points just below it rather than copying folds into
	# the cloth, and retain the original outer AABB and every bone owner.
	var output:PackedVector3Array=vertices.duplicate()
	var count:int=0;var maximum:float=0.0
	for j in range(output.size()):
		var original:Vector3=output[j]
		for spec in SOCKET_DATA.CAPS[asset_id]:
			var axis:Vector3=spec.axis
			var right:Vector3=Vector3.UP.cross(axis)
			var delta:Vector3=output[j]-spec.center
			var x:float=delta.dot(right);var y:float=delta.y
			var theta:float=fposmod(atan2(x,y),TAU)
			var slot:float=theta/TAU*float(spec.sides)
			var a:int=int(floor(slot))%int(spec.sides);var b:int=(a+1)%int(spec.sides)
			var radius:float=lerpf(spec.edge_radii[a],spec.edge_radii[b],slot-floor(slot))
			var t:float=Vector2(x,y).length()/maxf(radius,.000001)
			if t>=.995:continue
			var inset:float=.00025*(1.0-smoothstep(.88,.995,t))
			var target:float=_socket_depth(spec,t,theta)-inset
			var depth:float=delta.dot(axis)
			if depth>target:output[j]=(output[j]-axis*(depth-target)).clamp(bounds.position,bounds.end)
		var distance:float=output[j].distance_to(original)
		if distance>.0000001:count+=1;maximum=maxf(maximum,distance)
	return {"vertices":output,"count":count,"maximum":maximum}

func _closed_normals(vertices:PackedVector3Array,indices:PackedInt32Array)->PackedVector3Array:
	# Known clockwise closed patches: a vertex's old axis is not a reliable
	# orientation hint at the curved rim. Preserve the one global winding.
	var normals:=PackedVector3Array();normals.resize(vertices.size())
	for j in range(0,indices.size(),3):
		var a:int=indices[j];var b:int=indices[j+1];var c:int=indices[j+2]
		var normal:Vector3=-(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
		normals[a]+=normal;normals[b]+=normal;normals[c]+=normal
	for j in range(normals.size()):normals[j]=normals[j].normalized()
	return normals

func _apply_body_albedo(node:MeshInstance3D,asset_id:String)->Dictionary:
	var path:String=BODY_ALBEDO[asset_id]
	var texture_key:String="body_albedo:"+asset_id
	if not _material_cache.has(texture_key):
		var image:=Image.load_from_file(path)
		if image==null or image.is_empty():return {"status":"missing_derivative","path":path}
		image.generate_mipmaps()
		var texture:=ImageTexture.create_from_image(image)
		# The original GLB contains one material surface. Preserve its optical
		# setup and normal/UV interfaces; palette treatment runs afterward.
		var original:StandardMaterial3D=node.get_active_material(0) as StandardMaterial3D
		if original==null:return {"status":"unsupported_original_material","path":path}
		var material:StandardMaterial3D=original.duplicate(false) as StandardMaterial3D
		material.albedo_texture=texture
		material.set_meta("a01_body_albedo_cleanup",path)
		material.set_meta("a01_original_albedo_texture",original.albedo_texture)
		_material_cache[texture_key]=material
	node.set_surface_override_material(0,_material_cache[texture_key])
	return {"status":"applied","path":path,"sha256":FileAccess.get_sha256(path),"method":"protected mesh-adjacency multiplicative colour correction preserving original per-texel fur; no image-space UV-chart blur","original_glb_unchanged":true,"native_quality":"pending"}

func _round_rib(source:Mesh,fitted:Transform3D,rib_index:int)->Dictionary:
	# Build the ROUND section in the final semantic bone space. The imported
	# hoop has its own Z scale and length profiling formerly scaled its whole
	# Y basis; constructing a circle only in local space was insufficient.
	var source_vertices:PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bounds:AABB = AABB(source_vertices[0],Vector3.ZERO)
	for point in source_vertices: bounds=bounds.expand(point)
	var center:Vector3=bounds.get_center()
	var old_radius:float=minf(bounds.size.y,bounds.size.z)*.071
	var ry:float=bounds.size.y*.5-old_radius
	var rz:float=bounds.size.z*.5-old_radius
	var factor:float=_rib_factor(rib_index)
	var diameter:float=_rib_diameter(rib_index)
	var radius:float=diameter*.5
	var attachment:Vector3=fitted*Vector3(0,source.get_aabb().end.y,0)
	var inverse:Transform3D=fitted.affine_inverse()
	var ring_count:int=72
	var sides:int=16
	var stride:int=sides+1
	var previous_center:=Vector3.ZERO
	var arc_length:float=0.0
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var uvs:=PackedVector2Array()
	var indices:=PackedInt32Array()
	for ring in range(ring_count+1):
		var angle:float=TAU*float(ring%ring_count)/float(ring_count)
		var amplitude:float=[.116,.126,.133,.142,.137,.129,.134,.121,.111][rib_index]
		var sweep:float=amplitude*cos(angle)*cos(angle)
		var c:Vector3=fitted*Vector3(center.x+sweep,center.y+ry*sin(angle),center.z+rz*cos(angle))
		# Only the centreline contracts toward the unchanged upper anchor.
		c.y=attachment.y+(c.y-attachment.y)*factor
		if ring>0:arc_length+=c.distance_to(previous_center)
		previous_center=c
		var tangent:Vector3=fitted.basis*Vector3(-2.0*amplitude*sin(angle)*cos(angle),ry*cos(angle),-rz*sin(angle))
		tangent.y*=factor
		tangent=tangent.normalized()
		var along:Vector3=fitted.basis.x.normalized()
		var axial:Vector3=(along-tangent*tangent.dot(along)).normalized()
		var outward:Vector3=axial.cross(tangent).normalized()
		for side in range(sides+1):
			var phi:float=TAU*float(side%sides)/float(sides)
			var normal:Vector3=axial*cos(phi)+outward*sin(phi)
			vertices.append(inverse*(c+normal*radius))
			normals.append((fitted.basis.transposed()*normal).normalized())
			uvs.append(Vector2(TAU*radius*float(side)/float(sides),arc_length)/CLOTH.PATCH_M)
	for ring in range(ring_count):
		for side in range(sides):
			var a:int=ring*stride+side
			var b:int=a+1
			var c:int=(ring+1)*stride+side
			var d:int=c+1
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
	arrays[Mesh.ARRAY_TANGENT]=CLOTH.tangents(vertices,normals,uvs,indices)
	var mesh:=ArrayMesh.new()
	mesh.resource_name="A01BoneSpaceRoundRib"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	CLOTH.record_basis_packing(mesh,normals,arrays[Mesh.ARRAY_TANGENT])
	var material_key:String="round_rib_canvas"
	if not _material_cache.has(material_key):
		var cloth:=StandardMaterial3D.new()
		cloth.resource_name="A01RoundRibCanvas"
		cloth.albedo_color=Color("eaddc2")
		cloth.roughness=.88;cloth.metallic=0.0
		CLOTH.apply(cloth)
		_material_cache[material_key]=cloth
	mesh.surface_set_material(0,_material_cache[material_key])

	# Retain the closed upper pad/eyelet and bronze pin, but discard obsolete
	# planar cut caps from the old slab: those poke through a round section.
	for surface in range(1,source.get_surface_count()):
		var retained:Array = source.surface_get_arrays(surface).duplicate(true)
		if surface==1:
			var old_points:PackedVector3Array = retained[Mesh.ARRAY_VERTEX]
			var old_indices:PackedInt32Array = retained[Mesh.ARRAY_INDEX]
			var kept:=PackedInt32Array()
			for j in range(0,old_indices.size()-2,3):
				var a:int=old_indices[j]
				var b:int=old_indices[j+1]
				var c:int=old_indices[j+2]
				if minf(old_points[a].y,minf(old_points[b].y,old_points[c].y))>.59:
					kept.append_array(PackedInt32Array([a,b,c]))
			retained[Mesh.ARRAY_INDEX]=kept
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface),retained)
		mesh.surface_set_material(surface,source.surface_get_material(surface))
	return {"mesh":mesh,"vertices":_all_vertices(source).size(),"output_vertices":_all_vertices(mesh).size(),"recipe":"final_bone_space_72x16_round_tube_centreline_profile_only","section_diameter_bone":diameter,"maximum_displacement":null,"displacement_note":"reconstructed topology; no one-to-one source vertex displacement"}

func _collect(node:Node,nodes:Array[MeshInstance3D])->void:
	if node is MeshInstance3D: nodes.append(node)
	for child in node.get_children(): _collect(child,nodes)

func _rib_index(node:MeshInstance3D)->int:
	return clampi(str(node.name).trim_prefix("RibHoop_").to_int()-1,0,8)
func _rib_factor(index:int)->float:
	return [.80,.88,.95,1.0,1.0,.98,.93,.86,.78][index]
func _rib_diameter(index:int)->float:
	return [.145,.150,.155,.160,.160,.158,.154,.149,.145][index]
func _profile_rib(node:MeshInstance3D,root:Node3D)->Dictionary:
	var index:int=_rib_index(node)
	return {"path":str(root.get_path_to(node)),"index":index+1,"length_factor":_rib_factor(index),"final_bone_space_section_diameter":_rib_diameter(index),"upper_mount_delta":"(0, 0, 0)","profile_policy":"centreline only; imported node transform and attachment surfaces unchanged","physics_or_root_fit_changed":false}

func _relative_transform(node:Node3D,root:Node3D)->Transform3D:
	var result := Transform3D.IDENTITY
	var current:Node3D = node
	while current != root and current != null:
		result = current.transform*result
		current = current.get_parent() as Node3D
	return result

func _refine(source:Mesh,asset_id:String,is_hoop:bool,fitted_up:Vector3)->Dictionary:
	var output := ArrayMesh.new()
	output.resource_name = "A01VisualRefinement_"+asset_id
	var bounds:AABB = source.get_aabb()
	var vertex_count:int = 0
	var maximum_displacement:float = 0.0
	var removed_fragments:Array=[]
	var seated_rims:Array=[]
	var lowest:float = INF
	var highest:float = -INF
	for point in _all_vertices(source):
		lowest = minf(lowest,point.dot(fitted_up))
		highest = maxf(highest,point.dot(fitted_up))
	for surface in range(source.get_surface_count()):
		var arrays:Array = source.surface_get_arrays(surface).duplicate(true)
		var vertices:PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var original:PackedVector3Array = vertices.duplicate()
		var indices:PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in range(vertices.size()): indices.append(i)
		if asset_id in ["specimen_bear","specimen_wolf"]:
			var trimmed:Dictionary=_trim_detached_neck_fragments(vertices,indices,bounds,asset_id)
			indices=trimmed.indices
			arrays[Mesh.ARRAY_INDEX]=indices
			removed_fragments.append({"surface":surface,"components":trimmed.components,"triangles":trimmed.triangles,"vertices":trimmed.vertices})
		if asset_id.begins_with("specimen_") or asset_id in ["mammoth_head","mammoth_chest","mammoth_pelvis","mammoth_neck"]:
			vertices = _smooth_body(vertices,indices,bounds,asset_id)
		for i in range(vertices.size()):
			var point:Vector3 = vertices[i]
			var q:Vector3 = (original[i]-bounds.position)/bounds.size.max(Vector3.ONE*.000001)
			if is_hoop:
				# Cross-section grows and sweeps in side view; upper/lower mounts are held.
				var weight:float = sin(clampf(q.y,0.0,1.0)*PI)
				weight *= weight
				point.x = bounds.get_center().x+(point.x-bounds.get_center().x)*(1.0+.33*weight)+bounds.size.y*.115*weight
				point.z = bounds.get_center().z+(point.z-bounds.get_center().z)*(1.0+.065*weight)
			elif asset_id.begins_with("specimen_"):
				var weight:float = _body_weight(q,asset_id)
				var fullness:float = .065 if asset_id == "specimen_deer" else .04
				point.x = bounds.get_center().x+(point.x-bounds.get_center().x)*(1.0+fullness*weight)
			elif asset_id in ["mammoth_front_leg","mammoth_back_leg"]:
				var weight:float = smoothstep(.12,.30,q.y)*(1.0-smoothstep(.70,.88,q.y))
				point.x = bounds.get_center().x+(point.x-bounds.get_center().x)*(1.0+.35*weight)
				point.z = bounds.get_center().z+(point.z-bounds.get_center().z)*(1.0+.30*weight)
			elif asset_id in ["mammoth_neck","mammoth_chest","mammoth_pelvis","mammoth_head"]:
				var axis:int = bounds.size.max_axis_index()
				var weight:float = smoothstep(.12,.32,q[axis])*(1.0-smoothstep(.68,.88,q[axis]))
				var fullness:float = .035 if asset_id=="mammoth_head" else .12
				for radial in range(3):
					if radial != axis: point[radial] = bounds.get_center()[radial]+(point[radial]-bounds.get_center()[radial])*(1.0+fullness*weight)
			if asset_id.begins_with("mammoth_"):
				# Fitted meshes can be tilted. Protect their actual native height
				# endpoints as well as the source longitudinal endpoint bands.
				var native_t:float = (original[i].dot(fitted_up)-lowest)/maxf(highest-lowest,.000001)
				var keep:float = smoothstep(.10,.24,native_t)*(1.0-smoothstep(.76,.90,native_t))
				point = original[i].lerp(point,keep)
			if asset_id in ["specimen_bear","specimen_wolf"]:
				# Local fullness cannot enlarge the canonical source envelope.
				point=point.clamp(bounds.position,bounds.end)
			vertices[i] = point
			maximum_displacement=maxf(maximum_displacement,point.distance_to(original[i]))
		if asset_id in ["mammoth_chest","mammoth_pelvis"]:
			var seated:Dictionary=_seat_socket_rims(vertices,asset_id,bounds)
			vertices=seated.vertices
			seated_rims.append({"surface":surface,"vertices":seated.count,"maximum_local_displacement":seated.maximum})
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if source.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
			var new_normals:PackedVector3Array = _normals(vertices,indices,arrays[Mesh.ARRAY_NORMAL])
			arrays[Mesh.ARRAY_NORMAL] = new_normals
			# Preserve UV tangent handedness, reproject into the refined surface plane.
			if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
				var tangents:PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				if tangents.size() == vertices.size()*4:
					for j in range(vertices.size()):
						var t := Vector3(tangents[j*4],tangents[j*4+1],tangents[j*4+2])
						t = (t-new_normals[j]*t.dot(new_normals[j])).normalized()
						tangents[j*4] = t.x
						tangents[j*4+1] = t.y
						tangents[j*4+2] = t.z
					arrays[Mesh.ARRAY_TANGENT] = tangents
		output.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
		output.surface_set_material(surface,source.surface_get_material(surface))
		vertex_count += vertices.size()
	return {"mesh":output,"vertices":vertex_count,"maximum_displacement":maximum_displacement,"removed_detached_neck_fragments":removed_fragments,"seated_socket_rims":seated_rims,"recipe":"protected_body_relief_smoothing" if asset_id.begins_with("specimen_") else "protected_bone_rounding"}

func _feature_protection(q:Vector3,asset_id:String)->float:
	# Measured source face landmarks. Keep eye/nose/mouth core and ears while
	# allowing outer cheek/neck fur to join the torso at a consistent scale.
	var center:=Vector3(.5,.75,.94) if asset_id=="specimen_bear" else Vector3(.5,.77,.95)
	var radii:=Vector3(.23,.18,.14) if asset_id=="specimen_bear" else Vector3(.22,.14,.12)
	var face:float=1.0-smoothstep(1.0,1.25,((q-center)/radii).length())
	var ears:float=smoothstep(.76,.80,q.y)*smoothstep(.65,.73,q.z)
	var feet:float=1.0-smoothstep(.15,.24,q.y)
	return maxf(maxf(face,ears),feet)

func _neck_weight(q:Vector3,asset_id:String)->float:
	return smoothstep(.32,.40,q.y)*(1.0-smoothstep(.81,.86,q.y))*smoothstep(.55,.65,q.z)*(1.0-smoothstep(.91,.97,q.z))*(1.0-_feature_protection(q,asset_id))

func _body_weight(q:Vector3,asset_id:String)->float:
	if asset_id.begins_with("mammoth_"):
		return smoothstep(.08,.23,q.y)*(1.0-smoothstep(.77,.92,q.y))*smoothstep(.06,.20,q.z)*(1.0-smoothstep(.80,.94,q.z))
	var head:float=smoothstep(.65,.81,q.z)*smoothstep(.40,.61,q.y)
	var top:float=1.0-smoothstep(.89,.98,q.y)
	if asset_id=="specimen_deer":top=1.0-smoothstep(.61,.74,q.y)
	var body:float=smoothstep(.15,.29,q.y)*top*smoothstep(.06,.17,q.z)*(1.0-head)
	if asset_id in ["specimen_bear","specimen_wolf"]:
		return maxf(body,_neck_weight(q,asset_id))*(1.0-_feature_protection(q,asset_id))
	return body

func _component_root(parents:Array[int],index:int)->int:
	# Reference-backed path compression preserves the connected components and
	# chosen roots while avoiding repeated walks down thousands of parent links.
	var root:int=index
	while parents[root]!=root:root=parents[root]
	while parents[index]!=index:
		var next:int=parents[index];parents[index]=root;index=next
	return root

func _trim_detached_neck_fragments(vertices:PackedVector3Array,indices:PackedInt32Array,bounds:AABB,asset_id:String)->Dictionary:
	# Only entire, disconnected, tiny non-facial neck components can disappear.
	# The large connected fur folds are instead deformed, not misclassified.
	var weld:Dictionary={};var mapping:=PackedInt32Array();var parents:Array[int]=[]
	var tolerance:float=maxf(bounds.size.length()*.000001,.0000001)
	for point in vertices:
		var key:=Vector3i(roundi(point.x/tolerance),roundi(point.y/tolerance),roundi(point.z/tolerance))
		if not weld.has(key):weld[key]=parents.size();parents.append(parents.size())
		mapping.append(weld[key])
	for j in range(0,indices.size(),3):
		var root:int=_component_root(parents,mapping[indices[j]])
		for k in [1,2]:parents[_component_root(parents,mapping[indices[j+k]])]=root
	var groups:Dictionary={}
	for j in range(vertices.size()):
		var root:int=_component_root(parents,mapping[j])
		var q:Vector3=(vertices[j]-bounds.position)/bounds.size.max(Vector3.ONE*.000001)
		if not groups.has(root):groups[root]={"vertices":0,"eligible":true}
		groups[root].vertices+=1
		groups[root].eligible=groups[root].eligible and _neck_weight(q,asset_id)>.2 and _feature_protection(q,asset_id)<.00001
	var removed:Dictionary={};var removed_vertices:int=0
	for root in groups:
		if groups[root].eligible and groups[root].vertices<=120:
			removed[root]=true;removed_vertices+=groups[root].vertices
	var kept:=PackedInt32Array()
	for j in range(0,indices.size(),3):
		if not removed.has(_component_root(parents,mapping[indices[j]])):
			kept.append_array(PackedInt32Array([indices[j],indices[j+1],indices[j+2]]))
	return {"indices":kept,"components":removed.size(),"triangles":(indices.size()-kept.size())/3,"vertices":removed_vertices}

func _smooth_body(vertices:PackedVector3Array,indices:PackedInt32Array,bounds:AABB,asset_id:String)->PackedVector3Array:
	# Position welding keeps UV seams together. Stronger torso-only smoothing
	# actually reduces coarse fur relief rather than hiding it with roughness.
	# It cannot erase baked fur shadows or disconnected lobes; those remain a
	# named asset limitation. No topology, UV, index or contact-plane change.
	var weld:Dictionary = {}
	var mapping := PackedInt32Array()
	var positions := PackedVector3Array()
	var tolerance:float = maxf(bounds.size.length()*.000001,.0000001)
	for point in vertices:
		var key := Vector3i(roundi(point.x/tolerance),roundi(point.y/tolerance),roundi(point.z/tolerance))
		if not weld.has(key):
			weld[key] = positions.size()
			positions.append(point)
		mapping.append(weld[key])
	var base:PackedVector3Array = positions.duplicate()
	var weights:=PackedFloat32Array();var neck_weights:=PackedFloat32Array()
	for point in base:
		var q:Vector3=(point-bounds.position)/bounds.size.max(Vector3.ONE*.000001)
		weights.append(_body_weight(q,asset_id))
		neck_weights.append(_neck_weight(q,asset_id) if asset_id in ["specimen_bear","specimen_wolf"] else 0.0)
	var is_fur:bool = asset_id in ["specimen_bear","specimen_wolf"]
	var limit:float = bounds.size.length()*(.018 if is_fur else .008)
	var passes:int = 24 if is_fur else 5
	for iteration in range(passes):
		var sums := PackedVector3Array()
		var counts := PackedInt32Array()
		sums.resize(positions.size())
		counts.resize(positions.size())
		for j in range(0,indices.size()-2,3):
			var a:int = mapping[indices[j]]
			var b:int = mapping[indices[j+1]]
			var c:int = mapping[indices[j+2]]
			sums[a] += positions[b]+positions[c]
			sums[b] += positions[a]+positions[c]
			sums[c] += positions[a]+positions[b]
			counts[a] += 2
			counts[b] += 2
			counts[c] += 2
		for j in range(positions.size()):
			var weight:float=weights[j] if iteration<14 else neck_weights[j]
			if counts[j]==0 or weight<=.00001:continue
			var delta:Vector3=positions[j].lerp(sums[j]/float(counts[j]),.62*weight)-base[j]
			var local_limit:float=lerpf(limit,bounds.size.length()*.027,neck_weights[j]) if is_fur else limit
			positions[j]=base[j]+delta.limit_length(local_limit*maxf(weights[j],neck_weights[j]))
	var result:PackedVector3Array = vertices.duplicate()
	for j in range(result.size()): result[j] = positions[mapping[j]]
	return result

func _normals(vertices:PackedVector3Array,indices:PackedInt32Array,old_normals:PackedVector3Array)->PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(vertices.size())
	for j in range(0,indices.size()-2,3):
		var a:int = indices[j]
		var b:int = indices[j+1]
		var c:int = indices[j+2]
		var face:Vector3 = (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
		if old_normals.size()>a and face.dot(old_normals[a])<0.0: face = -face
		result[a] += face
		result[b] += face
		result[c] += face
	# Restore normal continuity across source UV splits at identical positions.
	var sums:Dictionary = {}
	var keys:Array[Vector3i] = []
	for j in range(vertices.size()):
		var p:Vector3 = vertices[j]*1000000.0
		var key := Vector3i(roundi(p.x),roundi(p.y),roundi(p.z))
		keys.append(key)
		sums[key] = sums.get(key,Vector3.ZERO)+result[j]
	for j in range(result.size()):
		var normal:Vector3 = sums[keys[j]]
		result[j] = normal.normalized() if normal.length_squared()>.00000000000001 else (old_normals[j] if old_normals.size()>j else Vector3.UP)
	return result

func _all_vertices(mesh:Mesh)->PackedVector3Array:
	var points := PackedVector3Array()
	for surface in range(mesh.get_surface_count()): points.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return points

func _animal_seams(node:MeshInstance3D,asset_id:String)->int:
	# A transverse welt on fur read as a necklace; keep the quieter deer seam.
	if asset_id in ["specimen_bear","specimen_wolf"]:return 0
	var bounds:AABB = node.mesh.get_aabb()
	var points:PackedVector3Array = _all_vertices(node.mesh)
	var color:Color = Color("a67f51") if asset_id == "specimen_bear" else (Color("bca17d") if asset_id == "specimen_deer" else Color("a39a87"))
	var count:int = 0
	for location in [.67]:
		var path:PackedVector3Array = _section_path(points,bounds,2,location,true)
		if path.size()<8: continue
		var thickness:float = bounds.size.x*.0035
		_tube(node,path,thickness,color)
		count += 1
		# A second, sparse stitched thread follows the same surface; one mesh batch.
		var stitches:Array[PackedVector3Array] = []
		for j in range(1,path.size()-2,2):
			stitches.append(PackedVector3Array([path[j].lerp(path[j+1],.12)+Vector3.UP*thickness,path[j].lerp(path[j+1],.72)+Vector3.UP*thickness]))
		_tube_many(node,stitches,thickness*.38,Color("c4ab83"))
		count += 1
	return count

func _limb_seams(node:MeshInstance3D)->int:
	var bounds:AABB = node.mesh.get_aabb()
	var points:PackedVector3Array = _all_vertices(node.mesh)
	var count:int = 0
	for location in [.19,.79]:
		var path:PackedVector3Array = _section_path(points,bounds,1,location,false)
		if path.size()<12: continue
		path.append(path[0])
		_tube(node,path,minf(bounds.size.x,bounds.size.z)*.012,Color("c8b89b"))
		count += 1
	return count

func _section_path(vertices:PackedVector3Array,bounds:AABB,axis:int,location:float,upper_only:bool)->PackedVector3Array:
	var center:Vector3 = bounds.get_center()
	center[axis] = bounds.position[axis]+bounds.size[axis]*location
	if upper_only: center.y = bounds.position.y+bounds.size.y*.49
	var u:int = 0
	var v:int = 1 if axis==2 else 2
	var samples:int = 25 if upper_only else 32
	var angle_span:float = PI if upper_only else TAU
	var best := PackedFloat32Array()
	var found := PackedByteArray()
	var path := PackedVector3Array()
	best.resize(samples)
	found.resize(samples)
	path.resize(samples)
	var scale_u:float = maxf(bounds.size[u]*.5,.00001)
	var scale_v:float = maxf(bounds.size[v]*(.29 if upper_only else .5),.00001)
	for point in vertices:
		if absf(point[axis]-center[axis])>bounds.size[axis]*.032: continue
		var du:float = (point[u]-center[u])/scale_u
		var dv:float = (point[v]-center[v])/scale_v
		var angle:float = atan2(dv,du)
		if upper_only and (angle<PI*.12 or angle>PI*.88): continue
		if not upper_only and angle<0.0: angle+=TAU
		var slot:int = clampi(roundi(angle/angle_span*float(samples-1)),0,samples-1)
		var radius:float = du*du+dv*dv
		if found[slot]==0 or radius>best[slot]:
			path[slot] = point
			path[slot][axis] = center[axis]
			best[slot] = radius
			found[slot] = 1
	var result := PackedVector3Array()
	for j in range(samples):
		if found[j] == 1:
			var point:Vector3 = path[j]
			point[u] = center[u]+(point[u]-center[u])*1.012
			point[v] = center[v]+(point[v]-center[v])*1.012
			result.append(point)
	return result if result.size()>=samples*.7 else PackedVector3Array()

func _thread_material(color:Color)->StandardMaterial3D:
	var key:String = color.to_html()
	if not _material_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .94
		material.metallic = 0.0
		_material_cache[key] = material
	return _material_cache[key]

func _tube(parent:Node3D,points:PackedVector3Array,radius:float,color:Color)->void:
	var paths:Array[PackedVector3Array] = [points]
	_tube_many(parent,paths,radius,color)

func _tube_many(parent:Node3D,paths:Array[PackedVector3Array],radius:float,color:Color)->void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for points in paths:
		for segment in range(points.size()-1):
			var forward:Vector3 = (points[segment+1]-points[segment]).normalized()
			if forward.length_squared()<.5: continue
			var right:Vector3 = forward.cross(Vector3.UP if absf(forward.y)<.9 else Vector3.RIGHT).normalized()
			var up:Vector3 = forward.cross(right).normalized()
			var offset:int = vertices.size()
			for end in range(2):
				for side in range(6):
					var angle:float = float(side)/6.0*TAU
					var normal:Vector3 = right*cos(angle)+up*sin(angle)
					vertices.append(points[segment+end]+normal*radius)
					normals.append(normal)
					uvs.append(Vector2(float(side)/6.0,float(end)))
			for side in range(6):
				var a:int = offset+side
				var b:int = offset+(side+1)%6
				indices.append_array(PackedInt32Array([a,b+6,b,a,a+6,b+6]))
	if vertices.is_empty(): return
	var arrays:Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name = "A01SurfaceWelting"
	node.mesh = mesh
	node.material_override = _thread_material(color)
	node.set_meta("exhibit_style_detail",true)
	parent.add_child(node)
