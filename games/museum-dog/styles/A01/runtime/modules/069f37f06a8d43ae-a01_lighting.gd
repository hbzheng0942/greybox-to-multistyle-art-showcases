extends RefCounted
## Visual-only room response and mounted picture lights at existing plaque faces.
func apply(game, mapping:Dictionary, kits)->Dictionary:
	game.get_viewport().positional_shadow_atlas_size=4096
	game.get_viewport().msaa_3d=Viewport.MSAA_4X
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	for child in game.get_children():
		if child is WorldEnvironment:
			child.environment=child.environment.duplicate()
			child.environment.ambient_light_color=Color("d9d4cc")
			child.environment.ambient_light_energy=.28
			child.environment.tonemap_mode=Environment.TONE_MAPPER_ACES
			child.environment.tonemap_exposure=.96
			child.environment.ssao_enabled=true
			child.environment.ssao_radius=.65
			child.environment.ssao_intensity=2.0
			child.environment.ssao_power=1.25
			child.environment.ssao_detail=.6
			child.environment.ssao_light_affect=.55
			child.environment.glow_enabled=true
			child.environment.glow_intensity=.15
			child.environment.glow_hdr_threshold=.88
		if child is DirectionalLight3D:
			child.light_energy=0.0
			# Compatibility still submits the zero-energy sun's shadow cascades.
			# The A01 local keys provide all visible shadows; skip this unused pass.
			child.shadow_enabled=false
	var zones:Dictionary={}
	for light in game.builder.lights:
		var at:Vector3=light.global_position
		var zone="hall"
		var tint=Color(1,.87,.70)
		var energy_scale=.26
		var reach=10.5
		if at.x < -8:
			zone="porcelain";tint=Color(1,.88,.73);energy_scale=.74;reach=6.8
		elif at.x > 8:
			zone="taxidermy";tint=Color(1,.87,.70);energy_scale=.72;reach=6.8
		elif at.z < -6:
			zone="kids";tint=Color(1,.91,.78);energy_scale=.24;reach=7.5
		elif at.z > 7:
			zone="vestibule";tint=Color(1,.88,.73);energy_scale=.68;reach=5.2
		light.light_color=tint
		light.light_energy*=energy_scale
		light.omni_range=reach
		zones[zone]=int(zones.get(zone,0))+1
	for light in game.builder.find_children("*","SpotLight3D",true,false):
		light.light_energy*=.55 if absf(light.global_position.x)>8 else .5
		light.light_color=Color(1,.94,.83)
		light.shadow_normal_bias=1.5
		light.shadow_bias=.1
		if absf(light.global_position.x)<8:light.shadow_enabled=false
	var key:=SpotLight3D.new()
	key.name="A01HallContactKey"
	key.position=Vector3(-1.8,7.4,2.4)
	key.light_color=Color(1,.91,.76)
	key.light_energy=1.25
	key.spot_range=12
	key.spot_angle=68
	key.shadow_enabled=true
	key.shadow_normal_bias=2.5
	key.shadow_bias=.16
	key.shadow_blur=3.0
	key.light_cull_mask=8
	for group in mapping.groups:
		if group.family_id in ["shell_wall","shell_ceiling","hall_column","hall_ceiling_detail","outer_roof_trim","portal_frame","main_backdrop"]:continue
		var artwork:Node3D=game.visual_catalog.entries[group.anchor_id].artwork
		if artwork!=null:_key_layer(artwork)
	_key_layer(game.dog)
	game.add_child(key)
	key.look_at(Vector3(0,0,-1.5),Vector3.UP)
	var gallery:=Node3D.new()
	gallery.name="A01GalleryPictureLights"
	game.add_child(gallery)
	var count:=0
	var gallery_groups:Array=mapping.groups.duplicate()
	gallery_groups.append(kits.ENTRY_PICTURE)
	for group in gallery_groups:
		if group.family_id not in ["hall_wall_print","information_panel","entry_guide_board","fossil_panel","kids_wall_panel"]:continue
		var box:AABB=kits._graphic_box(group)
		var center:=box.get_center()
		var normal:=Vector3(0,0,-1) if center.z>1 else Vector3(0,0,1)
		var yaw:=PI if center.z>1 else 0.0
		if box.size.x<box.size.z:
			normal=Vector3(-1,0,0) if center.x>0 else Vector3(1,0,0)
			yaw=-PI*.5 if center.x>0 else PI*.5
		var fixture:=Node3D.new()
		fixture.name="PictureLight_"+str(count)
		fixture.transform=Transform3D(Basis(Vector3.UP,yaw),center+normal*(minf(box.size.x,box.size.z)*.5+.035))
		gallery.add_child(fixture)
		var y:float=box.size.y*.5+.16
		var metal:=Color("3d3d39")
		kits.soft.box(fixture,Vector3(.12,.16,.035),Vector3(0,y,.01),metal)
		kits.soft.tube(fixture,PackedVector3Array([Vector3(0,y,.02),Vector3(0,y+.06,.16),Vector3(0,y+.04,.34)]),.025,metal)
		var hood:MeshInstance3D=kits.soft.box(fixture,Vector3(.23,.11,.19),Vector3(0,y+.005,.34),metal)
		hood.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lens:MeshInstance3D=kits.soft.box(fixture,Vector3(.17,.009,.13),Vector3(0,y-.054,.34),Color("ffe4aa"))
		var glow:StandardMaterial3D=lens.material_override.duplicate()
		glow.emission_enabled=true;glow.emission=Color(1,.73,.35);glow.emission_energy_multiplier=1.3
		lens.material_override=glow
		lens.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var spot:=SpotLight3D.new()
		spot.name="PlaqueWarmPool"
		spot.position=Vector3(0,y-.06,.38)
		spot.light_color=Color(1,.86,.62)
		spot.light_energy=.42 if group.family_id=="kids_wall_panel" else 1.3
		spot.spot_range=maxf(2.0,box.size.y*1.6)
		spot.spot_angle=58
		spot.spot_attenuation=.6
		spot.shadow_enabled=false
		fixture.add_child(spot)
		spot.look_at(fixture.to_global(Vector3(0,-box.size.y*.08,0)),Vector3.UP)
		count+=1
	# Broad oblique fill reveals pressure folds without self-shadow stripes.
	for spec in [Vector3(-5.8,5.5,4.5),Vector3(5.8,5.5,4.5),Vector3(-13,4.1,3.0),Vector3(13,4.1,3.0),Vector3(0,4.8,-8.0),Vector3(0,3.0,10.0)]:
		var wash:=OmniLight3D.new();wash.name="PressureSurfaceFill"
		wash.position=spec;wash.light_color=Color(1,.92,.80);wash.light_energy=.12 if spec.z < -6 else .30;wash.omni_range=8.5;wash.shadow_enabled=false;game.add_child(wash)
	var ceiling_panels:=Node3D.new();ceiling_panels.name="A01CeilingLightPanels";game.add_child(ceiling_panels)
	for x in [-4.8,4.8]:
		for z in [-2.5,3.4]:
			var pool:=SpotLight3D.new();pool.name="WarmGalleryPool";pool.position=Vector3(x,6.7,z)
			pool.light_color=Color(1,.91,.77);pool.light_energy=1.6;pool.spot_angle=43;pool.spot_attenuation=.65;pool.spot_range=10;pool.shadow_enabled=false
			game.add_child(pool);pool.look_at(Vector3(x*.88,.05,z-.3),Vector3.FORWARD)
			var panel:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(2.4,1.3);panel.mesh=quad;panel.position=Vector3(x,8.43,z);panel.rotation.x=PI*.5;panel.layers=3
			var mat:=StandardMaterial3D.new();mat.albedo_color=Color("fff1d3");mat.emission_enabled=true;mat.emission=Color("ffe2b0");mat.emission_energy_multiplier=2.5;panel.material_override=mat;panel.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;ceiling_panels.add_child(panel)
	# Grazing light is restricted to the shell: reveal pressure curvature without
	# lifting floor/exhibits or multiplying the floor specular pools.
	for group in mapping.groups:
		if group.family_id not in ["shell_wall","hall_column","portal_frame","main_backdrop"]:continue
		var shell:Node3D=game.visual_catalog.entries[group.anchor_id].artwork
		if shell!=null:_shell_light_layer(shell)
	for spec in [
		[Vector3(-4.0,6.2,3.8),Vector3(-7.8,3.4,-1.0)],
		[Vector3(4.0,6.2,3.8),Vector3(7.8,3.4,-1.0)],
		[Vector3(4.5,6.2,-1.0),Vector3(-1.5,3.5,-5.8)]]:
		var rake:=SpotLight3D.new();rake.name="A01ShellRakingLight"
		rake.position=spec[0];rake.light_color=Color(1,.94,.85);rake.light_energy=.9
		rake.spot_angle=64;rake.spot_attenuation=.5;rake.spot_range=14
		rake.shadow_enabled=false;rake.light_cull_mask=16
		game.add_child(rake);rake.look_at(spec[1],Vector3.UP)
	# Children gallery previously had only weak, unshadowed omnidirectional fill.
	# The local key establishes object modelling and real tabletop/foot shadows.
	for group in mapping.groups:
		var art:Node3D=game.visual_catalog.entries[group.anchor_id].artwork
		if art!=null and (group.region=="kids" or str(group.family_id).begins_with("prop_") or str(group.family_id).begins_with("visitor_") or str(group.family_id).begins_with("mammoth_")):_kids_light_layer(art)
	_kids_light_layer(game.dog)
	if game.has_node("A01RoomStructure"):_kids_light_layer(game.get_node("A01RoomStructure"))
	var kids_key:=SpotLight3D.new();kids_key.name="A01KidsWarmKey"
	kids_key.position=Vector3(-1.3,5.0,-10.0);kids_key.light_color=Color(1,.90,.75);kids_key.light_energy=.50
	kids_key.spot_range=9.0;kids_key.spot_angle=58;kids_key.spot_attenuation=.45
	kids_key.shadow_enabled=true;kids_key.shadow_normal_bias=1.5;kids_key.shadow_bias=.12;kids_key.shadow_blur=5.0;kids_key.shadow_opacity=.62;kids_key.light_cull_mask=32
	game.add_child(kids_key);kids_key.look_at(Vector3(.3,.4,-11.7),Vector3.UP)
	var bounce:=OmniLight3D.new();bounce.name="A01KidsFrontBounce"
	bounce.position=Vector3(1.6,2.8,-8.0);bounce.light_color=Color(1,.94,.84);bounce.light_energy=.18;bounce.omni_range=7.0;bounce.light_cull_mask=32;game.add_child(bounce)
	# Native 4.7 area response gives cloth a broad highlight. Compatibility
	# does not cast area-light shadows; the separate spot above retains them.
	var softbox:=AreaLight3D.new();softbox.name="A01KidsBroadClothLight"
	softbox.position=Vector3(-.7,4.55,-10.5);softbox.area_size=Vector2(3.4,2.4)
	softbox.area_range=9.0;softbox.area_attenuation=1.0;softbox.area_normalize_energy=true
	softbox.light_color=Color(1,.91,.78);softbox.light_energy=.45;softbox.light_specular=.35;softbox.light_cull_mask=32
	softbox.shadow_enabled=false;game.add_child(softbox);softbox.look_at(Vector3(.1,.6,-11.8),Vector3.UP)
	var probes:=_room_reflections(game,mapping)
	return {"id":"a01-warm-cloth-light-v8","ambient_energy":.28,"ssao_enabled":true,"ssao_radius":.65,"ssao_intensity":2.0,"reflection_probes":probes,"tone_mapper":"ACES","glow_intensity":.15,"existing_fixture_counts":zones,"new_gallery_lights":count,"shell_raking_lights":3,"ceiling_light_panels":4,"additional_shadow_lights":2,"kids_key":true,"kids_key_energy":.50,"kids_area_light":{"energy":.45,"specular":.35,"size":[3.4,2.4],"shadows":false},"renderer_limits":"Compatibility area lights illuminate but do not cast area shadows; separate spot casts shadows","msaa_3d":4,"native_visual_review":"pending","collision_changes":0}

func _room_reflections(game,mapping:Dictionary)->int:
	# Capture only static architecture/furniture: no stale dog/visitor/loose-prop
	# reflections when an exhibit moves. Five small boxes, at most two per mesh.
	for path in ["A01RoomStructure","A01GalleryPictureLights","A01PorcelainDisplay"]:
		if game.has_node(path):_probe_layer(game.get_node(path))
	for group in mapping.groups:
		if group.family_id=="shell_floor":
			var floor_root:Node3D=game.visual_catalog.entries[group.anchor_id].artwork
			if floor_root!=null:_probe_receiver(floor_root)
		if group.source_route!="authored" or str(group.family_id).begins_with("prop_") or group.family_id=="shell_floor":continue
		var root:Node3D=game.visual_catalog.entries[group.anchor_id].artwork
		if root!=null:_probe_layer(root)
	for room in [
		{"id":"Hall","center":Vector3(0,4.15,1),"size":Vector3(15.8,8.3,13.8)},
		{"id":"Porcelain","center":Vector3(-13,2.5,1),"size":Vector3(9.8,5.0,9.8)},
		{"id":"Taxidermy","center":Vector3(13,2.65,1),"size":Vector3(9.8,5.3,9.8)},
		{"id":"Kids","center":Vector3(0,2.9,-10.5),"size":Vector3(7.8,5.8,8.8)},
		{"id":"Vestibule","center":Vector3(0,1.8,9.7),"size":Vector3(5.8,3.6,3.2)}]:
		var probe:=ReflectionProbe.new()
		probe.name="A01StaticReflection"+str(room.id)
		probe.position=room.center
		probe.size=room.size
		probe.origin_offset=Vector3(0,-room.size.y*.28,0)
		probe.box_projection=true
		probe.interior=true
		probe.intensity=.8
		probe.ambient_mode=ReflectionProbe.AMBIENT_DISABLED
		probe.cull_mask=2
		probe.reflection_mask=4
		probe.max_distance=24
		probe.blend_distance=.25
		probe.update_mode=ReflectionProbe.UPDATE_ONCE
		probe.enable_shadows=false
		game.add_child(probe)
	return 5

func _probe_layer(node:Node)->void:
	if node is MeshInstance3D:node.layers|=2
	for child in node.get_children():_probe_layer(child)

func _probe_receiver(node:Node)->void:
	if node is MeshInstance3D:node.layers|=4
	for child in node.get_children():_probe_receiver(child)

func _key_layer(node:Node)->void:
	if node is MeshInstance3D:node.layers|=8
	for child in node.get_children():_key_layer(child)

func _shell_light_layer(node:Node)->void:
	if node is MeshInstance3D:node.layers|=16
	for child in node.get_children():_shell_light_layer(child)

func _kids_light_layer(node:Node)->void:
	if node is MeshInstance3D:node.layers|=32
	for child in node.get_children():_kids_light_layer(child)
