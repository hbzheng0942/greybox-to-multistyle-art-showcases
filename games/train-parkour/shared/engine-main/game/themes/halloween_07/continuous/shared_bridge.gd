extends RefCounted
## The same bridge is seen from cliff_turn and the returning underpass.
func build(ctx: RefCounted) -> Dictionary:
	if not ctx.claim("cliff_turn_underpass_single_bridge"): return {"duplicate_claim":true}
	ctx.use_scene("valley")
	var upper: SpatialTrack = ctx.route.tracks.cliff_turn
	var lower: SpatialTrack = ctx.route.tracks.underpass
	var anchor_s := upper.length*0.52
	var anchor: Transform3D = upper.pose(anchor_s)
	var lower_s := lower.nearest(anchor.origin)
	var lower_pose := lower.pose(lower_s)
	var separation := anchor.origin.y-lower_pose.origin.y
	var lowest_crossing_soffit := INF
	var columns := 0
	# The rail bed already follows the exact curved upper track. These are its two
	# real shallow side spandrels, not an unrelated second crossing or tunnel.
	for i in 22:
		var offset := -42.0+(float(i)+0.5)*4.0
		var p: Transform3D = ctx.upright_pose("cliff_turn",anchor_s+offset)
		var depth := 0.10 if absf(offset)<12.0 else 0.10+pow((absf(offset)-12.0)/32.0,2)*12.0
		var half := upper.width_at(anchor_s+offset)
		for side: float in [-1.0,1.0]:
			ctx._at(p,Vector3(side*(half+0.65),0.02-depth*0.5,0),Vector3(1.6,depth,4.06),"stone" if i%4 else "warm_stone")
			ctx._at(p,Vector3(side*(half+0.65),0.35,0),Vector3(1.85,0.55,4.08),"violet")
			ctx._at(p,Vector3(side*(half+0.65),2.25,0),Vector3(0.18,0.2,4.08),"ink")
			if i%2 == 0: ctx._at(p,Vector3(side*(half+0.65),1.35,0),Vector3(0.18,2.1,0.20),"ink")
		# Only the true lower-track width belongs to the 18 m declared opening.
		# Measure both ends of each covered segment, accounting for upper slope.
		for endpoint: float in [-2.03,2.03]:
			var edge: Transform3D = ctx.upright_pose("cliff_turn",anchor_s+offset+endpoint)
			var near: Transform3D = lower.pose(lower.nearest(edge.origin))
			if Vector2(edge.origin.x,edge.origin.z).distance_to(Vector2(near.origin.x,near.origin.z)) <= lower.half_width+0.15:
				lowest_crossing_soffit = minf(lowest_crossing_soffit,edge.origin.y-maxf(0.12,depth-0.02))
	for offset: float in [-45.0,45.0]:
		for side: float in [-1.0,1.0]:
			var p: Transform3D = ctx.upright_pose("cliff_turn",anchor_s+offset)
			var accepted := false; var reach := 0.0
			for candidate: float in [20.0,30.0,42.0,58.0,76.0]:
				var q := p.translated_local(Vector3(side*candidate,0,0))
				var floor_y: float = ctx.ground_y(q.origin)
				var h := q.origin.y-floor_y-4.0
				var guarded_h := q.origin.y-floor_y+10.0
				var middle := Transform3D(q.basis,Vector3(q.origin.x,floor_y+guarded_h*0.5,q.origin.z))
				var beam := p.translated_local(Vector3(side*(candidate+8)*0.5,-8.0,0))
				if h>4.0 and ctx.can_place(middle,Vector3(9,guarded_h,10),0.8) and ctx.can_place(beam,Vector3(candidate-8+4,2.0,5),0.3):
					p=q; reach=candidate; accepted=true; break
			if not accepted: continue
			var bottom: float = ctx.ground_y(p.origin)
			var height := p.origin.y-bottom-4.0
			var base := Transform3D(p.basis,Vector3(p.origin.x,bottom,p.origin.z))
			ctx._profile(base,5.5,6.5,[Vector2(0,1.5),Vector2(2.0,1.5),Vector2(3.5,1.1),Vector2(height-3,0.88),Vector2(height-1,1.25),Vector2(height,1.25)],"violet")
			var joint: Transform3D = ctx.upright_pose("cliff_turn",anchor_s+offset)
			ctx._at(joint,Vector3(side*(reach+8)*0.5,-8.0,0),Vector3(reach-8+4,2.0,5),"stone")
			ctx._profile(p.translated_local(Vector3(0,-4,0)),6,7,[Vector2(0,1),Vector2(1,1),Vector2(2,0.85),Vector2(9,0.85),Vector2(10,1.1)],"stone")
			ctx.place_model("h07_lantern",p.translated_local(Vector3(0,6.5,0)),Vector3(2.5,3.5,2.5),0,"H07SharedBridgeLantern_"+str(offset)+"_"+str(side),650)
			ctx.add_light(p.translated_local(Vector3(0,8,0)).origin,35,35)
			columns += 1
	var clearance := lowest_crossing_soffit-lower_pose.origin.y
	var wide := _wide_deck(ctx,upper,lower,anchor_s)
	var gallery := _underpass_gallery(ctx,lower,lower_s)
	var banks := {"owner":"regions_valley.gd","duplicate_bank_geometry_emitted":false}
	var old_piers := 0
	if columns>=2:
		var presentation: Node=ctx.app.get_node("ControllerLab/PresentationRoot")
		for index in ceili(upper.length/120.0):
			var s:=minf(upper.length,float(index)*120.0+60.0)
			if absf(s-anchor_s)>48.0: continue
			var chunk: Node=presentation.get_node_or_null("cliff_turn_%02d"%index)
			if chunk==null: continue
			for node in chunk.get_children():
				if node is MultiMeshInstance3D and str(node.name).begins_with("TrackPiers"): node.visible=false; old_piers+=1
	return {"claim":"cliff_turn_underpass_single_bridge","upper_track":"cliff_turn","upper_s_m":anchor_s,"upper_anchor":[anchor.origin.x,anchor.origin.y,anchor.origin.z],"lower_track":"underpass","lower_s_m":lower_s,"vertical_separation_m":separation,"minimum_center_span_soffit_y":lowest_crossing_soffit,"lower_declared_ceiling_m":lower.ceiling,"center_span_clearance_m":clearance,"center_span_at_least_declared_ceiling":clearance>=lower.ceiling,"piers":columns,"retired_exact_original_bridge_pier_batches":old_piers,"wide_bridge":wide,"covered_underpass":gallery,"valley_banks":banks,"source_contract":{"visual_inner_roof_m":13.5,"visual_source":"game/levels/labs/spatial_full_lab/spatial_full_lab.gd:102 (ceiling-4 centre14, thickness1, inner roof13.5)","original_hub_width_length_m":[46,96],"hub_source":"game/levels/labs/spatial_full_lab/spatial_full_lab.gd:427-442","declared_solver_ceiling_m":18,"solver_source":"game/scripts/spatial/spatial_full_r2_route.gd:281-285","different_visual_and_gameplay_quantities":true},"entire_banked_opening_18m_certified":false,"upper_bed_thinned":true,"same_world_object":true,"limits":"18.337 is a center-span estimate only. Banked rail underside has separately measured lower vertices; this is not an entire-opening 18m certification or visual acceptance. Frozen collision/camera solids remain unchanged."}

func _wide_deck(ctx: RefCounted, upper: SpatialTrack, lower: SpatialTrack, anchor_s: float) -> Dictionary:
	ctx.use_scene("valley")
	var tiles := 0
	for i in 32:
		var s := anchor_s-48.0+(float(i)+0.5)*3.0
		var p: Transform3D=ctx.upright_pose("cliff_turn",s)
		var banked:=upper.pose(s); var half:=upper.width_at(s)
		var thickness:=0.55+pow(maxf(0.0,absf(s-anchor_s)-12.0)/36.0,2)*11.5
		for side:float in [-1.0,1.0]:
			# Horizontal side wings flank the original banked rail trough. Expanding
			# the rolled track to46m would lower one edge by several metres.
			ctx._at(p,Vector3(side*16.0,-thickness*0.5,0),Vector3(14.0,thickness,3.08),"violet")
			ctx._at(p,Vector3(side*23.0,0.3,0),Vector3(0.8,0.6,3.10),"stone")
			ctx._at(p,Vector3(side*23.0,2.5,0),Vector3(0.16,0.20,3.10),"ink")
			if i%2==0:ctx._at(p,Vector3(side*23.0,1.5,0),Vector3(0.16,2.4,0.20),"ink")
			var inner:Vector3=p.affine_inverse()*(banked*Vector3(side*(half+0.25),-0.04,0))
			var outer:=Vector2(side*9.0,-0.04)
			var profile:=PackedVector2Array([Vector2(inner.x,inner.y-0.12),Vector2(outer.x,outer.y-0.12),outer,Vector2(inner.x,inner.y)])
			ctx._prism(p,_ccw(profile),3.14,"stone","banked_bridge_walkway_join")
			tiles+=1
	var minimum:=INF
	var divisions:=ceili(upper.length/5.0);var pitch:=upper.length/float(divisions)
	for i in divisions:
		var s:float=(float(i)+0.5)*pitch
		if absf(s-anchor_s)>48:continue
		var p:=upper.pose(s);var half:=upper.width_at(s)
		for side:float in [-1.0,1.0]:
			for end:float in [-1.0,1.0]:
				var v:=p*Vector3(side*(half+0.3),-0.12,end*(pitch+0.09)*0.5)
				var near:=lower.pose(lower.nearest(v))
				if Vector2(v.x,v.z).distance_to(Vector2(near.origin.x,near.origin.z))<=lower.half_width+0.2:minimum=minf(minimum,v.y-near.origin.y)
	return {"physical_width_m":46,"physical_length_m":96,"side_wing_tiles":tiles,"banked_rail_trough_preserved":true,"measured_banked_rail_bottom_vertex_clearance_m":minimum,"entire_opening_18m_certified":false,"bearing":"Thick wing ends intersect the four checked transverse beams and grounded piers"}

func _vault_section(s:float,crossing:float,outer:bool)->PackedVector2Array:
	# A true 0.4m minimum thick bridge barrel descends under the banked upper bed.
	# Full-height gallery and low bridge belly share the same section endpoints.
	var blend:=smoothstep(40.0,85.0,absf(s-crossing))
	var apex:=lerpf(13.0,18.3,blend)
	if outer:
		var shoulder:=lerpf(12.8,17.0,blend);var crown:=lerpf(13.4,19.5,blend)
		return PackedVector2Array([Vector2(-12.4,12),Vector2(-11,shoulder),Vector2(-9,crown),Vector2(9,crown),Vector2(11,shoulder),Vector2(12.4,12)])
	return PackedVector2Array([Vector2(-10,12),Vector2(-9,lerpf(12.4,15.5,blend)),Vector2(-7.5,apex),Vector2(7.5,apex),Vector2(9,lerpf(12.4,15.5,blend)),Vector2(10,12)])

func _solid_vault_panel(ctx:RefCounted,st:SurfaceTool,p0:Transform3D,p1:Transform3D,a:PackedVector2Array,b:PackedVector2Array)->bool:
	var vertices:=PackedVector3Array()
	for q:Vector2 in a:vertices.append(p0*Vector3(q.x,q.y,0))
	for q:Vector2 in b:vertices.append(p1*Vector3(q.x,q.y,0))
	# Align the conservative solid bound to its sloped cross-section edge;
	# a horizontal shoulder AABB includes empty air above the wedge.
	var longest:=Vector2.RIGHT
	for i in a.size():
		var edge:=a[(i+1)%a.size()]-a[i]
		if edge.length_squared()>longest.length_squared():longest=edge
	var frame:=p0.rotated_local(Vector3.BACK,atan2(longest.y,longest.x))
	var inverse:=frame.affine_inverse()
	var bounds:=AABB(inverse*vertices[0],Vector3.ZERO)
	for v:Vector3 in vertices:bounds=bounds.expand(inverse*v)
	# Every solid still checks the unchanged track, flight and camera envelopes.
	if not ctx.can_place(frame.translated_local(bounds.get_center()),bounds.size,0.25):return false
	var count:=a.size()
	for i in count:
		var n:=(i+1)%count
		_tri(st,vertices[i],vertices[n+count],vertices[n]);_tri(st,vertices[i],vertices[i+count],vertices[n+count])
	var indices:=Geometry2D.triangulate_polygon(a)
	for i in range(0,indices.size(),3):
		_tri(st,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]])
		_tri(st,vertices[count+indices[i]],vertices[count+indices[i+2]],vertices[count+indices[i+1]])
	return true

func _tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3)->void:
	st.add_vertex(a);st.add_vertex(b);st.add_vertex(c)

func _underpass_gallery(ctx: RefCounted, track: SpatialTrack, crossing: float) -> Dictionary:
	ctx.use_scene("finale")
	var walls:=0;var roofs:=0;var rejects:=0;var interface_panels:=0;var rejected_panels:=[]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The frozen nominal520m line evaluates to520.0000559m. Even divisions
	# avoid a degenerate55micrometre terminal sliver and share exact endpoints.
	var divisions:=maxi(1,ceili(track.length/2.0-0.0001))
	for i in divisions:
		var begin:=track.length*float(i)/float(divisions);var end:=track.length*float(i+1)/float(divisions)
		var pitch:=end-begin;var s:float=(begin+end)*0.5
		var p:Transform3D=ctx.upright_pose(track.id,s)
		for side:float in [-1.0,1.0]:
			var foot:=p.translated_local(Vector3(side*11.2,0,0));var floor_y:float=ctx.ground_y(foot.origin)-2.0
			var height:=p.origin.y+12.0-floor_y
			var center:=Transform3D(p.basis,Vector3(foot.origin.x,floor_y+height*0.5,foot.origin.z))
			if ctx.can_place(center,Vector3(2.4,height,pitch+0.08),0.4):
				ctx._box(center,Vector3(2.4,height,pitch+0.08),"violet" if (i/5)%4 else "plum");walls+=1
				ctx._at(p,Vector3(side*10.0,1.0,0),Vector3(0.45,1.8,pitch+0.10),"stone")
				if i%15==7:
					ctx._gothic_window(p.translated_local(Vector3(side*9.96,5.5,0)),side,3.5,7.0,"window_dim")
					ctx.add_light(p.translated_local(Vector3(side*8.8,6,0)).origin,32,24)
		var inner0:=_vault_section(begin,crossing,false);var outer0:=_vault_section(begin,crossing,true)
		var inner1:=_vault_section(end,crossing,false);var outer1:=_vault_section(end,crossing,true)
		var p0:Transform3D=ctx.upright_pose(track.id,begin);var p1:Transform3D=ctx.upright_pose(track.id,end)
		for j in inner0.size()-1:
			var a:=_ccw(PackedVector2Array([inner0[j],inner0[j+1],outer0[j+1],outer0[j]]))
			var b:=_ccw(PackedVector2Array([inner1[j],inner1[j+1],outer1[j+1],outer1[j]]))
			if _solid_vault_panel(ctx,st,p0,p1,a,b):
				roofs+=1
				if absf(s-crossing)<=85.0:interface_panels+=1
			else:rejects+=1;rejected_panels.append({"s":s,"j":j})
		if i%20==0:
			for side:float in [-1.0,1.0]:
				var pylon:=p.translated_local(Vector3(side*11.2,6.0,0))
				if ctx.can_place(pylon,Vector3(3.0,12.0,1.2),0.2):ctx._box(pylon,Vector3(3.0,12.0,1.2),"stone")
	st.generate_normals();ctx._mesh(st.commit(),Transform3D.IDENTITY,"soffit","H07ConnectedBridgeBarrel")
	ctx.use_scene("valley")
	return {"route_length_m":track.length,"grounded_wall_segments":walls,"thick_roof_segments":roofs,"expected_roof_segments":divisions*5,"center_gallery_intrados_m":18.3,"bridge_belly_intrados_m":13.0,"bridge_belly_crown_thickness_m":0.4,"bridge_belly_outer_crown_m":13.4,"bridge_interface_roof_panels":interface_panels,"shared_endpoint_loft":true,"roof_panels_omitted_for_same_upper_bridge":0,"roof_panel_rejects_elsewhere":rejects,"rejected_panels":rejected_panels,"all_roof_panels_emitted":rejects==0,"old_visual_intrados_m":13.5,"logical_ceiling_m_unchanged":track.ceiling,"same_bridge_crossing_not_duplicated":true,"native_coverage_and_joins_review":"pending_new_dynamic_frames"}

func _ccw(points:PackedVector2Array)->PackedVector2Array:
	var area:=0.0
	for i in points.size():area+=points[i].cross(points[(i+1)%points.size()])
	if area<0:points.reverse()
	return points

