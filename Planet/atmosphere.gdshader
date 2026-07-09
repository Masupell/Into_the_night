
shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_test_disabled;

uniform float planet_radius;
uniform float atmosphere_radius;
uniform vec3 sun_dir; 
uniform float atmosphere_density_mult : hint_range(0.1, 5.0) = 0.4;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

const int SAMPLE_COUNT = 6;
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
    vec3 ray_origin = CAMERA_POSITION_WORLD;
    vec3 world_vertex = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 ray_dir = normalize(world_vertex - ray_origin);
    vec3 planet_center = vec3(0.0);
    
    vec2 atmos_hit = ray_sphere_intersect(ray_origin, ray_dir, planet_center, atmosphere_radius);
    if (atmos_hit.y < 0.0) discard; 
    
    float ray_start = max(0.0, atmos_hit.x);
    float ray_end = atmos_hit.y;
    
    float depth = texture(depth_texture, SCREEN_UV).x;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    vec3 world_terrain_pos = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
    
    float terrain_dist = length(world_terrain_pos - ray_origin);
    
    ray_end = min(ray_end, terrain_dist);
    
    float view_sun_dot = dot(ray_dir, sun_dir);
    
    float path_length = ray_end - ray_start;
    if (path_length <= 0.0) discard;
    
    float step_size = path_length / float(SAMPLE_COUNT);
    
    vec3 accumulated_color = vec3(0.0);
    float accumulated_alpha = 0.0;
    
    vec3 scattered_blue = vec3(0.1, 0.4, 0.9);
    vec3 sunset_red = vec3(1.0, 0.3, 0.02);
    
	float forward_scatter = pow(max(0.0, view_sun_dot), 6.0) * 3.5;
	
    for (int i = 0; i < SAMPLE_COUNT; i++)
	{
        float t = ray_start + (float(i) + 0.5) * step_size;
        vec3 sample_pos = ray_origin + ray_dir * t;
        
        float current_height = length(sample_pos) - planet_radius;
        float height_factor = clamp(current_height / (atmosphere_radius - planet_radius), 0.0, 1.0);
        
        float local_density = exp(-height_factor * DENSITY_FALLOFF) * step_size * 0.01;
        
        vec3 surface_normal = normalize(sample_pos);
        float sun_angle = dot(surface_normal, sun_dir);
        
        float light_intensity = smoothstep(-0.1, 0.2, sun_angle);

        if (light_intensity > 0.0)
		{
            vec2 shadow_check = ray_sphere_intersect(sample_pos, sun_dir, planet_center, planet_radius);
            if (shadow_check.x > 0.0)
			{
                light_intensity = 0.0;
            }
        }
        
		// Not sure, if I will keep it or not
		//light_intensity = max(0.1, light_intensity); // for slight glow at night
		
        float sunset_factor = smoothstep(0.25, -0.15, sun_angle);
        vec3 current_air_color = mix(scattered_blue, sunset_red, sunset_factor);
		current_air_color += sunset_red * sunset_factor * forward_scatter;
        
        accumulated_color += current_air_color * local_density * light_intensity;
        accumulated_alpha += local_density;
    }
    
    ALBEDO = accumulated_color;
    ALPHA = 1.0 - exp(-accumulated_alpha * atmosphere_density_mult);
}