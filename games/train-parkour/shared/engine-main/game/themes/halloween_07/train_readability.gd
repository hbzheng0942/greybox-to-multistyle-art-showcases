extends RefCounted
## T2 surface treatment and lamps; canonical mesh, textures and fit remain shared.
const SURFACE = preload("res://themes/halloween_07/train_surface.gdshader")

func apply(train: Node3D, size: Vector3) -> void:
	var surfaces := 0
	for node: Node in train.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for index in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(index) as ShaderMaterial
			if original == null: continue
			var material := ShaderMaterial.new()
			material.shader = SURFACE
			for key in ["albedo_texture", "metallic_roughness", "albedo_factor", "metallic_factor", "roughness_factor"]:
				material.set_shader_parameter(key, original.get_shader_parameter(key))
			material.set_shader_parameter("mesh_to_train", train.global_transform.affine_inverse() * mesh.global_transform)
			material.set_shader_parameter("train_size", size)
			mesh.set_surface_override_material(index, material)
			surfaces += 1
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = Color("fff1c6")
	lamp_material.emission_enabled = true
	lamp_material.emission = Color("ffd277")
	lamp_material.emission_energy_multiplier = 5.0
	lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Inset warm lenses inside the existing round buffer, at both visible ends.
	for direction: float in [-1.0, 1.0]:
		var lens := MeshInstance3D.new()
		lens.name = "GhostBufferLensFront" if direction < 0 else "GhostBufferLensRear"
		var disc := CylinderMesh.new()
		disc.top_radius = 0.145; disc.bottom_radius = 0.145; disc.height = 0.018
		disc.radial_segments = 24; disc.rings = 1
		lens.mesh = disc; lens.material_override = lamp_material
		lens.rotation_degrees.x = 90
		# The +X source end is a solid disc; its lens cap must clear that surface too.
		lens.position = Vector3(0.0095, size.y * 0.177, direction * (size.z * 0.5 + 0.003))
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		train.add_child(lens)
		var light := SpotLight3D.new()
		light.name = "GhostBufferLightFront" if direction < 0 else "GhostBufferLightRear"
		light.position = lens.position + Vector3(0, 0, direction * 0.035)
		# Yaw reverses Z, not Y: both ends pitch down in the train's local frame.
		light.rotation_degrees = Vector3(-9, 0 if direction < 0 else 180, 0)
		light.light_color = Color("ffd58c"); light.light_energy = 2.2
		light.spot_range = 32; light.spot_angle = 36; light.spot_attenuation = 1.0
		light.shadow_enabled = false
		train.add_child(light)
	train.set_meta("h07_train_readability", {"textured_surfaces": surfaces, "emissive_lenses": 2, "realtime_lights": 2, "new_shadow_lights": 0, "canonical_geometry_unchanged": true})
