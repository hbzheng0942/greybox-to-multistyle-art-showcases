extends RefCounted
## Black hole presentation: 2D character border around an uncapped 3D aperture.
##
## Contract (01_WORKBUDDY_EXECUTION_PROMPT.md section 8):
##   * the mouth, inner funnel, swirl, face, growth and rival colour are designed here;
##   * the hole is never a flat black disc and never a capped GLB;
##   * character art stays outside the functional opening and cannot cap falling objects;
##   * nothing in this file owns radius, swallow timing or payouts - it only reads signals.

const WELL_SHADER = preload("res://shaders/hole_well.gdshader")
const RIM_SHADER = preload("res://shaders/hole_rim.gdshader")
const IMAGE_SHADER = preload("res://shaders/hole_image.gdshader")
const STAR_IMAGE = preload("res://assets/characters/star-gummy-satin-v3.png")
const SPRITE_SHADER = preload("res://shaders/hole_sprite.gdshader")
const MouthTuning = preload("res://scripts/tuning.gd")

const WELL_DEPTH := 2.55
const MOUTH_RADIUS := 1.0

## Built at unit radius; the caller scales X/Z by the live functional radius and leaves Y alone,
## so the funnel depth stays constant while the opening grows with the hole.
func make(accent: Color, rival: bool = false) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "BlackHoleRival" if rival else "BlackHolePlayer"

	# --- inner funnel: depth falloff and restrained swirl
	var well: MeshInstance3D = MeshInstance3D.new()
	well.name = "FunnelInterior"
	var well_mesh: CylinderMesh = CylinderMesh.new()
	well_mesh.top_radius = MOUTH_RADIUS
	well_mesh.bottom_radius = 0.68
	well_mesh.height = WELL_DEPTH
	well_mesh.radial_segments = 64
	well_mesh.cap_top = false
	well_mesh.cap_bottom = false
	well.mesh = well_mesh
	well.position.y = -WELL_DEPTH * 0.5
	var well_material: ShaderMaterial = ShaderMaterial.new()
	well_material.shader = WELL_SHADER
	well_material.set_shader_parameter("accent", accent)
	well_material.set_shader_parameter("well_depth", WELL_DEPTH)
	well_material.set_shader_parameter("face_angle", PI)
	well_material.set_shader_parameter("growth01", 0.0)
	well_material.set_shader_parameter("bite_pulse", 0.0)
	well_material.set_shader_parameter("alive", 1.0)
	well.material_override = well_material
	root.add_child(well)

	# --- throat: seals the bottom of the funnel so nothing shows through the map
	var throat: MeshInstance3D = MeshInstance3D.new()
	throat.name = "Throat"
	var throat_mesh: CylinderMesh = CylinderMesh.new()
	throat_mesh.top_radius = 0.72
	throat_mesh.bottom_radius = 0.60
	throat_mesh.height = 0.08
	throat_mesh.radial_segments = 48
	throat.mesh = throat_mesh
	throat.position.y = -WELL_DEPTH + 0.01
	var throat_material: StandardMaterial3D = StandardMaterial3D.new()
	throat_material.albedo_color = Color("06090e")
	throat_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	throat.material_override = throat_material
	root.add_child(throat)

	# --- narrow physical lip beneath the 2D border
	var lip: MeshInstance3D = MeshInstance3D.new()
	lip.name = "BeveledMouth"
	var lip_mesh: TorusMesh = TorusMesh.new()
	lip_mesh.inner_radius = MouthTuning.MOUTH_DIAMETER_RATIO
	lip_mesh.outer_radius = 1.08
	lip_mesh.rings = 72
	lip_mesh.ring_segments = 10
	lip.mesh = lip_mesh
	lip.scale = Vector3(1.0, 0.42, 1.0)
	lip.position.y = 0.025
	var lip_material: ShaderMaterial = ShaderMaterial.new()
	lip_material.shader = RIM_SHADER
	lip_material.set_shader_parameter("accent", accent)
	lip_material.set_shader_parameter("growth01", 0.0)
	lip_material.set_shader_parameter("bite_pulse", 0.0)
	lip_material.set_shader_parameter("alive", 1.0)
	lip.material_override = lip_material
	root.add_child(lip)

	# Six lightweight 2D quads carry the identity; no generated 3D character mesh.
	var sprites: Array = []
	for i in range(2):
		sprites.append(_sprite(root, "Eye%d" % i, Vector3(-.39 if i == 0 else .39, .17, -1.18), Vector2(.38,.43), 0))
	for i in range(2):
		sprites.append(_sprite(root, "Cheek%d" % i, Vector3(-1.065 if i == 0 else 1.065, .05, -.34), Vector2(.19,.14), 1))
	sprites.append(_sprite(root, "Badge", Vector3(.74,.065,-.80), Vector2(.21,.21), 2))
	sprites.append(_sprite(root, "Horn", Vector3(-.93,.11,-.84), Vector2(.25,.32), 3))
	var image_ring := MeshInstance3D.new()
	image_ring.name = "IllustratedStarRim"
	var ring_quad := QuadMesh.new()
	ring_quad.size = Vector2(2.60,2.60)
	image_ring.mesh = ring_quad
	image_ring.rotation.x = -PI/2
	image_ring.position.y = .056
	image_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var image_material := ShaderMaterial.new()
	image_material.shader = IMAGE_SHADER
	image_material.set_shader_parameter("sprite_texture", STAR_IMAGE)
	image_material.set_shader_parameter("mouth_ratio",MouthTuning.MOUTH_DIAMETER_RATIO)
	image_ring.material_override = image_material
	root.add_child(image_ring)
	var image_eyes := _sprite(root,"IllustratedEyes",Vector3(0,.13,-1.12),Vector2(.64,.35),0)
	var eye_material := ShaderMaterial.new()
	eye_material.shader = IMAGE_SHADER
	eye_material.set_shader_parameter("sprite_texture",STAR_IMAGE)
	eye_material.set_shader_parameter("face",true)
	image_eyes.material_override = eye_material
	root.set_meta("image_eyes",image_eyes)
	root.set_meta("image_ring",image_ring)
	root.set_meta("face_sprites", sprites)
	root.set_meta("hole_materials", [well_material, lip_material])
	root.set_meta("status", "PROCEDURAL_FUNCTIONAL_OPENING")
	return root

## Per-frame presentation update. Reads live signals; writes nothing back to the simulation.
func update(view: Node3D, accent: Color, growth01: float, bite_pulse: float,
		face_angle: float, alive: bool) -> void:
	var mats: Array = view.get_meta("hole_materials", [])
	if mats.size() < 2:
		return
	var well: ShaderMaterial = mats[0]
	var lip: ShaderMaterial = mats[1]
	well.set_shader_parameter("accent", accent)
	well.set_shader_parameter("growth01", growth01)
	well.set_shader_parameter("bite_pulse", bite_pulse)
	well.set_shader_parameter("face_angle", face_angle)
	well.set_shader_parameter("alive", 1.0 if alive else 0.0)
	lip.set_shader_parameter("accent", accent)
	lip.set_shader_parameter("growth01", growth01)
	lip.set_shader_parameter("bite_pulse", bite_pulse)
	lip.set_shader_parameter("alive", 1.0 if alive else 0.0)

func _sprite(parent: Node3D, name: String, position: Vector3, size: Vector2, feature: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	var quad := QuadMesh.new()
	quad.size = size
	node.mesh = quad
	node.position = position
	node.rotation.x = -deg_to_rad(52.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SPRITE_SHADER
	material.set_shader_parameter("feature", feature)
	node.material_override = material
	node.set_meta("base_position", position)
	parent.add_child(node)
	node.top_level = true
	return node

func update_character(view: Node3D, skin: String, radius: float, velocity: Vector2, bite: float, finished: bool, clock: float) -> void:
	var palette := {"star":Color("8980de"),"frog":Color("84ad77"),"cream":Color("edcf8d")}
	var tint: Color = palette.get(skin, palette.star)
	var mats: Array = view.get_meta("hole_materials", [])
	if mats.size() == 2:
		mats[0].set_shader_parameter("accent", Color("bd6269") if skin == "cream" else tint)
		mats[1].set_shader_parameter("accent", tint)
	var blink := 1.0 if finished or fmod(clock,4.1) > 4.02 or bite > .90 else 0.0
	var growth: float = float(mats[0].get_shader_parameter("growth01")) if mats.size() else 0.0
	if clock < float(view.get_meta("last_clock",0.0)):
		view.set_meta("growth_until",0.0)
	if growth > float(view.get_meta("previous_growth",growth)) + .002:
		view.set_meta("growth_until",clock+.32)
	view.set_meta("previous_growth",growth)
	view.set_meta("last_clock",clock)
	var expression := "finished" if finished else ("swallow" if bite > .1 else ("move" if velocity.length() > .2 else "idle"))
	if not finished and clock < float(view.get_meta("growth_until",0.0)):
		expression = "growth"
	view.set_meta("skin",skin)
	view.set_meta("expression",expression)
	var image_ring: MeshInstance3D = view.get_meta("image_ring")
	image_ring.visible = skin == "star"
	var image_eyes: MeshInstance3D = view.get_meta("image_eyes")
	image_eyes.visible = skin == "star"
	var eye_scale := star_eye_scale(radius)
	image_eyes.global_position = view.global_position + Vector3(0,.056+.13*eye_scale,-1.12*radius)
	image_eyes.scale = Vector3.ONE*eye_scale
	image_eyes.material_override.set_shader_parameter("blink",blink)
	view.get_node("BeveledMouth").visible = skin != "star"
	image_ring.material_override.set_shader_parameter("blink",blink)
	image_ring.material_override.set_shader_parameter("bite_pulse",bite)
	image_ring.material_override.set_shader_parameter("gaze",Vector2(clampf(velocity.x*.018,-.16,.16),clampf(velocity.y*.009,-.06,.06)))
	for sprite in view.get_meta("face_sprites", []):
		sprite.visible = skin != "star"
		var pos: Vector3 = sprite.get_meta("base_position")
		# World-space sprite avoids inheriting the root's XZ-only scale twice.
		sprite.global_position = view.global_position + pos * radius
		sprite.scale = Vector3.ONE * radius
		var mat: ShaderMaterial = sprite.material_override
		mat.set_shader_parameter("blink",blink)
		mat.set_shader_parameter("gaze", Vector2(clampf(velocity.x*.018,-.18,.18), clampf(velocity.y*.009,-.08,.08)))
		if str(sprite.name).begins_with("Eye"):
			mat.set_shader_parameter("tint",Color("fff5db"))
		elif str(sprite.name).begins_with("Cheek"):
			mat.set_shader_parameter("tint",Color("f39886"))
		elif sprite.name == "Badge":
			sprite.visible = skin == "cream"
			mat.set_shader_parameter("feature", 3 if skin == "cream" else 2)
			mat.set_shader_parameter("tint",Color("b89acc") if skin == "cream" else Color("ffd06a"))
		else:
			sprite.visible = skin == "cream"
			mat.set_shader_parameter("tint",Color("b89acc"))

# Small-screen compensation tapers out by G2; it never alters the circular mouth.
static func star_eye_scale(radius: float) -> float:
	return radius * (1.0 + .30 * (1.0 - smoothstep(.45,1.05,radius)))
