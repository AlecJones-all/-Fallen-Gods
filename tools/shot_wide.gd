extends SceneTree
# 2:1 宽屏取景（对齐用户截图的比例），用场景自己的机位
const SHOTS := [ { "n": "12_宽屏_院子.png", "x": 33.0 }, { "n": "12_宽屏_卡口.png", "x": 10.0 },
	{ "n": "14_税亭内装.png", "x": 15.5 },
	{ "n": "15_院子尾段.png", "x": 44.0 } ]
var _m: Node
var _rig: Node3D
var _player: Node3D
var _world: Node3D
var _f := 0
var _i := 0
func _initialize() -> void:
	_m = (load("res://scenes/levels/tithe_gate_graybox.tscn") as PackedScene).instantiate()
	get_root().add_child(_m)
	_rig = _m.get_node_or_null("CameraRig") as Node3D
	_player = _m.get_node_or_null("World/Player") as Node3D
	_world = _m.get_node_or_null("World") as Node3D
func _process(_d: float) -> bool:
	_f += 1
	if _i >= SHOTS.size(): return true
	if _f == 8 + 50 * _i:
		var x := float(SHOTS[_i]["x"])
		if _player != null: _player.position = Vector3(x, 0.05, 0.0)
		if _rig != null and _world != null:
			_rig.global_position = _world.transform * Vector3(x, 1.0, 0.0)
		return false
	if _f == 8 + 50 * _i + 44:
		get_root().get_texture().get_image().save_png("res://docs/" + String(SHOTS[_i]["n"]))
		print("saved ", SHOTS[_i]["n"])
		_i += 1
	return false
