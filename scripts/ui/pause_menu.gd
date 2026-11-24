extends CanvasLayer

## Pause menu: Esc toggles it and pauses the tree. Works while the tree is paused.

const FALLBACK_PRESET := &"medieval_dark"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_panel.tscn")

var _resume_button: Button
var _settings_button: Button
var _settings_panel: Control
var _is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_preset()
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	get_viewport().set_input_as_handled()
	if _settings_open():
		return
	toggle()


func _apply_preset() -> void:
	if GoUi.preset() != null:
		return
	var id := FALLBACK_PRESET
	var tuning := get_node_or_null(^"/root/Tuning")
	if tuning != null and tuning.has_method(&"value"):
		var chosen: Variant = tuning.call(&"value", "ui", "theme_preset", String(FALLBACK_PRESET))
		if chosen is String or chosen is StringName:
			var text := String(chosen)
			if not text.is_empty():
				id = StringName(text)
	GoUi.use_preset(id)


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var scrim := GoStyle.scrim()
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scrim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := GoStyle.hud_panel(Color.TRANSPARENT, 32, 24, GoTheme.BOX_PANEL)
	panel.name = "Panel"
	center.add_child(panel)

	var column := GoStyle.column(GoUi.metric(GoTheme.GAP))
	column.name = "Menu"
	column.custom_minimum_size.x = 300.0
	panel.add_child(column)

	var title := GoStyle.label("已暂停", GoTheme.ROLE_BODY, GoUi.color(GoTheme.TEXT))
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", GoUi.font_size(GoTheme.ROLE_TITLE))
	column.add_child(title)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.custom_minimum_size.y = GoUi.metric(GoTheme.GAP_SMALL)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

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
