class_name NoiseSource
extends TerrainSource

# Procedural continents and mountains from a seed
const COAST_HEIGHT := 0.40 # becomes sea level (0)
const OCEAN_DEPTH := 0.08 # deepest ocean after remapping, same as the old earth map

var continent_noise := FastNoiseLite.new()
var mountain_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var climate_shift_noise := FastNoiseLite.new()

func _init(planet_seed: int) -> void:
	continent_noise.seed = planet_seed
	continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	continent_noise.frequency = 0.004
	continent_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	continent_noise.fractal_octaves = 5
	continent_noise.fractal_lacunarity = 2.0
	continent_noise.fractal_gain = 0.55

	mountain_noise.seed = planet_seed + 1234 # so it is not same seed as continents
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mountain_noise.frequency = 0.007
	mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	mountain_noise.fractal_octaves = 4
	mountain_noise.fractal_gain = 0.6

	# both large and smooth: climate changes over hundreds of km
	moisture_noise.seed = planet_seed + 5678
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture_noise.frequency = 0.006
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 3

	climate_shift_noise.seed = planet_seed + 8765
	climate_shift_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	climate_shift_noise.frequency = 0.004
	climate_shift_noise.fractal_type = FastNoiseLite.FRACTAL_NONE

func height_at(dir: Vector3) -> float:
	var sphere_point = dir * 150.0
	var continent_value = (continent_noise.get_noise_3dv(sphere_point) + 1.0) * 0.5

	var final_height = 0.0
	var sea_level = 0.46

	if continent_value < sea_level:
		var ocean_ratio = continent_value / sea_level
		final_height = lerp(0.1, COAST_HEIGHT, ocean_ratio)
	else:
		var land_progress = (continent_value - sea_level) / (1.0 - sea_level)
		var coastal_profile = (mountain_noise.get_noise_3dv(sphere_point * 0.3) + 1.0) * 0.5
		var shoreline_start = lerp(COAST_HEIGHT, 0.44, coastal_profile)
		var land_elevation = shoreline_start + (land_progress * 0.2)
		var mountain_mask = smoothstep(0.52, 0.62, continent_value)
		var mountain_value = (mountain_noise.get_noise_3dv(sphere_point * 1.5) + 1.0) * 0.5
		mountain_value = pow(mountain_value, 1.8)
		var headroom = 1.0 - land_elevation
		var allowed_mountain_height = mountain_value * headroom * mountain_mask * 0.96
		final_height = land_elevation + allowed_mountain_height

	final_height = clamp(final_height, 0.0, 1.0)
	return remap_to_sea_level(final_height)

# Bands like the Earth's air circulation: wet at the equator, dry at ~30° (Sahara, Australia), wet again at ~60°,
# dry at the poles. cos(6 * latitude) has exactly those highs and lows, mid latitudes a bit drier than the equator.
# climate_shift_noise moves the bands up to ~10° north/south so they aren't straight stripes,
# moisture_noise adds wetter and drier regions, and land far from the sea gets drier (continent value as a cheap
# stand-in for the distance to the coast, real distances / rain shadows need the one-time world generation)
func moisture_at(dir: Vector3) -> float:
	var sphere_point = dir * 150.0
	var latitude = absf(asin(clampf(dir.y, -1.0, 1.0)))
	latitude += climate_shift_noise.get_noise_3dv(sphere_point) * deg_to_rad(10.0)
	var bands = 0.52 + 0.35 * cos(6.0 * latitude) - 0.1 * latitude / (PI * 0.5)

	var regional = moisture_noise.get_noise_3dv(sphere_point) * 0.35

	var continent_value = (continent_noise.get_noise_3dv(sphere_point) + 1.0) * 0.5
	var inland = smoothstep(0.46, 0.6, continent_value) * 0.15 # 0.46 is the coast in height_at

	return clampf(bands + regional - inland, 0.0, 1.0)

# Moves the coast from COAST_HEIGHT to 0, ocean becomes -OCEAN_DEPTH..0 and land 0..1
static func remap_to_sea_level(h: float) -> float:
	if h < COAST_HEIGHT:
		return (h / COAST_HEIGHT - 1.0) * OCEAN_DEPTH
	return (h - COAST_HEIGHT) / (1.0 - COAST_HEIGHT)
