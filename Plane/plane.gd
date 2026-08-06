extends CharacterBody3D

@export var gravity := 9.8

@export var stall_speed := 30.0 # speed, where lift equals gravity (so no tipping down anymore)
@export var lift_efficiency := 1.0 # heavier planes are more sluggish, fighter jets quite efficient

@export var max_speed := 65.0
@export var acceleration := 3.0

@export var air_align_speed := 3.0
@export var lift_damping_speed := 4.0 # wings bleeding off downwards speed

var move_speed := 0.0
var fall_speed := 0.0
var max_fall_speed := 50.0

@export var pitch_speed := 1.0
@export var roll_speed := 2.5
@export var yaw_speed := 0.4 #1.2

var ground_align_speed := 10.0

@export var camera_distance := 8.0
@export var camera_sensitivity := 0.005
@export var min_pitch := deg_to_rad(-80.0)
@export var max_pitch := deg_to_rad(80.0)

@onready var pivot = $Pivot
@onready var spring_arm = $Pivot/SpringArm3D
@onready var camera = $Pivot/SpringArm3D/Camera3D

@onready var propellor = $Sketchfab_model/LowPolyPlane01_FBX/RootNode/Propeller/Object_7/Propeller_Plane_0
@export var max_rotor_speed := 8.0 # rotations per second
var rotor_speed := 0.0

@onready var left_aileron = $Sketchfab_model/LowPolyPlane01_FBX/RootNode/LeftAileron
@onready var right_aileron = $Sketchfab_model/LowPolyPlane01_FBX/RootNode/RightAileron
@onready var elevator = $Sketchfab_model/LowPolyPlane01_FBX/RootNode/Elevator
@onready var rudder = $Sketchfab_model/LowPolyPlane01_FBX/RootNode/Rudder

# For Animation
var animation_pitch := 0.0
var animation_roll := 0.0
var animation_yaw := 0.0

const CONTROL_SPEED := 5.0

@export var aileron_angle := 20.0
@export var elevator_angle := 15.0
@export var rudder_angle := 8.0

var left_aileron_rest: Vector3
var right_aileron_rest: Vector3
var elevator_rest: Vector3
var rudder_rest: Vector3

#@onready var text = $"../CanvasLayer/Label"
@export var hud: FligthHUD
@export var planet_radius: float = 5000.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	spring_arm.spring_length = camera_distance
	spring_arm.add_excluded_object(get_rid())
	camera.position = Vector3.ZERO
	
	pivot.top_level = true
	
	left_aileron_rest = left_aileron.rotation
	right_aileron_rest = right_aileron.rotation
	elevator_rest = elevator.rotation
	rudder_rest = rudder.rotation


func _physics_process(delta: float) -> void:
	if global_position.length_squared() < 0.001: # to not crash, when somehow in 0,0,0
		return
	var planet_up = global_position.normalized()
	up_direction = planet_up
	
	var thrust_input := 0.0
	if Input.is_key_pressed(KEY_SHIFT):
		thrust_input += 1.0
		#text.text = str(move_speed) + "m/s  --  " + str(move_speed*3.6) + "km/h"
	if Input.is_key_pressed(KEY_CTRL):
		thrust_input -= 2.0
		#text.text = str(move_speed) + "m/s  --  " + str(move_speed*3.6) + "km/h"
	move_speed = clamp(move_speed + thrust_input * acceleration * delta, 0.0, max_speed)
	
	var forward = global_transform.basis.z
	velocity = (forward * move_speed) + (-planet_up * fall_speed)
	
	var pitch_input := 0.0
	if Input.is_key_pressed(KEY_S): pitch_input -= 1.0 # Pull up
	if Input.is_key_pressed(KEY_W): pitch_input += 1.0 # Pull down
	
	var roll_input := 0.0
	if Input.is_key_pressed(KEY_A): roll_input += 1.0 # Bank left
	if Input.is_key_pressed(KEY_D): roll_input -= 1.0 # Bank right
	
	var yaw_input := 0.0
	if Input.is_key_pressed(KEY_E): yaw_input += 1.0 # Right
	if Input.is_key_pressed(KEY_Q): yaw_input -= 1.0 # Left
	
	if is_on_floor():
		fall_speed = 0.0
		
		var floor_normal = get_floor_normal()
		if basis.y.dot(floor_normal) > 0.2: # Only align, when it is roughly straight (later explode otherwise)
			var correction = basis.y.cross(floor_normal)
			if correction.length() > 0.001:
				rotate(correction.normalized(), correction.length() * ground_align_speed * delta)
	else:
		var lift_factor = clamp((move_speed / stall_speed) * lift_efficiency, 0.0, 1.0)
		var upright_factor = basis.y.dot(planet_up) # 1.0 = upright, -1.0 = upside down
		var effective_lift = lift_factor * upright_factor
		
		#Gravity
		var target_fall_speed = max_fall_speed * (1.0 - effective_lift)
		var adjustment_rate = gravity * (1.0 + lift_factor)
		fall_speed = move_toward(fall_speed, target_fall_speed, adjustment_rate * delta)
		
		#Air alignment
		if velocity.length_squared() > 1.0 and pitch_input == 0.0 and roll_input == 0.0:
			var travel_dir = velocity.normalized()
			var air_correction = forward.cross(travel_dir)
			if air_correction.length_squared() > 0.001:
				rotate(air_correction.normalized(), air_correction.length() * air_align_speed * delta)
	
	if pitch_input != 0.0:
		rotate_object_local(Vector3.RIGHT, pitch_input * pitch_speed * delta)
	if not is_on_floor() and roll_input != 0.0:
		rotate_object_local(Vector3.FORWARD, roll_input * roll_speed * delta)
	if yaw_input != 0.0:
		rotate_object_local(Vector3.UP, -yaw_input * yaw_speed * delta)
	global_transform.basis = global_transform.basis.orthonormalized()
	
	move_and_slide()
	
	
	#Animation
	var speed_percent = move_speed / max_speed
	rotor_speed = ease(speed_percent, 0.5) * max_rotor_speed#lerp(0.0, max_rotor_speed, speed_percent)
	
	propellor.rotate_z(rotor_speed * TAU * delta)
	
	animation_pitch = move_toward(animation_pitch, pitch_input, CONTROL_SPEED * delta)
	animation_roll = move_toward(animation_roll, roll_input, CONTROL_SPEED * delta)
	animation_yaw = move_toward(animation_yaw, yaw_input, CONTROL_SPEED * delta)
	
	left_aileron.rotation.x = lerp_angle(
		left_aileron.rotation.x,
		left_aileron_rest.x + deg_to_rad(20.0 * animation_roll),
		delta * 10.0
	)

	right_aileron.rotation.x = lerp_angle(
		right_aileron.rotation.x,
		right_aileron_rest.x - deg_to_rad(20.0 * animation_roll),
		delta * 10.0
	)

	elevator.rotation.x = lerp_angle(
		elevator.rotation.x,
		elevator_rest.x + deg_to_rad(15.0 * animation_pitch),
		delta * 10.0
	)

	rudder.rotation.y = lerp_angle(
		rudder.rotation.y,
		rudder_rest.y + deg_to_rad(8.0 * animation_yaw),
		delta * 10.0
	)
	
	
	#Camera movement around Plane
	pivot.global_position = global_position

	var current_fwd = -pivot.global_transform.basis.z
	var current_pitch = asin(clamp(current_fwd.dot(planet_up), -1.0, 1.0))
	var right = current_fwd.cross(planet_up).normalized()
	if right.length_squared() < 0.001:
		right = pivot.global_transform.basis.x.slide(planet_up).normalized()
	var level_fwd = planet_up.cross(right).normalized()
	var clean_horizon = Basis(right, planet_up, -level_fwd)
	var pitch_rot = Quaternion(right, current_pitch)
	
	pivot.global_transform.basis = Basis(pitch_rot) * clean_horizon
	pivot.global_transform.basis = pivot.global_transform.basis.orthonormalized()
	
	# Raycast for above ground height measure
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, Vector3.ZERO)
	query.exclude = [self.get_rid()]
	var result = space_state.intersect_ray(query)
	var current_agl: float = -1.0
	if result:
		var hit_position: Vector3 = result.position
		current_agl =global_position.distance_to(hit_position)
	
	#Compass
	var world_north_pole = Vector3.UP
	var surface_north = world_north_pole.slide(planet_up).normalized()
	if surface_north.length_squared() < 0.001:
		surface_north = Vector3.FORWARD.slide(planet_up).normalized()
	var surface_east = planet_up.cross(surface_north).normalized()
	var heading_forward = forward.slide(planet_up).normalized()
	
	var heading_rad = atan2(heading_forward.dot(surface_east), heading_forward.dot(surface_north))
	var heading_deg = wrapf(rad_to_deg(heading_rad), 0.0, 360.0)
	
	# Hud
	if hud:
		var power = move_speed/max_speed
		var current_speed = velocity.length()
		var current_amsl = global_position.length() - planet_radius
		var pitch_rad = asin(clamp(forward.dot(planet_up), -1.0, 1.0))
		var pitch_deg = rad_to_deg(pitch_rad)
		var roll_rad = atan2(-global_transform.basis.x.dot(planet_up), global_transform.basis.y.dot(planet_up))
		var roll_deg = rad_to_deg(roll_rad)
		hud.update_metrics(power, current_speed, heading_deg, current_amsl, current_agl, pitch_deg, roll_deg)
	
	if Input.is_key_pressed(KEY_ESCAPE): 
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): 
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var current_up = global_position.normalized()
		
		var yaw_delta = -event.relative.x * camera_sensitivity
		pivot.global_transform.basis = pivot.global_transform.basis.rotated(current_up, yaw_delta)
		
		var forward = -pivot.global_transform.basis.z
		var current_pitch = asin(clamp(forward.dot(current_up), -1.0, 1.0))
		
		var target_pitch = clamp(current_pitch - event.relative.y * camera_sensitivity, min_pitch, max_pitch)
		var pitch_delta = target_pitch - current_pitch
		
		var local_x = pivot.global_transform.basis.x
		pivot.global_transform.basis = pivot.global_transform.basis.rotated(local_x, pitch_delta)
