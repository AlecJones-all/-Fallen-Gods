extends Control
## 波次间三选一构筑面板：全屏半透明遮罩 + 居中面板，3 张选项卡。
## 点击卡片发 chosen(option) 后隐藏；显隐由外部（导演层）控制。

signal chosen(option: Dictionary)

const UiStyle := preload("res://ui/panels/UiStyle.gd")
const Icons := preload("res://ui/panels/Icons.gd")

@onready var _cards: VBoxContainer = $Center/Panel/Margin/VBox/Cards


func _ready() -> void:
	UiStyle.style_panel($Center/Panel)
	UiStyle.style_label($Center/Panel/Margin/VBox/Title, 22)
	UiStyle.style_label($Center/Panel/Margin/VBox/Hint, 13, UiStyle.DIM)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible:
		UiStyle.enter_anim(self, _cards.get_children())
	else:
		UiStyle.exit_anim(self)


func show_choices(options: Array) -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	for option in options:
		_cards.add_child(_make_card(option))
	show()


func _make_card(option: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(376, 108)
	UiStyle.style_button(btn)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 14.0
	vbox.offset_top = 8.0
	vbox.offset_right = -14.0
	vbox.offset_bottom = -8.0
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 3)
	btn.add_child(vbox)

	# 卡面图标 + 名称同行居中（图标读 icons.json：cards/builds 映射，缺失不显示）
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(Icons.make_icon(str(option.get("id", ""))))
	head.add_child(UiStyle.make_label(str(option.get("name", "")), 18))
	vbox.add_child(head)
	var desc := UiStyle.make_label(str(option.get("desc", "")), 13, UiStyle.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var cost: float = float(option.get("corruption_cost", 0))
	if cost > 0.0:
		vbox.add_child(UiStyle.make_label("污秽 +%d" % int(cost), 13, UiStyle.RED))

	btn.pressed.connect(func() -> void:
		chosen.emit(option)
		hide())
	return btn