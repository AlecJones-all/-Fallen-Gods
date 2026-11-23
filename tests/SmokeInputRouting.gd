extends Control

## 回归：BattleScene 在全屏 Control 容器下仍按自身局部逻辑坐标处理左键，且暂停时拒绝输入。

var battle: Node2D


func _ready() -> void:
	GameState.meta = GameState.default_meta()
	GameState.start_level(1)
	battle = load("res://battle/BattleScene.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.setup(1)
	var before: Vector2 = battle.player_pos
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var desired_target := before + Vector2(-90, -45)
	click.position = desired_target
	battle._input(click)
	await get_tree().process_frame
	var expected := Vector2(-90, -45).normalized()
	var reached_battle: bool = battle._aim_direction.dot(expected) > 0.99
	var paused_aim: Vector2 = battle._aim_direction
	battle.set_combat_paused(true)
	var blocked := InputEventMouseButton.new()
	blocked.button_index = MOUSE_BUTTON_LEFT
	blocked.pressed = true
	blocked.position = before + Vector2(100, 0)
	battle._input(blocked)
	await get_tree().process_frame
	var pause_guard_ok: bool = battle._aim_direction.is_equal_approx(paused_aim)
	var ok: bool = reached_battle and battle.player_pos == before and pause_guard_ok
	print("INPUT_ROUTING ", "PASS" if ok else "FAIL", " reached=", reached_battle, " paused=", pause_guard_ok, " aim=", battle._aim_direction)
	get_tree().quit(0 if ok else 1)
