class_name Planet
extends Node3D

@export var planet_seed: int = 0

@export var radius := 5000.0
@export var max_height: float = 200.0#500.0

@export_group("Terrain Settings")
@export var terrain_noise: FastNoiseLite

var detail_noise := FastNoiseLite.new()

@export_group("", "")
@export var max_lod_level := 16 #Only really ever get to 9, so 16, is a bit unnecessary
@export var grid_size: int = 16
@export var terrain_max_tile_level: int = 2 # 2^2 = 4 tiles per face edge at the finest level
@export var terrain_tile_size: int = 129 # Pixels per tile edge, 4 * 128 + 1 = 513 per face at level 2, roughly the 2048 wide earth map at the equator

@onready var chunk_container: Node3D = Node3D.new()
var free_chunks: Array[Chunk] = []

var root_quads: Array[Quad] = []

@export_range(10.0, 40.0) var lod_threshold_deg: float = 20.0
var split_distances: Array[float] = []

@onready var camera = get_viewport().get_camera_3d()
var camera_mode = 2

#var world_image: Image
var terrain_data: TerrainData
var world_texture: ImageTexture

var atmosphere: MeshInstance3D

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@export var real_seconds_per_game_minute: float = 1.0
var time_speed_multiplier: float = 1.0
var orbit_speed: float = 0.0
@export var orbit_distance: float = 7000.0

var sun_orbit_angle: float = 0.0

var terrain_material: ShaderMaterial
var water_material: ShaderMaterial

@export var command_processor: CommandProcessor

var world_commands: WorldCommands

var edge_length: float = (radius * 2.0) / sqrt(3.0)

@export var plane: AirPlane
@export var free_cam: FreeCam
@export var flight_hud: FligthHUD
@export var canvas_layer: CanvasLayer

# True position of the controller that owns the current camera, relative to the planets center
var true_x: float = 0.0
var true_y: float = 0.0
var true_z: float = 0.0

func _ready() -> void:
	#for level in range(17):
		#var chunk_world_size = (radius * 2.0 / sqrt(3.0)) / pow(2, level)
		#print(level, ": ", chunk_world_size)

	free_cam.global_position.z = 12000.0
	#plane.global_position = free_cam.global_position
	seed_origin_from(free_cam.global_position)
	free_cam.global_position = Vector3.ZERO
	plane.global_position = Vector3.ZERO

	planet_seed = randi()
	#generate_world_texture()
	world_from_texture()

	detail_noise.seed = planet_seed + 4321
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.25
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 4
	detail_noise.fractal_gain = 0.5

	terrain_material = ShaderMaterial.new()
	terrain_material.shader = preload("res://Planet/planet.gdshader")
	terrain_material.set_shader_parameter("world_map", world_texture)

	water_material = ShaderMaterial.new()
	water_material.shader = preload("res://Planet/water.gdshader")

	atmosphere = MeshInstance3D.new()
	var atmosphere_radius: float = radius + max_height + 200.0

	var atmosphere_mesh = SphereMesh.new()
	atmosphere_mesh.radius = atmosphere_radius
	atmosphere_mesh.height = atmosphere_radius*2.0
	atmosphere.mesh = atmosphere_mesh

	var atmosphere_material = ShaderMaterial.new()
	atmosphere_material.shader = preload("res://Planet/atmosphere.gdshader")
	atmosphere_material.render_priority = 10
	atmosphere_material.set_shader_parameter("planet_radius", radius)
	atmosphere_material.set_shader_parameter("atmosphere_radius", atmosphere_radius)
	atmosphere.material_override = atmosphere_material
	add_child(atmosphere)

	sun.global_position = Vector3(0.0, 0.0, orbit_distance)
	sun.look_at(global_position, Vector3.UP)

	var real_seconds_per_day = 1440.0 * real_seconds_per_game_minute
	orbit_speed = TAU/real_seconds_per_day

	if not terrain_noise:
		terrain_noise = FastNoiseLite.new()
		terrain_noise.seed = randi()

	chunk_container.name = "ChunkPool"
	add_child(chunk_container)

	compute_lod_thresholds()

	for face in range(6):
		var q = Quad.new(self, 0, CubeSphere.FACES[face], null, Quad.Type.ROOT, face)
		root_quads.append(q)
		q.draw_chunk()

	world_commands = WorldCommands.new(command_processor, self)

func _process(delta: float) -> void:
	terrain_data.update()

	if not camera:
		camera = get_viewport().get_camera_3d()
		return

	#var cam_pos = to_local(camera.global_position) # as long as planet is on 0,0,0 'to_local' does not matter
	var cam_pos = get_true_position()
	var frustum_planes = []
	for p in camera.get_frustum():
		frustum_planes.append(Plane(p.normal, p.d - p.normal.dot(global_position)))
	for q in root_quads:
		q.update_lod(cam_pos, frustum_planes)

	sun_orbit_angle += orbit_speed * delta
	update_sun_position()

	var sun_dir = Vector3(cos(sun_orbit_angle), 0.0, sin(sun_orbit_angle)).normalized()
	var mat = atmosphere.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("sun_dir", sun_dir)

func compute_lod_thresholds():
	split_distances.resize(max_lod_level + 1)
	var edge_size: float = (radius * 2.0) / sqrt(3.0)

	for level in range(max_lod_level + 1):
		var level_edge = edge_size / pow(2, level)
		var level_diagonal = level_edge * sqrt(2.0)
		var dist = level_edge / tan(deg_to_rad(lod_threshold_deg))
		var safety_floor = level_diagonal * 2.2
		split_distances[level] = maxf(dist, safety_floor)


func request_chunk() -> Chunk:
	var c: Chunk
	if free_chunks.is_empty():
		c = Chunk.new()
		chunk_container.add_child(c)
	else:
		c = free_chunks.pop_back()
	c.visible = true
	return c

func return_chunk(c: Chunk):
	c.visible = false
	#c.mesh = null
	free_chunks.append(c)
	#if c.get_parent():
		#c.get_parent().remove_child(c)


func get_true_position() -> Vector3:
	return Vector3(true_x, true_y, true_z)

func shift_origin(moved_by: Vector3):
	if moved_by == Vector3.ZERO:
		return
	true_x += moved_by.x
	true_y += moved_by.y
	true_z += moved_by.z
	global_position = -get_true_position()

	# temprorary for plane
	if camera_mode != 1 and plane:
		plane.global_position -= moved_by

# At start of game and after potential teleports
func seed_origin_from(world_pos: Vector3):
	true_x = world_pos.x
	true_y = world_pos.y
	true_z = world_pos.z
	global_position = -get_true_position()

func world_from_texture():
	var image = load("res://Planet/earth_map.png").get_image()
	terrain_data = TerrainData.new(terrain_max_tile_level, terrain_tile_size, EquirectSource.new(image, 0.08)) # 0.08 is roughly the sea in this map
	world_texture = ImageTexture.create_from_image(image)

func generate_world_texture():
	terrain_data = TerrainData.new(terrain_max_tile_level, terrain_tile_size, NoiseSource.new(planet_seed))

func update_sun_position():
	var sun_x = cos(sun_orbit_angle) * orbit_distance
	var sun_z = sin(sun_orbit_angle) * orbit_distance
	sun.global_position = global_position + Vector3(sun_x, 0, sun_z)
	sun.look_at(global_position, Vector3.UP)

func update_orbit_speed():
	if time_speed_multiplier == 0.0:
		orbit_speed = 0.0
		return
	var real_seconds_per_day = 1440.0 * (real_seconds_per_game_minute / time_speed_multiplier)
	orbit_speed = TAU/real_seconds_per_day

func set_time_hours(target_hours: float):
	var hours = wrapf(target_hours, 0.0, 24.0)

	var planet_up = get_true_position().normalized() # Have to change that later, but for now it works
	var plane_equator = planet_up.slide(Vector3.DOWN).normalized() #Vector3.DOWN is northpole
	var plane_longitude = atan2(plane_equator.z, plane_equator.x)
	sun_orbit_angle = ((hours - 12.0) / 24.0) * TAU + plane_longitude

	update_sun_position()

func set_time_speed(multiplier: float):
	time_speed_multiplier = multiplier
	update_orbit_speed()


func switch_to_free(debug: bool = false):
	var plane_camera = plane.camera
	free_cam.main_camera.rotation = Vector3.ZERO
	free_cam.global_transform = plane_camera.global_transform
	free_cam.main_camera.current = true
	camera = free_cam.main_camera
	free_cam.process_mode = Node.PROCESS_MODE_INHERIT
	canvas_layer.visible = true
	flight_hud.visible = false
	camera_mode = free_cam.set_debug_mode(debug)

func switch_to_plane(): # kind of switches to plane from old free position, because I never changed the code her
	var pivot = plane.pivot
	var spring = plane.spring_arm
	pivot.global_basis = free_cam.global_basis
	var forward = -free_cam.global_basis.z
	plane.global_position = free_cam.global_position + forward * spring.spring_length
	plane.global_basis = free_cam.global_basis
	plane.velocity = Vector3.ZERO
	plane.camera.current = true
	camera = plane.camera
	free_cam.process_mode = Node.PROCESS_MODE_DISABLED
	canvas_layer.visible = false
	flight_hud.visible = true
	camera_mode = 1
