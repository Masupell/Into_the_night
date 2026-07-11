extends CharacterBody3D

@export var walk_speed := 8.0
@export var acceleration := 30.0
@export var jump_speed := 10.0
@export var jetpack_force := 20.0
@export var gravity := 9.8
@export var mouse_sensitivity := 0.002

@onready var camera_pivot := $CameraPivot

var look_direction := Vector3.FORWARD
var camera_pitch := 0.0
var active := false

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event):
	if not active:
		return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var up = global_position.normalized()
		if up.length() < 0.001:
			return
		look_direction = look_direction.rotated(up, -event.relative.x * mouse_sensitivity)
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch = clamp(camera_pitch, deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta):
	var up = global_position.normalized()
	if up.length() < 0.001:
		return
	var down = -up
	up_direction = up
	
	var flat_look = (look_direction - up * look_direction.dot(up))
	
	if flat_look.length() > 0.001:
		flat_look = flat_look.normalized()
		basis = Basis.looking_at(flat_look, up)
		look_direction = flat_look
	
	camera_pivot.rotation.x = camera_pitch
	
	velocity += down * gravity * delta
	
	var input_dir = Input.get_vector("left", "right", "forward", "backward")

	var forward = -global_transform.basis.z
	var right = global_transform.basis.x

	var move_dir = -forward * input_dir.y + right * input_dir.x
	
	var horizontal_velocity = velocity - up * velocity.dot(up)
	
	if move_dir.length() > 0:
		horizontal_velocity = horizontal_velocity.move_toward(move_dir.normalized() * walk_speed, acceleration * delta)
	else:
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, acceleration * delta)
	
	velocity = (horizontal_velocity + up * velocity.dot(up))
	
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity += up * jump_speed
	
	if Input.is_action_pressed("jump") and not is_on_floor():
		velocity += up * jetpack_force * delta
	
	move_and_slide()
	
	
	if Input.is_key_pressed(KEY_ESCAPE): 
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): 
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
