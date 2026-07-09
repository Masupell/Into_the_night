extends CharacterBody3D

const MIN_SPEED = 1.0
const MAX_SPEED = 10000.0
@export var move_speed: float = 2000.0
@export var look_sensitivity: float = 0.1
@export var planet_position := Vector3.ZERO 

var debug_mode := false
var align_to_planet := false 

@onready var debug_camera := $"../Debug"
@onready var main_camera: Camera3D = $Camera3D

var controlled_camera: Node3D

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	controlled_camera = main_camera

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if align_to_planet and not debug_mode:
			rotate_object_local(Vector3.UP, deg_to_rad(-event.relative.x * look_sensitivity))
			
			main_camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(-event.relative.y * look_sensitivity))
			main_camera.rotation.x = clamp(main_camera.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
		else:
			controlled_camera.rotate_object_local(Vector3.UP, deg_to_rad(-event.relative.x * look_sensitivity))
			controlled_camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(-event.relative.y * look_sensitivity))
		
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			move_speed *= 1.2
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			move_speed /= 1.2
		move_speed = clamp(move_speed, MIN_SPEED, MAX_SPEED)
		
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_3:
			align_to_planet = !align_to_planet
			if align_to_planet:
				main_camera.rotation.y = 0.0
				main_camera.rotation.z = 0.0
			else:
				up_direction = Vector3.UP

func _process(delta):
	var direction = Vector3.ZERO
	
	if align_to_planet and not debug_mode:
		if Input.is_key_pressed(KEY_W): direction -= global_transform.basis.z
		if Input.is_key_pressed(KEY_S): direction += global_transform.basis.z
		if Input.is_key_pressed(KEY_A): direction -= global_transform.basis.x
		if Input.is_key_pressed(KEY_D): direction += global_transform.basis.x
	else:
		if Input.is_key_pressed(KEY_W): direction -= controlled_camera.global_transform.basis.z
		if Input.is_key_pressed(KEY_S): direction += controlled_camera.global_transform.basis.z
		if Input.is_key_pressed(KEY_A): direction -= controlled_camera.global_transform.basis.x
		if Input.is_key_pressed(KEY_D): direction += controlled_camera.global_transform.basis.x
		
		if Input.is_key_pressed(KEY_Q):
			controlled_camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(-60.0 * delta))
		if Input.is_key_pressed(KEY_E):
			controlled_camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(60.0 * delta))
	
	if align_to_planet and not debug_mode:
		var target_up = (global_position - planet_position).normalized()
		up_direction = target_up
		
		var forward = -global_transform.basis.z
		var right = forward.cross(target_up).normalized()
		forward = target_up.cross(right).normalized() 
		
		var target_basis = Basis(right, target_up, -forward)
		global_transform.basis = global_transform.basis.slerp(target_basis, 14.0 * delta).orthonormalized()

	if debug_mode:
		velocity = Vector3.ZERO
		controlled_camera.global_position += direction.normalized() * move_speed * delta
	else:
		if direction != Vector3.ZERO:
			velocity = direction.normalized() * move_speed
		else:
			velocity = Vector3.ZERO 

		var altitude_before_move = global_position.distance_to(planet_position)
		
		move_and_slide()
		
		if align_to_planet and get_slide_collision_count() == 0:
			var current_direction = (global_position - planet_position).normalized()
			global_position = planet_position + current_direction * altitude_before_move
	
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
		debug_camera.global_transform = main_camera.global_transform
		debug_camera.current = true
		main_camera.current = false
		controlled_camera = debug_camera
	else:
		main_camera.current = true
		debug_camera.current = false
		controlled_camera = main_camera
		# Ensure layout is cleared up returning from noclip
		if align_to_planet:
			main_camera.rotation.y = 0.0
			main_camera.rotation.z = 0.0
