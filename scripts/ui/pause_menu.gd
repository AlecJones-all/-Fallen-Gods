extends CanvasLayer

## Pause menu: Esc toggles it and pauses the tree. Works while the tree is paused.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_panel.tscn")
const SCRIM_COLOR := Color(0.02, 0.02, 0.03, 0.72)
const PANEL_WIDTH := 320.0

var _resume_button: Button
var _settings_button: Button
var _settings_panel: Control
var _is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuShell.apply_preset()
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	get_viewport().set_input_as_handled()
	if _settings_open():
		return
	toggle()


func _build() -> void:
	var column := MenuShell.modal_frame(self, SCRIM_COLOR, PANEL_WIDTH)

	MenuShell.title(column, "已暂停")
	MenuShell.gap(column)

	_resume_button = GoStyle.button("继续游戏", _on_resume_pressed, GoStyle.Tone.PRIMARY)
	_resume_button.name = "Resume"
	column.add_child(_resume_button)

	_settings_button = GoStyle.button("设置", _on_settings_pressed, GoStyle.Tone.NORMAL)
	_settings_button.name = "Settings"
	column.add_child(_settings_button)

	var main_menu_button := GoStyle.button("返回主菜单", _on_main_menu_pressed, GoStyle.Tone.NORMAL)
	main_menu_button.name = "MainMenu"
	column.add_child(main_menu_button)

	var quit_button := GoStyle.button("退出游戏", _on_quit_pressed, GoStyle.Tone.NORMAL)
	quit_button.name = "Quit"
	column.add_child(quit_button)

	MenuShell.hint(column, "Esc 继续游戏")


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	get_tree().paused = true
	visible = true
	if _resume_button != null:
		_resume_button.grab_focus.call_deferred()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	get_tree().paused = false


func _on_resume_pressed() -> void:
	close()


func _on_settings_pressed() -> void:
	if _settings_open():
		return
	_settings_panel = SETTINGS_SCENE.instantiate() as Control
	_settings_panel.name = "SettingsPanel"
	_settings_panel.connect(&"closed", _on_settings_closed)
	add_child(_settings_panel)


func _on_settings_closed() -> void:
	_settings_panel = null
	if _is_open and _settings_button != null:
		_settings_button.grab_focus.call_deferred()


func _on_main_menu_pressed() -> void:
	var router := get_node_or_null(^"/root/Router")
	if router != null and router.has_method(&"goto"):
		router.call(&"goto", MAIN_MENU_SCENE)
		return
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _settings_open() -> bool:
	return _settings_panel != null and is_instance_valid(_settings_panel)
