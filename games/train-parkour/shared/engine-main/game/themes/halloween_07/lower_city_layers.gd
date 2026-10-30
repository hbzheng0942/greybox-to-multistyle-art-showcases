extends RefCounted
## Actual streets below the railway, grouped by spatial cell. No per-window nodes/lights.
const Field = preload("res://themes/halloween_07/continuous/ground_field.gd")
const Paint = preload("res://themes/halloween_07/lower_city_paint.gdshader")
var cells: Dictionary = {}
var cell: Dictionary
var placement: Transform3D
var building_height := 1.0
var building_seed := 0.0
var foundation_size := Vector3.ZERO
var foundation_profile: Array[Vector2]=[]
var blockers: Array[AABB] = []
var emitted: Array[AABB] = []
var stats := {"buildings":0,"windows":0,"lit_windows":0,"rejected_route":0,"rejected_structure":0,"draw_batches":0,"triangles":0,"real_time_lights_added":0,"retried_placements":0,"foundation_facades":0}

func _v(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])

func build(host: RefCounted) -> void:
	var field := Field.new()
	field.configure(host.route,JSON.parse_string(FileAccess.get_file_as_string("res://themes/halloween_07/continuous/program.json")))
	for fit: Dictionary in host.models.fits:
		if not fit.asset_id in ["h07_facade_a","h07_facade_b","h07_clocktower","h07_castle_keep"]:continue
		var size:=_v(fit.achieved_size_m)
		var basis:=Basis(_v(fit.world_basis[0]),_v(fit.world_basis[1]),_v(fit.world_basis[2])).orthonormalized()
		var transform:=Transform3D(basis,_v(fit.origin))
		var bounds:=transform*AABB(Vector3(-size.x*0.5,0,-size.z*0.5),size)
		if fit.asset_id=="h07_castle_keep":
			var bottom:=minf(18.0,bounds.position.y)
			bounds.size.y+=bounds.position.y-bottom;bounds.position.y=bottom
		blockers.append(bounds.grow(4.0))
	for anchor: Dictionary in host.city_anchors:
		var size: Vector3=anchor.size
		blockers.append(AABB(anchor.base-Vector3(size.x*0.62,0,size.z*0.62),Vector3(size.x*1.24,size.y+13,size.z*1.24)))
	# Individual masonry piers/footings, not an AABB across the open arches.
	for key: String in host.custom_batches:
		if not key.begins_with("profile_"):continue
		var batch: Dictionary=host.custom_batches[key]
		var local_bounds: AABB=batch.mesh.get_aabb()
		if local_bounds.size.y<12.0 or minf(local_bounds.size.x,local_bounds.size.z)<1.2:continue
		for pose: Transform3D in batch.poses:blockers.append((pose*local_bounds).grow(1.4))
	for key in ["violet","plum","brick","ochre","stone","warm_stone"]:
		for pose: Transform3D in host.batches.get(key,[]):
			var size:=pose.basis.get_scale().abs()
			if size.y>18 and minf(size.x,size.z)>5.0:
				blockers.append((pose*AABB(-Vector3.ONE*.5,Vector3.ONE)).grow(1.2))
	var index:=0
	for track_id in ["station_carve","station_ramp","canyon_safe"]:
		var track: SpatialTrack=host.route.tracks[track_id]
		for layer in 4:
			var spacing: float=[22.0,28.0,35.0,43.0][layer]
			var start: float=150.0+layer*11.0 if track_id=="station_carve" else 8.0+layer*5.0
			var limit:=minf(track.length-10.0,660.0)
			var s:=start
			while s<limit:
				for side in [-1.0,1.0]:
					index+=1
					# Preserve the deliberately opened FAST camera/flight corridor.
					if track_id=="canyon_safe" and side<0 and s>245 and s<440 and layer in [1,2]:continue
					var offset: float=[39.0,82.0,139.0,204.0][layer]
					if track_id=="station_carve" and layer>0:offset+=13.0
					if track_id=="station_ramp" and layer>0:offset+=22.0
					var rail_y: float=track.pose(s).origin.y
					var width: float=([12.0,14.0,16.0][index%3] if layer==0 else [16.0,20.0,23.0][index%3])
					var depth: float=(10.0 if layer==0 else 14.0)+float(index%3)*1.4
					if layer==3:width=13.0+float(index%3)*3.0;depth=12.0
					var tower:=index%5==0 or layer==3
					var roof_height: float=(26.0+float(index%3)*7.0) if layer==3 else (12.0 if tower else 7.0)
					var accepted:=false
					var height:=0.0
					var bounds: AABB
					var envelope: Vector3
					var center: Transform3D
					for trial in [Vector2(0,0),Vector2(7,7),Vector2(-7,-5),Vector2(12,-10),Vector2(-12,13)]:
						placement=host._level(track,clampf(s+trial.x,0,track.length),side*(offset+trial.y+float(index%3-1)*2.0))
						placement.origin.y=field.height_at(placement.origin)-0.5
						height=clampf(rail_y-placement.origin.y-[28.0,31.0,17.0,-3.0][layer]-roof_height,24.0,96.0)
						if layer>0:height*=([0.86,1.0,0.94,1.08][index%4] as float)
						if layer==3:height=100.0+float(index%5)*10.0
						envelope=Vector3(depth+2.0,height+roof_height+1.0,width+2.0)
						center=placement.translated_local(Vector3(0,envelope.y*0.5,0))
						if not field.can_place_obb(center,envelope,5.0):
							if trial==Vector2.ZERO:stats.rejected_route+=1
							continue
						bounds=placement*AABB(Vector3(-envelope.x*0.5,0,-envelope.z*0.5),envelope)
						var blocked:=false
						for existing: AABB in blockers+emitted:
							if existing.intersects(bounds):blocked=true;break
						if blocked:continue
						accepted=true
						if trial!=Vector2.ZERO:stats.retried_placements+=1
						break
					if not accepted:stats.rejected_structure+=1;continue
					emitted.append(bounds)
					var key:=Vector3i(floori(placement.origin.x/128),0,floori(placement.origin.z/128))
					if not cells.has(key):cells[key]={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray(),"uv":PackedVector2Array(),"uv2":PackedVector2Array()}
					cell=cells[key];building_height=height;building_seed=float(index%17)/17.0+(2.0 if layer==3 else 0.0)
					_house(depth,width,height,roof_height,side,index,layer,tower)
					host.city_anchors.append({"id":"layered_"+str(index),"base":placement.origin,"roof":placement*Vector3(0,height+roof_height,0),"far":layer==3,"size":Vector3(depth,height,width)})
					host.record.append({"kind":"box","material":"lower_city_layers","scene_id":"canyon" if track_id=="canyon_safe" else "station","center":[center.origin.x,center.origin.y,center.origin.z],"size":[envelope.x,envelope.y,envelope.z]})
					stats.buildings+=1
				s+=spacing
	# Occupied tower bases have actual window apertures represented by inset dark
	# shapes, mullions and opaque emissive glass. Bridge piers remain solid masonry.
	for facade: Dictionary in host.foundation_facades:
		placement=facade.pose
		var size: Vector3=facade.size
		if size.y<18:continue
		var key:=Vector3i(floori(placement.origin.x/128),0,floori(placement.origin.z/128))
		if not cells.has(key):cells[key]={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray(),"uv":PackedVector2Array(),"uv2":PackedVector2Array()}
		cell=cells[key];building_height=size.y;building_seed=float(stats.foundation_facades%17)/17.0
		foundation_size=size
		foundation_profile=[Vector2(0,1.10),Vector2(2,1.10),Vector2(5,1.04),Vector2(size.y*.50,1.02),Vector2(size.y*.50+1,1.06),Vector2(size.y*.50+2,1.02),Vector2(size.y-2,1),Vector2(size.y+4,1.02)]
		for side: float in [-1.0,1.0]:
			for row in maxi(1,int((size.y-9)/11.0)):
				var y:=8.0+row*11.0
				if y+4.0>=size.y*.5 and y-4.0<=size.y*.5+2.0:continue
				# Base profile is 1.02 scale away from its short cornice courses.
				for col in maxi(1,int((size.z-9)/9)):
					var z: float=-size.z*.5+8+col*9
					_window(Vector3(side*(size.x*.52+.16),y,z),Vector3.BACK,Vector3(side,0,0),3.6,6.5,(col+row+stats.foundation_facades)%5!=0)
				for col in maxi(1,int((size.x-9)/9)):
					var x: float=-size.x*.5+8+col*9
					_window(Vector3(x,y,side*(size.z*.52+.16)),Vector3.RIGHT,Vector3(0,0,side),3.6,6.5,(col+row+stats.foundation_facades)%5!=0)
		stats.foundation_facades+=1
	foundation_size=Vector3.ZERO
	var material:=ShaderMaterial.new();material.shader=Paint
	material.set_shader_parameter("masonry_texture",host.mats.violet.get_shader_parameter("paint_texture"))
	material.set_shader_parameter("roof_texture",host.mats.roof.get_shader_parameter("paint_texture"))
	for key: Vector3i in cells:
		var data: Dictionary=cells[key];var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=data.vertices;arrays[Mesh.ARRAY_NORMAL]=data.normals;arrays[Mesh.ARRAY_COLOR]=data.colors
		arrays[Mesh.ARRAY_TEX_UV]=data.uv;arrays[Mesh.ARRAY_TEX_UV2]=data.uv2
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var node:=MeshInstance3D.new();node.name="H07LayeredCity_"+str(key);node.mesh=mesh;node.material_override=material
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("scene_id","canyon");node.set_meta("asset_id","h07_authored_lower_city");node.set_meta("instance_id",str(node.name))
		host.world.add_child(node);host.count+=1;stats.draw_batches+=1;stats.triangles+=data.vertices.size()/3
	host.world.set_meta("h07_layered_city",stats)
	print("H07_LAYERED_CITY ",JSON.stringify(stats))

func _foundation_scale(y: float) -> float:
	for i in range(foundation_profile.size()-1):
		var a:=foundation_profile[i];var b:=foundation_profile[i+1]
		if y<=b.x:return lerpf(a.y,b.y,clampf((y-a.x)/maxf(.001,b.x-a.x),0.0,1.0))
	return foundation_profile[-1].y

func _vertex(point: Vector3, normal: Vector3, color: Color, kind: float) -> void:
	if foundation_size!=Vector3.ZERO:
		# Project every frame/glass vertex onto the actual tapered footing surface.
		var scale:=_foundation_scale(point.y)
		if absf(normal.x)>.5:
			var offset:=point.x*normal.x-foundation_size.x*.52
			point.x=normal.x*(foundation_size.x*.5*scale+offset)
		else:
			var offset:=point.z*normal.z-foundation_size.z*.52
			point.z=normal.z*(foundation_size.z*.5*scale+offset)
	cell.vertices.append(placement*point);cell.normals.append((placement.basis*normal).normalized())
	cell.colors.append(color.srgb_to_linear());cell.uv.append(Vector2(0,point.y/building_height));cell.uv2.append(Vector2(kind,building_seed))

func _tri(a: Vector3,b: Vector3,c: Vector3,n: Vector3,color: Color,kind:=0.0) -> void:
	_vertex(a,n,color,kind);_vertex(b,n,color,kind);_vertex(c,n,color,kind)

func _quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,n: Vector3,color: Color,kind:=0.0) -> void:
	_tri(a,b,c,n,color,kind);_tri(a,c,d,n,color,kind)

func _box(center: Vector3,size: Vector3,color: Color,kind:=0.0) -> void:
	var a:=center-size*0.5;var b:=center+size*0.5
	_quad(Vector3(a.x,a.y,b.z),Vector3(b.x,a.y,b.z),b,Vector3(a.x,b.y,b.z),Vector3.BACK,color,kind)
	_quad(a,Vector3(a.x,b.y,a.z),Vector3(b.x,b.y,a.z),Vector3(b.x,a.y,a.z),Vector3.FORWARD,color,kind)
	_quad(a,Vector3(a.x,a.y,b.z),Vector3(a.x,b.y,b.z),Vector3(a.x,b.y,a.z),Vector3.LEFT,color,kind)
	_quad(Vector3(b.x,a.y,a.z),Vector3(b.x,b.y,a.z),b,Vector3(b.x,a.y,b.z),Vector3.RIGHT,color,kind)
	_quad(Vector3(a.x,b.y,a.z),Vector3(a.x,b.y,b.z),b,Vector3(b.x,b.y,a.z),Vector3.UP,color,kind)
	_quad(a,Vector3(b.x,a.y,a.z),Vector3(b.x,a.y,b.z),Vector3(a.x,a.y,b.z),Vector3.DOWN,color,kind)

func _roof(d: float,w: float,h: float,rh: float,color: Color,tower: bool) -> void:
	var a:=Vector3(-d*0.56,h,-w*0.55);var b:=Vector3(d*0.56,h,-w*0.55)
	var c:=Vector3(d*0.56,h,w*0.55);var e:=Vector3(-d*0.56,h,w*0.55)
	if tower:
		var top:=Vector3(0,h+rh,0)
		for pair in [[a,b],[b,c],[c,e],[e,a]]:
			var n: Vector3=-(pair[1]-pair[0]).cross(top-pair[0]).normalized()
			_tri(pair[0],pair[1],top,n,color,1.0)
	else:
		var t:=Vector3(0,h+rh,-w*0.55);var u:=Vector3(0,h+rh,w*0.55)
		_quad(a,t,u,e,Vector3(-rh,d*.56,0).normalized(),color,1.0)
		_quad(b,c,u,t,Vector3(rh,d*.56,0).normalized(),color,1.0)
		_tri(a,b,t,Vector3.FORWARD,color,0.0);_tri(e,u,c,Vector3.BACK,color,0.0)

func _arch(center: Vector3,right: Vector3,n: Vector3,w: float,h: float,color: Color,kind: float) -> void:
	var points: Array[Vector2]=[Vector2(-w/2,-h/2),Vector2(w/2,-h/2),Vector2(w/2,h*.12),Vector2(w*.32,h*.35),Vector2(0,h/2),Vector2(-w*.32,h*.35),Vector2(-w/2,h*.12)]
	for i in range(1,points.size()-1):
		_tri(center+right*points[0].x+Vector3.UP*points[0].y,center+right*points[i].x+Vector3.UP*points[i].y,center+right*points[i+1].x+Vector3.UP*points[i+1].y,n,color,kind)

func _window(center: Vector3,right: Vector3,n: Vector3,w: float,h: float,lit: bool) -> void:
	_arch(center-n*.03,right,n,w+1.5,h+1.5,Color("85503c"),0.0)
	_arch(center,right,n,w+0.85,h+0.85,Color("140d25"),2.0)
	_arch(center+n*.10,right,n,w,h,Color("ff6416") if lit else Color("392947"),3.0 if lit else 2.0)
	# Opaque dark mullions, separate from the orange glass; no alpha or extra pass.
	var stripe:=maxf(.15,w*.065)
	_quad(center+n*.15-right*stripe/2-Vector3.UP*h*.43,center+n*.15+right*stripe/2-Vector3.UP*h*.43,center+n*.15+right*stripe/2+Vector3.UP*h*.33,center+n*.15-right*stripe/2+Vector3.UP*h*.33,n,Color("1c102a"),2.0)
	_quad(center+n*.16-right*w*.45-Vector3.UP*.10,center+n*.16+right*w*.45-Vector3.UP*.10,center+n*.16+right*w*.45+Vector3.UP*.10,center+n*.16-right*w*.45+Vector3.UP*.10,n,Color("1c102a"),2.0)
	stats.windows+=1;stats.lit_windows+=int(lit)

func _house(d: float,w: float,h: float,rh: float,side: float,index: int,layer: int,tower: bool) -> void:
	var palettes: Array[Color]=[Color("532d54"),Color("61345d"),Color("694269"),Color("472a52")]
	var wall: Color=Color("303047") if layer==3 else palettes[index%4]
	_box(Vector3(0,h/2,0),Vector3(d,h,w),wall)
	_box(Vector3(0,h-.4,0),Vector3(d+1.5,.8,w+1.6),Color("35213f"))
	_box(Vector3(0,1.2,0),Vector3(d+1.6,2.4,w+1.5),Color("6d4166"))
	_roof(d,w,h,rh,Color("303852") if layer<2 else Color("403951"),tower)
	if layer==3:
		for y: float in [h*.55,h*.80,h-.8]:_box(Vector3(0,y,0),Vector3(d+1.5,1.1,w+1.5),Color("24253c"),1.0)
	if not tower:_box(Vector3(d*.22,h+rh*.7,w*.21),Vector3(1.8,5.0,1.8),wall)
	var rows:=maxi(3,int(h/(18.0 if layer==3 else 12.0)))
	for row in rows:
		var y:=7.0+row*(h-14.0)/rows
		if row>0:_box(Vector3(0,y-4.2,0),Vector3(d+0.5,0.35,w+0.5),Color("65405c"))
		for column in (2 if layer==3 else 3):
			var z: float=(column-(.5 if layer==3 else 1.0))*w*.28
			var lit: bool=(index*7+row*3+column)%10<8
			_window(Vector3(-side*(d*.5+.03),y,z),Vector3(0,0,1),Vector3(-side,0,0),1.8 if layer==3 else 3.0,6.0,lit)
		for column in 2:
			var x: float=(column-.5)*d*.43
			_window(Vector3(x,y,w*.5+.03),Vector3.RIGHT,Vector3.BACK,1.8 if layer==3 else 3.0,6.0,(index+row*3+column)%5!=0)
	# Vertical corner pilasters preserve readable divisions between narrow houses.
	for z: float in [-w*.48,w*.48]:
		_box(Vector3(-side*(d*.5+.28),h*.5,z),Vector3(.65,h,.8),Color("805476"))
