shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// Only the reflection of the water surface: the color of the water itself (depth, how far you see into it) is done
// by the terrain shader on the ground below sea level, see planet.gdshader. Further away the depth buffer can't tell
// this surface and shallow ground under it apart, then this reflection may be missing, but the water is still there
uniform vec3 reflection_color : source_color = vec3(0.55, 0.7, 0.9); // the sky it reflects
uniform float base_reflectance = 0.02; // water reflects 2% looking straight down, nearly all looking along it (Fresnel)

void fragment()
{
	float cos_view = clamp(dot(normalize(-VERTEX), NORMAL), 0.0, 1.0);
	float fresnel = base_reflectance + (1.0 - base_reflectance) * pow(1.0 - cos_view, 5.0); // Schlick

	ALBEDO = reflection_color;
	ALPHA = fresnel;
	ROUGHNESS = 0.1;
	SPECULAR = 0.9; // sun glints
}
