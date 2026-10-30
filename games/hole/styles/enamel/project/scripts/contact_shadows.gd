extends MultiMeshInstance3D
## One batched, soft ambient contact layer for Compatibility. Not SSAO.
## Grounded units only; follows release/sink/restart and both actual hole openings.
const Simulation = preload("res://scripts/simulation.gd")
var material: ShaderMaterial
var cached: Array = []
var strength: float = 0.18
var spread: float = 1.18

func configure(profile: Dictionary, map: Dictionary, count: int) -> void:
	name = "GroundContactShadows"
	strength = float(profile.get("strength", 0.18))
	spread = float(profile.get("spread", 1.18))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/contact_shadow.gdshader")
	material.set_shader_parameter("strength", strength)
	var color: Array = profile.get("color", [0.20, 0.23, 0.36])
	material.set_shader_parameter("shadow_color", Color(color[0], color[1], color[2]))
	# Same frozen land and inlet used by floor.gdshader; no water decals.
	var full: Array = map["floor_size_xz"]
	var half: Array = [float(full[0]) * 0.5, float(full[1]) * 0.5]
	material.set_shader_parameter("land_half_size", Vector2(half[0], half[1]))
	var corner: Array = map["water_cut_corner_xz"]
	material.set_shader_parameter("water_corner", Vector2(corner[0], corner[1]))
	material_override = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	multimesh.mesh = plane
	multimesh.instance_count = count
	cached.resize(count)
	for i in count:
		multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))
	custom_aabb = AABB(Vector3(-26, -1, -22), Vector3(52, 4, 44))

func sync(objects: Array, a: Vector4, b: Vector4, proxies: bool) -> void:
	visible = not proxies
	material.set_shader_parameter("hole_a", a)
	material.set_shader_parameter("hole_b", b)
	for i in objects.size():
		var o: Dictionary = objects[i]
		var p: Vector3 = o.position
		var size: Vector3 = o.size
		var scale_factor: float = float(o.visual_scale)
		var bottom: float = p.y - size.y * 0.5 * scale_factor
		# Supported prizes must not leave footprints beneath their tables.
		# Sink weight falls smoothly, then vanishes with the consumed unit.
		var weight: float = (1.0 - smoothstep(0.03, 0.55, maxf(bottom, 0.0))) * (1.0 - smoothstep(0.0, 0.55, maxf(-bottom, 0.0)))
		if int(o.state) in [Simulation.LOCKED, Simulation.CONSUMED]:
			weight = 0.0
		var radii := Vector2(maxf(size.x * 0.5 * spread, 0.11), maxf(size.z * 0.5 * spread, 0.11)) * scale_factor
		var state: Array = [p.x, p.z, float(o.yaw), radii, weight]
		if cached[i] == state:
			continue
		cached[i] = state
		var basis := Basis(Vector3.UP, float(o.yaw)).scaled_local(Vector3(radii.x, 1, radii.y))
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(p.x, 0.008, p.z)))
		multimesh.set_instance_custom_data(i, Color(weight, 0, 0, 0))
