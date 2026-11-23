extends Node

## V1 输入回归：桌面端鼠标不移动玩家；左键只确定自动射击方向。

var battle: Node2D


func _ready() -> void:
	GameState.meta = GameState.default_meta()
	GameState.start_level(1)
	battle = load("res://battle/BattleScene.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.setup(1)
	var before: Vector2 = battle.player_pos
	var initial_target := before + Vector2(80, 20)
	var target := before + Vector2(-40, -88)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.position = target
	drag.relative = Vector2(-80, -48)
	var fire_press := InputEventMouseButton.new()
	fire_press.button_index = MOUSE_BUTTON_LEFT
	fire_press.pressed = true
	fire_press.position = initial_target
	battle._input(fire_press)
	battle._input(drag)
	var fire_release := InputEventMouseButton.new()
	fire_release.button_index = MOUSE_BUTTON_LEFT
	fire_release.pressed = false
	fire_release.position = target
	battle._input(fire_release)
	battle.balls.clear()
	battle._weapon_timers.clear()
	battle._update_weapons(0.01)
	var aim_ok: bool = battle._aim_direction.dot((target - before).normalized()) > 0.99
	var shot_ok: bool = not battle.balls.is_empty() and Vector2(battle.balls[0].vel).dot(battle._aim_direction) > 0.0
	var aimed_before_pause: Vector2 = battle._aim_direction
	battle.set_combat_paused(true)
	var ignored_click := InputEventMouseButton.new()
	ignored_click.button_index = MOUSE_BUTTON_LEFT
	ignored_click.pressed = true
	ignored_click.position = before + Vector2(-80, 40)
	battle._input(ignored_click)
	var pause_ok: bool = battle._aim_direction == aimed_before_pause
	var ok: bool = battle.player_pos == before and aim_ok and shot_ok and pause_ok
	print("MOUSE_AIM_AUTO_FIRE ", "PASS" if ok else "FAIL", " player=", battle.player_pos, " aim=", battle._aim_direction, " shot=", shot_ok, " pause=", pause_ok)
	battle.set_combat_paused(true)
	get_tree().quit(0 if ok else 1)
