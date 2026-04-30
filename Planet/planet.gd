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

func update_terrain():
	if !terrain:
		pass
	
	var mesh_arrays = create_sphere(radius, detail)
	terrain.clear_surfaces()
	terrain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)

func update_water():
	pass
