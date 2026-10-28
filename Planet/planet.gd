class_name Planet
extends Node3D

@export var planet_seed: int = 0

@export var radius := 63710#5000.0
@export var start_altitude := 70000.0
@export var max_depth_ratio: float = 1.25 # deepest ocean floor below sea level, times max_height (ETOPO: 10752 / 8849 = 1.22)
@export var max_height: float = 442.4#88.48#200.0#500.0
@export var atmosphere_radius: float = radius+5000.0

@export_group("Terrain Settings")
@export var terrain_noise: FastNoiseLite

var detail_noise := FastNoiseLite.new()

@export_group("", "")
@export var max_lod_level := 16 #Only really ever get to 9, so 16, is a bit unnecessary
@export var grid_size: int = 16
@export var collision_radius: float = 300.0 # chunks this close to the player get a collider, lose it again at 1.5x
@export var collider_budget_ms: float = 2.0 # time per frame for making colliders, nearest first, the rest waits for the next frames
@export var collider_always_distance: float = 50.0 # closer than this a collider is made right away, even over the budget
@export var min_vertex_spacing: float = 1.0 # meters, chunks don't split further than this, the data has no finer detail anyway
var lod_level_limit: int # max_lod_level, or lower if vertices would get closer than min_vertex_spacing
@export var terrain_max_tile_level: int = 6 # 2^6 * 128 + 1 = 8193 pixels per face edge, ETOPO 60s has 5400 per face (90 degrees). Baked tiles bring their own
@export var terrain_tile_size: int = 129 # Pixels per tile edge
@export var earth_meters_per_unit: float = 8849.0 # Real meters that become max_height, Everest = max_height

@onready var chunk_container: Node3D = Node3D.new()
var free_chunks: Array[Chunk] = []

var root_quads: Array[Quad] = []

@export_range(10.0, 40.0) var lod_threshold_deg: float = 20.0
var split_distances: Array[float] = []

@onready var camera = get_viewport().get_camera_3d()
var camera_mode = 2
@export var near_per_clearance: float = 0.002 # near plane grows with the distance above the highest mountains (free cam only)
var base_near: Dictionary = {} # Camera3D -> near set in the scene, the near plane never gets smaller than that

#var world_image: Image
var terrain_data: TerrainData
var world_texture: ImageTexture

var atmosphere: MeshInstance3D

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@export var real_seconds_per_game_minute: float = 1.0
var time_speed_multiplier: float = 1.0
var orbit_speed: float = 0.0
@export var orbit_distance_factor: float = 1.4 # debug sun sphere distance, times radius
var orbit_distance: float

var sun_orbit_angle: float = 0.0

var terrain_material: ShaderMaterial
var water_material: ShaderMaterial

@export var command_processor: CommandProcessor

var world_commands: WorldCommands

var min_terrain_radius: float # lowest possible ground (ocean floor), set in _ready
var edge_length: float # set in _ready, an initializer here would still use the default radius, not the one from the scene

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

	edge_length = (radius * 2.0) / sqrt(3.0)
	min_terrain_radius = radius - max_depth_ratio * max_height
	orbit_distance = radius * orbit_distance_factor

	free_cam.global_position.z = radius + start_altitude
	#plane.global_position = free_cam.global_position
	seed_origin_from(free_cam.global_position)
	free_cam.global_position = Vector3.ZERO
	plane.global_position = Vector3.ZERO

	planet_seed = randi()
	#generate_world_texture()
	#world_from_texture()
	#world_from_etopo()
	world_from_baked_tiles()

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
	chunk_container.top_level = true # stays at the world origin, chunks position themselves (see update_chunk_positions)
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
	update_camera_planes()
	var frustum_planes = []
	for p in camera.get_frustum():
		frustum_planes.append(Plane(p.normal, p.d - p.normal.dot(global_position)))
	for q in root_quads:
		q.update_lod(cam_pos, frustum_planes)
	update_colliders()

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

	lod_level_limit = 0
	while lod_level_limit < max_lod_level and edge_size / float(1 << (lod_level_limit + 1)) / grid_size_for_level(lod_level_limit + 1) >= min_vertex_spacing:
		lod_level_limit += 1

# Far plane: nothing is visible past the horizon, except things sticking up behind it, the highest being the atmosphere.
# So far = distance to the horizon + how far behind the horizon the top of the atmosphere still shows.
# Near plane: grows with the distance to the highest possible ground, so near / far stays small high up.
# Not in plane mode, the plane itself is right in front of the camera there
func update_camera_planes():
	if not base_near.has(camera):
		base_near[camera] = camera.near
	var pos: Vector3 = get_true_position() + camera.global_position # plane camera is behind the plane, debug camera elsewhere
	var dist := pos.length()

	# above water the sea surface blocks the view, under water only the ocean floor does
	@warning_ignore("incompatible_ternary")
	var occluder: float = radius if dist > radius else min_terrain_radius
	var top := maxf(atmosphere_radius, radius + max_height)
	var to_horizon := sqrt(maxf(0.0, dist * dist - occluder * occluder))
	var behind_horizon := sqrt(top * top - occluder * occluder)
	camera.far = (to_horizon + behind_horizon) * 1.05
	(atmosphere.material_override as ShaderMaterial).set_shader_parameter("max_draw_distance", camera.far * 0.9)

	var near: float = base_near[camera]
	if camera_mode != 1:
		var clearance := dist - (radius + max_height)
		near = maxf(near, clearance * near_per_clearance)
	camera.near = near

# Colliders for the shown chunks near the player. Distance to the chunk's real height range (ocean floor up to the water
# surface under water), not its bounding box: that reaches from the ocean floor to the highest mountain and on a slope
# of the planet is hundreds of meters wide, then everything nearby counted as distance 0.
# Made nearest first within collider_budget_ms per frame, so arriving fast at the ground doesn't make them all in one frame.
# Only shown chunks: hidden ones (finished children waiting for their siblings, coarse ones about to be replaced)
# would contain the player just as much and use up the budget
func update_colliders():
	var player := get_true_position()
	var wanted := [] # [center distance, surface distance, chunk]
	for chunk: Chunk in chunk_container.get_children():
		if not chunk.is_ready or chunk.owner_quad == null or chunk.is_pending_recycle:
			continue
		var distance := chunk.owner_quad.surface_distance(player)
		if chunk.collider == null or chunk.collider_outdated:
			if distance < collision_radius and chunk.visible:
				# ordered by the center: the surface distance is 0 for every chunk the player is above or next to,
				# the one right under the player has the closest center
				wanted.append([chunk.owner_quad.center_distance(player), distance, chunk])
		elif distance > collision_radius * 1.5: # a bit further than added, so they don't flicker on and off at the edge
			chunk.remove_collider()

	wanted.sort_custom(func(a, b): return a[0] < b[0])
	var start := Time.get_ticks_usec()
	var budget_usec := collider_budget_ms * 1000.0
	for entry in wanted:
		if Time.get_ticks_usec() - start > budget_usec and entry[1] > collider_always_distance:
			continue
		entry[2].build_collider()

# Vertices per chunk edge, bigger chunks get more so the curvature stays smooth
func grid_size_for_level(level: int) -> int:
	var level_edge = edge_length / float(1 << level) # 2^level by bitshifting
	if level_edge > 2500.0: # 2.5km across
		return grid_size * 4
	elif level_edge > 1000.0: # 1km across
		return grid_size * 2
	return grid_size


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
	update_chunk_positions()

	# temprorary for plane
	if camera_mode != 1 and plane:
		plane.global_position -= moved_by

# Meters above the radius of the ground under dir, from the finest loaded tile (without loading anything)
# Ocean floor depth if nothing is loaded there yet, so it is never above the real ground
func ground_height_at(dir: Vector3) -> float:
	var face := CubeSphere.get_face(dir)
	var h := terrain_data.sample_loaded(face, CubeSphere.get_face_uv(dir, face))
	if is_nan(h):
		return min_terrain_radius - radius
	return Chunk.surface_heights(detail_noise, PackedVector3Array([dir.normalized()]), PackedFloat32Array([h]), max_height, radius / Chunk.DETAIL_TUNED_FOR_RADIUS)[0]

# If the active controller (free cam / plane) ended up below the ground (too fast for its collision, or no collider yet),
# push it back out along the up direction, clearance meters above the ground. Returns true if it had to
func keep_above_ground(clearance: float) -> bool:
	var pos := get_true_position()
	var dist := pos.length()
	var dir := pos / dist if dist > 1.0 else Vector3.UP # at the very center there is no up, pick any
	var ground := radius + ground_height_at(dir)
	if dist >= ground:
		return false
	shift_origin(dir * (ground + clearance) - pos)
	return true

# At start of game and after potential teleports
func seed_origin_from(world_pos: Vector3):
	true_x = world_pos.x
	true_y = world_pos.y
	true_z = world_pos.z
	global_position = -get_true_position()
	update_chunk_positions()

# Chunks are not moved by the planet node (float32: at 300km that would be ~3cm off and jitter),
# each one is placed at its center - true position, computed in doubles
func update_chunk_positions():
	for c in chunk_container.get_children():
		c.update_position()

func world_from_texture():
	var image = load("res://Planet/earth_map.png").get_image()
	terrain_data = TerrainData.new(terrain_max_tile_level, terrain_tile_size, ImageSource.new(image, 0.08)) # 0.08 is roughly the sea in this map
	world_texture = ImageTexture.create_from_image(image)

func world_from_etopo():
	terrain_data = TerrainData.new(terrain_max_tile_level, terrain_tile_size, EtopoSource.new("res://data/etopo_60s", earth_meters_per_unit))

# Tiles baked with tools/bake_tiles.py, level count and tile size come from the baked data
func world_from_baked_tiles():
	var source := DiskSource.new("res://data/earth_tiles", earth_meters_per_unit)
	terrain_data = TerrainData.new(source.max_level, source.tile_size, source)

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
