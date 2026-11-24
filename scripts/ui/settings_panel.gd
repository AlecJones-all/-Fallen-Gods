extends Control

## Settings panel: volume sliders, fullscreen toggle and window size, usable while the tree runs or is paused.

signal closed

const SLIDER_STEP := 0.01
const LABEL_WIDTH := 76.0
const PERCENT_WIDTH := 52.0
const FALLBACK_WINDOW_SIZE := Vector2i(1280, 720)

var _settings: Node
var _first_slider: HSlider
var _resolution_picker: OptionButton
var _resolution_hint: Label
var _closing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings = get_node_or_null(^"/root/Settings")
	_build()
	if _first_slider != null:
		_first_slider.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	get_viewport().set_input_as_handled()
	close()


func _build() -> void:
	var scrim := GoStyle.scrim()
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := GoStyle.hud_panel(Color.TRANSPARENT, 32, 24, GoTheme.BOX_PANEL)
	panel.name = "Panel"
	center.add_child(panel)

	var column := GoStyle.column(GoUi.metric(GoTheme.GAP))
	column.name = "Settings"
	column.custom_minimum_size.x = 420.0
	panel.add_child(column)

	var title := GoStyle.label("设置", GoTheme.ROLE_BODY, GoUi.color(GoTheme.TEXT))
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", GoUi.font_size(GoTheme.ROLE_TITLE))
	column.add_child(title)

	_first_slider = _add_slider_row(column, "主音量", &"master", 1.0)
	_add_slider_row(column, "音乐", &"music", 1.0)
	_add_slider_row(column, "音效", &"sfx", 1.0)

	var fullscreen := GoStyle.toggle("全屏", false)
	fullscreen.name = "Fullscreen"
	fullscreen.set_pressed_no_signal(_read_bool(&"fullscreen", false))
	fullscreen.toggled.connect(_on_fullscreen_toggled)
	column.add_child(fullscreen)

	_resolution_picker = _add_resolution_row(column, fullscreen.button_pressed)
	_resolution_hint = GoStyle.label("全屏时跟随桌面分辨率", GoTheme.ROLE_MICRO,
		GoUi.color(GoTheme.MUTED))
	_resolution_hint.name = "ResolutionHint"
	_resolution_hint.visible = fullscreen.button_pressed
	column.add_child(_resolution_hint)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.custom_minimum_size.y = GoUi.metric(GoTheme.GAP_SMALL)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var back := GoStyle.button("返回", close, GoStyle.Tone.PRIMARY)
	back.name = "Back"
	column.add_child(back)


func _add_slider_row(column: VBoxContainer, title: String, key: StringName, fallback: float) -> HSlider:
	var row := GoStyle.row(GoUi.metric(GoTheme.GAP_SMALL))
	row.name = String(key).to_pascal_case() + "Row"
	column.add_child(row)

	var name_label := GoStyle.label(title, GoTheme.ROLE_BODY, GoUi.color(GoTheme.TEXT))
	name_label.name = "Label"
	name_label.custom_minimum_size.x = LABEL_WIDTH
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(name_label)

	var slider := GoStyle.slider(0.0, 1.0, SLIDER_STEP)
	slider.name = "Slider"
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var initial := clampf(_read_float(key, fallback), 0.0, 1.0)
	slider.set_value_no_signal(initial)
	row.add_child(slider)

	var percent := GoStyle.label(_format_percent(initial), GoTheme.ROLE_BODY, GoUi.color(GoTheme.MUTED))
	percent.name = "Percent"
	percent.custom_minimum_size.x = PERCENT_WIDTH
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(percent)

	slider.value_changed.connect(_on_slider_changed.bind(percent, key))
	return slider


func _add_resolution_row(column: VBoxContainer, fullscreen: bool) -> OptionButton:
	var sizes := _available_resolutions()
	var row := GoStyle.row(GoUi.metric(GoTheme.GAP_SMALL))
	row.name = "ResolutionRow"
	column.add_child(row)

	var row_label := GoStyle.label("窗口尺寸", GoTheme.ROLE_BODY, GoUi.color(GoTheme.TEXT))
	row_label.name = "Label"
	row_label.custom_minimum_size.x = LABEL_WIDTH
	row_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(row_label)

	var picker := GoStyle.select(_resolution_labels(sizes))
	picker.name = "Resolution"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.disabled = fullscreen
	var current := _read_window_size()
	for index in sizes.size():
		if sizes[index] == current:
			picker.select(index)
			break
	picker.item_selected.connect(_on_resolution_selected.bind(sizes))
	row.add_child(picker)
	return picker


func _available_resolutions() -> Array[Vector2i]:
	if _settings != null and _settings.has_method(&"available_resolutions"):
		var value: Variant = _settings.call(&"available_resolutions")
		if value is Array:
			var options: Array[Vector2i] = []
			for item: Variant in value:
				if item is Vector2i:
					options.append(item)
			if not options.is_empty():
				return options
	var fallback: Array[Vector2i] = [_read_window_size()]
	return fallback


func _resolution_labels(sizes: Array[Vector2i]) -> Array:
	var labels: Array = []
	for size in sizes:
		labels.append("%d × %d" % [size.x, size.y])
	return labels


func _read_window_size() -> Vector2i:
	if _settings != null and _settings.has_method(&"get_window_size"):
		var value: Variant = _settings.call(&"get_window_size")
		if value is Vector2i:
			return value
	return FALLBACK_WINDOW_SIZE


func _on_resolution_selected(index: int, sizes: Array[Vector2i]) -> void:
	if _settings == null or index < 0 or index >= sizes.size():
		return
	_settings.call(&"set_window_size", sizes[index])


func _on_slider_changed(value: float, percent: Label, key: StringName) -> void:
	percent.text = _format_percent(value)
	if _settings == null:
		return
	match key:
		&"master": _settings.call(&"set_master", value)
		&"music": _settings.call(&"set_music", value)
		&"sfx": _settings.call(&"set_sfx", value)


func _on_fullscreen_toggled(on: bool) -> void:
	if _resolution_picker != null:
		_resolution_picker.disabled = on
	if _resolution_hint != null:
		_resolution_hint.visible = on
	if _settings != null:
		_settings.call(&"set_fullscreen", on)


func _format_percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


func _read_float(key: StringName, fallback: float) -> float:
	if _settings == null:
		return fallback
	var value: Variant = _settings.get(key)
	if value is float or value is int:
		return float(value)
	return fallback


func _read_bool(key: StringName, fallback: bool) -> bool:
	if _settings == null:
		return fallback
	var value: Variant = _settings.get(key)
	if value is bool:
		return bool(value)
	return fallback


func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
