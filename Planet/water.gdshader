shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform vec3 color_shallow : source_color = vec3(0.0, 0.45, 0.55);
uniform vec3 color_deep : source_color = vec3(0.01, 0.05, 0.2);
uniform float depth_scale = 8.0;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable;

void fragment()
{
    float depth_raw = texture(depth_texture, SCREEN_UV).r;
    vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
    vec3 pixel_position = upos.xyz / upos.w;
    
    float depth_difference = VERTEX.z - pixel_position.z;
    depth_difference = max(0.0, depth_difference);

	// Beer-Lambert law approximation
    float depth_factor = 1.0 - exp(-depth_difference / depth_scale);
    
    vec3 final_color = mix(color_shallow, color_deep, depth_factor);
    float final_alpha = mix(0.35, 1.0, depth_factor);
    
    ALBEDO = final_color;
    ALPHA = final_alpha;
    
    ROUGHNESS = 0.1;  // Once I have an atmosphere
    SPECULAR = 0.9;
	
	//ROUGHNESS = 0.22;
    //SPECULAR = 0.5;
	
	EMISSION = final_color; // While I don't have an atmosphere, so it does not reflect black back
}