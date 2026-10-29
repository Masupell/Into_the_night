shader_type spatial;
render_mode cull_front, unshaded, blend_premul_alpha, depth_test_disabled, skip_vertex_transform;

// Single scattering: along the view ray, sunlight reaches each point dimmed by the air it went through on the way
// (blue is scattered much more than red, so a long way through the air leaves it red: sunsets), is scattered
// towards the camera there, and dimmed again on the way to the camera.
// Rayleigh (small molecules): blue sky, scatters forward and backward alike.
// Mie (haze, dust): grey, scatters mostly forward, the bright glow around the sun.

uniform float planet_radius;
uniform float atmosphere_radius;
uniform vec3 sun_dir;
uniform float max_draw_distance = 10000.0; // set from the cameras far plane, see Planet.update_camera_planes

// How much light goes missing straight up from sea level to space, per color (Earth: about 0.05, 0.12, 0.29).
// Higher = deeper blue, but also more haze seen from space and a reddish horizon (long way through the air to the camera)
uniform vec3 rayleigh_depth = vec3(0.05, 0.12, 0.29);
// Extra air only on the sunlight's way to each point, not on the way to the camera: the planet is small, so near
// the horizon the sunlight goes through much less air than on Earth (~15x the way straight up instead of ~38x),
// sunsets wouldn't get red without it. Depends on planet radius / atmosphere height, retune when those change
uniform float sun_reddening = 2.5;
// Ozone only absorbs, mostly green-orange, and only counted on the sunlight's way. It is what keeps the sky blue at dusk
// instead of olive (Earth: ~0.01, 0.028, 0.0013, here 2x because it is spread like the air instead of a layer up high)
uniform vec3 ozone_depth = vec3(0.02, 0.056, 0.0026);
// Reddish sunlight (dawn, dusk) only shows its color towards the sun, away from it it keeps its brightness but gets grey.
// On Earth there is a pink band opposite the sun at dusk, 0 keeps it
uniform float away_desaturation : hint_range(0.0, 1.0) = 0.85;
uniform float mie_depth = 0.02;
uniform float mie_g : hint_range(0.0, 0.99) = 0.76; // how strongly haze scatters forward (glow size around the sun)
uniform float sun_intensity = 22.0;
// Seen from above the atmosphere, the haze lies over the sunlit ground instead of black space and would look milky,
// so it gets darker the further up the camera is (full brightness up to 30% of the atmosphere, this from its top on)
uniform float space_brightness : hint_range(0.0, 1.0) = 0.4;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

const int SAMPLE_COUNT = 12;
const float DENSITY_FALLOFF = 4.5; // atmosphere thickness / scale height of the air (density 1/e every scale height)
const float MIE_SCALE = 0.2; // haze stays lower than the air

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

// Air between a point and space in one direction, in scale heights times the density at the ground
// (straight up from sea level it is 1). Chapman function approximation (C. Schueler, GPU Pro 3), works down to
// the horizon and a bit below it. x: planet radius / scale height, h: height / scale height, cos_zenith of the direction
float chapman(float x, float h, float cos_zenith)
{
	float c = sqrt(x + h);
	if (cos_zenith >= 0.0) {
		return c / (c * cos_zenith + 1.0) * exp(-h);
	}
	float x0 = sqrt(1.0 - cos_zenith * cos_zenith) * (x + h);
	float c0 = sqrt(x0);
	return 2.0 * c0 * exp(min(x - x0, 30.0)) - c / (1.0 - c * cos_zenith) * exp(-h);
}

// The back faces (far side of the sphere, behind the planet) can be further away than the far plane.
// Vertices beyond max_draw_distance are moved towards the camera along their view ray, so they stay on the same pixel
// and the fragment shader still runs everywhere, it only uses the ray direction, the atmosphere itself is ray traced
void vertex()
{
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(VERTEX);
	if (dist > max_draw_distance) {
		VERTEX *= max_draw_distance / dist;
	}
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

	// The water isn't in the depth buffer (transparent), so above water the view ends at the sea surface, not at the
	// sea floor. Otherwise underwater mountains get less haze than the valleys between them and show through the water
	if (length(ray_origin - planet_center) > planet_radius) {
		vec2 sea_hit = ray_sphere_intersect(ray_origin, ray_dir, planet_center, planet_radius);
		if (sea_hit.x > 0.0) ray_end = min(ray_end, sea_hit.x);
	}

	float path_length = ray_end - ray_start;
	if (path_length <= 0.0) discard;

	float thickness = max(1.0, atmosphere_radius - planet_radius);
	float rayleigh_height = thickness / DENSITY_FALLOFF;
	float mie_height = rayleigh_height * MIE_SCALE;
	// scattering per meter at sea level, so that straight up adds up to rayleigh_depth / mie_depth
	float rayleigh_column = rayleigh_height * (1.0 - exp(-thickness / rayleigh_height));
	vec3 rayleigh_coeff = rayleigh_depth / rayleigh_column;
	vec3 sun_extinction = (rayleigh_depth * sun_reddening + ozone_depth) / rayleigh_column; // on the sunlight's way only
	float mie_coeff = mie_depth / (mie_height * (1.0 - exp(-thickness / mie_height)));

	// how much of the light is scattered from the sun towards the camera (phase functions)
	float cos_angle = dot(ray_dir, sun_dir);
	float rayleigh_phase = 3.0 / (16.0 * PI) * (1.0 + cos_angle * cos_angle);
	float g2 = mie_g * mie_g;
	float mie_phase = (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * mie_g * cos_angle, 1.5));

	// how much of the sunlight's color is kept, full towards the sun
	float color_keep = mix(1.0 - away_desaturation, 1.0, smoothstep(-0.2, 0.7, cos_angle));

	float step_size = path_length / float(SAMPLE_COUNT);
	vec3 view_depth = vec3(0.0); // air between the camera and the current sample, as optical depth per color
	vec3 light = vec3(0.0);

	for (int i = 0; i < SAMPLE_COUNT; i++)
	{
		vec3 sample_pos = ray_origin + ray_dir * (ray_start + (float(i) + 0.5) * step_size);
		vec3 to_sample = sample_pos - planet_center;
		float sample_radius = length(to_sample);
		float height = max(0.0, sample_radius - planet_radius);

		float rayleigh_density = exp(-height / rayleigh_height);
		float mie_density = exp(-height / mie_height);
		vec3 extinction = rayleigh_coeff * rayleigh_density + mie_coeff * mie_density * 1.1; // haze also absorbs a bit
		vec3 view_transmittance = exp(-(view_depth + extinction * step_size * 0.5));
		view_depth += extinction * step_size;

		// in the planet's shadow no sunlight arrives at all
		vec2 shadow = ray_sphere_intersect(sample_pos, sun_dir, planet_center, planet_radius);
		if (shadow.x > 0.0) continue;

		// sunlight that is left after its way through the air to this point
		float cos_zenith = dot(to_sample / sample_radius, sun_dir);
		vec3 sun_depth = sun_extinction * rayleigh_height * chapman(planet_radius / rayleigh_height, height / rayleigh_height, cos_zenith)
			+ mie_coeff * 1.1 * mie_height * chapman(planet_radius / mie_height, height / mie_height, cos_zenith);
		vec3 sun_transmittance = exp(-sun_depth);
		float brightness = dot(sun_transmittance, vec3(0.2126, 0.7152, 0.0722));
		sun_transmittance = mix(vec3(brightness), sun_transmittance, color_keep);

		vec3 scattering = rayleigh_coeff * rayleigh_density * rayleigh_phase + mie_coeff * mie_density * mie_phase;
		light += scattering * sun_transmittance * view_transmittance * step_size;
	}

	float camera_height = length(ray_origin - planet_center) - planet_radius;
	light *= sun_intensity * mix(1.0, space_brightness, smoothstep(0.3 * thickness, thickness, camera_height));
	vec3 transmittance = exp(-view_depth);
	float alpha = 1.0 - (transmittance.r + transmittance.g + transmittance.b) / 3.0;
	if (alpha < 0.0001 && max(light.r, max(light.g, light.b)) < 0.0001) discard;

	// premultiplied: the result is light + what is behind * (1 - alpha), the terrain behind gets dimmed by the air
	ALBEDO = light;
	ALPHA = alpha;
}
