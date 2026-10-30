extends "res://scripts/art/production/clay_kit.gd"
## Same sampled profiles, with continuous normals on curved portions. Sharp corners stay sharp.
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
				var current: int=ij.y
				var previous_tangent:=(profile[current]-profile[(current-1+n)%n]).normalized()
				var next_tangent:=(profile[(current+1)%n]-profile[current]).normalized()
				var vertex_normal:=normal
				if previous_tangent.dot(next_tangent)>.75:
					var smooth_tangent:=(previous_tangent+next_tangent).normalized()
					vertex_normal=Vector2(smooth_tangent.y,-smooth_tangent.x)*(1.0 if inside else -1.0)
				st.set_normal((pose.basis.x*vertex_normal.x+pose.basis.y*vertex_normal.y).normalized())
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
