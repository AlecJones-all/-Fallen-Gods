extends CanvasLayer

## In-game HUD: HP and dash readiness bars, floor progress, and the weapon line.

const FALLBACK_PRESET := &"medieval_dark"
const PLAYER_GROUP := &"player"
const DUNGEON_GROUP := &"dungeon"
const POLL_SECONDS := 0.25
const FALLBACK_MAX_HP := 100.0
const DEFAULT_FLOOR := 1
const WEAPON_SLOTS := 2
const DEFAULT_WEAPON := "长剑"

var _hp_bar: GoBar
var _dash_bar: GoBar
var _floor_label: Label
var _objective_label: Label
var _weapon_label: Label
var _player: Node
var _dungeon: Node
var _poll: Timer


func _ready() -> void:
	_apply_preset()
	_build()
	_start_target_poll()
	_find_targets.call_deferred()


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

	_weapon_label = GoStyle.label(_weapon_text(0, DEFAULT_WEAPON),
		GoTheme.ROLE_MICRO, GoUi.color(GoTheme.MUTED))
	_weapon_label.name = "WeaponLabel"
	_weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_weapon_label)

	var top := GoHudAnchor.new()
	top.name = "FloorAnchor"
	top.spot = GoHudAnchor.Spot.TOP_CENTER
	top.keyboard_focus = false
	top.reserve_space = false
	add_child(top)

	var stack := GoStyle.column(GoUi.metric(GoTheme.GAP_TINY))
	stack.name = "FloorStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(stack)

	_floor_label = GoStyle.label("第 %d 层" % DEFAULT_FLOOR,
		GoTheme.ROLE_COMPACT, GoUi.color(GoTheme.MUTED))
	_floor_label.name = "FloorLabel"
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_floor_label)

	_objective_label = GoStyle.label("", GoTheme.ROLE_MICRO, GoUi.color(GoTheme.MUTED))
	_objective_label.name = "ObjectiveLabel"
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_objective_label)


func _start_target_poll() -> void:
	_poll = Timer.new()
	_poll.name = "TargetPoll"
	_poll.wait_time = POLL_SECONDS
	_poll.autostart = true
	_poll.timeout.connect(_find_targets)
	add_child(_poll)


func _find_targets() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if not is_instance_valid(_player):
		_player = tree.get_first_node_in_group(PLAYER_GROUP)
		if _player != null:
			_bind_player()
	if not is_instance_valid(_dungeon):
		_dungeon = tree.get_first_node_in_group(DUNGEON_GROUP)
		if _dungeon != null:
			_bind_dungeon()


func _bind_player() -> void:
	_seed_bars()
	_seed_weapon()
	_connect_player_signal(&"hp_changed", _on_hp_changed)
	_connect_player_signal(&"dash_state_changed", _on_dash_state_changed)
	_connect_player_signal(&"weapon_changed", _on_weapon_changed)


func _connect_player_signal(signal_name: StringName, handler: Callable) -> void:
	if not _player.has_signal(signal_name) or _player.is_connected(signal_name, handler):
		return
	_player.connect(signal_name, handler)


func _bind_dungeon() -> void:
	if _dungeon.has_signal(&"status_changed") \
			and not _dungeon.is_connected(&"status_changed", _on_dungeon_status):
		_dungeon.connect(&"status_changed", _on_dungeon_status)
	_apply_dungeon_status(
		_node_int(_dungeon, &"get_floor_number", DEFAULT_FLOOR),
		_node_int(_dungeon, &"get_cleared_count", 0),
		_node_int(_dungeon, &"get_room_total", 0),
		_node_int(_dungeon, &"get_active_enemies_left", 0))


func _seed_bars() -> void:
	_hp_bar.set_values(_player_value(&"get_current_hp", FALLBACK_MAX_HP),
		_player_value(&"get_max_hp", FALLBACK_MAX_HP), false)
	_apply_dash(_player_value(&"get_dash_remaining", 0.0),
		_player_value(&"get_dash_total", 0.0), false)


func _seed_weapon() -> void:
	var label := DEFAULT_WEAPON
	if is_instance_valid(_player) and _player.has_method(&"get_weapon_label"):
		var value: Variant = _player.call(&"get_weapon_label")
		if value is String or value is StringName:
			label = String(value)
	_apply_weapon(_node_int(_player, &"get_weapon_index", 0), label)


func _player_value(method: StringName, fallback: float) -> float:
	if not is_instance_valid(_player) or not _player.has_method(method):
		return fallback
	var value: Variant = _player.call(method)
	if value is float or value is int:
		return float(value)
	return fallback


func _node_int(node: Node, method: StringName, fallback: int) -> int:
	if not is_instance_valid(node) or not node.has_method(method):
		return fallback
	var value: Variant = node.call(method)
	if value is float or value is int:
		return int(value)
	return fallback


func _on_hp_changed(current: float, maximum: float) -> void:
	_hp_bar.set_values(current, maximum)


func _on_dash_state_changed(remaining: float, total: float) -> void:
	_apply_dash(remaining, total)


func _on_weapon_changed(index: int, label: String) -> void:
	_apply_weapon(index, label)


func _on_dungeon_status(floor_number: int, cleared: int, total: int,
		_enemies_left: int, active_left: int) -> void:
	_apply_dungeon_status(floor_number, cleared, total, active_left)


func _apply_weapon(index: int, label: String) -> void:
	_weapon_label.text = _weapon_text(index, label)


func _weapon_text(index: int, label: String) -> String:
	return "武器　%s　·　%d / %d 切换" % [label, index + 1, WEAPON_SLOTS]


func _apply_dungeon_status(floor_number: int, cleared: int, total: int, active_left: int) -> void:
	_floor_label.text = "第 %d 层 · 清剿 %d/%d" % [floor_number, cleared, total]
	if active_left > 0:
		_objective_label.text = "剩余敌人 %d" % active_left
	elif total > 0 and cleared >= total:
		_objective_label.text = "本层已肃清 · 进入传送门"
	else:
		_objective_label.text = "探索房间 · 清剿敌人"


func _apply_dash(remaining: float, total: float, animate := true) -> void:
	var ready := 1.0 if total <= 0.0 else clampf(1.0 - remaining / total, 0.0, 1.0)
	_dash_bar.set_ratio(ready, animate)
