@tool
class_name Planet
extends Node3D

@export_group("Sphere")
@export var radius := 8.0:
	set(new_radius):
		radius = maxf(1.0, new_radius)
		update_terrain()
		update_water()
@export var detail := 64:
		set(new_detail):
			detail = maxi(1, new_detail)
			update_terrain()

@export_group("Terrain")
@export var noise := FastNoiseLite.new():
	set(new_noise):
		noise = new_noise
		if noise:
			noise.changed.connect(update_terrain)
@export var height := 1.0:
	set(new_height):
		height = maxf(0.0, new_height)
		update_terrain()
		update_water()

@export_group("Water")

var terrain := ArrayMesh.new()
var water := ArrayMesh.new()

func _ready() -> void:
	$Terrain.mesh = terrain
	$Water.mesh = water
	update_terrain()
	update_water()

func create_sphere(sphere_radius: float, sphere_detail: int) -> Array:
	var sphere = SphereMesh.new()
	sphere.radius = sphere_radius
	sphere.height = sphere_radius*2.0
	
	sphere.radial_segments = sphere_detail * 2
	sphere.rings = sphere_detail
	
	return sphere.get_mesh_arrays()

func get_noise(vertex: Vector3) -> float:
	return (noise.get_noise_3dv(vertex.normalized() * 2.0) + 1.0) / 2.0 * height

func update_terrain():
	if !terrain or !noise:
		pass
	
	var mesh_arrays = create_sphere(radius, detail)
	var vertices: PackedVector3Array = mesh_arrays[ArrayMesh.ARRAY_VERTEX]
	for i: int in vertices.size():
		var vertex := vertices[i]
		vertex += vertex.normalized() * get_noise(vertex)
		vertices[i] = vertex
	
	terrain.clear_surfaces()
	terrain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)

func update_water():
	pass
