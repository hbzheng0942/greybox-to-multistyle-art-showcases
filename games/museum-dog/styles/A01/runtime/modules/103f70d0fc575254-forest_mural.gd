extends RefCounted
## Two printed layers on the original taxidermy canvas, not scenery objects.
## Clip to the same 24 x 20 cloth triangles so no print bridges a gathered seam.
const WALLS := {"taxidermy/shell_wall/13.0_-4.0":1.0,"taxidermy/shell_wall/13.0_6.0":-1.0,"taxidermy/shell_wall/18.0_1.0":-1.0}
const NX := 64
const NY := 48
const BAND_BOTTOM := 1.70
const BAND_TOP := 3.85
var _materials: Array[Material] = []
# Exact pressure samples are invariant for one width/height. The old inner loop
# evaluated four pressure points five times per printed vertex for normals.
var _pressure_width:float=-1.0
var _pressure_height:float=-1.0
var _pressure_grid:=PackedFloat64Array()

func apply(parent:Node3D,group:Dictionary,segments:Array[Vector2],soft)->Dictionary:
	var id:=str(group.id)
	if not WALLS.has(id):return {"applied":false}
	var side:float=WALLS[id]
	var base_y:float=group.primary_world_aabb.min[1]
	var phase:int=0 if id.ends_with("_-4.0") else (1 if id.ends_with("_6.0") else 2)
	var width:float=maxf(float(group.primary_world_aabb.size[0]),float(group.primary_world_aabb.size[2]))
	if _materials.is_empty():
		var base:Color=soft.palette.wall_material(Color("e5d7b6")).albedo_color
		_materials.append(soft.palette.wall_material(base.lerp(Color("819c9b"),.34)))
		_materials.append(soft.palette.wall_material(base.lerp(Color("526d7c"),.56)))
	var counts:Array[int]=[]
	for layer in range(2):
		var vertices:=PackedVector3Array()
		var normals:=PackedVector3Array()
		var polygons:Array[PackedVector2Array]=_silhouettes(width,layer,phase)
		for segment in segments:
			var panel_width:float=segment.y-.006
			var height:float=BAND_TOP-BAND_BOTTOM
			for polygon in polygons:
				var indices:=Geometry2D.triangulate_polygon(polygon)
				for i in range(0,indices.size(),3):
					var triangle:=PackedVector2Array([polygon[indices[i]],polygon[indices[i+1]],polygon[indices[i+2]]])
					_emit_on_canvas(triangle,segment.x,panel_width,height,base_y,side,.0012+layer*.0007,soft,vertices,normals)
		var arrays:Array=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh:=ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var instance:=MeshInstance3D.new()
		instance.name="ForestPrintDistant" if layer==0 else "ForestPrintNear"
		instance.mesh=mesh
		instance.material_override=_materials[layer]
		parent.add_child(instance)
		counts.append(vertices.size()/3)
	return {"applied":true,"wall_id":id,"layers":2,"triangles":counts,"surface":"original inward canvas","world_y":[BAND_BOTTOM+.035,3.13],"collision_nodes_added":0}

func _silhouettes(width:float,layer:int,phase:int)->Array[PackedVector2Array]:
	var result:Array[PackedVector2Array]=[]
	var bottom:=BAND_BOTTOM+.035
	var ridge:=PackedVector2Array([Vector2(-width*.5,bottom),Vector2(width*.5,bottom)])
	for i in range(10,-1,-1):
		var x:float=-width*.5+width*float(i)/10.0
		var rise:float=(.28+.60*(.5+.5*sin(float(i*7+phase*3)))) if layer==0 else (.07+.13*(.5+.5*sin(float(i*5+phase))))
		ridge.append(Vector2(x,bottom+rise))
	result.append(ridge)
	var count:int=9 if layer==0 else 6
	for i in range(count):
		var seed_value:=float(i*7+phase*5+layer*3)
		var x:float=-width*.5+width*(float(i)+.35+.25*sin(seed_value))/float(count)
		var h:float=(.72+.57*(.5+.5*sin(seed_value*1.7))) if layer==0 else (.91+.76*(.5+.5*sin(seed_value*1.3)))
		var w:float=h*((.38+.16*(.5+.5*cos(seed_value))) if layer==0 else (.40+.19*(.5+.5*sin(seed_value*.7))))
		result.append(_pine(Vector2(x,bottom+.03),w,h))
	return result

func _pine(at:Vector2,width:float,height:float)->PackedVector2Array:
	# Broad stitched-print contour: three branch tiers and a short integral trunk.
	var outline:=PackedVector2Array([Vector2(0,1),Vector2(.23,.74),Vector2(.13,.74),Vector2(.37,.45),Vector2(.25,.45),Vector2(.5,.16),Vector2(.065,.16),Vector2(.065,0),Vector2(-.065,0),Vector2(-.065,.16),Vector2(-.5,.16),Vector2(-.25,.45),Vector2(-.37,.45),Vector2(-.13,.74),Vector2(-.23,.74)])
	for i in range(outline.size()):outline[i]=at+outline[i]*Vector2(width,height)
	return outline

func _clip(poly:PackedVector2Array,normal:Vector2,limit:float)->PackedVector2Array:
	var out:=PackedVector2Array()
	if poly.is_empty():return out
	var previous:Vector2=poly[poly.size()-1]
	var pd:float=previous.dot(normal)-limit
	for current in poly:
		var cd:float=current.dot(normal)-limit
		if (cd<=0.000001)!=(pd<=0.000001):out.append(previous.lerp(current,pd/(pd-cd)))
		if cd<=0.000001:out.append(current)
		previous=current;pd=cd
	return out

func _emit_on_canvas(triangle:PackedVector2Array,center:float,width:float,height:float,base_y:float,side:float,offset:float,soft,vertices:PackedVector3Array,normals:PackedVector3Array)->void:
	var left:float=center-width*.5
	var right:float=center+width*.5
	var poly:=_clip(_clip(triangle,Vector2(-1,0),-(left+.035)),Vector2(1,0),right-.035)
	if poly.size()<3:return
	var lo:=poly[0];var hi:=poly[0]
	for p in poly:lo=lo.min(p);hi=hi.max(p)
	var ix0:int=clampi(floori((lo.x-left)/width*NX),0,NX-1)
	var ix1:int=clampi(floori((hi.x-left)/width*NX),0,NX-1)
	var iy0:int=clampi(floori((lo.y-BAND_BOTTOM)/height*NY),0,NY-1)
	var iy1:int=clampi(floori((hi.y-BAND_BOTTOM)/height*NY),0,NY-1)
	for y in range(iy0,iy1+1):
		for x in range(ix0,ix1+1):
			var x0:float=left+width*float(x)/NX;var x1:float=left+width*float(x+1)/NX
			var y0:float=BAND_BOTTOM+height*float(y)/NY;var y1:float=BAND_BOTTOM+height*float(y+1)/NY
			var rect:=_clip(_clip(_clip(_clip(poly,Vector2(-1,0),-x0),Vector2(1,0),x1),Vector2(0,-1),-y0),Vector2(0,1),y1)
			if rect.size()<3:continue
			var diagonal:=Vector2(1.0/(x1-x0),1.0/(y1-y0))
			var limit:float=1.0+x0*diagonal.x+y0*diagonal.y
			for half in range(2):
				var cut:=_clip(rect,diagonal if half==0 else -diagonal,limit if half==0 else -limit)
				for i in range(1,cut.size()-1):
					var a:Vector2=cut[0];var b:Vector2=cut[i];var c:Vector2=cut[i+1]
					var cross_value:float=(b-a).cross(c-a)
					if absf(cross_value)<0.00000001:continue
					if cross_value*side>0.0:var swap:=b;b=c;c=swap
					for p in [a,b,c]:
						var u:float=(p.x-left)/width;var t:float=(p.y-BAND_BOTTOM)/height
						var z:float=_cloth_height(u,t,width,height,soft)
						vertices.append(Vector3(p.x,p.y-base_y,side*(z+offset)))
						var dx:float=(_cloth_height(u+.0001,t,width,height,soft)-_cloth_height(u-.0001,t,width,height,soft))/(.0002*width)
						var dy:float=(_cloth_height(u,t+.0001,width,height,soft)-_cloth_height(u,t-.0001,width,height,soft))/(.0002*height)
						normals.append(Vector3(-dx,-dy,side).normalized())

func _cloth_height(u:float,t:float,width:float,height:float,soft)->float:
	var px:float=clampf(u,0.0,.999999)*NX
	var py:float=clampf(t,0.0,.999999)*NY
	var x:int=floori(px);var y:int=floori(py)
	var fx:float=px-x;var fy:float=py-y
	if width!=_pressure_width or height!=_pressure_height:
		_pressure_width=width;_pressure_height=height
		_pressure_grid.resize((NX+1)*(NY+1))
		for gy in range(NY+1):
			for gx in range(NX+1):
				_pressure_grid[gy*(NX+1)+gx]=soft._canvas_pressure(float(gx)/NX,float(gy)/NY,width,height)
	var h00:float=_pressure_grid[y*(NX+1)+x]
	var h10:float=_pressure_grid[y*(NX+1)+x+1]
	var h01:float=_pressure_grid[(y+1)*(NX+1)+x]
	var h11:float=_pressure_grid[(y+1)*(NX+1)+x+1]
	return h00+(h10-h00)*fx+(h01-h00)*fy if fx+fy<=1.0 else h11+(h01-h11)*(1.0-fx)+(h10-h11)*(1.0-fy)
