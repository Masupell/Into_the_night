class_name Chunk
extends MeshInstance3D

var water_mesh_instance: MeshInstance3D

var active_task_id: int = -1
var generation_id: int = 1

var is_pending_recycle: bool = false
var is_ready: bool = false

var redraw_requested: bool = false
var owner_quad: Quad = null

var planet: Planet # Easier with reference right now

func _process(_delta: float) -> void:
	if active_task_id != -1:
		if WorkerThreadPool.is_task_completed(active_task_id):
			WorkerThreadPool.wait_for_task_completion(active_task_id)
			active_task_id = -1
			
			if is_pending_recycle:
				is_pending_recycle = false
				completely_reset_and_return()
			elif redraw_requested:
				redraw_requested = false
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
	owner_quad = null
	if water_mesh_instance:
		water_mesh_instance.mesh = null
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	planet.return_chunk(self)


# On Main Thread
func apply_generation_results(total_data: Dictionary):
	if total_data["gen_id"] != generation_id:
		return
	
	var terrain_data = total_data["terrain"]
	var water_data = total_data["water"]
	
	# Terrain
	var terrain_mesh = ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, terrain_data)
	self.mesh = terrain_mesh
	
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	
	if total_data["needs_collision"]:
		var static_body := StaticBody3D.new()
		add_child(static_body)
		
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = terrain_mesh.create_trimesh_shape()
		static_body.add_child(collision_shape)
	
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


static func generate_chunk_data(chunk_instance: Chunk, gen_id: int, detail_noise: FastNoiseLite, world_texture: Image, corners: Array, grid_size: int, radius: float, height: float, stitch_north: bool, stitch_south: bool, stitch_east: bool, stitch_west: bool, needs_collision: bool, skirt_depth: float):
	var data = calculate_terrain_mesh(detail_noise, world_texture, corners, grid_size, radius, height, stitch_north, stitch_south, stitch_east, stitch_west, skirt_depth)
	var total_data = {
		"gen_id": gen_id,
		"needs_collision": needs_collision,
		"terrain": data["mesh_array"],
		"water": data["water_data"]
	}
	chunk_instance.apply_generation_results.call_deferred(total_data)

static func calculate_terrain_mesh(detail_noise: FastNoiseLite, world_texture: Image, corners: Array, grid_size: int, radius: float, height: float, stitch_north: bool, stitch_south: bool, stitch_east: bool, stitch_west: bool, skirt_depth: float) -> Dictionary:
	var mesh_array = []
	mesh_array.resize(Mesh.ARRAY_MAX)
	
	var num_vertices = grid_size + 1
	var total_vertices = num_vertices * num_vertices
	
	var skirt_vertex_count = num_vertices * 4
	var total_vertices_all = total_vertices + skirt_vertex_count
	var main_index_count = grid_size * grid_size * 6
	var skirt_index_count = grid_size * 4 * 6
	var total_index_count = main_index_count + skirt_index_count
	
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	
	vertices.resize(total_vertices_all)
	indices.resize(total_index_count)
	normals.resize(total_vertices_all)
	colors.resize(total_vertices_all)
	
	var sphere_points_cache = PackedVector3Array()
	sphere_points_cache.resize(total_vertices)
	
	var min_chunk_height := 1.0
	
	for y in range(num_vertices):
		for x in range(num_vertices):
			var idx = x + (y * num_vertices)
			var u = float(x) / grid_size
			var v = float(y) / grid_size
			
			var top_lerp = corners[0].lerp(corners[1], u) # top-left to top-right
			var bottom_lerp = corners[3].lerp(corners[2], u) # bottom-left to bottom-right
			var cube_point = top_lerp.lerp(bottom_lerp, v) # vertical
			
			var sphere_point = spherify(cube_point)
			sphere_points_cache[idx] = sphere_point
			
			var world_uv = get_uv_from_vector(sphere_point)
			
			var texture_data = sample_image_bilinear(world_texture, world_uv)
			var macro_height_ratio = texture_data.r
			if macro_height_ratio < min_chunk_height:
				min_chunk_height = macro_height_ratio
			var macro_height = macro_height_ratio * height
			
			# A bit more detail, needs twaking, but first step
			var large_detail = detail_noise.get_noise_3dv(sphere_point * 80.0)
			var medium_detail = detail_noise.get_noise_3dv(sphere_point * 250.0)
			var small_detail = detail_noise.get_noise_3dv(sphere_point * 700.0)
			
			var detail = large_detail * 4.0 + medium_detail * 1.5 + small_detail * 0.4
			var land = smoothstep(0.45, 0.5, macro_height_ratio)
			var mountain_factor = smoothstep(0.55, 0.8, macro_height_ratio)
			var detail_strength = lerp(1.0, 6.0, mountain_factor)
			
			macro_height += detail * detail_strength * land
			
			
			var vertex_pos = sphere_point * (radius + macro_height)
			
			vertices[idx] = vertex_pos
			normals[idx] = sphere_point.normalized()
			colors[idx] = Color(macro_height_ratio, 0.0, 0.0)
	
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
			colors[curr_idx] = colors[prev_idx].lerp(colors[next_idx], 0.5)
	
	for y in range(grid_size):
		for x in range(grid_size):
			var idx = (x + (y * grid_size)) * 6
			var top_left = x + y * num_vertices
			var top_right = (x+1) + y * num_vertices
			var bottom_left = x + (y+1) * num_vertices
			var bottom_right = (x+1) + (y+1) * num_vertices
			
			indices[idx] = top_left
			indices[idx+1] = top_right
			indices[idx+2] = bottom_left
			
			indices[idx+3] = top_right
			indices[idx+4] = bottom_right
			indices[idx+5] = bottom_left
	
	
	
	# Skirt, so that the occasional still existing hole (nbo idea why though), dissapears
	var north_offset = total_vertices
	var south_offset = north_offset + num_vertices
	var west_offset = south_offset + num_vertices
	var east_offset = west_offset + num_vertices
	
	for x in range(num_vertices):
		var src_idx = x # north edge, y = 0
		var s_idx = north_offset + x
		vertices[s_idx] = vertices[src_idx] - normals[src_idx] * skirt_depth
		normals[s_idx] = normals[src_idx]
		colors[s_idx] = colors[src_idx]
	
	for x in range(num_vertices):
		var src_idx = x + grid_size * num_vertices # south edge
		var s_idx = south_offset + x
		vertices[s_idx] = vertices[src_idx] - normals[src_idx] * skirt_depth
		normals[s_idx] = normals[src_idx]
		colors[s_idx] = colors[src_idx]
	
	for y in range(num_vertices):
		var src_idx = y * num_vertices # west edge
		var s_idx = west_offset + y
		vertices[s_idx] = vertices[src_idx] - normals[src_idx] * skirt_depth
		normals[s_idx] = normals[src_idx]
		colors[s_idx] = colors[src_idx]
	
	for y in range(num_vertices):
		var src_idx = grid_size + y * num_vertices # east edge
		var s_idx = east_offset + y
		vertices[s_idx] = vertices[src_idx] - normals[src_idx] * skirt_depth
		normals[s_idx] = normals[src_idx]
		colors[s_idx] = colors[src_idx]
	
	var idx_ptr = main_index_count
	
	for x in range(grid_size):
		var top_left = north_offset + x
		var top_right = north_offset + x + 1
		var bottom_left = x
		var bottom_right = x + 1
		indices[idx_ptr] = top_left
		indices[idx_ptr+1] = top_right
		indices[idx_ptr+2] = bottom_left
		indices[idx_ptr+3] = top_right
		indices[idx_ptr+4] = bottom_right
		indices[idx_ptr+5] = bottom_left
		idx_ptr += 6
	
	for x in range(grid_size):
		var top_left = x + grid_size * num_vertices
		var top_right = x + 1 + grid_size * num_vertices
		var bottom_left = south_offset + x
		var bottom_right = south_offset + x + 1
		indices[idx_ptr] = top_left
		indices[idx_ptr+1] = top_right
		indices[idx_ptr+2] = bottom_left
		indices[idx_ptr+3] = top_right
		indices[idx_ptr+4] = bottom_right
		indices[idx_ptr+5] = bottom_left
		idx_ptr += 6
	
	for y in range(grid_size):
		var top_left = west_offset + y
		var top_right = y * num_vertices
		var bottom_left = west_offset + y + 1
		var bottom_right = (y+1) * num_vertices
		indices[idx_ptr] = top_left
		indices[idx_ptr+1] = top_right
		indices[idx_ptr+2] = bottom_left
		indices[idx_ptr+3] = top_right
		indices[idx_ptr+4] = bottom_right
		indices[idx_ptr+5] = bottom_left
		idx_ptr += 6
	
	for y in range(grid_size):
		var top_left = grid_size + y * num_vertices
		var top_right = east_offset + y
		var bottom_left = grid_size + (y+1) * num_vertices
		var bottom_right = east_offset + y + 1
		indices[idx_ptr] = top_left
		indices[idx_ptr+1] = top_right
		indices[idx_ptr+2] = bottom_left
		indices[idx_ptr+3] = top_right
		indices[idx_ptr+4] = bottom_right
		indices[idx_ptr+5] = bottom_left
		idx_ptr += 6
	
	
	
	
	mesh_array[Mesh.ARRAY_VERTEX] = vertices
	mesh_array[Mesh.ARRAY_INDEX] = indices
	mesh_array[Mesh.ARRAY_NORMAL] = normals
	mesh_array[Mesh.ARRAY_COLOR] = colors
	
	var water_data = calculate_water_mesh(grid_size, radius, height, min_chunk_height, 0.08, sphere_points_cache)
	
	return {
		"mesh_array": mesh_array,
		"water_data": water_data
	}

static func calculate_water_mesh(grid_size: int, radius: float, height: float, min_terrain_height: float, sea_level_ratio: float, sphere_points_cache: PackedVector3Array) -> Dictionary:
	if min_terrain_height > (sea_level_ratio + 0.1):
		return { "should_render": false }

	var mesh_array = []
	mesh_array.resize(Mesh.ARRAY_MAX)
	
	var num_vertices = grid_size + 1
	var total_vertices = num_vertices * num_vertices
	
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	
	vertices.resize(total_vertices)
	normals.resize(total_vertices)
	uvs.resize(total_vertices)
	indices.resize(grid_size * grid_size * 6)
	
	var water_radisu = radius + (sea_level_ratio * height)
	
	for y in range(num_vertices):
		for x in range(num_vertices):
			var idx = x + (y * num_vertices)
			var u = float(x) / grid_size
			var v = float(y) / grid_size
			
			var sphere_point = sphere_points_cache[idx]
			
			var vertex_pos = sphere_point * water_radisu
			
			vertices[idx] = vertex_pos
			normals[idx] = sphere_point
			uvs[idx] = Vector2(u, v)
			
	for y in range(grid_size):
		for x in range(grid_size):
			var idx = (x + (y * grid_size)) * 6
			var top_left = x + y * num_vertices
			var top_right = (x+1) + y * num_vertices
			var bottom_left = x + (y+1) * num_vertices
			var bottom_right = (x+1) + (y+1) * num_vertices
			
			indices[idx] = top_left
			indices[idx+1] = top_right
			indices[idx+2] = bottom_left
			
			indices[idx+3] = top_right
			indices[idx+4] = bottom_right
			indices[idx+5] = bottom_left
	
	mesh_array[Mesh.ARRAY_VERTEX] = vertices
	mesh_array[Mesh.ARRAY_INDEX] = indices
	mesh_array[Mesh.ARRAY_NORMAL] = normals
	mesh_array[Mesh.ARRAY_TEX_UV] = uvs
	
	return {
		"should_render": true,
		"mesh_array": mesh_array
	}


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

static func sample_image_bilinear(img: Image, uv: Vector2) -> Color:
	var width = img.get_width()
	var height = img.get_height()
	
	var x = uv.x * (width - 1)
	var y = uv.y * (height - 1)
	
	var x0 = clampi(int(floor(x)), 0, width - 1)
	var y0 = clampi(int(floor(y)), 0, height - 1)
	
	var x1 = clampi(x0 + 1, 0, width - 1)
	var y1 = clampi(y0 + 1, 0, height - 1)
	
	var tx = x - x0
	var ty = y - y0
	
	var c00 = img.get_pixel(x0, y0)
	var c10 = img.get_pixel(x1, y0)
	var c01 = img.get_pixel(x0, y1)
	var c11 = img.get_pixel(x1, y1)
	
	var top_row = c00.lerp(c10, tx)
	var bottom_row = c01.lerp(c11, tx)
	
	return top_row.lerp(bottom_row, ty)
