extends Camera3D

const MIN_SPEED = 1.0
const MAX_SPEED = 100.0
@export var move_speed: float = 50.0
@export var look_sensitivity: float = 0.1

var debug_mode := false

@onready var debug_camera := $"../Debug"

var controlled_camera: Camera3D

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	controlled_camera = self

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		controlled_camera.rotate_object_local(Vector3.UP, deg_to_rad(-event.relative.x * look_sensitivity))
		controlled_camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(-event.relative.y * look_sensitivity))
		
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			move_speed *= 1.2
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			move_speed /= 1.2
		move_speed = clamp(move_speed, MIN_SPEED, MAX_SPEED)

func _process(delta):
	var direction = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direction -= controlled_camera.transform.basis.z
	if Input.is_key_pressed(KEY_S):
		direction += controlled_camera.transform.basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= controlled_camera.transform.basis.x
	if Input.is_key_pressed(KEY_D):
		direction += controlled_camera.transform.basis.x
	if Input.is_key_pressed(KEY_Q):
		controlled_camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(60.0 * delta))
	if Input.is_key_pressed(KEY_E):
		controlled_camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(-60.0 * delta))
	
	controlled_camera.global_position += direction.normalized() * move_speed * delta
	
	if Input.is_key_pressed(KEY_TAB):
		print(global_position)
	if Input.is_action_just_released("ui_accept"):
		toggle_debug_mode()
	if Input.is_key_pressed(KEY_ESCAPE): 
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): 
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_debug_mode():
	debug_mode = !debug_mode

	if debug_mode:
		debug_camera.global_transform = global_transform
		
		debug_camera.current = true
		current = false
		
		controlled_camera = debug_camera
	else:
		current = true
		debug_camera.current = false
		controlled_camera = self
