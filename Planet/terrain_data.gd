class_name TerrainData
extends RefCounted

# Heights are stored as 6 cube face grids (CubeSpheres.FACES), each split into tiles_per_face * tiles_per_face tiles
# Pixel 0 and face_size - 1, are exactly on the face borders, neighbouring faces share their values
# so samples continuous. Tiles share their border pixels the same way, so a face has
# tiles_per_face * (tile_size - 1) + 1 pixels per edge
var tiles_per_face: int
var tile_size: int # pixels per tile edge
var face_size: int

const SEA_LEVEL := 0.08 # height (0..1) of the water surface, every TerrainSource is scaled to this

var tiles: Dictionary = {} # Vector3i(face, tile_x, tile_y) -> TerrainTile
var source: TerrainSource

func _init(_tiles_per_face: int, _tile_size: int, _source: TerrainSource) -> void:
	tiles_per_face = _tiles_per_face
	tile_size = _tile_size
	face_size = tiles_per_face * (tile_size - 1) + 1
	source = _source

	# All tiles up front for now, streaming comes later
	for face in range(6):
		for tile_y in range(tiles_per_face):
			for tile_x in range(tiles_per_face):
				load_tile(face, tile_x, tile_y)

func load_tile(face: int, tile_x: int, tile_y: int) -> TerrainTile:
	var tile := TerrainTile.new(face, tile_x, tile_y, tile_size, tiles_per_face)
	source.fill_tile(tile)
	tiles[Vector3i(face, tile_x, tile_y)] = tile
	return tile

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
