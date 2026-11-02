class_name TerrainSource
extends RefCounted

# 0 sea level, 1 planet.max_height, negative under water
func height_at(_dir: Vector3) -> float:
	return 0.0

# 0 desert, 1 rainforest, 0.5 grass by default
func moisture_at(_dir: Vector3) -> float:
	return 0.5

func fill_tile(tile: TerrainTile) -> void:
	fill_heights(tile)
	fill_moisture(tile)

func fill_heights(tile: TerrainTile) -> void:
	for y in range(tile.size):
		for x in range(tile.size):
			tile.set_height(x, y, height_at(tile.pixel_to_dir(x, y)))

func fill_moisture(tile: TerrainTile) -> void:
	var n := TerrainTile.MOISTURE_SIZE
	for y in range(n):
		for x in range(n):
			tile.moisture[x + y * n] = moisture_at(tile.moisture_pixel_to_dir(x, y))
