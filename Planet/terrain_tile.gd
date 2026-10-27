class_name TerrainTile
extends RefCounted

# One square piece of a cube face. Pixel 0 and size - 1 lie exactly on the tile borders,
# so neighbouring tiles share their border values (same as the faces do)
# Level 0 is one tile for the whole face, every level splits each tile into 4 (like the quadtree),
# so every level has the same pixels per tile, but twice the detail
var face: int
var level: int
var tile_x: int
var tile_y: int
var size: int # pixels per edge
var tiles_per_face: int # per edge, 2^level

var heights: PackedFloat32Array

func _init(_face: int, _level: int, _tile_x: int, _tile_y: int, _size: int) -> void:
	face = _face
	level = _level
	tile_x = _tile_x
	tile_y = _tile_y
	size = _size
	tiles_per_face = 1 << level
	heights.resize(size * size)

func get_height(x: int, y: int) -> float:
	return heights[x + y * size]

func set_height(x: int, y: int, value: float):
	heights[x + y * size] = value

# Direction on the sphere of a tile pixel. Uses whole face pixel coordinates,
# so a shared border pixel gives exactly the same direction in both tiles
func pixel_to_dir(x: int, y: int) -> Vector3:
	var face_pixels := float(tiles_per_face * (size - 1))
	var uv := Vector2(tile_x * (size - 1) + x, tile_y * (size - 1) + y) / face_pixels
	return CubeSphere.face_to_sphere(face, uv)
