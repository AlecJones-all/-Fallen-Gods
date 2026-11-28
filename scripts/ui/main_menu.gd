extends CanvasLayer

## Main menu: title, level board / settings / quit, and the build version.
## The level board replaces the column in place — no scene change, so leaving it is instant
## and the Router is only touched when a level actually starts.

const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_panel.tscn")

var _levels_button: Button
var _settings_button: Button
var _settings_panel: Control
var _title_view: Control
var _version: Label
var _level_view: LevelSelect
var _leaving_board := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuShell.apply_preset()
	_build()
	if _opens_on_board():
		_on_levels_pressed()
	elif _levels_button != null:
		_levels_button.grab_focus.call_deferred()


## Coming back from a stop that is not built yet lands straight on the board again.
func _opens_on_board() -> bool:
	return bool(_payload().get("open_levels", false))


## The board reopens on the stop that was last asked for, so a quick look round keeps its place.
func _remembered_level() -> int:
	var level := int(_payload().get("level", -1))
	if level < 0 or level >= LevelBook.count():
		return -1
	return level


func _payload() -> Dictionary:
	var router := get_node_or_null(^"/root/Router")
	if router == null:
		return {}
	return router.get(&"last_payload")


func _build() -> void:
	var background := GoStyle.scrim(1.0, Color("#0B0C10"))
	background.name = "Background"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_title_view = center

	var column := MenuShell.menu_column(center, 340.0)

	MenuShell.title(column, "Fallen Gods", GoTheme.TEXT, 1.8)
	MenuShell.subtitle(column, "帷外 · 灰盒原型", GoTheme.MUTED)
	MenuShell.gap(column, GoTheme.GAP_LARGE)

	_levels_button = GoStyle.button("选择关卡", _on_levels_pressed, GoStyle.Tone.PRIMARY)
	_levels_button.name = "Levels"
	column.add_child(_levels_button)

	_settings_button = GoStyle.button("设置", _on_settings_pressed, GoStyle.Tone.NORMAL)
	_settings_button.name = "Settings"
	column.add_child(_settings_button)

	var quit_button := GoStyle.button("退出", _on_quit_pressed, GoStyle.Tone.NORMAL)
	quit_button.name = "Quit"
	column.add_child(quit_button)

	_build_version_label()


func _build_version_label() -> void:
	var version := GoStyle.label("开发中 v0.1", GoTheme.ROLE_MICRO, GoUi.color(GoTheme.MUTED))
	version.name = "Version"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var margin := float(GoUi.metric(GoTheme.SCREEN_MARGIN))
	version.offset_left = -220.0
	version.offset_top = -40.0
	version.offset_right = -margin
	version.offset_bottom = -margin
	add_child(version)
	_version = version


func _on_levels_pressed() -> void:
	if _level_view != null and is_instance_valid(_level_view):
		return
	_leaving_board = false
	_level_view = LevelSelect.new()
	_level_view.name = "LevelSelect"
	_level_view.initial_index = _remembered_level()
	_level_view.entered.connect(_on_level_entered)
	_level_view.closed.connect(_on_levels_closed)
	add_child(_level_view)
	# The version line belongs to the title page — the board carries nothing but the fifteen names.
	if _version != null:
		move_child(_version, get_child_count() - 1)
		_version.visible = false

	_level_view.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_title_view, "modulate:a", 0.0, 0.10)
	tween.tween_property(_level_view, "modulate:a", 1.0, 0.16)
	tween.chain().tween_callback(_conceal_title)


func _conceal_title() -> void:
	if _title_view == null:
		return
	_title_view.visible = false
	_title_view.modulate.a = 1.0


func _on_levels_closed() -> void:
	if _level_view == null or _leaving_board:
		return
	_leaving_board = true
	_title_view.visible = true
	_title_view.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_level_view, "modulate:a", 0.0, 0.12)
	tween.tween_property(_title_view, "modulate:a", 1.0, 0.16)
	tween.chain().tween_callback(_dispose_levels)


func _dispose_levels() -> void:
	if _level_view != null:
		_level_view.queue_free()
		_level_view = null
	if _version != null:
		_version.visible = true
	if _levels_button != null:
		_levels_button.grab_focus.call_deferred()


func _on_level_entered(scene_path: String, level_index: int) -> void:
	_goto(scene_path, {
		"restart_scene": scene_path,
		"level": level_index,
		"name": LevelBook.name_of(level_index),
	})


func _on_settings_pressed() -> void:
	if _settings_panel != null and is_instance_valid(_settings_panel):
		return
	_settings_panel = SETTINGS_SCENE.instantiate() as Control
	_settings_panel.name = "SettingsPanel"
	_settings_panel.connect(&"closed", _on_settings_closed)
	add_child(_settings_panel)


func _on_settings_closed() -> void:
	_settings_panel = null
	if _settings_button != null:
		_settings_button.grab_focus.call_deferred()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _goto(path: String, payload: Dictionary = {}) -> void:
	var router := get_node_or_null(^"/root/Router")
	if router != null and router.has_method(&"goto"):
		router.call(&"goto", path, payload)
		return
	get_tree().change_scene_to_file(path)
