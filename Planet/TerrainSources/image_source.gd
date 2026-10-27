class_name ImageSource
extends EquirectSource

# Equirectangular heightmap image (red channel), like the old earth_map.png
var data: PackedFloat32Array
var sea_level: float # value in the image that is sea level, gets subtracted

func _init(source: Image, _sea_level: float) -> void:
	sea_level = _sea_level
	var img := source.duplicate() as Image
	img.convert(Image.FORMAT_RF)
	data = img.get_data().to_float32_array()
	width = img.get_width()
	height = img.get_height()

func get_value(index: int) -> float:
	return data[index] - sea_level
