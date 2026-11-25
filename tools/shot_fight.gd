extends SceneTree
# 战斗截图：把玩家放到指定点触发遭遇，等敌人靠近后拍一张
# 用法: godot --path . --resolution 1600x900 --script res://tools/shot_fight.gd -- 14.0 gate.png
var _f := 0
var _x := 14.0
var _out := "04_卡口1v3.png"

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1: _x = float(a[0])
	if a.size() >= 2: _out = a[1]
	var m: Node = (load("res://scenes/levels/tithe_gate_graybox.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	_m = m
var _m: Node

func _process(_d: float) -> bool:
	_f += 1
	var p: Node3D = _m.get_node_or_null("World/Player")
	if _f == 3 and p != null:
		p.position = Vector3(_x, 0.05, 0.0)
		var rig: Node3D = _m.get_node_or_null("CameraRig")
		if rig != null:
			rig.set_physics_process(false)
			rig.global_position = (_m.get_node("World") as Node3D).transform * Vector3(_x, 1.0, 0.0)
	if _f == 70:
		get_root().get_texture().get_image().save_png("res://docs/" + _out)
		print("saved ", _out, " enemies=", get_nodes_in_group("enemies").size())
		return true
	return false
