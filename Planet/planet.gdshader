shader_type spatial;

uniform sampler2D world_map;
varying float v_height;
varying vec3 v_world_pos;

float hash3D(vec3 p) // fast 3d hash function I got
{
    p = fract(p * vec3(443.8975, 397.2973, 491.1871));
    p += dot(p.xyz, p.yzx + 19.19);
    return fract(p.x * p.y * p.z);
}

void vertex()
{
    v_height = COLOR.r;
	v_world_pos = VERTEX;
}

void fragment()
{
	SPECULAR = 0.4;
	ROUGHNESS = 0.6;
	
	float micro_detail = hash3D(normalize(v_world_pos) * 500.0) * 0.04;
	float blended_height = clamp(v_height + micro_detail, 0.0, 1.0);
	
	if (blended_height < 0.4)
	{
		SPECULAR = 0.9;
		ROUGHNESS = 0.3;
		ALBEDO = vec3(0.0, 0.2, 0.8) + (micro_detail * 0.2); // water
    }
    else if (blended_height < 0.5)
	{
        ALBEDO = vec3(0.1, 0.4, 0.1) - (micro_detail * 0.3);; // grass
    }
	else if (blended_height < 0.65)
	{
        ALBEDO = vec3(0.12, 0.28, 0.12) - (micro_detail * 0.3);; // darker grass
    }
    else if (blended_height < 0.7)
	{
        ALBEDO = vec3(0.4, 0.3, 0.2) + (micro_detail * 0.5); // rock
    }
    else
	{
        ALBEDO = vec3(1.0) - (micro_detail * 0.1); // snow
    }
}