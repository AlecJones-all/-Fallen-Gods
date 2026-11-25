extends SceneTree

# 交互探针：站到每个交互点旁，确认 (1) Area 检测到玩家 (2) 按 E 能弹出文本面板。
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"
const SPOTS := [
	{ "id": "ledger", "at": Vector3(13.4, 0.05, -1.6) },
	{ "id": "scale", "at": Vector3(8.0, 0.05, -2.2) },
	{ "id": "cage", "at": Vector3(29.5, 0.05, -1.2) },
]

var _f := 0
var _idx := 0
var _m: Node
var _player: Node3D
var _wait := 0
var _ok := 0

func _initialize() -> void:
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)

func _process(_d: float) -> bool:
	_f += 1
	if _m == null:
		return false
	if _player == null:
		_player = _m.get_node_or_null("World/Player") as Node3D
	if _f < 4:
		return false
	if _idx >= SPOTS.size():
		print("INTERACT %s  %d/%d" % ["OK" if _ok == SPOTS.size() else "FAIL", _ok, SPOTS.size()])
		return true

	var spot: Dictionary = SPOTS[_idx]
	var area: Area3D = _m.get_node_or_null("World/Interactables/Interact_%s" % spot["id"]) as Area3D
	if area == null:
		print("INTERACT FAIL 找不到 %s" % spot["id"])
		return true

	if _wait == 0:
		_player.position = spot["at"]
		_wait = 1
		return false

	# 等两帧让 Area 完成重叠检测
	if _wait < 8:
		_wait += 1
		return false

	var near := area.get_overlapping_bodies().size() > 0
	var mark: Label3D = area.get_node_or_null("Mark") as Label3D
	var panel: Control = area.get_node_or_null("ReadLayer/ReadPanel") as Control
	if _wait == 8:
		print("  %s overlap=%s mark=%s" % [spot["id"], near, mark.visible if mark else "?"])
		# 模拟按 E
		var ev := InputEventKey.new()
		ev.keycode = KEY_E
		ev.pressed = true
		area.call("_input", ev)
		_wait = 9
		return false

	var shown := panel != null and panel.visible
	print("  %s 读文本=%s" % [spot["id"], shown])
	if near and shown:
		_ok += 1
	area.call("_stop_reading")
	_idx += 1
	_wait = 0
	_f = 3
	return false
