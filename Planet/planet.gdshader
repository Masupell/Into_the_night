shader_type spatial;

global uniform bool show_borders;
global uniform bool show_lod;
instance uniform float instance_lod_level;

uniform sampler2D world_map;
varying float v_height;
varying vec3 v_world_pos;

uniform vec3 seabed_color: source_color = vec3(0.55, 0.48, 0.38);
uniform vec3 grass_color: source_color = vec3(0.1, 0.4, 0.1);
uniform vec3 dark_grass_color: source_color = vec3(0.12, 0.28, 0.12);
uniform vec3 rock_color: source_color = vec3(0.4, 0.3, 0.2);
uniform vec3 snow_color: source_color = vec3(1.0);

// 0: smooth terrain normals from the mesh, 1: flat triangles (low poly look)
uniform float facet_amount : hint_range(0.0, 1.0) = 0.75;
// Light from the whole sky, not only the sun: without it everything facing away from the sun is black.
// Only on the day side, strongest on surfaces facing up. sun_dir and planet_center are set by the planet every frame
uniform vec3 sky_color : source_color = vec3(0.45, 0.6, 0.85);
uniform float sky_light = 0.3;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 planet_center;


//float hash3D(vec3 p) // fast 3d hash function I got
//{
    //p = fract(p * vec3(443.8975, 397.2973, 491.1871));
    //p += dot(p.xyz, p.yzx + 19.19);
    //return fract(p.x * p.y * p.z);
//}

void vertex()
{
    v_height = UV2.x; // height relative to sea level (0), 1 = max_height
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment()
{
	vec3 face_normal = normalize(cross(dFdy(VERTEX), dFdx(VERTEX))); //inverted because of mesh winding order
	NORMAL = normalize(mix(NORMAL, face_normal, facet_amount));
	SPECULAR = 0.1;
	ROUGHNESS = 0.8;


	//float micro_detail = hash3D(normalize(v_world_pos) * 500.0) * 0.04;
	//float blended_height = clamp(v_height + micro_detail, 0.0, 1.0);

	//float to_grass = smoothstep(0.44, 0.46, v_height);
    //float to_dark_grass = smoothstep(0.55, 0.58, v_height);
    //float to_rock = smoothstep(0.70, 0.74, v_height);
    //float to_snow = smoothstep(0.84, 0.86, v_height);
	// same bands as before, moved down by the old earth map sea level (0.08)
	float to_grass = smoothstep(-0.01, 0.02, v_height);
    float to_dark_grass = smoothstep(0.08, 0.10, v_height);
    float to_rock = smoothstep(0.18, 0.20, v_height);
    float to_snow = smoothstep(0.37, 0.39, v_height);

	vec3 final_albedo = seabed_color;
    final_albedo = mix(final_albedo, grass_color, to_grass);
    final_albedo = mix(final_albedo, dark_grass_color, to_dark_grass);
    final_albedo = mix(final_albedo, rock_color, to_rock);
    final_albedo = mix(final_albedo, snow_color, to_snow);

	// -- Debug --
	if (show_lod)
	{
		vec3 lod_colors[9] = vec3[](
			vec3(0.9, 0.1, 0.1), // L0: Red
			vec3(0.9, 0.5, 0.1), // L1: Orange
			vec3(0.9, 0.9, 0.1), // L2: Yellow
			vec3(0.1, 0.9, 0.1), // L3: Green
			vec3(0.1, 0.9, 0.9), // L4: Cyan
			vec3(0.1, 0.3, 0.9), // L5: Blue
			vec3(0.6, 0.1, 0.9), // L6: Purple
			vec3(0.9, 0.1, 0.6), // L7: Magenta
			vec3(0.4, 0.4, 0.4)  // L8+: Gray
		);
		int lod_idx = clamp(int(instance_lod_level), 0, 8);
		final_albedo = mix(final_albedo, lod_colors[lod_idx], 0.75);
	}

	if (show_borders)
	{
		vec2 pixel_width = fwidth(UV) * 2.0;
	    vec2 edge_bottom_left = smoothstep(vec2(0.0), pixel_width, UV);
	    vec2 edge_top_right = smoothstep(vec2(1.0), vec2(1.0) - pixel_width, UV);
	    float is_border = 1.0 - (edge_bottom_left.x * edge_bottom_left.y * edge_top_right.x * edge_top_right.y);
	    final_albedo = mix(final_albedo, vec3(1.0, 1.0, 1.0), is_border);
	}

	ALBEDO = final_albedo;

	vec3 up = normalize(v_world_pos - planet_center);
	float daylight = smoothstep(-0.1, 0.15, dot(up, sun_dir)); // fades out over dusk
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float sky_visible = 0.5 + 0.5 * dot(world_normal, up); // a wall sees half the sky, an overhang less
	EMISSION = final_albedo * sky_color * sky_light * daylight * sky_visible;
}
