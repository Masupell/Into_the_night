shader_type spatial;

global uniform bool show_borders;
global uniform bool show_lod;
instance uniform float instance_lod_level;
// Geomorphing: from the parent's shape (CUSTOM0) to its own
global uniform float terrain_time;
instance uniform float morph_start = -1000.0;
uniform float morph_duration = 0.1;

uniform sampler2D world_map;
varying float v_height;
varying float v_moisture;
varying float v_water; // water level, same units as v_height
varying float v_surface; // v_height with the detail noise
varying vec3 v_world_pos;

uniform vec3 seabed_color: source_color = vec3(0.55, 0.48, 0.38);
uniform vec3 grass_color: source_color = vec3(0.1, 0.4, 0.1);
uniform vec3 dark_grass_color: source_color = vec3(0.12, 0.28, 0.12);
uniform vec3 forest_color: source_color = vec3(0.04, 0.25, 0.06);
uniform vec3 savanna_color: source_color = vec3(0.55, 0.5, 0.25);
uniform vec3 desert_color: source_color = vec3(0.8, 0.66, 0.44);
uniform vec3 rock_color: source_color = vec3(0.4, 0.3, 0.2);
uniform vec3 tundra_color: source_color = vec3(0.42, 0.4, 0.28);
uniform vec3 snow_color: source_color = vec3(1.0);

// Height bands in real Earth meters, the seabed color is also the beach sand
uniform float meters_per_unit = 8849.0; // set by the planet
uniform vec2 grass_band = vec2(2.0, 10.0);
uniform vec2 dark_grass_band = vec2(700.0, 885.0);
uniform vec2 rock_band = vec2(1600.0, 1770.0);

// Temperature: annual mean in °C, from latitude and height (real climate data later)
uniform float equator_temperature = 27.0;
uniform float pole_temperature = -20.0;
uniform float temperature_curve = 1.5;
uniform float lapse_rate = 6.5;
// Tundra over the grass
uniform vec2 tundra_temperature_band = vec2(3.0, -2.0);
// Snow on land
uniform vec2 snow_temperature_band = vec2(-6.0, -9.0);

// Moisture: 0 desert, 0.5 grass, 1 rainforest
uniform vec2 forest_moisture_band = vec2(0.6, 0.8);
uniform vec2 savanna_moisture_band = vec2(0.45, 0.3);
uniform vec2 desert_moisture_band = vec2(0.25, 0.1);

// 0: smooth, 1: flat triangles (low poly)
uniform float facet_amount : hint_range(0.0, 1.0) = 0.75;
// Sky light, so things facing away from the sun aren't black. Only on the day side
uniform vec3 sky_color : source_color = vec3(0.45, 0.6, 0.85);
uniform float sky_light = 0.3;
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform vec3 planet_center;

// Water color is done here on the ground, the depth buffer can't separate it from shallow ground further away.
// The water mesh only adds the reflection
uniform float planet_radius;
uniform float max_height;
uniform vec3 water_shallow : source_color = vec3(0.1, 0.7, 0.95);
uniform vec3 water_deep : source_color = vec3(0.04, 0.2, 0.7);
uniform float water_depth_scale = 8.0; // meters until it is opaque


//float hash3D(vec3 p) // fast 3d hash function I got
//{
    //p = fract(p * vec3(443.8975, 397.2973, 491.1871));
    //p += dot(p.xyz, p.yzx + 19.19);
    //return fract(p.x * p.y * p.z);
//}

void vertex()
{
	float coarse = 1.0 - smoothstep(0.0, 1.0, clamp((terrain_time - morph_start) / morph_duration, 0.0, 1.0));
	VERTEX += CUSTOM0.xyz * coarse;
    v_height = UV2.x + CUSTOM0.w * coarse; // 0 sea level, 1 max_height
	v_moisture = UV2.y;
	v_water = CUSTOM1.x;
	v_surface = CUSTOM1.y + CUSTOM1.z * coarse;
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
	float latitude = asin(clamp(abs(up.y), 0.0, 1.0)) / (PI * 0.5); // 0 equator, 1 pole
	float sea_temperature = mix(equator_temperature, pole_temperature, pow(latitude, temperature_curve));
	float temperature = sea_temperature - lapse_rate * max(meters, 0.0) / 1000.0;
	float to_tundra = smoothstep(tundra_temperature_band.x, tundra_temperature_band.y, temperature) * to_grass; // beaches stay sand
	float to_snow = smoothstep(snow_temperature_band.x, snow_temperature_band.y, temperature) * step(0.0, meters);

	// only on land
	float to_forest = smoothstep(forest_moisture_band.x, forest_moisture_band.y, v_moisture) * to_grass;
	float to_savanna = smoothstep(savanna_moisture_band.x, savanna_moisture_band.y, v_moisture) * to_grass;
	float to_desert = smoothstep(desert_moisture_band.x, desert_moisture_band.y, v_moisture) * to_grass;

	vec3 final_albedo = seabed_color;
    final_albedo = mix(final_albedo, grass_color, to_grass);
    final_albedo = mix(final_albedo, dark_grass_color, to_dark_grass);
    final_albedo = mix(final_albedo, forest_color, to_forest);
    final_albedo = mix(final_albedo, savanna_color, to_savanna);
    final_albedo = mix(final_albedo, desert_color, to_desert);
    final_albedo = mix(final_albedo, tundra_color, to_tundra);
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
	float ground_depth = (v_water - v_surface) * max_height;
	if (ground_depth > 0.0 && camera_height > v_water * max_height && !show_lod && !show_borders)
	{
		// Beer-Lambert approximation
		vec3 view_dir = normalize(v_world_pos - CAMERA_POSITION_WORLD);
		float cos_view = max(dot(-view_dir, up), 0.01);
		float depth_factor = 1.0 - exp(-ground_depth / cos_view / water_depth_scale);
		float cover = mix(0.45, 1.0, depth_factor);
		final_albedo = mix(final_albedo, mix(water_shallow, water_deep, depth_factor), cover);
		// deeper water is lit like a flat surface
		vec3 up_view = (VIEW_MATRIX * vec4(up, 0.0)).xyz;
		NORMAL = normalize(mix(NORMAL, up_view, cover));
	}

	ALBEDO = final_albedo;

	float daylight = smoothstep(-0.1, 0.15, dot(up, sun_dir));
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float sky_visible = 0.5 + 0.5 * dot(world_normal, up);
	EMISSION = final_albedo * sky_color * sky_light * daylight * sky_visible;
}
