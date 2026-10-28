class_name TerrainSampler
extends RefCounted

# The one tile a chunk samples from, handed to the chunk generation thread.
# A chunk always lies completely inside one tile of its tile level (both are the same quadtree split),
# tiles never change after loading, so the thread never touches TerrainData and no locking is needed
var tile: TerrainTile

func _init(_tile: TerrainTile) -> void:
	tile = _tile

# uv is on the whole face, has to be inside this tile (gets clamped onto its border otherwise)
func sample(uv: Vector2) -> float:
	var step := tile.size - 1
	var x := clampf((uv.x * tile.tiles_per_face - tile.tile_x) * step, 0.0, step)
	var y := clampf((uv.y * tile.tiles_per_face - tile.tile_y) * step, 0.0, step)

	# floor, but at most the second to last pixel, so x0 + 1 stays inside the tile (tx is 1.0 on the last pixel then)
	var x0 := mini(int(x), step - 1)
	var y0 := mini(int(y), step - 1)

	var tx := x - x0
	var ty := y - y0

	# Bicubic (Catmull-Rom): 4x4 pixels around the point, first 4 rows along x, then those along y.
	# Goes exactly through the pixels like bilinear, but without the kinks at them
	# A row or column outside the tile (-1 or size) is extrapolated in a straight line from the two inside
	var r1 := row(y0, x0, tx)
	var r2 := row(y0 + 1, x0, tx)
	var r0 := row(y0 - 1, x0, tx) if y0 > 0 else 2.0 * r1 - r2
	var r3 := row(y0 + 2, x0, tx) if y0 + 2 <= step else 2.0 * r2 - r1
	return catmull_rom(r0, r1, r2, r3, ty)

# 4 pixels of row y around x0 .. x0 + 1, interpolated at t
func row(y: int, x0: int, t: float) -> float:
	var step := tile.size - 1
	var p1 := tile.get_height(x0, y)
	var p2 := tile.get_height(x0 + 1, y)
	var p0 := tile.get_height(x0 - 1, y) if x0 > 0 else 2.0 * p1 - p2
	var p3 := tile.get_height(x0 + 2, y) if x0 + 2 <= step else 2.0 * p2 - p1
	return catmull_rom(p0, p1, p2, p3, t)

# Curve through p1 (t = 0) and p2 (t = 1), the slope at each is taken from its two neighbours
static func catmull_rom(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)))
