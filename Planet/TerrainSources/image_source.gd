class_name ImageSource
extends EquirectSource

# Heightmap image (red channel)
var data: PackedFloat32Array
var sea_level: float

func _init(source: Image, _sea_level: float) -> void:
	sea_level = _sea_level
	var img := source.duplicate() as Image
	img.convert(Image.FORMAT_RF)
	data = img.get_data().to_float32_array()
	width = img.get_width()
	height = img.get_height()

func get_value(index: int) -> float:
	return data[index] - sea_level
