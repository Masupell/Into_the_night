class_name ChunkGrid
extends RefCounted

# Everything of a chunk mesh that only depends on the grid size, not on the terrain: the triangles (indices) and UVs
# of the terrain (with its skirts) and of the water. Made once per grid size and shared by all chunks of that size,
# instead of every chunk build computing the same again. Only read after it is made, so the worker threads can share it
var terrain_indices := PackedInt32Array()
var terrain_uvs := PackedVector2Array() # skirt vertices have the uv of the edge vertex they hang from
var water_indices := PackedInt32Array()
var water_uvs := PackedVector2Array()

static var _grids := {} # grid size -> ChunkGrid
static var _mutex := Mutex.new()

# Called on the worker threads, the first one of a size makes it (the others wait for it)
static func for_size(grid_size: int) -> ChunkGrid:
	_mutex.lock()
	if not _grids.has(grid_size):
		_grids[grid_size] = ChunkGrid.new(grid_size)
	var grid: ChunkGrid = _grids[grid_size]
	_mutex.unlock()
	return grid

func _init(grid_size: int) -> void:
	var num_vertices := grid_size + 1
	var total_vertices := num_vertices * num_vertices
	var main_index_count := grid_size * grid_size * 6
	var indices := PackedInt32Array()
	indices.resize(main_index_count + grid_size * 4 * 6)

	# Same order as the vertices in Chunk.calculate_terrain_mesh: the grid row by row, then the skirts north, south, west, east
	for y in range(grid_size):
		for x in range(grid_size):
			var idx = (x + (y * grid_size)) * 6
			var top_left = x + y * num_vertices
			var top_right = (x+1) + y * num_vertices
			var bottom_left = x + (y+1) * num_vertices
			var bottom_right = (x+1) + (y+1) * num_vertices

			indices[idx] = top_left
			indices[idx+1] = top_right
			indices[idx+2] = bottom_left

			indices[idx+3] = top_right
			indices[idx+4] = bottom_right
			indices[idx+5] = bottom_left

	var north_offset := total_vertices
	var south_offset := north_offset + num_vertices
	var west_offset := south_offset + num_vertices
	var east_offset := west_offset + num_vertices

	var idx_ptr = main_index_count

	for x in range(grid_size):
		var top_left = north_offset + x
		var top_right = north_offset + x + 1
		var bottom_left = x
		var bottom_right = x + 1
		indices[idx_ptr] = top_left
		indices[idx_ptr+1] = top_right
		indices[idx_ptr+2] = bottom_left
		indices[idx_ptr+3] = top_right
		indices[idx_ptr+4] = bottom_right
		indices[idx_ptr+5] = bottom_left
		idx_ptr += 6

	for x in range(grid_size):
		var top_left = x + grid_size * num_vertices
		var top_right = x + 1 + grid_size * num_vertices
		var bottom_left = south_offset + x
		var bottom_right = south_offset + x + 1
		indices[idx_ptr] = top_left
		indices[idx_ptr+1] = top_right
		indices[idx_ptr+2] = bottom_left
		indices[idx_ptr+3] = top_right
		indices[idx_ptr+4] = bottom_right
		indices[idx_ptr+5] = bottom_left
		idx_ptr += 6

	for y in range(grid_size):
		var top_left = west_offset + y
		var top_right = y * num_vertices
		var bottom_left = west_offset + y + 1
		var bottom_right = (y+1) * num_vertices
		indices[idx_ptr] = top_left
		indices[idx_ptr+1] = top_right
		indices[idx_ptr+2] = bottom_left
		indices[idx_ptr+3] = top_right
		indices[idx_ptr+4] = bottom_right
		indices[idx_ptr+5] = bottom_left
		idx_ptr += 6

	for y in range(grid_size):
		var top_left = grid_size + y * num_vertices
		var top_right = east_offset + y
		var bottom_left = grid_size + (y+1) * num_vertices
		var bottom_right = east_offset + y + 1
		indices[idx_ptr] = top_left
		indices[idx_ptr+1] = top_right
		indices[idx_ptr+2] = bottom_left
		indices[idx_ptr+3] = top_right
		indices[idx_ptr+4] = bottom_right
		indices[idx_ptr+5] = bottom_left
		idx_ptr += 6
	terrain_indices = indices

	var uvs := PackedVector2Array()
	uvs.resize(total_vertices + num_vertices * 4)
	for y in range(num_vertices):
		for x in range(num_vertices):
			uvs[x + y * num_vertices] = Vector2(float(x) / grid_size, float(y) / grid_size)
	for i in range(num_vertices):
		uvs[north_offset + i] = uvs[i] # north edge, y = 0
		uvs[south_offset + i] = uvs[i + grid_size * num_vertices]
		uvs[west_offset + i] = uvs[i * num_vertices]
		uvs[east_offset + i] = uvs[grid_size + i * num_vertices]
	terrain_uvs = uvs

	# The water is the same grid without skirts
	water_indices = indices.slice(0, main_index_count)
	water_uvs = uvs.slice(0, total_vertices)
