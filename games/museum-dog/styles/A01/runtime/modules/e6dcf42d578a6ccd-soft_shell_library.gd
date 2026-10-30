extends RefCounted
## A01 authored construction study. Static visual nodes only, no gameplay owners.
## Mesh profiles, piping, tension bands and buckles are actual geometry.

const CREAM := Color("e5d7b6")
const NAVY := Color("21384d")
const ORANGE := Color("d87935")
const THREAD := Color("b9b29c")
const METAL := Color("657078")
const RECIPES := {
	"central_plinth": {"type":"case", "size":Vector3(7.6,.8,3), "base":.05},
	"bust_plinth": {"type":"case", "size":Vector3(.9,1.15,.9), "base":.045},
	"rock_plinth": {"type":"case", "size":Vector3(1.8,.85,1.8), "base":.045},
	"hero_vase_plinth": {"type":"case", "size":Vector3(1.4,1,1.4), "base":.05},
	"porcelain_table": {"type":"case", "size":Vector3(2.1,.85,1.1), "base":.045},
	"taxidermy_plinth": {"type":"case", "size":Vector3(2.6,.8,2.1), "base":.05},
	"specimen_table": {"type":"case", "size":Vector3(1,.72,.7), "base":.05},
	"bone_counter": {"type":"case", "size":Vector3(3.2,.55,1.2), "base":.055},
	"kids_button_stand": {"type":"case", "size":Vector3(2,1,.8), "base":.05},
	"ticket_desk": {"type":"case", "size":Vector3(2.2,.95,.9), "base":.045},
	"bench": {"type":"bench", "base":.05},
	"gift_table": {"type":"table", "size":Vector3(2.4,.12,1.2), "top":.93, "base":.05},
	"kids_craft_table": {"type":"table", "size":Vector3(5.4,.16,1.5), "top":.89, "base":.05},
	"kids_soft_block": {"type":"case", "size":Vector3(1.6,.5,1.6), "base":.05},
	"kids_ball_pit": {"type":"pit", "base":.05},
	"porcelain_shelf": {"type":"shelf", "base":0.0},
	"kids_toy_shelf": {"type":"toy_shelf", "base":.05},
}
const PALETTE = preload("res://styles/A01/runtime/modules/c55f42a18825edd0-material_palette.gd")
var palette = PALETTE.new()
var materials := {}
var weave: ImageTexture
var cloth_normal: ImageTexture
var _canvas_bay_cache:Dictionary={}

func bake_static_visual(source:Node3D)->Node3D:
	# Build-time consolidation. The caller keeps ownership of the source until checked.
	var buckets:Dictionary={}
	for child in source.get_children():
		if child is Node3D:
			_bake_collect(child,Transform3D.IDENTITY,buckets)
	var output:=Node3D.new()
	output.name=source.name+"_Baked"
	output.transform=source.transform
	for key in buckets:
		var node:=MeshInstance3D.new()
		node.name="MaterialBatch_"+str(output.get_child_count())
		node.mesh=(buckets[key].tool as SurfaceTool).commit()
		node.material_override=buckets[key].material
		output.add_child(node)
	return output

func _bake_collect(node:Node3D,parent_transform:Transform3D,buckets:Dictionary)->void:
	var transform:=parent_transform*node.transform
	if node is MeshInstance3D:
		var visual:=node as MeshInstance3D
		for surface in range(visual.mesh.get_surface_count()):
			var mat:Material=visual.material_override if visual.material_override!=null else visual.mesh.surface_get_material(surface)
			var key:int=mat.get_instance_id() if mat!=null else 0
			if not buckets.has(key):
				var st:=SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				buckets[key]={"tool":st,"material":mat}
			(buckets[key].tool as SurfaceTool).append_from(visual.mesh,surface,transform)
	for child in node.get_children():
		if child is Node3D:
			_bake_collect(child,transform,buckets)

func _init() -> void:
	var im := Image.create(128,128,false,Image.FORMAT_RGB8)
	for y in range(128):
		for x in range(128):
			var tone := .98 + .012 * sin(float(x) * PI * .5) + .008 * sin(float(y) * PI * .5)
			im.set_pixel(x,y,Color(tone,tone,tone))
	im.generate_mipmaps()
	weave = ImageTexture.create_from_image(im)
	var normal_image:=Image.create(128,128,false,Image.FORMAT_RGB8)
	for y in range(128):
		for x in range(128):
			var dx:=.10*sin(float(x)*PI*.5)+.025*sin(float(y)*.17)
			var dy:=.07*sin(float(y)*PI*.5)+.020*sin(float(x)*.23)
			normal_image.set_pixel(x,y,Color(.5+dx,.5+dy,.985))
	normal_image.generate_mipmaps()
	cloth_normal=ImageTexture.create_from_image(normal_image)

func material(color: Color, fabric: bool = true) -> StandardMaterial3D:
	return palette.material(color,fabric)

func box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material(color)
	parent.add_child(node)
	return node

func _mesh(parent: Node3D, vertices: PackedVector3Array, indices: PackedInt32Array, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Explicit angle-weighted smooth normals avoid tessellation density bias at
	# the long straight spans / tightly sampled corners of the same cloth skin.
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var ia:=indices[i];var ib:=indices[i+1];var ic:=indices[i+2]
		var a:=vertices[ia];var b:=vertices[ib];var c:=vertices[ic]
		var face:Vector3=(c-a).cross(b-a).normalized() # Godot clockwise front.
		if face.length_squared()<.5:continue
		normals[ia]+=face*(b-a).angle_to(c-a)
		normals[ib]+=face*(c-b).angle_to(a-b)
		normals[ic]+=face*(a-c).angle_to(b-c)
	for i in range(vertices.size()):
		var p:=vertices[i]
		st.set_normal(normals[i].normalized())
		st.set_uv(Vector2(p.x+p.z,p.y))
		st.add_vertex(p)
	for index in indices:
		st.add_index(index)
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = material(color)
	parent.add_child(node)
	return node

func ring(width: float, depth: float, radius: float, y: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	var r := minf(radius,minf(width,depth)*.48)
	for corner in range(4):
		var cx := (width*.5-r) * (1.0 if corner in [0,3] else -1.0)
		var cz := (depth*.5-r) * (1.0 if corner in [0,1] else -1.0)
		for step in range(10):
			var a := (float(corner)*90.0 + float(step)*90.0/9.0) * PI/180.0
			result.append(Vector3(cx+cos(a)*r,y,cz+sin(a)*r))
	# Subdivide straight spans too: long case sides can show pressure/fold geometry.
	var sampled:=PackedVector3Array()
	for i in range(result.size()):
		sampled.append(result[i])
		if i%10==9:
			for j in range(1,8):sampled.append(result[i].lerp(result[(i+1)%result.size()],j/8.0))
	return sampled

func tube(parent: Node3D, points: PackedVector3Array, radius: float, color: Color, close: bool = false) -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var count := points.size() if close else points.size()-1
	for i in range(count):
		var a := points[i]
		var b := points[(i+1)%points.size()]
		var direction := (b-a).normalized()
		if a.distance_to(b)<.0001:
			continue
		var side := direction.cross(Vector3.UP)
		if side.length()<.01:
			side = direction.cross(Vector3.FORWARD)
		side = side.normalized()
		var normal := direction.cross(side).normalized()
		var start := vertices.size()
		for end in [a,b]:
			for j in range(6):
				var angle := TAU*float(j)/6.0
				vertices.append(end+(side*cos(angle)+normal*sin(angle))*radius)
		for j in range(6):
			var k := (j+1)%6
			indices.append_array(PackedInt32Array([start+j,start+6+j,start+k,start+k,start+6+j,start+6+k]))
	_mesh(parent,vertices,indices,color)

func _buckle(parent: Node3D, at: Vector3, scale_value: float = 1.0) -> void:
	var w := .14*scale_value
	var h := .17*scale_value
	for side in [-1.0,1.0]:
		box(parent,Vector3(.018*scale_value,h,.022),at+Vector3(side*w*.5,0,0),METAL)
		box(parent,Vector3(w,.018*scale_value,.022),at+Vector3(0,side*h*.5,0),METAL)
	box(parent,Vector3(.014*scale_value,h*.78,.025),at,Color("a6adb0"))

func inflated_case(parent: Node3D, size: Vector3, color: Color = NAVY, flat_top: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "PneumaticCase"
	parent.add_child(root)
	var heights:Array[float]=[]
	var insets:Array[float]=[]
	# Broad near-flat side, rounded compressed ends; no accordion row steps.
	for row in range(17):
		var v:=float(row)/16.0
		heights.append(v)
		insets.append(.105*exp(-v/.075)+.085*exp(-(1.0-v)/.075))
	var radius := minf(.30,minf(size.x,size.z)*.30)
	var cap_round:float=0.0 if flat_top else minf(.10,size.y*.18)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var rows := heights.size()
	for row in range(rows):
		var shrink: float = float(insets[row])*minf(1.0,minf(size.x,size.z))
		var side_y:float=cap_round+(size.y-2.0*cap_round)*float(heights[row])
		var profile:=ring(size.x-shrink*2,size.z-shrink*2,radius,side_y)
		for i in range(profile.size()):
			var point:Vector3=profile[i]
			if absf(point.z)>size.z*.5-radius*.55 and size.y>.25:
				var v:float=float(heights[row])
				var edge:=maxf(0.0,size.x*.5-absf(point.x))
				var gather:float=.012*exp(-pow((edge-.12-v*.22)/.14,2.0))*exp(-v/.28)
				var pinch:float=.018*exp(-pow((absf(point.x)-size.x*.32)/.18,2.0))*sin(PI*v)
				point.z-=signf(point.z)*(gather+pinch)
			profile[i]=point
		vertices.append_array(profile)
	var cols := ring(size.x,size.z,radius,0).size()
	for row in range(rows-1):
		for j in range(cols):
			var n := (j+1)%cols
			var a := row*cols+j
			var b := row*cols+n
			indices.append_array(PackedInt32Array([a,b,a+cols,b,b+cols,a+cols]))
	for top in [false,true]:
		if top and flat_top:
			continue # Exact gameplay support plane remains flat and at native height.
		var offset:int=(rows-1)*cols if top else 0
		if not flat_top:
			# Several broad rings roll the cushion skin into the top/bottom;
			# the former single planar fan read as a hard box with bevels.
			var edge_width:float=size.x-float(insets[rows-1 if top else 0])*2.0*minf(1.0,minf(size.x,size.z))
			var edge_depth:float=size.z-float(insets[rows-1 if top else 0])*2.0*minf(1.0,minf(size.x,size.z))
			for cap in range(1,5):
				var f:float=float(cap)/5.0
				var h:float=cap_round*(1.0-pow(1.0-f,2.0))
				var cap_y:float=size.y-cap_round+h if top else cap_round-h
				var ring_offset:=vertices.size()
				vertices.append_array(ring(edge_width*(1.0-f),edge_depth*(1.0-f),radius*(1.0-f),cap_y))
				for j in range(cols):
					var n:=(j+1)%cols
					indices.append_array(PackedInt32Array([offset+j,offset+n,ring_offset+j,offset+n,ring_offset+n,ring_offset+j] if top else [offset+j,ring_offset+j,offset+n,offset+n,ring_offset+j,ring_offset+n]))
				offset=ring_offset
		var center:=vertices.size()
		vertices.append(Vector3(0,size.y if top else 0.0,0))
		for j in range(cols):
			var n:=(j+1)%cols
			indices.append_array(PackedInt32Array([center,offset+j,offset+n] if top else [center,offset+n,offset+j]))
	_mesh(root,vertices,indices,color)
	# Piping follows this exact pressure profile; it must not retain the old
	# hard-box perimeter after the cushion cap rolls inward.
	var seam_fractions:Array=[.10,.90] if flat_top else [.82]
	for fraction in seam_fractions:
		var f:float=float(fraction)
		var shrink:float=(.105*exp(-f/.075)+.085*exp(-(1.0-f)/.075))*minf(1.0,minf(size.x,size.z))
		var seam_y:float=cap_round+(size.y-2.0*cap_round)*f
		tube(root,ring(size.x-2.0*shrink+.004,size.z-2.0*shrink+.004,radius,seam_y),.0055,THREAD,true)
	if flat_top:
		var rim:=ring(size.x,size.z,radius,size.y)
		var top_vertices:=PackedVector3Array([Vector3(0,size.y,0)])
		top_vertices.append_array(rim)
		var top_indices:=PackedInt32Array()
		for i in range(rim.size()):top_indices.append_array(PackedInt32Array([0,i+1,(i+1)%rim.size()+1]))
		var support:=_mesh(root,top_vertices,top_indices,CREAM)
		support.name="ExactRoundedSupportPlane"
		# Same native top height/footprint; the soft lip grows downward.
		padded_loop(root,size.x,size.z,radius,minf(.035,size.y*.18),size.y-minf(.035,size.y*.18),color)
	# Concept furniture uses corner leather reinforcement, not full orange
	# cargo straps on every cabinet. Keep the large cream cloth faces readable.
	if size.y>.25:
		for sign_x in [-1.0,1.0]:
			for sign_z in [-1.0,1.0]:
				var x:float=sign_x*(size.x*.5-radius-.060)
				for fraction in [.15,.85]:
					var f:float=float(fraction)
					var level:float=cap_round+(size.y-2.0*cap_round)*f
					var shrink:float=(.105*exp(-f/.075)+.085*exp(-(1.0-f)/.075))*minf(1.0,minf(size.x,size.z))
					var z:float=sign_z*(size.z*.5-shrink-.006)
					box(root,Vector3(.10,minf(.10,size.y*.20),.018),Vector3(x,level,z),Color("40434b"))
					var pin:=SphereMesh.new();pin.radius=.010;pin.height=.020;pin.radial_segments=8;pin.rings=4
					var rivet:=MeshInstance3D.new();rivet.mesh=pin;rivet.position=Vector3(x,level,z+sign_z*.014);rivet.material_override=material(Color("a7824d"),false);root.add_child(rivet)

	return root

func make_family(id: String, override_size: Vector3 = Vector3.ZERO) -> Node3D:
	assert(RECIPES.has(id),"Unknown authored family")
	var spec: Dictionary = RECIPES[id]
	var root := Node3D.new()
	root.name = id
	root.position.y = float(spec.base)
	root.set_meta("source_family",id)
	root.set_meta("native_base_y",float(spec.base))
	var kind: String = spec.type
	if kind=="case":
		var size: Vector3 = spec.size if override_size==Vector3.ZERO else override_size
		inflated_case(root,size,Color("91a69b") if id=="kids_soft_block" else CREAM,id!="kids_soft_block")
		if id!="kids_soft_block":
			for x in [-size.x*.5+.065,size.x*.5-.065]:
				for z in [-size.z*.5+.065,size.z*.5-.065]:
					box(root,Vector3(.12,.065,.12),Vector3(x,.0325,z),NAVY)
			# Side compression channels run below the exact untouched support plane.
			var divisions:=maxi(1,ceili(size.x/1.25))
			for i in range(1,divisions):
				var x:float=-size.x*.5+size.x*i/divisions
				for z in [-size.z*.5+.005,size.z*.5-.005]:
					tube(root,PackedVector3Array([Vector3(x,.09,z),Vector3(x,size.y*.48,z),Vector3(x,size.y-.09,z)]),.006,THREAD)
	elif kind=="bench":
		var seat := inflated_case(root,Vector3(2.2,.14,.6),ORANGE,false)
		seat.position.y=.41
		box(root,Vector3(2.2,.04,.6),Vector3(0,.43,0),CREAM)
		var back := inflated_case(root,Vector3(2.2,.5,.12),ORANGE,false)
		back.position=Vector3(0,.53,.24)
		for x in [-.85,.85]:
			box(root,Vector3(.12,.48,.5),Vector3(x,.24,0),CREAM)
			box(root,Vector3(.17,.025,.52),Vector3(x,.0125,0),CREAM.darkened(.12))
	elif kind=="table":
		var size: Vector3=spec.size
		var top: float=float(spec.top)-float(spec.base)
		# Thicker children's upholstered apron grows downward only. Support top
		# and XZ footprint remain native; existing legs meet the apron inside it.
		var visual_size:=size
		if id=="kids_craft_table":visual_size.y=.34
		var slab:=inflated_case(root,visual_size,ORANGE,true)
		slab.position.y=top-visual_size.y
		var xs: Array=[-1.0,1.0] if id=="gift_table" else [-2.4,-.8,.8,2.4]
		for x in xs:
			var h: float=.82 if id=="gift_table" else .76
			var legz: float=0.0 if id=="gift_table" else .6
			var leg_width:float=.16 if id=="gift_table" else .34
			var leg:=inflated_pillar(root,leg_width,h,leg_width,CREAM)
			leg.position=Vector3(float(x),0,legz)
			collar(root,leg_width,leg_width,.09,.075,Vector3(float(x),0,legz),NAVY)
	elif kind=="pit":
		# All four skirts stay inside the native .16-thick low perimeter.
		# Local top .26 + base .05 = original .31; no raised gate or new collider.
		var cloth:=Color("79949d")
		var lining:=Color("a3b9bb")
		for sign_z in [-1.0,1.0]:
			_fabric_lip(root,Vector3(3.20,.18,.14),Vector3(0,.015,sign_z*1.40),cloth)
			box(root,Vector3(3.04,.15,.006),Vector3(0,.105,sign_z*1.334),lining)
		for sign_x in [-1.0,1.0]:
			_fabric_lip(root,Vector3(.14,.18,2.96),Vector3(sign_x*1.60,.015,0),cloth)
			box(root,Vector3(.006,.15,2.64),Vector3(sign_x*1.534,.105,0),lining)
		# Low pale padded top, including the front approach. Inner aperture is
		# 3.04 x 2.64, matching the original perimeter's inner faces.
		padded_loop(root,3.36,2.96,.18,.08,.18,Color("b5c6bf"))
		padded_loop(root,3.36,2.96,.18,.025,.025,cloth.darkened(.14))
		for sign_x in [-1.0,1.0]:
			for sign_z in [-1.0,1.0]:
				# L-shaped sewn corner wraps, fully inside the original footprint.
				box(root,Vector3(.19,.16,.012),Vector3(sign_x*1.585,.105,sign_z*1.472),cloth.darkened(.12))
				box(root,Vector3(.012,.16,.19),Vector3(sign_x*1.672,.105,sign_z*1.385),cloth.darkened(.12))
		root.set_meta("pit_native_outer_size",Vector3(3.36,.26,2.96))
		root.set_meta("pit_top_world_y",.31)
	elif kind=="shelf":
		box(root,Vector3(9,3,.22),Vector3(0,1.55,.25),NAVY)
		for y in [.95,1.67,2.39]:
			var shelf:=inflated_case(root,Vector3(8.76,.07,.5),CREAM,true)
			shelf.position=Vector3(0,float(y)-.035,0)
		var base:=inflated_case(root,Vector3(9,.16,.6),NAVY,true)
		base.position.y=0
		var crown:=inflated_case(root,Vector3(9,.22,.62),NAVY,false)
		crown.position.y=2.95
	elif kind=="toy_shelf":
		# Canonical local long axis X; native wall shelf uses long axis Z, rotate in fitting.
		box(root,Vector3(3.2,1.2,.16),Vector3(0,.6,.18),NAVY)
		for y in [.55,.95]:
			var shelf:=inflated_case(root,Vector3(3.1,.06,.36),CREAM,true)
			shelf.position=Vector3(0,float(y)-.03,0)
			# The exact existing shelf support plane is the boxes' liner floor.
			# No extra layer raises the original 6 real objects on either shelf.
			var support:=shelf.get_node_or_null("ExactRoundedSupportPlane")
			if support is MeshInstance3D:support.material_override=material(Color("a6bdc1"))
			var edges:Array[float]=[-1.55,-1.08,0.0,1.08,1.55]
			for i in range(4):
				# Six native centres are +/-1.35,+/-.81,+/-.27. Unequal four
				# compartments put every divider in a real gap: 1 / 2 / 2 / 1.
				var width:float=edges[i+1]-edges[i]-.012
				var center:float=(edges[i]+edges[i+1])*.5
				_open_storage_bin(root,width,Vector3(center,float(y)+.03,0),i)
		root.set_meta("open_storage_bins",8)
		root.set_meta("unchanged_support_world_y",[.63,1.03])
	return root

func _fabric_lip(parent:Node3D,size:Vector3,at:Vector3,color:Color)->Node3D:
	# Small fabric wall: four profile rows rather than a full 17-row cabinet.
	var root:=Node3D.new();root.position=at;parent.add_child(root)
	var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
	var radius:=minf(.025,minf(size.x,size.z)*.42)
	var ys:Array[float]=[0,.012,size.y-.012,size.y]
	var shrink:Array[float]=[.007,0,0,.007]
	var cols:int=ring(size.x,size.z,radius,0).size()
	for row in range(4):vertices.append_array(ring(size.x-shrink[row]*2,size.z-shrink[row]*2,radius,ys[row]))
	for row in range(3):
		for j in range(cols):
			var a:=row*cols+j;var b:=row*cols+(j+1)%cols
			indices.append_array(PackedInt32Array([a,b,a+cols,b,b+cols,a+cols]))
	for top in [false,true]:
		var offset:int=3*cols if top else 0
		var center:=vertices.size();vertices.append(Vector3(0,size.y if top else 0,0))
		for j in range(cols):
			var n:=(j+1)%cols
			indices.append_array(PackedInt32Array([center,offset+j,offset+n] if top else [center,offset+n,offset+j]))
	_mesh(root,vertices,indices,color)
	return root

func _open_storage_bin(parent:Node3D,width:float,at:Vector3,index:int)->void:
	var root:=Node3D.new();root.name="OpenFabricBin_"+str(index);root.position=at;parent.add_child(root)
	var cloth:=Color("799fa9")
	# Local -Z opens toward the room. Front lip .07m; back/sides .12m.
	_fabric_lip(root,Vector3(width,.07,.040),Vector3(0,0,-.155),cloth)
	_fabric_lip(root,Vector3(width,.12,.040),Vector3(0,0,.150),cloth)
	for sign_x in [-1.0,1.0]:
		_fabric_lip(root,Vector3(.035,.12,.30),Vector3(sign_x*(width*.5-.0175),0,-.0025),cloth)
	# A flat cloth pull-tab reads as a container, without a lid or fake contents.
	box(root,Vector3(minf(.12,width*.25),.022,.004),Vector3(0,.037,-.177),Color("bfced0"))
	root.set_meta("open_top",true)
	root.set_meta("lip_heights",Vector2(.07,.12))

func make_portal(clear_width: float = 2.86, clear_height: float = 3.55) -> Node3D:
	var root := Node3D.new()
	root.name="LowHeaderPortal"
	root.position.y=.05
	for sign_x in [-1.0,1.0]:
		var jamb:=inflated_pillar(root,.5,clear_height+.10,.6,ORANGE)
		jamb.position.x=sign_x*(clear_width*.5+.25)
		collar(root,.49,.59,.12,.07,Vector3(jamb.position.x,0,0),ORANGE)
		var join:=inflated_case(root,Vector3(.5,.20,.60),ORANGE,false)
		join.position=Vector3(jamb.position.x,clear_height,0)
	var lintel:=inflated_case(root,Vector3(clear_width+1.0,.20,.6),ORANGE,false)
	lintel.position.y=clear_height
	root.set_meta("clear_width",clear_width)
	root.set_meta("clear_height",clear_height)
	root.set_meta("header_world_y",Vector2(3.6,3.8))
	return root

func make_column(height: float = 8.5) -> Node3D:
	var root:=Node3D.new()
	root.name="HallColumn"
	var base:=inflated_case(root,Vector3(.95,.35,.95),ORANGE,true)
	base.position.y=0
	# Same outer footprint: the reduced nominal diameter compensates for the
	# fuller chamber centre; 22 cm cuffs now visibly squeeze separate bellies.
	var shaft:=inflated_pillar(root,.79,height-.7,.79,CREAM,[.15,.50,.85],.22)
	shaft.position.y=.35
	var capital:=inflated_case(root,Vector3(.95,.35,.95),ORANGE,false)
	capital.position.y=height-.35
	collar(root,.90,.90,.13,.36,Vector3.ZERO,ORANGE)
	collar(root,.90,.90,.13,height-.36,Vector3.ZERO,ORANGE)
	return root

func _pillar_pressure(f:float,bands:Array,broad:bool)->float:
	if not broad:
		var p:float=.96-.16*exp(-f/.035)-.16*exp(-(1.0-f)/.035)
		for band in bands:p-=.115*exp(-pow((f-float(band))/.022,2.0))
		return p
	# Each real cuff is a boundary of a pressure chamber. The previous nearly
	# constant-radius tube had only a narrow notch, leaving its long span rigid.
	var lower:=0.0;var upper:=1.0
	for band in bands:
		if float(band)<=f:lower=float(band)
		elif float(band)<upper:upper=float(band)
	var v:float=clampf((f-lower)/maxf(.001,upper-lower),0.0,1.0)
	return .78+.22*pow(maxf(0.0,sin(PI*v)),.70)

func inflated_pillar(parent:Node3D,width:float,height:float,depth:float,color:Color,bands:Array=[.15,.50,.85],band_width:float=.05)->Node3D:
	var root:=Node3D.new()
	root.name="PressureChamber"
	parent.add_child(root)
	var fractions:Array[float]=[]
	var pressure:Array[float]=[]
	for row in range(65):
		var f:=float(row)/64.0
		fractions.append(f)
		var broad_pressure:bool=band_width>=.15
		pressure.append(_pillar_pressure(f,bands,broad_pressure))
	var rx:=width*.5-.022
	var rz:=depth*.5-.022
	var vertices:=PackedVector3Array()
	var indices:=PackedInt32Array()
	var sides:=48
	for row in range(fractions.size()):
		for j in range(sides):
			var angle:=TAU*float(j)/float(sides)
			var f:float=fractions[row]
			var pinch:=0.0
			for band in bands:pinch+=exp(-pow((f-float(band))/.065,2.0))
			var ripple:float=1.0+.018*sin(angle*5.0+f*11.0)*pinch+.009*sin(angle*3.0+f*7.0)
			vertices.append(Vector3(cos(angle)*rx*float(pressure[row])*ripple,height*float(fractions[row]),sin(angle)*rz*float(pressure[row])*ripple))
	for row in range(fractions.size()-1):
		for j in range(sides):
			var a:=row*sides+j
			var b:=row*sides+(j+1)%sides
			indices.append_array(PackedInt32Array([a,b,a+sides,b,b+sides,a+sides]))
	for top in [false,true]:
		var offset:=(fractions.size()-1)*sides if top else 0
		var center:=vertices.size()
		vertices.append(Vector3(0,height if top else 0.0,0))
		for j in range(sides):
			var n:=(j+1)%sides
			indices.append_array(PackedInt32Array([center,offset+j,offset+n] if top else [center,offset+n,offset+j]))
	_mesh(root,vertices,indices,color)
	for f in bands:
		# A broad cloth cuff drapes over the compressed shaft. Matching the
		# pressure field prevents a constant-radius ring floating at its waist.
		var belt_vertices:=PackedVector3Array();var belt_indices:=PackedInt32Array()
		for row in range(7):
			var v:float=clampf(float(f)+(float(row)/6.0-.5)*band_width/height,0.0,1.0)
			var sample:float=v*64.0
			var low:int=mini(63,floori(sample))
			var p:float=lerpf(pressure[low],pressure[low+1],sample-low)
			var pinch:=0.0
			for band in bands:pinch+=exp(-pow((v-float(band))/.065,2.0))
			for j in range(sides):
				var angle:=TAU*float(j)/float(sides)
				var ripple:float=1.0+.018*sin(angle*5.0+v*11.0)*pinch+.009*sin(angle*3.0+v*7.0)
				belt_vertices.append(Vector3(cos(angle)*(rx*p*ripple+.006),height*v,sin(angle)*(rz*p*ripple+.006)))
		for row in range(6):
			for j in range(sides):
				var a:=row*sides+j;var b:=row*sides+(j+1)%sides
				belt_indices.append_array(PackedInt32Array([a,b,a+sides,b,b+sides,a+sides]))
		_mesh(root,belt_vertices,belt_indices,ORANGE)
		var sample:float=float(f)*64.0
		var low:int=mini(63,floori(sample))
		var p:float=lerpf(pressure[low],pressure[low+1],sample-low)
		var pinch:=0.0
		for band in bands:pinch+=exp(-pow((float(f)-float(band))/.065,2.0))
		var ripple:float=1.0+.018*sin(PI*.5*5.0+float(f)*11.0)*pinch+.009*sin(PI*.5*3.0+float(f)*7.0)
		# Buckle back embeds 1 mm into the pressure cuff at its exact height.
		_buckle(root,Vector3(0,height*float(f),rz*p*ripple+.006+.010),.65)

	for angle in [.65,3.79]:
		var seam:=PackedVector3Array()
		for row in range(fractions.size()):
			var f:float=fractions[row]
			var pinch:=0.0
			for band in bands:pinch+=exp(-pow((f-float(band))/.065,2.0))
			var ripple:float=1.0+.018*sin(angle*5.0+f*11.0)*pinch+.009*sin(angle*3.0+f*7.0)
			seam.append(Vector3(cos(angle)*(rx*pressure[row]*ripple+.003),height*f,sin(angle)*(rz*pressure[row]*ripple+.003)))
		tube(root,seam,.004,color.lightened(.10))
	return root

func make_wall_panel(width: float = 3.2, height: float = 2.6) -> Node3D:
	var root:=Node3D.new()
	root.name="WallCanvasPanel"
	# This is a designed panelisation within the actual .3m native wall depth.
	var lower:=inflated_case(root,Vector3(width,height*.38,.30),NAVY,false)
	lower.position.y=0
	for i in range(3):
		var upper:=inflated_case(root,Vector3(width/3.0-.025,height*.62,.30),CREAM,false)
		upper.position=Vector3((float(i)-1.0)*width/3.0,height*.38,0)
	tube(root,PackedVector3Array([Vector3(-width*.48,height*.38,-.155),Vector3(width*.48,height*.38,-.155)]),.018,ORANGE)
	return root


func _canvas_bay_edges(width:float)->PackedFloat32Array:
	if _canvas_bay_cache.has(width):return _canvas_bay_cache[width]
	# Unequal pressure bays are sewn into one continuous field. No new dark
	# battens or semantic wall breaks; the forest print uses this same field.
	var count:int=maxi(1,ceili(width/2.80))
	var weights:Array[float]=[];var total:=0.0
	for i in range(count):
		var w:float=[1.03,.91,1.10,.96][i%4]
		weights.append(w);total+=w
	var edges:=PackedFloat32Array([0.0]);var cursor:=0.0
	for w in weights:
		cursor+=width*w/total;edges.append(cursor)
	_canvas_bay_cache[width]=edges
	return edges

func _canvas_bay_edge(index:int,t:float,width:float)->float:
	var edges:=_canvas_bay_edges(width)
	if index==0 or index==edges.size()-1:return edges[index]
	# A shallow unequal seam bow, fixed at top/bottom. It is not a wave train.
	return edges[index]+[.032,-.025,.041][(index-1)%3]*4.0*t*(1.0-t)

func _canvas_pressure(u:float,t:float,width:float,height:float)->float:
	# All relief remains inside the existing +/- .205 m envelope. An 8 m wall
	# previously had one 10.5 cm swell, so almost every interior normal was flat.
	# Reallocate that depth to human-scale inflated bays and short seam gathers.
	var x:float=clampf(u,0.0,1.0)*width;var y:float=clampf(t,0.0,1.0)*height
	var edges:=_canvas_bay_edges(width);var bay:=edges.size()-2
	for i in range(edges.size()-1):
		if x<=_canvas_bay_edge(i+1,t,width):bay=i;break
	var left:float=_canvas_bay_edge(bay,t,width)
	var right:float=_canvas_bay_edge(bay+1,t,width)
	var span:float=right-left;var q:float=clampf((x-left)/span,0.0,1.0)
	var ex:float=minf(x-left,right-x);var ey:float=minf(y,height-y)
	var edge:float=(1.0-exp(-maxf(0.0,ex)/.055))*(1.0-exp(-ey/.065))
	var belly:float=.132*pow(maxf(0.0,sin(PI*q)),.72)*pow(maxf(0.0,sin(PI*t)),.58)
	belly+=.009*exp(-pow((q-.68)/.27,2.0)-pow((t-.41)/.32,2.0))*edge
	var folds:=0.0
	for side in [0.0,1.0]:
		var reach:float=x-left if side==0.0 else right-x
		for k in range(2):
			var anchor:float=height*(.21+.47*k+.035*((bay+int(side))%3))
			var diagonal:float=y-anchor-(.32 if (k+bay)%2==0 else -.26)*reach
			folds+=.034*(exp(-pow((diagonal-.075)/.12,2.0))-.83*exp(-pow(diagonal/.066,2.0)))*exp(-reach/.48)
	for side in [0.0,1.0]:
		var reach:float=y if side==0.0 else height-y
		for anchor in [.19,.56,.84]:
			var diagonal:float=x-left-span*float(anchor)-(.36 if side==0 else -.29)*reach
			folds+=.026*(exp(-pow((diagonal-.065)/.115,2.0))-.90*exp(-pow(diagonal/.065,2.0)))*exp(-reach/.36)
	return clampf(.060+belly+edge*folds,.054,.205)

func canvas_membrane(parent:Node3D,width:float,height:float,color:Color)->Node3D:
	# Closed backing and visibly inflated skin on both faces. Small skin
	# projection is recorded; wall owners/colliders and doorway spans are unchanged.
	var root:=Node3D.new();root.name="TensionedCanvas";parent.add_child(root)
	var backing:=box(root,Vector3(width,height,.10),Vector3(0,height*.5,0),color)
	backing.material_override=palette.wall_material(color)
	var nx:=64;var ny:=48
	for side in [-1.0,1.0]:
		var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
		for j in range(ny+1):
			for i in range(nx+1):
				var u:=float(i)/nx;var t:=float(j)/ny
				var pressure:=_canvas_pressure(u,t,width,height)
				vertices.append(Vector3((u-.5)*width,t*height,side*pressure))
		for j in range(ny):
			for i in range(nx):
				var a:=j*(nx+1)+i;var c:=a+nx+1
				indices.append_array(PackedInt32Array([a,c,a+1,a+1,c,c+1] if side>0 else [a,a+1,c,a+1,c+1,c]))
		var membrane:=_mesh(root,vertices,indices,color)
		membrane.material_override=palette.wall_material(color)
		for x in [-width*.485,width*.485]:
			box(root,Vector3(.065,height,.016),Vector3(x,height*.5,side*.078),NAVY.darkened(.10))
		for y in [.045,maxf(.045,height-.045)]:
			_canvas_folded_seam(root,width,height,y,side,color)
		for bay in range(1,_canvas_bay_edges(width).size()-1):
			_canvas_bay_seam(root,width,height,bay,side,color)
		for x in [-width*.48,width*.48]:
			for y in [.06,maxf(.06,height-.06)]:
				box(root,Vector3(.095,.095,.018),Vector3(x,y,side*.087),METAL.darkened(.30))
	return root

func _canvas_surface_pressure(u:float,t:float,width:float,height:float)->float:
	# Interpolate the actual 64x48 triangles, not the ideal pressure field.
	# Fine seams must remain on the same discretized skin as the forest print.
	var px:float=clampf(u,0.0,.999999)*64.0;var py:float=clampf(t,0.0,.999999)*48.0
	var x:int=floori(px);var y:int=floori(py)
	var fx:float=px-x;var fy:float=py-y
	var h00:float=_canvas_pressure(float(x)/64.0,float(y)/48.0,width,height)
	var h10:float=_canvas_pressure(float(x+1)/64.0,float(y)/48.0,width,height)
	var h01:float=_canvas_pressure(float(x)/64.0,float(y+1)/48.0,width,height)
	var h11:float=_canvas_pressure(float(x+1)/64.0,float(y+1)/48.0,width,height)
	return h00+(h10-h00)*fx+(h01-h00)*fy if fx+fy<=1.0 else h11+(h01-h11)*(1.0-fx)+(h10-h11)*(1.0-fy)

func _canvas_bay_seam(parent:Node3D,width:float,height:float,bay:int,side:float,color:Color)->void:
	# Same-color folded weld sits in the actual compressed channel. Its broad
	# shoulders come from the membrane, not from floating decorative tubing.
	var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
	for row in range(49):
		var t:float=row/48.0
		var center:float=_canvas_bay_edge(bay,t,width)
		for j in range(5):
			var f:float=j/4.0;var x:float=center+(f-.5)*.045
			var z:float=minf(.205,_canvas_surface_pressure(x/width,t,width,height)+.002+.006*sin(PI*f))
			vertices.append(Vector3(x-width*.5,t*height,side*z))
	for row in range(48):
		for j in range(4):
			var a:=row*5+j;var c:=a+5
			indices.append_array(PackedInt32Array([a,c,a+1,a+1,c,c+1] if side>0 else [a,a+1,c,a+1,c+1,c]))
	var seam:=_mesh(parent,vertices,indices,color.lightened(.025))
	seam.material_override=palette.wall_material(color.lightened(.025))

func _canvas_folded_seam(parent:Node3D,width:float,height:float,y:float,side:float,color:Color)->void:
	# A folded cloth flange with real rounded relief and a small stitch line.
	# Its samples follow the exact membrane, so it neither floats nor reduces
	# the construction to two high-contrast drawn lines.
	var vertices:=PackedVector3Array();var indices:=PackedInt32Array();var nx:=48
	for row in range(5):
		var f:float=row/4.0
		var at_y:float=clampf(y+(f-.5)*.065,.008,height-.008)
		for i in range(nx+1):
			var u:float=.018+.964*i/nx
			var z:float=minf(.205,_canvas_surface_pressure(u,at_y/height,width,height)+.003+.012*sin(PI*f))
			vertices.append(Vector3((u-.5)*width,at_y,side*z))
	for row in range(4):
		for i in range(nx):
			var a:=row*(nx+1)+i;var c:=a+nx+1
			indices.append_array(PackedInt32Array([a,c,a+1,a+1,c,c+1] if side>0 else [a,a+1,c,a+1,c+1,c]))
	var seam:MeshInstance3D=_mesh(parent,vertices,indices,color.lightened(.045))
	seam.material_override=palette.wall_material(color.lightened(.045))
	var points:=PackedVector3Array()
	for i in range(nx+1):
		var u:float=.02+.96*i/nx
		var at_y:float=clampf(y+.018,.008,height-.008)
		points.append(Vector3((u-.5)*width,at_y,side*minf(.202,_canvas_surface_pressure(u,at_y/height,width,height)+.015)))
	tube(parent,points,.0025,color.lightened(.18))

func floor_tiles(parent:Node3D,size:Vector3,region:String)->void:
	var first_child:=parent.get_child_count()
	# All tile faces end at the original native floor top, no raised thresholds.
	box(parent,Vector3(size.x,size.y-.003,size.z),Vector3(0,-.0015,0),Color("ad9a7d"))
	var nx:=maxi(1,ceili(size.x/2.0));var nz:=maxi(1,ceili(size.z/2.0))
	var y:float=size.y*.5
	var tones:Array=[Color("c7b79b"),Color("ccbd9f"),Color("c2b294")]
	if region=="kids":tones=[Color("cbbd9e"),Color("cebea1"),Color("c6b798")]
	var mean:Color=(tones[0]+tones[1]+tones[2])/3.0
	for i in range(tones.size()):tones[i]=mean.lerp(tones[i],.5)
	for x in range(nx):
		for z in range(nz):
			var sx:float=size.x/nx;var sz:float=size.z/nz
			var at:=Vector3(-size.x*.5+sx*(x+.5),y-.001,-size.z*.5+sz*(z+.5))
			box(parent,Vector3(sx-.009,.002,sz-.009),at,tones[(x*7+z*5)%3])
	# Double needle lines are flat, within the original surface tolerance.
	for x in range(1,nx):
		var px:float=-size.x*.5+size.x*x/nx
		for offset in [-.014,.014]:box(parent,Vector3(.003,.0004,size.z),Vector3(px+offset,y+.0002,0),Color("b9a88d"))
	for z in range(1,nz):
		var pz:float=-size.z*.5+size.z*z/nz
		for offset in [-.014,.014]:box(parent,Vector3(size.x,.0004,.003),Vector3(0,y+.0002,pz+offset),Color("b9a88d"))
	for i in range(first_child,parent.get_child_count()):
		var node=parent.get_child(i)
		if node is MeshInstance3D and node.material_override is StandardMaterial3D:
			node.material_override=palette.floor_material(node.material_override.albedo_color)

func opal_fixture(parent:Node3D,diameter:float)->void:
	# Visual fixture only; the scene owner tunes the corresponding native lights.
	var housing:=CylinderMesh.new();housing.top_radius=diameter*.42;housing.bottom_radius=diameter*.50;housing.height=.13;housing.radial_segments=24
	var body:=MeshInstance3D.new();body.mesh=housing;body.material_override=material(NAVY,false);body.position.y=.01;parent.add_child(body)
	var lens:=SphereMesh.new();lens.radius=diameter*.39;lens.height=diameter*.50;lens.radial_segments=24;lens.rings=12
	var diffuser:=MeshInstance3D.new();diffuser.mesh=lens;diffuser.position.y=-.07

	var key:="opal_warm_emission"
	if not materials.has(key):
		var m:=StandardMaterial3D.new();m.albedo_color=Color("fff0cf");m.roughness=.65;m.emission_enabled=true;m.emission=Color("ffe2a5");m.emission_energy_multiplier=.65;materials[key]=m
	diffuser.material_override=materials[key];parent.add_child(diffuser)
	for x in [-diameter*.25,diameter*.25]:box(parent,Vector3(.035,.20,.035),Vector3(x,.12,0),NAVY)
	tube(parent,ring(diameter*.96,diameter*.96,diameter*.46,-.045),.013,CREAM,true)


func roof_diffuser_material()->StandardMaterial3D:
	var key:="roof_translucent_appearance"
	if not materials.has(key):
		var m:=StandardMaterial3D.new();m.albedo_color=Color("f6e8cb");m.roughness=.88;m.emission_enabled=true;m.emission=Color("ffedc5");m.emission_energy_multiplier=.08;materials[key]=m
	return materials[key]

func padded_roof_beam(parent:Node3D,a:Vector3,b:Vector3,radius:float,end_color:Color=Color.TRANSPARENT)->void:
	var span:=b-a;var length:float=span.length()
	var root:=Node3D.new();root.position=a;root.basis=Basis(Quaternion(Vector3.UP,span.normalized()));parent.add_child(root)
	var edge:float=minf(.16,.65/maxf(length,.01))
	var fractions:Array=[0.0,edge*.20,edge*.50,edge,1.0-edge,1.0-edge*.50,1.0-edge*.20,1.0]
	var pressure:Array=[.76,.90,1.0,1.0,1.0,1.0,.90,.76]
	var vertices:=PackedVector3Array();var indices:=PackedInt32Array();var sleeves:=PackedInt32Array();var sides:=24
	for row in range(fractions.size()):
		for j in range(sides):
			var angle:=TAU*j/sides
			vertices.append(Vector3(cos(angle)*radius*pressure[row],length*fractions[row],sin(angle)*radius*pressure[row]))
	for row in range(fractions.size()-1):
		for j in range(sides):
			var a0:=row*sides+j;var b0:=row*sides+(j+1)%sides
			var tris:=PackedInt32Array([a0,b0,a0+sides,b0,b0+sides,a0+sides])
			if end_color.a>0.0 and row!=3:sleeves.append_array(tris)
			else:indices.append_array(tris)
	for top in [false,true]:
		var center:=vertices.size();var offset:=(fractions.size()-1)*sides if top else 0
		vertices.append(Vector3(0,length if top else 0,0))
		for j in range(sides):indices.append_array(PackedInt32Array([center,offset+j,offset+(j+1)%sides] if top else [center,offset+(j+1)%sides,offset+j]))
	_mesh(root,vertices,indices,CREAM)
	if not sleeves.is_empty():_mesh(root,vertices,sleeves,end_color)
	for f in [edge*.55,1.0-edge*.55]:collar(root,radius*1.88,radius*1.88,minf(.08,length*.04),length*f,Vector3.ZERO,end_color if end_color.a>0.0 else CREAM)


func padded_loop(parent:Node3D,width:float,depth:float,corner:float,section:float,y:float,color:Color)->void:
	var path:=ring(width-section*2.0,depth-section*2.0,maxf(.02,corner-section),y)
	var vertices:=PackedVector3Array();var indices:=PackedInt32Array();var n:=path.size();var sides:=10
	for i in range(n):
		var tangent:Vector3=(path[(i+1)%n]-path[(i-1+n)%n]).normalized()
		var outward:=tangent.cross(Vector3.UP).normalized()
		for j in range(sides):
			var a:=TAU*j/sides
			vertices.append(path[i]+section*(outward*cos(a)+Vector3.UP*sin(a)))
	for i in range(n):
		for j in range(sides):
			var a:=i*sides+j;var b:=i*sides+(j+1)%sides;var c:=((i+1)%n)*sides+j;var d:=((i+1)%n)*sides+(j+1)%sides
			indices.append_array(PackedInt32Array([a,c,b,b,c,d]))
	_mesh(parent,vertices,indices,color)

func collar(parent:Node3D,width:float,depth:float,height:float,y:float,at:Vector3,color:Color)->void:
	var mesh:=CylinderMesh.new();mesh.top_radius=.5;mesh.bottom_radius=.5;mesh.height=height;mesh.radial_segments=24
	var node:=MeshInstance3D.new();node.mesh=mesh;node.scale=Vector3(width,1,depth);node.position=at+Vector3(0,y,0);node.material_override=material(color);parent.add_child(node)
