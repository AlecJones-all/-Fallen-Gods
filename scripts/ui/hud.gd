extends CanvasLayer

## In-game HUD: HP and dash readiness bars, floor progress, the weapon line and the key hints.

const FALLBACK_PRESET := &"medieval_dark"
const PLAYER_GROUP := &"player"
const DUNGEON_GROUP := &"dungeon"
const BOSS_GROUP := &"boss"
const BOSS_FALLBACK_NAME := "BOSS"
const POLL_SECONDS := 0.25
const FALLBACK_MAX_HP := 100.0
const DEFAULT_FLOOR := 1
const DEFAULT_WEAPON := "长剑"
const HIT_FLASH_COLOR: Color = Color(0.78, 0.05, 0.05, 0.32)
const HIT_FLASH_SEC: float = 0.24
const LOW_HP_RATIO: float = 0.3
const LOW_HP_TEXT := "生命垂危"
const WARNING_BLINK_SEC: float = 0.45
const BOSS_FINAL_INK: Color = Color(1.0, 0.3, 0.22)
const HURT_ARROW_COLOR: Color = Color(1.0, 0.32, 0.26, 0.9)
const HURT_ARROW_SIZE: float = 16.0
const HURT_ARROW_RADIUS: float = 0.34
const HURT_ARROW_SEC: float = 0.55

## Caption text, then the actions whose bound keys to show for it.
const KEY_HINT_ROWS := {
	"移动": ["move_forward", "move_left", "move_back", "move_right"],
	"冲刺": ["sprint"],
	"闪避": ["dash"],
	"攻击": ["attack"],
	"换武器": ["weapon_1", "weapon_2", "weapon_next"],
	"暂停": ["pause"],
}

## `OS.get_keycode_string` prints the engine's own words, which read badly on a key cap.
const KEY_WORD_OVERRIDES := {
	" ": "空格",
	"Escape": "Esc",
}

const MOUSE_WORDS := {
	MOUSE_BUTTON_LEFT: "左键",
	MOUSE_BUTTON_RIGHT: "右键",
	MOUSE_BUTTON_WHEEL_UP: "滚轮↑",
	MOUSE_BUTTON_WHEEL_DOWN: "滚轮↓",
}

var _hp_bar: GoBar
var _dash_bar: GoBar
var _boss_bar: GoBar
var _floor_label: Label
var _objective_label: Label
var _warning_label: Label
var _weapon_label: Label
var _flash: ColorRect
var _flash_tween: Tween
var _warning_tween: Tween
var _last_hp: float = -1.0
var _player: Node
var _dungeon: Node
var _boss: Node
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

	_weapon_label = GoStyle.one_line(GoStyle.label(_weapon_text(DEFAULT_WEAPON),
		GoTheme.ROLE_MICRO, GoUi.color(GoTheme.MUTED)))
	_weapon_label.name = "WeaponLabel"
	_weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_weapon_label)

	var top := GoHudAnchor.new()
	top.name = "FloorAnchor"
	top.spot = GoHudAnchor.Spot.TOP_CENTER
	top.keyboard_focus = false
	top.reserve_space = false
	add_child(top)

	var plate := GoStyle.hud_panel(Color.TRANSPARENT, 16, 8, GoTheme.BOX_HUD)
	plate.name = "TopPlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(plate)

	var stack := GoStyle.column(GoUi.metric(GoTheme.GAP_TINY))
	stack.name = "FloorStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(stack)

	var summary := GoStyle.row(GoUi.metric(GoTheme.GAP))
	summary.name = "FloorSummary"
	summary.alignment = BoxContainer.ALIGNMENT_CENTER
	summary.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(summary)

	_floor_label = GoStyle.one_line(GoStyle.label("第 %d 层" % DEFAULT_FLOOR,
		GoTheme.ROLE_COMPACT, GoUi.color(GoTheme.MUTED)))
	_floor_label.name = "FloorLabel"
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_floor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary.add_child(_floor_label)

	_objective_label = GoStyle.one_line(GoStyle.label("", GoTheme.ROLE_MICRO, GoUi.color(GoTheme.MUTED)))
	_objective_label.name = "ObjectiveLabel"
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary.add_child(_objective_label)

	_boss_bar = GoBar.new()
	_boss_bar.name = "BossBar"
	_boss_bar.label_text = BOSS_FALLBACK_NAME
	_boss_bar.ink = GoUi.color(GoTheme.DANGER_FILL)
	_boss_bar.thickness = 10
	_boss_bar.readout = GoBar.Readout.PERCENT
	_boss_bar.custom_minimum_size.x = 420.0
	_boss_bar.visible = false
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_boss_bar)

	_warning_label = GoStyle.one_line(GoStyle.label(LOW_HP_TEXT, GoTheme.ROLE_COMPACT, GoUi.color(GoTheme.DANGER)))
	_warning_label.name = "LowHpWarning"
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning_label.visible = false
	stack.add_child(_warning_label)

	_build_key_hints()
	_build_hit_flash()


func _build_key_hints() -> void:
	var anchor := GoHudAnchor.new()
	anchor.name = "KeyHintAnchor"
	anchor.spot = GoHudAnchor.Spot.BOTTOM_RIGHT
	anchor.keyboard_focus = false
	anchor.reserve_space = false
	add_child(anchor)

	var panel := GoStyle.hud_panel(Color.TRANSPARENT, 12, 8, GoTheme.BOX_HUD)
	panel.name = "KeyHints"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(panel)

	var grid := GridContainer.new()
	grid.name = "KeyHintGrid"
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override(&"h_separation", GoUi.metric(GoTheme.GAP_SMALL))
	grid.add_theme_constant_override(&"v_separation", GoUi.metric(GoTheme.GAP_TINY))
	panel.add_child(grid)

	for caption_text: String in KEY_HINT_ROWS:
		var caption := GoStyle.label(caption_text, GoTheme.ROLE_MICRO, GoUi.color(GoTheme.MUTED))
		caption.name = "HintName"
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		GoStyle.natural_width(caption)
		grid.add_child(caption)

		var caps := GoStyle.row(GoUi.metric(GoTheme.GAP_TINY))
		caps.name = "HintCaps"
		caps.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var actions: Array = KEY_HINT_ROWS[caption_text]
		for action: String in actions:
			caps.add_child(_kbd_for(StringName(action)))
		grid.add_child(caps)


## The caps for one action, read out of `InputMap` so a rebind cannot leave a lying hint behind.
## `GoKbd` only knows keyboard events, so the mouse bindings are worded here.
func _kbd_for(action: StringName) -> GoKbd:
	var keys: Array = []
	for word in GoKbd.action_keys(action):
		var text := String(word)
		keys.append(KEY_WORD_OVERRIDES.get(text, text))
	if keys.is_empty():
		var mouse := _mouse_word(action)
		if not mouse.is_empty():
			keys.append(mouse)
	var node := GoKbd.new()
	node.name = "Kbd"
	node.set_keys(keys)
	return node


func _mouse_word(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		var button := event as InputEventMouseButton
		if button == null:
			continue
		var word := String(MOUSE_WORDS.get(button.button_index, ""))
		if not word.is_empty():
			return word
	return ""


func _build_hit_flash() -> void:
	# Full-viewport overlay, drawn above every panel and inert to the mouse.
	_flash = ColorRect.new()
	_flash.name = "HitFlash"
	_flash.color = Color(HIT_FLASH_COLOR, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)


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
	if not is_instance_valid(_boss):
		_boss = tree.get_first_node_in_group(BOSS_GROUP)
		if _boss != null:
			_bind_boss()
		elif _boss_bar != null:
			_boss_bar.visible = false


func _bind_player() -> void:
	_seed_bars()
	_seed_weapon()
	_connect_player_signal(&"hp_changed", _on_hp_changed)
	_connect_player_signal(&"dash_state_changed", _on_dash_state_changed)
	_connect_player_signal(&"weapon_changed", _on_weapon_changed)
	_connect_player_signal(&"damaged_from", _on_player_damaged)


func _bind_boss() -> void:
	if not is_instance_valid(_boss) or _boss_bar == null:
		return
	if _boss.has_signal(&"health_changed") \
			and not _boss.is_connected(&"health_changed", _on_boss_health_changed):
		_boss.connect(&"health_changed", _on_boss_health_changed)
	if _boss.has_signal(&"died") and not _boss.is_connected(&"died", _on_boss_died):
		_boss.connect(&"died", _on_boss_died)
	if _boss.has_signal(&"phase_changed") \
			and not _boss.is_connected(&"phase_changed", _on_boss_phase_changed):
		_boss.connect(&"phase_changed", _on_boss_phase_changed)

	var display := BOSS_FALLBACK_NAME
	if _boss.has_method(&"get_display_name"):
		display = String(_boss.call(&"get_display_name"))
	_boss_bar.label_text = display

	var current := 1.0
	var maximum := 1.0
	if _boss.has_method(&"get_current_hp"):
		current = float(_boss.call(&"get_current_hp"))
	if _boss.has_method(&"get_max_hp"):
		maximum = maxf(float(_boss.call(&"get_max_hp")), 1.0)
	_boss_bar.set_values(current, maximum, false)
	_boss_bar.visible = true
	if _boss.has_method(&"get_phase"):
		_on_boss_phase_changed(int(_boss.call(&"get_phase")))

	if _objective_label != null:
		_objective_label.text = "击败 BOSS · %s" % display


func _on_boss_phase_changed(phase: int) -> void:
	if _boss_bar == null:
		return
	match phase:
		2:
			_boss_bar.ink = GoUi.color(GoTheme.WARNING_FILL)
		3:
			_boss_bar.ink = BOSS_FINAL_INK
		_:
			_boss_bar.ink = GoUi.color(GoTheme.DANGER_FILL)


func _on_boss_health_changed(current: float, maximum: float) -> void:
	if _boss_bar != null:
		_boss_bar.set_values(current, maxf(maximum, 1.0))


func _on_boss_died(_boss_node: Node) -> void:
	_boss = null
	if _boss_bar != null:
		_boss_bar.visible = false
	if _objective_label != null:
		# The boss only guards the exit room, so its death always unlocks the portal.
		_objective_label.text = "本层已肃清 · 进入传送门"


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
	var current := _player_value(&"get_current_hp", FALLBACK_MAX_HP)
	var maximum := _player_value(&"get_max_hp", FALLBACK_MAX_HP)
	_last_hp = current
	_hp_bar.set_values(current, maximum, false)
	_update_low_hp_warning(current, maximum)
	_apply_dash(_player_value(&"get_dash_remaining", 0.0),
		_player_value(&"get_dash_total", 0.0), false)


func _seed_weapon() -> void:
	var label := DEFAULT_WEAPON
	if is_instance_valid(_player) and _player.has_method(&"get_weapon_label"):
		var value: Variant = _player.call(&"get_weapon_label")
		if value is String or value is StringName:
			label = String(value)
	_apply_weapon(label)


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
	_update_low_hp_warning(current, maximum)
	if _last_hp >= 0.0 and current < _last_hp - 0.01:
		_trigger_hit_flash()
	_last_hp = current


func _update_low_hp_warning(current: float, maximum: float) -> void:
	if _warning_label == null:
		return
	var low := maximum > 0.0 and current > 0.0 and current / maximum <= LOW_HP_RATIO
	if low:
		if _warning_label.visible:
			return
		_warning_label.visible = true
		_warning_label.modulate.a = 1.0
		if _warning_tween != null and _warning_tween.is_valid():
			_warning_tween.kill()
		_warning_tween = create_tween().set_loops()
		_warning_tween.tween_property(_warning_label, "modulate:a", 0.35, WARNING_BLINK_SEC)
		_warning_tween.tween_property(_warning_label, "modulate:a", 1.0, WARNING_BLINK_SEC)
	elif _warning_label.visible:
		_warning_label.visible = false
		if _warning_tween != null and _warning_tween.is_valid():
			_warning_tween.kill()
		_warning_tween = null


func _on_player_damaged(source_position: Vector3) -> void:
	if not source_position.is_finite() or not is_instance_valid(_player):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var to_source := source_position - (_player as Node3D).global_position
	to_source.y = 0.0
	if to_source.length_squared() < 0.0001:
		return
	to_source = to_source.normalized()

	var camera_basis := camera.global_transform.basis
	# Camera local +z points behind the camera; project it and the right axis onto the ground.
	var back := Vector3(camera_basis.z.x, 0.0, camera_basis.z.z)
	var right := Vector3(camera_basis.x.x, 0.0, camera_basis.x.z)
	if back.length_squared() < 0.0001 or right.length_squared() < 0.0001:
		return
	back = back.normalized()
	right = right.normalized()

	var screen_dir := Vector2(to_source.dot(right), to_source.dot(back))
	if screen_dir.length_squared() < 0.0001:
		return
	screen_dir = screen_dir.normalized()

	var view := get_viewport().get_visible_rect().size
	var arrow := Polygon2D.new()
	arrow.name = "HurtDirection"
	arrow.polygon = PackedVector2Array([
		Vector2(0.0, -HURT_ARROW_SIZE),
		Vector2(HURT_ARROW_SIZE * 0.7, HURT_ARROW_SIZE * 0.55),
		Vector2(-HURT_ARROW_SIZE * 0.7, HURT_ARROW_SIZE * 0.55),
	])
	arrow.color = HURT_ARROW_COLOR
	arrow.position = view * 0.5 + screen_dir * minf(view.x, view.y) * HURT_ARROW_RADIUS
	arrow.rotation = atan2(screen_dir.x, -screen_dir.y)
	add_child(arrow)

	var tween := create_tween()
	tween.tween_property(arrow, "modulate:a", 0.0, HURT_ARROW_SEC)
	tween.tween_callback(arrow.queue_free)


func _trigger_hit_flash() -> void:
	if _flash == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.color.a = HIT_FLASH_COLOR.a
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, HIT_FLASH_SEC)


func _on_dash_state_changed(remaining: float, total: float) -> void:
	_apply_dash(remaining, total)


func _on_weapon_changed(_index: int, label: String) -> void:
	_apply_weapon(label)


func _on_dungeon_status(floor_number: int, cleared: int, total: int,
		_enemies_left: int, active_left: int) -> void:
	_apply_dungeon_status(floor_number, cleared, total, active_left)


func _apply_weapon(label: String) -> void:
	_weapon_label.text = _weapon_text(label)


func _weapon_text(label: String) -> String:
	return "武器　%s" % label


func _apply_dungeon_status(floor_number: int, cleared: int, total: int, active_left: int) -> void:
	_floor_label.text = "第 %d 层 · 清剿 %d/%d" % [floor_number, cleared, total]
	var elites := _node_int(_dungeon, &"get_active_elite_count", 0)
	if active_left > 0:
		_objective_label.text = "剩余敌人 %d" % active_left
		if elites > 0:
			_objective_label.text += " · 精英 %d" % elites
	elif total > 0 and cleared >= total:
		_objective_label.text = "本层已肃清 · 进入传送门"
	else:
		_objective_label.text = "探索房间 · 清剿敌人"

	if is_instance_valid(_boss) and _boss_bar != null and _boss_bar.visible:
		_objective_label.text = "击败 BOSS · %s" % _boss_bar.label_text


func _apply_dash(remaining: float, total: float, animate := true) -> void:
	var ready := 1.0 if total <= 0.0 else clampf(1.0 - remaining / total, 0.0, 1.0)
	_dash_bar.set_ratio(ready, animate)
