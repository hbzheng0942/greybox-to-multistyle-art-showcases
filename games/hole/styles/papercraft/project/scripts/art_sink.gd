extends RefCounted
## Procedural triangle accumulator for the Toy Downtown Waterfront art pass.
##
## Design contract (docs/02_EXECUTION_CONTRACT_v2.md + formal_assets_v1.csv):
##   * one logical unit = one or two merged surfaces, so material slots stay <= 2;
##   * the palette travels in vertex colours (COLOR), not in extra materials;
##   * stripes / checker / window rows are baked geometry banding, never a texture hack;
##   * rounded boxes come from an exact signed-distance solve so the toy bevel is real
##     geometry with analytic normals (no post-process smoothing).
##
## Nothing here knows about gameplay. Positions, footprints and rewards stay in the
## simulation; these builders only fill a visual child.

const GROUP_BODY := "body"
const GROUP_GLOW := "glow"

## One SurfaceTool per unit, not one per group.
##
## Draw-call discipline: a logical unit must cost ONE mesh instance and ONE material. The two
## original groups (matte body / self-lit trim) are therefore merged into a single triangle
## stream, and the distinction travels in vertex-colour ALPHA (0 = matte, 1 = glow) instead of
## in a second material. shaders/object.gdshader reads that alpha.
##
## `_counts` still reports the two logical groups separately so the ledger stays meaningful.
var _st: SurfaceTool
var _counts: Dictionary = {}

func _tool() -> SurfaceTool:
	if _st == null:
		_st = SurfaceTool.new()
		_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_counts[GROUP_BODY] = 0
		_counts[GROUP_GLOW] = 0
	return _st

func groups() -> Array:
	if _st == null:
		return []
	return [GROUP_BODY]

func triangle_count(group: String = "") -> int:
	if group == "":
		var total: int = 0
		for key in _counts:
			total += int(_counts[key])
		return total
	return int(_counts.get(group, 0))

func vertex_count(group: String = "") -> int:
	return (_st as SurfaceTool).get_vertex_count() if _st != null else 0

func commit(group: String) -> ArrayMesh:
	if _st == null or group != GROUP_BODY:
		return null
	return _st.commit()

func _put(st: SurfaceTool, xf: Transform3D, p: Vector3, n: Vector3, uv: Vector2,
		color: Color, glow: bool) -> void:
	var world_normal: Vector3 = (xf.basis * n)
	st.set_normal(world_normal.normalized() if world_normal.length_squared() > 0.0 else Vector3.UP)
	st.set_uv(uv)
	# Alpha is the self-lit weight, not transparency. Keep the palette RGB untouched.
	var c: Color = color
	c.a = 1.0 if glow else 0.0
	st.set_color(c)
	st.add_vertex(xf * p)

func _tri(group: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, color: Color) -> void:
	var st: SurfaceTool = _tool()
	var glow: bool = group == GROUP_GLOW
	_put(st, xf, a, na, Vector2(0.0, 0.0), color, glow)
	_put(st, xf, b, nb, Vector2(1.0, 0.0), color, glow)
	_put(st, xf, c, nc, Vector2(0.5, 1.0), color, glow)
	_counts[group] = int(_counts.get(group, 0)) + 1

func _quad(group: String, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, color: Color) -> void:
	_tri(group, xf, a, b, c, na, nb, nc, color)
	_tri(group, xf, a, c, d, na, nc, nd, color)

# ---------------------------------------------------------------- rounded box

static func _sd_round_box(p: Vector3, core: Vector3, r: float) -> float:
	var q: Vector3 = Vector3(absf(p.x), absf(p.y), absf(p.z)) - core
	var m: Vector3 = Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0))
	return m.length() - r

static func _solve_surface(dir: Vector3, h: Vector3, core: Vector3, r: float) -> Vector3:
	var t_max: float = 0.0
	for axis in 3:
		var a: float = absf(dir[axis])
		if a > 1e-6:
			t_max = maxf(t_max, h[axis] / a)
	if t_max <= 0.0:
		t_max = h.length()
	if t_max <= 0.0:
		return Vector3.ZERO
	var lo: float = 0.0
	var hi: float = t_max
	for _step in range(24):
		var mid: float = (lo + hi) * 0.5
		if _sd_round_box(dir * mid, core, r) < 0.0:
			lo = mid
		else:
			hi = mid
	return dir * ((lo + hi) * 0.5)

static func _round_box_normal(p: Vector3, core: Vector3) -> Vector3:
	var q: Vector3 = Vector3(absf(p.x), absf(p.y), absf(p.z)) - core
	var m: Vector3 = Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0))
	if m.length() > 1e-5:
		var s: Vector3 = Vector3(signf(p.x), signf(p.y), signf(p.z))
		var n: Vector3 = Vector3(s.x * m.x, s.y * m.y, s.z * m.z)
		if n.length_squared() > 1e-12:
			return n.normalized()
	return Vector3.UP

const _FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]

## Triangle-budget rule (the "减面" half of the delivery).
##
## A rounded box at `seg = n` emits 6 * n * n * 2 triangles: the 6 faces are each subdivided into
## an n x n grid so the corner bevel has somewhere to live. That is the right cost for a shop
## facade and the wrong cost for a 6 cm door bolt or a donut sprinkle, where the bevel is smaller
## than a pixel at any playable camera distance.
##
## This returns a step count that is never larger than the recipe asked for, so a recipe can still
## opt into more detail explicitly.
static func budgeted_steps(size: Vector3, requested: int) -> int:
	var extent: float = maxf(size.x, maxf(size.y, maxf(size.z, 0.0001)))
	var cap: int = requested
	if extent <= 0.10:
		cap = 1
	elif extent <= 0.30:
		cap = 2
	return clampi(mini(requested, cap), 1, 4)

## Rounded box centred on the transform origin. face_colors overrides per axis (±X,±Y,±Z order).
## `skip` is a 6-bit mask of faces to omit (bit i drops _FACES[i]); faces that are buried inside
## another part or facing the ground are pure waste, so recipes may drop them.
func rbox(xf: Transform3D, size: Vector3, radius: float, color: Color,
		seg: int = 3, group: String = GROUP_BODY, face_colors: Array = [], skip: int = 0) -> void:
	var s: Vector3 = Vector3(maxf(size.x, 1e-4), maxf(size.y, 1e-4), maxf(size.z, 1e-4))
	var h: Vector3 = s * 0.5
	var r: float = clampf(radius, 0.0012, minf(h.x, minf(h.y, h.z)) * 0.97)
	var core: Vector3 = Vector3(maxf(h.x - r, 0.0), maxf(h.y - r, 0.0), maxf(h.z - r, 0.0))
	# Include the centre of every face even at the lowest budget. A four-corner
	# approximation cannot represent the extreme of a thin, wide slab.
	var steps: int = maxi(2, budgeted_steps(s, maxi(1, seg)))
	for fi in range(6):
		if skip & (1 << fi):
			continue
		var fn: Vector3 = _FACES[fi][0]
		var ft: Vector3 = _FACES[fi][1]
		var fb: Vector3 = _FACES[fi][2]
		var col: Color = color if face_colors.is_empty() else face_colors[fi]
		var pts: Array = []
		var nms: Array = []
		for i in range(steps + 1):
			var row_p: Array = []
			var row_n: Array = []
			var u: float = float(i) / float(steps) * 2.0 - 1.0
			for j in range(steps + 1):
				var v: float = float(j) / float(steps) * 2.0 - 1.0
				# Build a dimension-aware point on the enclosing box, then round
				# only the portion outside the unrounded core. Unit-cube rays
				# collapse long, thin parts toward their short axis.
				var box_point: Vector3 = Vector3(fn.x * h.x + ft.x * h.x * u + fb.x * h.x * v,
					fn.y * h.y + ft.y * h.y * u + fb.y * h.y * v,
					fn.z * h.z + ft.z * h.z * u + fb.z * h.z * v)
				var closest: Vector3 = Vector3(clampf(box_point.x, -core.x, core.x),
					clampf(box_point.y, -core.y, core.y), clampf(box_point.z, -core.z, core.z))
				var p: Vector3 = closest + (box_point - closest).normalized() * r
				row_p.append(p)
				row_n.append(_round_box_normal(p, core))
			pts.append(row_p)
			nms.append(row_n)
		for i in range(steps):
			for j in range(steps):
				# Match BoxMesh's winding. The old order culled the outer faces.
				_quad(group, xf,
					pts[i][j], pts[i][j + 1], pts[i + 1][j + 1], pts[i + 1][j],
					nms[i][j], nms[i][j + 1], nms[i + 1][j + 1], nms[i + 1][j], col)

## Axis-aligned slab helper: centre + size in the parent frame.
func slab(parent: Transform3D, center: Vector3, size: Vector3, radius: float, color: Color,
		seg: int = 2, group: String = GROUP_BODY, face_colors: Array = [], skip: int = 0) -> void:
	var xf: Transform3D = parent
	xf.origin = parent * center
	xf.basis = parent.basis
	rbox(xf, size, radius, color, seg, group, face_colors, skip)

# -------------------------------------------------------------------- banding

## Subdivides a slab along one axis so alternating colour bands become real geometry.
## Used for awnings (stripes), shutters (louvers), crates (lattice) and window rows.
##
## Only the BAND axis walks: bands tile `size[axis]` from `center[axis] - size[axis] * 0.5`
## upward. The other two axes must stay exactly on `center`, because a band's own size does not
## depend on the band index. `probe_band.gd` measures this: with the old
## `center - size * 0.5 + step * (i + 0.5)` on every axis, `step` is zero off-axis, so the whole
## slab was silently displaced by half its size on those two axes - which pushed the market stall
## canopy 0.19 past its 0.85-deep gameplay envelope and sank the striped pallet planks below the
## plain ones.
func banded_slab(parent: Transform3D, center: Vector3, size: Vector3, radius: float,
		bands: int, axis: int, color_a: Color, color_b: Color, seg: int = 2,
		group: String = GROUP_BODY) -> void:
	var count: int = maxi(1, bands)
	var step: Vector3 = Vector3.ZERO
	step[axis] = size[axis] / float(count)
	for i in range(count):
		var offset: Vector3 = center
		offset[axis] = center[axis] - size[axis] * 0.5 + step[axis] * (float(i) + 0.5)
		var piece: Vector3 = size
		piece[axis] = step[axis] * 1.02
		slab(parent, offset, piece, radius, color_a if i % 2 == 0 else color_b, seg, group)

# --------------------------------------------------------------------- sphere

static func _sph(radius: float, phi: float, theta: float) -> Vector3:
	var sp: float = sin(phi)
	return Vector3(radius * sp * cos(theta), radius * cos(phi), radius * sp * sin(theta))

## Ellipsoid with analytic normals. rings = latitude, segs = longitude.
func sphere(xf: Transform3D, radius: Vector3, color: Color, rings: int = 8, segs: int = 12,
		group: String = GROUP_BODY, phi_north: float = 0.0, phi_south: float = PI) -> void:
	var r: int = maxi(2, rings)
	var q: int = maxi(3, segs)
	for i in range(r):
		var phi0: float = lerpf(phi_north, phi_south, float(i) / float(r))
		var phi1: float = lerpf(phi_north, phi_south, float(i + 1) / float(r))
		for j in range(q):
			var th0: float = TAU * float(j) / float(q)
			var th1: float = TAU * float(j + 1) / float(q)
			var p00: Vector3 = _sph(1.0, phi0, th0) * radius
			var p01: Vector3 = _sph(1.0, phi0, th1) * radius
			var p11: Vector3 = _sph(1.0, phi1, th1) * radius
			var p10: Vector3 = _sph(1.0, phi1, th0) * radius
			var n00: Vector3 = (_sph(1.0, phi0, th0) / radius).normalized()
			var n01: Vector3 = (_sph(1.0, phi0, th1) / radius).normalized()
			var n11: Vector3 = (_sph(1.0, phi1, th1) / radius).normalized()
			var n10: Vector3 = (_sph(1.0, phi1, th0) / radius).normalized()
			if i == 0:
				_tri(group, xf, p00, p11, p10, n00, n11, n10, color)
			elif i == r - 1:
				_tri(group, xf, p00, p01, p11, n00, n01, n11, color)
			else:
				_quad(group, xf, p00, p01, p11, p10, n00, n01, n11, n10, color)

# ------------------------------------------------------------------- cylinder

func cylinder(xf: Transform3D, bottom_radius: float, top_radius: float, height: float,
		color: Color, segs: int = 12, cap_bottom: bool = true, cap_top: bool = true,
		group: String = GROUP_BODY, side_color_top: Color = Color(0, 0, 0, 0)) -> void:
	var q: int = maxi(3, segs)
	var hy: float = height * 0.5
	var at_top: bool = side_color_top.a > 0.001
	for j in range(q):
		var th0: float = TAU * float(j) / float(q)
		var th1: float = TAU * float(j + 1) / float(q)
		var b0: Vector3 = Vector3(bottom_radius * cos(th0), -hy, bottom_radius * sin(th0))
		var b1: Vector3 = Vector3(bottom_radius * cos(th1), -hy, bottom_radius * sin(th1))
		var t0: Vector3 = Vector3(top_radius * cos(th0), hy, top_radius * sin(th0))
		var t1: Vector3 = Vector3(top_radius * cos(th1), hy, top_radius * sin(th1))
		var n0: Vector3 = Vector3(cos(th0), 0.0, sin(th0))
		var n1: Vector3 = Vector3(cos(th1), 0.0, sin(th1))
		var side: Color = color if not at_top else color.lerp(side_color_top, 0.5)
		_quad(group, xf, b0, t0, t1, b1, n0, n0, n1, n1, side)
		if cap_top:
			_tri(group, xf, Vector3(0, hy, 0), t1, t0, Vector3.UP, Vector3.UP, Vector3.UP, color)
		if cap_bottom:
			_tri(group, xf, Vector3(0, -hy, 0), b0, b1, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, color)

# ---------------------------------------------------------------------- torus

func torus(xf: Transform3D, major: float, minor: float, color: Color, rings: int = 24,
		ring_segments: int = 8, group: String = GROUP_BODY) -> void:
	var R: int = maxi(4, rings)
	var S: int = maxi(3, ring_segments)
	var p := func(u: float, v: float) -> Vector3:
		return Vector3((major + minor * cos(v)) * cos(u), minor * sin(v), (major + minor * cos(v)) * sin(u))
	var n := func(u: float, v: float) -> Vector3:
		return Vector3(cos(v) * cos(u), sin(v), cos(v) * sin(u))
	for a in range(R):
		var u0: float = TAU * float(a) / float(R)
		var u1: float = TAU * float(a + 1) / float(R)
		for b in range(S):
			var v0: float = TAU * float(b) / float(S)
			var v1: float = TAU * float(b + 1) / float(S)
			_quad(group, xf, p.call(u0, v0), p.call(u0, v1), p.call(u1, v1), p.call(u1, v0),
				n.call(u0, v0), n.call(u0, v1), n.call(u1, v1), n.call(u1, v0), color)

# ---------------------------------------------------------------------- prism

## Convex prism in the XZ footprint, extruded along +Y. Used for wedges and closed roofs.
## footprint must be convex and given counter-clockwise seen from +Y.
func prism(xf: Transform3D, footprint: Array, height: float, color: Color,
		top_color: Color = Color(0, 0, 0, 0), group: String = GROUP_BODY) -> void:
	var n: int = footprint.size()
	if n < 3:
		return
	var hy: float = height * 0.5
	var top: Color = top_color if top_color.a > 0.001 else color
	var center_bottom: Vector3 = Vector3.ZERO
	var center_top: Vector3 = Vector3.ZERO
	for i in range(n):
		var a: Vector2 = footprint[i]
		var b: Vector2 = footprint[(i + 1) % n]
		center_bottom += Vector3(a.x, -hy, a.y)
		center_top += Vector3(a.x, hy, a.y)
	center_bottom /= float(n)
	center_top /= float(n)
	for i in range(n):
		var a: Vector2 = footprint[i]
		var b: Vector2 = footprint[(i + 1) % n]
		var a0: Vector3 = Vector3(a.x, -hy, a.y)
		var b0: Vector3 = Vector3(b.x, -hy, b.y)
		var a1: Vector3 = Vector3(a.x, hy, a.y)
		var b1: Vector3 = Vector3(b.x, hy, b.y)
		var edge: Vector3 = Vector3(b.x - a.x, 0.0, b.y - a.y)
		var nrm: Vector3 = Vector3(edge.z, 0.0, -edge.x).normalized()
		_quad(group, xf, a0, a1, b1, b0, nrm, nrm, nrm, nrm, color)
		_tri(group, xf, center_top, a1, b1, Vector3.UP, Vector3.UP, Vector3.UP, top)
		_tri(group, xf, center_bottom, b0, a0, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, color)
