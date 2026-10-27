class_name NoiseSource
extends TerrainSource

# Procedural continents and mountains from a seed (was Planet.generate_world_texture)
const COAST_HEIGHT := 0.40 # where ocean ends and land starts in the raw values below, gets remapped to TerrainData.SEA_LEVEL

var continent_noise := FastNoiseLite.new()
var mountain_noise := FastNoiseLite.new()

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

# Moves the coast from COAST_HEIGHT to TerrainData.SEA_LEVEL, ocean and land are each stretched linearly
static func remap_to_sea_level(h: float) -> float:
	if h < COAST_HEIGHT:
		return h / COAST_HEIGHT * TerrainData.SEA_LEVEL
	return TerrainData.SEA_LEVEL + (h - COAST_HEIGHT) / (1.0 - COAST_HEIGHT) * (1.0 - TerrainData.SEA_LEVEL)
