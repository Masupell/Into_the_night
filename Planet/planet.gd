class_name Planet
extends Node3D

@export var resolution := 16

@export var radius := 5000.0
@export var max_height: float = 500.0

@export_group("Terrain Settings")
@export var terrain_noise: FastNoiseLite

@export_group("", "")
@export var max_lod_level := 10
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

func _ready() -> void:
	#get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	
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

func _process(_delta: float) -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()
		return
	
	var cam_pos = to_local(camera.global_position) # as long as planet is on 0,0,0 'to_local' does not matter
	var frustum_planes = []
	for p in camera.get_frustum():
		frustum_planes.append(Plane(p.normal, p.d - p.normal.dot(global_position)))
	for q in root_quads:
		q.update_lod(cam_pos, frustum_planes)

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
