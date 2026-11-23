extends Control

const BATTLE := preload("res://battle/BattleScene.tscn")
const HUD := preload("res://ui/panels/Hud.tscn")
const DIALOGUE := preload("res://ui/dialogue/DialogueLayer.tscn")
const BUILD_PANEL := preload("res://ui/panels/BuildChoicePanel.tscn")
const ALTAR_PANEL := preload("res://ui/panels/AltarPanel.tscn")
const SHOP_PANEL := preload("res://ui/panels/ShopPanel.tscn")
const MENU_PANEL := preload("res://ui/panels/MainMenuPanel.tscn")
const TransitionLayer := preload("res://scenes/TransitionLayer.gd")

var battle: Node2D
var hud: CanvasLayer
var dialogue: CanvasLayer
var build_panel: Control
var altar_panel: Control
var shop_panel: Control
var menu_panel: Control
var transition: TransitionLayer

var current_level := 1
var retry_mode := false
var story: Dictionary = {}
var _run_token := 0

signal _altar_resolved

func _ready() -> void:
	SaveManager.load_game()
	battle = BATTLE.instantiate()
	add_child(battle)
	battle.visible = false
	battle.set_combat_paused(true)
	hud = HUD.instantiate()
	add_child(hud)
	hud.visible = false
	dialogue = DIALOGUE.instantiate()
	add_child(dialogue)
	build_panel = BUILD_PANEL.instantiate()
	add_child(build_panel)
	altar_panel = ALTAR_PANEL.instantiate()
	add_child(altar_panel)
	shop_panel = SHOP_PANEL.instantiate()
	add_child(shop_panel)
	menu_panel = MENU_PANEL.instantiate()
	add_child(menu_panel)

	EventBus.player_died.connect(_on_player_died)
	EventBus.mob_died.connect(_on_mob_died)
	EventBus.corruption_tier_changed.connect(_on_tier_changed)
	menu_panel.start_requested.connect(_on_start_requested)
	menu_panel.demo_requested.connect(_on_demo_requested)
	altar_panel.chosen.connect(func(_k: String, _s: String) -> void: _altar_resolved.emit())
	altar_panel.skipped.connect(func() -> void: _altar_resolved.emit())
	menu_panel.set_mode(false)
	menu_panel.visible = true
	transition = TransitionLayer.new()
	add_child(transition)

func _on_start_requested() -> void:
	menu_panel.visible = false
	transition.fade_in(0.3)
	var level_id: int = current_level if retry_mode else GameState.meta.unlocked_level
	retry_mode = false
	_run_level(level_id)


func _on_demo_requested() -> void:
	menu_panel.visible = false
	transition.fade_in(0.3)
	retry_mode = false
	_run_level(1)

func _on_player_died() -> void:
	_run_token += 1
	battle.set_combat_paused(true)
	retry_mode = true
	menu_panel.set_mode(true)
	menu_panel.visible = true
	transition.fade_out_in(0.18, 0.06, 0.3)

func _on_mob_died(kind: String, _pos: Vector2) -> void:
	match kind:
		"mob":
			GameState.add_ichor(Data.economy.ichor_gain.mob)
		"elite":
			GameState.add_ichor(Data.economy.ichor_gain.elite)
			GameState.gain_shards(Data.economy.shards.elite_drop)
		"boss":
			GameState.add_ichor(Data.economy.ichor_gain.boss)
			GameState.gain_shards(Data.economy.shards.boss_drop)

func _on_tier_changed(tier: int) -> void:
	if tier < 1:
		return
	var stings: Array = story.get("stings", {}).get(str(tier), [])
	if not stings.is_empty():
		dialogue.show_sting(stings.pick_random())

func _run_level(level_id: int) -> void:
	_run_token += 1
	var token := _run_token
	current_level = level_id
	GameState.start_level(level_id)
	story = _load_story(level_id)
	battle.setup(level_id)
	battle.visible = true
	hud.visible = true
	hud.refresh()
	var cfg := Data.level_config(level_id)

	await _play_story("opening")
	if token != _run_token: return

	var elites_per_wave := _distribute_elites(cfg.elites, cfg.waves)
	for i in cfg.waves:
		if cfg.boss == null and i == cfg.waves - 1:
			await _altar()
			if token != _run_token: return
		hud.set_wave("波次 %d/%d" % [i + 1, cfg.waves])
		battle.spawn_wave(i, elites_per_wave[i])
		await battle.wave_cleared
		if token != _run_token: return
		await _play_story("after_wave_%d" % [i + 1])
		if token != _run_token: return
		await _build_choice()
		if token != _run_token: return

	if cfg.boss != null:
		await _altar()
		if token != _run_token: return
		await _play_story("boss_before")
		if token != _run_token: return
		hud.set_wave("BOSS")
		battle.spawn_boss(cfg.boss)
		await battle.boss_defeated
		if token != _run_token: return
		await _play_story("boss_after")
		if token != _run_token: return

	await _play_story("closing")
	if token != _run_token: return
	var settlement := GameState.grant_settlement()
	shop_panel.open(settlement)
	await shop_panel.closed
	if token != _run_token: return
	GameState.finish_level()
	battle.set_combat_paused(true)
	battle.visible = false
	hud.visible = false
	menu_panel.set_mode(false)
	menu_panel.visible = true

func _play_story(key: String) -> void:
	var token := _run_token
	var lines: Array = story.get("nodes", {}).get(key, [])
	if lines.is_empty():
		return
	battle.set_combat_paused(true)
	dialogue.play("L%02d_%s" % [current_level, key], lines)
	await dialogue.finished
	if token != _run_token: return
	battle.set_combat_paused(false)

func _build_choice() -> void:
	var token := _run_token
	battle.set_combat_paused(true)
	var pool: Array = Data.build_pool.duplicate()
	pool.shuffle()
	build_panel.show_choices(pool.slice(0, 3))
	var option: Dictionary = await build_panel.chosen
	if token != _run_token: return
	GameState.apply_build_option(option)
	battle.set_combat_paused(false)

func _altar() -> void:
	var token := _run_token
	await _play_story("altar")
	if token != _run_token: return
	battle.set_combat_paused(true)
	altar_panel.open()
	await _altar_resolved
	if token != _run_token: return
	battle.set_combat_paused(false)

func _distribute_elites(elites: int, waves: int) -> Array:
	var arr: Array = []
	arr.resize(waves)
	arr.fill(0)
	for k in elites:
		arr[waves - 1 - (k % waves)] += 1
	return arr

func _load_story(level_id: int) -> Dictionary:
	var path := "res://data/story/level_%02d.json" % level_id
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("剧情文件缺失: " + path)
		return {}
	return parsed
