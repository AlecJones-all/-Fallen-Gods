extends CanvasLayer

## Game-over screen: the run's stats and the way back into the game.

const FALLBACK_PRESET := &"medieval_dark"
const SCRIM_COLOR := Color(0.02, 0.02, 0.03, 0.85)
const TIME_FALLBACK := "--:--"
const FLOOR_FALLBACK := "—"

var _restart_button: Button


func _ready() -> void:
	_apply_preset()
	_build()
	_restart_button.grab_focus.call_deferred()
	Audio.play(&"game_over")


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
	var payload: Dictionary = Router.last_payload

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var scrim := GoStyle.scrim(-1.0, SCRIM_COLOR)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scrim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := GoStyle.hud_panel(Color.TRANSPARENT, 40, 32, GoTheme.BOX_PANEL)
	panel.name = "Panel"
	center.add_child(panel)

	var column := GoStyle.column(GoUi.metric(GoTheme.GAP))
	column.name = "Menu"
	column.custom_minimum_size.x = 360.0
	panel.add_child(column)

	var title := GoStyle.label("你已陨落", GoTheme.ROLE_BODY, GoUi.color(GoTheme.DANGER))
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", GoUi.font_size(GoTheme.ROLE_TITLE))
	column.add_child(title)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.custom_minimum_size.y = GoUi.metric(GoTheme.GAP_SMALL)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var time_label := GoStyle.label("存活时间  %s" % _elapsed_text(payload.get("elapsed_sec")),
		GoTheme.ROLE_BODY, GoUi.color(GoTheme.TEXT))
	time_label.name = "Elapsed"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(time_label)

	var floor_label := GoStyle.label("到达层数  %s" % _floor_text(payload.get("floor")),
		GoTheme.ROLE_BODY, GoUi.color(GoTheme.SECONDARY))
	floor_label.name = "Floor"
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(floor_label)

	_restart_button = GoStyle.button("重新开始", _on_restart_pressed, GoStyle.Tone.PRIMARY)
	_restart_button.name = "Restart"
	column.add_child(_restart_button)

	var menu_button := GoStyle.button("返回主菜单", _on_main_menu_pressed, GoStyle.Tone.NORMAL)
	menu_button.name = "MainMenu"
	column.add_child(menu_button)


func _elapsed_text(value: Variant) -> String:
	if not (value is float or value is int):
		return TIME_FALLBACK
	var total := maxi(int(value), 0)
	return "%d:%02d" % [int(total / 60.0), total % 60]


func _floor_text(value: Variant) -> String:
	if value is int or value is float:
		return str(int(value))
	return FLOOR_FALLBACK


func _on_restart_pressed() -> void:
	Router.goto("res://scenes/main.tscn")


func _on_main_menu_pressed() -> void:
	Router.goto("res://scenes/ui/main_menu.tscn")
