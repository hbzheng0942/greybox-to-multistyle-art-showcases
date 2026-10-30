extends RefCounted
## A ready registry record is admission data, not art/native acceptance.
var registry:Dictionary={}
var cache:Dictionary={}
var error:=""

func load_registry(path:String)->void:
	registry={}
	error=""
	if not FileAccess.file_exists(path):
		error="missing_registry"
		return
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("schema")!=1 or parsed.get("kind")!="a01-asset-registry" or not parsed.get("assets") is Dictionary:
		error="invalid_registry_schema"
		return
	registry=parsed

func prepare(group:Dictionary,catalog)->Dictionary:
	var aid:String=group.asset_id
	var records:Dictionary=registry.get("assets",{})
	if not records.has(aid): return {"status":"missing","reason":"missing_generated_model","asset_id":aid}
	var record:Dictionary=records[aid]
	if record.get("status")!="ready":return {"status":"missing","reason":"registry_status_"+str(record.get("status","unknown")),"asset_id":aid}
	var path:String=record.get("scene_path","")
	if not path.begins_with("res://") or ".." in path or path.get_extension() not in ["glb","gltf","tscn","scn"]:
		return {"status":"failed","reason":"invalid_scene_path","asset_id":aid}
	if not FileAccess.file_exists(path):return {"status":"failed","reason":"ready_file_missing","asset_id":aid}
	var expected:String=record.get("sha256","")
	if expected.length()!=64 or FileAccess.get_sha256(path)!=expected:return {"status":"failed","reason":"sha256_mismatch","asset_id":aid}
	var material_policy:Dictionary=record.get("material_policy",{})
	if not material_policy.is_empty():
		if material_policy.get("mode")!="cloth_matte" or float(material_policy.get("metallic",-1))!=0.0 or float(material_policy.get("roughness",0))<.75 or float(material_policy.get("roughness",2))>1.0:
			return {"status":"failed","reason":"invalid_material_policy","asset_id":aid}
	var key:=path+expected+JSON.stringify(material_policy)
	if not cache.has(key):
		var loaded=load(path)
		if not loaded is PackedScene or not catalog._is_static_scene_state(loaded.get_state()):
			return {"status":"failed","reason":"nonstatic_or_unsupported_scene","asset_id":aid}
		# Preserve an imported root transform beneath an identity adapter root.
		var wrapper:=Node3D.new()
		wrapper.name="AssetLocalGeometry"
		var imported:Node3D=loaded.instantiate()
		wrapper.add_child(imported)
		if not material_policy.is_empty() and not _apply_material_policy(imported,material_policy):
			wrapper.free()
			return {"status":"failed","reason":"unsupported_material_policy_surface","asset_id":aid}
		_set_owner(imported,wrapper)
		var wrapped:=PackedScene.new()
		wrapped.pack(wrapper)
		wrapper.free()
		cache[key]=wrapped
	var scene:PackedScene=cache[key]
	var fit:Dictionary=record.get("fit",{}).duplicate(true)
	var override:Dictionary=registry.get("bindings",{}).get(str(group.anchor_id),{})
	fit.merge(override.get("fit",{}),true)
	var mode:String=fit.get("mode","")
	if mode not in ["native_local","uniform_contain"]:return {"status":"failed","reason":"explicit_fit_mode_required","asset_id":aid}
	var rotation:=_v(fit.get("rotation_degrees",[0,0,0]))*PI/180.0
	var scale_value:=_v(fit.get("scale",[1,1,1]))
	if minf(scale_value.x,minf(scale_value.y,scale_value.z))<=0:return {"status":"failed","reason":"positive_scale_required","asset_id":aid}
	var transform:=Transform3D(Basis.from_euler(rotation).scaled(scale_value),_v(fit.get("offset",[0,0,0])))
	var instance:Node3D=scene.instantiate()
	var bounds:=_bounds(instance,Transform3D.IDENTITY)
	instance.free()
	if bounds.size.length()<.0001:return {"status":"failed","reason":"empty_visual_bounds","asset_id":aid}
	var report:Dictionary={"status":"loaded","asset_id":aid,"scene_path":path,"sha256":expected,"fit_mode":mode,"source_aabb":_box(bounds),"limiting_axis":null,"temporary_fit":mode=="uniform_contain"}
	if not material_policy.is_empty():report["material_policy"]=material_policy.duplicate(true)
	if mode=="uniform_contain":
		var anchor_transform:=_tr(group.anchor_world_transform)
		var world_box:=AABB(_v(group.native_world_aabb.min),_v(group.native_world_aabb.size))
		if group.has("support"):world_box.position.y=float(group.support.foot_plane_y)
		var target:AABB=anchor_transform.affine_inverse()*world_box
		var rotated:AABB=Transform3D(transform.basis,Vector3.ZERO)*bounds
		var ratios:=target.size/rotated.size.max(Vector3.ONE*.00001)
		var factor:=minf(ratios.x,minf(ratios.y,ratios.z))
		transform.basis=transform.basis.scaled(Vector3.ONE*factor)
		var achieved:AABB=Transform3D(transform.basis,Vector3.ZERO)*bounds
		transform.origin+=Vector3(target.get_center().x-achieved.get_center().x,target.position.y-achieved.position.y,target.get_center().z-achieved.get_center().z)
		report["limiting_axis"]=["x","y","z"][0 if ratios.x<=ratios.y and ratios.x<=ratios.z else (1 if ratios.y<=ratios.z else 2)]
		report["uniform_factor"]=factor
		report["target_local_aabb"]=_box(target)
		report["qualification"]="provisional_fit_requires_actual_native_review"
	else:
		report["qualification"]="native_local_transform_preserved_no_second_fit"
	report["achieved_local_aabb"]=_box(transform*bounds)
	report["fit_transform"]={"offset":_a(transform.origin),"basis_x":_a(transform.basis.x),"basis_y":_a(transform.basis.y),"basis_z":_a(transform.basis.z)}
	return {"status":"loaded","scene":scene,"local_transform":transform,"report":report}

func _bounds(node:Node3D,parent:Transform3D)->AABB:
	var current:=parent*node.transform
	var result:=AABB()
	var first:=true
	if node is MeshInstance3D and node.mesh!=null:
		result=current*node.mesh.get_aabb()
		first=false
	for child in node.get_children():
		if child is Node3D:
			var child_box:=_bounds(child,current)
			if child_box.size.length()>.00001:
				result=child_box if first else result.merge(child_box)
				first=false
	return result

func _tr(d:Dictionary)->Transform3D:
	return Transform3D(Basis(_v(d.basis_x),_v(d.basis_y),_v(d.basis_z)),_v(d.position))
func _v(a:Array)->Vector3:return Vector3(float(a[0]),float(a[1]),float(a[2]))
func _a(v:Vector3)->Array:return [v.x,v.y,v.z]
func _box(b:AABB)->Dictionary:return {"min":_a(b.position),"size":_a(b.size)}

func _set_owner(node:Node,root:Node)->void:
	node.owner=root
	node.scene_file_path="" # Flatten the imported instance when packing the wrapper.
	for child in node.get_children():_set_owner(child,root)

func _apply_material_policy(node:Node,policy:Dictionary)->bool:
	# Explicit registry opt-in only. Imported resources and texture pixels remain
	# canonical; each instance owns an independent, reversible material override.
	if node is MeshInstance3D and node.mesh!=null:
		for surface in range(node.mesh.get_surface_count()):
			var original=node.get_active_material(surface)
			if not original is StandardMaterial3D:return false
			var material:StandardMaterial3D=original.duplicate()
			material.metallic=0.0
			material.metallic_texture=null
			material.roughness=float(policy.roughness)
			material.roughness_texture=null
			node.set_surface_override_material(surface,material)
	for child in node.get_children():
		if not _apply_material_policy(child,policy):return false
	return true
