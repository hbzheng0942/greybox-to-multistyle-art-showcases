extends RefCounted
## Local visual relief on existing semantic plaque faces. +Z faces the room.
## No collisions, gameplay nodes, new placements or generated image resources.
const INK := Color("263e4a")
const IVORY := Color("eee0bb")
const OCHRE := Color("b1844b")
const STONE := Color("dcc9a3")
const RIM := Color("a7865c")
const ATLAS := "res://styles/A01/assets/authored_graphics_kit/poster-atlas-d3ed7c3c227f55fa.png"
var _meshes:Dictionary = {}
var _atlas_material:StandardMaterial3D

func decorate(face:Node3D, group:Dictionary, width:float, height:float, world_center:Vector3, soft)->bool:
	var family:String = str(group.get("family_id", ""))
	if family not in ["fossil_panel", "kids_wall_panel", "entry_guide_board"]:
		return false
	var art := Node3D.new()
	art.name = "AuthoredMuseumRelief"
	face.add_child(art)
	if family == "fossil_panel":
		_fossil(art, width, height, 0 if world_center.z < -.5 else (1 if world_center.z < 2.0 else 2), soft)
	elif family == "kids_wall_panel":
		_kids(art, width, height, 0 if world_center.x < -.5 else (2 if world_center.x > .5 else 1), soft)
	else:
		_guide(art, width, height, soft)
	return true

func _fossil(root:Node3D, w:float, h:float, kind:int, soft)->void:
	soft.box(root, Vector3(w*.97,h*.95,.026), Vector3(0,0,.015), RIM)
	soft.box(root, Vector3(w*.92,h*.87,.024), Vector3(0,0,.035), STONE)
	# Slightly irregular inset slab silhouette; relief sits above this surface.
	_poly(root, [[-.438,-.39],[-.452,-.12],[-.439,.36],[-.24,.405],[.18,.388],[.442,.36],[.449,-.28],[.31,-.403]], w,h,.049,Color("e5d3ae"),soft)
	for side in [-1.0,1.0]:
		soft.box(root,Vector3(w*.06,h*.14,.022),Vector3(side*w*.455,0,.054),Color("c57b3c"))
		soft.box(root,Vector3(w*.024,h*.19,.028),Vector3(side*w*.46,0,.062),INK)
	var drawing := Node3D.new()
	drawing.position.y = h*.025
	root.add_child(drawing)
	match kind:
		0: _fish(drawing,w,h,soft)
		1: _ribs(drawing,w,h,soft)
		2: _leaf(drawing,w,h,soft)
	var labels:Array[String] = ["01  /  ANCIENT SEAS", "02  /  LIFE IN BONE", "03  /  FOSSIL LEAF"]
	_text(root,labels[kind],w*.54,h*.047,Vector3(0,-h*.343,.077),Color("806546"),soft)

func _fish(root:Node3D,w:float,h:float,soft)->void:
	# Broad skull, vertebral column, tapered paired ribs and forked caudal fin.
	_poly(root,[[-.34,.015],[-.30,.13],[-.20,.165],[-.132,.08],[-.14,-.09],[-.25,-.135]],w,h,.083,OCHRE,soft)
	_poly(root,[[-.33,-.005],[-.25,-.145],[-.14,-.12],[-.17,-.17],[-.29,-.17]],w,h,.085,OCHRE,soft)
	_ellipse(root,Vector2(-.255,.055),Vector2(.032,.043),w,h,.087,Color("776044"),soft)
	_line(root,[[-.155,0],[-.07,.015],[.06,.012],[.18,0],[.29,-.015]],w,h,.083,h*.021,OCHRE,soft)
	for i in range(9):
		var x:float = -.105 + float(i)*.041
		var span:float = .20*sin((float(i)+1.8)/12.0*PI)
		for sign_y in [-1.0,1.0]:
			_line(root,[[x,.01],[x-.025,span*sign_y*.58],[x-.045,span*sign_y]],w,h,.080,h*.012,OCHRE,soft)
		_ellipse(root,Vector2(x,.008),Vector2(.012,.029),w,h,.089,Color("bd945b"),soft)
	_poly(root,[[.25,-.014],[.365,.17],[.345,.025],[.37,-.155]],w,h,.080,OCHRE,soft)
	for yy in [-.105,-.035,.04,.10]:
		_line(root,[[.27,-.014],[.345,yy]],w,h,.089,h*.007,Color("d9bb86"),soft)
	_poly(root,[[-.035,.19],[.065,.30],[.14,.18]],w,h,.075,OCHRE,soft)
	_poly(root,[[-.02,-.18],[.08,-.285],[.135,-.17]],w,h,.075,OCHRE,soft)

func _ribs(root:Node3D,w:float,h:float,soft)->void:
	var spine:Array = []
	for i in range(12):
		var t:float = float(i)/11.0
		spine.append([-.33+t*.64,.04+.21*sin(t*PI)])
	_line(root,spine,w,h,.085,h*.028,OCHRE,soft)
	for i in range(9):
		var t:float = (float(i)+1.0)/10.0
		var x:float = -.33+t*.64
		var y:float = .04+.21*sin(t*PI)
		var length:float = .22+.20*sin(t*PI)
		_line(root,[[x,y],[x+.025,y-.07],[x+.048,y-length*.65],[x+.035,y-length],[x-.003,y-length-.025]],w,h,.078,h*.019,OCHRE,soft)
		_ellipse(root,Vector2(x,y),Vector2(.018,.039),w,h,.096,Color("bc945d"),soft)
	# Thickened shoulder end distinguishes the specimen from an abstract comb.
	_poly(root,[[-.35,.015],[-.36,.15],[-.30,.19],[-.275,.12],[-.30,.04]],w,h,.078,OCHRE,soft)

func _leaf(root:Node3D,w:float,h:float,soft)->void:
	_poly(root,[[-.31,-.23],[-.30,-.03],[-.24,.12],[-.12,.245],[.05,.30],[.30,.26],[.29,.10],[.20,-.09],[.04,-.23],[-.14,-.28]],w,h,.076,OCHRE,soft)
	_line(root,[[-.36,-.30],[-.22,-.20],[-.05,-.08],[.12,.08],[.28,.25]],w,h,.091,h*.017,Color("d5b985"),soft)
	for i in range(5):
		var t:float = float(i)/5.0
		var x:float = -.24+t*.43
		var y:float = -.20+t*.38
		_line(root,[[x,y],[x-.055,y+.16],[x-.047,y+.24]],w,h,.087,h*.010,Color("d5b985"),soft)
		_line(root,[[x,y],[x+.10,y-.015],[x+.17,y+.025]],w,h,.087,h*.010,Color("d5b985"),soft)

func _kids(root:Node3D,w:float,h:float,kind:int,soft)->void:
	var colors:Array[Color] = [Color("c8783f"),Color("679896"),Color("9d788d")]
	var base:Color = colors[kind]
	soft.box(root,Vector3(w*.95,h*.94,.014),Vector3(0,0,.013),base)
	_line(root,[[-.44,-.43],[-.44,.43],[.44,.43],[.44,-.43]],w,h,.025,minf(w,h)*.005,IVORY,soft,true)
	for sx in [-1.0,1.0]:
		for sy in [-1.0,1.0]:
			soft.box(root,Vector3(w*.066,h*.092,.016),Vector3(sx*w*.435,sy*h*.42,.033),INK)
			_ellipse(root,Vector2(sx*.435,sy*.42),Vector2(.014,.014),w,h,.044,Color("c1a36b"),soft)
			_ellipse(root,Vector2(sx*.435,sy*.42),Vector2(.006,.006),w,h,.047,INK,soft)
	match kind:
		0: _skull(root,w,h,base,soft)
		1: _trilobite(root,w,h,base,soft)
		2: _ammonite(root,w,h,base,soft)
	for i in range(3):
		_footprint(root,Vector2(-.19+float(i)*.19,-.32+(float(i%2)*.028)),w,h,soft)

func _skull(root:Node3D,w:float,h:float,base:Color,soft)->void:
	# A filled theropod skull silhouette with open jaw, orbit and distinct teeth.
	_poly(root,[[-.33,.04],[-.30,.22],[-.20,.31],[-.05,.32],[.08,.25],[.31,.18],[.33,.08],[.26,.015],[.035,.025],[-.08,-.04],[-.18,-.09],[-.29,-.07]],w,h,.040,IVORY,soft)
	_poly(root,[[-.28,-.08],[-.18,-.115],[.00,-.14],[.26,-.105],[.29,-.16],[.13,-.20],[-.06,-.21],[-.24,-.17]],w,h,.041,IVORY,soft)
	_ellipse(root,Vector2(-.145,.15),Vector2(.068,.077),w,h,.045,base,soft)
	_poly(root,[[-.02,.18],[.095,.15],[.045,.065],[-.035,.055]],w,h,.045,base,soft)
	_ellipse(root,Vector2(.245,.12),Vector2(.037,.027),w,h,.045,base,soft)
	for i in range(7):
		var x:float = -.025+float(i)*.043
		_poly(root,[[x,.024],[x+.029,.024],[x+.012,-.062]],w,h,.044,IVORY,soft)
		_poly(root,[[x,-.139],[x+.026,-.139],[x+.015,-.085]],w,h,.044,IVORY,soft)

func _trilobite(root:Node3D,w:float,h:float,base:Color,soft)->void:
	# Separate pleural ribs expose a segmented outline; no circular face or eyes.
	_poly(root,[[-.235,.17],[-.205,.275],[-.12,.33],[-.015,.35],[.10,.32],[.205,.24],[.235,.15],[.145,.185],[.09,.235],[.025,.26],[-.045,.255],[-.115,.205],[-.15,.165]],w,h,.042,IVORY,soft)
	_poly(root,[[-.065,.255],[.02,.28],[.065,.22],[.07,.095],[.05,-.105],[.018,-.24],[-.025,-.265],[-.06,-.15],[-.08,.07]],w,h,.040,IVORY,soft)
	for i in range(8):
		var y:float = .17-float(i)*.046
		var span:float = .225-float(i)*.020
		for side in [-1.0,1.0]:
			_line(root,[[side*.053,y],[side*(span*.65),y-.008],[side*span,y-.046],[side*(span+.005),y-.084]],w,h,.041,minf(w,h)*.012,IVORY,soft)
		_line(root,[[-.049,y-.011],[.0,y-.006],[.049,y-.013]],w,h,.048,minf(w,h)*.006,base,soft)
	# Curved cephalic sutures define the three lobes without cartoon eye sockets.
	_line(root,[[-.075,.325],[-.065,.285],[-.095,.245]],w,h,.048,minf(w,h)*.008,base,soft)
	_line(root,[[.075,.312],[.065,.275],[.095,.235]],w,h,.048,minf(w,h)*.008,base,soft)

func _ammonite(root:Node3D,w:float,h:float,base:Color,soft)->void:
	_ellipse(root,Vector2(-.015,.075),Vector2(.292,.292),w,h,.038,IVORY,soft)
	var spiral:Array = []
	for i in range(65):
		var t:float = float(i)/64.0
		var a:float = t*TAU*2.15
		var r:float = .018+.265*t
		spiral.append([-.015+cos(a)*r,.075+sin(a)*r])
	_line(root,spiral,w,h,.045,minf(w,h)*.010,base,soft)
	for i in range(11):
		var a:float = -.35+float(i)*.49
		_line(root,[[cos(a)*.222-.015,sin(a)*.222+.075],[cos(a+.055)*.282-.015,sin(a+.055)*.282+.075]],w,h,.046,minf(w,h)*.006,base,soft)

func _footprint(root:Node3D,at:Vector2,w:float,h:float,soft)->void:
	_poly(root,[[at.x-.014,at.y-.03],[at.x+.017,at.y-.02],[at.x+.02,at.y+.014],[at.x+.055,at.y+.035],[at.x+.022,at.y+.032],[at.x+.01,at.y+.068],[at.x-.003,at.y+.035],[at.x-.033,at.y+.046],[at.x-.014,at.y+.015]],w,h,.043,IVORY,soft)

func _guide(root:Node3D,w:float,h:float,soft)->void:
	soft.box(root,Vector3(w*.97,h*.96,.033),Vector3(0,0,.018),RIM)
	soft.box(root,Vector3(w*.91,h*.90,.018),Vector3(0,0,.044),IVORY)
	_text(root,"MUSEUM  /  FIELD GUIDE",w*.76,h*.063,Vector3(0,h*.365,.061),INK,soft)
	var image_size:float = minf(w*.60,h*.48)
	_atlas_picture(root,image_size,Vector3(-w*.095,h*.048,.059))
	# Curatorial color bar and generous typography, with no invented navigation map.
	for i in range(3):
		var shades:Array[Color] = [Color("c8783f"),Color("679896"),Color("9d788d")]
		soft.box(root,Vector3(w*.065,h*.085,.008),Vector3(w*.325,h*(.19-float(i)*.13),.062),shades[i])
	_text(root,"NATURAL HISTORY",w*.72,h*.047,Vector3(0,-h*.263,.065),INK,soft)
	_line(root,[[-.34,-.315],[.34,-.315]],w,h,.065,minf(w,h)*.003,RIM,soft)
	_text(root,"EXPLORE  /  DISCOVER  /  PLAY",w*.72,h*.025,Vector3(0,-h*.369,.065),Color("7d674c"),soft)

func _atlas_picture(root:Node3D,size:float,at:Vector3)->void:
	if _atlas_material == null:
		_atlas_material = StandardMaterial3D.new()
		_atlas_material.albedo_texture = load(ATLAS)
		_atlas_material.roughness = .92
	var arr:Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-size*.5,-size*.5,0),Vector3(-size*.5,size*.5,0),Vector3(size*.5,size*.5,0),Vector3(size*.5,-size*.5,0)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3(0,0,1),Vector3(0,0,1),Vector3(0,0,1),Vector3(0,0,1)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(.004,.496),Vector2(.004,.004),Vector2(.329,.004),Vector2(.329,.496)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
	var node := MeshInstance3D.new()
	node.name = "ExistingMammothIllustration"
	node.mesh = mesh
	node.position = at
	node.material_override = _atlas_material
	root.add_child(node)

func _poly(root:Node3D,coords:Array,w:float,h:float,z:float,color:Color,soft)->void:
	var points := PackedVector2Array()
	for p in coords: points.append(Vector2(float(p[0])*w,float(p[1])*h))
	var key:String = str(points)
	if not _meshes.has(key):
		var source:PackedInt32Array = Geometry2D.triangulate_polygon(points)
		if source.is_empty(): return
		var indices := PackedInt32Array()
		for i in range(0,source.size(),3):
			var a:int = source[i]
			var b:int = source[i+1]
			var c:int = source[i+2]
			if (points[b]-points[a]).cross(points[c]-points[a]) > 0.0:
				indices.append_array(PackedInt32Array([a,c,b]))
			else: indices.append_array(PackedInt32Array([a,b,c]))
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		for point in points:
			vertices.append(Vector3(point.x,point.y,0))
			normals.append(Vector3(0,0,1))
			uvs.append(Vector2(point.x/maxf(w,.001)+.5,.5-point.y/maxf(h,.001)))
		var arr:Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vertices
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
		_meshes[key] = mesh
	var node := MeshInstance3D.new()
	node.mesh = _meshes[key]
	node.position.z = z
	node.material_override = soft.material(color)
	root.add_child(node)

func _ellipse(root:Node3D,at:Vector2,radius:Vector2,w:float,h:float,z:float,color:Color,soft)->void:
	var coords:Array = []
	for i in range(32):
		var a:float = float(i)/32.0*TAU
		coords.append([at.x+cos(a)*radius.x,at.y+sin(a)*radius.y])
	_poly(root,coords,w,h,z,color,soft)

func _line(root:Node3D,coords:Array,w:float,h:float,z:float,radius:float,color:Color,soft,closed:bool=false)->void:
	var points := PackedVector3Array()
	for p in coords: points.append(Vector3(float(p[0])*w,float(p[1])*h,z))
	soft.tube(root,points,radius,color,closed)

func _text(root:Node3D,content:String,max_width:float,line_height:float,at:Vector3,color:Color,soft)->void:
	var shape := TextMesh.new()
	shape.font = ThemeDB.fallback_font
	shape.text = content
	shape.font_size = 48
	shape.pixel_size = line_height/48.0
	shape.depth = 0.0
	shape.curve_step = 2.5
	var text_width:float = shape.get_aabb().size.x
	if text_width > max_width: shape.pixel_size *= max_width/text_width
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.position = at
	node.material_override = soft.material(color,false)
	root.add_child(node)
