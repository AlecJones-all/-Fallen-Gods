extends CharacterBody3D

signal hp_changed(current: float, maximum: float)
signal dash_state_changed(remaining: float, total: float)
signal aim_point_changed(point: Vector3)
signal died

const GROUND_Y: float = 0.0
const AIM_MARKER_Y: float = 0.02
const AIM_EPSILON: float = 0.0001

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _facing: Node3D = $FacingWedge
@onready var _aim_marker: MeshInstance3D = $AimMarker

var _max_hp: float = 100.0
var _current_hp: float = 100.0
var _dead: bool = false

var _move_speed: float = 5.5
var _sprint_multiplier: float = 1.6
var _acceleration: float = 40.0
var _friction: float = 30.0
var _dash_speed: float = 16.0
var _dash_time: float = 0.16
var _dash_cooldown: float = 1.0
var _radius: float = 0.45
var _height: float = 1.8
var _gravity: float = 9.8

var _dash_left: float = 0.0
var _dash_dir: Vector3 = Vector3.FORWARD
var _cooldown_left: float = 0.0
var _reported_cooldown: float = 0.0

var _aim_point: Vector3 = Vector3.ZERO
var _has_aim: bool = false
var _last_move_dir: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_read_tuning()
	_apply_geometry()
	_current_hp = _max_hp
	_emit_initial_state.call_deferred()


func _physics_process(delta: float) -> void:
	_update_aim()
	_update_dash(delta)
	_update_velocity(delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F1:
		take_damage(10.0)


func get_current_hp() -> float:
	return _current_hp


func get_max_hp() -> float:
	return _max_hp


func is_dead() -> bool:
	return _dead


func take_damage(amount: float) -> void:
	if amount <= 0.0 or _dead:
		return
	_current_hp = clampf(_current_hp - amount, 0.0, _max_hp)
	hp_changed.emit(_current_hp, _max_hp)
	if _current_hp > 0.0:
		return
	_dead = true
	set_physics_process(false)
	died.emit()


## Seconds of dash cooldown left; 0.0 means the dash is ready.
func get_dash_remaining() -> float:
	return _cooldown_left


func get_dash_total() -> float:
	return _dash_cooldown


func _read_tuning() -> void:
	_max_hp = float(Tuning.value("player", "max_hp", 100.0))
	_move_speed = float(Tuning.value("player", "move_speed", 5.5))
	_sprint_multiplier = float(Tuning.value("player", "sprint_multiplier", 1.6))
	_acceleration = float(Tuning.value("player", "acceleration", 40.0))
	_friction = float(Tuning.value("player", "friction", 30.0))
	_dash_speed = float(Tuning.value("player", "dash_speed", 16.0))
	_dash_time = float(Tuning.value("player", "dash_time", 0.16))
	_dash_cooldown = float(Tuning.value("player", "dash_cooldown", 1.0))
	_radius = float(Tuning.value("player", "radius", 0.45))
	_height = float(Tuning.value("player", "height", 1.8))
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _apply_geometry() -> void:
	# Root origin sits at the feet, so capsule and mesh are lifted by half the height.
	var capsule_height := maxf(_height, _radius * 2.0)

	var shape := _collision.shape as CapsuleShape3D
	if shape == null:
		shape = CapsuleShape3D.new()
		_collision.shape = shape
	shape.radius = _radius
	shape.height = capsule_height
	_collision.position = Vector3(0.0, _height * 0.5, 0.0)

	var capsule := _body_mesh.mesh as CapsuleMesh
	if capsule == null:
		capsule = CapsuleMesh.new()
		_body_mesh.mesh = capsule
	capsule.radius = _radius
	capsule.height = capsule_height
	_body_mesh.position = Vector3(0.0, _height * 0.5, 0.0)

	_facing.position = Vector3(0.0, _height * 0.6, 0.0)


func _emit_initial_state() -> void:
	hp_changed.emit(_current_hp, _max_hp)
	_reported_cooldown = _cooldown_left
	dash_state_changed.emit(_cooldown_left, _dash_cooldown)
	aim_point_changed.emit(_aim_point)


func _update_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	if absf(normal.y) < AIM_EPSILON:
		return

	var hit_time := (GROUND_Y - origin.y) / normal.y
	if hit_time < 0.0:
		return

	var point := origin + normal * hit_time
	point.y = GROUND_Y
	_aim_marker.global_position = Vector3(point.x, AIM_MARKER_Y, point.z)

	if _has_aim and point.distance_squared_to(_aim_point) < AIM_EPSILON:
		return
	_has_aim = true
	_aim_point = point
	aim_point_changed.emit(_aim_point)
	_face_aim()


func _face_aim() -> void:
	var flat := _aim_point - _facing.global_position
	flat.y = 0.0
	if flat.length_squared() < AIM_EPSILON:
		return
	_facing.look_at(_facing.global_position + flat, Vector3.UP)


func _update_dash(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_dash_left = maxf(_dash_left - delta, 0.0)

	if Input.is_action_just_pressed("dash") and _dash_left <= 0.0 and _cooldown_left <= 0.0:
		_dash_dir = _pick_dash_direction()
		_dash_left = _dash_time
		_cooldown_left = _dash_cooldown

	if _cooldown_left > 0.0:
		_reported_cooldown = _cooldown_left
		dash_state_changed.emit(_cooldown_left, _dash_cooldown)
	elif not is_zero_approx(_reported_cooldown):
		_reported_cooldown = 0.0
		dash_state_changed.emit(0.0, _dash_cooldown)


func _pick_dash_direction() -> Vector3:
	var input_dir := _read_move_input()
	if input_dir.length_squared() > AIM_EPSILON:
		return input_dir.normalized()

	var to_aim := _aim_point - global_position
	to_aim.y = 0.0
	if to_aim.length_squared() > AIM_EPSILON:
		return to_aim.normalized()

	return _last_move_dir


func _update_velocity(delta: float) -> void:
	if _dash_left > 0.0:
		velocity.x = _dash_dir.x * _dash_speed
		velocity.z = _dash_dir.z * _dash_speed
		return

	var input_dir := _read_move_input()
	if input_dir.length_squared() > AIM_EPSILON:
		_last_move_dir = input_dir.normalized()

	var speed := _move_speed
	if Input.is_action_pressed("sprint"):
		speed *= _sprint_multiplier

	var target := input_dir * speed
	var rate := _acceleration if input_dir.length_squared() > AIM_EPSILON else _friction
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)


func _read_move_input() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO

	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var camera_forward := -camera.global_basis.z
		camera_forward.y = 0.0
		if camera_forward.length_squared() > AIM_EPSILON:
			forward = camera_forward.normalized()

		var camera_right := camera.global_basis.x
		camera_right.y = 0.0
		if camera_right.length_squared() > AIM_EPSILON:
			right = camera_right.normalized()

	var direction := right * input.x - forward * input.y
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	return direction
