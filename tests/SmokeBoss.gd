extends Node

const LEVELS := [5, 10, 13, 14, 15]

var main: Control
var frames := 0
var stage := 0
var in_level := false

func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	_start_stage()

func _start_stage() -> void:
	var lvl: int = LEVELS[stage]
	GameState.meta = GameState.default_meta()
	GameState.meta.unlocked_level = lvl
	main.menu_panel.set_mode(false)
	in_level = true
	main.menu_panel.start_requested.emit()

func _process(_delta: float) -> void:
	frames += 1
	if frames > 15000:
		print("BOSS FAIL: timeout stage=", stage, " lvl=", GameState.run.get("level"))
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
		if in_level:
			in_level = false
			var lvl: int = LEVELS[stage]
			var expect: int = mini(lvl + 1, 15)
			if GameState.meta.unlocked_level != expect:
				print("BOSS FAIL: 关", lvl, " 解锁错误 ", GameState.meta.unlocked_level)
				get_tree().quit(1)
				return
			print("关", lvl, " PASS realm=", GameState.meta.realm, " shards=", GameState.meta.shards)
			stage += 1
			if stage >= LEVELS.size():
				print("BOSS PASS: 五场Boss关全部贯通")
				get_tree().quit(0)
				return
			_start_stage()
		return
	var battle: Node2D = main.battle
	if battle.visible and not battle.combat_paused:
		GameState.run.hp = 1e9
		for m in battle.mobs:
			m.hp = 0.0
		var boss = battle.boss
		if boss != null and is_instance_valid(boss):
			if boss.boss_id == "chaos":
				for s in boss.seals:
					if s.alive:
						boss.melee_hit(s.pos, 1.0, 1e9, null, 0.0)
			elif boss.boss_id != "inner_demon":
				boss.take_damage(1e9)