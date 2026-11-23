extends Node

## A1 回归：Demo 入口必须无视已解锁第 6 关，启动第 1 关，且不覆盖永久进度。

var main: Control


func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	GameState.meta = GameState.default_meta()
	GameState.meta.unlocked_level = 6
	main.menu_panel.demo_requested.emit()
	await get_tree().process_frame
	var ok: bool = int(GameState.run.get("level", 0)) == 1 \
		and GameState.meta.unlocked_level == 6 \
		and main.current_level == 1 \
		and main.battle.level_id == 1
	print("DEMO_ENTRY ", "PASS" if ok else "FAIL", " run=", GameState.run.get("level"), " unlocked=", GameState.meta.unlocked_level, " current=", main.current_level, " battle=", main.battle.level_id)
	main._run_token += 1
	get_tree().quit(0 if ok else 1)
