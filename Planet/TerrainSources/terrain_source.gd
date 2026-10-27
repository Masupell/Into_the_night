class_name TerrainSource
extends RefCounted

# Fills terrain tiles. A tile is filled only from its own coordinates, never from its neighbours,
# so tiles can be made in any order (and later on other threads, or streamed in)
# Every source returns heights 0..1 with TerrainData.SEA_LEVEL as sea level, so they all fit the same shader/water

func height_at(_dir: Vector3) -> float:
	return 0.0

func fill_tile(tile: TerrainTile) -> void:
	for y in range(tile.size):
		for x in range(tile.size):
			tile.set_height(x, y, height_at(tile.pixel_to_dir(x, y)))
