shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix;

uniform float planet_radius;
uniform float atmosphere_radius;

vec2 ray_sphere_intersect(vec3 ray_origin, vec3 ray_dir, vec3 sphere_center, float sphere_radius)
{
    vec3 relative_origin = ray_origin - sphere_center;
    float b = dot(relative_origin, ray_dir);
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
    
    vec3 planet_center = vec3(0.0); // For planet at (0, 0, 0), which it currently is
    
    vec2 atmos_hit = ray_sphere_intersect(ray_origin, ray_dir, planet_center, atmosphere_radius);
    
    if (atmos_hit.y < 0.0) { discard; }
    
    float ray_start = max(0.0, atmos_hit.x);
    float ray_end = atmos_hit.y;
    
    float look_thickness = ray_end - ray_start;
    
    float visual_glow = smoothstep(0.0, atmosphere_radius * 0.5, look_thickness);
    
    ALBEDO = vec3(0.1, 0.5, 1.0);
    ALPHA = visual_glow * 0.6;
}