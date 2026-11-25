extends CanvasLayer

## Main menu: title, start/settings/quit buttons and the build version.

const GAME_SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"
const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_panel.tscn")

var _start_button: Button
var _settings_button: Button
var _settings_panel: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuShell.apply_preset()
	_build()
	if _start_button != null:
		_start_button.grab_focus.call_deferred()


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

	var column := MenuShell.menu_column(center, 340.0)

	MenuShell.title(column, "Fallen Gods", GoTheme.TEXT, 1.8)
	MenuShell.subtitle(column, "帷外 · 灰盒原型", GoTheme.MUTED)
	MenuShell.gap(column, GoTheme.GAP_LARGE)

	_start_button = GoStyle.button("开始游戏", _on_start_pressed, GoStyle.Tone.PRIMARY)
	_start_button.name = "Start"
	column.add_child(_start_button)

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


func _on_start_pressed() -> void:
	_goto(GAME_SCENE, {"restart_scene": GAME_SCENE})


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
