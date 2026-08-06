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
var bounding_center: Vector3
var horizon_cos_alpha: float
var horizon_sin_alpha: float
var parent_quad: Quad
var currently_visible: bool = true

enum Type {TOP_LEFT = 0, TOP_RIGHT = 1, BOTTOM_RIGHT = 2, BOTTOM_LEFT = 3, ROOT = -1}
var quad_type: Type = Type.ROOT

#var highest_lod: int = 0

func _init(_planet: Planet, _level: int, _corners: Array, _parent: Quad = null, _type: Type = Type.ROOT) -> void:
	self.planet = _planet
	self.level = _level
	self.corners = _corners
	self.parent_quad = _parent
	self.quad_type = _type
	calculate_bounds()

func update_lod(camera_pos: Vector3, frustum_planes: Array):
	if parent_quad and parent_quad.frustum_state == FRUSTUM_INSIDE:
		frustum_state = FRUSTUM_INSIDE
	elif not frustum_planes.is_empty():
		frustum_state = test_frustum(frustum_planes)
	else:
		frustum_state = FRUSTUM_INTERSECT
	
	currently_visible = is_above_horizon(camera_pos) and frustum_state != FRUSTUM_OUTSIDE
	if not currently_visible:
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
		if are_children_ready():
			reveal_leaves()
			remove_chunk()
	else:
		if chunk == null:
			draw_chunk()
		if chunk != null and chunk.is_ready:
			if not children.is_empty():
				chunk.visible = true
				merge()
			elif not chunk.visible and not has_active_ancestor_chunk():
				chunk.visible = true

func are_children_ready() -> bool:
	if children.is_empty():
		return false
	for child in children:
		if not child.currently_visible:
			continue
		if not child.children.is_empty():
			if not child.are_children_ready():
				return false
		elif child.chunk == null or not child.chunk.is_ready:
			return false
	return true

func test_frustum(frustum_planes: Array) -> int:
	var fully_inside_count := 0
	var aabb_min = bounding_aabb.position
	var aabb_max = bounding_aabb.end
	var margin: float = bounding_aabb.size.length() * 0.15
	
	for plane in frustum_planes:
		var n_vertex = Vector3(
			aabb_min.x if plane.normal.x >= 0.0 else aabb_max.x,
			aabb_min.y if plane.normal.y >= 0.0 else aabb_max.y,
			aabb_min.z if plane.normal.z >= 0.0 else aabb_max.z
		)
		if plane.distance_to(n_vertex) > margin:
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

func is_above_horizon(camera_pos: Vector3) -> bool:
	var camera_distance: float = camera_pos.length()
	if camera_distance <= planet.radius:
		return true
		
	var camera_dir: Vector3 = camera_pos / camera_distance
	var chunk_dir: Vector3 = bounding_center.normalized()
	var cos_angle_to_chunk: float = camera_dir.dot(chunk_dir)
	
	if cos_angle_to_chunk >= horizon_cos_alpha:
		return true
		
	var cos_camera_horizon: float = planet.radius / camera_distance
	var sin_camera_horizon: float = sqrt(maxf(0.0, 1.0 - cos_camera_horizon * cos_camera_horizon))
	var cos_terrain_extend: float = planet.radius / (planet.radius + planet.max_height)
	var sin_terrain_extend: float = sqrt(maxf(0.0, 1.0 - cos_terrain_extend * cos_terrain_extend))
	
	var cos_total_horizon: float = cos_camera_horizon * cos_terrain_extend - sin_camera_horizon * sin_terrain_extend
	
	var sin_angle_to_chunk: float = sqrt(maxf(0.0, 1.0 - cos_angle_to_chunk * cos_angle_to_chunk))
	var cos_nearest_edge: float = cos_angle_to_chunk * horizon_cos_alpha + sin_angle_to_chunk * horizon_sin_alpha
	
	var margin: float = 0.02 / float(level + 1)
	
	return cos_nearest_edge > cos_total_horizon - margin


func get_neighbor_north() -> Quad:
	if parent_quad == null: return null
	if quad_type == Type.BOTTOM_LEFT: return parent_quad.children[Type.TOP_LEFT]
	if quad_type == Type.BOTTOM_RIGHT: return parent_quad.children[Type.TOP_RIGHT]
	
	var p_neighbor = parent_quad.get_neighbor_north()
	if p_neighbor == null or p_neighbor.children.is_empty(): return p_neighbor
	return p_neighbor.children[Type.BOTTOM_LEFT] if quad_type == Type.TOP_LEFT else p_neighbor.children[Type.BOTTOM_RIGHT]

func get_neighbor_south() -> Quad:
	if parent_quad == null: return null
	if quad_type == Type.TOP_LEFT: return parent_quad.children[Type.BOTTOM_LEFT]
	if quad_type == Type.TOP_RIGHT: return parent_quad.children[Type.BOTTOM_RIGHT]
	
	var p_neighbor = parent_quad.get_neighbor_south()
	if p_neighbor == null or p_neighbor.children.is_empty(): return p_neighbor
	return p_neighbor.children[Type.TOP_LEFT] if quad_type == Type.BOTTOM_LEFT else p_neighbor.children[Type.TOP_RIGHT]

func get_neighbor_east() -> Quad:
	if parent_quad == null: return null
	if quad_type == Type.TOP_LEFT: return parent_quad.children[Type.TOP_RIGHT]
	if quad_type == Type.BOTTOM_LEFT: return parent_quad.children[Type.BOTTOM_RIGHT]
	
	var p_neighbor = parent_quad.get_neighbor_east()
	if p_neighbor == null or p_neighbor.children.is_empty(): return p_neighbor
	return p_neighbor.children[Type.TOP_LEFT] if quad_type == Type.TOP_RIGHT else p_neighbor.children[Type.BOTTOM_LEFT]

func get_neighbor_west() -> Quad:
	if parent_quad == null: return null
	if quad_type == Type.TOP_RIGHT: return parent_quad.children[Type.TOP_LEFT]
	if quad_type == Type.BOTTOM_RIGHT: return parent_quad.children[Type.BOTTOM_LEFT]
	
	var p_neighbor = parent_quad.get_neighbor_west()
	if p_neighbor == null or p_neighbor.children.is_empty(): return p_neighbor
	return p_neighbor.children[Type.TOP_RIGHT] if quad_type == Type.TOP_LEFT else p_neighbor.children[Type.BOTTOM_RIGHT]


func refresh_neighbors():
	var neighbors = [
		get_neighbor_north(),
		get_neighbor_south(),
		get_neighbor_east(),
		get_neighbor_west()
	]
	
	for neighbor in neighbors:
		if neighbor != null:
			# recalculating entire chunk right now, can't just change specific vertices, 
			# because of collision mesh and gpu uploading makes this faster anyways
			neighbor.force_rebuild_leaves()

func force_rebuild_leaves():
	if chunk != null:
		draw_chunk()
	else:
		for child in children:
			child.force_rebuild_leaves()

func split():
	if children.is_empty():
		ensure_neighbors_within_one_level()
		var m01 = corners[0].lerp(corners[1], 0.5) # Top
		var m12 = corners[1].lerp(corners[2], 0.5) # Right
		var m23 = corners[2].lerp(corners[3], 0.5) # Bottom
		var m30 = corners[3].lerp(corners[0], 0.5) # Left
		var m_mid = corners[0].lerp(corners[2], 0.5) # Center
		
		children.append(Quad.new(planet, level + 1, [corners[0], m01, m_mid, m30], self, Type.TOP_LEFT)) # TopLeft
		children.append(Quad.new(planet, level + 1, [m01, corners[1], m12, m_mid], self, Type.TOP_RIGHT)) # TopRight
		children.append(Quad.new(planet, level + 1, [m_mid, m12, corners[2], m23], self, Type.BOTTOM_RIGHT)) # BottomRight
		children.append(Quad.new(planet, level + 1, [m30, m_mid, m23, corners[3]], self, Type.BOTTOM_LEFT)) # BottomLeft
		
		refresh_neighbors()

func ensure_neighbors_within_one_level():
	for neighbor in [get_neighbor_north(), get_neighbor_south(), get_neighbor_east(), get_neighbor_west()]:
		if neighbor != null and neighbor.level < level and neighbor.children.is_empty():
			neighbor.split()

func merge():
	for child in children:
		child.remove_chunk()
	children.clear()
	refresh_neighbors()

func remove_chunk():
	if chunk:
		#chunk.generation_id += 1
		#if chunk.active_task_id != -1:
			#WorkerThreadPool.wait_for_task_completion(chunk.active_task_id)
			#chunk.active_task_id = -1
		#planet.return_chunk(chunk)
		chunk.recycle()
		chunk = null

func draw_chunk():
	if chunk == null:
		chunk = planet.request_chunk()
		chunk.visible = false
	
	if chunk.active_task_id != -1:
		chunk.redraw_requested = true
		chunk.owner_quad = self
		return
	
	chunk.owner_quad = self
	chunk.generation_id += 1
	
	var n_nb = get_neighbor_north()
	var s_nb = get_neighbor_south()
	var e_nb = get_neighbor_east()
	var w_nb = get_neighbor_west()
	
	var stitch_n = n_nb != null and n_nb.level < level
	var stitch_s = s_nb != null and s_nb.level < level
	var stitch_e = e_nb != null and e_nb.level < level
	var stitch_w = w_nb != null and w_nb.level < level
	
	var dist_to_player = bounding_center.distance_squared_to(planet.camera.global_position)
	var needs_collision = dist_to_player < 90000.0 
	
	#if level > highest_lod:
		#highest_lod = level
		#var chunk_world_size = (planet.radius * 2.0 / sqrt(3.0)) / pow(2, level)
		#print(level, " ", chunk_world_size)
	
	chunk.planet = planet
	chunk.active_task_id = WorkerThreadPool.add_task(Chunk.generate_chunk_data.bind(chunk, chunk.generation_id, planet.detail_noise, planet.terrain_data, corners, planet.grid_size, planet.radius, planet.max_height, stitch_n, stitch_s, stitch_e, stitch_w, needs_collision, planet.max_height * 0.05))
	#chunk.build_mesh(planet, corners, planet.grid_size, planet.radius, planet.max_height, stitch_n, stitch_s, stitch_e, stitch_w, needs_collision)

func has_active_ancestor_chunk() -> bool:
	var p = parent_quad
	while p != null:
		if p.chunk != null:
			return true
		p = p.parent_quad
	return false

func reveal_leaves():
	if children.is_empty():
		if chunk:
			chunk.visible = true
	else:
		for child in children:
			child.reveal_leaves()

func calculate_bounds():
	var mid_point = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
	var surface_center = Planet.spherify(mid_point) * planet.radius
	
	bounding_center = surface_center * (1.0 + (planet.max_height / planet.radius) * 0.5)
	
	var center_dir = surface_center.normalized()
	var corner_dir = Planet.spherify(corners[0]).normalized()
	horizon_cos_alpha = center_dir.dot(corner_dir)
	horizon_sin_alpha = sqrt(maxf(0.0, 1.0 - horizon_cos_alpha * horizon_cos_alpha))
	
	var min_v = Vector3(INF, INF, INF)
	var max_v = Vector3(-INF, -INF, -INF)
	
	var points = corners.duplicate()
	points.append(mid_point)
	
	points.append(corners[0].lerp(corners[1], 0.5))
	points.append(corners[1].lerp(corners[2], 0.5))
	points.append(corners[2].lerp(corners[3], 0.5))
	points.append(corners[3].lerp(corners[0], 0.5))
	
	for p in points:
		var s = Planet.spherify(p)
		var surface = s * planet.radius
		var mountains = s * (planet.radius + planet.max_height)
		min_v = min_v.min(surface).min(mountains)
		max_v = max_v.max(surface).max(mountains)
	bounding_aabb = (AABB(min_v, max_v - min_v)).grow(5.0) # grow, to give a bit of a buffer around the screen edges
