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

// Height bands in real Earth meters (v_height * meters_per_unit), blending from the first to the second value.
// The seabed color also is the sand of the beaches
uniform float meters_per_unit = 8849.0; // set by the planet (earth_meters_per_unit): real meters that are v_height 1
uniform vec2 grass_band = vec2(2.0, 10.0);
uniform vec2 dark_grass_band = vec2(700.0, 885.0);
uniform vec2 rock_band = vec2(1600.0, 1770.0);

// Temperature: annual mean in °C, from the latitude and the height (for now, real climate data later)
// sea level: equator_temperature at the equator down to pole_temperature at the poles, temperature_curve shapes it
// (1.5: about 18 °C at 30°, 10 °C at 45°, 1 °C at 60°), then it gets colder by lapse_rate per real km up
uniform float equator_temperature = 27.0;
uniform float pole_temperature = -20.0;
uniform float temperature_curve = 1.5;
uniform float lapse_rate = 6.5;
// Snow (and ice) on land from the first to the second temperature
uniform vec2 snow_temperature_band = vec2(-6.0, -9.0);

// 0: smooth terrain normals from the mesh, 1: flat triangles (low poly look)
uniform float facet_amount : hint_range(0.0, 1.0) = 0.75;
// Light from the whole sky, not only the sun: without it everything facing away from the sun is black.
// Only on the day side, strongest on surfaces facing up. sun_dir and planet_center are set by the planet every frame
uniform vec3 sky_color : source_color = vec3(0.45, 0.6, 0.85);
uniform float sky_light = 0.3;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 planet_center;

// Water: the ground below sea level gets the color of the water in front of it here, not by the water surface mesh.
// The depth buffer can't separate a water surface from ground a few dm below it further away (the water disappeared
// over shallow ground), this works at any distance. The water mesh only adds the reflection (water.gdshader)
uniform float planet_radius; // set by the planet
uniform float max_height; // set by the planet
uniform vec3 water_shallow : source_color = vec3(0.1, 0.7, 0.95);
uniform vec3 water_deep : source_color = vec3(0.04, 0.2, 0.7);
uniform float water_depth_scale = 8.0; // meters of water along the view until it is mostly deep colored and opaque


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
	float meters = v_height * meters_per_unit;
	float to_grass = smoothstep(grass_band.x, grass_band.y, meters);
	float to_dark_grass = smoothstep(dark_grass_band.x, dark_grass_band.y, meters);
	float to_rock = smoothstep(rock_band.x, rock_band.y, meters);

	vec3 up = normalize(v_world_pos - planet_center);
	float latitude = asin(clamp(abs(up.y), 0.0, 1.0)) / (PI * 0.5); // 0 equator, 1 pole (the planet never rotates)
	float sea_temperature = mix(equator_temperature, pole_temperature, pow(latitude, temperature_curve));
	float temperature = sea_temperature - lapse_rate * max(meters, 0.0) / 1000.0;
	float to_snow = smoothstep(snow_temperature_band.x, snow_temperature_band.y, temperature) * step(0.0, meters);

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

	float camera_height = length(CAMERA_POSITION_WORLD - planet_center) - planet_radius;
	if (v_height < 0.0 && camera_height > 0.0 && !show_lod && !show_borders)
	{
		// the view goes down through the water at an angle until it reaches this ground (Beer-Lambert approximation)
		float ground_depth = -v_height * max_height; // no detail noise below sea level, so this is exact at the vertices
		vec3 view_dir = normalize(v_world_pos - CAMERA_POSITION_WORLD);
		float cos_view = max(dot(-view_dir, up), 0.01);
		float depth_factor = 1.0 - exp(-ground_depth / cos_view / water_depth_scale);
		float cover = mix(0.45, 1.0, depth_factor);
		final_albedo = mix(final_albedo, mix(water_shallow, water_deep, depth_factor), cover);
		// the more water in front, the more it is lit like a flat water surface instead of the ground below
		vec3 up_view = (VIEW_MATRIX * vec4(up, 0.0)).xyz;
		NORMAL = normalize(mix(NORMAL, up_view, cover));
	}

	ALBEDO = final_albedo;

	float daylight = smoothstep(-0.1, 0.15, dot(up, sun_dir)); // fades out over dusk
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float sky_visible = 0.5 + 0.5 * dot(world_normal, up); // a wall sees half the sky, an overhang less
	EMISSION = final_albedo * sky_color * sky_light * daylight * sky_visible;
}
