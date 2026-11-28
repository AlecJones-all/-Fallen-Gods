class_name CameraRig
extends Node3D

const PLAYER_GROUP: StringName = &"player"
const FALLBACK_ORTHO_SIZE := 12.0
const FALLBACK_FIT_ASPECT := 16.0 / 9.0
const FALLBACK_FIT_MAX := 1.5

## Per-level override so a single large room can widen the frame without
## touching the shared tuning values. 0 keeps the global ortho size.
@export var ortho_override: float = 0.0

@onready var _camera: Camera3D = $Camera3D

var _follow_speed: float = 10.0
var _target_height: float = 1.0
var _base_ortho_size: float = FALLBACK_ORTHO_SIZE
var _fit_aspect: float = FALLBACK_FIT_ASPECT
var _fit_max: float = FALLBACK_FIT_MAX
var _target: Node3D = null
var _snapped: bool = false

var _base_camera_position: Vector3 = Vector3.ZERO
var _shake_max: float = 0.45
var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_left: float = 0.0


func _ready() -> void:
	var yaw := deg_to_rad(float(Tuning.value("camera", "yaw_deg", 45.0)))
	var pitch := deg_to_rad(float(Tuning.value("camera", "pitch_deg", -55.0)))
	var distance := float(Tuning.value("camera", "distance", 24.0))
	_follow_speed = float(Tuning.value("camera", "follow_speed", 10.0))
	_target_height = float(Tuning.value("camera", "target_height", 1.0))
	_shake_max = float(Tuning.value("fx", "shake_max", 0.45))

	rotation = Vector3(pitch, yaw, 0.0)
	_base_camera_position = Vector3(0.0, 0.0, distance)
	_camera.position = _base_camera_position
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_base_ortho_size = maxf(float(Tuning.value("camera", "ortho_size", FALLBACK_ORTHO_SIZE)), 0.1)
	if ortho_override > 0.0:
		_base_ortho_size = ortho_override
	_fit_aspect = maxf(float(Tuning.value("camera", "fit_aspect", FALLBACK_FIT_ASPECT)), 0.1)
	_fit_max = maxf(float(Tuning.value("camera", "fit_max", FALLBACK_FIT_MAX)), 1.0)
	_update_projection()
	get_viewport().size_changed.connect(_update_projection)
	_camera.near = 0.1
	_camera.far = 200.0
	_camera.current = true

	global_position = Vector3(0.0, _target_height, 0.0)


## Ortho size is the vertical extent. Narrower-than-design windows zoom out so
## the horizontal view never drops below the 16:9 design width; wider ones keep
## the same vertical extent and simply show more of the room sideways.
static func fitted_ortho_size(base_size: float, aspect: float, design_aspect: float,
		max_fit := FALLBACK_FIT_MAX) -> float:
	if base_size <= 0.0 or aspect <= 0.0 or design_aspect <= 0.0:
		return base_size
	var fit := clampf(design_aspect / aspect, 1.0, maxf(max_fit, 1.0))
	return base_size * fit


func _update_projection() -> void:
	if _camera == null:
		return
	var view := get_viewport().get_visible_rect().size
	if view.y <= 0.0:
		_camera.size = _base_ortho_size
		return
	_camera.size = fitted_ortho_size(_base_ortho_size, view.x / view.y, _fit_aspect, _fit_max)


## Jumps the rig to the player, e.g. after a floor transition repositions them.
func snap_to_target() -> void:
	_shake_strength = 0.0
	_shake_duration = 0.0
	_shake_left = 0.0
	_camera.position = _base_camera_position
	_target = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node3D
	if _target == null:
		return
	global_position = _target.global_position + Vector3(0.0, _target_height, 0.0)
	_snapped = true


func add_shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	strength = clampf(strength, 0.0, _shake_max)
	if _shake_left > 0.0 and strength <= _shake_strength:
		return
	_shake_strength = strength
	_shake_duration = duration
	_shake_left = duration


func _process(delta: float) -> void:
	_update_shake(delta / maxf(Engine.time_scale, 0.01))


func _update_shake(delta: float) -> void:
	_shake_left = maxf(_shake_left - delta, 0.0)
	if _shake_left <= 0.0:
		_shake_strength = 0.0
		_shake_duration = 0.0
		_shake_left = 0.0
		if _camera.position != _base_camera_position:
			_camera.position = _base_camera_position
		return

	var decay := _shake_left / _shake_duration if _shake_duration > 0.0 else 0.0
	var amplitude := _shake_strength * decay
	_camera.position = _base_camera_position + Vector3(
		randf_range(-amplitude, amplitude), randf_range(-amplitude, amplitude), 0.0)


func _physics_process(delta: float) -> void:
	# The player may be instanced after this rig; keep polling instead of failing.
	if not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node3D
		if _target == null:
			return

	var desired := _target.global_position + Vector3(0.0, _target_height, 0.0)
	if not _snapped:
		_snapped = true
		global_position = desired
		return

	global_position = global_position.lerp(desired, 1.0 - exp(-_follow_speed * delta))
