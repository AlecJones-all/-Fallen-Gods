extends Node3D

const PLAYER_GROUP: StringName = &"player"

@onready var _camera: Camera3D = $Camera3D

var _follow_speed: float = 10.0
var _target_height: float = 1.0
var _target: Node3D = null
var _snapped: bool = false


func _ready() -> void:
	var yaw := deg_to_rad(float(Tuning.value("camera", "yaw_deg", 45.0)))
	var pitch := deg_to_rad(float(Tuning.value("camera", "pitch_deg", -55.0)))
	var distance := float(Tuning.value("camera", "distance", 24.0))
	_follow_speed = float(Tuning.value("camera", "follow_speed", 10.0))
	_target_height = float(Tuning.value("camera", "target_height", 1.0))

	rotation = Vector3(pitch, yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = float(Tuning.value("camera", "ortho_size", 12.0))
	_camera.near = 0.1
	_camera.far = 200.0
	_camera.current = true

	global_position = Vector3(0.0, _target_height, 0.0)


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
