shader_type spatial;
render_mode cull_front, unshaded, blend_mix, depth_test_disabled;

uniform float planet_radius;
uniform float atmosphere_radius;
uniform vec3 sun_dir; 
uniform float atmosphere_density_mult : hint_range(0.1, 5.0) = 1.5;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

const int SAMPLE_COUNT = 12; // 6 seems fine as well though
const float DENSITY_FALLOFF = 4.5;

vec2 ray_sphere_intersect(vec3 ray_origin, vec3 ray_dir_vector, vec3 sphere_center, float sphere_radius)
{
	vec3 relative_origin = ray_origin - sphere_center;
	float b = dot(relative_origin, ray_dir_vector);
	float c = dot(relative_origin, relative_origin) - (sphere_radius * sphere_radius);
	float d = b * b - c;

	if (d < 0.0) return vec2(-1.0);

	float sqrt_d = sqrt(d);
	return vec2(-b - sqrt_d, -b + sqrt_d);
}

void fragment()
{
	vec3 planet_center = NODE_POSITION_WORLD;
	
	vec3 ray_origin = CAMERA_POSITION_WORLD;
	vec3 world_vertex = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 ray_dir = normalize(world_vertex - ray_origin);
	
	vec2 atmos_hit = ray_sphere_intersect(ray_origin, ray_dir, planet_center, atmosphere_radius);
	if (atmos_hit.y < 0.0) discard; 
	
	float ray_start = max(0.0, atmos_hit.x);
	float ray_end = atmos_hit.y;
	
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float terrain_dist = length(view.xyz);
	
	ray_end = min(ray_end, terrain_dist);
	
	float path_length = ray_end - ray_start;
	if (path_length <= 0.0) discard;
	
	float step_size = path_length / float(SAMPLE_COUNT);
	float atmos_thickness = max(1.0, atmosphere_radius - planet_radius);
	float step_factor = step_size / atmos_thickness;
	
	float view_sun_dot = dot(ray_dir, sun_dir);
	float forward_scatter = pow(max(0.0, view_sun_dot), 6.0) * 2.5;
	
	vec3 scattered_blue = vec3(0.1, 0.45, 0.95);
	vec3 sunset_red = vec3(1.0, 0.35, 0.05);
	
	vec3 accumulated_light = vec3(0.0);
	float accumulated_density = 0.0;
	
	for (int i = 0; i < SAMPLE_COUNT; i++)
	{
	    float t = ray_start + (float(i) + 0.5) * step_size;
	    vec3 sample_pos = ray_origin + ray_dir * t;
	    
	    float current_height = length(sample_pos - planet_center) - planet_radius;
	    float height_factor = clamp(current_height / atmos_thickness, 0.0, 1.0);
	    
	    float density = exp(-height_factor * DENSITY_FALLOFF) * pow(1.0 - height_factor, 2.0) * step_factor;
	    
	    vec3 surface_normal = normalize(sample_pos - planet_center);
	    float sun_angle = dot(surface_normal, sun_dir);
	    float light_intensity = smoothstep(-0.15, 0.25, sun_angle);

	    if (light_intensity > 0.0)
	    {
	        vec2 shadow_check = ray_sphere_intersect(sample_pos, sun_dir, planet_center, planet_radius);
	        if (shadow_check.x > 0.0)
	        {
	            light_intensity = 0.0;
	        }
	    }
	    
	    float sunset_factor = smoothstep(0.3, -0.1, sun_angle);
	    vec3 current_air_color = mix(scattered_blue, sunset_red, sunset_factor);
	    current_air_color += sunset_red * sunset_factor * forward_scatter;
	    
	    accumulated_light += current_air_color * density * light_intensity;
	    accumulated_density += density;
	}

	if (accumulated_density <= 0.0001) discard;

	vec3 final_color = accumulated_light / accumulated_density;
	float alpha = 1.0 - exp(-accumulated_density * atmosphere_density_mult);

	ALBEDO = final_color;
	ALPHA = alpha;
}
