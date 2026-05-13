class_name Quad
extends RefCounted

var planet: Planet
var level: int = 0 # Depth of quadtree
var corners: Array
var children: Array[Quad] = []
var chunk: Chunk = null

const FRUSTUM_OUTSIDE = 0
const FRUSTUM_INTERSECT = 1
const FRUSTUM_INSIDE = 2

var frustum_state = FRUSTUM_INTERSECT
var bounding_aabb: AABB
var parent_quad: Quad

func _init(_planet: Planet, _level: int, _corners: Array, _parent: Quad = null) -> void:
	self.planet = _planet
	self.level = _level
	self.corners = _corners
	self.parent_quad = _parent
	calculate_aabb()

func update_lod(camera_pos: Vector3, frustum_planes: Array):
	if parent_quad and parent_quad.frustum_state == FRUSTUM_INSIDE:
		frustum_state = FRUSTUM_INSIDE
	elif not frustum_planes.is_empty():
		frustum_state = test_frustum(frustum_planes)
	else:
		frustum_state = FRUSTUM_INTERSECT
	
	var is_visible = is_above_horizon(camera_pos) and frustum_state != FRUSTUM_OUTSIDE
	if not is_visible:
		remove_chunk()
		for child in children:
			child.update_lod(camera_pos, frustum_planes)
		return
	
	var center = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
	var surface_center = Planet.spherify(center) * planet.radius
	var dist_to_cam = camera_pos.distance_to(surface_center)
	
	if level < planet.max_lod_level and dist_to_cam < planet.split_distances[level]:
		if children.is_empty():
			split()
		for child in children:
			child.update_lod(camera_pos, frustum_planes)
		remove_chunk()
	else:
		if not children.is_empty():
			merge()
		draw_chunk()

func test_frustum(frustum_planes: Array) -> int:
	var fully_inside_count := 0
	var aabb_min = bounding_aabb.position
	var aabb_max = bounding_aabb.end
	
	for plane in frustum_planes:
		var n_vertex = Vector3(
			aabb_min.x if plane.normal.x >= 0.0 else aabb_max.x,
			aabb_min.y if plane.normal.y >= 0.0 else aabb_max.y,
			aabb_min.z if plane.normal.z >= 0.0 else aabb_max.z
		)
		if plane.distance_to(n_vertex) > 0.0:
			return FRUSTUM_OUTSIDE
		
		var p_vertex = Vector3(
			aabb_max.x if plane.normal.x >= 0.0 else aabb_min.x,
			aabb_max.y if plane.normal.y >= 0.0 else aabb_min.y,
			aabb_max.z if plane.normal.z >= 0.0 else aabb_min.z
		)
		if plane.distance_to(p_vertex) <= 0.0:
			fully_inside_count += 1
	
	if fully_inside_count == frustum_planes.size():
		return FRUSTUM_INSIDE
	return FRUSTUM_INTERSECT

func is_above_horizon(cam_local_pos: Vector3) -> bool:
	var center = bounding_aabb.get_center()
	var normal = center.normalized()
	var dir_to_cam = (cam_local_pos - center).normalized()
	return normal.dot(dir_to_cam) > -0.2

func split():
	var m01 = corners[0].lerp(corners[1], 0.5) # Top
	var m12 = corners[1].lerp(corners[2], 0.5) # Right
	var m23 = corners[2].lerp(corners[3], 0.5) # Bottom
	var m30 = corners[3].lerp(corners[0], 0.5) # Left
	var m_mid = corners[0].lerp(corners[2], 0.5) # Center
	
	children.append(Quad.new(planet, level + 1, [corners[0], m01, m_mid, m30], self)) # TopLeft
	children.append(Quad.new(planet, level + 1, [m01, corners[1], m12, m_mid], self)) # TopRight
	children.append(Quad.new(planet, level + 1, [m_mid, m12, corners[2], m23], self)) # BottomRight
	children.append(Quad.new(planet, level + 1, [m30, m_mid, m23, corners[3]], self)) # BottomLeft

func merge():
	for child in children:
		child.remove_chunk()
	children.clear()

func remove_chunk():
	if chunk:
		#chunk.queue_free()
		planet.return_chunk(chunk)
		chunk = null

func draw_chunk():
	#if chunk == null:
		#chunk = Chunk.new()
		#planet.add_child(chunk)
		#chunk.build_mesh(corners, planet.grid_size, planet.radius)
	if chunk == null:
		chunk = planet.request_chunk()
		chunk.build_mesh(corners, planet.grid_size, planet.radius)

func calculate_aabb():
	var min_v = Vector3(INF, INF, INF)
	var max_v = Vector3(-INF, -INF, -INF)
	
	var points_to_check = corners.duplicate()
	var center_point = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
	points_to_check.append(center_point)
	
	for c in points_to_check:
		var surface = Planet.spherify(c) * planet.radius
		var mountains = Planet.spherify(c) * (planet.radius + planet.max_height)
		
		min_v = min_v.min(surface).min(mountains)
		max_v = max_v.max(surface).max(mountains)
	bounding_aabb = AABB(min_v, max_v - min_v)
