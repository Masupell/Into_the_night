shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// Only the reflection, the water color is done in planet.gdshader
uniform vec3 reflection_color : source_color = vec3(0.55, 0.7, 0.9);
uniform float base_reflectance = 0.02;

void fragment()
{
	float cos_view = clamp(dot(normalize(-VERTEX), NORMAL), 0.0, 1.0);
	float fresnel = base_reflectance + (1.0 - base_reflectance) * pow(1.0 - cos_view, 5.0); // Schlick

	ALBEDO = reflection_color;
	ALPHA = fresnel;
	ROUGHNESS = 0.1;
	SPECULAR = 0.9; // sun glints
}
