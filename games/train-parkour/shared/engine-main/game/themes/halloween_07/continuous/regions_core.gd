extends RefCounted
## N02–N05 share architecture/ground, rather than resetting scenery per track.
func build(ctx: RefCounted, region: Dictionary) -> Dictionary:
	var report := {"region":region.id,"houses":0,"near_facades":0,"keeps":0,"clocktowers":0,"side_arcades":0,"wall_buttresses":0}
	match str(region.id):
		"N02":
			_district(ctx,"canyon_fast",[80.0,210.0,360.0,510.0,640.0],report,1.0)
			_district(ctx,"canyon_merge",[50.0,160.0,280.0],report,0.85)
			_keep(ctx,"canyon_fast",340.0,-128.0,Vector3(76,112,64),"canyon_branch_citadel",report)
			_arcade(ctx,"canyon_merge",175.0,91.0,report)
			_near_street(ctx,"canyon_merge",report)
		"N03":
			_district(ctx,"rush",[35.0,125.0,225.0],report,0.85)
			_district(ctx,"carve",[50.0,150.0,270.0],report,1.0)
			_district(ctx,"drop",[40.0,135.0,220.0],report,0.78)
			_district(ctx,"rollout",[65.0,175.0,255.0],report,0.9)
			_keep(ctx,"wall",90.0,110.0,Vector3(74,145,70),"vertical_shared_keep",report)
			_keep(ctx,"inverted",120.0,-125.0,Vector3(60,126,56),"inversion_outer_keep",report)
			_wall(ctx,"wall",report)
			_wall_lower_courtyard(ctx,report)
			for id: String in ["rush","carve","drop","rollout"]: _near_street(ctx,id,report)
		"N04":
			_district(ctx,"loop_entry",[35.0,110.0],report,0.75)
			_district(ctx,"loop_out",[25.0,75.0],report,0.75)
			_keep(ctx,"loop",0.0,-125.0,Vector3(64,150,58),"moon_courtyard_west_keep",report)
			_keep(ctx,"loop",0.0,135.0,Vector3(54,130,54),"moon_courtyard_east_keep",report)
			_clock(ctx,"loop_entry",90.0,190.0,report)
			_loop_supports(ctx,report)
			for id: String in ["loop_entry","loop_out","exit_ramp"]: _near_street(ctx,id,report)
		"N05":
			_district(ctx,"relay",[55.0,155.0,260.0],report,0.85)
			_district(ctx,"high_merge",[110.0,250.0,390.0,480.0],report,0.9)
			_keep(ctx,"grind",260.0,-115.0,Vector3(75,106,58),"relay_air_citadel",report)
			_keep(ctx,"high_merge",380.0,110.0,Vector3(66,105,58),"tunnel_forecourt_keep",report)
			_arcade(ctx,"relay",170.0,-105.0,report)
			_district(ctx,"grind",[35.0,150.0,280.0,410.0],report,0.9)
			for id: String in ["relay","high_merge"]: _near_street(ctx,id,report)
	return report

func _district(ctx: RefCounted, track_id: String, distances: Array, report: Dictionary, scale: float) -> void:
	var index := 0
	var track: SpatialTrack = ctx.route.tracks[track_id]
	var sites := []
	for i in ceili(track.length/52.0): sites.append(minf(22.0+float(i)*52.0,track.length))
	for s: float in sites:
		for side: float in [-1.0,1.0]:
			for layer in 2:
				var offset := side*(111.0+float(layer)*57.0+float(index%3)*5.0)
				var p: Transform3D = ctx.ground_pose(track_id,s+float(layer)*16.0,offset)
				var height := (34.0+float(index%4)*7.0+float(layer)*8.0)*scale
				var width := 33.0+float(index%3)*5.0; var depth := 30.0+float(index%2)*5.0
				var size := Vector3(depth+5,height+17,width+5)
				var center := p.translated_local(Vector3(0,size.y*0.5,0))
				var ident := "city_"+str(Vector2i(roundi(p.origin.x/22),roundi(p.origin.z/22)))
				if not ctx.can_place(center,size,4.0) or not ctx.claim(ident): index += 1; continue
				ctx._profile(p,depth+5,width+5,[Vector2(-4,1.08),Vector2(0.8,1.08),Vector2(1.8,1.0),Vector2(3.5,1.0)],"stone")
				# The high_merge broad facade footing reaches this one top-row aperture.
				# Raise the complete window/sill within its existing wall; retain all house/route poses.
				var window_offsets: Dictionary={"2:1":2.8} if ctx.region_id=="N05" and track_id=="high_merge" and index==6 else {}
				ctx._city_house(p.translated_local(Vector3(0,3.5,0)),side,width,depth,height,index,layer>0,window_offsets)
				if layer == 0:
					var face := p.translated_local(Vector3(-side*(depth*0.5+0.25),3.5+height*0.46,0))
					ctx._mural(face,side,minf(width*0.30,7.0),height*0.5,"continuous_city_ghost")
					ctx.add_light(p.translated_local(Vector3(-side*(depth*0.5+7),height*0.46,0)).origin,32,32)
				report.houses += 1; index += 1

func _near_street(ctx: RefCounted, track_id: String, report: Dictionary) -> void:
	var track: SpatialTrack = ctx.route.tracks[track_id]
	var index := 0; var along := 16.0
	while along < track.length-5:
		for side: float in [-1.0,1.0]:
			var broad := index%5==3
			var envelope := Vector3(40,43,57) if broad else Vector3(43,60,34)
			var p := Transform3D.IDENTITY; var accepted := false
			for setback: float in [48.0,59.0,73.0,88.0]:
				p=ctx.upright_pose(track_id,along,side*setback)
				p.origin.y=maxf(p.origin.y-18.0,ctx.ground_y(p.origin)+4.0)
				if ctx.can_place(p.translated_local(Vector3(0,envelope.y*0.5,0)),envelope+Vector3(2,3,2),4.0): accepted=true; break
			if accepted and ctx.claim("core_near_lot_"+str(Vector2i(roundi(p.origin.x/18),roundi(p.origin.z/18)))):
				var node: Node3D=ctx.place_model("h07_facade_b" if broad else "h07_facade_a",p,envelope,-side*PI/2,"H07Near_"+track_id+"_"+str(index),1100)
				if node!=null:
					var actual: Array=ctx.models.fits[-1].achieved_size_m
					var height: float = p.origin.y-ctx.ground_y(p.origin)+6.0
					ctx._at(p,Vector3(0,-height*0.5,0),Vector3(float(actual[0])+0.5,height,float(actual[2])+0.5),"violet")
					ctx._at(p,Vector3(0,-0.35,0),Vector3(float(actual[0])+1.0,0.7,float(actual[2])+1.0),"stone")
					ctx.add_light(p.translated_local(Vector3(-side*(float(actual[0])*0.5+4),19,0)).origin,38,40)
					if index%3==1:
						var face:float=-side*(float(actual[0])*0.5+1.1)
						ctx._at(p,Vector3(face+side*0.7,20,0),Vector3(2.6,0.25,0.3),"ink")
						ctx._at(p,Vector3(face,19.7,0),Vector3(0.12,1.1,0.12),"ink")
						ctx.place_model("h07_lantern",p.translated_local(Vector3(face,16.8,0)),Vector3(1.6,2.5,1.6),0,"H07CoreWallLamp_"+track_id+"_"+str(index),350)
					report.near_facades += 1
			index += 1
		along += 48.0 if index%5==3 else 36.0

func _keep(ctx: RefCounted, track_id: String, s: float, side: float, size: Vector3, ident: String, report: Dictionary) -> void:
	var p: Transform3D = ctx.ground_pose(track_id,s,side)
	var accepted := false
	for spread: float in [1.0,1.35,1.7]:
		p = ctx.ground_pose(track_id,s,side*spread)
		if ctx.can_place(p.translated_local(Vector3(0,(size.y+5)*0.5,0)),size+Vector3(8,5,8),5.0): accepted = true; break
	if not accepted: return
	if not ctx.claim(ident+"_base"): return
	ctx._profile(p,size.x+5,size.z+5,[Vector2(-8,1.12),Vector2(1.4,1.12),Vector2(3,1),Vector2(5,1)],"stone")
	ctx.place_model("h07_castle_keep",p.translated_local(Vector3(0,5,0)),size,0.12 if side<0 else PI-0.12,"H07_"+ident,1700)
	for sign: float in [-1.0,1.0]:
		var brace := p.translated_local(Vector3(sign*(size.x*0.48+3),0,size.z*0.17))
		ctx._profile(brace,5,9,[Vector2(0,1.7),Vector2(3,1.7),Vector2(size.y*0.35,1),Vector2(size.y*0.56,0.55)],"violet")
	ctx.add_light(p.translated_local(Vector3(0,size.y*0.35,size.z*0.55)).origin,43,65)
	report.keeps += 1

func _clock(ctx: RefCounted, track_id: String, s: float, side: float, report: Dictionary) -> void:
	var p: Transform3D = ctx.ground_pose(track_id,s,side)
	if not ctx.can_place(p.translated_local(Vector3(0,77,0)),Vector3(54,154,54),5): return
	ctx.place_model("h07_clocktower",p,Vector3(52,154,52),0,"H07_"+ctx.region_id+"_Clock",2200)
	ctx._profile(p,58,58,[Vector2(-6,1),Vector2(1.5,1),Vector2(3,0.92)],"stone")
	report.clocktowers += 1

func _arcade(ctx: RefCounted, track_id: String, s: float, side: float, report: Dictionary) -> void:
	var p: Transform3D = ctx.upright_pose(track_id,s,side)
	p.origin.y -= 8.0
	var bottom: float = ctx.ground_y(p.origin)-p.origin.y
	var size := Vector3(128,42-bottom,11)
	if not ctx.can_place(p.translated_local(Vector3(0,(42+bottom)*0.5,0)),size,4.0): return
	if not ctx.claim("arcade_"+str(p.origin.snapped(Vector3.ONE*10))): return
	ctx._viaduct(p,3,40,34,bottom,8,"violet")
	report.side_arcades += 1

func _wall(ctx: RefCounted, track_id: String, report: Dictionary) -> void:
	var track: SpatialTrack = ctx.route.tracks[track_id]
	for i in 8:
		var s := (float(i)+0.5)*track.length/8.0
		var p: Transform3D = ctx.ground_pose(track_id,s,75.0)
		var height:=74.0+float(i%3)*7.0
		var size := Vector3(13,height,track.length/8.0+0.5)
		if not ctx.can_place(p.translated_local(Vector3(-3,52,0)),Vector3(30,108,size.z+5),4): continue
		ctx._at(p,Vector3(0,height*0.5,0),size,"plum" if i%3 else "violet")
		ctx._at(p,Vector3(0,height-0.5,0),Vector3(15,2,size.z+0.5),"stone")
		ctx._roof(p.translated_local(Vector3(0,height+5,0)),16,10,size.z+2,"roof")
		ctx._profile(p.translated_local(Vector3(-10,0,0)),6,8,[Vector2(-3,1.7),Vector2(3,1.7),Vector2(height*0.72,0.85),Vector2(height-3,0.6)],"warm_stone")
		for side:float in [-1.0,1.0]:
			for y:float in [16.0,36.0,56.0]:
				for z:float in [-size.z*0.25,size.z*0.25]:ctx._gothic_window(p.translated_local(Vector3(side*6.72,y,z)),-side,3.8,9.0,"window_dim" if (i+int(y))%3 else "window_dark")
			for y:float in [7.0,28.0,49.0,height-3.0]:ctx._at(p,Vector3(side*6.9,y,0),Vector3(0.7,0.65,size.z+0.6),"warm_stone")
		for end:float in [-1.0,1.0]:
			var face:=p.translated_local(Vector3(0,0,end*(size.z*0.5+0.2)));face.basis=face.basis*Basis(Vector3.UP,PI/2)
			for y:float in [18.0,40.0,61.0]:ctx._gothic_window(face.translated_local(Vector3(0,y,0)),end,6.5,12.5,"window_dim")
		if i%2==0:
			ctx._at(p,Vector3(-8.0,29.8,0),Vector3(3.2,0.3,0.4),"ink")
			ctx._at(p,Vector3(-9.0,29.2,0),Vector3(0.13,1.1,0.13),"ink")
			ctx.place_model("h07_lantern",p.translated_local(Vector3(-9.0,26.5,0)),Vector3(1.9,2.8,1.9),0,"H07WallGalleryLamp_"+str(i),480)
			ctx.add_light(p.translated_local(Vector3(-12,28,0)).origin,42,40)
		report.wall_buttresses += 1

func _loop_supports(ctx: RefCounted, report: Dictionary) -> void:
	var loop: SpatialTrack = ctx.route.tracks.loop
	for fraction: float in [0.2,0.36,0.5,0.64,0.8]:
		for side: float in [-1.0,1.0]:
			var p: Transform3D = ctx.ground_pose("loop",loop.length*fraction,side*20.0)
			var top: float = ctx.track_pose("loop",loop.length*fraction).origin.y-8.0
			var height := top-p.origin.y
			if height<7 or not ctx.can_place(p.translated_local(Vector3(0,height*0.5,0)),Vector3(5,height,7),1): continue
			ctx._profile(p,5,7,[Vector2(0,1.6),Vector2(2,1.6),Vector2(4,1),Vector2(height-2,0.75),Vector2(height,1)],"violet")
			report.wall_buttresses += 1

func _wall_lower_courtyard(ctx:RefCounted,report:Dictionary)->void:
	var lots:=0
	for i in 5:
		for offset:float in [22.0,52.0]:
			var p:Transform3D=ctx.ground_pose("wall",14.0+float(i)*31.0,offset)
			p.origin.y+=2.0
			var size:=Vector3(28,26,29)
			if not ctx.can_place(p.translated_local(Vector3(0,13,0)),size+Vector3(2,2,2),1.0):continue
			var node:Node3D=ctx.place_model("h07_facade_b" if i%3==1 else "h07_facade_a",p,size,-PI/2,"H07WallLowerCourt_"+str(i)+"_"+str(offset),650)
			if node==null:continue
			var achieved:Array=ctx.models.fits[-1].achieved_size_m
			ctx._at(p,Vector3(0,-2,0),Vector3(float(achieved[0])+0.5,4,float(achieved[2])+0.5),"stone")
			ctx.add_light(p.translated_local(Vector3(-float(achieved[0])*0.5-3,12,0)).origin,35,34)
			lots+=1
	report.wall_lower_courtyard_lots=lots

