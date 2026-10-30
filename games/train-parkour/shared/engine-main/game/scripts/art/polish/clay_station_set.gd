extends RefCounted
## Station district only: connected ground, street, garden, retaining shore.
## Other chapters must not inherit this district's scatter or coastline rules.
var lab: Node3D
func _init(owner_lab: Node3D) -> void:lab=owner_lab

func ground(t: SpatialTrack,s: float,x: float,h: float=0.0) -> Transform3D:
	var frame:=t.pose(clampf(s,0,t.length))
	var flat:=Vector3(frame.basis.x.x,0,frame.basis.x.z).normalized()
	if flat.length()<.5:flat=Vector3.RIGHT
	var origin:=frame.origin+flat*x+Vector3.UP*(frame.basis.x.y*clampf(x,-13.6,13.6)+h)
	return Transform3D(Basis(flat,Vector3.UP,flat.cross(Vector3.UP)),origin)

func art(id: String,pose: Transform3D) -> void:lab._kit_asset(lab.extra_root,id,pose)
func block(p: Transform3D,size: Vector3,key: String,label: String) -> void:lab._box_at(lab.extra_root,p,size,lab.surface.material(key),label)

func build() -> void:
	for id in ["station_start","station_carve","station_ramp"]:
		var t: SpatialTrack=lab.route.tracks[id]
		for n in ceili(t.length/96):
			var a:=n*96.0;var b:=minf(a+96,t.length)
			for side in [-1,1]:
				strip(t,a,b,side,PackedVector2Array([Vector2(10,-1.8),Vector2(13.6,-1.8),Vector2(13.6,.55),Vector2(36,.55),Vector2(40,-1.3),Vector2(63,-1.3),Vector2(67,-1.3),Vector2(67,4),Vector2(98,4)]),"cream","StationTownGround",id=="station_ramp")
				strip(t,a,b,side,PackedVector2Array([Vector2(98,4),Vector2(108,-4),Vector2(125,-17),Vector2(142,-42),Vector2(146,-200),Vector2(12,-200),Vector2(10,-2)]),"lavender","StationRetainingIsland",id=="station_ramp")
		if id=="station_ramp":continue
		for n in ceili(t.length/13):
			var s:=minf(6.5+n*13.0,t.length-1)
			for side in [-1,1]:
				var facade:=ground(t,s,side*20.5,.55).rotated_local(Vector3.UP,-side*PI/2).scaled_local(Vector3(1,1.2,1))
				# Grade changes shear the arch span while every column remains world-vertical.
				var ahead:=ground(t,s+1,side*20.5,.55).origin.y-ground(t,s-1,side*20.5,.55).origin.y
				var forward: Vector3=-ground(t,s,0).basis.z
				facade.basis.x.y=facade.basis.x.dot(forward)*ahead*.5
				var reserved: bool=lab.heroes.reserved(id,s,side)
				if not reserved and (side<0 or id=="station_start" or n%12<6):
					art("arcade-wall",facade)
					if n%2==0:
						art("trailing-garden",facade.translated_local(Vector3(-5.6,10.8,1.15)).scaled_local(Vector3.ONE*.78))
						art("wall-sconce",facade.translated_local(Vector3(5.6,7.9,1.05)))
				if not reserved and n%2==1:
					if not lab.enrichment.garden(self,t,s,side):art("garden-bed",ground(t,s,side*28,.58).rotated_local(Vector3.UP,-side*PI/2).scaled_local(Vector3.ONE*1.35))
				if not reserved and n%3==0:
					art("garden-bed",ground(t,s+3,side*17,.58).rotated_local(Vector3.UP,-side*PI/2))
				# Border protects a real garden terrace; the coast is another 45m beyond it.
				art("promenade-parapet",ground(t,s,side*97,4.1).rotated_local(Vector3.UP,-side*PI/2))
		for n in ceili(t.length/39):
			var s:=minf(18+n*39.0,t.length-15)
			for side in [-1,1]:
				if lab.heroes.reserved(id,s,side,20):continue
				var front:=ground(t,s,side*33,.58)
				art("garden-bed",front.rotated_local(Vector3.UP,-side*PI/2).scaled_local(Vector3.ONE*1.15))
				art("sculpted-garden",ground(t,s+13,side*55,-1.35).scaled_local(Vector3.ONE*1.05))
				if side<0 or n%3!=1:
					var house:=ground(t,s,side*49,-.75).rotated_local(Vector3.UP,-side*PI/2)
					var low:=INF;var high:=-INF
					for delta in [-14.0,0.0,14.0]:
						for lateral in [43.0,55.0]:
							var height:=ground(t,s+delta,side*lateral,-1.3).origin.y
							low=minf(low,height);high=maxf(high,height)
					house.origin.y=high+.25
					if not lab._safe_shape(house.translated_local(Vector3(0,8,0)),Vector3(25,17,12)):continue
					# A level floor above the highest adjacent grade, supported to the low side.
					var footing:=house;footing.origin.y=(high+low-.4)*.5
					block(footing,Vector3(25,high-low+1.2,12),"cream","TownhouseGroundedPlinth")
					var lux_house: bool=lab.enrichment.house(house,id,n)
					if not lux_house:
						art("terrace-house",house)
						art("trailing-garden",house.translated_local(Vector3(-6,8.4,4.9)))
					# A roof terrace supports each upper volume; staggered silhouettes replace equal-height rows.
					if not lux_house and n%3!=0:
						block(house.translated_local(Vector3(0,15.7,0)),Vector3(23.8,1.2,10.4),"cream","StationRoofTerrace")
						if n%3==1:art("terrace-house",house.translated_local(Vector3(0,16.15,0)).scaled_local(Vector3.ONE*.72))
						else:art("belfry-tower",house.translated_local(Vector3(0,16.15,0)).scaled_local(Vector3.ONE*.58))
						art("trailing-garden",house.translated_local(Vector3(-7,16.25,4.6)).scaled_local(Vector3.ONE*1.2))
					var street_y:=ground(t,s,side*40,-1.3).origin.y
					for step in 4:
						var top:=lerpf(house.origin.y,street_y,float(step+1)/5)
						var stair:=house.translated_local(Vector3(0,0,6.0+step*.8))
						stair.origin.y=(top+street_y-.4)*.5
						block(stair,Vector3(6,top-street_y+.4,.9),"cream","TownhouseEntryStep")

				else:
					art("garden-fountain",ground(t,s,side*48,-1.2))
					for offset in [-7,7]:art("garden-bed",ground(t,s+offset,side*49,-1.25).rotated_local(Vector3.UP,PI/2))
		for n in ceili(t.length/78):
			var s:=minf(44+n*78.0,t.length-18)
			for side in [-1,1]:
				var p:=ground(t,s,side*82,4.25).rotated_local(Vector3.UP,-side*PI/2)
				var high:=-INF;var low:=INF
				for delta in [-13.0,0.0,13.0]:
					var h:=ground(t,s+delta,side*82,4).origin.y
					high=maxf(high,h);low=minf(low,h)
				p.origin.y=high+.25
				if lab._safe_shape(p.translated_local(Vector3(0,10,0)),Vector3(26,21,14)):
					var plinth:=p;plinth.origin.y=(high+low-.4)*.5
					block(plinth,Vector3(25,high-low+1.2,12),"cream","TownhouseGroundedPlinth")
					art("terrace-house",p)
					art("belfry-tower",p.translated_local(Vector3(-6,15.15,0)).scaled_local(Vector3.ONE*.54))
					art("sculpted-garden",ground(t,s+20,side*85,3.8))
				for step in 8:
					var stairs:=ground(t,s,side*(60.5+step*.85),-1.3+(step+1)*.66*.5)
					block(stairs,Vector3(.9,(step+1)*.66,8),"cream","UpperGardenStair")
		for s in [t.length*.18,t.length*.78]:
			var p:=ground(t,s,-54,-.8)
			if lab._safe_shape(p.translated_local(Vector3(0,14,0)),Vector3(13,28,13)):
				block(p.translated_local(Vector3(0,-1,0)),Vector3(13,3,13),"cream","StationClockTowerFoot")
				art("belfry-tower",p)

	lab.heroes.station(self)

func strip(t: SpatialTrack,a: float,b: float,side: int,profile: PackedVector2Array,key: String,label: String,taper: bool) -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps:=maxi(1,ceili((b-a)/8.0))
	var center:=ground(t,a,0).origin
	for j in steps:
		var ss: Array[float]=[lerpf(a,b,float(j)/steps),lerpf(a,b,float(j+1)/steps)]
		for k in profile.size()-1:
			var vertices: Array[Vector3]=[]
			for ij in [Vector2i(0,k),Vector2i(1,k),Vector2i(1,k+1),Vector2i(0,k),Vector2i(1,k+1),Vector2i(0,k+1)]:
				var s: float=ss[ij.x];var q: Vector2=profile[ij.y]
				var factor:=lerpf(1.0,.42,smoothstep(0,t.length,s)) if taper else 1.0
				var p:=ground(t,s,side*q.x*factor,q.y).origin
				if q.y< -100:p.y=-50
				vertices.append(p-center)
			if side<0:vertices.reverse()
			for p in vertices:
				st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)
	st.generate_normals();st.index()
	var mesh:=st.commit()
	var node: MeshInstance3D=lab._piece_at(lab.extra_root,mesh,Transform3D(Basis.IDENTITY,center),lab.surface.material(key,"",0,key=="cream"),label)
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
