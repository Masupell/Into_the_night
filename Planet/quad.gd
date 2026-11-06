class_name Quad
extends RefCounted

var planet: Planet
var level: int = 0 # Depth of quadtree
var corners: Array
var face: int # cube face, same for the whole tree
var uv_min: Vector2 # uv rect on the face
var uv_max: Vector2
var center: PackedFloat64Array # x, y, z in doubles, origin of the chunk mesh
var children: Array[Quad] = []
var chunk: Chunk = null

const FRUSTUM_OUTSIDE = 0
const FRUSTUM_INTERSECT = 1
const FRUSTUM_INSIDE = 2

var frustum_state = FRUSTUM_INTERSECT
var bounding_aabb: AABB # sea level up to max_height
var bounding_aabb_deep: AABB # down to the ocean floor, for under water
# For test_frustum
var aabb_center: Vector3
var aabb_extents: Vector3
var aabb_margin: float
var aabb_deep_center: Vector3
var aabb_deep_extents: Vector3
var aabb_deep_margin: float
var bounding_center: Vector3
var surface_dir: Vector3
var half_diagonal: float
# Visible height range, from the parent until the own chunk is built
var surface_min: float
var surface_max: float
var horizon_cos_alpha: float
var horizon_sin_alpha: float
var parent_quad: Quad
var currently_visible: bool = true

enum Type {TOP_LEFT = 0, TOP_RIGHT = 1, BOTTOM_RIGHT = 2, BOTTOM_LEFT = 3, ROOT = -1}
var quad_type: Type = Type.ROOT

#var highest_lod: int = 0

func _init(_planet: Planet, _level: int, _corners: Array, _parent: Quad = null, _type: Type = Type.ROOT, _face: int = -1) -> void:
	self.planet = _planet
	self.level = _level
	self.corners = _corners
	self.parent_quad = _parent
	self.quad_type = _type
	self.face = _parent.face if _parent else _face
	self.uv_min = CubeSphere.cube_to_face_uv(face, corners[0])
	self.uv_max = CubeSphere.cube_to_face_uv(face, corners[2])
	if _parent:
		surface_min = _parent.surface_min
		surface_max = _parent.surface_max
		currently_visible = _parent.currently_visible
	else:
		surface_min = planet.min_terrain_radius - planet.radius
		surface_max = planet.max_height
	calculate_bounds()

# True when its chunk, or all visible children are ready
func update_lod(camera_pos: Vector3, frustum_planes: Array, ancestor_has_chunk: bool = false) -> bool:
	if parent_quad and parent_quad.frustum_state == FRUSTUM_INSIDE:
		frustum_state = FRUSTUM_INSIDE
	elif not frustum_planes.is_empty():
		var under_water: bool = camera_pos.length() < planet.radius
		frustum_state = test_frustum(frustum_planes, under_water)
	else:
		frustum_state = FRUSTUM_INTERSECT

	var was_visible := currently_visible
	currently_visible = is_above_horizon(camera_pos) and frustum_state != FRUSTUM_OUTSIDE
	if not currently_visible:
		# Everything below is out of view too
		if was_visible:
			hide_subtree()
		return true

	var dist_to_cam := center_distance(camera_pos)

	if level < planet.lod_level_limit and dist_to_cam < planet.split_distances[level]:
		if children.is_empty():
			split()
		var children_ready := true
		for child in children:
			if not child.update_lod(camera_pos, frustum_planes, ancestor_has_chunk or chunk != null):
				children_ready = false
		if children_ready:
			reveal_leaves()
			remove_chunk()
		return children_ready

	if chunk == null:
		draw_chunk()
	if chunk != null and chunk.is_ready:
		if not children.is_empty():
			chunk.visible = true
			merge()
		elif not chunk.visible and not ancestor_has_chunk:
			chunk.visible = true
		return true
	# Waiting to merge, the children are still shown
	if not children.is_empty():
		return are_children_ready()
	return false

# No chunks anywhere below
func hide_subtree():
	currently_visible = false
	remove_chunk()
	for child in children:
		child.hide_subtree()

# Distance to the quad centers height range
func center_distance(pos: Vector3) -> float:
	var height := pos.dot(surface_dir) - planet.radius
	return pos.distance_to(surface_dir * (planet.radius + clampf(height, surface_min, surface_max)))

# Roughly the distance to the surface, 0 when above it
func surface_distance(pos: Vector3) -> float:
	return maxf(0.0, center_distance(pos) - half_diagonal)

# Water surface included
func set_surface_range(height_range: Vector2):
	surface_min = height_range.x
	surface_max = height_range.y

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

# Frustum planes point outwards
func test_frustum(frustum_planes: Array, under_water: bool) -> int:
	var center_box := aabb_deep_center if under_water else aabb_center
	var extents := aabb_deep_extents if under_water else aabb_extents
	var margin := aabb_deep_margin if under_water else aabb_margin
	var fully_inside_count := 0

	for plane: Plane in frustum_planes:
		var distance := plane.distance_to(center_box)
		var r := extents.dot(plane.normal.abs())
		if distance - r > margin:
			return FRUSTUM_OUTSIDE
		if distance + r <= 0.0:
			fully_inside_count += 1

	if fully_inside_count == frustum_planes.size():
		return FRUSTUM_INSIDE
	return FRUSTUM_INTERSECT

func is_above_horizon(camera_pos: Vector3) -> bool:
	var camera_distance: float = camera_pos.length()
	# Under water only the ocean floor hides things
	@warning_ignore("incompatible_ternary")
	var occluder_radius: float = planet.radius if camera_distance > planet.radius else planet.min_terrain_radius
	if camera_distance <= occluder_radius:
		return true

	var camera_dir: Vector3 = camera_pos / camera_distance
	var chunk_dir: Vector3 = bounding_center.normalized()
	var cos_angle_to_chunk: float = camera_dir.dot(chunk_dir)

	if cos_angle_to_chunk >= horizon_cos_alpha:
		return true

	var cos_camera_horizon: float = occluder_radius / camera_distance
	var sin_camera_horizon: float = sqrt(maxf(0.0, 1.0 - cos_camera_horizon * cos_camera_horizon))
	var cos_terrain_extend: float = occluder_radius / (planet.radius + planet.max_height)
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


# Finest existing quad at each corner, null outside the face
func get_diagonal_neighbors() -> Array:
	var outward := (uv_max - uv_min) * 0.25
	return [
		quad_at(Vector2(uv_max.x + outward.x, uv_min.y - outward.y)),
		quad_at(uv_max + outward),
		quad_at(Vector2(uv_min.x - outward.x, uv_max.y + outward.y)),
		quad_at(uv_min - outward),
	]

func quad_at(uv: Vector2) -> Quad:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return null
	var quad := self
	while quad.parent_quad != null:
		quad = quad.parent_quad
	while not quad.children.is_empty():
		var mid: Vector2 = (quad.uv_min + quad.uv_max) * 0.5
		if uv.y < mid.y:
			quad = quad.children[Type.TOP_LEFT if uv.x < mid.x else Type.TOP_RIGHT]
		else:
			quad = quad.children[Type.BOTTOM_LEFT if uv.x < mid.x else Type.BOTTOM_RIGHT]
	return quad

func refresh_neighbors():
	var neighbors = [
		get_neighbor_north(),
		get_neighbor_south(),
		get_neighbor_east(),
		get_neighbor_west()
	]
	# corners only care if the tile level changes here
	var grid := planet.grid_size_for_level(level)
	if level < planet.lod_level_limit and planet.terrain_data.tile_level_for(level, grid) != planet.terrain_data.tile_level_for(level + 1, planet.grid_size_for_level(level + 1)):
		neighbors.append_array(get_diagonal_neighbors())

	for neighbor in neighbors:
		if neighbor != null:
			# recalculating entire chunk right now, can't just change specific vertices,
			# because of collision mesh and gpu uploading makes this faster anyways
			neighbor.force_rebuild_leaves()

func force_rebuild_leaves():
	if chunk != null:
		draw_chunk()
	# children can be shown while this chunk still exists
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
		child.remove_subtree()
	children.clear()
	refresh_neighbors()

# The whole subtree, otherwise deeper chunks stay forever
func remove_subtree():
	remove_chunk()
	for child in children:
		child.remove_subtree()
	children.clear()

# Parent and children reference each other, leaks otherwise
func release_tree():
	for child in children:
		child.release_tree()
	children.clear()
	parent_quad = null
	chunk = null

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
		chunk.planet = planet

	if chunk.active_task_id != -1:
		chunk.redraw_requested = true
		chunk.owner_quad = self
		return

	chunk.owner_quad = self

	var current_grid_size = planet.grid_size_for_level(level)

	var sampler := planet.terrain_data.get_sampler(face, level, current_grid_size, (uv_min + uv_max) * 0.5)
	if sampler == null: # tile is loading, try next frame
		chunk.waiting_for_tiles = true
		return

	var n_nb = get_neighbor_north()
	var s_nb = get_neighbor_south()
	var e_nb = get_neighbor_east()
	var w_nb = get_neighbor_west()

	# Coarsest last, it wins the corners
	var edge_samplers := []
	var tile_level: int = planet.terrain_data.tile_level_for(level, current_grid_size)
	# north, south, east, west, then the corners: north east, south east, south west, north west
	var neighbors := [n_nb, s_nb, e_nb, w_nb]
	neighbors.append_array(get_diagonal_neighbors())
	for i in range(8):
		if neighbors[i] == null:
			continue
		var nb_level: int = neighbors[i].level
		var nb_grid: int = planet.grid_size_for_level(nb_level)
		if planet.terrain_data.tile_level_for(nb_level, nb_grid) < tile_level:
			var edge_sampler := planet.terrain_data.get_sampler(face, nb_level, nb_grid, (uv_min + uv_max) * 0.5)
			if edge_sampler == null: # tile is loading, try next frame
				chunk.waiting_for_tiles = true
				return
			edge_samplers.append([i, edge_sampler])
	edge_samplers.sort_custom(func(a, b): return a[1].tile.level > b[1].tile.level)

	chunk.generation_id += 1

	# Only stitch where the neighbour's spacing is really twice
	var spacing := planet.vertex_spacing_for_level(level) * 1.5
	var stitch_n = n_nb != null and planet.vertex_spacing_for_level(n_nb.level) > spacing
	var stitch_s = s_nb != null and planet.vertex_spacing_for_level(s_nb.level) > spacing
	var stitch_e = e_nb != null and planet.vertex_spacing_for_level(e_nb.level) > spacing
	var stitch_w = w_nb != null and planet.vertex_spacing_for_level(w_nb.level) > spacing
	# Only morph if the parent was coarser
	var morph_from_parent = parent_quad != null and planet.vertex_spacing_for_level(level - 1) > spacing

	#if level > highest_lod:
		#highest_lod = level
		#var chunk_world_size = (planet.radius * 2.0 / sqrt(3.0)) / pow(2, level)
		#print(level, " ", chunk_world_size)

	chunk.active_task_id = WorkerThreadPool.add_task(Chunk.generate_chunk_data.bind(chunk, chunk.generation_id, planet.detail_noise, sampler, uv_min, uv_max, corners, center, current_grid_size, planet.radius, planet.max_height, stitch_n, stitch_s, stitch_e, stitch_w, planet.max_height * 0.05, morph_from_parent, edge_samplers))
	chunk.set_instance_shader_parameter("instance_lod_level", float(level))
	#chunk.build_mesh(planet, corners, planet.grid_size, planet.radius, planet.max_height, stitch_n, stitch_s, stitch_e, stitch_w, needs_collision)

# Children start in the parent's shape and morph to their own
func reveal_leaves():
	if children.is_empty():
		if chunk and not chunk.visible:
			chunk.visible = true
			chunk.start_morph()
	else:
		for child in children:
			child.reveal_leaves()

func calculate_bounds():
	var mid_point = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
	var surface_center = CubeSphere.spherify(mid_point) * planet.radius

	var x2: float = mid_point.x * mid_point.x
	var y2: float = mid_point.y * mid_point.y
	var z2: float = mid_point.z * mid_point.z
	center = PackedFloat64Array([
		CubeSphere.spherify_axis(mid_point.x, y2, z2) * planet.radius,
		CubeSphere.spherify_axis(mid_point.y, z2, x2) * planet.radius,
		CubeSphere.spherify_axis(mid_point.z, x2, y2) * planet.radius,
	])

	bounding_center = surface_center * (1.0 + (planet.max_height / planet.radius) * 0.5)

	var center_dir = surface_center.normalized()
	surface_dir = center_dir
	var corner_dir = CubeSphere.spherify(corners[0]).normalized()
	half_diagonal = surface_center.distance_to(corner_dir * planet.radius)
	horizon_cos_alpha = center_dir.dot(corner_dir)
	horizon_sin_alpha = sqrt(maxf(0.0, 1.0 - horizon_cos_alpha * horizon_cos_alpha))

	var min_v = Vector3(INF, INF, INF)
	var max_v = Vector3(-INF, -INF, -INF)
	var deep_min = Vector3(INF, INF, INF)
	var deep_max = Vector3(-INF, -INF, -INF)

	var points = corners.duplicate()
	points.append(mid_point)

	points.append(corners[0].lerp(corners[1], 0.5))
	points.append(corners[1].lerp(corners[2], 0.5))
	points.append(corners[2].lerp(corners[3], 0.5))
	points.append(corners[3].lerp(corners[0], 0.5))

	for p in points:
		var s = CubeSphere.spherify(p)
		var surface = s * planet.radius
		var mountains = s * (planet.radius + planet.max_height)
		var ocean_floor = s * planet.min_terrain_radius
		min_v = min_v.min(surface).min(mountains)
		max_v = max_v.max(surface).max(mountains)
		deep_min = deep_min.min(min_v).min(ocean_floor)
		deep_max = deep_max.max(max_v).max(ocean_floor)
	bounding_aabb = (AABB(min_v, max_v - min_v)).grow(5.0) # bit of buffer around the screen edges
	bounding_aabb_deep = (AABB(deep_min, deep_max - deep_min)).grow(5.0)

	aabb_center = bounding_aabb.get_center()
	aabb_extents = bounding_aabb.size * 0.5
	aabb_margin = bounding_aabb.size.length() * 0.15
	aabb_deep_center = bounding_aabb_deep.get_center()
	aabb_deep_extents = bounding_aabb_deep.size * 0.5
	aabb_deep_margin = bounding_aabb_deep.size.length() * 0.15
