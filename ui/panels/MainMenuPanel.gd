extends Control
## 主菜单：标题 + 副标题 + 第1关 Demo / 继续进度 / 重试入口 + 当前七境名。
## Demo 只请求当前局进入第1关，绝不改写永久存档。

signal start_requested
signal demo_requested

const UiStyle := preload("res://ui/panels/UiStyle.gd")

@onready var _start_btn: Button = $Center/VBox/StartBtn
@onready var _demo_btn: Button = $Center/VBox/DemoBtn
@onready var _realm_label: Label = $Center/VBox/RealmLabel


func _ready() -> void:
	UiStyle.style_label($Center/VBox/Title, 32)
	UiStyle.style_label($Center/VBox/Subtitle, 14, UiStyle.DIM)
	UiStyle.style_label(_realm_label, 13, UiStyle.DIM)
	UiStyle.style_button(_start_btn, 18)
	UiStyle.style_button(_demo_btn, 18)
	_start_btn.pressed.connect(func() -> void: start_requested.emit())
	_demo_btn.pressed.connect(func() -> void: demo_requested.emit())
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible:
		UiStyle.enter_anim(self, $Center/VBox.get_children())
	else:
		UiStyle.exit_anim(self)


func set_mode(retry: bool) -> void:
	_demo_btn.visible = not retry
	if retry:
		_start_btn.text = "重试当前关"
	else:
		_start_btn.text = "继续 · 第%d关" % int(GameState.meta.unlocked_level)
	var realm_index: int = clampi(int(GameState.meta.realm), 1, Data.realms.size())
	var realm: Dictionary = Data.realms[realm_index - 1]
	_realm_label.text = "七境 · %s（%s）" % [str(realm.name), str(realm.greek)]
