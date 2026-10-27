class_name TerrainSampler
extends RefCounted

# Read only set of tiles for one chunk, handed to the chunk generation thread.
# Tiles never change after they are loaded and this dictionary belongs only to this chunk,
# so the thread never touches TerrainData.tiles and no locking is needed
var tiles: Dictionary # Vector3i(face, tile_x, tile_y) -> TerrainTile
var tile_size: int
var face_size: int

func _init(_tiles: Dictionary, _tiles_per_face: int, _tile_size: int) -> void:
	tiles = _tiles
	tile_size = _tile_size
	face_size = _tiles_per_face * (tile_size - 1) + 1

# Bilinear cell containing u (or v), same math as TerrainData.tile_for_uv, so the needed tiles always match
static func cell_for_uv(u: float, _face_size: int) -> int:
	return clampi(int(floor(u * (_face_size - 1))), 0, _face_size - 2)

# Every bilinear cell lies completely inside one tile (borders are shared), so only one tile lookup is needed
func sample_face(face: int, uv: Vector2) -> float:
	var x = uv.x * (face_size - 1)
	var y = uv.y * (face_size - 1)

	var cell_x = cell_for_uv(uv.x, face_size)
	var cell_y = cell_for_uv(uv.y, face_size)

	@warning_ignore("integer_division")
	var tile_x = cell_x / (tile_size - 1)
	@warning_ignore("integer_division")
	var tile_y = cell_y / (tile_size - 1)
	var tile: TerrainTile = tiles.get(Vector3i(face, tile_x, tile_y))
	if tile == null:
		push_error("TerrainSampler: tile %s missing, chunk asked for the wrong tiles" % Vector3i(face, tile_x, tile_y))
		return 0.0

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
