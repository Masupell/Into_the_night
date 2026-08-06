extends CharacterBody3D

const MIN_SPEED = 1.0
const MAX_SPEED = 10000.0
@export var move_speed: float = 2000.0
@export var look_sensitivity: float = 0.1
@export var planet_position := Vector3.ZERO 

var debug_mode := false

@onready var debug_camera := $"../Debug"
@onready var main_camera: Camera3D = $Camera3D

var controlled_camera: Node3D

#temp:
@onready var text = $"../CanvasLayer/Label"

@export var console: CommandConsule
var is_typing: bool = false

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	controlled_camera = main_camera
	
	text.text = str(move_speed) + "m/s  --  " + str(move_speed*3.6) + "km/h"
	
	if console:
		console.console_toggled.connect(func(open: bool): is_typing = open)

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		controlled_camera.rotate_object_local(Vector3.UP, deg_to_rad(-event.relative.x * look_sensitivity))
		controlled_camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(-event.relative.y * look_sensitivity))
		
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			move_speed *= 1.2
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			move_speed /= 1.2
		text.text = str(move_speed) + "m/s  --  " + str(move_speed*3.6) + "km/h"
		move_speed = clamp(move_speed, MIN_SPEED, MAX_SPEED)
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta):
	if is_typing:
		return
	
	var direction = Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W): direction -= controlled_camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_S): direction += controlled_camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_A): direction -= controlled_camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_D): direction += controlled_camera.global_transform.basis.x
	
	if Input.is_key_pressed(KEY_Q):
		controlled_camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(-60.0 * delta))
	if Input.is_key_pressed(KEY_E):
		controlled_camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(60.0 * delta))
	
	if debug_mode:
		velocity = Vector3.ZERO
		controlled_camera.global_position += direction.normalized() * move_speed * delta
	else:
		if direction != Vector3.ZERO:
			velocity = direction.normalized() * move_speed
		else:
			velocity = Vector3.ZERO 
		
		move_and_slide()
	
	if Input.is_key_pressed(KEY_TAB):
		print(global_position)
		
	if Input.is_action_just_released("ui_up"):
		var cube_scene = preload("res://temp/cube.tscn")
		var cube = cube_scene.instantiate()
		get_parent().add_child(cube)
		cube.global_position = global_position

func set_debug_mode(debug: bool) -> int:
	debug_mode = debug
	if debug:
		debug_camera.global_transform = main_camera.global_transform
		debug_camera.current = true
		main_camera.current = false
		controlled_camera = debug_camera
		return 3
	else:
		main_camera.current = true
		debug_camera.current = false
		controlled_camera = main_camera
		return 2

func toggle_debug_mode():
	debug_mode = !debug_mode

	if debug_mode:
		debug_camera.global_transform = main_camera.global_transform
		debug_camera.current = true
		main_camera.current = false
		controlled_camera = debug_camera
	else:
		main_camera.current = true
		debug_camera.current = false
		controlled_camera = main_camera
