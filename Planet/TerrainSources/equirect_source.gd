class_name EquirectSource
extends TerrainSource

# Equirectangular heightmap (red channel right now), like the earth map
var data: PackedFloat32Array
var width: int
var height: int
var sea_level: float # value in the image that is sea level, gets subtracted

func _init(source: Image, _sea_level: float) -> void:
	sea_level = _sea_level
	var img := source.duplicate() as Image
	img.convert(Image.FORMAT_RF)
	data = img.get_data().to_float32_array()
	width = img.get_width()
	height = img.get_height()

func height_at(dir: Vector3) -> float:
	return sample(get_uv(dir)) - sea_level

# Equirectangular projection (Vector3.DOWN is the north pole)
static func get_uv(pos: Vector3) -> Vector2:
	var n = pos.normalized()
	var phi = atan2(n.z, n.x)
	var theta = asin(n.y)

	var u = (phi + PI) / (2.0 * PI)
	var v = (theta + PI / 2.0) / PI
	return Vector2(u, v)

# Bilinear on pixel centers, wraps around horizontally so there is no seam at u = 0/1
func sample(uv: Vector2) -> float:
	var x = uv.x * width - 0.5
	var y = clampf(uv.y * height - 0.5, 0.0, height - 1.0)

	var x0 = int(floor(x))
	var y0 = int(floor(y))
	var tx = x - x0
	var ty = y - y0

	x0 = posmod(x0, width)
	var x1 = (x0 + 1) % width
	var y1 = mini(y0 + 1, height - 1)

	var top = lerpf(data[x0 + y0 * width], data[x1 + y0 * width], tx)
	var bottom = lerpf(data[x0 + y1 * width], data[x1 + y1 * width], tx)

	return lerpf(top, bottom, ty)
