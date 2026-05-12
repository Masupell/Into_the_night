class_name Quad
extends RefCounted

var planet: Planet
var level: int = 0 # Depth of quadtree
var corners: Array
var children: Array[Quad] = []
var chunk: Chunk = null

func _init(_planet: Planet, _level: int, _corners: Array) -> void:
	self.planet = _planet
	self.level = _level
	self.corners = _corners

func update_lod(camera_pos: Vector3):
	var center = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
	
	var surface_center = Planet.spherify(center) * planet.radius
	var dist_to_cam = camera_pos.distance_to(surface_center)
	
	var split_dist = planet.radius * 2.0 / pow(2, level)
	if dist_to_cam < split_dist and level < planet.max_lod_level:
		if children.is_empty():
			split()
		for child in children:
			child.update_lod(camera_pos)
		remove_chunk()
	else:
		if not children.is_empty():
			merge()
		draw_chunk()

func split():
	var m01 = corners[0].lerp(corners[1], 0.5) # Top
	var m12 = corners[1].lerp(corners[2], 0.5) # Right
	var m23 = corners[2].lerp(corners[3], 0.5) # Bottom
	var m30 = corners[3].lerp(corners[0], 0.5) # Left
	var m_mid = corners[0].lerp(corners[2], 0.5) # Center
	
	children.append(Quad.new(planet, level + 1, [corners[0], m01, m_mid, m30])) # TopLeft
	children.append(Quad.new(planet, level + 1, [m01, corners[1], m12, m_mid])) # TopRight
	children.append(Quad.new(planet, level + 1, [m_mid, m12, corners[2], m23])) # BottomRight
	children.append(Quad.new(planet, level + 1, [m30, m_mid, m23, corners[3]])) # BottomLeft

func merge():
	for child in children:
		child.remove_chunk()
	children.clear()

func remove_chunk():
	if chunk:
		chunk.queue_free()
		chunk = null

func draw_chunk():
	if chunk == null:
		chunk = Chunk.new()
		planet.add_child(chunk)
		chunk.build_mesh(corners, planet.grid_size, planet.radius)
