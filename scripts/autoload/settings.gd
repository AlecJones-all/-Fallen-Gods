extends Node

const CONFIG_PATH := "user://settings.cfg"

signal changed

var master: float = 0.8
var music: float = 0.7
var sfx: float = 0.8
var fullscreen: bool = false


func _ready() -> void:
	_load()
	apply()


func set_master(value: float) -> void:
	master = clampf(value, 0.0, 1.0)
	_apply_bus("Master", master)
	save()
	changed.emit()


func set_music(value: float) -> void:
	music = clampf(value, 0.0, 1.0)
	_apply_bus("Music", music)
	save()
	changed.emit()


func set_sfx(value: float) -> void:
	sfx = clampf(value, 0.0, 1.0)
	_apply_bus("SFX", sfx)
	save()
	changed.emit()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_display()
	save()
	changed.emit()


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master)
	config.set_value("audio", "music", music)
	config.set_value("audio", "sfx", sfx)
	config.set_value("display", "fullscreen", fullscreen)
	var err := config.save(CONFIG_PATH)
	if err != OK:
		push_warning("Settings: 无法写入 %s（错误码 %d）" % [CONFIG_PATH, err])


func apply() -> void:
	_apply_bus("Master", master)
	_apply_bus("Music", music)
	_apply_bus("SFX", sfx)
	_apply_display()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	master = clampf(float(config.get_value("audio", "master", master)), 0.0, 1.0)
	music = clampf(float(config.get_value("audio", "music", music)), 0.0, 1.0)
	sfx = clampf(float(config.get_value("audio", "sfx", sfx)), 0.0, 1.0)
	fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))


func _apply_bus(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(value, 0.0001, 1.0)))


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
