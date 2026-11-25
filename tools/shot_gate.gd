extends SceneTree

# 灰盒截图：俯视平面 + 出生点 + 过卡口 + 收储院
# 用法: godot --path . --resolution 1600x900 --script res://tools/shot_gate.gd
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"
const WORLD_YAW := 135.0

const SHOTS := [
	{ "name": "02_灰盒平面.png", "x": 24.0, "size": 50.0, "hud": false, "plan": true },
	{ "name": "02_灰盒出生点.png", "x": 7.0, "size": 12.0, "hud": true, "plan": false },
	{ "name": "02_灰盒过卡口.png", "x": 14.5, "size": 12.0, "hud": true, "plan": false },
	{ "name": "02_灰盒院子.png", "x": 26.0, "size": 12.0, "hud": true, "plan": false },
]

var _f := 0
var _stage := 0
var _rig: Node3D
var _cam: Camera3D
var _player: Node3D
var _world: Node3D
var _hud: Node


func _initialize() -> void:
	var m: Node = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(m)
	_rig = m.get_node_or_null("CameraRig") as Node3D
	if _rig != null:
		_cam = _rig.get_node_or_null("Camera3D") as Camera3D
		_rig.set_physics_process(false)
	_world = m.get_node_or_null("World") as Node3D
	_player = m.get_node_or_null("World/Player") as Node3D
	_hud = m.get_node_or_null("HUD")


func _process(_d: float) -> bool:
	_f += 1
	if _stage >= SHOTS.size():
		return true
	if _f == 4:
		_apply(SHOTS[_stage])
		return false
	if _f == 10:
		get_root().get_texture().get_image().save_png("res://docs/" + String(SHOTS[_stage]["name"]))
		print("saved ", SHOTS[_stage]["name"])
		_stage += 1
		_f = 0
		return _stage >= SHOTS.size()
	return false


func _apply(shot: Dictionary) -> void:
	var x := float(shot["x"])
	var plan := bool(shot["plan"])
	if _world != null:
		_world.rotation.y = 0.0 if plan else deg_to_rad(WORLD_YAW)
	if _player != null:
		_player.position = Vector3(x, 0.05, 0.0)
	if _rig != null:
		if plan:
			_rig.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			_rig.global_position = Vector3(x, 0.0, 0.0)
		else:
			_rig.rotation_degrees = Vector3(-55.0, 45.0, 0.0)
			if _world != null:
				_rig.global_position = _world.transform * Vector3(x, 1.0, 0.0)
	if _cam != null:
		_cam.size = float(shot["size"])
	if _hud != null:
		_hud.set("visible", bool(shot["hud"]))
