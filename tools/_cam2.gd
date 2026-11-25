extends SceneTree
var _m: Node
var _f := 0
func _initialize() -> void:
	_m = (load("res://scenes/levels/tithe_gate_graybox.tscn") as PackedScene).instantiate()
	get_root().add_child(_m)
func _process(_d: float) -> bool:
	_f += 1
	if _f == 2 or _f == 30:
		var rig: Node3D = _m.get_node_or_null("CameraRig") as Node3D
		var cam: Camera3D = rig.get_node_or_null("Camera3D") as Camera3D if rig != null else null
		if rig != null:
			print("F%d rig rot=%s pos=%s" % [_f, rig.rotation_degrees, rig.global_position])
		if cam != null:
			print("F%d cam local=%s size=%.1f proj=%d current=%s fov=%.1f" % [_f, cam.position, cam.size, cam.projection, cam.current, cam.fov])
	return _f > 32
