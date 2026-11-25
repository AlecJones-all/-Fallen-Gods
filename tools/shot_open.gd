extends SceneTree
# 出生点开墙后的取景：用场景自己的机位，不改旋转。
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"
const SHOTS := [
	{ "n": "10_开场_拆墙后.png", "x": 7.0 },
	{ "n": "10_开场_贴边.png", "x": 3.0 },
]
var _m: Node
var _rig: Node3D
var _player: Node3D
var _world: Node3D
var _f := 0
var _i := 0
func _initialize() -> void:
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)
	_rig = _m.get_node_or_null("CameraRig") as Node3D
	_player = _m.get_node_or_null("World/Player") as Node3D
	_world = _m.get_node_or_null("World") as Node3D
	var hud := _m.get_node_or_null("HUD")
	if hud != null: hud.set("visible", false)
func _process(_d: float) -> bool:
	_f += 1
	if _i >= SHOTS.size(): return true
	if _f == 8:
		var x := float(SHOTS[_i]["x"])
		if _player != null: _player.position = Vector3(x, 0.05, 0.0)
		if _rig != null and _world != null:
			_rig.global_position = _world.transform * Vector3(x, 1.0, 0.0)
		return false
	if _f == 70:
		get_root().get_texture().get_image().save_png("res://docs/" + String(SHOTS[_i]["n"]))
		print("saved ", SHOTS[_i]["n"])
		_i += 1
		_f = 6
	return false
