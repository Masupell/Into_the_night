shader_type spatial;

varying float v_height;

void vertex()
{
    v_height = COLOR.r;
}

void fragment()
{
	SPECULAR = 0.4;
	ROUGHNESS = 0.6;
	if (v_height < 0.4)
	{
		SPECULAR = 0.9;
		ROUGHNESS = 0.3;
		ALBEDO = vec3(0.0, 0.2, 0.8); // water
    }
    else if (v_height < 0.5)
	{
        ALBEDO = vec3(0.1, 0.4, 0.1); // grass
    }
	else if (v_height < 0.65)
	{
        ALBEDO = vec3(0.12, 0.28, 0.12); // darker grass
    }
    else if (v_height < 0.7)
	{
        ALBEDO = vec3(0.4, 0.3, 0.2); // rock
    }
    else
	{
        ALBEDO = vec3(1.0); // snow
    }
}