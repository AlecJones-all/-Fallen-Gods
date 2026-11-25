extends SceneTree
# 油画风格静帧
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"
const SHOTS := [{ "name": "06_油画_出生点.png", "x": 7.0 }, { "name": "06_油画_过卡口.png", "x": 14.5 }]
var _f := 0
var _stage := 0
var _m: Node
var _rig: Node3D
var _cam: Camera3D
var _player: Node3D
var _world: Node3D

func _initialize() -> void:
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)
	_rig = _m.get_node_or_null("CameraRig") as Node3D
	if _rig != null:
		_cam = _rig.get_node_or_null("Camera3D") as Camera3D
		_rig.set_physics_process(false)
	_world = _m.get_node_or_null("World") as Node3D
	_player = _m.get_node_or_null("World/Player") as Node3D
	var hud := _m.get_node_or_null("HUD")
	if hud != null:
		hud.set("visible", false)

func _process(_d: float) -> bool:
	_f += 1
	if _stage >= SHOTS.size():
		return true
	if _f == 5:
		var x := float(SHOTS[_stage]["x"])
		if _player != null:
			_player.position = Vector3(x, 0.05, 0.0)
		if _rig != null and _world != null:
			_rig.rotation_degrees = Vector3(-55.0, 45.0, 0.0)
			_rig.global_position = _world.transform * Vector3(x, 1.0, 0.0)
		if _cam != null:
			_cam.size = 12.0
		return false
	if _f == 14:
		get_root().get_texture().get_image().save_png("res://docs/" + String(SHOTS[_stage]["name"]))
		print("saved ", SHOTS[_stage]["name"])
		_stage += 1
		_f = 0
		return _stage >= SHOTS.size()
	return false
