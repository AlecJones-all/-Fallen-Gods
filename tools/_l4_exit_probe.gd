extends SceneTree
## 验证第4关出口：玩家是否在 player 组、ExitGate 是否就位、踏入后是否触发换场。

var _frame := 0
var _scene: Node
var _player: Node3D


func _initialize() -> void:
	_scene = (load("res://scenes/levels/whitewash_chapel.tscn") as PackedScene).instantiate()
	get_root().add_child(_scene)
	_player = _scene.get_node_or_null("Player") as Node3D



func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 5:
		var gate := _scene.get_node_or_null("ExitGate")
		print("PROBE player_group=", _player.is_in_group(&"player"), " gate=", gate != null,
			" children=", _scene.get_child_count())
	if _frame == 10:
		_player.global_position = Vector3(15.6, 0.6, -16.5)
	if _frame == 40:
		var router: Node = get_root().get_node_or_null("Router")
		var payload: Dictionary = router.get("last_payload") if router != null else {}
		print("PROBE after_step payload=", payload, " transitioning=",
			router.get("is_transitioning") if router != null else "no-router")
		quit()
	return false
