class_name TerrainData
extends RefCounted

var width: int
var height: int

var height_map: PackedFloat32Array #currently only heightmap

func _init(w: int, h: int) -> void:
	width = w
	height = h
	height_map.resize(width * height)

func get_height(x: int, y: int) -> float:
	return height_map[x + y * width]

func set_height(x: int, y: int, value: float):
	height_map[x + y * width] = value


func sample_bilinear(uv: Vector2) -> float:
	var x = uv.x * (width - 1)
	var y = uv.y * (height - 1)

	var x0 = clampi(int(floor(x)), 0, width - 1)
	var y0 = clampi(int(floor(y)), 0, height - 1)

	var x1 = clampi(x0 + 1, 0, width - 1)
	var y1 = clampi(y0 + 1, 0, height - 1)

	var tx = x - x0
	var ty = y - y0

	var h00 = get_height(x0, y0)
	var h10 = get_height(x1, y0)
	var h01 = get_height(x0, y1)
	var h11 = get_height(x1, y1)

	var top = lerpf(h00, h10, tx)
	var bottom = lerpf(h01, h11, tx)

	return lerpf(top, bottom, ty)

func to_image() -> Image:
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			var h = get_height(x, y)
			img.set_pixel(x, y, Color(h, 0.0, 0.0, 1.0))
	return img

func load_from_image(img: Image):
	width = img.get_width()
	height = img.get_height()
	height_map.resize(width * height)
	for y in range(height):
		for x in range(width):
			var color = img.get_pixel(x, y)
			set_height(x, y, color.r)
