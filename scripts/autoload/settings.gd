extends Node

const CONFIG_PATH := "user://settings.cfg"
const MIN_WINDOW_SIZE := Vector2i(960, 540)
const DEFAULT_WINDOW_SIZE := Vector2i(1280, 720)
## Room kept free around a windowed client area for the title bar and borders.
const SCREEN_MARGIN := Vector2i(16, 64)
const SAVE_DEBOUNCE_SEC := 0.5
const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(1024, 768),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1366, 768),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1680, 1050),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1080),
	Vector2i(2560, 1440),
	Vector2i(2560, 1600),
	Vector2i(3840, 2160),
]

signal changed

var master: float = 0.8
var music: float = 0.7
var sfx: float = 0.8
var fullscreen: bool = false
var window_size: Vector2i = DEFAULT_WINDOW_SIZE

var _save_timer: Timer


func _ready() -> void:
	_load()
	apply()
	_start_window_tracking()


func _exit_tree() -> void:
	_capture_window_size()
	save()


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
	if fullscreen == on:
		return
	if on:
		_capture_window_size()
	fullscreen = on
	if not _is_headless():
		if on:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			window_size = _clamp_to_screen(window_size)
			DisplayServer.window_set_size(window_size)
			_center_window()
	save()
	changed.emit()


func set_window_size(size: Vector2i) -> void:
	window_size = _clamp_to_screen(size)
	if not _is_headless():
		if fullscreen:
			fullscreen = false
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_size)
		_center_window()
	save()
	changed.emit()


func get_window_size() -> Vector2i:
	return window_size


## Presets that fit on the current screen, plus the size in use. Sorted small to large.
func available_resolutions() -> Array[Vector2i]:
	var options: Array[Vector2i] = []
	var limit := Vector2i.ZERO
	if not _is_headless():
		limit = DisplayServer.screen_get_usable_rect(
			DisplayServer.window_get_current_screen()).size - SCREEN_MARGIN
	for preset in RESOLUTION_PRESETS:
		var size: Vector2i = preset
		if limit.x <= 0 or limit.y <= 0 or (size.x <= limit.x and size.y <= limit.y):
			if not options.has(size):
				options.append(size)
	if not options.has(window_size):
		options.append(window_size)
	options.sort_custom(_resolution_before)
	return options


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master)
	config.set_value("audio", "music", music)
	config.set_value("audio", "sfx", sfx)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "window_size", window_size)
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
	var stored: Variant = config.get_value("display", "window_size", window_size)
	if stored is Vector2i:
		window_size = _clamp_to_screen(stored)
	elif stored is Vector2:
		window_size = _clamp_to_screen(Vector2i(stored))


func _apply_bus(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(value, 0.0001, 1.0)))


func _apply_display() -> void:
	if _is_headless():
		return
	DisplayServer.window_set_min_size(MIN_WINDOW_SIZE)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	window_size = _clamp_to_screen(window_size)
	if DisplayServer.window_get_size() != window_size:
		DisplayServer.window_set_size(window_size)
	_center_window()


func _start_window_tracking() -> void:
	if _is_headless():
		return
	get_tree().root.size_changed.connect(_on_window_resized)
	_save_timer = Timer.new()
	_save_timer.name = "SaveTimer"
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SEC
	_save_timer.timeout.connect(save)
	add_child(_save_timer)


## Dragging the window edge bypasses `set_window_size`, so the last real size is
## picked up here and written once the user stops resizing.
func _on_window_resized() -> void:
	if fullscreen:
		return
	_capture_window_size()
	if _save_timer != null:
		_save_timer.start()


func _capture_window_size() -> void:
	if _is_headless() or fullscreen:
		return
	var current := DisplayServer.window_get_size()
	if current.x >= MIN_WINDOW_SIZE.x and current.y >= MIN_WINDOW_SIZE.y:
		window_size = current


func _clamp_to_screen(size: Vector2i) -> Vector2i:
	var result := Vector2i(
		maxi(size.x, MIN_WINDOW_SIZE.x),
		maxi(size.y, MIN_WINDOW_SIZE.y))
	if _is_headless():
		return result
	var usable := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen()).size
	if usable.x > 0 and usable.y > 0:
		result.x = mini(result.x, maxi(usable.x - SCREEN_MARGIN.x, MIN_WINDOW_SIZE.x))
		result.y = mini(result.y, maxi(usable.y - SCREEN_MARGIN.y, MIN_WINDOW_SIZE.y))
	return result


func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_position(
		usable.position + (usable.size - DisplayServer.window_get_size()) / 2)


func _resolution_before(a: Vector2i, b: Vector2i) -> bool:
	return a.x * a.y < b.x * b.y


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
