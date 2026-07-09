class_name Chunk
extends MeshInstance3D

func build_mesh(planet: Node3D, corners: Array, grid_size: int, radius: float, height: float):
	var mesh_array = []
	mesh_array.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	
	var num_vertices = grid_size + 1
	
	for y in range(num_vertices):
		for x in range(num_vertices):
			var u = float(x) / grid_size
			var v = float(y) / grid_size
			
			var top_lerp = corners[0].lerp(corners[1], u) # top-left to top-right
			var bottom_lerp = corners[3].lerp(corners[2], u) # bottom-left to bottom-right
			var cube_point = top_lerp.lerp(bottom_lerp, v) # vertical
			
			var sphere_point = spherify(cube_point)
			
			var world_uv = planet.get_uv_from_vector(sphere_point)
			
			var img_w = planet.world_image.get_width()
			var img_h = planet.world_image.get_height()
			var px = clampi(int(world_uv.x * img_w), 0, img_w - 1)
			var py = clampi(int(world_uv.y * img_h), 0, img_h - 1)
			
			var texture_data = planet.world_image.get_pixel(px, py)
			var macro_height_ratio = texture_data.r
			var macro_noise_value = macro_height_ratio * height
			
			var vertex_pos = sphere_point * (radius + macro_noise_value)
			
			vertices.push_back(vertex_pos)
			normals.push_back(sphere_point.normalized())
			
			colors.push_back(Color(macro_height_ratio, 0.0, 0.0))
	
	for y in range(grid_size):
		for x in range(grid_size):
			var top_left = x + y * num_vertices
			var top_right = (x+1) + y * num_vertices
			var bottom_left = x + (y+1) * num_vertices
			var bottom_right = (x+1) + (y+1) * num_vertices
			
			indices.push_back(top_left)
			indices.push_back(top_right)
			indices.push_back(bottom_left)
			
			indices.push_back(top_right)
			indices.push_back(bottom_right)
			indices.push_back(bottom_left)
	
	mesh_array[Mesh.ARRAY_VERTEX] = vertices
	mesh_array[Mesh.ARRAY_INDEX] = indices
	mesh_array[Mesh.ARRAY_NORMAL] = normals
	mesh_array[Mesh.ARRAY_COLOR] = colors
	
	var new_mesh = ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_array)
	self.mesh = new_mesh
	
	var material := ShaderMaterial.new()
	material.shader = preload("res://Planet/planet.gdshader")
	material.set_shader_parameter("world_map", planet.world_texture)
	self.material_override = material


static func spherify(p: Vector3) -> Vector3:
	var x2 := p.x * p.x
	var y2 := p.y * p.y
	var z2 := p.z * p.z
	
	var res := Vector3.ZERO
	res.x = p.x * sqrt(1.0 - y2 / 2.0 - z2 / 2.0 + y2 * z2 / 3.0)
	res.y = p.y * sqrt(1.0 - z2 / 2.0 - x2 / 2.0 + z2 * x2 / 3.0)
	res.z = p.z * sqrt(1.0 - x2 / 2.0 - y2 / 2.0 + x2 * y2 / 3.0)
	return res
