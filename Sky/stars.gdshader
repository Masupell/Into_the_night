shader_type sky;

// Star map: NASA SVS Deep Star Maps 2020 (svs.gsfc.nasa.gov/4851)
// Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio, Gaia DR2: ESA/Gaia/DPAC
// Set in Sky/sky.gd. Linear HDR, so no source_color
uniform sampler2D star_map : filter_linear_mipmap, repeat_enable;
uniform float star_brightness = 1.0;
// Set by Planet.update_star_visibility
global uniform float star_visibility;

// Sun, direction from the DirectionalLight3D
uniform float sun_size_deg = 1.0; // real one is 0.53
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_energy = 20.0;
uniform float limb_darkening : hint_range(0.0, 1.0) = 0.5;
uniform float glow_energy = 0.6;
uniform float glow_width_deg = 3.0;

vec3 sun(vec3 dir, vec3 sun_dir)
{
	float angle = acos(clamp(dot(dir, sun_dir), -1.0, 1.0));
	float radius = radians(sun_size_deg) * 0.5;
	float edge = max(fwidth(angle), 1e-5);
	float disc = 1.0 - smoothstep(radius - edge, radius + edge, angle);
	float r = clamp(angle / radius, 0.0, 1.0);
	float limb = 1.0 - limb_darkening * (1.0 - sqrt(1.0 - r * r));
	float glow = glow_energy * exp(-angle / radians(glow_width_deg));
	return sun_color * (disc * limb * sun_energy + glow);
}

void sky()
{
	// Ambient and reflections don't come from the sky
	if (AT_CUBEMAP_PASS) {
		COLOR = vec3(0.0);
	} else {
		vec3 dir = normalize(EYEDIR);
		vec3 sun_dir = LIGHT0_DIRECTION;

		// The sun goes around the planet, so the stars turn with it
		float sun_angle = atan(sun_dir.z, sun_dir.x);
		float c = cos(sun_angle);
		float s = sin(sun_angle);
		vec3 star_dir = vec3(dir.x * c + dir.z * s, dir.y, dir.z * c - dir.x * s);

		// Celestial north is -Y, right ascension 0h along +X
		float declination = asin(clamp(-star_dir.y, -1.0, 1.0));
		float right_ascension = atan(star_dir.z, star_dir.x);
		// Seen from the inside, so growing to the left
		vec2 uv = vec2(0.5 - right_ascension / TAU, 0.5 - declination / PI);
		// Mip level from the pixel angle, uv based blurs the poles and shows a seam
		float pixel_angle = max(length(dFdx(dir)), length(dFdy(dir)));
		float lod = log2(max(pixel_angle * float(textureSize(star_map, 0).y) / PI, 1e-6));
		vec3 stars = textureLod(star_map, uv, lod).rgb * star_brightness * star_visibility;

		COLOR = stars + (LIGHT0_ENABLED ? sun(dir, sun_dir) : vec3(0.0));
	}
}
