class_name ClayProductionKit
extends RefCounted
## Exact procedural profiles. Runtime poses come from SpatialTrack's transported frame.
var materials: Dictionary = {}
var material_noise: NoiseTexture2D
var built_meshes := 0
var triangles := 0
var step_max_m := 3.0
func clay(key: String, color: String, emission := 0.0) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "Clay_"+key
	m.albedo_color = Color(color)
	m.roughness = 0.87
	m.metallic_specular = 0.23
	if material_noise == null:
		var noise := FastNoiseLite.new()
		noise.seed = 2709
		noise.frequency = 0.032
		noise.fractal_octaves = 3
		material_noise = NoiseTexture2D.new()
		material_noise.width = 256
		material_noise.height = 256
		material_noise.noise = noise
		material_noise.seamless = true
		material_noise.as_normal_map = true
		material_noise.bump_strength = 0.3
	m.normal_enabled = true
	m.normal_texture = material_noise
	m.normal_scale = 0.18
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.45
	if emission > 0:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = emission
	materials[key] = m
	return m
func round_rect(width: float, bottom: float, top: float, bevel: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-width+bevel,top),Vector2(width-bevel,top),Vector2(width,top-bevel),Vector2(width,bottom+bevel),Vector2(width-bevel,bottom),Vector2(-width+bevel,bottom),Vector2(-width,bottom+bevel),Vector2(-width,top-bevel)])
func tunnel_profile(half_width: float, roof: float) -> PackedVector2Array:
	var result := PackedVector2Array([Vector2(-half_width,-0.42),Vector2(-half_width,7.2)])
	for j in range(1,33):
		var a := PI-float(j)*PI/32.0
		result.append(Vector2(cos(a)*half_width,7.2+sin(a)*(roof-7.2)))
	result.append(Vector2(half_width,-0.42))
	return result
func sweep(parent: Node3D, label: String, track: SpatialTrack, a: float, b: float, profile: PackedVector2Array, mat: Material, offset := Vector2.ZERO, inside := false, width_scale := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Bounded arc-length sampling; exact route frames preserve bank and roll.
	var span := b-a
	var steps := maxi(1,ceili(span/step_max_m))
	var n := profile.size()
	for i in steps:
		var s0 := lerpf(a,b,float(i)/steps)
		var s1 := lerpf(a,b,float(i+1)/steps)
		var poses: Array[Transform3D] = [track.pose(s0),track.pose(s1)]
		var ss := [s0,s1]
		for j in n:
			var j1 := (j+1)%n
			var tangent := (profile[j1]-profile[j]).normalized()
			var normal := Vector2(tangent.y,-tangent.x)*(1.0 if inside else -1.0)
			var vertices := [Vector2i(0,j),Vector2i(1,j),Vector2i(1,j1),Vector2i(0,j),Vector2i(1,j1),Vector2i(0,j1)]
			if inside: vertices.reverse()
			for ij in vertices:
				var pose := poses[ij.x]
				var p := profile[ij.y]+offset
				if width_scale: p.x *= track.width_at(ss[ij.x])
				st.set_normal((pose.basis.x*normal.x+pose.basis.y*normal.y).normalized())
				st.set_uv(Vector2(p.x,ss[ij.x]))
				st.add_vertex(pose*Vector3(p.x,p.y,0)-parent.position)
			triangles += 2
	var mesh := st.commit()
	built_meshes += 1
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	node.material_override = mat
	node.visibility_range_end = 1050
	node.visibility_range_end_margin = 100
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(node)
	return node
func mesh_piece(parent: Node3D, mesh: Mesh, pose: Transform3D, mat: Material, label := "KitPart") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	node.material_override = mat
	parent.add_child(node)
	node.transform = pose
	return node
func sphere(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 24
	m.rings = 12
	return m
func cylinder(radius: float, height: float, top_radius := -1.0) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius if top_radius < 0 else top_radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 24
	return m
