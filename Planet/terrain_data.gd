class_name TerrainData
extends RefCounted

# Heights are stored as 6 cube face grids (CubeSpheres.FACES), as a pyramid of tile levels:
# level 0 is one tile per face, level L has 2^L * 2^L tiles per face, all tiles have tile_size pixels per edge.
# Pixel 0 and size - 1, are exactly on the face/tile borders, neighbouring faces and tiles share their values
# so samples continuous. At the finest level a face has 2^max_level * (tile_size - 1) + 1 pixels per edge
# Pixels of a level are also pixels of every finer level (every second one), with the same values,
# so chunks using different levels still meet at the same heights
#
# Tiles are loaded on demand on the WorkerThreadPool and unloaded when nothing used them for a while.
# Everything in here runs on the main thread only, chunk threads get a TerrainSampler instead
var max_level: int
var tile_size: int # pixels per tile edge
var tiles_per_face: int # per edge at max_level
var face_size: int # pixels per edge at max_level

const SEA_LEVEL := 0.08 # height (0..1) of the water surface
const UNLOAD_AFTER_MSEC := 10000

var tiles: Dictionary = {} # Vector4i(face, level, tile_x, tile_y) -> TerrainTile, only finished tiles
var loading: Dictionary = {} # Vector4i -> [TerrainTile, task_id], the tile is only touched by its task until it is done
var last_used: Dictionary = {} # Vector4i -> msec
var source: TerrainSource

func _init(_max_level: int, _tile_size: int, _source: TerrainSource) -> void:
	max_level = _max_level
	tile_size = _tile_size
	tiles_per_face = 1 << max_level
	face_size = tiles_per_face * (tile_size - 1) + 1
	source = _source

func request_tile(key: Vector4i):
	if tiles.has(key) or loading.has(key):
		return
	var tile := TerrainTile.new(key.x, key.y, key.z, key.w, tile_size)
	var task_id := WorkerThreadPool.add_task(source.fill_tile.bind(tile))
	loading[key] = [tile, task_id]

func update():
	var now := Time.get_ticks_msec()

	for key in loading.keys():
		var entry: Array = loading[key]
		if WorkerThreadPool.is_task_completed(entry[1]):
			WorkerThreadPool.wait_for_task_completion(entry[1])
			tiles[key] = entry[0]
			last_used[key] = now
			loading.erase(key)

	for key in tiles.keys():
		if now - last_used[key] > UNLOAD_AFTER_MSEC:
			tiles.erase(key)
			last_used.erase(key)

# Coarsest tile level that still has at least one pixel per chunk grid cell.
# Never finer than the quad level, so the chunk always lies inside one tile
func tile_level_for(quad_level: int, grid_cells: int) -> int:
	var level := 0
	# pixels across the chunk: (tile_size - 1) * 2^level / 2^quad_level, compared without dividing
	while level < mini(quad_level, max_level) and ((tile_size - 1) << level) < (grid_cells << quad_level):
		level += 1
	return level

# The tile containing the chunk, or null while it is still loading (then it gets requested)
func get_sampler(face: int, quad_level: int, grid_cells: int, uv_center: Vector2) -> TerrainSampler:
	var level := tile_level_for(quad_level, grid_cells)
	var count := 1 << level
	var key := Vector4i(face, level, mini(int(uv_center.x * count), count - 1), mini(int(uv_center.y * count), count - 1))

	if not tiles.has(key):
		request_tile(key)
		return null
	last_used[key] = Time.get_ticks_msec()
	return TerrainSampler.new(tiles[key])

func get_tile(face: int, level: int, tile_x: int, tile_y: int) -> TerrainTile:
	return tiles.get(Vector4i(face, level, tile_x, tile_y))

# Tile that owns face pixel x/y. Border pixels belong to two (or four) tiles, this returns the lower one
func tile_index(pixel: int) -> int:
	@warning_ignore("integer_division")
	return mini(pixel / (tile_size - 1), tiles_per_face - 1)

# Pixel of the finest level, 0 if that tile is not loaded
func get_height(face: int, x: int, y: int) -> float:
	var tile_x := tile_index(x)
	var tile_y := tile_index(y)
	var tile := get_tile(face, max_level, tile_x, tile_y)
	if tile == null:
		return 0.0
	return tile.get_height(x - tile_x * (tile_size - 1), y - tile_y * (tile_size - 1))

# All 6 faces next to each other, in face order, for debugging (only loaded tiles of the finest level)
func to_image() -> Image:
	var img = Image.create(6 * face_size, face_size, false, Image.FORMAT_RGBA8)
	for face in range(6):
		for y in range(face_size):
			for x in range(face_size):
				var h = get_height(face, x, y)
				img.set_pixel(face * face_size + x, y, Color(h, 0.0, 0.0, 1.0))
	return img
