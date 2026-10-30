extends RefCounted
## Local A01 source kits. Only visual geometry is produced; physics remains native.
const SOFT = preload("res://styles/A01/runtime/modules/e6dcf42d578a6ccd-soft_shell_library.gd")
const GRAPHICS=preload("res://styles/A01/runtime/modules/31d2527de24987c4-graphics_relief.gd")
const LAYOUT=preload("res://styles/A01/runtime/modules/ec58f2faa7cec5bb-concept_layout.gd")
const FOREST=preload("res://styles/A01/runtime/modules/103f70d0fc575254-forest_mural.gd")
var layout=LAYOUT.new()
var forest=FOREST.new()
var graphics=GRAPHICS.new()
var soft = SOFT.new()
var cache: Dictionary = {}
var clipped_panels:Dictionary={}
var poster_material:StandardMaterial3D
const POSTER_MANIFEST="res://styles/A01/runtime/modules/dcb734d66fbc1b19-graphics-atlas.json"
const ENTRY_PICTURE={"family_id":"information_panel","id":"vestibule/entry-wall-art","region":"vestibule","native_world_aabb":{"min":[-2.86,1.65,8.65],"size":[.06,1.60,1.50]}}
var cream := Color("e5d7b6")
var navy := Color("21384d")
var orange := Color("d87935")

func v(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func pack(root: Node3D) -> PackedScene:
	_owners(root,root)
	var scene := PackedScene.new()
	if scene.pack(root) != OK:
		root.free()
		return null
	root.free()
	return scene

func _owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner=root
		_owners(child,root)

func make(group: Dictionary, catalog) -> Dictionary:
	var family: String=group.family_id
	var root:=Node3D.new()
	root.name="A01_"+family
	var anchor: Node3D=catalog.entries[group.anchor_id].visual
	var frame: Transform3D=anchor.global_transform
	var size: Vector3=v(group.primary_world_aabb.size)
	if family=="porcelain_shelf":
		frame=Transform3D(Basis(Vector3.UP,float(group.placement.rotation_y)),v(group.placement.origin))
		soft.box(root,Vector3(8.76,3,.22),Vector3(0,1.55,-.11),navy)
		var base:Node3D=soft.inflated_case(root,Vector3(8.76,.16,.6),cream,true)
		base.position=Vector3(0,0,.08)
		var crown:Node3D=soft.inflated_case(root,Vector3(8.76,.22,.62),navy,false)
		crown.position=Vector3(0,2.95,.08)
		for y in [.95,1.67,2.39]:
			var shelf:Node3D=soft.inflated_case(root,Vector3(8.76,.14,.5),cream,true)
			shelf.position=Vector3(0,float(y)+.035-.14,.14)
		# Side uprights sit outside the eight real plate footprints on each row.
		for x in [-4.22,4.22]:
			var post:Node3D=soft.inflated_pillar(root,.15,2.95,.18,Color("ac9b80"),[])
			post.position=Vector3(x,.08,.13)
		# A small ceramics study sits in the existing blank upper shelf backing.
		var study:=Node3D.new();study.position=Vector3(0,2.67,.014);root.add_child(study)
		_atlas_plane(study,.44,.44,2,Vector3.ZERO)
		var baked:Node3D=soft.bake_static_visual(root)
		root.free()
		return {"scene":pack(baked),"world_transform":frame,"method":"authored_native_shelf_interfaces"}
	if SOFT.RECIPES.has(family):
		frame=Transform3D(Basis(Vector3.UP,float(group.placement.rotation_y)),v(group.placement.origin))
		var override_size:=size if family=="kids_soft_block" else Vector3.ZERO
		var key:=family+str(override_size)
		if not cache.has(key):
			var wrapper:=Node3D.new()
			wrapper.add_child(soft.make_family(family,override_size))
			var baked: Node3D=soft.bake_static_visual(wrapper)
			wrapper.free()
			cache[key]=pack(baked)
		root.free()
		return {"scene":cache[key],"world_transform":frame,"method":"authored_furniture"}
	if family=="portal_frame":
		frame=Transform3D(Basis(Vector3.UP,float(group.placement.rotation_y)),v(group.placement.origin))
		root.add_child(soft.make_portal(float(group.portal.clear_width),3.55))
		var above: float=float(group.portal.header_top)-3.8
		if above>.01:
			var fill: Node3D=_wall_panel(float(group.portal.nominal_width),above,3.8,str(group.region))
			fill.position.y=3.8
			root.add_child(fill)
	elif family=="hall_ceiling_detail":
		# Legacy decorative grid superseded by one column-aligned pressure frame.
		pass
	elif family=="hall_column":
		frame=Transform3D(Basis.IDENTITY,v(group.placement.origin))
		root.add_child(soft.make_column(float(group.native_world_aabb.size[1])))
	elif family=="shell_wall":
		var box:=AABB(v(group.primary_world_aabb.min),size)
		var along_x:=size.x>size.z
		var width: float=size.x if along_x else size.z
		frame=Transform3D(Basis(Vector3.UP,0.0 if along_x else PI*.5),Vector3(box.get_center().x,box.position.y,box.get_center().z))
		var segments:Array[Vector2]=layout.wall_segments(str(group.region),width,str(group.id))
		for segment in segments:
			# The south hall wall is also the vestibule's north face: its outer
			# side receives the entry palette, not the hall's high cream band.
			var positive_region:String="vestibule" if str(group.region)=="hall" and box.get_center().z>7.8 and along_x else ""
			var panel:Node3D=_wall_panel(segment.y-.006,size.y,box.position.y,str(group.region),positive_region)
			panel.position.x=segment.x
			root.add_child(panel)
		forest.apply(root,group,segments,soft)
		if str(group.id)=="vestibule/shell_wall/-3.0_9.7":
			var art_box:=_graphic_box(ENTRY_PICTURE)
			var artwork:=Node3D.new()
			artwork.name="ConceptMammothWallPicture"
			artwork.transform=frame.affine_inverse()*Transform3D(Basis(Vector3.UP,PI*.5),art_box.get_center()+Vector3(.04,0,0))
			root.add_child(artwork)
			_framed_picture(artwork,1.50,1.60,0)
	elif family=="main_backdrop":
		# One complete dark field behind the mammoth. Do not inherit the three
		# greybox decorative strips as three unrelated panels / floating bars.
		frame=Transform3D(Basis.IDENTITY,Vector3(-1.20,.10,-5.64))
		var backdrop:Node3D=soft.canvas_membrane(root,6.80,4.15,navy.darkened(.12))
		backdrop.scale.z=.70 # .2072 total visual depth, within the old .26 envelope.
	elif family=="shell_floor":
		var box:=AABB(v(group.primary_world_aabb.min),size)
		frame=Transform3D(Basis.IDENTITY,box.get_center())
		soft.floor_tiles(root,size,str(group.region))
		# Flush graphic borders, not another raised support plane.
		var y:=size.y*.5+.0004
		for sign_v in [-1.0,1.0]:
			soft.box(root,Vector3(size.x-1.0,.0006,.018),Vector3(0,y,sign_v*(size.z*.5-.55)),orange)
			soft.box(root,Vector3(.018,.0006,size.z-1.0),Vector3(sign_v*(size.x*.5-.55),y,0),orange)
	elif family=="shell_ceiling":
		var box:=AABB(v(group.primary_world_aabb.min),size)
		frame=Transform3D(Basis.IDENTITY,box.position+Vector3(size.x*.5,0,size.z*.5))
		# Continuous backing closes tile corner gaps and stops exterior sun leaks.
		soft.box(root,Vector3(size.x,.02,size.z),Vector3(0,.27,0),cream)
		var hall:bool=str(group.region)=="hall"
		var vestibule:bool=str(group.region)=="vestibule"
		# Broad 8m hall bays; two large leaves per gallery, no tight grid.
		var nx:int=maxi(1,ceili(size.x/8.0)) if hall else (2 if size.x>size.z and not vestibule else 1)
		var nz:int=maxi(1,ceili(size.z/8.0)) if hall else (2 if size.z>=size.x and not vestibule else 1)
		for x in range(nx):
			for z in range(nz):
				var panel:Node3D=soft.inflated_case(root,Vector3(size.x/nx-.025,.12,size.z/nz-.025),cream,false)
				panel.position=Vector3(-size.x*.5+size.x*(float(x)+.5)/nx,.10,-size.z*.5+size.z*(float(z)+.5)/nz)
				var diffuser:=soft.box(root,Vector3(size.x/nx-.16,.004,size.z/nz-.16),panel.position+Vector3(0,-.003,0),cream)
				diffuser.material_override=soft.roof_diffuser_material()
		# Hall pressure beams hang.33m below its8.5m roof. Low vestibule stays within its original roof slab.
		var beam_radius:float=.27 if hall else .22
		var beam_y:float=-.06 if hall else -.04
		# room_structure owns the gallery perimeter beams; only one interior
		# divider remains here. The low vestibule keeps its complete backing.
		if hall:
			# One frame, aligned with four real column centres. Ends meet caps;
			# no legacy grid and no unrelated beams penetrating through shafts.
			var wy:float=8.28-box.position.y
			for x in [-7.05,7.05]:
				soft.padded_roof_beam(root,Vector3(x,wy,-4.2-box.get_center().z+.38),Vector3(x,wy,6.2-box.get_center().z-.38),.25)
			for z in [-4.2,6.2]:
				soft.padded_roof_beam(root,Vector3(-6.67,wy,z-box.get_center().z),Vector3(6.67,wy,z-box.get_center().z),.25)
		else:
			for x in range(1,nx):
				var px:float=-size.x*.5+size.x*x/nx
				soft.padded_roof_beam(root,Vector3(px,beam_y,-size.z*.5+.14),Vector3(px,beam_y,size.z*.5-.14),beam_radius)
			for z in range(1,nz):
				var pz:float=-size.z*.5+size.z*z/nz
				soft.padded_roof_beam(root,Vector3(-size.x*.5+.14,beam_y,pz),Vector3(size.x*.5-.14,beam_y,pz),beam_radius)

	elif family=="light_fixture":
		var box:=AABB(v(group.primary_world_aabb.min),size)
		frame=Transform3D(Basis.IDENTITY,box.get_center())
		soft.opal_fixture(root,maxf(size.x,size.z))
	elif str(group.asset_id)=="authored_small_props_kit":
		_copy_native(root,group,catalog,frame,cream)
		var local_box:=_local_bounds(root)
		if family=="prop_plate":
			for child in root.get_children():root.remove_child(child);child.free()
			_ceramic_plate(root,local_box,absi(str(group.id).hash()))
		elif family=="prop_ball":
			var colors:Array=[orange,Color("80a7ab"),Color("d6bb58"),cream]
			for child in root.get_children():
				if child is MeshInstance3D:child.material_override=soft.material(colors[absi(str(group.id).hash())%4])
			var radius:=local_box.size.x*.5
			var points:=PackedVector3Array()
			for i in range(32):
				var a:=TAU*i/32.0
				points.append(local_box.get_center()+Vector3(cos(a),sin(a),0)*radius)
			soft.tube(root,points,.0025,orange,true)
		elif family=="prop_craft":
			for child in root.get_children():root.remove_child(child);child.free()
			_craft_shape(root,local_box,absi(str(group.id).hash()))
		elif family=="prop_button":
			for child in root.get_children():root.remove_child(child);child.free()
			var dome:=SphereMesh.new();dome.radius=local_box.size.x*.48;dome.height=local_box.size.y*.82;dome.radial_segments=24;dome.rings=10
			var button:=MeshInstance3D.new();button.mesh=dome;button.material_override=soft.material(orange);button.position=local_box.get_center()+Vector3(0,local_box.size.y*.08,0);root.add_child(button)
			var line:=PackedVector3Array()
			for i in range(36):
				var angle:=TAU*i/36.0;line.append(local_box.get_center()+Vector3(cos(angle)*local_box.size.x*.42,-local_box.size.y*.08,sin(angle)*local_box.size.z*.42))
			soft.tube(root,line,.003,cream,true)
		elif family=="prop_brochure":
			for child in root.get_children():root.remove_child(child);child.free()
			for j in range(3):
				var center:Vector3=local_box.get_center()+Vector3(0,0,(j-1)*local_box.size.z*.29)
				var width:float=local_box.size.x*.94;var height:float=local_box.size.y*(.92+.025*j);var depth:float=local_box.size.z*.24
				soft.box(root,Vector3(width-.018,height-.012,depth-.010),center,cream)
				var cover:Color=orange if j==2 else navy
				soft.box(root,Vector3(.012,height,depth),center+Vector3(-width*.5+.006,0,0),cover)
				for sign_z in [-1.0,1.0]:
					soft.box(root,Vector3(width,height,.004),center+Vector3(0,0,sign_z*(depth*.5-.002)),cover)
					soft.box(root,Vector3(width*.64,height*.06,.002),center+Vector3(0,height*.22,sign_z*(depth*.5+.001)),cream)
					soft.box(root,Vector3(width*.64,height*.015,.002),center+Vector3(0,-height*.22,sign_z*(depth*.5+.001)),cream)

	elif str(group.asset_id)=="authored_graphics_kit":
		var graphic_box:=_graphic_box(group)
		if clipped_panels.has(group.id):
			var panel:=Node3D.new()
			panel.transform=frame.affine_inverse()*Transform3D(Basis.IDENTITY,graphic_box.get_center())
			root.add_child(panel)
			soft.box(panel,graphic_box.size,Vector3.ZERO,cream)
		else:_copy_native(root,group,catalog,frame,cream)
		_add_graphic(root,group,frame)
	else:
		# Exact native trim/support interfaces are retained. Larger visible panels
		# receive real soft contours; narrow ropes and fixtures reuse their geometry.
		for id in group.semantic_ids:
			var entry:Dictionary=catalog.entries[id]
			for mesh:MeshInstance3D in entry.greybox.find_children("*","MeshInstance3D",true,false):
				var mesh_size:=mesh.mesh.get_aabb().size
				if mesh.mesh is BoxMesh and minf(mesh_size.x,mesh_size.z)>.12 and mesh_size.y>.10:
					var container:=Node3D.new()
					container.transform=frame.affine_inverse()*mesh.global_transform
					root.add_child(container)
					var cushion:Node3D=soft.inflated_case(container,mesh_size,navy if family=="main_backdrop" else cream,false)
					cushion.position.y=-mesh_size.y*.5
				else:
					var copy:=MeshInstance3D.new()
					copy.mesh=mesh.mesh
					copy.transform=frame.affine_inverse()*mesh.global_transform
					copy.material_override=soft.material(orange if family in ["barrier_rope","light_fixture"] else navy)
					root.add_child(copy)
	var baked:Node3D=soft.bake_static_visual(root)
	if family in ["light_fixture","shell_floor"]:
		# Luminous fixtures and coplanar floor layers do not cast into the room.
		# Floors still receive the characters' and exhibits' contact shadows.
		for mesh in baked.get_children():
			if mesh is MeshInstance3D:mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.free()
	return {"scene":pack(baked),"world_transform":frame,"method":"authored_"+str(group.asset_id)}

func _copy_native(root:Node3D, group:Dictionary, catalog, frame:Transform3D, color:Color)->void:
	for id in group.semantic_ids:
		for mesh:MeshInstance3D in catalog.entries[id].greybox.find_children("*","MeshInstance3D",true,false):
			var copy:=MeshInstance3D.new()
			copy.mesh=mesh.mesh
			copy.transform=frame.affine_inverse()*mesh.global_transform
			copy.material_override=soft.material(color,false if group.family_id=="prop_plate" else true)
			root.add_child(copy)

func _add_graphic(root:Node3D, group:Dictionary, frame:Transform3D)->void:
	var family:String=group.family_id
	if family in ["kids_mat","entry_mat"]:
		for child in root.get_children():
			if child is MeshInstance3D:child.material_override=soft.material(Color("b58a92") if family=="kids_mat" else navy)
		return
	var box:=_graphic_box(group)
	var center:=box.get_center()
	var normal:=Vector3(0,0,1)
	var yaw:=0.0
	if box.size.x<box.size.z:
		normal=Vector3(-1,0,0) if center.x>0 else Vector3(1,0,0)
		yaw=-PI*.5 if center.x>0 else PI*.5
	else:
		normal=Vector3(0,0,-1) if center.z>1 else Vector3(0,0,1)
		yaw=PI if center.z>1 else 0.0
	var face:=Node3D.new()
	face.transform=frame.affine_inverse()*Transform3D(Basis(Vector3.UP,yaw),center+normal*(minf(box.size.x,box.size.z)*.5+.012))
	root.add_child(face)
	var width:=maxf(box.size.x,box.size.z)
	var height:=box.size.y
	if graphics.decorate(face,group,width,height,center,soft):return
	if family in ["hall_wall_print","information_panel"]:
		if family=="information_panel":_framed_picture(face,width,height,0)
		else:_framed_picture(face,width,height,[1,4,0][absi(str(group.id).hash())%3])
		return
	var words:={"hall":"MUSEUM DOG","porcelain":"CERAMICS","taxidermy":"NATURAL HISTORY","kids":"PLAY LAB","vestibule":"WELCOME"}
	var text:String=words.get(str(group.region),"EXHIBIT")
	if family=="exhibit_label": text="COLLECTION"
	if family=="directional_sign":
		text="CERAMICS" if str(group.id).ends_with("west") else ("NATURAL HISTORY" if str(group.id).ends_with("east") else ("PLAY LAB" if str(group.id).ends_with("north") else "WELCOME"))
	var shape:=TextMesh.new()
	shape.text=text
	shape.font=ThemeDB.fallback_font
	shape.font_size=48
	shape.pixel_size=minf(width/maxf(7.0,text.length())*.025,height*.009)
	shape.depth=.001
	var lettering:=MeshInstance3D.new()
	lettering.mesh=shape
	lettering.material_override=soft.material(navy,false)
	face.add_child(lettering)
	soft.box(face,Vector3(width*.7,.025,.006),Vector3(0,-height*.26,.006),orange)

func _local_bounds(root:Node3D)->AABB:
	var result:=AABB()
	var first:=true
	for mesh:MeshInstance3D in root.get_children():
		var box:AABB=mesh.transform*mesh.mesh.get_aabb()
		result=box if first else result.merge(box)
		first=false
	return result

func _wall_panel(width:float,height:float,base_y:float,region:String="hall",positive_region:String="")->Node3D:
	var root:=Node3D.new();root.name="ConceptCanvasWall"
	var regions:Array=[region] if positive_region.is_empty() else [region,positive_region]
	for region_index in range(regions.size()):
		for band in layout.wall_bands(str(regions[region_index])):
			var lo:float=maxf(base_y,float(band[0]));var hi:float=minf(base_y+height,float(band[1]))
			if hi-lo<.01:continue
			var color:Color=cream if str(band[2])=="cream" else navy
			# Tall cloth fields have two broad horizontal pressure bays. Existing
			# taxidermy print band remains one bay so its draped graphics coincide.
			var count:int=maxi(1,ceili((hi-lo)/2.70))
			for section in range(count):
				var h:float=(hi-lo)/count
				var panel:Node3D=soft.canvas_membrane(root,width,h-(.012 if count>1 else 0.0),color)
				panel.position.y=lo-base_y+section*h+(.006 if count>1 else 0.0)
				if regions.size()==2:
					for child in panel.get_children():
						if not child is MeshInstance3D:continue
						var local_box:AABB=child.transform*child.mesh.get_aabb()
						var z:float=local_box.get_center().z
						if absf(z)<.025 or (region_index==0 and z>0) or (region_index==1 and z<0):
							panel.remove_child(child);child.free()
	if regions.size()==2:soft.box(root,Vector3(width,height,.10),Vector3(0,height*.5,0),navy)
	return root

func _graphic_box(group:Dictionary)->AABB:
	var original:=AABB(v(group.native_world_aabb.min),v(group.native_world_aabb.size))
	var box:AABB=layout.graphic_box(group,original)
	if str(group.family_id) in ["kids_wall_panel","fossil_panel","hall_wall_print","information_panel","entry_guide_board"]:
		var center:Vector3=box.get_center()
		if box.size.x<box.size.z:box.position.x+=-.065 if center.x>0 else .065
		else:box.position.z+=-.065 if center.z>1 else .065
	# Four measured door clear prisms: span axis, plane axis, plane, low/high span.
	for portal in [[2,0,-8.0,.07,2.93],[2,0,8.0,.07,2.93],[0,2,-6.0,2.27,3.83],[0,2,8.0,-1.43,1.43]]:
		var axis:int=portal[0]
		var normal_axis:int=portal[1]
		if box.position.y>=3.6 or box.end.y<=.05:continue
		if box.position[normal_axis]>=float(portal[2])+.45 or box.end[normal_axis]<=float(portal[2])-.45:continue
		var low:float=float(portal[3])-.06
		var high:float=float(portal[4])+.06
		if box.position[axis]>=high or box.end[axis]<=low:continue
		var start:float=box.position[axis]
		var end:float=box.end[axis]
		if low-start>=end-high:box.size[axis]=maxf(.05,low-start)
		else:
			box.position[axis]=high
			box.size[axis]=maxf(.05,end-high)
	if box!=original:clipped_panels[group.id]={"original_min":[original.position.x,original.position.y,original.position.z],"original_size":[original.size.x,original.size.y,original.size.z],"new_min":[box.position.x,box.position.y,box.position.z],"new_size":[box.size.x,box.size.y,box.size.z],"method":"concept_layout visual-only reflow and/or 4 portal exclusion; original semantic owners/colliders unchanged"}
	return box


func _collection_print(face:Node3D,width:float,height:float,variant:int)->void:
	var paper:=Color("d7c49e");var ink:=Color("735c42");var border:=Color("a58155")
	soft.box(face,Vector3(width*.94,height*.93,.014),Vector3(0,0,.012),paper)
	for sign_v in [-1.0,1.0]:
		soft.box(face,Vector3(width,.035,.028),Vector3(0,sign_v*(height*.5-.02),.014),border)
		soft.box(face,Vector3(.035,height,.028),Vector3(sign_v*(width*.5-.02),0,.014),border)
	var picture:float=minf(width*.68,height*.72)
	_atlas_plane(face,picture,picture,[0,1,4][variant],Vector3(-width*.12,height*.035,.030))
	for i in range(4):soft.box(face,Vector3(width*.19,.009,.004),Vector3(width*.31,height*(.18-i*.085),.03),ink.lightened(.25))
	var title:=TextMesh.new();title.text=["MAMMOTH","FOSSIL STUDY","ANATOMY"][variant];title.font=ThemeDB.fallback_font;title.font_size=40;title.pixel_size=minf(width*.0016,height*.002);title.depth=.001
	var label:=MeshInstance3D.new();label.mesh=title;label.material_override=soft.material(ink,false);label.position=Vector3(0,-height*.36,.033);face.add_child(label)

func _atlas_plane(parent:Node3D,width:float,height:float,cell:int,at:Vector3)->void:
	# One canonical PNG, six UV cells. SurfaceTool bakes these explicit UVs into
	# ArrayMesh; no triplanar shader/cropping/export-time reconstruction is used.
	if poster_material==null:
		var data=JSON.parse_string(FileAccess.get_file_as_string(POSTER_MANIFEST))
		if not data is Dictionary or data.get("columns")!=3 or data.get("rows")!=2:
			push_error("A01 poster manifest invalid");return
		if FileAccess.get_sha256(data.path)!=data.sha256:
			push_error("A01 poster atlas SHA mismatch");return
		var texture=load(data.path)
		if not texture is Texture2D:push_error("A01 poster atlas requires imported Texture2D");return
		poster_material=StandardMaterial3D.new();poster_material.albedo_texture=texture;poster_material.roughness=.90;poster_material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var u0:float=(cell%3)/3.0+.0015;var u1:float=(cell%3+1)/3.0-.0015
	var v0:float=floorf(float(cell)/3.0)/2.0+.002;var v1:float=(floorf(float(cell)/3.0)+1)/2.0-.002
	var positions:=[Vector3(-width*.5,-height*.5,0),Vector3(-width*.5,height*.5,0),Vector3(width*.5,height*.5,0),Vector3(width*.5,-height*.5,0)]
	var uvs:=[Vector2(u0,v1),Vector2(u0,v0),Vector2(u1,v0),Vector2(u1,v1)]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(4):st.set_normal(Vector3(0,0,1));st.set_uv(uvs[i]);st.add_vertex(positions[i])
	for i in [0,1,2,0,2,3]:st.add_index(i)
	var mesh:=MeshInstance3D.new();mesh.mesh=st.commit();mesh.material_override=poster_material;mesh.position=at;mesh.set_meta("atlas_cell",cell);parent.add_child(mesh)

func _framed_picture(face:Node3D,width:float,height:float,cell:int)->void:
	var gold:=Color("a97e4c")
	soft.box(face,Vector3(width,height,.045),Vector3.ZERO,gold)
	soft.box(face,Vector3(width-.10,height-.10,.012),Vector3(0,0,.030),cream)
	var edge:=minf(width-.20,height-.20)
	_atlas_plane(face,edge,edge,cell,Vector3(0,0,.040))
	for sign_v in [-1.0,1.0]:
		soft.box(face,Vector3(width,.055,.045),Vector3(0,sign_v*(height*.5-.0275),.035),gold)
		soft.box(face,Vector3(.055,height,.045),Vector3(sign_v*(width*.5-.0275),0,.035),gold)

func _craft_shape(root:Node3D,box:AABB,identity:int)->void:
	var colors:Array=[Color("df9657"),Color("d7b85d"),Color("85aaa7"),Color("c98262")]
	var col:Color=colors[identity%4]
	var size:=box.size
	var center:=box.get_center()
	var kind:=identity%4
	if kind==0:
		var body:Node3D=soft.inflated_case(root,size,col,false)
		body.position=center-Vector3(0,size.y*.5,0)
	elif kind==1:
		var mesh:=CylinderMesh.new();mesh.top_radius=.012;mesh.bottom_radius=minf(size.x,size.z)*.49;mesh.height=size.y;mesh.radial_segments=24
		var cone:=MeshInstance3D.new();cone.mesh=mesh;cone.position=center;cone.material_override=soft.material(col);root.add_child(cone)
	elif kind==2:
		for i in range(3):
			var shrink:=1.0-float(i)*.22
			var tier:Node3D=soft.inflated_case(root,Vector3(size.x*shrink,size.y/3.0,size.z*shrink),colors[(identity+i)%4],false)
			tier.position=center+Vector3(0,-size.y*.5+size.y*float(i)/3.0,0)
	else:
		# Six-vertex triangular block fits the original native craft envelope.
		var pts:=PackedVector3Array([Vector3(-.5,-.5,-.5),Vector3(.5,-.5,-.5),Vector3(0,.5,-.5),Vector3(-.5,-.5,.5),Vector3(.5,-.5,.5),Vector3(0,.5,.5)])
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_smooth_group(-1)
		for i in [0,1,2,3,5,4,0,3,4,0,4,1,1,4,5,1,5,2,2,5,3,2,3,0]:st.add_vertex(center+pts[i]*size)
		st.generate_normals()
		var wedge:=MeshInstance3D.new();wedge.mesh=st.commit();wedge.material_override=soft.material(col);root.add_child(wedge)


func _ceramic_plate(root:Node3D,box:AABB,identity:int)->void:
	# One real grabbable plate, still horizontal and inside its native .38 x
	# .06 x .38 envelope. The full curved foot/rim replaces a .036m cylinder.
	# No fake shelf contents, extra bodies, tilted visual or support change.
	var center:=box.get_center();var size:=box.size
	var profile:Array[Vector2]=[Vector2(0,-.5),Vector2(.36,-.5),Vector2(.67,-.37),Vector2(.91,.05),Vector2(1,.36),Vector2(.985,.5),Vector2(.88,.40),Vector2(.66,-.05),Vector2(.30,-.16),Vector2(0,-.16)]
	var vertices:=PackedVector3Array();var indices:=PackedInt32Array();var sides:=48
	for section in profile:
		for j in range(sides):
			var angle:float=TAU*j/sides
			vertices.append(center+Vector3(cos(angle)*size.x*.5*section.x,size.y*section.y,sin(angle)*size.z*.5*section.x))
	for row in range(profile.size()-1):
		for j in range(sides):
			var a:=row*sides+j;var b:=row*sides+(j+1)%sides
			indices.append_array(PackedInt32Array([a,b,a+sides,b,b+sides,a+sides]))
	var body:MeshInstance3D=soft._mesh(root,vertices,indices,cream)
	body.material_override=soft.material(Color("f1e4c8"),false)
	var ink:Color=Color("344d66") if identity%4!=0 else Color("b66b34")
	# Pigment rings are thin geometry following the bowl, not floating tubing.
	for radius in [.89,.94]:
		var points:=PackedVector3Array()
		for j in range(sides):
			var angle:float=TAU*j/sides
			points.append(center+Vector3(cos(angle)*size.x*.5*radius,size.y*_plate_inner_height(radius)+.0008,sin(angle)*size.z*.5*radius))
		var before:int=root.get_child_count()
		soft.tube(root,points,.0018,ink,true)
		for k in range(before,root.get_child_count()):root.get_child(k).material_override=soft.material(ink,false)
	var decoration_vertices:=PackedVector3Array();var decoration_indices:=PackedInt32Array()
	for petal in range(6):
		var axis:float=TAU*petal/6.0
		var middle:=Vector2(cos(axis),sin(axis))*.43
		var start:=decoration_vertices.size()
		var outline:=PackedVector2Array([middle])
		for j in range(12):
			var angle:float=TAU*j/12.0
			var p:Vector2=middle+Vector2(cos(axis),sin(axis))*(cos(angle)*.22)+Vector2(-sin(axis),cos(axis))*(sin(angle)*.075)
			outline.append(p)
		for p in outline:
			decoration_vertices.append(center+Vector3(p.x*size.x*.5,size.y*_plate_inner_height(p.length())+.0012,p.y*size.z*.5))
		for j in range(12):decoration_indices.append_array(PackedInt32Array([start,start+j+1,start+(j+1)%12+1]))
	var motif:MeshInstance3D=soft._mesh(root,decoration_vertices,decoration_indices,ink)
	motif.material_override=soft.material(ink,false)
	root.set_meta("a01_ceramics_visual","native_envelope_curved_plate_with_glazed_pigment")

func _plate_inner_height(radius:float)->float:
	if radius<=.30:return -.16
	if radius<=.66:return lerpf(-.16,-.05,(radius-.30)/.36)
	if radius<=.88:return lerpf(-.05,.40,(radius-.66)/.22)
	return lerpf(.40,.50,clampf((radius-.88)/.105,0.0,1.0))
