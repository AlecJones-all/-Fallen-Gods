extends CanvasLayer

## Game-over screen: the run's stats and the way back into the game.

const SCRIM_COLOR := Color(0.02, 0.02, 0.03, 0.85)
const TIME_FALLBACK := "--:--"
const FLOOR_FALLBACK := "—"

var _restart_button: Button


func _ready() -> void:
	MenuShell.apply_preset()
	_build()
	_restart_button.grab_focus.call_deferred()
	Audio.play(&"game_over")


func _build() -> void:
	var payload: Dictionary = Router.last_payload
	var column := MenuShell.modal_frame(self, SCRIM_COLOR, 360.0)

	MenuShell.title(column, "你已陨落", GoTheme.DANGER)
	MenuShell.subtitle(column, "深渊吞没了你")
	MenuShell.gap(column)
	MenuShell.stat_row(column, "存活时间", _elapsed_text(payload.get("elapsed_sec")))
	MenuShell.stat_row(column, "到达层数", _floor_text(payload.get("floor")))
	MenuShell.gap(column)

	_restart_button = GoStyle.button("重新开始", _on_restart_pressed, GoStyle.Tone.PRIMARY)
	_restart_button.name = "Restart"
	column.add_child(_restart_button)

	var menu_button := GoStyle.button("返回主菜单", _on_main_menu_pressed, GoStyle.Tone.NORMAL)
	menu_button.name = "MainMenu"
	column.add_child(menu_button)

	MenuShell.hint(column, "回车确认")


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
