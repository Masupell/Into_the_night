class_name Planet
extends Node3D

@export var planet_seed: int = 0

@export var radius: float = 318550.0 # 1/20 of the Earth
@export var start_altitude: float = 350000.0
@export var max_depth_ratio: float = 1.25 # deepest ocean floor, times max_height (ETOPO: 10752 / 8849)
@export var max_height: float = 1106.0 # Everest, 2.5x scaled up, mountains feel too small otherwise
@export var atmosphere_height: float = 10000.0 # 2x the Earth's, so it stays above the mountains
var atmosphere_radius: float

@export_group("Terrain Settings")
@export var terrain_noise: FastNoiseLite

var detail_noise := FastNoiseLite.new()

@export_group("", "")
@export var max_lod_level := 16 #Only really ever get to 9, so 16, is a bit unnecessary
@export var grid_size: int = 16
@export var collision_radius: float = 300.0 # removed again at 1.5x
@export var collider_budget_ms: float = 2.0 # per frame, nearest first
@export var collider_always_distance: float = 50.0 # closer than this ignores the budget
# Far away chunks get 4x / 2x the grid cells, so distant mountains keep their shape
@export var dense_grid_distance: float = 7500.0:
	set(value):
		dense_grid_distance = value
		_grid_distances_changed()
@export var medium_grid_distance: float = 3000.0:
	set(value):
		medium_grid_distance = value
		_grid_distances_changed()
@export var min_vertex_spacing: float = 1.0 # meters, no finer detail in the data anyway
var lod_level_limit: int
@export var terrain_max_tile_level: int = 6 # baked tiles bring their own
@export var terrain_tile_size: int = 129
@export var earth_meters_per_unit: float = 8849.0 # real meters that become max_height (Everest)

@onready var chunk_container: Node3D = Node3D.new()
var free_chunks: Array[Chunk] = []

var root_quads: Array[Quad] = []

@export_range(10.0, 40.0) var lod_threshold_deg: float = 20.0
var split_distances: Array[float] = []
var terrain_time: float = 0.0 # for the chunk morphing

@onready var camera = get_viewport().get_camera_3d() # main camera, for LOD and culling
var camera_mode = 2 # 1 plane, 2 free cam, 3 debug camera
var main_mode = 2 # 1 plane, 2 free cam, stays during debug
@export var near_per_clearance: float = 0.002
var base_near: Dictionary = {} # Camera3D -> near from the scene

#var world_image: Image
var terrain_data: TerrainData
var world_texture: ImageTexture

var atmosphere: MeshInstance3D

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@export var real_seconds_per_game_minute: float = 1.0
var time_speed_multiplier: float = 1.0
var orbit_speed: float = 0.0
@export var orbit_distance_factor: float = 1.4 # only the direction matters
var orbit_distance: float

var sun_orbit_angle: float = 0.0

@export_group("Stars")
@export var twilight_band: Vector2 = Vector2(-0.12, 0.05) # sun height: all stars below x, none above y
@export var lit_ground_strength: float = 3.0
@export var sun_glare_margin: float = 0.5 # times screen height
@export var star_dim_speed: float = 4.0
@export var star_recover_speed: float = 0.7
@export_group("", "")
var star_visibility: float = 1.0
const STAR_SAMPLE_GRID := 5

var terrain_material: ShaderMaterial
var water_material: ShaderMaterial

@export var command_processor: CommandProcessor

var world_commands: WorldCommands

var min_terrain_radius: float # ocean floor
var edge_length: float

@export var plane: AirPlane
@export var free_cam: FreeCam
@export var flight_hud: FligthHUD
@export var canvas_layer: CanvasLayer

# True position of the current controller, relative to the planets center
var true_x: float = 0.0
var true_y: float = 0.0
var true_z: float = 0.0

func _ready() -> void:
	#for level in range(17):
		#var chunk_world_size = (radius * 2.0 / sqrt(3.0)) / pow(2, level)
		#print(level, ": ", chunk_world_size)

	edge_length = (radius * 2.0) / sqrt(3.0)
	min_terrain_radius = radius - max_depth_ratio * max_height
	atmosphere_radius = radius + atmosphere_height
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
	terrain_material.set_shader_parameter("planet_radius", radius)
	terrain_material.set_shader_parameter("max_height", max_height)
	terrain_material.set_shader_parameter("meters_per_unit", earth_meters_per_unit)

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
	chunk_container.top_level = true
	add_child(chunk_container)

	compute_lod_thresholds()

	for face in range(6):
		var q = Quad.new(self, 0, CubeSphere.FACES[face], null, Quad.Type.ROOT, face)
		root_quads.append(q)
		q.draw_chunk()

	world_commands = WorldCommands.new(command_processor, self)

func _process(delta: float) -> void:
	terrain_time += delta
	RenderingServer.global_shader_parameter_set("terrain_time", terrain_time)
	terrain_data.update()
	for chunk: Chunk in chunk_container.get_children():
		chunk.poll_task()

	if not camera:
		camera = get_viewport().get_camera_3d()
		return

	#var cam_pos = to_local(camera.global_position) # as long as planet is on 0,0,0 'to_local' does not matter
	var cam_pos = get_true_position()
	update_camera_planes(camera)
	var view_camera := get_viewport().get_camera_3d()
	if view_camera and view_camera != camera:
		update_camera_planes(view_camera)
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
	terrain_material.set_shader_parameter("sun_dir", sun_dir)
	terrain_material.set_shader_parameter("planet_center", global_position)
	update_star_visibility(sun_dir, delta)

# Wait for running tasks, otherwise they write into freed chunks
func _exit_tree() -> void:
	for chunk: Chunk in chunk_container.get_children():
		if chunk.active_task_id != -1:
			WorkerThreadPool.wait_for_task_completion(chunk.active_task_id)
			chunk.active_task_id = -1
	terrain_data.wait_for_loading()
	for q in root_quads:
		q.release_tree()
	root_quads.clear()

func compute_lod_thresholds():
	split_distances.resize(max_lod_level + 1)
	var edge_size: float = (radius * 2.0) / sqrt(3.0)

	for level in range(max_lod_level + 1):
		var level_edge = edge_size / pow(2, level)
		var level_diagonal = level_edge * sqrt(2.0)
		var dist = level_edge / tan(deg_to_rad(lod_threshold_deg))
		var safety_floor = level_diagonal * 2.2
		split_distances[level] = maxf(dist, safety_floor)

	# Less than 2x and the stitching breaks
	if dense_grid_distance < medium_grid_distance * 2.0:
		push_warning("dense_grid_distance should be at least 2x medium_grid_distance, chunk edges may not match")

	lod_level_limit = 0
	while lod_level_limit < max_lod_level and edge_size / float(1 << (lod_level_limit + 1)) / grid_size_for_level(lod_level_limit + 1) >= min_vertex_spacing:
		lod_level_limit += 1

# Far: horizon + how far the atmosphere still shows behind it
# Near: grows with the height (not for the plane camera)
func update_camera_planes(cam: Camera3D):
	if not base_near.has(cam):
		base_near[cam] = cam.near
	var pos: Vector3 = get_true_position() + cam.global_position
	var dist := pos.length()

	# under water only the ocean floor blocks the view
	@warning_ignore("incompatible_ternary")
	var occluder: float = radius if dist > radius else min_terrain_radius
	var top := maxf(atmosphere_radius, radius + max_height)
	var to_horizon := sqrt(maxf(0.0, dist * dist - occluder * occluder))
	var behind_horizon := sqrt(top * top - occluder * occluder)
	cam.far = (to_horizon + behind_horizon) * 1.05
	if cam == get_viewport().get_camera_3d():
		(atmosphere.material_override as ShaderMaterial).set_shader_parameter("max_draw_distance", cam.far * 0.9)

	var near: float = base_near[cam]
	if cam != plane.camera:
		var clearance := dist - (radius + max_height)
		near = maxf(near, clearance * near_per_clearance)
	cam.near = near

# Colliders for visible chunks near the player, nearest first, within the budget
func update_colliders():
	var player := get_true_position()
	var wanted := [] # [center distance, surface distance, chunk]
	for chunk: Chunk in chunk_container.get_children():
		if not chunk.is_ready or chunk.owner_quad == null or chunk.is_pending_recycle:
			continue
		var distance := chunk.owner_quad.surface_distance(player)
		if chunk.collider == null or chunk.collider_outdated:
			if distance < collision_radius and chunk.visible:
				# sorted by center, the surface distance is 0 for all chunks around
				wanted.append([chunk.owner_quad.center_distance(player), distance, chunk])
		elif distance > collision_radius * 1.5:
			chunk.remove_collider()

	wanted.sort_custom(func(a, b): return a[0] < b[0])
	var start := Time.get_ticks_usec()
	var budget_usec := collider_budget_ms * 1000.0
	for entry in wanted:
		if Time.get_ticks_usec() - start > budget_usec and entry[1] > collider_always_distance:
			continue
		entry[2].build_collider()

# Grid cells per chunk edge, more for far away chunks
func grid_size_for_level(level: int) -> int:
	if split_distances[level] >= dense_grid_distance:
		return grid_size * 4
	elif split_distances[level] >= medium_grid_distance:
		return grid_size * 2
	return grid_size

func _grid_distances_changed():
	if not is_node_ready():
		return
	compute_lod_thresholds()
	for q in root_quads:
		q.force_rebuild_leaves()

# On the cube, only relative between levels
func vertex_spacing_for_level(level: int) -> float:
	return edge_length / float(1 << level) / grid_size_for_level(level)


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

	if main_mode != 1 and plane:
		plane.global_position -= moved_by
	if camera_mode == 3:
		free_cam.debug_camera.global_position -= moved_by

# Like ground_height_at, but loads the finest tile, NAN until then
func ground_height_loading(dir: Vector3) -> float:
	var face := CubeSphere.get_face(dir)
	var h = terrain_data.sample_finest(face, CubeSphere.get_face_uv(dir, face))
	if is_nan(h):
		return NAN
	return Chunk.surface_heights(detail_noise, PackedVector3Array([dir.normalized()]), PackedFloat32Array([h]), max_height, radius / Chunk.DETAIL_TUNED_FOR_RADIUS)[0]

# From the finest loaded tile, ocean floor if nothing is loaded yet
func ground_height_at(dir: Vector3) -> float:
	var face := CubeSphere.get_face(dir)
	var h := terrain_data.sample_loaded(face, CubeSphere.get_face_uv(dir, face))
	if is_nan(h):
		return min_terrain_radius - radius
	return Chunk.surface_heights(detail_noise, PackedVector3Array([dir.normalized()]), PackedFloat32Array([h]), max_height, radius / Chunk.DETAIL_TUNED_FOR_RADIUS)[0]

# Pushes the controller back up if it fell through the ground
func keep_above_ground(clearance: float) -> bool:
	var pos := get_true_position()
	var dist := pos.length()
	var dir := pos / dist if dist > 1.0 else Vector3.UP
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

# Not moved with the planet node, float32 would jitter
func update_chunk_positions():
	for c in chunk_container.get_children():
		c.update_position()

func world_from_texture():
	var image = load("res://Planet/earth_map.png").get_image()
	terrain_data = TerrainData.new(terrain_max_tile_level, terrain_tile_size, ImageSource.new(image, 0.08)) # 0.08 is roughly the sea
	world_texture = ImageTexture.create_from_image(image)

func world_from_etopo():
	terrain_data = TerrainData.new(terrain_max_tile_level, terrain_tile_size, EtopoSource.new("res://data/etopo_60s", earth_meters_per_unit))

# Baked with tools/bake_tiles.py
func world_from_baked_tiles():
	var source := DiskSource.new("res://data/earth_tiles", earth_meters_per_unit, "res://data/earth_moisture", "res://data/earth_water")
	terrain_data = TerrainData.new(source.max_level, source.tile_size, source)

func generate_world_texture():
	terrain_data = TerrainData.new(terrain_max_tile_level, terrain_tile_size, NoiseSource.new(planet_seed))

func update_sun_position():
	var sun_x = cos(sun_orbit_angle) * orbit_distance
	var sun_z = sin(sun_orbit_angle) * orbit_distance
	sun.global_position = global_position + Vector3(sun_x, 0, sun_z)
	sun.look_at(global_position, Vector3.UP)

# Stars fade out like the eye adapts to the brightest thing: day sky, the sun, sunlit ground
func update_star_visibility(sun_dir: Vector3, delta: float):
	var cam := get_viewport().get_camera_3d()
	var pos := cam.global_position - global_position
	var dist := pos.length()
	var up := pos / dist
	var screen := get_viewport().get_visible_rect().size

	# day sky, fades towards space
	var air := 1.0 - smoothstep(0.3 * atmosphere_height, atmosphere_height, dist - radius)
	var daylight := smoothstep(twilight_band.x, twilight_band.y, up.dot(sun_dir)) * air

	# the sun, unless the planet is in front of it
	var planet_angle := asin(minf(1.0, radius / dist))
	var sun_free := smoothstep(-0.02, 0.02, (-up).angle_to(sun_dir) - planet_angle)
	var glare := 0.0
	var sun_point := cam.global_position + sun_dir * 1000.0
	if not cam.is_position_behind(sun_point):
		var p := cam.unproject_position(sun_point)
		var outside := Vector2(maxf(0.0, maxf(-p.x, p.x - screen.x)), maxf(0.0, maxf(-p.y, p.y - screen.y))).length()
		glare = (1.0 - smoothstep(0.0, sun_glare_margin * screen.y, outside)) * sun_free

	# sunlit ground, rays over the screen against the sea level sphere
	var lit := 0.0
	var c := dist * dist - radius * radius
	for i in STAR_SAMPLE_GRID:
		for j in STAR_SAMPLE_GRID:
			var screen_point := Vector2((i + 0.5) / STAR_SAMPLE_GRID * screen.x, (j + 0.5) / STAR_SAMPLE_GRID * screen.y)
			var ray := cam.project_ray_normal(screen_point)
			var b := pos.dot(ray)
			var d := b * b - c
			if d < 0.0:
				continue
			var t := -b - sqrt(d)
			if t < 0.0: # below sea level
				t = -b + sqrt(d)
			if t < 0.0:
				continue
			var hit_up := (pos + ray * t).normalized()
			lit += smoothstep(-0.1, 0.15, hit_up.dot(sun_dir)) # same as the terrain shader
	lit /= STAR_SAMPLE_GRID * STAR_SAMPLE_GRID

	var brightness := clampf(maxf(maxf(daylight, glare), lit * lit_ground_strength), 0.0, 1.0)
	var target := 1.0 - brightness
	var speed: float = star_dim_speed if target < star_visibility else star_recover_speed
	star_visibility = lerpf(star_visibility, target, 1.0 - exp(-speed * delta))
	RenderingServer.global_shader_parameter_set("star_visibility", star_visibility)

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


# Debug camera: LOD and colliders keep following the main controller
func switch_to_free(debug: bool = false):
	if debug:
		var view_camera := get_viewport().get_camera_3d()
		free_cam.process_mode = Node.PROCESS_MODE_INHERIT
		camera_mode = free_cam.set_debug_mode(true, view_camera.global_transform)
		canvas_layer.visible = true
		flight_hud.visible = false
		return

	if main_mode == 1: # start at the plane view
		free_cam.main_camera.rotation = Vector3.ZERO
		free_cam.global_transform = plane.camera.global_transform
	main_mode = 2
	camera = free_cam.main_camera
	free_cam.process_mode = Node.PROCESS_MODE_INHERIT
	canvas_layer.visible = true
	flight_hud.visible = false
	camera_mode = free_cam.set_debug_mode(false)

# --- Coordinates ---
# Degrees, north pole at -Y, longitude 0 along +X, growing towards +Z. Height above sea level

# -> Vector3(latitude, longitude, height)
func to_lat_lon_height(pos: Vector3) -> Vector3:
	var dist := pos.length()
	if dist < 0.001:
		return Vector3(0.0, 0.0, -radius)
	var n := pos / dist
	return Vector3(rad_to_deg(-asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(n.z, n.x)), dist - radius)

func from_lat_lon_height(latitude: float, longitude: float, height: float) -> Vector3:
	var lat := deg_to_rad(latitude)
	var lon := deg_to_rad(longitude)
	return Vector3(cos(lat) * cos(lon), -sin(lat), cos(lat) * sin(lon)) * (radius + height)

# Planet space position of what the player controls
func controlled_position() -> Vector3:
	if camera_mode == 3:
		return get_true_position() + free_cam.debug_camera.global_position
	return get_true_position()

func plane_position() -> Vector3:
	return plane.global_position - global_position

# Keeps heading and tilt relative to the ground
func _turn_between(from: Vector3, to: Vector3) -> Basis:
	var a := from.normalized()
	var b := to.normalized()
	if absf(a.y) < 0.9999 and absf(b.y) < 0.9999:
		return _ground_frame(b) * _ground_frame(a).inverse()
	if a.dot(b) < -0.9999: # other side
		return Basis(a.cross(Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.UP).normalized(), PI)
	return Basis(Quaternion(a, b))

# x: east, y: up, z: north (north pole is -Y)
func _ground_frame(up: Vector3) -> Basis:
	var north := Vector3.DOWN.slide(up).normalized()
	return Basis(north.cross(up), up, north)

# Moves what the player controls to a planet space position
func teleport_controlled(target: Vector3):
	var current := controlled_position()
	var turn := _turn_between(current, target)
	if camera_mode == 3:
		var debug_camera: Camera3D = free_cam.debug_camera
		debug_camera.global_basis = turn * debug_camera.global_basis
		debug_camera.global_position = target - get_true_position()
		return
	if main_mode == 1:
		plane.global_basis = turn * plane.global_basis
		plane.pivot.global_basis = turn * plane.pivot.global_basis
	else:
		free_cam.main_camera.global_basis = turn * free_cam.main_camera.global_basis
	shift_origin(target - current)

func teleport_plane(target: Vector3):
	var current := plane_position()
	var turn := _turn_between(current, target)
	plane.global_basis = turn * plane.global_basis
	plane.pivot.global_basis = turn * plane.pivot.global_basis
	if main_mode == 1:
		shift_origin(target - current)
	else:
		plane.global_position = target - get_true_position()

# Plane in front of the camera, level, standing still
func move_plane_to_view():
	var view_camera := get_viewport().get_camera_3d()
	var look := -view_camera.global_basis.z
	var plane_pos: Vector3 = view_camera.global_position + look * plane.spring_arm.spring_length
	var up := (get_true_position() + plane_pos).normalized()
	var forward := look.slide(up).normalized()
	if forward.length_squared() < 0.001:
		forward = view_camera.global_basis.y.slide(up).normalized()

	plane.global_position = plane_pos
	plane.global_basis = Basis.looking_at(-forward, up) # flies along +Z
	plane.pivot.global_basis = Basis.looking_at(forward, up)
	plane.velocity = Vector3.ZERO
	plane.move_speed = 0.0
	plane.fall_speed = 0.0

func switch_to_plane():
	free_cam.set_debug_mode(false)
	if main_mode != 1:
		main_mode = 1
		var plane_pos: Vector3 = plane.global_position
		shift_origin(plane_pos)
		plane.global_position = Vector3.ZERO
	plane.camera.current = true
	camera = plane.camera
	free_cam.process_mode = Node.PROCESS_MODE_DISABLED
	canvas_layer.visible = false
	flight_hud.visible = true
	camera_mode = 1
