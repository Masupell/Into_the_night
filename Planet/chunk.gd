class_name Chunk
extends MeshInstance3D

const DETAIL_TUNED_FOR_HEIGHT := 200.0 # max_height the detail noise amplitudes below were tuned for, scales with it
const DETAIL_TUNED_FOR_RADIUS := 5000.0 # radius the detail noise frequencies were tuned for, so features keep their size in meters

var water_mesh_instance: MeshInstance3D

var active_task_id: int = -1
var generation_id: int = 1
var task_result: Dictionary = {} # written by the worker task, only read on the main thread once that task is finished

var is_pending_recycle: bool = false
var is_ready: bool = false

var redraw_requested: bool = false
var waiting_for_tiles: bool = false
var owner_quad: Quad = null

var planet: Planet # Easier with reference right now

# Collider: made by Planet.update_colliders, only near the player and a few per frame (adding one to the physics world
# is the expensive part). Mesh vertices and triangles are kept for it, the list of triangle corners is only built then
var collision_vertices: PackedVector3Array
var collision_indices: PackedInt32Array
var collider: StaticBody3D = null
var collider_outdated: bool = false # mesh was rebuilt, the old collider stays until the new one is made

# Mesh vertices are relative to this point (planet space, double precision), so they stay small and precise.
# The chunk node sits at center - camera position, computed in doubles, see Planet.shift_origin
var center: PackedFloat64Array

# Called by the planet every frame before the LOD update, so a finished chunk is used in the same frame.
# The result is picked up here instead of call_deferred from the worker: a deferred call to a chunk that got freed
# in between (quitting) is an error
func poll_task() -> void:
	if active_task_id != -1:
		if WorkerThreadPool.is_task_completed(active_task_id):
			WorkerThreadPool.wait_for_task_completion(active_task_id)
			active_task_id = -1
			var result := task_result
			task_result = {}

			if is_pending_recycle:
				is_pending_recycle = false
				completely_reset_and_return()
				return
			if not result.is_empty():
				apply_generation_results(result)
			if redraw_requested:
				redraw_requested = false
				if owner_quad:
					owner_quad.draw_chunk()
	elif waiting_for_tiles:
		waiting_for_tiles = false
		if owner_quad:
			owner_quad.draw_chunk()


func recycle():
	generation_id += 1
	visible = false

	if active_task_id != -1:
		is_pending_recycle = true
	else:
		completely_reset_and_return()


func completely_reset_and_return():
	self.mesh = null
	is_ready = false
	redraw_requested = false
	waiting_for_tiles = false
	owner_quad = null
	center = PackedFloat64Array()
	if water_mesh_instance:
		water_mesh_instance.mesh = null
	remove_collider()
	collision_vertices = PackedVector3Array()
	collision_indices = PackedInt32Array()
	planet.return_chunk(self)

func build_collider():
	var faces := PackedVector3Array() # 3 vertices per triangle
	faces.resize(collision_indices.size())
	for i in range(collision_indices.size()):
		faces[i] = collision_vertices[collision_indices[i]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape
	var body := StaticBody3D.new()
	body.add_child(collision_shape)
	remove_collider()
	add_child(body)
	collider = body

func remove_collider():
	if collider:
		collider.queue_free()
		collider = null
	collider_outdated = false


func update_position():
	if center.is_empty():
		return
	position = Vector3(center[0] - planet.true_x, center[1] - planet.true_y, center[2] - planet.true_z)

# On Main Thread
func apply_generation_results(total_data: Dictionary):
	if total_data["gen_id"] != generation_id:
		return

	center = total_data["center"]
	update_position()
	if owner_quad:
		owner_quad.set_surface_range(total_data["surface_range"])

	var terrain_data = total_data["terrain"]
	var water_data = total_data["water"]

	# Terrain
	var terrain_mesh = ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, terrain_data)
	self.mesh = terrain_mesh

	collision_vertices = total_data["collision_vertices"]
	collision_indices = total_data["collision_indices"]
	if collider:
		collider_outdated = true

	self.material_override = planet.terrain_material


	# Water
	if not water_data["should_render"]:
		if water_mesh_instance:
			water_mesh_instance.mesh = null
	else:
		if not water_mesh_instance:
			water_mesh_instance = MeshInstance3D.new()
			add_child(water_mesh_instance)

		var water_mesh = ArrayMesh.new()
		water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water_data["mesh_array"])
		water_mesh_instance.mesh = water_mesh

		water_mesh_instance.material_override = planet.water_material
	is_ready = true


static func generate_chunk_data(chunk_instance: Chunk, gen_id: int, detail_noise: FastNoiseLite, sampler: TerrainSampler, uv_min: Vector2, uv_max: Vector2, corners: Array, terrain_center: PackedFloat64Array, grid_size: int, radius: float, height: float, stitch_north: bool, stitch_south: bool, stitch_east: bool, stitch_west: bool, skirt_depth: float):
	var data = calculate_terrain_mesh(detail_noise, sampler, uv_min, uv_max, corners, terrain_center, grid_size, radius, height, stitch_north, stitch_south, stitch_east, stitch_west, skirt_depth)
	var total_data = {
		"gen_id": gen_id,
		"center": terrain_center,
		"terrain": data["mesh_array"],
		"collision_vertices": data["mesh_array"][Mesh.ARRAY_VERTEX],
		"collision_indices": data["mesh_array"][Mesh.ARRAY_INDEX],
		"water": data["water_data"],
		"surface_range": data["surface_range"]
	}
	chunk_instance.task_result = total_data

static func calculate_terrain_mesh(detail_noise: FastNoiseLite, sampler: TerrainSampler, uv_min: Vector2, uv_max: Vector2, corners: Array, terrain_center: PackedFloat64Array, grid_size: int, radius: float, height: float, stitch_north: bool, stitch_south: bool, stitch_east: bool, stitch_west: bool, skirt_depth: float) -> Dictionary:
	var mesh_array = []
	mesh_array.resize(Mesh.ARRAY_MAX)

	var num_vertices = grid_size + 1
	var total_vertices = num_vertices * num_vertices

	var skirt_vertex_count = num_vertices * 4
	var total_vertices_all = total_vertices + skirt_vertex_count

	var grid := ChunkGrid.for_size(grid_size) # triangles and uvs, the same for every chunk of this size
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var heights = PackedVector2Array() # terrain height for the shader in x (UV2), float, so it can be negative

	vertices.resize(total_vertices_all)
	normals.resize(total_vertices_all)
	heights.resize(total_vertices_all)

	var sphere_points_cache = PackedFloat64Array() # x, y, z per vertex, double precision, for the water
	sphere_points_cache.resize(total_vertices * 3)

	var c0: Vector3 = corners[0]
	var c1: Vector3 = corners[1]
	var c2: Vector3 = corners[2]
	var c3: Vector3 = corners[3]
	var detail_scale := radius / DETAIL_TUNED_FOR_RADIUS

	var min_chunk_height := INF
	var min_surface := INF # real height range in meters (tile + detail noise), for the quads LOD distance
	var max_surface := -INF

	# No calls to GDScript functions in the per vertex loops (only once per chunk): those block each other between
	# the worker threads, so chunks would hardly build faster on several threads. Native ones (lerpf, sqrt, noise) are fine
	# One extra ring of vertices around the chunk, only for the normals: the edge vertices need their neighbours
	# on both sides, so neighbouring chunks get the same normals there and the edges don't show
	var ext_size: int = num_vertices + 2
	var ext_count: int = ext_size * ext_size
	var macro_ratios := sampler.sample_grid(uv_min, uv_max, grid_size, 1)
	var sphere_points := PackedVector3Array() # 32 bit is fine for directions, noise and normals
	sphere_points.resize(ext_count)
	var ext_cache := PackedFloat64Array() # x, y, z of the sphere points, double precision
	ext_cache.resize(ext_count * 3)

	# Cube point and spherify on plain floats (64 bit), Vector3 (32 bit) is only ~3cm precise at 300km
	# top-left to top-right and bottom-left to bottom-right per column (computed once), then vertical.
	# The ring is just a bit outside 0..1
	var top := PackedFloat64Array() # x, y, z per column
	var bottom := PackedFloat64Array()
	top.resize(ext_size * 3)
	bottom.resize(ext_size * 3)
	for ex in range(ext_size):
		var u := float(ex - 1) / grid_size
		top[ex * 3] = lerpf(c0.x, c1.x, u)
		top[ex * 3 + 1] = lerpf(c0.y, c1.y, u)
		top[ex * 3 + 2] = lerpf(c0.z, c1.z, u)
		bottom[ex * 3] = lerpf(c3.x, c2.x, u)
		bottom[ex * 3 + 1] = lerpf(c3.y, c2.y, u)
		bottom[ex * 3 + 2] = lerpf(c3.z, c2.z, u)

	for ey in range(ext_size):
		var v := float(ey - 1) / grid_size
		for ex in range(ext_size):
			var e: int = ex + ey * ext_size
			var px := lerpf(top[ex * 3], bottom[ex * 3], v)
			var py := lerpf(top[ex * 3 + 1], bottom[ex * 3 + 1], v)
			var pz := lerpf(top[ex * 3 + 2], bottom[ex * 3 + 2], v)
			var x2 := px * px
			var y2 := py * py
			var z2 := pz * pz
			# CubeSphere.spherify_axis, inlined
			var sx := px * sqrt(1.0 - y2 / 2.0 - z2 / 2.0 + y2 * z2 / 3.0)
			var sy := py * sqrt(1.0 - z2 / 2.0 - x2 / 2.0 + z2 * x2 / 3.0)
			var sz := pz * sqrt(1.0 - x2 / 2.0 - y2 / 2.0 + x2 * y2 / 3.0)
			ext_cache[e * 3] = sx
			ext_cache[e * 3 + 1] = sy
			ext_cache[e * 3 + 2] = sz
			sphere_points[e] = Vector3(sx, sy, sz)

	var surfaces := surface_heights(detail_noise, sphere_points, macro_ratios, height, detail_scale)

	var ups := PackedVector3Array() # away from the planet at each vertex, the skirts hang straight down from the edges
	ups.resize(total_vertices)
	var positions := PackedVector3Array() # relative to the chunk center, ring included
	positions.resize(ext_count)
	for e in range(ext_count):
		var r: float = radius + surfaces[e]
		positions[e] = Vector3(ext_cache[e * 3] * r - terrain_center[0], ext_cache[e * 3 + 1] * r - terrain_center[1], ext_cache[e * 3 + 2] * r - terrain_center[2])

	for y in range(num_vertices):
		for x in range(num_vertices):
			var idx: int = x + y * num_vertices
			var e: int = (x + 1) + (y + 1) * ext_size
			sphere_points_cache[idx * 3] = ext_cache[e * 3]
			sphere_points_cache[idx * 3 + 1] = ext_cache[e * 3 + 1]
			sphere_points_cache[idx * 3 + 2] = ext_cache[e * 3 + 2]

			var macro_height_ratio := macro_ratios[e]
			if macro_height_ratio < min_chunk_height:
				min_chunk_height = macro_height_ratio
			var surface := surfaces[e]
			min_surface = minf(min_surface, surface)
			max_surface = maxf(max_surface, surface)
			vertices[idx] = positions[e]
			ups[idx] = sphere_points[e].normalized()
			heights[idx] = Vector2(macro_height_ratio, 0.0)

			# Smooth normal of the terrain: from the neighbours left/right and above/below, pointing away from the planet
			var normal := (positions[e + 1] - positions[e - 1]).cross(positions[e + ext_size] - positions[e - ext_size])
			if normal.dot(sphere_points[e]) < 0.0:
				normal = -normal
			normals[idx] = normal.normalized()

	var edges_to_stitch: Array[PackedInt32Array] = []

	if stitch_north:
		var edge := PackedInt32Array()
		for x in range(num_vertices):
			edge.push_back(x)
		edges_to_stitch.append(edge)

	if stitch_south:
		var edge := PackedInt32Array()
		for x in range(num_vertices):
			edge.push_back(x + grid_size * num_vertices)
		edges_to_stitch.append(edge)

	if stitch_west:
		var edge := PackedInt32Array()
		for y in range(num_vertices):
			edge.push_back(y * num_vertices)
		edges_to_stitch.append(edge)

	if stitch_east:
		var edge := PackedInt32Array()
		for y in range(num_vertices):
			edge.push_back(grid_size + y * num_vertices)
		edges_to_stitch.append(edge)

	for edge_indices in edges_to_stitch:
		for i in range(1, edge_indices.size() - 1, 2):
			var prev_idx = edge_indices[i - 1]
			var curr_idx = edge_indices[i]
			var next_idx = edge_indices[i + 1]

			vertices[curr_idx] = vertices[prev_idx].lerp(vertices[next_idx], 0.5)
			normals[curr_idx] = (normals[prev_idx] + normals[next_idx]).normalized()
			heights[curr_idx] = heights[prev_idx].lerp(heights[next_idx], 0.5)

	# Skirt, so that the occasional still existing hole (nbo idea why though), dissapears
	var north_offset = total_vertices
	var south_offset = north_offset + num_vertices
	var west_offset = south_offset + num_vertices
	var east_offset = west_offset + num_vertices

	for x in range(num_vertices):
		var src_idx = x # north edge, y = 0
		var s_idx = north_offset + x
		vertices[s_idx] = vertices[src_idx] - ups[src_idx] * skirt_depth
		normals[s_idx] = normals[src_idx]
		heights[s_idx] = heights[src_idx]

	for x in range(num_vertices):
		var src_idx = x + grid_size * num_vertices # south edge
		var s_idx = south_offset + x
		vertices[s_idx] = vertices[src_idx] - ups[src_idx] * skirt_depth
		normals[s_idx] = normals[src_idx]
		heights[s_idx] = heights[src_idx]

	for y in range(num_vertices):
		var src_idx = y * num_vertices # west edge
		var s_idx = west_offset + y
		vertices[s_idx] = vertices[src_idx] - ups[src_idx] * skirt_depth
		normals[s_idx] = normals[src_idx]
		heights[s_idx] = heights[src_idx]

	for y in range(num_vertices):
		var src_idx = grid_size + y * num_vertices # east edge
		var s_idx = east_offset + y
		vertices[s_idx] = vertices[src_idx] - ups[src_idx] * skirt_depth
		normals[s_idx] = normals[src_idx]
		heights[s_idx] = heights[src_idx]

	mesh_array[Mesh.ARRAY_VERTEX] = vertices
	mesh_array[Mesh.ARRAY_INDEX] = grid.terrain_indices
	mesh_array[Mesh.ARRAY_NORMAL] = normals
	mesh_array[Mesh.ARRAY_TEX_UV2] = heights
	mesh_array[Mesh.ARRAY_TEX_UV] = grid.terrain_uvs

	var water_data = calculate_water_mesh(grid, grid_size, radius, terrain_center, min_chunk_height, sphere_points_cache)

	return {
		"mesh_array": mesh_array,
		"water_data": water_data,
		"surface_range": Vector2(min_surface, max_surface)
	}

# Sea level is height 0, so the water is just a sphere at the planet radius
# Meters above the planet radius at each point, from the tile height plus detail noise.
# Also used by Planet.ground_height_at, so the ground check matches the mesh
# For many points at once, the loop has no GDScript function calls (see calculate_terrain_mesh)
static func surface_heights(detail_noise: FastNoiseLite, sphere_points: PackedVector3Array, macro_height_ratios: PackedFloat32Array, height: float, detail_scale: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(sphere_points.size())
	var detail_height_scale := height / DETAIL_TUNED_FOR_HEIGHT
	for i in range(sphere_points.size()):
		var sphere_point := sphere_points[i]
		var macro_height_ratio := macro_height_ratios[i]
		var macro_height := macro_height_ratio * height
		if macro_height_ratio <= 0.0: # no detail below sea level (land is 0 there), so the noise isn't needed
			result[i] = macro_height
			continue

		# A bit more detail, needs twaking, but first step
		var large_detail := detail_noise.get_noise_3dv(sphere_point * (80.0 * detail_scale))
		var medium_detail := detail_noise.get_noise_3dv(sphere_point * (250.0 * detail_scale))
		var small_detail := detail_noise.get_noise_3dv(sphere_point * (700.0 * detail_scale))

		var detail := large_detail * 4.0 + medium_detail * 1.5 + small_detail * 0.4
		var land := smoothstep(0.0, 0.05, macro_height_ratio) # no detail below sea level
		var mountain_factor := smoothstep(0.25, 0.67, macro_height_ratio)
		var detail_strength := lerpf(1.0, 6.0, mountain_factor)

		result[i] = macro_height + detail * detail_strength * land * detail_height_scale
	return result

static func calculate_water_mesh(grid: ChunkGrid, grid_size: int, radius: float, terrain_center: PackedFloat64Array, min_terrain_height: float, sphere_points_cache: PackedFloat64Array) -> Dictionary:
	if min_terrain_height > 0.1:
		return { "should_render": false }

	var mesh_array = []
	mesh_array.resize(Mesh.ARRAY_MAX)

	var num_vertices = grid_size + 1
	var total_vertices = num_vertices * num_vertices

	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()

	vertices.resize(total_vertices)
	normals.resize(total_vertices)

	for y in range(num_vertices):
		for x in range(num_vertices):
			var idx = x + (y * num_vertices)

			var sx := sphere_points_cache[idx * 3]
			var sy := sphere_points_cache[idx * 3 + 1]
			var sz := sphere_points_cache[idx * 3 + 2]

			vertices[idx] = Vector3(sx * radius - terrain_center[0], sy * radius - terrain_center[1], sz * radius - terrain_center[2])
			normals[idx] = Vector3(sx, sy, sz)

	mesh_array[Mesh.ARRAY_VERTEX] = vertices
	mesh_array[Mesh.ARRAY_INDEX] = grid.water_indices
	mesh_array[Mesh.ARRAY_NORMAL] = normals
	mesh_array[Mesh.ARRAY_TEX_UV] = grid.water_uvs

	return {
		"should_render": true,
		"mesh_array": mesh_array
	}
