class_name TerrainData
extends RefCounted

# Heights are stored as 6 cube face grids (CubeSpheres.FACES)
# Pixel 0 and face_size - 1, are exactly on the face borders, neighbouring faces share their values
# so samplins continuous
var face_size: int

var height_map: PackedFloat32Array #currently only heightmap, 6 * face_size * face_size

func _init(_face_size: int) -> void:
	face_size = _face_size
	height_map.resize(6 * face_size * face_size)

func get_height(face: int, x: int, y: int) -> float:
	return height_map[(face * face_size + y) * face_size + x]

func set_height(face: int, x: int, y: int, value: float):
	height_map[(face * face_size + y) * face_size + x] = value

# Direction on the sphere of a pixel
func pixel_to_dir(face: int, x: int, y: int) -> Vector3:
	var uv := Vector2(x, y) / float(face_size - 1)
	return CubeSphere.face_to_sphere(face, uv)


# Height (0..1) at a direction on the sphere
func sample(dir: Vector3) -> float:
	var face := CubeSphere.get_face(dir)
	return sample_face(face, CubeSphere.get_face_uv(dir, face))

func sample_face(face: int, uv: Vector2) -> float:
	var x = uv.x * (face_size - 1)
	var y = uv.y * (face_size - 1)

	var x0 = clampi(int(floor(x)), 0, face_size - 1)
	var y0 = clampi(int(floor(y)), 0, face_size - 1)

	var x1 = clampi(x0 + 1, 0, face_size - 1)
	var y1 = clampi(y0 + 1, 0, face_size - 1)

	var tx = x - x0
	var ty = y - y0

	var h00 = get_height(face, x0, y0)
	var h10 = get_height(face, x1, y0)
	var h01 = get_height(face, x0, y1)
	var h11 = get_height(face, x1, y1)

	var top = lerpf(h00, h10, tx)
	var bottom = lerpf(h01, h11, tx)

	return lerpf(top, bottom, ty)

# All 6 faces next to each other, in face order, for debugging
func to_image() -> Image:
	var img = Image.create(6 * face_size, face_size, false, Image.FORMAT_RGBA8)
	for face in range(6):
		for y in range(face_size):
			for x in range(face_size):
				var h = get_height(face, x, y)
				img.set_pixel(face * face_size + x, y, Color(h, 0.0, 0.0, 1.0))
	return img


# Converts an equirectangular heightmap (red channel right now) into the cube faces
func load_from_equirect(source: Image):
	var img := source.duplicate() as Image
	img.convert(Image.FORMAT_RF)
	var data := img.get_data().to_float32_array()
	var width := img.get_width()
	var height := img.get_height()

	for face in range(6):
		for y in range(face_size):
			for x in range(face_size):
				var uv := get_equirect_uv(pixel_to_dir(face, x, y))
				set_height(face, x, y, sample_equirect(data, width, height, uv))

# Equirectangular projection (Vector3.DOWN is the north pole)
static func get_equirect_uv(pos: Vector3) -> Vector2:
	var n = pos.normalized()
	var phi = atan2(n.z, n.x)
	var theta = asin(n.y)

	var u = (phi + PI) / (2.0 * PI)
	var v = (theta + PI / 2.0) / PI
	return Vector2(u, v)

# Bilinear on pixel centers, wraps around horizontally so there is no seam at u = 0/1
static func sample_equirect(data: PackedFloat32Array, width: int, height: int, uv: Vector2) -> float:
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
