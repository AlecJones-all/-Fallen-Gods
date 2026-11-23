extends Node

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("存档写入失败: " + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({ "version": SAVE_VERSION, "meta": GameState.meta }, "\t"))

func load_game() -> void:
	if not has_save():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary and parsed.has("meta"):
		GameState.meta.merge(parsed.meta, true)
	else:
		push_warning("存档损坏，使用默认进度")