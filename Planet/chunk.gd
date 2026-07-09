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
			
			var texture_data = sample_image_bilinear(planet.world_image, world_uv)
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
