class_name DiskSource
extends TerrainSource

# Tiles baked by tools/bake_tiles.py, read one at a time, so only loaded tiles are in memory
# Every fill_tile opens its own FileAccess, so tiles can load on several threads at once
var path: String
var meters_per_unit: float # meters that become 1.0 (= planet.max_height)
var tile_size: int
var max_level: int
var tile_bytes: int
var level_offsets: PackedInt64Array

func _init(_path: String, _meters_per_unit: float) -> void:
	path = _path + ".bin"
	meters_per_unit = _meters_per_unit

	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path + ".json"))
	assert(info["format"] == "int16_le_meters", "DiskSource: unknown format %s" % info["format"])
	tile_size = int(info["tile_size"])
	max_level = int(info["max_level"])
	tile_bytes = int(info["tile_bytes"])
	for entry in info["levels"]:
		level_offsets.append(int(entry["offset"]))

func fill_tile(tile: TerrainTile) -> void:
	assert(tile.size == tile_size and tile.level <= max_level, "DiskSource: tile does not match the baked data")
	var n := tile.tiles_per_face
	var index := (tile.face * n + tile.tile_y) * n + tile.tile_x

	var file := FileAccess.open(path, FileAccess.READ)
	file.seek(level_offsets[tile.level] + index * tile_bytes)
	var bytes := file.get_buffer(tile_bytes)

	for i in range(tile_size * tile_size):
		tile.heights[i] = bytes.decode_s16(i * 2) / meters_per_unit
