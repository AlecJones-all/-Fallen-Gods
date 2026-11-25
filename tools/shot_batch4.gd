extends SceneTree

# 批 4 验收图：用场景自己的机位（−50°），不再手动改旋转。
# 用法：godot --path . --resolution 1600x900 --script res://tools/shot_batch4.gd
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

const SHOTS := [
	{ "name": "09_开场_拱门外.png", "x": 7.0, "z": 0.0, "hud": true },
	{ "name": "09_卡口_拱下.png", "x": 10.6, "z": 0.0, "hud": false },
	{ "name": "09_院子_吊笼.png", "x": 25.6, "z": 0.0, "hud": false },
	{ "name": "09_远景_塌口.png", "x": 34.0, "z": -1.5, "hud": false },
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


func _process(_d: float) -> bool:
	_f += 1
	if _i >= SHOTS.size():
		return true
	var shot: Dictionary = SHOTS[_i]
	var hud := _m.get_node_or_null("HUD")
	if hud != null:
		hud.set("visible", bool(shot["hud"]))
	if _f == 6:
		var at := Vector3(float(shot["x"]), 0.05, float(shot["z"]))
		if _player != null:
			_player.position = at
		if _rig != null and _world != null:
			_rig.global_position = _world.transform * Vector3(at.x, 1.0, at.z)
		return false
	if _f == 18:
		get_root().get_texture().get_image().save_png("res://docs/" + String(shot["name"]))
		print("saved ", shot["name"])
		_i += 1
		_f = 4
		return false
	return false
