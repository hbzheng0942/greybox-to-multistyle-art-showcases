shader_type spatial;
render_mode cull_disabled;
uniform sampler2D masonry_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wp;
varying vec3 wn;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
	float kind=UV2.x;
	vec3 color=COLOR.rgb;
	if(kind<0.5){
		vec2 tile=abs(wn.x)>abs(wn.z)?wp.zy:wp.xy;
		vec3 paint=texture(masonry_texture,tile/17.0).rgb;
		float stroke=dot(paint,vec3(0.2126,0.7152,0.0722));
		color=mix(color,paint*vec3(1.4,0.65,1.2),0.55);
		color*=mix(0.66,1.24,smoothstep(0.015,0.26,stroke));
	}
	if(kind>0.5&&kind<1.5){vec3 slate=texture(roof_texture,wp.xz/14.0).rgb; color*=mix(0.55,1.5,smoothstep(0.01,0.24,dot(slate,vec3(0.2126,0.7152,0.0722))));}
	ALBEDO=color;ROUGHNESS=0.95;SPECULAR=0.18;
	if(kind>2.5){
		EMISSION=color*(UV2.y>1.5?1.6:2.2);
	}else if(kind<0.5){
		// Authored irradiance on solid city walls: stable object-height field,
		// independent of the camera, shadowed roof tops and lit-window masks.
		float low=1.0-smoothstep(0.03,0.94,UV.y);
		float face=1.0-smoothstep(0.35,0.75,wn.y);
		float district=0.75+0.25*sin(wp.z*.026+wp.x*.019);
		EMISSION=color*vec3(4.2,0.65,2.2)*(0.24+low)*face*district*(UV2.y>1.5?0.18:1.0);
	}else if(kind<1.5){EMISSION=color*(UV2.y>1.5?0.12:0.65);}
}
void light(){
	float ndl=max(0.0,dot(NORMAL,LIGHT));
	float band=mix(0.15,0.6,smoothstep(0.0,0.1,ndl));
	band=mix(band,1.0,smoothstep(0.45,0.58,ndl));
	DIFFUSE_LIGHT+=LIGHT_COLOR*band*smoothstep(0.0,0.08,ndl)*ATTENUATION/PI;
}
