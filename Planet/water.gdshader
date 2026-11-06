shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// Only the reflection, the water color is done in planet.gdshader
uniform vec3 reflection_color : source_color = vec3(0.55, 0.7, 0.9);
uniform float base_reflectance = 0.02;
// Shallow water has no reflection, the depth buffer can't separate it from the ground
uniform float depth_fade_per_distance = 0.002;
varying float v_depth;

void vertex()
{
	v_depth = UV2.x;
}

void fragment()
{
	float cos_view = clamp(dot(normalize(-VERTEX), NORMAL), 0.0, 1.0);
	float fresnel = base_reflectance + (1.0 - base_reflectance) * pow(1.0 - cos_view, 5.0); // Schlick

	ALBEDO = reflection_color;
	ALPHA = fresnel * smoothstep(0.0, 0.1 + depth_fade_per_distance * length(VERTEX), v_depth);
	ROUGHNESS = 0.1;
	SPECULAR = 0.9; // sun glints
}
