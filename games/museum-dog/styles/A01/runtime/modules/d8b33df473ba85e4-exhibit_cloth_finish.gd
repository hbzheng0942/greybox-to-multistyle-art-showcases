extends RefCounted
## Generated exhibit cloth only. UVs arrive in metres / PATCH_M and retain
## their basis when the bone is picked up; no world-sliding projection.
const TEXTURES=preload("res://styles/A01/runtime/modules/8ae8b471957da1a2-surface_texture_source.gd")
const PATCH_M:float=.32

static func apply(material:StandardMaterial3D)->void:
	var maps:Dictionary=TEXTURES.maps("canvas",PATCH_M)
	material.albedo_texture=maps.albedo
	material.normal_enabled=true
	material.normal_texture=maps.normal
	material.normal_scale=.35
	material.roughness=1.0
	material.roughness_texture=maps.roughness
	material.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.metallic=0.0
	material.metallic_specular=.22
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.set_meta("a01_generated_cloth_patch_m",PATCH_M)
	material.set_meta("a01_generated_cloth_mapping","final fitting metric UV, tangent basis supplied; object attached")

static func tangents(vertices:PackedVector3Array,normals:PackedVector3Array,uvs:PackedVector2Array,indices:PackedInt32Array)->PackedFloat32Array:
	var along:=PackedVector3Array();var across:=PackedVector3Array()
	along.resize(vertices.size());across.resize(vertices.size())
	for j in range(0,indices.size(),3):
		var a:int=indices[j];var b:int=indices[j+1];var c:int=indices[j+2]
		var x:Vector3=vertices[b]-vertices[a];var y:Vector3=vertices[c]-vertices[a]
		var u:Vector2=uvs[b]-uvs[a];var v:Vector2=uvs[c]-uvs[a]
		var determinant:float=u.x*v.y-u.y*v.x
		if absf(determinant)<.00000000001:continue
		var tangent:Vector3=(x*v.y-y*u.y)/determinant
		var bitangent:Vector3=(y*u.x-x*v.x)/determinant
		for k in [a,b,c]:along[k]+=tangent;across[k]+=bitangent
	var result:=PackedFloat32Array()
	for j in range(vertices.size()):
		var n:Vector3=normals[j]
		var t:Vector3=(along[j]-n*n.dot(along[j])).normalized()
		if t.length_squared()<.5:t=n.cross(Vector3.UP if absf(n.y)<.95 else Vector3.RIGHT).normalized()
		var sign_value:float=-1.0 if n.cross(t).dot(across[j])<0 else 1.0
		result.append_array(PackedFloat32Array([t.x,t.y,t.z,sign_value]))
	return result

static func record_basis_packing(mesh:ArrayMesh,normals:PackedVector3Array,tangents_before:PackedFloat32Array)->void:
	# ArrayMesh packs normals/tangents internally. Record both the supplied
	# orthogonal basis and the actual round-trip error, rather than pretending
	# that unpacked normals retain float32 precision.
	var arrays:Array=mesh.surface_get_arrays(0)
	var packed_normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var packed_tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
	var dot_error:float=0.0;var normal_error:float=0.0;var tangent_error:float=0.0
	for j in range(normals.size()):
		var t:=Vector3(tangents_before[4*j],tangents_before[4*j+1],tangents_before[4*j+2])
		var after:=Vector3(packed_tangents[4*j],packed_tangents[4*j+1],packed_tangents[4*j+2])
		dot_error=maxf(dot_error,absf(normals[j].dot(t)))
		normal_error=maxf(normal_error,normals[j].distance_to(packed_normals[j]))
		tangent_error=maxf(tangent_error,t.distance_to(after))
	mesh.set_meta("a01_cloth_basis_packing",{"prepack_maximum_normal_tangent_dot":dot_error,"normal_roundtrip_max_error":normal_error,"tangent_roundtrip_max_error":tangent_error,"derived_packed_dot_bound":dot_error+normal_error+tangent_error+normal_error*tangent_error})

static func stitches(specs:Array,bounds:AABB,fitted:Transform3D,sampler:Callable)->Dictionary:
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	var colors:=PackedColorArray();var indices:=PackedInt32Array()
	var inverse:Transform3D=fitted.affine_inverse();var count:int=0
	for spec in specs:
		var radius_sum:float=0.0
		for radius in spec.edge_radii:radius_sum+=radius
		var radius:float=radius_sum/float(spec.edge_radii.size())
		var right:Vector3=Vector3.UP.cross(spec.axis)
		var metre_radius:float=radius*.90*(fitted.basis*right).length()
		var stitch_count:int=clampi(roundi(TAU*metre_radius/.032),24,40)
		var thread:Color=spec.colors[0]*Color(.89,.89,.89,1.0)
		for stitch in range(stitch_count):
			var angle:float=TAU*(float(stitch)+.035*sin(float(stitch)*2.37))/float(stitch_count)
			var half_span:float=.0055/maxf(metre_radius,.0001)
			var points:=PackedVector3Array();var surface_normals:=PackedVector3Array()
			for step in range(3):
				var theta:float=angle+float(step-1)*half_span
				var point:Vector3=sampler.call(spec,.90,theta)
				var du:Vector3=sampler.call(spec,.90,theta+.001)-sampler.call(spec,.90,theta-.001)
				var dv:Vector3=sampler.call(spec,.901,theta)-sampler.call(spec,.899,theta)
				var n:Vector3=(fitted.basis.inverse().transposed()*du.cross(dv).normalized()).normalized()
				points.append(fitted*point+n*.00055);surface_normals.append(n)
			var offset:int=vertices.size()
			for step in range(3):
				var forward:Vector3=(points[mini(step+1,2)]-points[maxi(step-1,0)]).normalized()
				var radial:Vector3=forward.cross(surface_normals[step]).normalized()
				var up:Vector3=forward.cross(radial).normalized()
				for side in range(6):
					var phi:float=TAU*float(side)/6.0
					var n:Vector3=radial*cos(phi)+up*sin(phi)
					vertices.append((inverse*(points[step]+n*.00065)).clamp(bounds.position,bounds.end))
					normals.append((fitted.basis.transposed()*n).normalized());colors.append(thread)
			for segment in range(2):
				for side in range(6):
					var a:int=offset+segment*6+side;var b:int=offset+segment*6+(side+1)%6
					indices.append_array(PackedInt32Array([a,b+6,b,a,a+6,b+6]))
			count+=1
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.resource_name="A01FineSocketStitches"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return {"mesh":mesh,"stitches":count,"triangles":indices.size()/3,"thread_diameter_m":.0013,"stitch_length_m":.011}
