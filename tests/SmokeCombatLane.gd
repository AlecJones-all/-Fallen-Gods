extends Node

## A2.1 回归：第1关的纵深道路必须是实际战斗边界，
## 玩家出生点和全部首波怪物都不能落在两侧墓地环境中。

var battle: Node2D


func _ready() -> void:
	GameState.meta = GameState.default_meta()
	GameState.start_level(1)
	battle = load("res://battle/BattleScene.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.setup(1)
	battle.spawn_wave(0, 0)
	var lane = battle._combat_lane
	var mobs_in_lane := true
	var mob_positions: Array = []
	for mob in battle.mobs:
		var in_lane: bool = lane.contains(mob.pos, float(mob.half))
		mobs_in_lane = mobs_in_lane and in_lane
		mob_positions.append({"pos": mob.pos, "half": mob.half, "in_lane": in_lane})
	battle.mobs.clear()
	battle.balls = [{
		"pos": Vector2(75, 200), "vel": Vector2(-1000, 0), "radius": 6.0,
		"bounces": 3, "hit_ids": {}, "trail": []
	}]
	battle._update_balls(0.1)
	var ball: Dictionary = battle.balls[0]
	var ball_in_lane: bool = lane.contains(ball.pos, float(ball.radius)) and ball.vel.x > 0.0
	var ok: bool = lane != null \
		and lane.contains(battle.player_pos, float(Data.tuning.player.radius_px)) \
		and lane.contains(Vector2(320, 64)) \
		and not lane.contains(Vector2(90, 64)) \
		and not lane.contains(Vector2(30, 320)) \
		and mobs_in_lane \
		and ball_in_lane
	print("COMBAT_LANE ", "PASS" if ok else "FAIL", " bounds=", lane.bounds() if lane != null else "none", " player_ok=", lane.contains(battle.player_pos, float(Data.tuning.player.radius_px)) if lane != null else false, " top_ok=", lane.contains(Vector2(320, 64)) if lane != null else false, " left_rejected=", not lane.contains(Vector2(90, 64)) if lane != null else false, " bottom_rejected=", not lane.contains(Vector2(30, 320)) if lane != null else false, " mobs_ok=", mobs_in_lane, " mob_positions=", mob_positions, " ball_ok=", ball_in_lane)
	battle.set_combat_paused(true)
	get_tree().quit(0 if ok else 1)
