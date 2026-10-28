class_name TerrainSampler
extends RefCounted

# The one tile a chunk samples from, handed to the chunk generation thread.
# A chunk always lies completely inside one tile of its tile level (both are the same quadtree split),
# tiles never change after loading, so the thread never touches TerrainData and no locking is needed
var tile: TerrainTile

func _init(_tile: TerrainTile) -> void:
	tile = _tile

# uv is on the whole face, has to be inside this tile (gets clamped onto its border otherwise)
# Bicubic (Catmull-Rom): 4x4 pixels around the point. Goes exactly through the pixels like bilinear, but without the kinks at them
func sample(uv: Vector2) -> float:
	var step := tile.size - 1
	var x := pixel_pos(uv.x, tile.tile_x)
	var y := pixel_pos(uv.y, tile.tile_y)
	var x0 := first_pixel(x, step)
	var y0 := first_pixel(y, step)
	var wx := weights(x - x0, x0 == 0, x0 + 2 > step)
	var wy := weights(y - y0, y0 == 0, y0 + 2 > step)

	var h := tile.heights
	var xa := maxi(x0 - 1, 0) # pixel before / after the tile only get weight 0, any index inside is fine
	var xb := mini(x0 + 2, step)
	var result := 0.0
	for j in range(4):
		var row := clampi(y0 - 1 + j, 0, step) * tile.size
		result += wy[j] * (wx.x * h[row + xa] + wx.y * h[row + x0] + wx.z * h[row + x0 + 1] + wx.w * h[row + xb])
	return result

# Heights of a whole chunk grid ((grid_size + 1)^2, row by row), same values as sample() at each vertex.
# One call per chunk: calls to GDScript functions block each other between threads, so the per vertex loop has none.
# x only depends on the column and y only on the row, so their pixels and weights are computed once
func sample_grid(uv_min: Vector2, uv_max: Vector2, grid_size: int) -> PackedFloat32Array:
	var n := grid_size + 1
	var step := tile.size - 1
	var xs := PackedInt32Array()
	var wxs := PackedVector4Array()
	var ys := PackedInt32Array()
	var wys := PackedVector4Array()
	xs.resize(n)
	wxs.resize(n)
	ys.resize(n)
	wys.resize(n)
	for i in range(n):
		var t := float(i) / grid_size
		# a * (1 - t) + b * t, so the edges hit uv_min/uv_max exactly and neighbouring chunks sample the same values
		var x := pixel_pos(uv_min.x * (1.0 - t) + uv_max.x * t, tile.tile_x)
		var y := pixel_pos(uv_min.y * (1.0 - t) + uv_max.y * t, tile.tile_y)
		xs[i] = first_pixel(x, step)
		ys[i] = first_pixel(y, step)
		wxs[i] = weights(x - xs[i], xs[i] == 0, xs[i] + 2 > step)
		wys[i] = weights(y - ys[i], ys[i] == 0, ys[i] + 2 > step)

	var h := tile.heights
	var size := tile.size
	var result := PackedFloat32Array()
	result.resize(n * n)
	for j in range(n):
		var y0 := ys[j]
		var wy := wys[j]
		var r0 := maxi(y0 - 1, 0) * size
		var r1 := y0 * size
		var r2 := (y0 + 1) * size
		var r3 := mini(y0 + 2, step) * size
		for i in range(n):
			var x0 := xs[i]
			var wx := wxs[i]
			var xa := maxi(x0 - 1, 0)
			var xb := mini(x0 + 2, step)
			result[i + j * n] = (wy.x * (wx.x * h[r0 + xa] + wx.y * h[r0 + x0] + wx.z * h[r0 + x0 + 1] + wx.w * h[r0 + xb])
				+ wy.y * (wx.x * h[r1 + xa] + wx.y * h[r1 + x0] + wx.z * h[r1 + x0 + 1] + wx.w * h[r1 + xb])
				+ wy.z * (wx.x * h[r2 + xa] + wx.y * h[r2 + x0] + wx.z * h[r2 + x0 + 1] + wx.w * h[r2 + xb])
				+ wy.w * (wx.x * h[r3 + xa] + wx.y * h[r3 + x0] + wx.z * h[r3 + x0 + 1] + wx.w * h[r3 + xb]))
	return result

# Position in pixels along one axis inside this tile, from a face uv coordinate
func pixel_pos(uv: float, tile_index: int) -> float:
	var step := tile.size - 1
	return clampf((uv * tile.tiles_per_face - tile_index) * step, 0.0, step)

# floor, but at most the second to last pixel, so pixel + 1 stays inside the tile (t is 1.0 on the last pixel then)
static func first_pixel(pos: float, step: int) -> int:
	return mini(int(pos), step - 1)

# Catmull-Rom weights of the 4 pixels around t (between pixel 1 and 2): curve through both,
# the slope at each taken from its two neighbours. A pixel outside the tile (before the first / after the last)
# is extrapolated in a straight line from the two inside, folded into the weights of those two
static func weights(t: float, at_start: bool, at_end: bool) -> Vector4:
	var t2 := t * t
	var t3 := t2 * t
	var w := Vector4(0.5 * (-t + 2.0 * t2 - t3), 0.5 * (2.0 - 5.0 * t2 + 3.0 * t3), 0.5 * (t + 4.0 * t2 - 3.0 * t3), 0.5 * (t3 - t2))
	if at_start: # p0 = 2 p1 - p2
		w = Vector4(0.0, w.y + 2.0 * w.x, w.z - w.x, w.w)
	if at_end: # p3 = 2 p2 - p1
		w = Vector4(w.x, w.y - w.w, w.z + 2.0 * w.w, 0.0)
	return w
