extends Node

var tuning: Dictionary
var economy: Dictionary
var cards: Dictionary
var build_pool: Array
var realms: Array
var levels: Array
var bosses: Dictionary
var combat_lanes: Dictionary

func _ready() -> void:
	tuning = _load("res://data/tuning.json")
	economy = _load("res://data/economy.json")
	cards = _load("res://data/cards.json")
	build_pool = _load("res://data/build_pool.json")
	realms = _load("res://data/realms.json")
	levels = _load("res://data/levels.json")
	bosses = _load("res://data/bosses.json")
	combat_lanes = _load("res://data/combat_lanes.json")

func level_config(level_id: int) -> Dictionary:
	return levels[level_id - 1]


func combat_lane_config(level_id: int) -> Dictionary:
	return combat_lanes.levels.get(str(level_id), combat_lanes.default)

func _load(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("数据表缺失: " + path)
		get_tree().quit(1)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("数据表解析失败: " + path)
		get_tree().quit(1)
	return parsed
