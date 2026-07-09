extends RigidBody3D

func _ready() -> void:
	gravity_scale = 0.0

func _physics_process(_delta: float) -> void:
	var gravity_strength = 9.8
	var gravity_dir = -global_position.normalized()
	
	apply_central_force(gravity_dir * gravity_strength * mass)
