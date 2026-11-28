extends CanvasLayer

## Interim page for a stop whose scene is not built yet. It names the stop and offers the way back,
## so every card on the board leads somewhere instead of doing nothing. Replace the level's `scene`
## in [LevelBook] and this page stops being used.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _level := 0
var _back_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuShell.apply_preset()
	_level = _read_level()
	_build()
	if _back_button != null:
		_back_button.grab_focus.call_deferred()


func _read_level() -> int:
	var router := get_node_or_null(^"/root/Router")
	if router == null:
		return 0
	var payload: Dictionary = router.get(&"last_payload")
	var level := int(payload.get("level", 0))
	return clampi(level, 0, LevelBook.count() - 1)


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

	var column := MenuShell.menu_column(center, 420.0)

	var eyebrow := GoStyle.label("第 %02d 关" % (_level + 1), GoTheme.ROLE_COMPACT, GoUi.color(GoTheme.ACCENT))
	eyebrow.name = "Eyebrow"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(eyebrow)

	MenuShell.title(column, LevelBook.name_of(_level), GoTheme.TEXT, 2.0)
	MenuShell.gap(column, GoTheme.GAP_LARGE)

	_back_button = GoStyle.button("返回关卡", _on_back_pressed, GoStyle.Tone.PRIMARY)
	_back_button.name = "Back"
	column.add_child(_back_button)


func _on_back_pressed() -> void:
	_goto(MENU_SCENE, { "open_levels": true, "level": _level })


func _goto(path: String, payload: Dictionary = {}) -> void:
	var router := get_node_or_null(^"/root/Router")
	if router != null and router.has_method(&"goto"):
		router.call(&"goto", path, payload)
		return
	get_tree().change_scene_to_file(path)
