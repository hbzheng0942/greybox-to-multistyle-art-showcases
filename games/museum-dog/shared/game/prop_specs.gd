extends RefCounted
## Shared native dimensions. Art swaps replace visuals without changing these shapes.
## Heights are full dimensions; rock keeps its original .26 m visual / .28 m collider.

const SPECS := {
	"plate": {"shape": "cylinder", "radius": 0.18, "height": 0.06, "top": 0.19, "bottom": 0.15},
	"vase": {"shape": "cylinder", "radius": 0.12, "height": 0.30, "top": 0.09, "bottom": 0.13},
	"vase_big": {"shape": "cylinder", "radius": 0.27, "height": 0.75, "top": 0.20, "bottom": 0.30},
	"button": {"shape": "cylinder", "radius": 0.12, "height": 0.07, "top": 0.12, "bottom": 0.12},
	"ball": {"shape": "sphere", "radius": 0.16, "visual_radius": 0.16, "visual_height": 0.32},
	"rock": {"shape": "sphere", "radius": 0.14, "visual_radius": 0.15, "visual_height": 0.26},
	"bone": {"shape": "box", "size": Vector3(0.42, 0.09, 0.09)},
	"specimen": {"shape": "box", "size": Vector3(0.50, 0.60, 0.40)},
	"bust": {"shape": "box", "size": Vector3(0.36, 0.50, 0.30)},
	"souvenir": {"shape": "box", "size": Vector3(0.18, 0.20, 0.18)},
	"craft": {"shape": "box", "size": Vector3(0.18, 0.20, 0.18)},
	"brochure": {"shape": "box", "size": Vector3(0.22, 0.26, 0.22)},
}

static func _spec(kind: String) -> Dictionary:
	return SPECS.get(kind, SPECS["brochure"])

static func rest_height(kind: String) -> float:
	var spec := _spec(kind)
	match str(spec["shape"]):
		"sphere":
			return float(spec["radius"]) * 2.0
		"cylinder":
			return float(spec["height"])
		_:
			var size: Vector3 = spec["size"]
			return size.y

static func shape_for(kind: String) -> Shape3D:
	var spec := _spec(kind)
	match str(spec["shape"]):
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = float(spec["radius"])
			return sphere
		"cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = float(spec["radius"])
			cylinder.height = float(spec["height"])
			return cylinder
		_:
			var box := BoxShape3D.new()
			box.size = spec["size"]
			return box

static func mesh_for(kind: String) -> Mesh:
	var spec := _spec(kind)
	match str(spec["shape"]):
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = float(spec["visual_radius"])
			sphere.height = float(spec["visual_height"])
			return sphere
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = float(spec["top"])
			cylinder.bottom_radius = float(spec["bottom"])
			cylinder.height = float(spec["height"])
			return cylinder
		_:
			var box := BoxMesh.new()
			box.size = spec["size"]
			return box
