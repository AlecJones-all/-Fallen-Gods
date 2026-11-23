extends Node
## 音效管理器：EventBus 信号自动触发 + play_sfx(id) 供战斗/UI 细粒度挂钩。
## 素材：Soundza Standard License（免费商用，随游戏分发，见 assets/audio/sfx/LICENSE）。

const POOL_SIZE := 16
const BASE := "res://assets/audio/sfx/"

const SFX := {
	"mob_kill": "explosions/crackly_bang_hit.wav",
	"elite_kill": "explosions/dark_boom_impact.wav",
	"boss_kill": "explosions/large_explosion.wav",
	"player_hurt": "hits_impacts/deep_punch_thud.wav",
	"player_heal": "magic/magical_heal_chime.wav",
	"wave_clear": "jingles_stingers/glockenspiel_success_chime.wav",
	"level_clear": "jingles_stingers/level_clear.wav",
	"player_death": "ui_menu/ominous_stinger.wav",
	"corruption_tier": "magic/dark_sci_fi_charge_up.wav",
	"ichor": "pickups_powerups/coin_5.wav",
	"shards": "ui_menu/fantasy_crystal_chime.wav",
	"story_start": "ui_menu/soft_ui_tap.wav",
	"ball_bounce": "hits_impacts/bounce_energy_deep_one_shot.wav",
	"ball_hit": "hits_impacts/hit_7.wav",
	"ui_click": "ui_menu/short_ui_click.wav",
	"ui_confirm": "ui_menu/menu_selection_click.wav",
}

const VOLUMES := {
	"mob_kill": -10.0, "elite_kill": -6.0, "boss_kill": -4.0,
	"player_hurt": -5.0, "player_heal": -8.0,
	"wave_clear": -7.0, "level_clear": -6.0, "player_death": -5.0,
	"corruption_tier": -6.0, "ichor": -12.0, "shards": -8.0,
	"story_start": -14.0, "ball_bounce": -16.0, "ball_hit": -12.0,
	"ui_click": -10.0, "ui_confirm": -9.0,
}

# 同一音效的最小重触发间隔（秒），防止割草时叠成噪音墙
const THROTTLE := {
	"mob_kill": 0.06, "ichor": 0.09, "ball_bounce": 0.05, "ball_hit": 0.05,
	"player_heal": 0.2,
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _last_played: Dictionary = {}
var _last_hp: float = -1.0
var _last_ichor: int = -1
var _last_shards: int = -1


func _ready() -> void:
	for id in SFX:
		_streams[id] = load(BASE + SFX[id])
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EventBus.mob_died.connect(_on_mob_died)
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.wave_cleared.connect(func(_w: int) -> void: play_sfx("wave_clear"))
	EventBus.level_cleared.connect(func(_l: int) -> void:
		play_sfx("level_clear")
		_last_hp = -1.0)
	EventBus.player_died.connect(func() -> void:
		play_sfx("player_death")
		_last_hp = -1.0)
	EventBus.corruption_tier_changed.connect(func(_t: int) -> void: play_sfx("corruption_tier"))
	EventBus.ichor_changed.connect(_on_ichor)
	EventBus.shards_changed.connect(_on_shards)
	EventBus.story_node_started.connect(func(_n: String) -> void: play_sfx("story_start"))


func play_sfx(id: String, pitch_jitter: float = 0.0) -> void:
	if not _streams.has(id):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var gap: float = THROTTLE.get(id, 0.0)
	if gap > 0.0 and now - float(_last_played.get(id, -100.0)) < gap:
		return
	_last_played[id] = now
	var p := _get_player()
	if p == null:
		return
	p.stream = _streams[id]
	p.volume_db = VOLUMES.get(id, -8.0)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _get_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	var oldest := _players[0]
	for p in _players:
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest


func _on_mob_died(kind: String, _pos: Vector2) -> void:
	if kind == "boss":
		play_sfx("boss_kill")
	elif kind == "elite":
		play_sfx("elite_kill", 0.05)
	else:
		play_sfx("mob_kill", 0.1)


func _on_hp_changed(hp: float, _max_hp: float) -> void:
	if _last_hp >= 0.0:
		if hp < _last_hp:
			play_sfx("player_hurt")
		elif hp > _last_hp:
			play_sfx("player_heal")
	_last_hp = hp


func _on_ichor(total: int) -> void:
	if _last_ichor >= 0 and total > _last_ichor:
		play_sfx("ichor", 0.08)
	_last_ichor = total


func _on_shards(total: int) -> void:
	if _last_shards >= 0 and total > _last_shards:
		play_sfx("shards")
	_last_shards = total