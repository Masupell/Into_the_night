class_name TerrainTile
extends RefCounted

# One square piece of a cube face. Pixel 0 and size - 1 lie exactly on the tile borders,
# so neighbouring tiles share their border values (same as the faces do)
var face: int
var tile_x: int
var tile_y: int
var size: int # pixels per edge

var heights: PackedFloat32Array

func _init(_face: int, _tile_x: int, _tile_y: int, _size: int) -> void:
	face = _face
	tile_x = _tile_x
	tile_y = _tile_y
	size = _size
	heights.resize(size * size)

func get_height(x: int, y: int) -> float:
	return heights[x + y * size]

func set_height(x: int, y: int, value: float):
	heights[x + y * size] = value
