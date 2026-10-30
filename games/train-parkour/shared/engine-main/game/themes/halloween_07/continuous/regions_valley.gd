extends RefCounted
## N06–N08 only. Shared terrain, travel surfaces, functional props and the cliff/underpass bridge belong to core.
var features: Dictionary = {}

func build(ctx: RefCounted, region: Dictionary) -> Dictionary:
	features = {}
	# Region-owned material map: far districts can enter an airborne close camera.
	# Preserve authored paint detail there without changing the frozen sample palette.
	ctx.mats=ctx.mats.duplicate()
	var far_masonry:ShaderMaterial=ctx.mats.violet.duplicate()
	far_masonry.set_shader_parameter("paint",Color("30334c"))
	ctx.mats["far2"]=far_masonry
	ctx.metrics.tracks = region.tracks.duplicate()
	match str(region.id):
		"N06": _crypt(ctx)
		"N07": _valley(ctx)
		"N08": _return_city(ctx)
	ctx.metrics["features"] = features.duplicate(true)
	ctx.metrics["shared_bridge_emitted"] = false
	ctx.metrics["ground_emitted"] = false
	return {"features": features.duplicate(true), "shared_bridge_emitted": false, "ground_emitted": false}

func _note(name: String, accepted: bool) -> void:
	if not features.has(name): features[name] = {"emitted": 0, "accepted_envelopes": 0, "rejected": 0}
	features[name]["accepted_envelopes" if accepted else "rejected"] += 1

func _emit(name: String, amount: int = 1) -> void:
	if not features.has(name): features[name] = {"emitted": 0, "accepted_envelopes": 0, "rejected": 0}
	features[name].emitted += amount

func _clear(ctx: RefCounted, p: Transform3D, size: Vector3, feature: String, margin: float = 4.0) -> bool:
	var accepted: bool = ctx.can_place(p, size, margin)
	_note(feature, accepted)
	return accepted

func _box(ctx: RefCounted, p: Transform3D, size: Vector3, key: String, feature: String, margin: float = 4.0) -> bool:
	if not _clear(ctx, p, size, feature, margin): return false
	ctx._box(p, size, key); _emit(feature)
	return true

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

func _ccw(polygon: PackedVector2Array) -> PackedVector2Array:
	var points := polygon.duplicate(); var signed_area := 0.0
	for i in points.size():
		var a: Vector2=points[i]; var b: Vector2=points[(i+1)%points.size()]
		signed_area += a.x*b.y-b.x*a.y
	if signed_area<0:points.reverse()
	return points

func _prism(st: SurfaceTool, polygon: PackedVector2Array, depth: float) -> void:
	polygon=_ccw(polygon)
	var indices := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, indices.size(), 3):
		var a: Vector2 = polygon[indices[i]]; var b: Vector2 = polygon[indices[i + 1]]; var c: Vector2 = polygon[indices[i + 2]]
		_tri(st, Vector3(a.x,a.y,-depth/2),Vector3(c.x,c.y,-depth/2),Vector3(b.x,b.y,-depth/2))
		_tri(st, Vector3(a.x,a.y,depth/2),Vector3(b.x,b.y,depth/2),Vector3(c.x,c.y,depth/2))
	for i in polygon.size():
		var a: Vector2 = polygon[i]; var b: Vector2 = polygon[(i + 1) % polygon.size()]
		_tri(st,Vector3(a.x,a.y,-depth/2),Vector3(b.x,b.y,-depth/2),Vector3(b.x,b.y,depth/2))
		_tri(st,Vector3(a.x,a.y,-depth/2),Vector3(b.x,b.y,depth/2),Vector3(a.x,a.y,depth/2))

func _solid_loft(ctx: RefCounted, p0: Transform3D, p1: Transform3D, section: PackedVector2Array, tools: Dictionary, key: String, feature: String) -> void:
	section=_ccw(section)
	var vertices := PackedVector3Array()
	for p: Transform3D in [p0, p1]:
		for q: Vector2 in section: vertices.append(p * Vector3(q.x,q.y,0))
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for v: Vector3 in vertices: bounds = bounds.expand(v)
	if not _clear(ctx, Transform3D(Basis.IDENTITY, bounds.get_center()), bounds.size, feature, 3.0): return
	if not tools.has(key):
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); tools[key] = st
	var st: SurfaceTool = tools[key]; _emit(feature)
	for i in 4:
		var n := (i + 1) % 4
		_tri(st,vertices[i],vertices[n+4],vertices[n]);_tri(st,vertices[i],vertices[i+4],vertices[n+4])
	_tri(st,vertices[0],vertices[1],vertices[2]);_tri(st,vertices[0],vertices[2],vertices[3])
	_tri(st,vertices[4],vertices[6],vertices[5]);_tri(st,vertices[4],vertices[7],vertices[6])

func _commit_loft(ctx: RefCounted, tools: Dictionary, ident: String) -> void:
	for key: String in tools:
		var st: SurfaceTool = tools[key]; st.generate_normals()
		ctx._mesh(st.commit(), Transform3D.IDENTITY, key, ident)

func _rib(ctx: RefCounted, p: Transform3D, half: float, spring: float, rise: float, depth: float, name: String) -> void:
	# Each solid wedge has its own conservative envelope. The central void is never treated as a solid box.
	var tools: Array[SurfaceTool] = []
	for i in 2:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); tools.append(st)
	var counts := [0,0]
	for i in 24:
		var a := i * PI/24 + 0.004; var b := (i + 1) * PI/24 - 0.004
		var polygon := PackedVector2Array([Vector2(cos(a)*half,spring+sin(a)*rise),Vector2(cos(b)*half,spring+sin(b)*rise),Vector2(cos(b)*(half+1.25),spring+sin(b)*(rise+1.25)),Vector2(cos(a)*(half+1.25),spring+sin(a)*(rise+1.25))])
		var bounds := AABB(p * Vector3(polygon[0].x,polygon[0].y,-depth/2),Vector3.ZERO)
		for q: Vector2 in polygon:
			for z in [-depth/2,depth/2]: bounds = bounds.expand(p * Vector3(q.x,q.y,z))
		if not _clear(ctx,Transform3D(Basis.IDENTITY,bounds.get_center()),bounds.size,name,3.0): continue
		var material_index := int(i%4==0); _prism(tools[material_index],polygon,depth); counts[material_index] += 1; _emit(name)
	var mesh := ArrayMesh.new()
	for i in 2:
		if counts[i] == 0: continue
		tools[i].generate_normals(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tools[i].commit_to_arrays())
		mesh.surface_set_material(mesh.get_surface_count()-1,ctx.mats["warm_stone" if i==1 else "stone"])
	if mesh.get_surface_count()>0: ctx._inst(mesh,p,"",name+"_"+str(p.origin))

func _fixture(ctx: RefCounted, p: Transform3D, ident: String, power: float = 34.0, radius: float = 31.0) -> void:
	var envelope := Vector3(1.65,2.8,1.65)
	if not _clear(ctx,p.translated_local(Vector3(0,1.4,0)),envelope,"caged_pumpkin",2.0): return
	var model: Node3D = ctx.place_model("h07_lantern",p,envelope,0,ident,360.0)
	if model == null: return
	_emit("caged_pumpkin")
	_box(ctx,p.translated_local(Vector3(0,3.0,0)),Vector3(0.13,2.1,0.13),"ink","fixture_chain",1.5)
	ctx.add_light(p.translated_local(Vector3(0,1.15,0)).origin,power,radius)

func _standing_fixture(ctx: RefCounted, p: Transform3D, ident: String) -> void:
	var ground:float=ctx.ground_y(p.origin)-0.7
	var base:=p;base.origin.y=ground
	var h:=p.origin.y-ground+4.05
	if not _clear(ctx,base.translated_local(Vector3(0,h*0.5,0)),Vector3(1.2,h,1.2),"grounded_lamp_post",1.5):return
	ctx._profile(base,0.65,0.65,[Vector2(0,1.8),Vector2(0.8,1.8),Vector2(1.1,0.8),Vector2(h-0.4,0.8),Vector2(h,1.15)],"ink")
	_emit("grounded_lamp_post")
	_fixture(ctx,p,ident)

func _ghost(ctx: RefCounted, p: Transform3D, side: float, w: float, h: float, ident: String) -> void:
	if not _clear(ctx,p,Vector3(0.08,h,w),"wall_paint",2.0): return
	ctx._mural(p,side,w,h,ident); _emit("wall_paint")

func _crypt(ctx: RefCounted) -> void:
	ctx.use_scene("tunnel")
	var track: SpatialTrack = ctx.route.tracks.tunnel
	var half := float(track.enclosure_half_width)-1.0
	var inner_top := float(track.ceiling)-4.5 # Actual original shell intrados13.5; logical ceiling18 remains unchanged.
	var spring := 8.0; var rise := inner_top-spring
	var step := 10.0; var chunk_tools: Dictionary = {}
	for bay in ceili(track.length/step):
		var a := minf(bay*step,track.length); var b := minf((bay+1)*step,track.length)
		var p0: Transform3D = ctx.upright_pose("tunnel",a); var p1: Transform3D = ctx.upright_pose("tunnel",b)
		for side in [-1.0,1.0]:
			var wall := PackedVector2Array([Vector2(side*half,-1.3),Vector2(side*(half+2.4),-1.3),Vector2(side*(half+2.4),spring),Vector2(side*half,spring)])
			_solid_loft(ctx,p0,p1,wall,chunk_tools,"violet","curved_crypt_wall")
		for arc in 14:
			var t0 := float(arc)*PI/14; var t1 := float(arc+1)*PI/14
			var q := PackedVector2Array([Vector2(cos(t0)*half,spring+sin(t0)*rise),Vector2(cos(t1)*half,spring+sin(t1)*rise),Vector2(cos(t1)*(half+2.4),spring+sin(t1)*(rise+2.2)),Vector2(cos(t0)*(half+2.4),spring+sin(t0)*(rise+2.2))])
			_solid_loft(ctx,p0,p1,q,chunk_tools,"soffit","curved_crypt_vault")
		if bay%6==5 or bay==ceili(track.length/step)-1:
			_commit_loft(ctx,chunk_tools,"curved_thick_crypt_shell");chunk_tools={}
	for bay in ceili(track.length/42.0)+1:
		var s := minf(bay*42.0,track.length); var p: Transform3D = ctx.upright_pose("tunnel",s)
		_rib(ctx,p,16.0,8.0,rise-0.3,1.2,"crypt_inner_vault_rib")
		for side in [-1.0,1.0]:
			var column := p.translated_local(Vector3(side*16,-0.4,0))
			if _clear(ctx,column.translated_local(Vector3(0,4.3,0)),Vector3(3.2,9.4,3.2),"crypt_colonnade",3.0):
				ctx._profile(column,2.6,2.6,[Vector2(0,1.18),Vector2(0.5,1.18),Vector2(0.9,0.78),Vector2(7.5,0.78),Vector2(7.8,1),Vector2(8.5,1.2)],"stone"); _emit("crypt_colonnade")
			_fixture(ctx,p.translated_local(Vector3(side*13.8,5.8,0)),"H07CryptLamp_"+str(bay)+"_"+str(side),42,34)
			_box(ctx,p.translated_local(Vector3(side*14.8,9.0,0)),Vector3(2.0,0.18,0.22),"ink","crypt_bracket",2.0)
			if bay%2==0:
				_crypt_chapel(ctx,p,side,bay)
				_fixture(ctx,p.translated_local(Vector3(side*33.8,5.0,15)),"H07CryptOuterLamp_"+str(bay)+"_"+str(side),36,31)
			var niche := p.translated_local(Vector3(side*(half-0.12),3.1,12))
			if _clear(ctx,niche,Vector3(1.3,7,6.3),"crypt_pointed_niche",3.0): ctx._gothic_window(niche,side,5.2,5.6,"window_dim" if bay%3==0 else "window_dark"); _emit("crypt_pointed_niche")
			if bay%3==1: _ghost(ctx,p.translated_local(Vector3(side*(half-0.05),3.5,-11)),side,11,7.6,"crypt_wall_ghost")
	for end in [0.0,float(track.length)]:
		var p: Transform3D = ctx.upright_pose("tunnel",end)
		_rib(ctx,p,half-0.1,spring,rise,5.0,"crypt_thick_portal")
		for side in [-1.0,1.0]:
			var anchor := p.translated_local(Vector3(side*(half+4.3),0,0))
			var ground := _footing_ground(ctx,anchor,Vector3(7,1,9));var h := maxf(18,p.origin.y+20-ground)
			var base := anchor; base.origin.y=ground
			if _clear(ctx,base.translated_local(Vector3(0,h/2,0)),Vector3(7,h,9),"crypt_gateway_buttress"):
				ctx._profile(base,7,9,[Vector2(0,1.2),Vector2(2,1.2),Vector2(h-2,0.9),Vector2(h-1,1.08),Vector2(h,1.08)],"violet"); _emit("crypt_gateway_buttress")
			_fixture(ctx,p.translated_local(Vector3(side*(half-2.0),5.4,4.0 if end==0 else -4.0)),"H07CryptPortalLamp_"+str(end)+"_"+str(side))
	for side in [-1.0,1.0]: _keep(ctx,"tunnel",0,side*78,Vector3(38,78,62),"H07CryptGateKeep_"+str(side),-8)

func _footing_ground(ctx: RefCounted, p: Transform3D, size: Vector3) -> float:
	var floor_y: float = ctx.ground_y(p.origin)
	for x in [-size.x*0.5,size.x*0.5]:
		for z in [-size.z*0.5,size.z*0.5]: floor_y=minf(floor_y,ctx.ground_y(p*Vector3(x,0,z)))
	return floor_y

func _keep(ctx: RefCounted, track_id: String, s: float, side: float, envelope: Vector3, ident: String, level_offset: float = -12.0, asset: String = "h07_castle_keep") -> bool:
	for retreat in [0.0,32.0,66.0]:
		var p: Transform3D = ctx.upright_pose(track_id,s,side+signf(side)*retreat)
		var ground := _footing_ground(ctx,p,envelope+Vector3(3,0,3));p.origin.y=maxf(ground+5.0,p.origin.y+level_offset)
		var base := p; base.origin.y=ground;var h:=p.origin.y-ground
		if not _clear(ctx,p.translated_local(Vector3(0,envelope.y*0.5,0)),envelope,"canonical_fortress"):continue
		if not _clear(ctx,base.translated_local(Vector3(0,h*0.5,0)),Vector3((envelope.x+3)*1.14,h+2,(envelope.z+3)*1.14),"fortress_foundation"):continue
		var yaw := (PI/2 if side<0 else -PI/2) if asset!="h07_clocktower" else 0.12
		var model: Node3D = ctx.place_model(asset,p,envelope,yaw,ident,1200.0 if asset=="h07_clocktower" else 950.0)
		if model==null:return false
		_emit("canonical_fortress"); _emit("fortress_foundation")
		var fit: Dictionary=ctx.models.fits[-1];var actual: Array=fit.achieved_size_m
		ctx._profile(base,float(actual[0])+2,float(actual[2])+2,[Vector2(0,1.12),Vector2(1.4,1.12),Vector2(3,1.02),Vector2(h*0.45,1.02),Vector2(h*0.45+0.7,1.07),Vector2(h*0.45+1.4,1.02),Vector2(h+1.2,1.02)],"violet")
		for z in [-float(actual[2])*0.43,float(actual[2])*0.43]:
			var buttress:=base.translated_local(Vector3(-signf(side)*(float(actual[0])*0.5-0.2),0,z))
			ctx._profile(buttress,3.8,4.2,[Vector2(0,1.4),Vector2(1.4,1.4),Vector2(h+8,0.8),Vector2(h+9,1.02)],"stone")
		return true
	return false

func _model_size(ctx: RefCounted, asset: String, envelope: Vector3, yaw: float) -> Vector3:
	if not ctx.models._load(asset): return Vector3.ZERO
	var bounds: AABB=ctx.models.cache[asset].bounds
	var rotated: AABB=Transform3D(Basis(Vector3.UP,yaw),Vector3.ZERO)*bounds
	var size:=rotated.size
	return size*minf(envelope.x/size.x,minf(envelope.y/size.y,envelope.z/size.z))

func _foundation(ctx: RefCounted, floor_pose: Transform3D, size: Vector3, name: String) -> bool:
	var bottom:=_footing_ground(ctx,floor_pose,size)-2.0
	var height:=floor_pose.origin.y-bottom
	if height<=0.0:return true
	var base:=floor_pose;base.origin.y=bottom
	var width:=size.x+1.2;var depth:=size.z+1.2
	if not _clear(ctx,base.translated_local(Vector3(0,height*0.5,0)),Vector3(width*1.12,height+0.5,depth*1.12),name,3):return false
	ctx._profile(base,width,depth,[Vector2(0,1.1),Vector2(1.1,1.1),Vector2(2.0,1.03),Vector2(maxf(2.1,height*0.64),1.03),Vector2(maxf(2.2,height*0.64+0.7),1.08),Vector2(height,1.08)],"violet")
	_emit(name)
	return true

func _crypt_chapel(ctx: RefCounted, aisle: Transform3D, side: float, index: int) -> void:
	# Canonical painted masonry fills the side aisle, below the unchanged curved intrados.
	var p:=aisle.translated_local(Vector3(side*24.0,0.15,12.0))
	var envelope:=Vector3(12,11,18);var yaw:float=-side*PI/2.0
	var size:=_model_size(ctx,"h07_facade_a",envelope,yaw)
	if size==Vector3.ZERO or not _clear(ctx,p.translated_local(Vector3(0,size.y*0.5,0)),size+Vector3(0.6,0.1,0.6),"crypt_chapel",2):return
	var model: Node3D=ctx.place_model("h07_facade_a",p,envelope,yaw,"H07CryptChapel_"+str(index)+"_"+str(side),380)
	if model==null:return
	_emit("crypt_chapel")
	_box(ctx,p.translated_local(Vector3(0,-0.325,0)),Vector3(size.x+1.2,0.65,size.z+1.2),"stone","crypt_chapel_step",1.0)
	ctx.add_light(p.translated_local(Vector3(-side*(size.x*0.5+2),5.6,0)).origin,35,29)

func _street(ctx: RefCounted, track_id: String, pitch: float, start: float = 15.0, end: float = -1.0) -> void:
	var track: SpatialTrack=ctx.route.tracks[track_id]
	var stop:=track.length-8.0 if end<0 else minf(end,track.length-8)
	var index:=0;var along:=start
	while along<stop:
		for side in [-1.0,1.0]:
			if track_id in ["cliff_turn","cliff_lip"] and side>0:continue # High continuous right cliff, open lower left valley.
			var broad:bool=(index+int(side>0))%4==2
			var asset:="h07_facade_b" if broad else "h07_facade_a"
			var envelope:=Vector3(32,42,52) if broad else Vector3(34,58,38)
			var yaw:float=-side*PI/2.0
			var actual:=_model_size(ctx,asset,envelope,yaw)
			for setback in [42.0,52.0,64.0,80.0]:
				var p:Transform3D=ctx.upright_pose(track_id,along,side*setback)
				p.origin.y=maxf(p.origin.y-13.0,ctx.ground_y(p.origin)+3.5)
				if not _clear(ctx,p.translated_local(Vector3(0,actual.y*0.5,0)),actual+Vector3(1.6,1,1.6),"near_g1_street",3):continue
				var lot:="valley_lot_"+str(roundi(p.origin.x/16))+"_"+str(roundi(p.origin.z/16))
				if not ctx.claim(lot):break
				# Check supports before the model, so a safe facade never floats over a rejected base.
				if not _foundation(ctx,p,actual,"street_foundation"):continue
				var model:Node3D=ctx.place_model(asset,p,envelope,yaw,"H07Street_"+track_id+"_"+str(index)+"_"+str(side),750)
				if model==null:break
				_emit("near_g1_street")
				var face:float=-side*(actual.x*0.5+1.5)
				_fixture(ctx,p.translated_local(Vector3(face,actual.y*0.51,actual.z*0.12)),"H07StreetLamp_"+track_id+"_"+str(index)+"_"+str(side),40,34)
				_box(ctx,p.translated_local(Vector3(face+side*0.8,actual.y*0.51+3.4,actual.z*0.12)),Vector3(2.2,0.24,0.28),"ink","street_lamp_bracket",1)
				ctx.add_light(p.translated_local(Vector3(face-side*4.5,actual.y*0.42,0)).origin,40,37)
				break
		along+=pitch;index+=1

func _small_city(ctx: RefCounted, track_id: String, s: float, side: float, index: int, far: bool = false) -> void:
	var p: Transform3D=ctx.upright_pose(track_id,s,side)
	var h:=31.0+float(index%4)*7.0
	var width:=35.0+float(index%3)*3.0;var depth:=29.0+float(index%2)*5.0
	var size:=Vector3(depth*1.12,h+14.0,width*1.12)
	p.origin.y=maxf(_footing_ground(ctx,p,size)+2.0,p.origin.y-(47.0 if far else 33.0))
	if not _clear(ctx,p.translated_local(Vector3(0,size.y*0.5,0)),size,"layered_valley_city"):return
	if not _foundation(ctx,p,size,"lower_city_foundation"):return
	var child_start:int=ctx.world.get_child_count()
	ctx._city_house(p,signf(side),width,depth,h,index,far); _emit("layered_valley_city")
	# Far-layer geometry may be foreground from the upper-finish flight camera.
	# Keep the exact roof mesh, but use its proper slate paint instead of a flat edge-color proxy.
	for i in range(child_start,ctx.world.get_child_count()):
		var child:Node=ctx.world.get_child(i)
		if child is MeshInstance3D and str(child.name).begins_with("crooked_roof"):
			child.material_override=ctx.mats.roof;child.set_meta("asset_id","h07_authored_roof")
	if not far and index%3==1:
		_ghost(ctx,p.translated_local(Vector3(-signf(side)*(depth*0.5+0.12),h*0.48,0)),signf(side),9.0,h*0.55,"valley_district_ghost")

func _terrace_chain(ctx: RefCounted, id: String, pitch: float = 64.0) -> void:
	# Discrete overlapping embankments follow the same valley, rather than a new flat ground.
	var track:SpatialTrack=ctx.route.tracks[id]
	for i in ceili(track.length/pitch):
		for side in [-1.0,1.0]:
			var p:Transform3D=ctx.upright_pose(id,minf(20+i*pitch,track.length),side*(103+float(i%3)*8))
			var width:=59.0+float(i%3)*8;var depth:=pitch+12.0
			var ground:=_footing_ground(ctx,p,Vector3(width,1,depth))-3.0
			var top:=maxf(ground+16,p.origin.y-24.0+float(i%3)*3)
			p.origin.y=ground
			var h:=top-ground
			if not _clear(ctx,p.translated_local(Vector3(0,h*0.5,0)),Vector3(width*1.16,h,depth*1.12),"connected_valley_terrace",4):continue
			ctx._profile(p,width,depth,[Vector2(0,1.13),Vector2(h*0.2,1.13),Vector2(h*0.25,1.04),Vector2(h*0.56,1.04),Vector2(h*0.62,0.89),Vector2(h*0.9,0.89),Vector2(h,0.79)],"plum" if i%3==0 else "violet")
			_emit("connected_valley_terrace")
			for z in [-depth*0.35,depth*0.35]:
				var q:=p.translated_local(Vector3(-side*width*0.45,0,z))
				ctx._profile(q,5.0,7.0,[Vector2(0,1.3),Vector2(2,1.3),Vector2(h*0.74,0.8),Vector2(h*0.8,0.9)],"stone")

func _gallery(ctx: RefCounted, id: String, s: float, side: float) -> void:
	var p: Transform3D=ctx.upright_pose(id,s,side).rotated_local(Vector3.UP,PI/2)
	var ground:=_footing_ground(ctx,p,Vector3(70,1,10));var bottom:=ground-p.origin.y
	var height:=12.0-bottom
	if not _clear(ctx,p.translated_local(Vector3(0,bottom+height*0.5,0)),Vector3(70,height+5,11),"lateral_fortress_arcade"):return
	ctx._viaduct(p,3,22,12,bottom,8,"violet"); _emit("lateral_fortress_arcade")

func _ridge(ctx: RefCounted, id: String, s: float, side: float, width: float, height: float) -> void:
	var p: Transform3D=ctx.ground_pose(id,s,side)
	var depth:=24.0;var size:=Vector3(width,height,depth)
	if not _clear(ctx,p.translated_local(Vector3(0,height*0.5,0)),Vector3(size.x*1.2,size.y,size.z*1.2),"cut_stone_cliff_terrace"):return
	ctx._profile(p,width,depth,[Vector2(0,1.10),Vector2(height*0.18,1.10),Vector2(height*0.21,1.04),Vector2(height*0.52,1.04),Vector2(height*0.56,0.91),Vector2(height*0.82,0.91),Vector2(height,0.79)],"violet"); _emit("cut_stone_cliff_terrace")
	for z in [-depth*0.35,depth*0.35]:
		ctx._profile(p.translated_local(Vector3(-signf(side)*width*0.48,0,z)),4,4,[Vector2(0,1.4),Vector2(2,1.4),Vector2(height*0.82,0.8),Vector2(height*0.85,1)],"warm_stone")

func _cliff_boundary(ctx: RefCounted, id: String) -> void:
	var track:SpatialTrack=ctx.route.tracks[id]
	# Preserve the prototype's high right bank as one continuous fortress cliff.
	# Each thick segment is checked independently; the left valley remains lower/open.
	for i in ceili(track.length/30.0)+1:
		var along:=minf(i*30.0,track.length)
		for setback in [40.0,49.0,60.0,75.0]:
			var p:Transform3D=ctx.upright_pose(id,along,setback)
			var width:=36.0;var depth:=44.0
			var ground:=_footing_ground(ctx,p,Vector3(width*1.12,1,depth*1.12))-2.0
			var top:=p.origin.y+55.0+float(i%3)*6.0
			var h:=top-ground;p.origin.y=ground
			var query:=Vector3(width*1.14,h+1,depth*1.14)
			if not _clear(ctx,p.translated_local(Vector3(0,h*.5,0)),query,"continuous_high_right_cliff",3):continue
			ctx._profile(p,width,depth,[Vector2(0,1.12),Vector2(3,1.12),Vector2(h*.30,1.04),Vector2(h*.33,1.1),Vector2(h*.35,1.04),Vector2(h*.73,1.04),Vector2(h*.76,.96),Vector2(h-2,.96),Vector2(h-1,1.05),Vector2(h,1.05)],"violet" if i%3 else "plum")
			_emit("continuous_high_right_cliff")
			# Bonded buttress and dark ledge articulate a large connected face, not a repeated house row.
			var face:=p.translated_local(Vector3(-width*.49,0,-depth*.28))
			ctx._profile(face,3.2,5.0,[Vector2(0,1.3),Vector2(3,1.3),Vector2(h*.78,.82),Vector2(h*.81,1.02)],"stone")
			for level in [h*.34,h*.76]:
				ctx._at(p,Vector3(-width*.51,level,0),Vector3(.45,.8,depth*.94),"ink")
			break

func _valley(ctx: RefCounted) -> void:
	ctx.use_scene("valley")
	# The one real cliff bridge above underpass is emitted by core, never by this region.
	_cliff_boundary(ctx,"cliff_turn")
	_cliff_boundary(ctx,"cliff_lip")
	for side in [-1.0,1.0]:
		_keep(ctx,"upper",95,side*112,Vector3(40,84,66),"H07HighValleyKeep_"+str(side))
		_gallery(ctx,"upper",170,side*93)
		_ridge(ctx,"upper",145,side*69,29,48)
	_keep(ctx,"upper",255,145,Vector3(48,130,48),"H07ValleyReturnClock",-20,"h07_clocktower")
	_keep(ctx,"rescue",210,-90,Vector3(34,66,54),"H07RescueSideKeep",-6)
	_keep(ctx,"finish",150,108,Vector3(36,76,60),"H07ValleyExitKeep",-12)
	for id in ["cliff_turn","cliff_lip","upper","rescue","rescue_merge","finish"]:
		var track: SpatialTrack=ctx.route.tracks[id]
		_street(ctx,id,46.0)
		_terrace_chain(ctx,id)
		for i in ceili(track.length/47.0):
			var s:=minf(20+i*47.0,track.length)
			for side in [-1.0,1.0]:
				if id in ["cliff_turn","cliff_lip"] and side>0:continue
				_small_city(ctx,id,s,side*(99.0+float(i%2)*12.0),i+int(side>0)*3)
				_small_city(ctx,id,minf(s+23,track.length),side*(163+float(i%3)*9),i+5,true)
	for side in [-1.0,1.0]:
		_ridge(ctx,"cliff_turn",30,side*78,35,66)
		_ridge(ctx,"cliff_lip",15,side*92,34,56)

func _return_city(ctx: RefCounted) -> void:
	ctx.use_scene("valley")
	var track: SpatialTrack=ctx.route.tracks.landmark_return
	for i in 3:
		var s: float=track.length*[0.12,0.49,0.82][i]
		_keep(ctx,"landmark_return",s,-106 if i%2==0 else 116,Vector3(38,84,64),"H07ReturnKeep_"+str(i),-10)
	_street(ctx,"landmark_return",43.0)
	_terrace_chain(ctx,"landmark_return")
	for i in ceili(track.length/48.0):
		var s:=minf(25+i*48.0,track.length)
		for side in [-1.0,1.0]:
			_small_city(ctx,"landmark_return",s,side*(100+float(i%3)*7),i)
			_small_city(ctx,"landmark_return",minf(s+24,track.length),side*(165+float(i%2)*13),i+3,true)
		if i%8==3:_gallery(ctx,"landmark_return",s,142 if i%2==0 else -142)
	ctx.use_scene("finale")
	# Leave the shared bridge crossing and its two faces open; no enclosing underpass tunnel is added.
	_street(ctx,"underpass",43.0,14.0,150.0)
	_street(ctx,"underpass",43.0,370.0)
	_terrace_chain(ctx,"underpass",70.0)
	for s in [45.0,110.0,410.0,480.0]:
		for side in [-1.0,1.0]:
			_standing_fixture(ctx,ctx.upright_pose("underpass",s,side*17).translated_local(Vector3(0,4.2,0)),"H07UnderBridgeLamp_"+str(s)+"_"+str(side))
			_small_city(ctx,"underpass",s,side*83,int(s/20))
	_street(ctx,"return_switchback",40.0)
	_terrace_chain(ctx,"return_switchback",60.0)
	var back: SpatialTrack=ctx.route.tracks.return_switchback
	for i in ceili(back.length/47.0):
		var s:=minf(22+i*47.0,back.length-20)
		for side in [-1.0,1.0]:
			_small_city(ctx,"return_switchback",s,side*(104.0+float(i%2)*12),i+6)
			_standing_fixture(ctx,ctx.upright_pose("return_switchback",s,side*17).translated_local(Vector3(0,4.0,0)),"H07ReturnGateLamp_"+str(i)+"_"+str(side))
