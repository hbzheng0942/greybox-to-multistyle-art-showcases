extends RefCounted
## Dynamic canonical GLB loading. Source resources remain in art; meshes/textures are shared.
const PAINTED=preload("res://themes/halloween_07/painted_asset.gdshader")
const MANIFEST="res://../art/themes/halloween_07/model-bindings.json"
var sources: Dictionary={}
var cache: Dictionary={}
var fits: Array=[]
var errors: Array=[]
func _init() -> void:
	if FileAccess.file_exists(MANIFEST):sources=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)).sources
func has(id: String) -> bool:return sources.has(id)
func _collect(node: Node,p: Transform3D,boxes: Array) -> void:
	var q:=p
	if node is Node3D:q=p*node.transform
	if node is MeshInstance3D and node.mesh!=null:boxes.append(q*node.get_aabb())
	for child in node.get_children():_collect(child,q,boxes)
func _load(id: String) -> bool:
	if cache.has(id):return true
	if not has(id):return false
	var row: Dictionary=sources[id];var path:=ProjectSettings.globalize_path("res://../"+str(row.path))
	if FileAccess.get_sha256(path)!=row.sha256:errors.append(id+": source hash mismatch");return false
	var doc:=GLTFDocument.new();var state:=GLTFState.new()
	var code:=doc.append_from_file(path,state)
	if code!=OK:errors.append(id+": GLTF import "+str(code));return false
	var root:=doc.generate_scene(state) as Node3D
	if root==null:errors.append(id+": empty GLTF scene");return false
	for n in root.find_children("*","MeshInstance3D",true,false):
		if n.mesh is ArrayMesh:
			var source: ArrayMesh=n.mesh;var importer:=ImporterMesh.new()
			for i in source.get_surface_count():
				var original:=source.surface_get_material(i) as StandardMaterial3D
				var material: Material=original
				if original!=null and original.albedo_texture!=null:
					var painted:=ShaderMaterial.new();painted.shader=PAINTED
					painted.set_shader_parameter("albedo_texture",original.albedo_texture);painted.set_shader_parameter("albedo_factor",original.albedo_color)
					painted.set_shader_parameter("metallic_roughness",original.roughness_texture);painted.set_shader_parameter("metallic_factor",original.metallic);painted.set_shader_parameter("roughness_factor",original.roughness)
					painted.set_shader_parameter("warm_emission",0.75 if id=="h07_lantern" else (0.65 if id in ["h07_clocktower","h07_castle_keep","h07_facade_a","h07_facade_b"] else 0.0))
					painted.set_shader_parameter("city_surface_light",0.75 if id in ["h07_clocktower","h07_castle_keep","h07_facade_a","h07_facade_b"] else 0.0)
					painted.set_shader_parameter("readability_emission",0.09 if id=="h07_train" else 0.0)
					if id=="h07_hazard":painted.set_shader_parameter("warm_emission",1.6);painted.set_shader_parameter("hazard_pink_emission",2.4)
					material=painted
				importer.add_surface(source.surface_get_primitive_type(i),source.surface_get_arrays(i),[],{},material)
			importer.generate_lods(60.0,25.0,[]);n.mesh=importer.get_mesh();n.lod_bias=0.8
	var boxes:=[];_collect(root,Transform3D.IDENTITY,boxes)
	if boxes.is_empty():errors.append(id+": no geometry bounds");root.free();return false
	var bounds: AABB=boxes[0]
	for box: AABB in boxes:bounds=bounds.merge(box)
	cache[id]={"root":root,"bounds":bounds}
	return true
func place(id: String,parent: Node3D,p: Transform3D,envelope: Vector3,yaw: float,ident: String,distance:=500.0) -> Node3D:
	if not _load(id):return null
	var data: Dictionary=cache[id];var bounds: AABB=data.bounds
	var rotation:=Basis(Vector3.UP,yaw)
	var rotated: AABB=Transform3D(rotation,Vector3.ZERO)*bounds
	var size:=rotated.size
	var factor:=minf(envelope.x/size.x,minf(envelope.y/size.y,envelope.z/size.z))
	var container:=Node3D.new();container.name=ident;container.transform=p;container.set_meta("asset_id",id);container.set_meta("instance_id",ident);container.set_meta("scene_id","station");parent.add_child(container)
	var mesh_root: Node3D=data.root.duplicate();mesh_root.name="CanonicalG1";mesh_root.transform=Transform3D(rotation.scaled(Vector3.ONE*factor),-Vector3(rotated.get_center().x,rotated.position.y,rotated.get_center().z)*factor);container.add_child(mesh_root)
	for n in mesh_root.find_children("*","GeometryInstance3D",true,false):
		n.visibility_range_end=distance;n.visibility_range_end_margin=45.0;n.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	fits.append({"asset_id":id,"instance_id":ident,"source_path":sources[id].path,"source_sha256":sources[id].sha256,"source_bounds":{"min":[bounds.position.x,bounds.position.y,bounds.position.z],"size":[bounds.size.x,bounds.size.y,bounds.size.z]},"uniform_scale":factor,"yaw_degrees":rad_to_deg(yaw),"achieved_size_m":[size.x*factor,size.y*factor,size.z*factor],"envelope_m":[envelope.x,envelope.y,envelope.z],"origin":[p.origin.x,p.origin.y,p.origin.z],"world_basis":[[p.basis.x.x,p.basis.x.y,p.basis.x.z],[p.basis.y.x,p.basis.y.y,p.basis.y.z],[p.basis.z.x,p.basis.z.y,p.basis.z.z]],"visibility_end_m":distance,"material_policy":"canonical albedo/MR preserved; orange-pixel window emission, original paint retained, broad textured light bands; no albedo tint/quantization"})
	return container

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:
		for row: Dictionary in cache.values():
			if is_instance_valid(row.root):row.root.free()
		cache.clear()
