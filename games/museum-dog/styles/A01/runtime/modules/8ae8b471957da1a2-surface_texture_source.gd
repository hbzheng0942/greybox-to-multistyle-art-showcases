extends RefCounted
## Small, immutable runtime texture tiles; no source images are written or changed.
const SIZE := 256
static var _cache: Dictionary = {}

static func maps(family: String, patch_m: float) -> Dictionary:
	var key := family + ":" + str(patch_m)
	if _cache.has(key): return _cache[key]
	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	var color := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rough := Image.create(SIZE, SIZE, false, Image.FORMAT_R8)
	var normal := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in range(SIZE):
		for x in range(SIZE):
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			var grain := _noise(u, v, 64, 31)
			var broad := _noise(u, v, 12, 73)
			var h := 0.0
			var pigment := 1.0
			var rough_value := 0.5
			if family == "canvas":
				# Phase-varied weave contributes only subtle pigment/roughness.
				# No coherent 4px carrier in the normal map (gameplay moire).
				var tx := fposmod(float(x) + 1.35*_noise(u,v,8,211) + .55*_noise(u,v,32,227),4.0)
				var ty := fposmod(float(y) + 1.35*_noise(u,v,8,239) + .55*_noise(u,v,32,251),4.0)
				var over := posmod(int(x / 4) + int(y / 4), 2) == 0
				var warp := pow(sin(PI*tx/4.0),2.0)
				var weft := pow(sin(PI*ty/4.0),2.0)
				var yarn := warp * .75 + weft * .25 if over else warp * .25 + weft * .75
				var crease := _creases(u, v)
				h = (_noise(u,v,32,269)-.5)*.000060 + (grain-.5)*.000020 + crease*.00055
				pigment = .982 + (yarn-.6)*.008 + (broad-.5)*.012
				rough_value = clampf(.72 + .12*grain + .06*broad + .015*(1.0-yarn),0.0,1.0)
			elif family=="floor":
				# Metre-scale pressed cloth relief and satin wear, not uniform glass.
				var cloud:float=_noise(u,v,4,389)
				var fibres:float=_noise(u,v,64,409)
				h=(cloud-.5)*.0020+(_noise(u,v,13,431)-.5)*.0008+(fibres-.5)*.00004
				pigment=.96+(cloud-.5)*.075+(fibres-.5)*.018
				rough_value=clampf(.20+.65*cloud+.12*grain,0.0,1.0)
			else:
				# Irregular leather/PVC emboss; no large sinusoidal waves.
				var pebble := _noise(u, v, 48, 117)
				var pores := pow(maxf(0.0, .48-grain), 2.0)
				var crease := _creases(u, v)
				var relief := .00020 if family == "floor" else .00012
				h = (pebble-.5)*relief - pores*.00016 + crease*(.00026 if family == "floor" else .00038)
				pigment = .985 + (pebble-.5)*.016 + (broad-.5)*.012
				rough_value = clampf(.45 + .24*pebble + .10*grain, 0.0, 1.0)
			height[y*SIZE+x] = h
			color.set_pixel(x,y,Color(pigment,pigment,pigment,1.0))
			rough.set_pixel(x,y,Color(rough_value,rough_value,rough_value))
	var texel_m := patch_m / SIZE
	for y in range(SIZE):
		for x in range(SIZE):
			var dx := (height[y*SIZE+posmod(x+1,SIZE)] - height[y*SIZE+posmod(x-1,SIZE)]) / (2.0*texel_m)
			var dy := (height[posmod(y+1,SIZE)*SIZE+x] - height[posmod(y-1,SIZE)*SIZE+x]) / (2.0*texel_m)
			var n := Vector3(-dx,-dy,1.0).normalized()
			normal.set_pixel(x,y,Color(n.x*.5+.5,n.y*.5+.5,n.z*.5+.5))
	for im in [color,rough,normal]: im.generate_mipmaps()
	var result := {"albedo":ImageTexture.create_from_image(color),"normal":ImageTexture.create_from_image(normal),"roughness":ImageTexture.create_from_image(rough),"patch_m":patch_m}
	_cache[key] = result
	return result

static func detail(family: String, strength: float) -> Dictionary:
	var key := "detail:"+family+":"+str(strength)
	if _cache.has(key):return _cache[key]
	var base := maps("canvas",.32)
	var color: Image = base.albedo.get_image()
	color.clear_mipmaps()
	for y in range(SIZE):
		for x in range(SIZE):
			var c := color.get_pixel(x,y)
			c.a = strength
			color.set_pixel(x,y,c)
	color.generate_mipmaps()
	var result := {"albedo":ImageTexture.create_from_image(color),"normal":base.normal}
	_cache[key] = result
	return result

static func _hash(x: int, y: int, seed: int) -> float:
	var n := posmod(x*374761393 + y*668265263 + seed*982451653, 2147483647)
	n = posmod((n ^ (n >> 13))*1274126177,2147483647)
	return float(n) / 2147483647.0

static func _noise(u: float, v: float, cells: int, seed: int) -> float:
	var px := u*cells
	var py := v*cells
	var ix := int(floor(px))
	var iy := int(floor(py))
	var fx := smoothstep(0.0,1.0,px-floor(px))
	var fy := smoothstep(0.0,1.0,py-floor(py))
	return lerpf(lerpf(_hash(posmod(ix,cells),posmod(iy,cells),seed),_hash(posmod(ix+1,cells),posmod(iy,cells),seed),fx),lerpf(_hash(posmod(ix,cells),posmod(iy+1,cells),seed),_hash(posmod(ix+1,cells),posmod(iy+1,cells),seed),fx),fy)

static func _creases(u: float, v: float) -> float:
	# Eight short tapered creases, wrapped and individually oriented. They do
	# not run across the whole tile like the rejected wave/woodgrain pattern.
	var sum := 0.0
	for i in range(8):
		var cx := _hash(i,3,151)
		var cy := _hash(i,7,191)
		var dx := wrapf(u-cx,-.5,.5)
		var dy := wrapf(v-cy,-.5,.5)
		var angle := _hash(i,11,47)*TAU
		var along := dx*cos(angle)+dy*sin(angle)
		var across := -dx*sin(angle)+dy*cos(angle)
		var length := .08 + .07*_hash(i,13,23)
		var width := .009 + .004*_hash(i,17,83)
		sum += exp(-pow(across/width,2.0)-pow(along/length,4.0)) * (.55 + .45*_hash(i,19,41))
	return sum

static func neutral_normal() -> Texture2D:
	if _cache.has("neutral_normal"):return _cache.neutral_normal
	var im:=Image.create(1,1,false,Image.FORMAT_RGB8)
	im.fill(Color(.5,.5,1.0))
	var texture:=ImageTexture.create_from_image(im)
	_cache.neutral_normal=texture
	return texture
