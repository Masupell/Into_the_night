class_name TerrainSampler
extends RefCounted

# The tile a chunk samples from, on the chunk thread. Tiles don't change after loading, so no locking
var tile: TerrainTile

func _init(_tile: TerrainTile) -> void:
	tile = _tile

# Face uv, bicubic (Catmull-Rom)
func sample(uv: Vector2) -> float:
	var step := tile.size - 1
	var x := pixel_pos(uv.x, tile.tile_x)
	var y := pixel_pos(uv.y, tile.tile_y)
	var x0 := first_pixel(x, step)
	var y0 := first_pixel(y, step)
	var wx := weights(x - x0, x0 == 0, x0 + 2 > step)
	var wy := weights(y - y0, y0 == 0, y0 + 2 > step)

	var h := tile.heights
	var xa := maxi(x0 - 1, 0) # outside pixels have weight 0 anyway
	var xb := mini(x0 + 2, step)
	var result := 0.0
	for j in range(4):
		var row := clampi(y0 - 1 + j, 0, step) * tile.size
		result += wy[j] * (wx.x * h[row + xa] + wx.y * h[row + x0] + wx.z * h[row + x0 + 1] + wx.w * h[row + xb])
	return result

# Same as sample() for a whole chunk grid, border is the extra ring for the normals.
# One call per chunk, no function calls in the loop (threads)
func sample_grid(uv_min: Vector2, uv_max: Vector2, grid_size: int, border: int = 0) -> PackedFloat32Array:
	var n := grid_size + 1 + 2 * border
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
		var t := float(i - border) / grid_size
		# so the edges hit uv_min/uv_max exactly
		var x := pixel_pos(uv_min.x * (1.0 - t) + uv_max.x * t, tile.tile_x)
		var y := pixel_pos(uv_min.y * (1.0 - t) + uv_max.y * t, tile.tile_y)
		if i < border or i >= n - border:
			x = pixel_pos_unclamped(uv_min.x * (1.0 - t) + uv_max.x * t, tile.tile_x)
			y = pixel_pos_unclamped(uv_min.y * (1.0 - t) + uv_max.y * t, tile.tile_y)
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

# Moisture of a whole chunk grid, bilinear is enough here
func sample_moisture_grid(uv_min: Vector2, uv_max: Vector2, grid_size: int) -> PackedFloat32Array:
	var n := grid_size + 1
	var size := TerrainTile.MOISTURE_SIZE
	var step := size - 1
	var xs := PackedInt32Array()
	var txs := PackedFloat32Array()
	var ys := PackedInt32Array()
	var tys := PackedFloat32Array()
	xs.resize(n)
	txs.resize(n)
	ys.resize(n)
	tys.resize(n)
	for i in range(n):
		var t := float(i) / grid_size
		var x := clampf((((uv_min.x * (1.0 - t) + uv_max.x * t) * tile.tiles_per_face) - tile.tile_x) * step, 0.0, step)
		var y := clampf((((uv_min.y * (1.0 - t) + uv_max.y * t) * tile.tiles_per_face) - tile.tile_y) * step, 0.0, step)
		xs[i] = first_pixel(x, step)
		ys[i] = first_pixel(y, step)
		txs[i] = x - xs[i]
		tys[i] = y - ys[i]

	var m := tile.moisture
	var result := PackedFloat32Array()
	result.resize(n * n)
	for j in range(n):
		var r0 := ys[j] * size
		var r1 := r0 + size
		var ty := tys[j]
		for i in range(n):
			var x0 := xs[i]
			var tx := txs[i]
			var top := m[r0 + x0] * (1.0 - tx) + m[r0 + x0 + 1] * tx
			var bottom := m[r1 + x0] * (1.0 - tx) + m[r1 + x0 + 1] * tx
			result[i + j * n] = top * (1.0 - ty) + bottom * ty
	return result

# Face uv -> pixel position inside this tile
func pixel_pos(uv: float, tile_index: int) -> float:
	var step := tile.size - 1
	return clampf((uv * tile.tiles_per_face - tile_index) * step, 0.0, step)

func pixel_pos_unclamped(uv: float, tile_index: int) -> float:
	return (uv * tile.tiles_per_face - tile_index) * (tile.size - 1)

# floor, but pixel + 1 stays inside the tile
static func first_pixel(pos: float, step: int) -> int:
	return clampi(floori(pos), 0, step - 1)

# Catmull-Rom weights, pixels outside the tile are extrapolated linearly
static func weights(t: float, at_start: bool, at_end: bool) -> Vector4:
	if t < 0.0 or t > 1.0: # outside the tile
		return Vector4(0.0, 1.0 - t, t, 0.0)
	var t2 := t * t
	var t3 := t2 * t
	var w := Vector4(0.5 * (-t + 2.0 * t2 - t3), 0.5 * (2.0 - 5.0 * t2 + 3.0 * t3), 0.5 * (t + 4.0 * t2 - 3.0 * t3), 0.5 * (t3 - t2))
	if at_start: # p0 = 2 p1 - p2
		w = Vector4(0.0, w.y + 2.0 * w.x, w.z - w.x, w.w)
	if at_end: # p3 = 2 p2 - p1
		w = Vector4(w.x, w.y - w.w, w.z + 2.0 * w.w, 0.0)
	return w
