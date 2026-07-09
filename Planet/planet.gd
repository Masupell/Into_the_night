class_name Planet
extends Node3D

@export var planet_seed: int = 0

@export var resolution := 16

@export var radius := 5000.0
@export var max_height: float = 500.0

@export_group("Terrain Settings")
@export var terrain_noise: FastNoiseLite

@export_group("", "")
@export var max_lod_level := 16
@export var grid_size: int = 16

@onready var chunk_container: Node3D = Node3D.new()
var free_chunks: Array[Chunk] = []

var root_quads: Array[Quad] = []

@export_range(10.0, 40.0) var lod_threshold_deg: float = 20.0
var split_distances: Array[float] = []

@onready var camera = get_viewport().get_camera_3d()

const CUBE_FACES: Array = [
	[Vector3(-1, 1, 1), Vector3( 1, 1, 1), Vector3( 1,-1, 1), Vector3(-1,-1, 1)], # Front (+Z)
	[Vector3( 1, 1, 1), Vector3( 1, 1,-1), Vector3( 1,-1,-1), Vector3( 1,-1, 1)], # Right (+X)
	[Vector3( 1, 1,-1), Vector3(-1, 1,-1), Vector3(-1,-1,-1), Vector3( 1,-1,-1)], # Back  (-Z)
	[Vector3(-1, 1,-1), Vector3(-1, 1, 1), Vector3(-1,-1, 1), Vector3(-1,-1,-1)], # Left  (-X)
	[Vector3(-1, 1,-1), Vector3( 1, 1,-1), Vector3( 1, 1, 1), Vector3(-1, 1, 1)], # Top   (+Y)
	[Vector3(-1,-1, 1), Vector3( 1,-1, 1), Vector3( 1,-1,-1), Vector3(-1,-1,-1)], # Bottom(-Y)
]

var world_image: Image
var world_texture: ImageTexture

var atmosphere: MeshInstance3D

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@export var orbit_speed: float = 0.05
@export var orbit_distance: float = 2000.0

var sun_orbit_angle: float = 0.0

func _ready() -> void:
	#get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAMEwww
	
	planet_seed = randi()
	generate_world_texture()
	
	atmosphere = MeshInstance3D.new()
	var atmosphere_radius: float = radius + max_height + 200.0
	
	var atmosphere_mesh = SphereMesh.new()
	atmosphere_mesh.radius = atmosphere_radius
	atmosphere_mesh.height = atmosphere_radius*2.0
	atmosphere.mesh = atmosphere_mesh
	
	var atmosphere_material = ShaderMaterial.new()
	atmosphere_material.shader = preload("res://Planet/atmosphere.gdshader")
	atmosphere_material.render_priority = -10
	atmosphere_material.set_shader_parameter("planet_radius", radius)
	atmosphere_material.set_shader_parameter("atmosphere_radius", atmosphere_radius)
	atmosphere.material_override = atmosphere_material
	add_child(atmosphere)
	
	sun.global_position = Vector3(0.0, 0.0, orbit_distance)
	sun.look_at(global_position, Vector3.UP)
	
	if not terrain_noise:
		terrain_noise = FastNoiseLite.new()
		terrain_noise.seed = randi()
	
	chunk_container.name = "ChunkPool"
	add_child(chunk_container)
	
	compute_lod_thresholds()
	
	for face_corner in CUBE_FACES:
		var q = Quad.new(self, 0, face_corner)
		root_quads.append(q)
		q.draw_chunk()

func _process(delta: float) -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()
		return
	
	var cam_pos = to_local(camera.global_position) # as long as planet is on 0,0,0 'to_local' does not matter
	var frustum_planes = []
	for p in camera.get_frustum():
		frustum_planes.append(Plane(p.normal, p.d - p.normal.dot(global_position)))
	for q in root_quads:
		q.update_lod(cam_pos, frustum_planes)
	
	sun_orbit_angle += orbit_speed * delta
	var sun_x = cos(sun_orbit_angle) * orbit_distance
	var sun_z = sin(sun_orbit_angle) * orbit_distance
	var new_sun_pos = global_position + Vector3(sun_x, 0.0, sun_z)
	sun.global_position = new_sun_pos
	sun.look_at(global_position, Vector3.UP)
	
	var sun_dir = sun.global_transform.basis.z.normalized()
	var mat = atmosphere.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("sun_dir", sun_dir)
	
	if Input.is_key_pressed(KEY_1):
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	if Input.is_key_pressed(KEY_2):
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	
	if Input.is_key_pressed(KEY_EQUAL):
		orbit_speed += 0.05
	if Input.is_key_pressed(KEY_MINUS):
		orbit_speed = max(orbit_speed - 0.05, 0.0)

func compute_lod_thresholds():
	split_distances.resize(max_lod_level + 1)
	var edge_size: float = (radius * 2.0) / sqrt(3.0)
	
	for level in range(max_lod_level + 1):
		var level_edge = edge_size / pow(2, level)
		var dist = level_edge / tan(deg_to_rad(lod_threshold_deg))
		split_distances[level] = dist


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
	c.mesh = null
	free_chunks.append(c)
	#if c.get_parent():
		#c.get_parent().remove_child(c)


static func spherify(p: Vector3) -> Vector3:
	var x2 := p.x * p.x
	var y2 := p.y * p.y
	var z2 := p.z * p.z
	
	var res := Vector3.ZERO
	res.x = p.x * sqrt(1.0 - y2 / 2.0 - z2 / 2.0 + y2 * z2 / 3.0)
	res.y = p.y * sqrt(1.0 - z2 / 2.0 - x2 / 2.0 + z2 * x2 / 3.0)
	res.z = p.z * sqrt(1.0 - x2 / 2.0 - y2 / 2.0 + x2 * y2 / 3.0)
	return res

static func get_uv_from_vector(pos: Vector3) -> Vector2:
	var n = pos.normalized()
	var phi = atan2(n.z, n.x)
	var theta = asin(n.y)
	
	var u = (phi + PI) / (2.0 * PI)
	var v = (theta + PI / 2.0) / PI
	return Vector2(u, v)

func generate_world_texture():
	world_image = Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	
	var continent_noise = FastNoiseLite.new()
	continent_noise.seed = planet_seed
	continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	continent_noise.frequency = 0.004
	continent_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	continent_noise.fractal_octaves = 5
	continent_noise.fractal_lacunarity = 2.0
	continent_noise.fractal_gain = 0.55
	
	var mountain_noise = FastNoiseLite.new()
	mountain_noise.seed = planet_seed + 1234 # so it is not same seed as continents
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mountain_noise.frequency = 0.007
	mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	mountain_noise.fractal_octaves = 4
	mountain_noise.fractal_gain = 0.6
	
	for y in range(1024):
		for x in range(1024):
			var u = float(x) / 1024.0
			var v = float(y) / 1024.0
			
			var phi = (u * 2.0 * PI) - PI
			var theta = (v * PI) - (PI / 2.0)
			
			var sphere_point = (Vector3(cos(theta) * cos(phi), sin(theta), cos(theta) * sin(phi))) * 150.0
			var continent_value = (continent_noise.get_noise_3dv(sphere_point) + 1.0) * 0.5
			
			var final_height = 0.0
			var sea_level = 0.46
			
			if continent_value < sea_level:
				var ocean_ratio = continent_value / sea_level
				final_height = lerp(0.1, 0.40, ocean_ratio)
			else:
				var land_progress = (continent_value - sea_level) / (1.0 - sea_level)
				var coastal_profile = (mountain_noise.get_noise_3dv(sphere_point * 0.3) + 1.0) * 0.5
				var shoreline_start = lerp(0.40, 0.44, coastal_profile)
				var land_elevation = shoreline_start + (land_progress * 0.2)
				var mountain_mask = smoothstep(0.52, 0.62, continent_value)
				var mountain_value = (mountain_noise.get_noise_3dv(sphere_point * 1.5) + 1.0) * 0.5
				mountain_value = pow(mountain_value, 1.8)
				var headroom = 1.0 - land_elevation
				var allowed_mountain_height = mountain_value * headroom * mountain_mask * 0.96
				final_height = land_elevation + allowed_mountain_height
			
			final_height = clamp(final_height, 0.0, 1.0)
			
			world_image.set_pixel(x, y, Color(final_height, 1.0 if final_height < sea_level else 0.0, 0.0, 1.0))
	
	world_image.save_png("res://test/terrain.png")
	world_texture = ImageTexture.create_from_image(world_image)
