shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, diffuse_lambert;

// E01 / E02 / E03 / E12 - one shared, hole-aware dry surface.
// Palette follows the frozen concept: warm slate walkways, cream plaza paving, mid-slate
// asphalt, cream crossings. No whitewashed slabs and no high-frequency texture.
// Both moving openings are still cut out here, so new paving can never seal the cavity.

uniform vec4 hole_a = vec4(0.0);
uniform vec4 hole_b = vec4(0.0);
uniform vec2 land_half_size = vec2(22.0, 18.0);
uniform vec2 water_corner = vec2(-9.0, 8.0);
uniform bool show_grid = false;
uniform bool park_paving = false;
uniform bool calibrated_light = false;
uniform float floor_fill = 0.24;
uniform float shore_margin = 0.18;
uniform vec3 walkway_color = vec3(0.605, 0.610, 0.590);
uniform vec3 paving_color = vec3(0.780, 0.735, 0.625);
uniform vec3 asphalt_color = vec3(0.335, 0.375, 0.425);
uniform vec3 kerb_color = vec3(0.815, 0.790, 0.715);
uniform int motif_count = 0;
uniform vec4 motifs[32]; // center XZ, radius, triangle flag
uniform vec4 motif_colors[32];
uniform vec2 motif_options[32]; // Y aspect ratio, road-only flag
uniform vec2 motif_rotations[32]; // cos, sin; authored in scene recipe
uniform float path_edge_width = 0.04;
varying vec3 world_position;

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

float rectmask(vec2 p, vec2 c, vec2 h) { vec2 q = abs(p - c) - h; return 1.0 - smoothstep(0.0, 0.045, max(q.x, q.y)); }
float smooth_union(float a, float b) { float h = max(.45-abs(a-b),0.0)/.45; return min(a,b)-h*h*.1125; }
float segdist(vec2 p, vec2 a, vec2 b) { vec2 d = b - a; return length(p - a - d * clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0)); }

void fragment() {
	vec2 p = world_position.xz;
	if (p.x < water_corner.x && p.y > water_corner.y) { discard; }
	if (hole_a.w > 0.5 && distance(p, hole_a.xy) < hole_a.z) { discard; }
	if (hole_b.w > 0.5 && distance(p, hole_b.xy) < hole_b.z) { discard; }

	vec3 walkway = walkway_color;
	vec3 paving = paving_color;
	vec3 asphalt = asphalt_color;
	vec3 kerb = kerb_color;

	float plaza = 1.0 - smoothstep(4.55, 4.65, length(p - vec2(0.0, -3.0)));
	float ring = 1.0 - smoothstep(1.45, 1.52, abs(length(p - vec2(0.0, -3.0)) - 6.30));
	float road = max(ring, rectmask(p, vec2(0.0, 4.30), vec2(19.7, 1.50)));
	road = max(road, rectmask(p, vec2(-7.30, -9.8), vec2(1.45, 7.8)));
	road = max(road, rectmask(p, vec2(6.5, 8.9), vec2(1.45, 8.8)));

	float road_distance = abs(length(p-vec2(0.,-3.))-6.30)-1.50;
	road_distance = smooth_union(road_distance,max(abs(p.x)-19.7,abs(p.y-4.30)-1.50));
	road_distance = smooth_union(road_distance,max(abs(p.x+7.30)-1.45,abs(p.y+9.8)-7.8));
	road_distance = smooth_union(road_distance,max(abs(p.x-6.5)-1.45,abs(p.y-8.9)-8.8));
	if (park_paving) { road = 1.0-smoothstep(-.035,.035,road_distance); }
	vec3 color = mix(walkway, paving, plaza);
	color = mix(color, asphalt, road);

	// Paving joints stay inside the slab so the walkway still reads as large clean blocks.
	vec2 tile = abs(fract(p * 1.1) - .5);
	float seam = smoothstep(.470, .492, max(tile.x, tile.y));
	color *= 1.0 - seam * .085 * (1.0 - road);

	// Distance to the nearest shore edge: used for the kerb band and the debug safety line.
	float shore = min(land_half_size.x - abs(p.x), min(land_half_size.y - abs(p.y), p.y + land_half_size.y));
	shore = min(shore, segdist(p, vec2(-22., 8.), water_corner));
	shore = min(shore, segdist(p, water_corner, vec2(-9., 18.)));
	color = mix(color, kerb, (1.0 - smoothstep(0.10, 0.36, shore)) * 0.80);

	float dash = step(.40, fract(p.x * .40));
	float lane = (1.0 - smoothstep(.018, .045, abs(p.y - 4.3))) * dash * rectmask(p, vec2(0., 4.3), vec2(19.0, 1.0));
	color = mix(color, vec3(.88, .79, .46), lane * .70);

	// Four readable crossings, drawn into the SAME hole-aware surface.
	float crossing = max(rectmask(p, vec2(-8.8, 4.3), vec2(.9, 1.36)), rectmask(p, vec2(8.0, 4.3), vec2(.9, 1.36)));
	crossing = max(crossing, rectmask(p, vec2(-7.3, -3.2), vec2(1.35, .85)));
	color = mix(color, vec3(.905, .885, .820), crossing * step(.43, fract(p.y * 1.5)) * .88);

	// E03 plaza inlay: a soft ring built from the same surface, so it never adds collision.
	float inlay = (1.0 - smoothstep(1.70, 1.86, abs(length(p - vec2(0.0, -3.0)) - 3.30))) * plaza;
	color = mix(color, vec3(0.700, 0.665, 0.560), inlay * 0.62);

	if (park_paving) {
        color = mix(walkway, asphalt, road);
        float sector = step(.50, fract(atan(p.y+3.0,p.x) * 2.54648));
        color = mix(color, mix(paving,walkway,sector*.20),plaza);
        float edge = 1.0-smoothstep(.035,.075,abs(length(p-vec2(0.,-3.))-4.45));
        color = mix(color,kerb,edge);
        // Low-frequency painted park motifs on the same opening-aware surface.
        float circles = max(1.0-smoothstep(1.65,1.70,length(p-vec2(12.6,13.0))),1.0-smoothstep(1.22,1.27,length(p-vec2(-1.0,11.0))));
        circles = max(circles,1.0-smoothstep(1.35,1.40,length(p-vec2(13.0,-12.7))));
        color = mix(color,vec3(.72,.63,.91),circles*(1.0-road)*.65*(motif_count==0?1.0:0.0));
        float coral_dot = 1.0-smoothstep(.72,.77,length(p-vec2(2.5,15.3)));
        color = mix(color,vec3(.96,.66,.51),coral_dot*.52*(motif_count==0?1.0:0.0));
        // Inset path edging joins the existing routes without changing traversable geometry.
        float border = 1.0-smoothstep(path_edge_width*.7,path_edge_width,abs(road_distance+.16));
        if(motif_count>0) {
            // Put the band outside the union. An inset contour can leave detached
            // islands where three paths meet even when the road itself has no hole.
            border=smoothstep(0.0,.022,road_distance)*(1.0-smoothstep(path_edge_width-.025,path_edge_width,road_distance));
            color=mix(color,kerb,border*(1.0-plaza));
        } else { color=mix(color,kerb,border*.42*road*(1.0-plaza)); }
        // Large slabs keep broad empty areas legible without high-frequency checker patterns.
        vec2 joint = abs(fract(p*.36)-.5);
        color *= 1.0-smoothstep(.492,.499,max(joint.x,joint.y))*.025*(1.0-road);
        if(motif_count>0) {
            // Selected-concept graphics are paint, not objects: both hole discards above remain authoritative.
            for(int i=0;i<32;i++) {
                if(i>=motif_count) { break; }
                vec2 q=(p-motifs[i].xy)/motifs[i].z;
                vec2 rot=motif_rotations[i];
                q=vec2(q.x*rot.x-q.y*rot.y,q.x*rot.y+q.y*rot.x);
                float d=length(q)-1.0;
                q.y/=max(motif_options[i].x,.01);
                if(motifs[i].w>1.5) {
                    vec2 b=abs(q)-vec2(.77);
                    d=length(max(b,0.0))+min(max(b.x,b.y),0.0)-.23;
                } else if(motifs[i].w>.5) {
                    // Equilateral triangle with a tiny softened paint edge.
                    d=max(-q.y-.5,max(q.x*.866025+q.y*.5,-q.x*.866025+q.y*.5)-.5);
                }
                float painted=1.0-smoothstep(-.018,.018,d);
                painted*=motif_options[i].y>.5?road*(1.0-border):(1.0-road)*(1.0-border);
                color=mix(color,motif_colors[i].rgb,painted*motif_colors[i].a);
            }
            // Concentric brass-colored bands frame the small physical wheel without changing its swallow size.
            float medallion=length(p-vec2(0.,-3.));
            float band=1.0-smoothstep(.07,.12,abs(medallion-3.12));
            color=mix(color,kerb,band);
        }
    }
    if (show_grid) {
		vec2 cell = abs(fract(p - .5) - .5); vec2 aa = max(fwidth(p), vec2(.005));
		float grid = 1.0 - min(smoothstep(0., aa.x, cell.x), smoothstep(0., aa.y, cell.y));
		color = mix(color, vec3(.65, .75, .72), grid * .18);
		// Safety contour for the CURRENT functional radius + shore margin. Debug only.
		float safe = 1.0 - smoothstep(.035, .075, abs(shore - hole_a.z - shore_margin));
		color = mix(color, vec3(.3, .9, .8), safe * .9);
	}

	ALBEDO = color;
	EMISSION = color * (calibrated_light ? floor_fill : 0.18);
	ROUGHNESS = 0.98;
	SPECULAR = 0.0;
}

void light() {
	float wrapped = max((dot(NORMAL, LIGHT) + 0.45) / 1.45, 0.0);
	// LIGHT_COLOR includes light energy and PI in Godot; preserve the legacy floor
	// only for snapshots without a calibrated scene recipe.
	DIFFUSE_LIGHT += calibrated_light ? wrapped * ATTENUATION * LIGHT_COLOR / PI : vec3(wrapped * ATTENUATION * 0.82);
}
