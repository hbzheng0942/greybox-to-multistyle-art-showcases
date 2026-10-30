extends RefCounted
## A01 camera presentation partitions only the horizontal tabletop caps.
## Legs, the vertical apron, exhibits and all native collision remain intact.
## It never changes geometry, transforms, native shapes, visibility or materials.
## Normal/tangent reserialization error is measured separately in the unit fixture.

static func partition_support(source:MeshInstance3D,support_world_y:float,slab_thickness:float=.12)->Dictionary:
	if source==null or source.mesh==null:return {"ready":false,"reason":"missing_mesh"}
	if source.mesh is ArrayMesh and source.mesh.get_blend_shape_count()>0:return {"ready":false,"reason":"static_furniture_only"}
	var output:=ArrayMesh.new()
	var selected_surfaces:Array=[]
	var source_triangle_count:=0
	var selected_triangle_count:=0
	var surface_map:Array=[]
	for surface in range(source.mesh.get_surface_count()):
		if source.mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:return {"ready":false,"reason":"triangle_surfaces_only"}
		var arrays:Array=source.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in range(vertices.size()):indices.append(i)
		var selected:=PackedInt32Array();var opaque:=PackedInt32Array()
		for i in range(0,indices.size()-2,3):
			var a:Vector3=source.global_transform*vertices[indices[i]]
			var b:Vector3=source.global_transform*vertices[indices[i+1]]
			var c:Vector3=source.global_transform*vertices[indices[i+2]]
			var normal:Vector3=(b-a).cross(c-a).normalized()
			var top_face:bool=absf(a.y-support_world_y)<.015 and absf(b.y-support_world_y)<.015 and absf(c.y-support_world_y)<.015
			var bottom_face:bool=absf(a.y-(support_world_y-slab_thickness))<.015 and absf(b.y-(support_world_y-slab_thickness))<.015 and absf(c.y-(support_world_y-slab_thickness))<.015
			var is_support:bool=(top_face or bottom_face) and absf(normal.y)>.95
			var target:PackedInt32Array=selected if is_support else opaque
			target.append_array(PackedInt32Array([indices[i],indices[i+1],indices[i+2]]))
			if is_support:selected=target
			else:opaque=target
			source_triangle_count+=1
		for part in [{"indices":opaque,"fade":false},{"indices":selected,"fade":true}]:
			if part.indices.is_empty():continue
			var copied:Array=arrays.duplicate()
			copied[Mesh.ARRAY_INDEX]=part.indices
			var index:int=output.get_surface_count()
			output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,copied)
			output.surface_set_material(index,source.get_active_material(surface))
			surface_map.append({"output_surface":index,"source_surface":surface,"triangles":part.indices.size()/3,"support_only":part.fade})
			if part.fade:
				selected_surfaces.append(index)
				selected_triangle_count+=part.indices.size()/3
	return {"ready":not selected_surfaces.is_empty(),"mesh":output,"support_surfaces":selected_surfaces,"surface_map":surface_map,"source_triangles":source_triangle_count,"selected_triangles":selected_triangle_count,"scope":"geometry-identical slab-horizontal-cap partition; unintegrated; caller must keep original mesh and overrides for restoration"}
