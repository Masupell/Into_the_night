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

#var world_image: Image
var terrain_data: TerrainData
var world_texture: ImageTexture

var atmosphere: MeshInstance3D

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@export var orbit_speed: float = 0.05
@export var orbit_distance: float = 2000.0

var sun_orbit_angle: float = 0.0

var terrain_material: ShaderMaterial
var water_material: ShaderMaterial

func _ready() -> void:
	#get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	
	#$Player.global_position = $Camera.global_position
	$Plane.global_position = $Camera.global_position
	
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
	
	#Temp
	if Input.is_action_just_pressed("ui_left"):
		var plane_camera = $Plane/Pivot/SpringArm3D/Camera3D
		$Camera.global_transform = plane_camera.global_transform
		$Camera/Camera3D.current = true
		camera = $Camera/Camera3D
		$Plane.process_mode = Node.PROCESS_MODE_DISABLED
		$Camera.process_mode = Node.PROCESS_MODE_INHERIT
		#$Plane.active = false
		#$CanvasLayer/Label.visible = true
	if Input.is_action_just_pressed("ui_right"):
		$Plane.global_position = $Camera.global_position
		$Plane.velocity = Vector3.ZERO
		#
		# Copy camera orientation directly to plane
		#
		$Plane.global_basis = $Camera.global_basis
		#
		# Make player camera match plane
		#
		#$Plane/CameraPivot.rotation = Vector3.ZERO
		$Plane/Pivot/SpringArm3D/Camera3D.current = true
		camera = $Plane/Pivot/SpringArm3D/Camera3D
		$Camera.process_mode = Node.PROCESS_MODE_DISABLED
		$Plane.process_mode = Node.PROCESS_MODE_INHERIT
		#$Plane.active = true
		#$CanvasLayer/Label.visible = false
	#if Input.is_action_just_pressed("ui_left"):
		#var forward = -$Player/CameraPivot/Camera3D.global_transform.basis.z
		#var up = $Player.global_position.normalized()
		#$Camera.global_transform = Transform3D(Basis.looking_at(forward, up), $Player/CameraPivot/Camera3D.global_position)
		#$Camera/Camera3D.rotation = Vector3.ZERO
		#$Camera/Camera3D.current = true
		#camera = $Camera/Camera3D
		#$Player.process_mode = Node.PROCESS_MODE_DISABLED
		#$Camera.process_mode = Node.PROCESS_MODE_INHERIT
		#$Player.active = false
		#$CanvasLayer/Label.visible = true
	#if Input.is_action_just_pressed("ui_right"):
		#$Player.global_position = $Camera.global_position
		#$Player.velocity = Vector3.ZERO
		#var up = $Player.global_position.normalized()
		#var camera_forward = -$Camera.global_transform.basis.z
		#var flat_forward = camera_forward - up * camera_forward.dot(up)
		#if flat_forward.length() > 0.001:
			#flat_forward = flat_forward.normalized()
			#$Player.look_direction = flat_forward
			#$Player.basis = Basis.looking_at(flat_forward, up)
			#var local_forward = $Player.global_transform.basis.inverse() * camera_forward
			#$Player.camera_pitch = atan2(local_forward.y, -local_forward.z)
		#$Player/CameraPivot.rotation.x = $Player.camera_pitch
		#$Player/CameraPivot/Camera3D.current = true
		#camera = $Player/CameraPivot/Camera3D
		#$Camera.process_mode = Node.PROCESS_MODE_DISABLED
		#$Player.process_mode = Node.PROCESS_MODE_INHERIT
		#$Player.active = true
		#$CanvasLayer/Label.visible = false

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

func world_from_texture():
	terrain_data = TerrainData.new(2048, 2048)
	var image = load("res://temp/earth_map.png").get_image()
	terrain_data.load_from_image(image)
	world_texture = ImageTexture.create_from_image(image)
	#world_image = load("res://temp/earth_map.png").get_image()#Image.load_from_file("res://temp/earth_map.png")
	#world_texture = ImageTexture.create_from_image(world_image)

func generate_world_texture():
	#world_image = Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	terrain_data = TerrainData.new(2048, 2048)
	
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
	
	for y in range(2048):
		for x in range(2048):
			var u = float(x) / 2048.0
			var v = float(y) / 2048.0
			
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
			
			terrain_data.set_height(x, y, final_height)
			#world_image.set_pixel(x, y, Color(final_height, 1.0 if final_height < sea_level else 0.0, 0.0, 1.0))
	
	var preview = terrain_data.to_image()
	preview.save_png("res://test/terrain.png")
	world_texture = ImageTexture.create_from_image(preview)
	#world_image.save_png("res://test/terrain.png")
	#world_texture = ImageTexture.create_from_image(world_image)
