extends Control
## 净礼坛面板：净礼 / 疗愈 / 强化（三属性子选项）/ 离开。
## 点击选项调 GameState.altar_choice，成功后发 chosen(key, stat) 并关闭；
## 离开发 skipped。余额不足的按钮 disabled。

signal chosen(key: String, stat: String)
signal skipped

const UiStyle := preload("res://ui/panels/UiStyle.gd")

@onready var _balance: Label = $Center/Panel/Margin/VBox/Balance
@onready var _purify_btn: Button = $Center/Panel/Margin/VBox/PurifyBtn
@onready var _heal_btn: Button = $Center/Panel/Margin/VBox/HealBtn
@onready var _enhance_btn: Button = $Center/Panel/Margin/VBox/EnhanceBtn
@onready var _enhance_box: VBoxContainer = $Center/Panel/Margin/VBox/EnhanceBox
@onready var _power_btn: Button = $Center/Panel/Margin/VBox/EnhanceBox/PowerBtn
@onready var _hp_btn: Button = $Center/Panel/Margin/VBox/EnhanceBox/HpBtn
@onready var _speed_btn: Button = $Center/Panel/Margin/VBox/EnhanceBox/SpeedBtn
@onready var _leave_btn: Button = $Center/Panel/Margin/VBox/LeaveBtn


func _ready() -> void:
	UiStyle.style_panel($Center/Panel)
	UiStyle.style_label($Center/Panel/Margin/VBox/Title, 22)
	UiStyle.style_label(_balance, 14, UiStyle.GOLD)
	for btn in [_purify_btn, _heal_btn, _enhance_btn, _leave_btn]:
		UiStyle.style_button(btn)
	for btn in [_power_btn, _hp_btn, _speed_btn]:
		UiStyle.style_button(btn, 14)
	_purify_btn.pressed.connect(_try_choice.bind("purify", ""))
	_heal_btn.pressed.connect(_try_choice.bind("heal", ""))
	_enhance_btn.pressed.connect(func() -> void:
		_enhance_box.visible = not _enhance_box.visible)
	_power_btn.pressed.connect(_try_choice.bind("enhance", "power"))
	_hp_btn.pressed.connect(_try_choice.bind("enhance", "hp"))
	_speed_btn.pressed.connect(_try_choice.bind("enhance", "speed"))
	_leave_btn.pressed.connect(func() -> void:
		skipped.emit()
		hide())
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible:
		UiStyle.enter_anim(self, [_purify_btn, _heal_btn, _enhance_btn, _leave_btn])
	else:
		UiStyle.exit_anim(self)


func open() -> void:
	_enhance_box.hide()
	_refresh()
	show()


func _refresh() -> void:
	var ichor: int = int(GameState.run.get("ichor", 0))
	_balance.text = "Ichor 余额：%d" % ichor
	_purify_btn.disabled = ichor < int(Data.economy.altar.purify.cost)
	_heal_btn.disabled = ichor < int(Data.economy.altar.heal.cost)
	var enhance_cost: int = int(Data.economy.altar.enhance.cost)
	_enhance_btn.disabled = ichor < enhance_cost
	_power_btn.disabled = ichor < enhance_cost
	_hp_btn.disabled = ichor < enhance_cost
	_speed_btn.disabled = ichor < enhance_cost


func _try_choice(key: String, stat: String) -> void:
	if GameState.altar_choice(key, stat):
		chosen.emit(key, stat)
		hide()
	else:
		_refresh()