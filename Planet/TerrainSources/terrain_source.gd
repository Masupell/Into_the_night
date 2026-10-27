class_name TerrainSource
extends RefCounted

func height_at(_dir: Vector3) -> float:
	return 0.0

func fill_tile(tile: TerrainTile) -> void:
	for y in range(tile.size):
		for x in range(tile.size):
			tile.set_height(x, y, height_at(tile.pixel_to_dir(x, y)))
