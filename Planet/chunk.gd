class_name Chunk
extends MeshInstance3D

var water_mesh_instance: MeshInstance3D

func build_mesh(planet: Node3D, corners: Array, grid_size: int, radius: float, height: float, stitch_north: bool, stitch_south: bool, stitch_east: bool, stitch_west: bool, needs_collision: bool):
	var mesh_array = []
	mesh_array.resize(Mesh.ARRAY_MAX)
	
	var num_vertices = grid_size + 1
	var total_vertices = num_vertices * num_vertices
	
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	
	vertices.resize(total_vertices)
	indices.resize(grid_size*grid_size*6)
	normals.resize(total_vertices)
	colors.resize(total_vertices)
	
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
			
			var world_uv = planet.get_uv_from_vector(sphere_point)
			
			var texture_data = sample_image_bilinear(planet.world_image, world_uv)
			var macro_height_ratio = texture_data.r
			if macro_height_ratio < min_chunk_height:
				min_chunk_height = macro_height_ratio
			var macro_height = macro_height_ratio * height
			
			# A bit more detail, needs twaking, but first step
			var large_detail = planet.detail_noise.get_noise_3dv(sphere_point * 80.0)
			var medium_detail = planet.detail_noise.get_noise_3dv(sphere_point * 250.0)
			var small_detail = planet.detail_noise.get_noise_3dv(sphere_point * 700.0)
			
			var detail = large_detail * 4.0 + medium_detail * 1.5 + small_detail * 0.4
			var land = smoothstep(0.45, 0.5, macro_height_ratio)
			var mountain_factor = smoothstep(0.55, 0.8, macro_height_ratio)
			var detail_strength = lerp(1.0, 6.0, mountain_factor)
			
			macro_height += detail * detail_strength * land
			
			
			var vertex_pos = sphere_point * (radius + macro_height)
			
			vertices[idx] = vertex_pos
			normals[idx] = sphere_point.normalized()
			colors[idx] = Color(macro_height_ratio, 0.0, 0.0)
	
	
	# This array will hold arrays of vertex indices that need stitching
	var edges_to_stitch: Array[PackedInt32Array] = []

	# Collect North Edge indices (y = 0)
	if stitch_north:
		var edge := PackedInt32Array()
		for x in range(num_vertices):
			edge.push_back(x)
		edges_to_stitch.append(edge)

	# Collect South Edge indices (y = grid_size)
	if stitch_south:
		var edge := PackedInt32Array()
		for x in range(num_vertices):
			edge.push_back(x + grid_size * num_vertices)
		edges_to_stitch.append(edge)

	# Collect West Edge indices (x = 0)
	if stitch_west:
		var edge := PackedInt32Array()
		for y in range(num_vertices):
			edge.push_back(y * num_vertices)
		edges_to_stitch.append(edge)

	# Collect East Edge indices (x = grid_size)
	if stitch_east:
		var edge := PackedInt32Array()
		for y in range(num_vertices):
			edge.push_back(grid_size + y * num_vertices)
		edges_to_stitch.append(edge)

	# Execute the single, unified flattening loop across all flagged edges
	for edge_indices in edges_to_stitch:
		# Step by 2 to target only the odd vertices (1, 3, 5...) 
		# This leaves the corner anchors (0 and grid_size) untouched!
		for i in range(1, edge_indices.size() - 1, 2):
			var prev_idx = edge_indices[i - 1]
			var curr_idx = edge_indices[i]
			var next_idx = edge_indices[i + 1]
			
			# Flatten the odd vertex exactly halfway between its neighbor even vertices
			vertices[curr_idx] = vertices[prev_idx].lerp(vertices[next_idx], 0.5)
			
			# Average the normals and colors to keep the lighting and textures seamless
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
	
	mesh_array[Mesh.ARRAY_VERTEX] = vertices
	mesh_array[Mesh.ARRAY_INDEX] = indices
	mesh_array[Mesh.ARRAY_NORMAL] = normals
	mesh_array[Mesh.ARRAY_COLOR] = colors
	
	var new_mesh = ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_array)
	self.mesh = new_mesh
	
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	
	if needs_collision:
		var static_body := StaticBody3D.new()
		add_child(static_body)
		
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = new_mesh.create_trimesh_shape()
		static_body.add_child(collision_shape)
	
	self.material_override = planet.terrain_material
	
	build_water_mesh(corners, grid_size, radius, height, min_chunk_height, 0.08, planet.water_material, sphere_points_cache)


func build_water_mesh(corners: Array, grid_size: int, radius: float, height: float, min_terrain_height: float, sea_level_ratio: float, water_material: ShaderMaterial, sphere_points_cache: PackedVector3Array):
	if min_terrain_height > (sea_level_ratio + 0.1):
		if water_mesh_instance:
			water_mesh_instance.mesh = null
		return
	
	if not water_mesh_instance:
		water_mesh_instance = MeshInstance3D.new()
		add_child(water_mesh_instance)
	else:
		water_mesh_instance.mesh = null

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
	
	var new_mesh = ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_array)
	water_mesh_instance.mesh = new_mesh
	
	water_mesh_instance.material_override = water_material


static func spherify(p: Vector3) -> Vector3:
	var x2 := p.x * p.x
	var y2 := p.y * p.y
	var z2 := p.z * p.z
	
	var res := Vector3.ZERO
	res.x = p.x * sqrt(1.0 - y2 / 2.0 - z2 / 2.0 + y2 * z2 / 3.0)
	res.y = p.y * sqrt(1.0 - z2 / 2.0 - x2 / 2.0 + z2 * x2 / 3.0)
	res.z = p.z * sqrt(1.0 - x2 / 2.0 - y2 / 2.0 + x2 * y2 / 3.0)
	return res


func sample_image_bilinear(img: Image, uv: Vector2) -> Color:
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
