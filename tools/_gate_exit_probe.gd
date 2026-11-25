extends SceneTree

# P2 兼容检查：走到出口传送门 → Router 切换到地牢主场景。
# 用法：godot --path . --script res://tools/_gate_exit_probe.gd
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

var _m: Node
var _f := 0
var _t := 0.0


func _initialize() -> void:
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)
	current_scene = _m


func _process(d: float) -> bool:
	_f += 1
	_t += d
	if _f == 20:
		var player := _m.get_node_or_null("World/Player") as Node3D
		if player != null:
			player.position = Vector3(46.0, 0.05, 0.0)
			print("moved player to exit ", player.position)
	if _f % 60 == 0:
		var cs := current_scene
		print("t=%.1f current_scene=%s" % [_t, cs.scene_file_path if cs != null else "null"])
	if _t > 8.0:
		var cs := current_scene
		var path := cs.scene_file_path if cs != null else ""
		print("EXIT ", "OK" if path == "res://scenes/main.tscn" else "FAIL", " path=", path)
		return true
	return false