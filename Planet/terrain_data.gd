class_name TerrainData
extends RefCounted

# Heights are stored as 6 cube face grids (CubeSpheres.FACES), each split into tiles_per_face * tiles_per_face tiles
# Pixel 0 and face_size - 1, are exactly on the face borders, neighbouring faces share their values
# so samples continuous. Tiles share their border pixels the same way, so a face has
# tiles_per_face * (tile_size - 1) + 1 pixels per edge
#
# Tiles are loaded on demand on the WorkerThreadPool and unloaded when nothing used them for a while.
# Everything in here runs on the main thread only, chunk threads get a TerrainSampler instead
var tiles_per_face: int
var tile_size: int # pixels per tile edge
var face_size: int

const SEA_LEVEL := 0.08 # height (0..1) of the water surface
const UNLOAD_AFTER_MSEC := 10000

var tiles: Dictionary = {} # Vector3i(face, tile_x, tile_y) -> TerrainTile, only finished tiles
var loading: Dictionary = {} # Vector3i -> [TerrainTile, task_id], the tile is only touched by its task until it is done
var last_used: Dictionary = {} # Vector3i -> msec
var source: TerrainSource

func _init(_tiles_per_face: int, _tile_size: int, _source: TerrainSource) -> void:
	tiles_per_face = _tiles_per_face
	tile_size = _tile_size
	face_size = tiles_per_face * (tile_size - 1) + 1
	source = _source

func request_tile(key: Vector3i):
	if tiles.has(key) or loading.has(key):
		return
	var tile := TerrainTile.new(key.x, key.y, key.z, tile_size, tiles_per_face)
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

# Tile index the sampler will use for this u (or v)
func tile_for_uv(u: float) -> int:
	@warning_ignore("integer_division")
	return TerrainSampler.cell_for_uv(u, face_size) / (tile_size - 1)

# All tiles covering the uv rectangle of a face, or null if some are still loading (those get requested)
func get_sampler(face: int, uv_min: Vector2, uv_max: Vector2) -> TerrainSampler:
	var now := Time.get_ticks_msec()
	var needed := {}
	var missing := false

	for tile_y in range(tile_for_uv(uv_min.y), tile_for_uv(uv_max.y) + 1):
		for tile_x in range(tile_for_uv(uv_min.x), tile_for_uv(uv_max.x) + 1):
			var key := Vector3i(face, tile_x, tile_y)
			if tiles.has(key):
				needed[key] = tiles[key]
				last_used[key] = now
			else:
				request_tile(key)
				missing = true

	if missing:
		return null
	return TerrainSampler.new(needed, tiles_per_face, tile_size)

func get_tile(face: int, tile_x: int, tile_y: int) -> TerrainTile:
	return tiles.get(Vector3i(face, tile_x, tile_y))

# Tile that owns face pixel x/y. Border pixels belong to two (or four) tiles, this returns the lower one
func tile_index(pixel: int) -> int:
	@warning_ignore("integer_division")
	return mini(pixel / (tile_size - 1), tiles_per_face - 1)

# 0 if the tile is not loaded
func get_height(face: int, x: int, y: int) -> float:
	var tile_x := tile_index(x)
	var tile_y := tile_index(y)
	var tile := get_tile(face, tile_x, tile_y)
	if tile == null:
		return 0.0
	return tile.get_height(x - tile_x * (tile_size - 1), y - tile_y * (tile_size - 1))

# All 6 faces next to each other, in face order, for debugging (only loaded tiles)
func to_image() -> Image:
	var img = Image.create(6 * face_size, face_size, false, Image.FORMAT_RGBA8)
	for face in range(6):
		for y in range(face_size):
			for x in range(face_size):
				var h = get_height(face, x, y)
				img.set_pixel(face * face_size + x, y, Color(h, 0.0, 0.0, 1.0))
	return img
