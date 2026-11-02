class_name EtopoSource
extends EquirectSource

# Converted with tools/convert_etopo.py, whole file in memory
var bytes: PackedByteArray
var meters_per_unit: float # meters that become planet.max_height

func _init(path: String, _meters_per_unit: float) -> void:
	meters_per_unit = _meters_per_unit

	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
	assert(info["format"] == "int16_le_meters", "EtopoSource: unknown format %s" % info["format"])
	width = int(info["width"])
	height = int(info["height"])

	bytes = FileAccess.get_file_as_bytes(path + ".bin")
	assert(bytes.size() == width * height * 2, "EtopoSource: %s.bin has the wrong size" % path)

func get_value(index: int) -> float:
	return bytes.decode_s16(index * 2) / meters_per_unit
