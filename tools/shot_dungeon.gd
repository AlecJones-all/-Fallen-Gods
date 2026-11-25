extends SceneTree
# 地牢（main.tscn，程序化生成）实拍
const SHOTS := [ { "n": "13_地牢_出生.png", "advance": 0.0 }, { "n": "13_地牢_探索.png", "advance": 1.0 } ]
var _m: Node
var _f := 0
var _i := 0
func _initialize() -> void:
	_m = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_m)
	current_scene = _m
func _process(_d: float) -> bool:
	_f += 1
	if _i >= SHOTS.size(): return true
	if _f == 30 + 40 * _i:
		if _i == 1:
			Input.action_press("move_forward")
		return false
	if _f == 30 + 40 * _i + 30:
		Input.action_release("move_forward")
		var n := String(SHOTS[_i]["n"])
		get_root().get_texture().get_image().save_png("res://docs/" + n)
		print("saved ", n)
		_i += 1
	return false
