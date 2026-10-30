extends RefCounted
## Static authored draw batching only. Canonical per-item added_bounds are never replaced.
const CELL_METERS := 64.0
const MAX_INSTANCES := 64
const EQUIVALENCE_EPS_M := 0.001
const SETTINGS := ["visible","layers","cast_shadow","extra_cull_margin","ignore_occlusion_culling", "visibility_range_begin","visibility_range_end","visibility_range_begin_margin","visibility_range_end_margin","visibility_range_fade_mode","gi_mode","gi_lightmap_scale","lightmap_texel_scale","transparency","lod_bias","sorting_offset","sorting_use_aabb_center","visibility_parent","physics_interpolation_mode"]
var host:RefCounted
var world:Node3D
var cached_arrays:Dictionary={}
var box_meshes:Dictionary={}
var safe_materials:Dictionary={}
var groups:Dictionary={}
var setting_names:Array[String]=[]
var report:Dictionary={}

func build(builder:RefCounted) -> Dictionary:
	host=builder
	world=host.rebuild_world
	if world.has_meta("reconstruction_batching"):return world.get_meta("reconstruction_batching")
	var started:=Time.get_ticks_usec()
	var bounds_hash_before:=JSON.stringify(host.added_bounds).sha256_text()
	for key:Variant in host.crate_meshes:
		var mesh:Mesh=host.crate_meshes[key]
		cached_arrays[mesh.get_instance_id()]=str(key)
	var example:=MultiMeshInstance3D.new()
	var available:Dictionary={}
	for property:Dictionary in example.get_property_list():available[str(property.name)]=true
	for key:String in SETTINGS:
		if available.has(key):setting_names.append(key)
	example.free()
	report={"schema":1,"kind":"authored_static_multimesh_batching","source_sha256":FileAccess.get_sha256("res://../art/train-parkour/shared/tools/reconstruction_batcher.gd"),"cell_m":CELL_METERS,"max_instances":MAX_INSTANCES,"tolerance_m":EQUIVALENCE_EPS_M,"eligible_source_nodes":0,"batched_source_nodes":0,"batch_nodes":0,"singleton_groups_retained":0,"skipped":{},"groups":[],"failed_ids":[],"failed_group_count":0,"failed_tested_instance_count":0,"failed_groups_first_16":[],"max_corner_error_m":0.0,"max_transform_component_error":0.0,"max_normal_error":0.0,"added_bounds_count":host.added_bounds.size(),"added_bounds_sha256_before":bounds_hash_before,"preserved_settings":setting_names.filter(func(key):return key!="physics_interpolation_mode"),"static_setting_exception":{"physics_interpolation_mode":"OFF for immutable authored batches; resource physics interpolation explicitly false before writing transforms","reason":"Godot4.7.2 returns pending interpolation buffer as zeros during synchronous build; two-instance native Metal probe proves immediate real readback when OFF"},"render_acceptance":"pending native capture and performance profile","unit_box_material_contract":"Active reconstruction_surface world-position/world-normal shader only; unreviewed material semantics retained as original nodes","world_shader_sha256":FileAccess.get_sha256("res://../art/train-parkour/shared/tools/reconstruction_surface.gdshader")}
	var registered:Dictionary={}
	for item:Dictionary in host.added_bounds:registered[str(item.id)]=item
	for child:Node in world.get_children():
		if not child is MeshInstance3D:continue
		var node:=child as MeshInstance3D
		var ident:=str(node.get_meta("instance_id",""))
		var asset:=str(node.get_meta("asset_id",""))
		if not ident.begins_with("rebuild:") or not asset.begins_with("authored_"):continue
		if not registered.has(ident):_skip("no_canonical_added_bounds");continue
		if node.get_child_count()!=0 or node.get_script()!=null:_skip("children_or_script");continue
		if node.skin!=null:_skip("skinned_mesh");continue
		if node.custom_aabb.size!=Vector3.ZERO:_skip("custom_aabb");continue
		if node.visibility_range_begin!=0.0 or node.visibility_range_end!=0.0:_skip("per_object_distance_visibility");continue
		if node.mesh==null:_skip("missing_mesh");continue
		if node.material_override==null:_skip("no_shared_material_override");continue
		var has_surface_override:=false
		for surface:int in node.get_surface_override_material_count():
			if node.get_surface_override_material(surface)!=null:has_surface_override=true
		if has_surface_override:_skip("surface_override");continue
		var mat:=node.material_override
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader.code.contains("instance uniform"):_skip("instance_shader_parameters");continue
		var mesh_key:String
		var batched_mesh:Mesh
		var render_pose:=node.global_transform
		var source_box:AABB=node.mesh.get_aabb()
		var box_size:=Vector3.ONE
		if node.mesh is BoxMesh:
			if not _safe_unit_material(mat) or (node.material_overlay!=null and not _safe_unit_material(node.material_overlay)):_skip("unit_box_shader_semantics_unreviewed");continue
			var box:=node.mesh as BoxMesh
			box_size=box.size
			if box_size.x<=0 or box_size.y<=0 or box_size.z<=0:_skip("degenerate_box");continue
			var primitive_state:Dictionary={}
			for property:Dictionary in box.get_property_list():
				var name:String=str(property.name)
				if name in ["subdivide_width","subdivide_height","subdivide_depth","flip_faces","add_uv2","uv2_padding"]:primitive_state[name]=box.get(name)
			mesh_key="box:"+var_to_str(primitive_state)
			if not box_meshes.has(mesh_key):
				var unit:=box.duplicate() as BoxMesh
				unit.size=Vector3.ONE
				box_meshes[mesh_key]=unit
			batched_mesh=box_meshes[mesh_key]
			render_pose.basis=render_pose.basis.scaled_local(box_size)
		elif node.mesh is ArrayMesh and cached_arrays.has(node.mesh.get_instance_id()):
			mesh_key="cached_chamfer:"+str(node.mesh.get_instance_id())
			batched_mesh=node.mesh
		else:_skip("non_box_or_uncached_arraymesh");continue
		var settings:Dictionary={}
		for key:String in setting_names:settings[key]=node.get(key)
		var cell:=Vector3i((node.global_position/CELL_METERS).floor())
		var overlay_id:int=node.material_overlay.get_instance_id() if node.material_overlay!=null else 0
		var key:=mesh_key+"|material:"+str(mat.get_instance_id())+"|overlay:"+str(overlay_id)+"|settings:"+var_to_str(settings)+"|cell:"+str(cell)+"|scene:"+str(node.get_meta("scene_id",""))
		if not groups.has(key):groups[key]={"mesh":batched_mesh,"mesh_kind":"unit_box" if node.mesh is BoxMesh else "same_cached_chamfer_resource","material":mat,"overlay":node.material_overlay,"settings":settings,"cell":cell,"entries":[]}
		groups[key].entries.append({"node":node,"id":ident,"asset":asset,"scene":str(node.get_meta("scene_id","")),"source_pose":node.global_transform,"render_pose":render_pose,"source_box":source_box,"box_size":box_size,"source_record":registered[ident]})
		report.eligible_source_nodes+=1
	for key:String in groups:
		if report.failed_group_count>0:break
		var group:Dictionary=groups[key]
		var entries:Array=group.entries
		for first:int in range(0,entries.size(),MAX_INSTANCES):
			if report.failed_group_count>0:break
			var amount:int=mini(MAX_INSTANCES,entries.size()-first)
			if amount==1:report.singleton_groups_retained+=1;continue
			_batch(group,entries.slice(first,first+amount))
	var bounds_hash_after:=JSON.stringify(host.added_bounds).sha256_text()
	report.added_bounds_sha256_after=bounds_hash_after
	report.added_bounds_unchanged=bounds_hash_after==bounds_hash_before
	report.passed=report.failed_ids.is_empty() and report.added_bounds_unchanged
	report.elapsed_ms=(Time.get_ticks_usec()-started)/1000.0
	if not report.passed:host.errors.append("Static authored batching failed transform equivalence or canonical geometry preservation")
	world.set_meta("reconstruction_batching",report)
	assert(report.passed,"Static batch renderer/geometry equivalence failed; inspect reconstruction_batching metadata")
	return report

func _safe_unit_material(material:Material) -> bool:
	var ident:int=material.get_instance_id()
	if safe_materials.has(ident):return safe_materials[ident]
	var safe:=false
	if material.next_pass==null:
		if material is ShaderMaterial:
			# Reviewed active shader uses only world position and world normal; fragment ignores local vertex/UV/model scale.
			var shader:Shader=(material as ShaderMaterial).shader
			safe=shader!=null and shader.resource_path=="res://../art/train-parkour/shared/tools/reconstruction_surface.gdshader"
	safe_materials[ident]=safe
	return safe

func _skip(reason:String) -> void:
	report.skipped[reason]=int(report.skipped.get(reason,0))+1

func _batch(group:Dictionary,entries:Array) -> void:
	var center:=Vector3.ZERO
	for entry:Dictionary in entries:center+=(entry.render_pose as Transform3D).origin
	center/=float(entries.size())
	var multimesh:=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.mesh=group.mesh
	multimesh.instance_count=entries.size()
	var node:=MultiMeshInstance3D.new()
	node.name="ReconstructionAuthoredBatch_%d"%report.batch_nodes
	node.multimesh=multimesh
	node.material_override=group.material
	node.material_overlay=group.overlay
	for key:String in setting_names:node.set(key,group.settings[key])
	node.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(node)
	# These authored world batches never move. Disable interpolation before setting their permanent transforms.
	RenderingServer.multimesh_set_physics_interpolated(multimesh.get_rid(),false)
	node.global_transform=Transform3D(Basis.IDENTITY,center)
	var ids:Array[String]=[]
	var assets:Array[String]=[]
	var max_corner:=0.0
	var max_matrix:=0.0
	var max_normal:=0.0
	var failed:Array[String]=[]
	var actual_settings:Dictionary={}
	for key:String in setting_names:actual_settings[key]=node.get(key)
	var expected_settings:Dictionary=group.settings.duplicate()
	expected_settings["physics_interpolation_mode"]=Node.PHYSICS_INTERPOLATION_MODE_OFF
	var settings_match:bool=actual_settings==expected_settings
	var resources_match:bool=node.material_override==group.material and node.material_overlay==group.overlay and multimesh.mesh==group.mesh
	for i:int in entries.size():
		var entry:Dictionary=entries[i]
		var render_pose:Transform3D=entry.render_pose
		var local:=Transform3D(render_pose.basis,render_pose.origin-center)
		multimesh.set_instance_transform(i,local)
		# Check the actual stored GPU instance transform, not only the authored metadata.
		var actual:Transform3D=node.global_transform*multimesh.get_instance_transform(i)
		var original:Transform3D=entry.source_pose
		if not actual.is_finite() or absf(actual.basis.determinant())<1e-12:
			failed.append(str(entry.id))
			if report.failed_groups_first_16.size()<16:report.failed_groups_first_16.append({"reason":"singular_or_nonfinite_actual_readback","source_id":entry.id,"original_transform":host.transform_array(original),"expected_render_transform":host.transform_array(render_pose),"actual_readback_transform":host.transform_array(actual),"settings_match":settings_match,"resources_match":resources_match})
			break
		var source_box:AABB=entry.source_box
		var size:Vector3=entry.box_size
		var source_record:Dictionary=entry.source_record
		var registered:Transform3D=_from_array(source_record.mesh_to_world)
		var matrix_error:=_transform_error(original,registered)
		matrix_error=maxf(matrix_error,_transform_error(actual,render_pose))
		var corner_error:=0.0
		for n:int in 8:
			var point:=source_box.get_endpoint(n)
			var batched_point:Vector3=point/size if group.mesh_kind=="unit_box" else point
			corner_error=maxf(corner_error,(original*point).distance_to(actual*batched_point))
		var old_normals:=original.basis.inverse().transposed()
		var new_normals:=actual.basis.inverse().transposed()
		var normal_error:=0.0
		for axis:Vector3 in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:normal_error=maxf(normal_error,(old_normals*axis).normalized().distance_to((new_normals*axis).normalized()))
		max_corner=maxf(max_corner,corner_error)
		max_matrix=maxf(max_matrix,matrix_error)
		max_normal=maxf(max_normal,normal_error)
		if corner_error>EQUIVALENCE_EPS_M or matrix_error>EQUIVALENCE_EPS_M or normal_error>.00001 or not settings_match or not resources_match:failed.append(str(entry.id))
		ids.append(str(entry.id))
		assets.append(str(entry.asset))
	report.max_corner_error_m=maxf(report.max_corner_error_m,max_corner)
	report.max_transform_component_error=maxf(report.max_transform_component_error,max_matrix)
	report.max_normal_error=maxf(report.max_normal_error,max_normal)
	if not failed.is_empty():
		report.failed_group_count+=1
		report.failed_tested_instance_count+=failed.size()
		for ident:String in failed:
			if report.failed_ids.size()<16:report.failed_ids.append(ident)
		if report.failed_groups_first_16.size()<16 and (report.failed_groups_first_16.is_empty() or report.failed_groups_first_16[-1].get("reason","")!="singular_or_nonfinite_actual_readback"):report.failed_groups_first_16.append({"reason":"geometry_or_settings_equivalence","source_ids_first_16":failed.slice(0,16),"max_corner_error_m":max_corner,"max_transform_component_error":max_matrix,"max_normal_error":max_normal,"settings_match":settings_match,"resources_match":resources_match})
		node.free()
		return
	var batch_id:="rebuild:authored_batch:%d"%report.batch_nodes
	host._tag_tree(node,batch_id,"authored_static_multimesh_batch",str(entries[0].scene))
	# Index i always refers to source_instance_ids[i]; canonical source transforms remain in added_bounds.
	node.set_meta("source_instance_ids",ids)
	node.set_meta("source_asset_ids",assets)
	node.set_meta("source_geometry_mapping","instance index maps to canonical added_bounds source id; unit boxes scale by source local BoxMesh size")
	for entry:Dictionary in entries:(entry.node as MeshInstance3D).free()
	report.batched_source_nodes+=entries.size()
	report.batch_nodes+=1
	report.max_corner_error_m=maxf(report.max_corner_error_m,max_corner)
	report.max_transform_component_error=maxf(report.max_transform_component_error,max_matrix)
	report.max_normal_error=maxf(report.max_normal_error,max_normal)
	report.groups.append({"batch_id":batch_id,"mesh_kind":group.mesh_kind,"world_origin_m":host.array(center),"cell":[group.cell.x,group.cell.y,group.cell.z],"source_instance_ids":ids,"source_asset_ids":assets,"count":entries.size(),"material_and_mesh_resource_identity":resources_match,"render_settings_equal":settings_match,"render_settings_sha256":var_to_str(actual_settings).sha256_text(),"source_physics_interpolation_mode":group.settings.get("physics_interpolation_mode"),"batch_physics_interpolation_mode":node.physics_interpolation_mode,"max_corner_error_m":max_corner,"max_transform_component_error":max_matrix,"max_normal_error":max_normal})

func _from_array(a:Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[4],a[5],a[6]),Vector3(a[8],a[9],a[10])),Vector3(a[12],a[13],a[14]))

func _transform_error(a:Transform3D,b:Transform3D) -> float:
	var largest:=0.0
	for axis:int in 3:
		largest=maxf(largest,absf(a.origin[axis]-b.origin[axis]))
		for component:int in 3:largest=maxf(largest,absf(a.basis[axis][component]-b.basis[axis][component]))
	return largest
