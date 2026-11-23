extends Node

var main: Control
var frames := 0

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	GameState.meta = GameState.default_meta()
	main.menu_panel.set_mode(false)
	main.menu_panel.start_requested.emit()

func _process(_delta: float) -> void:
	frames += 1
	if frames % 600 == 0:
		print("frame=", frames, " lvl=", GameState.run.get("level"), " dialogue=", main.dialogue.is_playing(), " build=", main.build_panel.visible, " altar=", main.altar_panel.visible, " shop=", main.shop_panel.visible, " menu=", main.menu_panel.visible, " paused=", main.battle.combat_paused, " mobs=", main.battle.mobs.size(), " wave_active=", main.battle._wave_active)
	if frames > 6000:
		print("SMOKE FAIL: timeout level=", GameState.run.get("level"), " unlocked=", GameState.meta.unlocked_level)
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
	if main.menu_panel.visible and GameState.meta.unlocked_level >= 2:
		print("SMOKE PASS: unlocked=", GameState.meta.unlocked_level, " realm=", GameState.meta.realm, " weapons=", GameState.meta.weapons, " save=", SaveManager.has_save())
		get_tree().quit(0)
		return
	var battle: Node2D = main.battle
	if battle.visible and not battle.combat_paused:
		for m in battle.mobs:
			m.hp = 0.0