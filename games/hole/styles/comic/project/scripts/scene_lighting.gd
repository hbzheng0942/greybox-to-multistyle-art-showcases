extends RefCounted
## Theme-independent presentation recipe. Missing fields retain the parent look.
static func apply(scene: Node3D, profile: Dictionary) -> void:
	if profile.is_empty():
		return
	var key: DirectionalLight3D = scene.get_node("KeyLight")
	for field in {"key_energy":"light_energy", "shadow_opacity":"shadow_opacity", "shadow_bias":"shadow_bias", "shadow_normal_bias":"shadow_normal_bias", "shadow_blur":"shadow_blur", "shadow_distance":"directional_shadow_max_distance"}:
		if profile.has(field):
			var property: String = {"key_energy":"light_energy", "shadow_opacity":"shadow_opacity", "shadow_bias":"shadow_bias", "shadow_normal_bias":"shadow_normal_bias", "shadow_blur":"shadow_blur", "shadow_distance":"directional_shadow_max_distance"}[field]
			key.set(property, float(profile[field]))
	if profile.has("key_rotation_degrees"):
		var angle: Array = profile.key_rotation_degrees
		key.rotation_degrees = Vector3(angle[0], angle[1], angle[2])
	if profile.has("key_color"):
		var c: Array = profile.key_color
		key.light_color = Color(c[0], c[1], c[2])
	var world: WorldEnvironment = scene.get_node("WorldEnvironment")
	world.environment = world.environment.duplicate()
	world.environment.ambient_light_energy = float(profile.get("ambient_energy", world.environment.ambient_light_energy))
	if profile.has("ambient_color"):
		var c: Array = profile.ambient_color
		world.environment.ambient_light_color = Color(c[0], c[1], c[2])
