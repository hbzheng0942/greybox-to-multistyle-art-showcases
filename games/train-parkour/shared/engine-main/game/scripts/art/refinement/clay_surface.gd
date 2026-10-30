class_name ClaySurface
extends RefCounted
var cache := {}
var geometry := {}
var noise: NoiseTexture2D
var shader := preload("res://materials/clay-refinement/handmade.gdshader")
const COLORS := {"cream":"f0d5ac","peach":"d89070","teal":"568d87","lavender":"a995c3","dark":"354c69","orange":"e78f48","floor":"9a87aa","rail":"beb8c5","sleeper":"6b5b79","red":"d84b38","gold":"d8ab58","sage":"708b61"}
func material(key: String, color := "", glow := 0.0, tile := false) -> ShaderMaterial:
	var id := key+color+str(glow)+str(tile)
	if cache.has(id): return cache[id]
	if noise == null:
		var n := FastNoiseLite.new(); n.seed = 928; n.frequency = .065; n.fractal_octaves = 4
		noise = NoiseTexture2D.new(); noise.width = 512; noise.height = 512; noise.noise = n; noise.seamless = true; noise.generate_mipmaps = true
	var m := ShaderMaterial.new();m.shader = shader;m.resource_name = "Handmade_"+key
	m.set_shader_parameter("clay_color",Color(COLORS.get(key,"e0bd99") if color=="" else color))
	m.set_shader_parameter("grain",noise);m.set_shader_parameter("emission_value",glow)
	m.set_shader_parameter("relief",.007 if not tile else .003);m.set_shader_parameter("tiled",1.0 if tile else 0.0)
	cache[id]=m;return m
func converted(old: Material) -> Material:
	if not old is StandardMaterial3D: return old
	var key := str(old.get_instance_id())
	if cache.has(key): return cache[key]
	var name: String = old.resource_name.to_lower()
	var color: Color = old.albedo_color
	for pair in [["terracotta","peach"],["cream","cream"],["teal","teal"],["lavender","lavender"],["indigo","dark"],["safetyred","red"]]:
		if pair[0] in name: color=Color(COLORS[pair[1]])
	var m := material(key,color.to_html(false),.6 if "globe" in name or "signal" in name else 0.0).duplicate()
	if old.albedo_texture != null:
		m.set_shader_parameter("textured",true);m.set_shader_parameter("source_albedo",old.albedo_texture)
	if "glass" in name or "indigo" in name:m.set_shader_parameter("roughness_value",.28);m.set_shader_parameter("relief",.005)
	cache[key]=m;return m
func box(dim: Vector3, radius := .15) -> ArrayMesh:
	var key := str(dim)+str(radius)
	if geometry.has(key): return geometry[key]
	var box := BoxMesh.new();box.size=dim;box.subdivide_width=5;box.subdivide_height=5;box.subdivide_depth=5
	var arrays := box.get_mesh_arrays();var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var r := minf(radius,minf(dim.x,minf(dim.y,dim.z))*.45)
	var inner := dim*.5-Vector3.ONE*r
	for i in vertices.size():
		var p := vertices[i];var c:=p.clamp(-inner,inner);var n:=(p-c).normalized();vertices[i]=c+n*r;normals[i]=n
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var result := ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);geometry[key]=result;return result
