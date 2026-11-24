extends CanvasLayer

## In-game HUD: HP and dash readiness bars, plus the floor title.

const FALLBACK_PRESET := &"medieval_dark"
const PLAYER_GROUP := &"player"
const POLL_SECONDS := 0.25
const FALLBACK_MAX_HP := 100.0

var _hp_bar: GoBar
var _dash_bar: GoBar
var _player: Node
var _poll: Timer


func _ready() -> void:
	_apply_preset()
	_build()
	_start_player_poll()
	_find_player.call_deferred()


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
	var corner := GoHudAnchor.new()
	corner.name = "Corner"
	corner.spot = GoHudAnchor.Spot.TOP_LEFT
	corner.keyboard_focus = false
	corner.reserve_space = false
	add_child(corner)

	var dock := GoStyle.hud_panel(Color.TRANSPARENT, 14, 10, GoTheme.BOX_HUD)
	dock.name = "Dock"
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_child(dock)

	var column := GoStyle.column(GoUi.metric(GoTheme.GAP_SMALL))
	column.name = "Bars"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(column)

	_hp_bar = GoBar.new()
	_hp_bar.name = "HpBar"
	_hp_bar.label_text = "生命"
	_hp_bar.ink = GoUi.color(GoTheme.DANGER_FILL)
	_hp_bar.custom_minimum_size.x = 220.0
	_hp_bar.set_values(FALLBACK_MAX_HP, FALLBACK_MAX_HP, false)
	column.add_child(_hp_bar)

	_dash_bar = GoBar.new()
	_dash_bar.name = "DashBar"
	_dash_bar.label_text = "冲刺"
	_dash_bar.ink = GoUi.color(GoTheme.ACCENT_FILL)
	_dash_bar.thickness = 6
	_dash_bar.readout = GoBar.Readout.NONE
	_dash_bar.custom_minimum_size.x = 140.0
	_dash_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_dash_bar.set_ratio(1.0, false)
	column.add_child(_dash_bar)

	var top := GoHudAnchor.new()
	top.name = "FloorAnchor"
	top.spot = GoHudAnchor.Spot.TOP_CENTER
	top.keyboard_focus = false
	top.reserve_space = false
	add_child(top)

	var floor_label := GoStyle.label("第 1 层 · 灰盒测试", GoTheme.ROLE_COMPACT, GoUi.color(GoTheme.MUTED))
	floor_label.name = "FloorLabel"
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(floor_label)


func _start_player_poll() -> void:
	_poll = Timer.new()
	_poll.name = "PlayerPoll"
	_poll.wait_time = POLL_SECONDS
	_poll.autostart = true
	_poll.timeout.connect(_find_player)
	add_child(_poll)


func _find_player() -> void:
	if is_instance_valid(_player):
		return
	_player = null
	var tree := get_tree()
	if tree == null:
		return
	_player = tree.get_first_node_in_group(PLAYER_GROUP)
	if _player != null:
		_bind_player()


func _bind_player() -> void:
	_seed_bars()
	_connect_player_signal(&"hp_changed", _on_hp_changed)
	_connect_player_signal(&"dash_state_changed", _on_dash_state_changed)


func _connect_player_signal(signal_name: StringName, handler: Callable) -> void:
	if not _player.has_signal(signal_name) or _player.is_connected(signal_name, handler):
		return
	_player.connect(signal_name, handler)


func _seed_bars() -> void:
	_hp_bar.set_values(_player_value(&"get_current_hp", FALLBACK_MAX_HP),
		_player_value(&"get_max_hp", FALLBACK_MAX_HP), false)
	_apply_dash(_player_value(&"get_dash_remaining", 0.0),
		_player_value(&"get_dash_total", 0.0), false)


func _player_value(method: StringName, fallback: float) -> float:
	if not is_instance_valid(_player) or not _player.has_method(method):
		return fallback
	var value: Variant = _player.call(method)
	if value is float or value is int:
		return float(value)
	return fallback


func _on_hp_changed(current: float, maximum: float) -> void:
	_hp_bar.set_values(current, maximum)


func _on_dash_state_changed(remaining: float, total: float) -> void:
	_apply_dash(remaining, total)


func _apply_dash(remaining: float, total: float, animate := true) -> void:
	var ready := 1.0 if total <= 0.0 else clampf(1.0 - remaining / total, 0.0, 1.0)
	_dash_bar.set_ratio(ready, animate)
