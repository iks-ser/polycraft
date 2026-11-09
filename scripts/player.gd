class_name Player
extends CharacterBody3D
## First-person player: WASD to move, mouse to look, Space to jump, Shift to
## sprint, Esc to release the mouse (click the window to grab it again).
##
## Input actions (move_forward, move_back, move_left, move_right, jump, sprint)
## are defined in project.godot, so they can be rebound in Project Settings.

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 9.0
@export var jump_velocity: float = 5.0
## How quickly the player reaches the target speed on the ground (m/s²).
@export var ground_acceleration: float = 40.0
## Same, while airborne. Lower = floatier, less air control.
@export var air_acceleration: float = 8.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export_range(1.0, 89.0) var max_pitch_degrees: float = 89.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _head: Node3D = $Head


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Yaw turns the whole body, pitch only tilts the head/camera.
		rotate_y(-event.relative.x * mouse_sensitivity)
		var max_pitch := deg_to_rad(max_pitch_degrees)
		_head.rotation.x = clampf(_head.rotation.x - event.relative.y * mouse_sensitivity, -max_pitch, max_pitch)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# Vertical: gravity / jump.
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= _gravity * delta

	# Horizontal: WASD relative to where the player is facing.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration

	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)

	move_and_slide()
