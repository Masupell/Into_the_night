class_name CubeSphere
extends RefCounted

## Mapping between the cube (6 faces, uv 0..1 per face) and the unit sphere.
## Every face/tile/chunk lookup goes through here, so the quadtree, terrain data and tiles all agree.
## Face corners are [top_left, top_right, bottom_right, bottom_left], u goes left -> right, v goes top -> bottom.

const FACES: Array = [
	[Vector3(-1, 1, 1), Vector3( 1, 1, 1), Vector3( 1,-1, 1), Vector3(-1,-1, 1)], # 0 Front (+Z)
	[Vector3( 1, 1, 1), Vector3( 1, 1,-1), Vector3( 1,-1,-1), Vector3( 1,-1, 1)], # 1 Right (+X)
	[Vector3( 1, 1,-1), Vector3(-1, 1,-1), Vector3(-1,-1,-1), Vector3( 1,-1,-1)], # 2 Back  (-Z)
	[Vector3(-1, 1,-1), Vector3(-1, 1, 1), Vector3(-1,-1, 1), Vector3(-1,-1,-1)], # 3 Left  (-X)
	[Vector3(-1, 1,-1), Vector3( 1, 1,-1), Vector3( 1, 1, 1), Vector3(-1, 1, 1)], # 4 Top   (+Y)
	[Vector3(-1,-1, 1), Vector3( 1,-1, 1), Vector3( 1,-1,-1), Vector3(-1,-1,-1)], # 5 Bottom(-Y)
]

static func spherify(p: Vector3) -> Vector3:
	var x2 := p.x * p.x
	var y2 := p.y * p.y
	var z2 := p.z * p.z

	var res := Vector3.ZERO
	res.x = p.x * sqrt(1.0 - y2 / 2.0 - z2 / 2.0 + y2 * z2 / 3.0)
	res.y = p.y * sqrt(1.0 - z2 / 2.0 - x2 / 2.0 + z2 * x2 / 3.0)
	res.z = p.z * sqrt(1.0 - x2 / 2.0 - y2 / 2.0 + x2 * y2 / 3.0)
	return res

static func face_to_cube(face: int, uv: Vector2) -> Vector3:
	var c: Array = FACES[face]
	return c[0] + (c[1] - c[0]) * uv.x + (c[3] - c[0]) * uv.y

static func face_to_sphere(face: int, uv: Vector2) -> Vector3:
	return spherify(face_to_cube(face, uv))

static func get_face(dir: Vector3) -> int:
	var a := dir.abs()
	if a.x >= a.y and a.x >= a.z:
		return 1 if dir.x > 0.0 else 3
	if a.y >= a.z:
		return 4 if dir.y > 0.0 else 5
	return 0 if dir.z > 0.0 else 2

# Inverse of face_to_sphere.
static func get_face_uv(dir: Vector3, face: int) -> Vector2:
	var s := dir.normalized()
	var c: Array = FACES[face]
	var cube := Vector3.ZERO

	match face:
		0, 2: # z fixed
			var xy := unspherify_pair(s.x, s.y)
			cube = Vector3(xy.x, xy.y, c[0].z)
		1, 3: # x fixed
			var yz := unspherify_pair(s.y, s.z)
			cube = Vector3(c[0].x, yz.x, yz.y)
		_: # y fixed
			var xz := unspherify_pair(s.x, s.z)
			cube = Vector3(xz.x, c[0].y, xz.y)

	var to_cube: Vector3 = cube - c[0]
	var u: float = to_cube.dot(c[1] - c[0]) / 4.0 # edges are 2 long, so squared length is 4
	var v: float = to_cube.dot(c[3] - c[0]) / 4.0
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))

# Closed form inverse of spherify for the two free coordinates of a face
static func unspherify_pair(a: float, b: float) -> Vector2:
	var a2 := a * a * 2.0
	var b2 := b * b * 2.0
	var inner := -a2 + b2 - 3.0
	var inner_sqrt := -sqrt(maxf(0.0, inner * inner - 12.0 * a2))

	var x := sqrt(maxf(0.0, inner_sqrt + a2 - b2 + 3.0)) * sqrt(0.5) * signf(a)
	var y := sqrt(maxf(0.0, inner_sqrt - a2 + b2 + 3.0)) * sqrt(0.5) * signf(b)
	return Vector2(clampf(x, -1.0, 1.0), clampf(y, -1.0, 1.0))
