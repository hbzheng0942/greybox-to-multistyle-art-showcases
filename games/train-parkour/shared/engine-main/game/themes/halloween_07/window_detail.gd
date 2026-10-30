extends RefCounted
## A closed annular casing in front of the existing solid wall. No boolean wall cut.
## Local +Z faces the viewer; dimensional reveal/tracery stay inside the old envelope.

static func contours(w: float, h: float, pointed: bool) -> Array:
	if not pointed:
		return [PackedVector2Array([Vector2(-w*.5,-h*.5),Vector2(w*.5,-h*.5),Vector2(w*.5,h*.5),Vector2(-w*.5,h*.5)]),PackedVector2Array([Vector2(-w*.41,-h*.43),Vector2(w*.41,-h*.43),Vector2(w*.41,h*.43),Vector2(-w*.41,h*.43)])]
	return [PackedVector2Array([Vector2(-w*.5,-h*.5),Vector2(w*.5,-h*.5),Vector2(w*.5,h*.18),Vector2(w*.29,h*.49),Vector2(0,h*.72),Vector2(-w*.29,h*.49),Vector2(-w*.5,h*.18)]),PackedVector2Array([Vector2(-w*.41,-h*.43),Vector2(w*.41,-h*.43),Vector2(w*.41,h*.16),Vector2(w*.24,h*.44),Vector2(0,h*.635),Vector2(-w*.24,h*.44),Vector2(-w*.41,h*.16)])]

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v: Vector3 in [a,b,c,a,c,d]: st.add_vertex(v)

static func ring_mesh(outer: PackedVector2Array, inner: PackedVector2Array, back: float, front: float) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Beveled front edge, a continuous front face, and real inner reveal depth.
	var bevel := minf(.045, (front-back)*.2)
	var loops := []
	for spec: Array in [[outer,back,1.0],[outer,front-bevel,1.0],[outer,front,.985],[inner,front,1.025],[inner,front-bevel,1.0],[inner,back,1.0]]:
		var ring := PackedVector3Array()
		for q: Vector2 in spec[0]:ring.append(Vector3(q.x*float(spec[2]),q.y*float(spec[2]),float(spec[1])))
		loops.append(ring)
	for k in loops.size():
		var next_k := (k+1)%loops.size()
		for i in outer.size():
			var j := (i+1)%outer.size()
			_quad(st,loops[k][i],loops[k][j],loops[next_k][j],loops[next_k][i])
	st.generate_normals();return st.commit()

static func _strip(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var n := (b-a).normalized().orthogonal()*width*.5
	return PackedVector2Array([a+n,a-n,b-n,b+n])

static func grille(aperture: PackedVector2Array, w: float, h: float, pointed: bool) -> Array:
	var strips := []
	var width := clampf(w*.025,.055,.13)
	if pointed:
		# Three seated uprights; the side uprights turn into two lancet heads.
		# Upper panes no longer carry disconnected vertical prison bars.
		strips.append(_strip(Vector2(0,-h),Vector2(0,h),width*1.2))
		for side: float in [-1.0,1.0]:
			var x := side*w*.205
			strips.append(_strip(Vector2(x,-h),Vector2(x,h*.14),width))
			var last := Vector2(x,h*.14)
			for j in range(1,9):
				var t := float(j)/8.0
				var q := Vector2(x*(1.0-t*t),h*(.14+.36*t))
				strips.append(_strip(last,q,width));last=q
		for y: float in [-h*.17,h*.14]:strips.append(_strip(Vector2(-w,y),Vector2(w,y),width*.85))
	else:
		strips.append(_strip(Vector2(0,-h),Vector2(0,h),width*1.1))
		strips.append(_strip(Vector2(-w,h*.02),Vector2(w,h*.02),width))
	var clipped := []
	for strip: PackedVector2Array in strips:
		for polygon: PackedVector2Array in Geometry2D.intersect_polygons(strip,aperture):
			if polygon.size()>=3:clipped.append(polygon)
	return clipped

static func build(ctx: RefCounted, p: Transform3D, side: float, w: float, h: float, glass: String, pointed: bool=true) -> void:
	var frame := p;frame.basis=frame.basis*Basis(Vector3.UP,-side*PI/2)
	var profiles := contours(w,h,pointed)
	var depth := clampf(w*.10,.20,.43)
	var outer: PackedVector2Array=profiles[0];var inner: PackedVector2Array=profiles[1]
	var token := "window_casing_v2_"+str(w)+"_"+str(h)+"_"+str(pointed)
	if not ctx.shape_cache.has(token):ctx.shape_cache[token]=ring_mesh(outer,inner,.07,.16+depth)
	ctx._inst(ctx.shape_cache[token],frame,"window_frame",token)
	# The pocket closes against the host wall. Glass is behind the lead and front stone.
	ctx._prism(frame.translated_local(Vector3(0,0,.105)),inner,.025,"ink","window_pocket_v2")
	var glass_key: String={"window":"glazing_lit","window_dim":"glazing_dim","window_dark":"glazing_dark"}.get(glass,"glazing_dark")
	ctx._prism(frame.translated_local(Vector3(0,0,.17)),inner,.035,glass_key,"window_glazing_v2")
	var bead_outer := PackedVector2Array();var bead_inner := PackedVector2Array()
	for q: Vector2 in inner:
		bead_outer.append(q*1.012);bead_inner.append(q*.967)
	var bead_id := token+"_rebate"
	if not ctx.shape_cache.has(bead_id):ctx.shape_cache[bead_id]=ring_mesh(bead_outer,bead_inner,.20,.30)
	ctx._inst(ctx.shape_cache[bead_id],frame,"window_lead",bead_id)
	# Clipped ends overlap the inner bead, so bars seat into the frame at the crown and sill.
	var lead_id := token+"_tracery"
	if not ctx.shape_cache.has(lead_id):
		var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for poly: PackedVector2Array in grille(inner,w,h,pointed):
			st.append_from(ctx._prism_mesh(poly,.10,"window_fitted_lead_v2"),0,Transform3D.IDENTITY)
		ctx.shape_cache[lead_id]=st.commit()
	ctx._inst(ctx.shape_cache[lead_id],frame.translated_local(Vector3(0,0,.285)),"window_lead",lead_id)
	ctx._profile(p.translated_local(Vector3(-side*.1,-h*.5-.22,0)),1.2,w+.65,[Vector2(-.18,.88),Vector2(0,1),Vector2(.20,.98)],"window_frame")
