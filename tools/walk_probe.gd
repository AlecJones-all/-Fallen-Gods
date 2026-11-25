extends SceneTree

# 走位探针：按住 W 沿路前进，检查是否卡在卡口或途中。
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"
const GOAL := 44.0
const LIMIT_SEC := 20.0

var _f := 0
var _t := 0.0
var _player: Node3D
var _max_x := 0.0
var _last_x := 0.0
var _stuck := 0.0
var _done := false

func _initialize() -> void:
	var m: Node = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(m)
	_player = m.get_node_or_null("World/Player") as Node3D

func _physics_process(delta: float) -> bool:
	_f += 1
	if _f < 6 or _done:
		return _done
	if _f == 6:
		Input.action_press("move_forward")
	if _player == null:
		print("WALK FAIL: no player")
		return true
	_t += delta
	var x := _player.position.x
	if x > _max_x:
		_max_x = x
	if absf(x - _last_x) < 0.002:
		_stuck += delta
	else:
		_stuck = 0.0
	_last_x = x
	if x >= GOAL:
		Input.action_release("move_forward")
		print("WALK OK  到达 x=%.1f，用时 %.1fs" % [x, _t])
		_done = true
		return true
	if _stuck > 3.0:
		Input.action_release("move_forward")
		print("WALK FAIL 卡在 x=%.2f（%.1fs 没动）" % [x, _stuck])
		_done = true
		return true
	if _t > LIMIT_SEC:
		Input.action_release("move_forward")
		print("WALK FAIL 超时，最远 x=%.1f" % _max_x)
		_done = true
		return true
	return false
