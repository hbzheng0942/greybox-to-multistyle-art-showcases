extends "res://../art/train-parkour/shared/tools/scene_rebuild_world.gd"
## Approved B2 composition: asymmetrical receiving workshop and skylit cargo towers.
## Decorations only. All routes, physics, motion and camera remain native authorities.
const FINISH = preload("res://../art/train-parkour/shared/tools/scene_finish_surface.gdshader")
const CARDBOARD_PATH:="res://../art/train-parkour/styles/odd-logistics/materials/cardboard-brush-v1.png"
var cardboard_texture:Texture2D
const SAGGING:="B2-LUX-07-soft_parcel-fat_sagging"
const BUNDLE:="B2-LUX-07-soft_parcel-lopsided_bundle"
const LOADED := "B2-LUX-03-rack_bay-squat_loaded"
var practical_lights: Array = []
var finish_materials: Dictionary = {}
var crate_meshes: Dictionary = {}

func _chamfered_box(size:Vector3) -> ArrayMesh:
	var key:=str(size)
	if crate_meshes.has(key):return crate_meshes[key]
	var h:=size*0.5
	var b:=minf(0.24,minf(size.x,minf(size.y,size.z))*0.045)
	var faces:Array=[]
	for axis in range(3):
		var u:=(axis+1)%3
		var v:=(axis+2)%3
		for sign_value:float in [-1.0,1.0]:
			var face:PackedVector3Array=[]
			for corner:Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var p:=Vector3.ZERO
				p[axis]=sign_value*h[axis]
				p[u]=corner.x*(h[u]-b)
				p[v]=corner.y*(h[v]-b)
				face.append(p)
			faces.append(face)
	for a in range(3):
		for b_axis in range(a+1,3):
			var c:=3-a-b_axis
			for sa:float in [-1.0,1.0]:
				for sb:float in [-1.0,1.0]:
					var face:PackedVector3Array=[]
					for corner:Vector2 in [Vector2(-1,0),Vector2(1,0),Vector2(1,1),Vector2(-1,1)]:
						var p:=Vector3.ZERO
						p[c]=corner.x*(h[c]-b)
						p[a]=sa*(h[a]-corner.y*b)
						p[b_axis]=sb*(h[b_axis]-(1.0-corner.y)*b)
						face.append(p)
					faces.append(face)
	for sx:float in [-1.0,1.0]:
		for sy:float in [-1.0,1.0]:
			for sz:float in [-1.0,1.0]:
				faces.append(PackedVector3Array([Vector3(sx*h.x,sy*(h.y-b),sz*(h.z-b)),Vector3(sx*(h.x-b),sy*h.y,sz*(h.z-b)),Vector3(sx*(h.x-b),sy*(h.y-b),sz*h.z)]))
	var tool:=SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face:PackedVector3Array in faces:
		for j in range(1,face.size()-1):
			var a:Vector3=face[0]
			var c:Vector3=face[j+1]
			var v:Vector3=face[j]
			if (v-a).cross(c-a).dot(a+v+c)<0:
				var temporary:=c
				c=v
				v=temporary
			var normal:Vector3=(v-a).cross(c-a).normalized()
			for p:Vector3 in [a,c,v]:
				tool.set_normal(normal)
				tool.add_vertex(p)
	var mesh:=tool.commit()
	crate_meshes[key]=mesh
	return mesh

func _apply_sample(world:Node3D,config:Dictionary) -> void:
	super._apply_sample(world,config)
	# Existing rail geometry receives a metal response; no rail transforms or collision are edited.
	var steel:=StandardMaterial3D.new()
	steel.albedo_color=Color("8f9790")
	steel.metallic=0.65
	steel.roughness=0.38
	for node:GeometryInstance3D in rebuild_session.lab.find_children("*","GeometryInstance3D",true,false):
		if str(node.name).begins_with("Rail"):node.material_override=steel
		elif str(node.name).begins_with("Bed"):node.material_override=_mat("686354",true,0.12)

func _sample_config_path() -> String:
	return CASE+"styles/odd-logistics/runtime/scene-finish-assembly.json"

func _mat(color: String, floor_surface := false, metal := 0.1) -> Material:
	var key := color+str(floor_surface)+str(metal)
	if finish_materials.has(key): return finish_materials[key]
	if cardboard_texture==null:
		var image:=Image.load_from_file(ProjectSettings.globalize_path(CARDBOARD_PATH))
		image.generate_mipmaps()
		cardboard_texture=ImageTexture.create_from_image(image)
	var material := ShaderMaterial.new()
	material.shader = FINISH
	material.set_shader_parameter("base_color",Color(color))
	material.set_shader_parameter("floor_surface",floor_surface)
	material.set_shader_parameter("metalness",metal)
	material.set_shader_parameter("cardboard_tex",cardboard_texture)
	material.set_shader_parameter("textured_cardboard",color in ["a68a51","b99c60","8e7548","b49b6a","927c4d"])
	material.set_shader_parameter("safety_stripes",color=="b49a45")
	finish_materials[key]=material
	return material

func _solid(size: Vector3, pose: Transform3D, color: String, space: String, role: String, floor_surface := false) -> Node3D:
	# Continuous solid members, including tall columns, must clear every frozen branch.
	if role not in ["receiving_floor","rail_edge","sleeper","fastener","well_floor"]:
		if not _route_clear(AABB(-size*0.5,size),pose,7.0):
			rejected_parts.append({"role":role,"space":space,"position":array(pose.origin),"reason":"Frozen route clearance; complete solid rejected"})
			return null
	return super._solid(size,pose,color,space,role,floor_surface)

func _model(asset:String,pose:Transform3D,scale_value:float,space:String,role:String,clearance:=true) -> Node3D:
	var node:=super._model(asset,pose,scale_value,space,role,clearance)
	if node==null:return null
	var end:=200.0 if asset in [SAGGING,BUNDLE] else (380.0 if asset==LOADED else 520.0)
	for mesh:GeometryInstance3D in node.find_children("*","GeometryInstance3D",true,false):
		mesh.visibility_range_end=end
		mesh.visibility_range_end_margin=45.0
		mesh.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return node

func _beam(a: Vector3,b: Vector3,thickness: float,color: String,space: String,role: String) -> void:
	var length := a.distance_to(b)
	var basis := Basis.looking_at((b-a).normalized(),Vector3.FORWARD if absf((b-a).normalized().dot(Vector3.UP))>0.98 else Vector3.UP)
	_solid(Vector3(thickness,thickness,length),Transform3D(basis,(a+b)*0.5),color,space,role)

func _crate(pose: Transform3D,size: Vector3,variant: int,space: String) -> void:
	if space=="N02" and posmod(variant,7)==4:
		_soft_group(pose,size,variant,space)
		return
	var colors := ["a68a51","b99c60","8e7548","b49b6a","927c4d"]
	var body := _solid(size,_at(pose,Vector3(0,size.y*0.5,0)),colors[posmod(variant,colors.size())],space,"paper_freight")
	if body==null: return
	(body as MeshInstance3D).mesh=_chamfered_box(size)
	# Broad packing bands and a label provide visible construction at gameplay distance.
	for x: float in [-0.24,0.24]:
		_solid(Vector3(size.x*0.035,size.y+0.04,size.z+0.05),_at(pose,Vector3(x*size.x,size.y*0.5,0)),"4d4c40",space,"cargo_band")
	if posmod(variant,3)==0:_solid(Vector3(size.x*0.22,size.y*0.18,0.045),_at(pose,Vector3(size.x*0.20,size.y*0.61,-size.z*0.5-0.04)),"c2b791",space,"cargo_label")

func _soft_group(pose:Transform3D,size:Vector3,variant:int,space:String) -> void:
	var box:AABB=source_boxes.get(SAGGING,AABB())
	if box.size.x<=0:return
	var scale_value:=minf(size.x/box.size.x,minf((size.z+1.8)/box.size.z,size.y/box.size.y))
	var p:=pose.rotated_local(Vector3.UP,0.08 if posmod(variant,2)==0 else -0.09)
	_model(SAGGING,p,scale_value,space,"cloth_wrapped_freight")
	if size.x>7.0:
		var small:=minf(2.7,size.y*0.48)
		_model(BUNDLE,_at(pose,Vector3(size.x*0.30,0,-0.45)),small,space,"knotted_parcel")

func _tarp(pose:Transform3D,size:Vector3,variant:int,space:String) -> void:
	_soft_group(pose,size,variant,space)

func _worklight(pose: Transform3D,space: String,variant: int,wall := false) -> void:
	var housing := _solid(Vector3(4.8,0.6,1.8),pose,"3d4238",space,"worklight_case")
	if housing==null:return
	var face := _solid(Vector3(4.15,0.12,1.35),_at(pose,Vector3(0,-0.35,0)),"d3bd81",space,"worklight_face") as MeshInstance3D
	if face!=null:
		var glow:=StandardMaterial3D.new()
		glow.albedo_color=Color("ffe7ad")
		glow.emission_enabled=true
		glow.emission=Color("ffe3a4")
		glow.emission_energy_multiplier=1.8
		face.material_override=glow
	practical_lights.append({"pose":pose,"space":space,"variant":variant,"wall":wall})

func _column(pose: Transform3D,height: float,space: String) -> void:
	var size:=Vector3(3.4,height,3.8)
	if not _route_clear(AABB(Vector3(-1.7,0,-1.9),size),pose,9.0):return
	_solid(size,_at(pose,Vector3(0,height*0.5,0)),"85816a",space,"concrete_pier")
	_solid(Vector3(3.62,5.5,4.0),_at(pose,Vector3(0,2.75,0)),"b49a45",space,"safety_boot")
	_solid(Vector3(4.6,0.65,4.8),_at(pose,Vector3(0,0.33,0)),"57594b",space,"pier_foot")
	_solid(Vector3(3.65,0.45,4.05),_at(pose,Vector3(0,5.65,0)),"383e35",space,"pier_collar")

func _build_station(track_id: String) -> void:
	var length: float=rebuild_route.tracks[track_id].length
	var bay:=34.0
	for i in range(ceili(length/bay)):
		var s:=minf(i*bay+bay*0.5,length-0.5)
		var pose:=_pose(track_id,s)
		var horizontal:=Transform3D(_flat(pose),pose.origin)
		var deck:=_unbanked(pose)
		var span:=minf(bay,length-i*bay)+1.2
		for side: float in [-1.0,1.0]:
			_solid(Vector3(42,1.2,span),_at(deck,Vector3(side*29,-1.1,0)),"74705b","N01","receiving_floor",true)
			_solid(Vector3(0.75,0.85,span),_at(deck,Vector3(side*8.3,-0.65,0)),"5c5d4b","N01","rail_edge")
			_column(_at(horizontal,Vector3(side*18.5,-0.4,0)),34.0,"N01")
		_solid(Vector3(106,1.1,span+3),_at(horizontal,Vector3(0,34.6,0)),"3b3c31","N01","warehouse_roof")
		_solid(Vector3(41,2.8,2.2),_at(horizontal,Vector3(0,32.8,0)),"4b5144","N01","portal_header")
		for side:float in [-1.0,1.0]:
			_solid(Vector3(2.0,36.0,span+3),_at(horizontal,Vector3(side*52,17,0)),"565b4b","N01","outer_enclosure")
		# Left side: receiving docks and an overhead loaded conveyor, at a different scale from shelving.
		var left_face:=Basis.looking_at(horizontal.basis.x,Vector3.UP)
		var dock:=_at(horizontal,Vector3(-31,0,0))
		_model(RECEIVING,Transform3D(left_face,dock.origin),1.15,"N01","receiving_bay")
		_solid(Vector3(9,1.2,span+1),_at(horizontal,Vector3(-23,13.2,0)),"303930","N01","conveyor_spine")
		for x: float in [-27.1,-18.9]:
			_solid(Vector3(0.45,1.2,span+1),_at(horizontal,Vector3(x,14.0,0)),"777965","N01","conveyor_edge")
		for z in range(-14,16,4):
			_solid(Vector3(7.6,0.25,1.3),_at(horizontal,Vector3(-23,13.95,float(z))),"646554","N01","conveyor_roller")
		for z: float in [-10.0,8.0]:
			if posmod(i,4)!=2:_crate(_at(horizontal,Vector3(-23,14.1,z)),Vector3(5.3,4.3+float(posmod(i,3))*0.7,5.4),i,"N01")
		if posmod(i,3)==0:
			_tarp(_at(horizontal,Vector3(-16,0,8)),Vector3(5.0,4.2,6),i,"N01")
		elif posmod(i,3)==1:
			_model(CART,_at(horizontal,Vector3(-16,0,-8)),1.2,"N01","parked_cage_cart")
		# Right side: carton racks in staggered two-tier groups, with a recessed enclosure behind.
		var right_face:=Basis.looking_at(-horizontal.basis.x,Vector3.UP)
		var rack_at:=_at(horizontal,Vector3(29,0,0))
		_model(LOADED,Transform3D(right_face,rack_at.origin),1.35,"N01","carton_rack_lower")
		if posmod(i,4)!=1:_model(LOADED,Transform3D(right_face,rack_at.origin+Vector3.UP*13.95),1.35,"N01","carton_rack_upper")
		if posmod(i,2)==0:
			var p:=_at(horizontal,Vector3(47,0,0))
			_model(WAREHOUSE,Transform3D(right_face,p.origin),1.3,"N01","recessed_warehouse")
		if posmod(i,3)!=1:
			_crate(_at(horizontal,Vector3(12.5,0,-7)),Vector3(4.2,3.2,4.6),i+1,"N01")
		# Practical work pools alternate sides instead of flattening the whole hall.
		var lx:float=-5.0 if posmod(i,2)==0 else 10.0
		_worklight(_at(horizontal,Vector3(lx,26,0)),"N01",i)
		_solid(Vector3(0.18,7.0,0.18),_at(horizontal,Vector3(lx,29.7,0)),"41463a","N01","fixture_drop")
		for side: float in [-1.0,1.0]:
			for j in range(4):
				_solid(Vector3(6.2,0.03,0.8),_at(deck,Vector3(side*13.2,-0.48,float(j)*2.3-4)),"a58f43","N01","loading_zone_stripe")

func _remove_superseded_environment(world:Node3D) -> void:
	super._remove_superseded_environment(world)
	# The refined hall now reaches the canyon exit; remove the old downstream scaffolding as well.
	var ids:Dictionary={}
	for item:Dictionary in world.get_meta("proxy_geometry_before_calibration",{}).get("items",[]):
		if item.get("space_id","")!="N02" or item.get("category","") not in ["background_mass","roof","bank"]:continue
		ids[str(item.id).split("/")[0].split(":mesh:")[0]]=true
	for node:Node3D in world.get_children():
		var ident:=str(node.get_meta("instance_id",""))
		if ids.has(ident):
			node.visible=false
			if not ident in replaced_ids:replaced_ids.append(ident)

func _build_canyon() -> void:
	var track_id:="canyon_safe"
	for i in range(25):
		var pose:=_pose(track_id,i*34.0)
		var horizontal:=Transform3D(_flat(pose),pose.origin)
		for side: float in [-1.0,1.0]:
			var offset:=side*(33.0+float(posmod(i+(1 if side<0 else 0),3))*6.0)
			var face:=Basis.looking_at(-horizontal.basis.x*side,Vector3.UP)
			var floor_y:=16.0
			var levels:=10+posmod(i,3)
			var height:=float(levels)*11.4
			var base:=horizontal.origin+horizontal.basis.x*offset
			base.y=floor_y
			var stack_box:=AABB(Vector3(-11,0,-5.7),Vector3(22,height,11.4))
			for attempt in range(12):
				if _route_clear(stack_box,Transform3D(face,base),11.0):break
				offset+=side*12.0
				base=horizontal.origin+horizontal.basis.x*offset
				base.y=floor_y
			# Continuous masonry piers frame a filled tower, rather than repeating rack feet as its silhouette.
			var tower:=Transform3D(face,base)
			for x:float in [-11.4,11.4]:
				_column(_at(tower,Vector3(x,0,-0.6)),height+0.8,"N02")
			_solid(Vector3(24,1.2,13),_at(tower,Vector3(0,-0.6,0)),"4e5245","N02","tower_foundation")
			_solid(Vector3(22,height,1.3),_at(tower,Vector3(0,height*0.5,5.6)),"464a3b","N02","dark_rack_back")
			for level in range(levels):
				var tier:=_at(tower,Vector3(0,float(level)*11.4,0))
				_model(LOADED,tier,1.0,"N02","loaded_carton_tier")
				_solid(Vector3(22.5,0.8,0.9),_at(tier,Vector3(0,0,-5.0)),"92523c","N02","tower_shelf_header")
				# A front loading shelf carries large freight; back racks provide depth and irregular small cartons.
				if posmod(level+i,5)!=2:
					_solid(Vector3(19.8,0.6,4.8),_at(tier,Vector3(0,0.25,-6.4)),"6d6b51","N02","front_loading_shelf")
					for x:float in [-5.0,5.0]:
						var cargo:=_at(tier,Vector3(x,0.55,-6.4))
						var size:=Vector3(8.8,6.5+float(posmod(level+i+int(x),3))*0.8,4.6)
						var variant:=i+level+int(x)
						if posmod(variant,4)==0:_tarp(cargo,size,variant,"N02")
						elif posmod(variant,4)==1:
							_crate(_at(cargo,Vector3(-2.1,0,0)),Vector3(4.0,4.1,4.4),variant,"N02")
							_crate(_at(cargo,Vector3(2.1,0,0)),Vector3(3.9,6.8,4.4),variant+1,"N02")
							_crate(_at(cargo,Vector3(-2.1,4.1,0)),Vector3(3.6,2.7,4.1),variant+2,"N02")
						else:_crate(cargo,size,variant,"N02")
			# A boxy upper freight silhouette breaks the common top line.
			_solid(Vector3(22.5,1.0,12),_at(tower,Vector3(0,height-0.5,0)),"696650","N02","top_freight_deck")
			_crate(_at(tower,Vector3(0,height,0)),Vector3(12.0,6.0+float(posmod(i,3))*2,9.0),i,"N02")
			if posmod(i,2)==0:
				var lamp:=_at(tower,Vector3(0,78+float(posmod(i,3))*11,-7))
				_solid(Vector3(1.2,2.5,8),_at(lamp,Vector3(0,1.0,3.0)),"4b5142","N02","lamp_cantilever")
				_worklight(lamp,"N02",i+int(side)*3,true)
				_solid(Vector3(18,1,6),_at(tower,Vector3(0,73,-7)),"555949","N02","maintenance_balcony")
				for x:float in [-8.5,8.5]:
					_solid(Vector3(0.28,2.6,6),_at(tower,Vector3(x,74.7,-7)),"a98f43","N02","balcony_guard")
		# Dark roof blades alternate with broad blue skylight slots. Sunlight has an actual opening.
		var roof:=Transform3D(horizontal.basis,Vector3(horizontal.origin.x,166,horizontal.origin.z))
		_solid(Vector3(238,2.4,2.5),roof,"434d43","N02","roof_crossbeam")
		_solid(Vector3(240,0.7,11.5),_at(roof,Vector3(0,2.0,10)),"3d493f","N02","skylight_roof_blade")
		for side:float in [-1.0,1.0]:
			var column:=_at(roof,Vector3(side*115,-75,0))
			var column_size:=Vector3(2.8,150,3.0)
			for attempt in range(14):
				if _route_clear(AABB(-column_size*0.5,column_size),column,12):break
				column.origin+=horizontal.basis.x*side*12
			_solid(column_size,column,"616958","N02","skylight_support")
			var wall:=_at(roof,Vector3(side*120,-75,16))
			_solid(Vector3(2.0,150,35.5),wall,"4a584b","N02","hall_enclosure")
	for i in range(16):
		var floor_pose:=_pose(track_id,i*55.0+25)
		floor_pose.origin.y=14.0
		floor_pose.basis=_flat(floor_pose)
		_solid(Vector3(180,2,57),floor_pose,"343d35","N02","well_floor",true)

	_distant_warehouse()

func _distant_warehouse() -> void:
	# Continue the visible warehouse skyline beyond the first detailed flight segment.
	# Whole volumes are checked against every route; no painted wall fills a flight gap.
	var pose:=_pose("canyon_safe",810)
	var flat:=_flat(pose)
	for i in range(5):
		var size:=Vector3(38+float(posmod(i,3))*9,132+float(posmod(i+1,3))*16,32)
		var center:=pose.origin-flat.z*(155+float(i)*48)+flat.x*(-80+float(i)*33)
		center.y=14+size.y*0.5
		var at:=Transform3D(flat,center)
		var clear:=false
		for attempt in range(12):
			if _route_clear(AABB(-size*0.5,size),at,16):
				clear=true
				break
			at.origin-=flat.z*35
		if not clear:continue
		_solid(size,at,"777760","N02","distant_storage_mass")
		for y in range(12,int(size.y),14):
			_solid(Vector3(size.x+0.4,0.9,0.5),_at(at,Vector3(0,float(y)-size.y*0.5,-size.z*0.5-0.1)),"655849","N02","distant_shelf_band")
		for x in range(-12,13,12):
			_solid(Vector3(1.8,size.y+0.8,1.8),_at(at,Vector3(float(x),0,-size.z*0.5-0.4)),"555e50","N02","distant_frame")

func _apply_sample_lighting(session: Node3D,world: Node3D) -> void:
	for node: WorldEnvironment in session.find_children("*","WorldEnvironment",true,false):
		var env:=node.environment.duplicate() as Environment
		node.environment=env
		var material:=ProceduralSkyMaterial.new()
		material.sky_top_color=Color("7396b1")
		material.sky_horizon_color=Color("bdd9e8")
		material.ground_bottom_color=Color("29382e")
		material.ground_horizon_color=Color("bdcec9")
		var sky:=Sky.new()
		sky.sky_material=material
		env.sky=sky
		env.background_mode=Environment.BG_SKY
		env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color=Color("b9cbce")
		env.ambient_light_energy=0.23
		env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure=1.15
		env.fog_enabled=true
		env.fog_light_color=Color("a1b6ba")
		env.fog_light_energy=0.5
		env.fog_density=0.00045
		env.fog_sky_affect=0.0
		env.volumetric_fog_enabled=true
		env.volumetric_fog_density=0.0012
		env.volumetric_fog_albedo=Color("b6bec0")
		env.volumetric_fog_length=450
		env.volumetric_fog_ambient_inject=0.15
		env.volumetric_fog_sky_affect=0.0
		env.volumetric_fog_anisotropy=0.45
		env.ssao_enabled=true
		env.ssao_intensity=2.2
		env.ssao_radius=2.8
		env.ssil_enabled=true
		env.ssil_intensity=0.45
		env.glow_enabled=true
		env.glow_intensity=0.25
	for sun: DirectionalLight3D in session.find_children("*","DirectionalLight3D",true,false):
		sun.light_color=Color("d9e9ef")
		sun.light_energy=1.65
		sun.rotation_degrees=Vector3(-55,-23,0)
		sun.shadow_enabled=true
		sun.directional_shadow_max_distance=280
		sun.light_volumetric_fog_energy=0.65
	for record:Dictionary in practical_lights:
		var pose:Transform3D=record.pose
		var light:=SpotLight3D.new()
		light.light_color=Color("ffe1a0")
		light.light_energy=27.0 if record.space=="N01" else 38.0
		light.spot_range=44 if record.space=="N01" else 38
		light.spot_angle=60
		light.spot_attenuation=1.0
		light.shadow_enabled=posmod(int(record.variant),6)==0
		light.light_volumetric_fog_energy=0.4
		light.distance_fade_enabled=true
		light.distance_fade_begin=200
		light.distance_fade_length=90
		world.add_child(light)
		light.global_transform=Transform3D(pose.basis*Basis(Vector3.RIGHT,-PI*0.5),pose.origin-Vector3.UP*0.6)
	world.set_meta("concept_finish_render",{"renderer":"Existing Forward+ Metal","mechanisms":["Shadowed native directional light through authored roof slots","Bounded warm spot work pools","SSAO/SSIL contact","Low-density native volumetric atmosphere"],"practical_count":practical_lights.size(),"new_generated_assets":0,"runtime_budget":"Unmeasured; capture is not FPS acceptance"})
