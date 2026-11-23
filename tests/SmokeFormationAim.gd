extends Node

## V1 回归：敌阵固定七列，远处视觉更小；手动方向必须决定远程弹体初始方向。

var battle: Node2D


func _ready() -> void:
	GameState.meta = GameState.default_meta()
	GameState.start_level(1)
	battle = load("res://battle/BattleScene.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.setup(1)
	battle.spawn_wave(0, 0)
	var cols_ok: bool = battle._cols == 7 and battle.mobs.all(func(m): return int(m.col) >= 0 and int(m.col) < 7)
	var far_scale: float = battle._mob_visual_scale(100.0)
	var near_scale: float = battle._mob_visual_scale(230.0)
	battle.balls.clear()
	battle._weapon_timers.clear()
	battle._set_aim_direction(Vector2.RIGHT)
	battle._update_weapons(0.01)
	var shot_ok: bool = not battle.balls.is_empty() and Vector2(battle.balls[0].vel).x > 0.0
	var ok: bool = cols_ok and far_scale < near_scale and near_scale <= 1.0 and shot_ok
	print("FORMATION_AIM ", "PASS" if ok else "FAIL", " cols=", battle._cols, " scales=", far_scale, "/", near_scale, " shot=", shot_ok)
	battle.set_combat_paused(true)
	get_tree().quit(0 if ok else 1)
