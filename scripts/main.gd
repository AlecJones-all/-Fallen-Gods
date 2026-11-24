extends Node3D


func _ready() -> void:
	$Camera3D.look_at(Vector3.ZERO)