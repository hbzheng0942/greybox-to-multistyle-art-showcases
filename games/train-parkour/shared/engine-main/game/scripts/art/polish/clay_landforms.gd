extends RefCounted
## Recess-only, rounded terraced silhouettes. Bounds never exceed the supplied scenery envelope.
const HEIGHTS = [0.0,.025,.07,.16,.26,.30,.335,.355,.38,.48,.57,.605,.64,.66,.69,.79,.87,.92,.965,1.0]
const RADII = [.75,.86,.94,.975,.96,.935,.90,.77,.755,.78,.765,.74,.70,.56,.545,.565,.55,.50,.425,.40]
static func radius(t: float) -> float:
	for j in range(1,HEIGHTS.size()):
		if t<=HEIGHTS[j]:return lerpf(RADII[j-1],RADII[j],smoothstep(HEIGHTS[j-1],HEIGHTS[j],t))
	return RADII[-1]
static func point(dim: Vector3,seed_value: int,t: float,angle: float) -> Vector3:
	var phase:=seed_value*.731
	# Asymmetric lobes break the repeated lathed-cylinder silhouette. The
	# construction stays inside the original envelope and shares its surface
	# function with planting/spillways, so decoration cannot float off it.
	var wobble:=.79+.105*sin(angle*3+phase+t*2.7)+.055*sin(angle*5-phase*.7+t*4)+.025*cos(angle*9+phase)
	var lean:=Vector2(sin(phase+t*2),cos(phase-t))*.065*sin(t*PI)
	var local_t:=clampf(t+.065*sin(angle*3+phase)*sin(t*PI),0,1)
	var r:=radius(local_t)
	var rx:=signf(cos(angle))*pow(absf(cos(angle)),.60)
	var rz:=signf(sin(angle))*pow(absf(sin(angle)),.60)
	return Vector3((rx*r*wobble+lean.x)*dim.x*.5,dim.y*(t-.5),(rz*r*wobble+lean.y)*dim.z*.5)
static func mesh(dim: Vector3,seed_value: int) -> ArrayMesh:
	var count:=64
	var rings: Array[PackedVector3Array]=[]
	var levels: Array[float]=[]
	for j in HEIGHTS.size()-1:
		for n in 2:levels.append(lerpf(HEIGHTS[j],HEIGHTS[j+1],n/2.0))
	levels.append(1.0)
	for t: float in levels:
		var ring:=PackedVector3Array()
		for k in count:ring.append(point(dim,seed_value,t,TAU*k/count))
		rings.append(ring)
	var normals: Array[PackedVector3Array]=[]
	for j in rings.size():
		var row:=PackedVector3Array()
		for k in count:
			var vertical:=rings[mini(j+1,rings.size()-1)][k]-rings[maxi(j-1,0)][k]
			var around:=rings[j][(k+1)%count]-rings[j][(k+count-1)%count]
			row.append(vertical.cross(around).normalized())
		normals.append(row)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings.size()-1:
		for k in count:
			var next:=(k+1)%count
			for ij: Vector2i in [Vector2i(j,k),Vector2i(j,next),Vector2i(j+1,k),Vector2i(j,next),Vector2i(j+1,next),Vector2i(j+1,k)]:
				st.set_normal(normals[ij.x][ij.y]);st.set_uv(Vector2(float(ij.y)/count,levels[ij.x]))
				st.set_color(Color.WHITE)
				st.add_vertex(rings[ij.x][ij.y])
	for k in count:
		for p in [Vector3(0,dim.y*.5,0),rings[-1][k],rings[-1][(k+1)%count]]:
			st.set_normal(Vector3.UP);st.set_uv(Vector2(p.x,p.z));st.set_color(Color.WHITE);st.add_vertex(p)
	st.index();var result:=st.commit()
	result.set_meta("land_dimensions",dim);result.set_meta("land_seed",seed_value)
	return result

static func channel_x(z: float,dim: Vector3,seed_value: int) -> float:
	return dim.x*(.12+.18*sin(z/dim.z*5.0+seed_value*.4))
static func field_height(x: float,z: float,dim: Vector3,seed_value: int) -> float:
	var nx:=x/(dim.x*.5);var nz:=z/(dim.z*.5)
	var edge:=smoothstep(.70,1.0,maxf(absf(nx),absf(nz)))
	var base:=dim.y*(.28+.09*sin(nx*5+seed_value)*cos(nz*4)-edge*.76)
	var distance:=absf(x-channel_x(z,dim,seed_value))
	var trench:=1.0-smoothstep(minf(12,dim.x*.012),minf(26,dim.x*.026),distance)
	return base-dim.y*.62*trench
static func field(dim: Vector3,seed_value: int) -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx:=clampi(ceili(dim.x/12.0),24,100);var nz:=clampi(ceili(dim.z/14.0),24,130)
	for j in nz:
		for i in nx:
			for ij: Vector2i in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i,j+1),Vector2i(i+1,j),Vector2i(i+1,j+1),Vector2i(i,j+1)]:
				var x:=dim.x*(float(ij.x)/nx-.5);var z:=dim.z*(float(ij.y)/nz-.5)
				st.set_uv(Vector2(x,z));st.add_vertex(Vector3(x,field_height(x,z,dim,seed_value),z))
	st.generate_normals();st.index();var result:=st.commit();result.set_meta("land_dimensions",dim);result.set_meta("land_seed",seed_value);return result

static func lobe(seed_value: int) -> ArrayMesh:
	# Broad sculpted block with rounded foot/cap and low-frequency clay lobes.
	# Unit bounds are reused by multiple islands rather than regenerating meshes.
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:=40;var rows:=20
	var points: Array[PackedVector3Array]=[]
	for j in rows+1:
		var t:=float(j)/rows;var ring:=PackedVector3Array()
		var radius:=.91+.075*sin(t*PI)-.10*(1-smoothstep(0,.12,t))-.06*smoothstep(.87,1,t)
		for k in count:
			var a:=TAU*k/count;var phase:=seed_value*.79
			var irregular:=.94+.045*sin(a*3+phase)+.023*sin(a*7+phase+t*2)
			var x:=signf(cos(a))*pow(absf(cos(a)),.79)
			var z:=signf(sin(a))*pow(absf(sin(a)),.79)
			ring.append(Vector3(x*radius*irregular*.5,t-.5,z*radius*irregular*.5))
		points.append(ring)
	for j in rows:
		for k in count:
			for ij: Vector2i in [Vector2i(j,k),Vector2i(j,(k+1)%count),Vector2i(j+1,k),Vector2i(j,(k+1)%count),Vector2i(j+1,(k+1)%count),Vector2i(j+1,k)]:
				var a:=points[mini(rows,ij.x+1)][ij.y]-points[maxi(0,ij.x-1)][ij.y]
				var b:=points[ij.x][(ij.y+1)%count]-points[ij.x][(ij.y+count-1)%count]
				st.set_normal(a.cross(b).normalized());st.set_uv(Vector2(float(ij.y)/count,float(ij.x)/rows));st.add_vertex(points[ij.x][ij.y])
	for k in count:
		for p in [Vector3(0,.5,0),points[-1][k],points[-1][(k+1)%count]]:
			st.set_normal(Vector3.UP);st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)
	st.index()
	return st.commit()
