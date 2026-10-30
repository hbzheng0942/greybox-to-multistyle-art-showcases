extends RefCounted
## Black hole presentation: procedural geometry + shaders.
##
## Contract (01_WORKBUDDY_EXECUTION_PROMPT.md section 8):
##   * the mouth, inner funnel, swirl, face, growth and rival colour are designed here;
##   * the hole is never a flat black disc and never a capped GLB;
##   * the expression sits inside the funnel so it cannot cover a falling object;
##   * nothing in this file owns radius, swallow timing or payouts - it only reads signals.

const WELL_SHADER = preload("res://shaders/hole_well.gdshader")
const RIM_SHADER = preload("res://shaders/hole_rim.gdshader")
const MouthTuning = preload("res://scripts/tuning.gd")

const WELL_DEPTH := 2.55
const MOUTH_RADIUS := 1.0

## Built at unit radius; the caller scales X/Z by the live functional radius and leaves Y alone,
## so the funnel depth stays constant while the opening grows with the hole.
func make(accent: Color, rival: bool = false) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "BlackHoleRival" if rival else "BlackHolePlayer"

	# --- inner funnel: depth falloff, restrained swirl and the painted face
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

	# --- beveled rim: the bright tick ring stays inside the functional opening
	var lip: MeshInstance3D = MeshInstance3D.new()
	lip.name = "BeveledMouth"
	var lip_mesh: TorusMesh = TorusMesh.new()
	lip_mesh.inner_radius = MouthTuning.MOUTH_DIAMETER_RATIO
	lip_mesh.outer_radius = 1.062
	lip_mesh.rings = 72
	lip_mesh.ring_segments = 10
	lip.mesh = lip_mesh
	lip.scale = Vector3(1.0, 0.34, 1.0)
	lip.position.y = -0.004
	var lip_material: ShaderMaterial = ShaderMaterial.new()
	lip_material.shader = RIM_SHADER
	lip_material.set_shader_parameter("accent", accent)
	lip_material.set_shader_parameter("growth01", 0.0)
	lip_material.set_shader_parameter("bite_pulse", 0.0)
	lip_material.set_shader_parameter("alive", 1.0)
	lip.material_override = lip_material
	root.add_child(lip)

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
