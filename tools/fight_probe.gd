extends SceneTree

# 卡口压力测试：触发遭遇后按住 S 退到门后，看 4m 洞口能同时放进来几个。
# 用法: godot --headless --path . --fixed-fps 60 --script res://tools/fight_probe.gd -- 13.5 [retreat]
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"
const ATTACK_RANGE := 1.9
const RETREAT_SEC := 2.0

var _stand_x := 13.5
var _retreat := true
var _f := 0
var _t := 0.0
var _player: Node3D
var _peak := 0
var _sample := 0.0
var _spawned := 0
var _died_at := -1.0
var _trigger_at := -1.0
var _retreat_end := -1.0
var _min_x := 999.0
var _passed := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_stand_x = float(args[0])
	if args.size() >= 2:
		_retreat = args[1] == "retreat"
	var m: Node = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(m)
	_player = m.get_node_or_null("World/Player") as Node3D


func _process(delta: float) -> bool:
	_f += 1
	if _f == 3:
		# 场景 _ready 会把玩家放回出生点，必须等它跑完再挪
		if _player != null:
			_player.position = Vector3(_stand_x, 0.05, 0.0)
		return false
	if _f < 5:
		return false

	_t += delta
	var enemies := get_nodes_in_group(&"enemies")

	if _spawned == 0 and enemies.size() > 0:
		_spawned = enemies.size()
		_trigger_at = _t
		print("SPAWN %d 名，玩家在 x=%.1f" % [_spawned, _player.position.x])

	if _retreat and _trigger_at > 0.0:
		if _t < _trigger_at + 0.4:
			pass
		elif _t < _trigger_at + 0.4 + RETREAT_SEC:
			Input.action_press(&"move_back")
		elif _retreat_end < 0.0:
			Input.action_release(&"move_back")
			_retreat_end = _t
			print("退到 x=%.1f" % _player.position.x)

	if _player == null:
		return true
	var px := _player.position.x
	_min_x = minf(_min_x, px)

	_sample += delta
	if _sample >= 0.25:
		_sample = 0.0
		var near := 0
		for e: Node3D in enemies:
			if e.global_position.distance_to(_player.global_position) <= ATTACK_RANGE:
				near += 1
		_peak = maxi(_peak, near)
		var through := 0
		for e: Node3D in enemies:
			var local_x := (_player.get_parent() as Node3D).to_local(e.global_position).x
			if local_x < 11.8:
				through += 1
		_passed = maxi(_passed, through)

	if _died_at < 0.0 and bool(_player.call(&"is_dead")):
		_died_at = _t
		print("DIED at %.1fs, x=%.1f" % [_died_at, _player.position.x])

	if _t >= 14.0:
		var hp := 0.0
		if _player.has_method(&"get_current_hp"):
			hp = float(_player.call(&"get_current_hp"))
		print("RESULT retreat=%s spawned=%d 最远退到x=%.1f 同时贴身=%d 穿门洞最多=%d hp=%.0f died_at=%.1f" % [
			str(_retreat), _spawned, _min_x, _peak, _passed, hp, _died_at])
		return true
	return false
