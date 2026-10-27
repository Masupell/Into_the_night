class_name TerrainSource
extends RefCounted

# Height relative to sea level: 0 = sea level, 1 = planet.max_height above it, negative = under water
func height_at(_dir: Vector3) -> float:
	return 0.0

func fill_tile(tile: TerrainTile) -> void:
	for y in range(tile.size):
		for x in range(tile.size):
			tile.set_height(x, y, height_at(tile.pixel_to_dir(x, y)))
