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

	var h00 := tile.get_height(x0, y0)
	var h10 := tile.get_height(x0 + 1, y0)
	var h01 := tile.get_height(x0, y0 + 1)
	var h11 := tile.get_height(x0 + 1, y0 + 1)

	var top := lerpf(h00, h10, tx)
	var bottom := lerpf(h01, h11, tx)

	return lerpf(top, bottom, ty)
