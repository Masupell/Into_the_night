class_name TerrainData
extends RefCounted

# Heights are stored as 6 cube face grids (CubeSpheres.FACES), each split into tiles_per_face * tiles_per_face tiles
# Pixel 0 and face_size - 1, are exactly on the face borders, neighbouring faces share their values
# so samples continuous. Tiles share their border pixels the same way, so a face has
# tiles_per_face * (tile_size - 1) + 1 pixels per edge
var tiles_per_face: int
var tile_size: int # pixels per tile edge
var face_size: int

var tiles: Dictionary = {} # Vector3i(face, tile_x, tile_y) -> TerrainTile

func _init(_tiles_per_face: int, _tile_size: int) -> void:
	tiles_per_face = _tiles_per_face
	tile_size = _tile_size
	face_size = tiles_per_face * (tile_size - 1) + 1

	for face in range(6):
		for tile_y in range(tiles_per_face):
			for tile_x in range(tiles_per_face):
				tiles[Vector3i(face, tile_x, tile_y)] = TerrainTile.new(face, tile_x, tile_y, tile_size)

func get_tile(face: int, tile_x: int, tile_y: int) -> TerrainTile:
	return tiles.get(Vector3i(face, tile_x, tile_y))

# Tile that owns face pixel x/y. Border pixels belong to two (or four) tiles, this returns the lower one
func tile_index(pixel: int) -> int:
	@warning_ignore("integer_division")
	return mini(pixel / (tile_size - 1), tiles_per_face - 1)

func get_height(face: int, x: int, y: int) -> float:
	var tile_x := tile_index(x)
	var tile_y := tile_index(y)
	return get_tile(face, tile_x, tile_y).get_height(x - tile_x * (tile_size - 1), y - tile_y * (tile_size - 1))

# Writes into every tile that contains the pixel, so the shared borders stay equal
func set_height(face: int, x: int, y: int, value: float):
	var step := tile_size - 1
	@warning_ignore("integer_division")
	for tile_y in range(maxi(0, (y - 1) / step), mini(y / step, tiles_per_face - 1) + 1):
		@warning_ignore("integer_division")
		for tile_x in range(maxi(0, (x - 1) / step), mini(x / step, tiles_per_face - 1) + 1):
			get_tile(face, tile_x, tile_y).set_height(x - tile_x * step, y - tile_y * step, value)

# Direction on the sphere of a pixel
func pixel_to_dir(face: int, x: int, y: int) -> Vector3:
	var uv := Vector2(x, y) / float(face_size - 1)
	return CubeSphere.face_to_sphere(face, uv)


# Height (0..1) at a direction on the sphere
func sample(dir: Vector3) -> float:
	var face := CubeSphere.get_face(dir)
	return sample_face(face, CubeSphere.get_face_uv(dir, face))

# Every bilinear cell lies completely inside one tile (borders are shared), so only one tile lookup is needed
func sample_face(face: int, uv: Vector2) -> float:
	var x = uv.x * (face_size - 1)
	var y = uv.y * (face_size - 1)

	var cell_x = clampi(int(floor(x)), 0, face_size - 2)
	var cell_y = clampi(int(floor(y)), 0, face_size - 2)

	@warning_ignore("integer_division")
	var tile_x = cell_x / (tile_size - 1)
	@warning_ignore("integer_division")
	var tile_y = cell_y / (tile_size - 1)
	var tile := get_tile(face, tile_x, tile_y)

	var x0 = cell_x - tile_x * (tile_size - 1)
	var y0 = cell_y - tile_y * (tile_size - 1)

	var tx = x - cell_x
	var ty = y - cell_y

	var h00 = tile.get_height(x0, y0)
	var h10 = tile.get_height(x0 + 1, y0)
	var h01 = tile.get_height(x0, y0 + 1)
	var h11 = tile.get_height(x0 + 1, y0 + 1)

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
