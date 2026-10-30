extends RefCounted
## Stable world-space studio daylight. No camera-following light or exposure pumping.
static func apply(lab: Node3D) -> void:
	# Accumulate soft-shadow/specular sampling in the isolated art entry.
	# MSAA alone cannot resolve the PCSS and glossy-water grain.
	lab.get_viewport().use_taa=true
	lab.get_viewport().msaa_3d=Viewport.MSAA_2X
	var world: Node3D=lab.get_node("EnvironmentRoot")
	var env: Environment=world.get_node("WorldEnvironment").environment
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution=.38
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_color=Color("e4d8cb")
	env.ambient_light_energy=.42
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	env.tonemap_exposure=.94
	env.tonemap_white=4.0
	env.adjustment_enabled=false
	env.ssao_enabled=true;env.ssao_intensity=1.65;env.ssao_radius=3.5;env.ssao_detail=1.2
	env.ssao_light_affect=.30
	env.ssil_enabled=true;env.ssil_radius=9.0;env.ssil_intensity=.65
	env.fog_density=.000055;env.fog_light_color=Color("9acade")
	env.fog_sky_affect=.025
	var sky:=ShaderMaterial.new();sky.shader=preload("res://materials/clay-polish/clay_sky.gdshader")
	env.sky.sky_material=sky
	var sun: DirectionalLight3D=world.get_node("Sun")
	sun.rotation_degrees=Vector3(-48,-42,0)
	sun.light_energy=1.38;sun.light_color=Color("fff6ea")
	sun.light_angular_distance=3.0;sun.light_specular=1.0
	sun.directional_shadow_max_distance=350
	sun.directional_shadow_blend_splits=true
	# Low-energy broad fill stands in for sky/ground bounce. Only key casts shadows.
	fill(world,"SkyBounce",Vector3(-22,64,0),Color("c4e0f3"),.09)
	fill(world,"TerracottaBounce",Vector3(24,-24,0),Color("ffd5b2"),.075)
	for node in lab.find_children("*","OmniLight3D",true,false):
		node.light_color=Color("ffe4be")
		node.light_energy*=1.08
		node.light_specular=.45
	# Existing canopy globes emitted visually but contributed no local illumination.
	for track_id in ["station_start","victory_run"]:
		var track: SpatialTrack=lab.route.tracks[track_id]
		for index in ceili(track.length/56.0):
			var s:=22.0+index*56.0
			if s>track.length:continue
			for side in [-1,1]:
				var lamp:=OmniLight3D.new();lamp.name="CanopyBounce"
				world.add_child(lamp);lamp.global_position=track.pose(s)*Vector3(side*15.35,13.8,0)
				lamp.light_color=Color("ffe2bd");lamp.light_energy=2.1;lamp.light_specular=.3
				lamp.omni_range=23;lamp.omni_attenuation=1.3;lamp.shadow_enabled=false
				lamp.distance_fade_enabled=true;lamp.distance_fade_begin=100;lamp.distance_fade_length=50
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)

static func fill(parent: Node3D,label: String,rotation: Vector3,color: Color,energy: float) -> void:
	var light:=DirectionalLight3D.new();light.name=label
	parent.add_child(light);light.rotation_degrees=rotation
	light.light_color=color;light.light_energy=energy;light.light_specular=0
	light.shadow_enabled=false;light.sky_mode=DirectionalLight3D.SKY_MODE_LIGHT_ONLY
