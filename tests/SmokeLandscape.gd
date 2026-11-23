extends Node

## 横屏纵深底座回归：验证 640×360 战场在横屏中央保留纵深道路，
## 且第 1 关优先加载原创的横屏深坑道路背景。

var battle: Node2D


func _ready() -> void:
	GameState.start_level(1)
	battle = load("res://battle/BattleScene.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.setup(1)
	var has_depth_road: bool = battle._bg_node != null \
		and battle._bg_node.texture != null \
		and battle._bg_node.texture.resource_path.ends_with("level_01_graveyard_road_landscape.png")
	var ok: bool = battle._view_size == Vector2(640, 360) \
		and battle._field.position == Vector2(70, 64) \
		and battle._field.size == Vector2(500, 272) \
		and battle.player_pos == Vector2(320, 316) \
		and battle.get("_background_draw_suppressed") == true \
		and has_depth_road
	print("DEPTH_ROAD ", "PASS" if ok else "FAIL", " view=", battle._view_size, " field=", battle._field, " player=", battle.player_pos, " texture=", battle._bg_node.texture.resource_path if battle._bg_node != null and battle._bg_node.texture != null else "none")
	get_tree().quit(0 if ok else 1)
