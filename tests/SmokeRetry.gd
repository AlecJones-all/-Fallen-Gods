extends Node

var main: Control
var frames := 0
var died_once := false
var retried := false

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	GameState.meta = GameState.default_meta()
	main.menu_panel.set_mode(false)
	main.menu_panel.start_requested.emit()

func _process(_delta: float) -> void:
	frames += 1
	if frames > 9000:
		print("RETRY FAIL: timeout died=", died_once, " retried=", retried, " unlocked=", GameState.meta.unlocked_level)
		get_tree().quit(1)
		return
	if main.dialogue.is_playing():
		main.dialogue.skip()
		return
	if main.build_panel.visible:
		main.build_panel.chosen.emit(Data.build_pool[0])
		main.build_panel.hide()
		return
	if main.altar_panel.visible:
		main.altar_panel.skipped.emit()
		main.altar_panel.hide()
		return
	if main.shop_panel.visible:
		main.shop_panel.closed.emit()
		main.shop_panel.hide()
		return
	if main.menu_panel.visible:
		if not died_once:
			pass
		elif not retried:
			if GameState.run.level != 1:
				print("RETRY FAIL: 重试关号错误 ", GameState.run.level)
				get_tree().quit(1)
				return
			if GameState.run.buffs.power != 0:
				print("RETRY FAIL: buff 未重置")
				get_tree().quit(1)
				return
			retried = true
			main.menu_panel.start_requested.emit()
		elif GameState.meta.unlocked_level >= 2:
			print("RETRY PASS: 死亡→整关重开→通关, unlocked=", GameState.meta.unlocked_level)
			get_tree().quit(0)
		return
	var battle: Node2D = main.battle
	if battle.visible and not battle.combat_paused:
		if not died_once and battle.mobs.size() > 0:
			died_once = true
			GameState.damage_player(99999.0, 0.0)
			return
		for m in battle.mobs:
			m.hp = 0.0