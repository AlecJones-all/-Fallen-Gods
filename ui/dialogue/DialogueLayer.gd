extends CanvasLayer
## 对话演出层：底部半透明对话框（说话人+正文，点击/空格推进），
## 已读节点显示「跳过」；顶部恐怖飘字 1.5s 淡出，非阻塞。
## 几何风格（ColorRect+Label），无贴图无音频。
## 契约：GameState.meta.read_story / mark_story_read；EventBus.story_node_started/finished。

signal finished

const TEXT_COLOR := Color("#f2f2f7")
const DIM_COLOR := Color("#9a9ab2")
const GOLD_COLOR := Color("#e8c05a")
const BOX_COLOR := Color(0.02, 0.02, 0.04, 0.78)
const BORDER_COLOR := Color("#4a4a60")
const BTN_COLOR := Color("#20202e")
const BTN_HOVER := Color("#2a2a3c")
const STING_COLOR := Color("#c9b8e8")

var _root: Control
var _speaker_label: Label
var _text_label: Label
var _skip_btn: Button
var _sting_holder: Control

var _node_id := ""
var _lines: Array = []
var _index := 0
var _playing := false
var _typing := false
var _type_tween: Tween = null

const CHARS_PER_SEC := 30.0


func _ready() -> void:
	layer = 30
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "DialogueRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	_root.gui_input.connect(_on_root_gui_input)

	# 底部对话框：覆盖下半屏，半透明黑，战场在上方仍可见。
	var box := ColorRect.new()
	box.name = "Box"
	box.color = BOX_COLOR
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.anchor_top = 0.5
	box.offset_top = 0.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	var top_line := ColorRect.new()
	top_line.color = BORDER_COLOR
	top_line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_line.offset_bottom = 2.0
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top_line)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 18)
	_speaker_label.add_theme_color_override("font_color", GOLD_COLOR)
	_speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_speaker_label)

	_skip_btn = Button.new()
	_skip_btn.text = "跳过"
	_skip_btn.visible = false
	_skip_btn.add_theme_font_size_override("font_size", 14)
	_skip_btn.add_theme_color_override("font_color", DIM_COLOR)
	_skip_btn.add_theme_color_override("font_hover_color", TEXT_COLOR)
	_skip_btn.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BTN_COLOR
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_skip_btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = BTN_HOVER
	_skip_btn.add_theme_stylebox_override("hover", sb_hover)
	_skip_btn.add_theme_stylebox_override("pressed", sb_hover)
	_skip_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_skip_btn.pressed.connect(skip)
	head.add_child(_skip_btn)

	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 17)
	_text_label.add_theme_color_override("font_color", TEXT_COLOR)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_text_label)

	var hint := Label.new()
	hint.text = "点击 / 空格 继续"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", DIM_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)

	# 飘字挂点：常驻、不拦截任何输入。
	_sting_holder = Control.new()
	_sting_holder.name = "StingHolder"
	_sting_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sting_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sting_holder)


## 播放一段剧情节点。lines = [{"speaker": String, "text": String}, ...]
func play(node_id: String, lines: Array) -> void:
	if _playing:
		_finish()
	_node_id = node_id
	_lines = lines
	_index = 0
	EventBus.story_node_started.emit(node_id)
	if lines.is_empty():
		_finish()
		return
	_playing = true
	_skip_btn.visible = node_id in GameState.meta.read_story
	_root.visible = true
	_show_line()


func is_playing() -> bool:
	return _playing


## 推进一句；末句后自动结束。
func advance() -> void:
	if not _playing:
		return
	if _typing:
		_complete_line()
		return
	_index += 1
	if _index >= _lines.size():
		_finish()
	else:
		_show_line()


## 跳过整段（仅已读节点显示按钮，但接口始终可用）。
func skip() -> void:
	if _playing:
		_finish()


## 顶部居中恐怖飘字，1.5s 淡出，非阻塞。
func show_sting(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", STING_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sting_holder.add_child(label)
	label.anchor_right = 1.0
	label.offset_top = 72.0
	label.offset_bottom = 102.0
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(0.85)
	tw.tween_property(label, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(label.queue_free)


func _show_line() -> void:
	var line: Dictionary = _lines[_index]
	_speaker_label.text = str(line.get("speaker", ""))
	var full := str(line.get("text", ""))
	_text_label.text = full
	_kill_typing()
	_text_label.visible_characters = 0
	_typing = true
	_type_tween = create_tween()
	_type_tween.tween_property(_text_label, "visible_characters", full.length(), float(full.length()) / CHARS_PER_SEC)
	_type_tween.tween_callback(_line_typed)


func _line_typed() -> void:
	_typing = false


func _kill_typing() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = null


func _complete_line() -> void:
	_kill_typing()
	_typing = false
	_text_label.visible_characters = -1


func _finish() -> void:
	_kill_typing()
	_typing = false
	_text_label.visible_characters = -1
	_playing = false
	_root.visible = false
	GameState.mark_story_read(_node_id)
	EventBus.story_node_finished.emit(_node_id)
	finished.emit()


func _on_root_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		advance()


func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			advance()
			get_viewport().set_input_as_handled()