class_name DiskSource
extends TerrainSource

# Tiles baked by tools/bake_tiles.py, own FileAccess per tile so they load on several threads
var path: String
var meters_per_unit: float # meters that become planet.max_height
var tile_size: int
var max_level: int
var tile_bytes: int
var level_offsets: PackedInt64Array
# Moisture tiles, empty path for default moisture
var moisture_path := ""
var moisture_tile_bytes: int
var moisture_level_offsets: PackedInt64Array
# Water tiles, empty path for sea level everywhere
var water_path := ""
var water_tile_bytes: int
var water_level_offsets: PackedInt64Array

func _init(_path: String, _meters_per_unit: float, _moisture_path := "", _water_path := "") -> void:
	path = _path + ".bin"
	meters_per_unit = _meters_per_unit

	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path + ".json"))
	assert(info["format"] == "int16_le_meters", "DiskSource: unknown format %s" % info["format"])
	tile_size = int(info["tile_size"])
	max_level = int(info["max_level"])
	tile_bytes = int(info["tile_bytes"])
	for entry in info["levels"]:
		level_offsets.append(int(entry["offset"]))

	if _water_path != "":
		if not FileAccess.file_exists(_water_path + ".json") or not FileAccess.file_exists(_water_path + ".bin"):
			push_warning("DiskSource: no water tiles at %s, see tools/install.txt" % _water_path)
		else:
			var water_info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_water_path + ".json"))
			assert(water_info["format"] == "int16_le_water_meters", "DiskSource: unknown water format %s" % water_info["format"])
			assert(int(water_info["tile_size"]) == TerrainTile.WATER_SIZE, "DiskSource: water tile size doesn't match TerrainTile.WATER_SIZE")
			assert(int(water_info["max_level"]) >= max_level, "DiskSource: water tiles have fewer levels than the heights")
			water_path = _water_path + ".bin"
			water_tile_bytes = int(water_info["tile_bytes"])
			for entry in water_info["levels"]:
				water_level_offsets.append(int(entry["offset"]))

	if _moisture_path != "":
		if not FileAccess.file_exists(_moisture_path + ".json") or not FileAccess.file_exists(_moisture_path + ".bin"):
			push_warning("DiskSource: no moisture tiles at %s, see tools/install.txt" % _moisture_path)
			return
		var moisture_info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_moisture_path + ".json"))
		assert(moisture_info["format"] == "uint8_moisture", "DiskSource: unknown moisture format %s" % moisture_info["format"])
		assert(int(moisture_info["tile_size"]) == TerrainTile.MOISTURE_SIZE, "DiskSource: moisture tile size doesn't match TerrainTile.MOISTURE_SIZE")
		assert(int(moisture_info["max_level"]) >= max_level, "DiskSource: moisture tiles have fewer levels than the heights")
		moisture_path = _moisture_path + ".bin"
		moisture_tile_bytes = int(moisture_info["tile_bytes"])
		for entry in moisture_info["levels"]:
			moisture_level_offsets.append(int(entry["offset"]))

func fill_heights(tile: TerrainTile) -> void:
	assert(tile.size == tile_size and tile.level <= max_level, "DiskSource: tile does not match the baked data")
	var n := tile.tiles_per_face
	var index := (tile.face * n + tile.tile_y) * n + tile.tile_x

	var file := FileAccess.open(path, FileAccess.READ)
	file.seek(level_offsets[tile.level] + index * tile_bytes)
	var bytes := file.get_buffer(tile_bytes)

	for i in range(tile_size * tile_size):
		tile.heights[i] = bytes.decode_s16(i * 2) / meters_per_unit

func fill_moisture(tile: TerrainTile) -> void:
	if moisture_path == "":
		super(tile)
		return
	var n := tile.tiles_per_face
	var index := (tile.face * n + tile.tile_y) * n + tile.tile_x

	var file := FileAccess.open(moisture_path, FileAccess.READ)
	file.seek(moisture_level_offsets[tile.level] + index * moisture_tile_bytes)
	var bytes := file.get_buffer(moisture_tile_bytes)

	for i in range(moisture_tile_bytes):
		tile.moisture[i] = bytes[i] / 255.0

func fill_water(tile: TerrainTile) -> void:
	if water_path == "":
		super(tile)
		return
	var n := tile.tiles_per_face
	var index := (tile.face * n + tile.tile_y) * n + tile.tile_x

	var file := FileAccess.open(water_path, FileAccess.READ)
	file.seek(water_level_offsets[tile.level] + index * water_tile_bytes)
	var bytes := file.get_buffer(water_tile_bytes)

	for i in range(TerrainTile.WATER_SIZE * TerrainTile.WATER_SIZE):
		tile.water[i] = bytes.decode_s16(i * 2) / meters_per_unit
