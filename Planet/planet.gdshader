shader_type spatial;

uniform sampler2D world_map;
varying float v_height;
varying vec3 v_world_pos;

//float hash3D(vec3 p) // fast 3d hash function I got
//{
    //p = fract(p * vec3(443.8975, 397.2973, 491.1871));
    //p += dot(p.xyz, p.yzx + 19.19);
    //return fract(p.x * p.y * p.z);
//}

void vertex()
{
    v_height = COLOR.r;
	v_world_pos = VERTEX;
}

void fragment()
{
	vec3 face_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = face_normal;
	SPECULAR = 0.1;
	ROUGHNESS = 0.8;
	
	vec3 seabed_color = vec3(0.55, 0.48, 0.38);//vec3(0.0, 0.2, 0.8);
    vec3 grass_color = vec3(0.1, 0.4, 0.1);
    vec3 dark_grass_color = vec3(0.12, 0.28, 0.12);
    vec3 rock_color = vec3(0.4, 0.3, 0.2);
    vec3 snow_color = vec3(1.0);
	
	//float micro_detail = hash3D(normalize(v_world_pos) * 500.0) * 0.04;
	//float blended_height = clamp(v_height + micro_detail, 0.0, 1.0);
	
	float to_grass = smoothstep(0.44, 0.46, v_height);
    float to_dark_grass = smoothstep(0.55, 0.58, v_height);
    float to_rock = smoothstep(0.70, 0.74, v_height);
    float to_snow = smoothstep(0.84, 0.86, v_height);
	
	vec3 final_albedo = seabed_color;
    final_albedo = mix(final_albedo, grass_color, to_grass);
    final_albedo = mix(final_albedo, dark_grass_color, to_dark_grass);
    final_albedo = mix(final_albedo, rock_color, to_rock);
    final_albedo = mix(final_albedo, snow_color, to_snow);
	
	float is_land = smoothstep(0.39, 0.41, v_height);
    SPECULAR = mix(0.4, 0.9, is_land);
    ROUGHNESS = mix(0.6, 0.3, is_land);
	
	ALBEDO = final_albedo;
}