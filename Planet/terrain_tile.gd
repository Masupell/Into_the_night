class_name TerrainTile
extends RefCounted

# One square piece of a cube face, border pixels are shared with the neighbours.
# Every level splits each tile into 4, like the quadtree
var face: int
var level: int
var tile_x: int
var tile_y: int
var size: int # pixels per edge
var tiles_per_face: int # per edge

var heights: PackedFloat32Array
# 0 desert, 1 rainforest. Coarser grid, MOISTURE_SIZE - 1 has to divide size - 1
const MOISTURE_SIZE := 33
var moisture: PackedFloat32Array
# Water surface, same units as the heights, below the ground where there is none.
# Coarse too, the shore comes from the ground
const WATER_SIZE := 33
var water: PackedFloat32Array

func _init(_face: int, _level: int, _tile_x: int, _tile_y: int, _size: int) -> void:
	face = _face
	level = _level
	tile_x = _tile_x
	tile_y = _tile_y
	size = _size
	tiles_per_face = 1 << level
	heights.resize(size * size)
	moisture.resize(MOISTURE_SIZE * MOISTURE_SIZE)
	water.resize(WATER_SIZE * WATER_SIZE)

func get_height(x: int, y: int) -> float:
	return heights[x + y * size]

func set_height(x: int, y: int, value: float):
	heights[x + y * size] = value

# Face pixel coordinates, so shared border pixels match exactly
func pixel_to_dir(x: int, y: int) -> Vector3:
	return grid_to_dir(x, y, size)

# Same for the moisture grid
func moisture_pixel_to_dir(x: int, y: int) -> Vector3:
	return grid_to_dir(x, y, MOISTURE_SIZE)

func grid_to_dir(x: int, y: int, grid_size: int) -> Vector3:
	var face_pixels := float(tiles_per_face * (grid_size - 1))
	var uv := Vector2(tile_x * (grid_size - 1) + x, tile_y * (grid_size - 1) + y) / face_pixels
	return CubeSphere.face_to_sphere(face, uv)
