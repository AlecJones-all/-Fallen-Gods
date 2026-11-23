extends CanvasLayer
## 战斗顶部 80px HUD 横条：HP 条+数字、Ichor 数、污秽条+档位名、波次标签。
## 监听 EventBus 自动刷新，也提供 refresh()；显隐由外部控制。

const UiStyle := preload("res://ui/panels/UiStyle.gd")
const Icons := preload("res://ui/panels/Icons.gd")

@onready var _hp_bar: ProgressBar = $Bar/Margin/VBox/Row1/HpWrap/HpBar
@onready var _hp_label: Label = $Bar/Margin/VBox/Row1/HpWrap/HpLabel
@onready var _ichor_label: Label = $Bar/Margin/VBox/Row1/IchorLabel
@onready var _wave_label: Label = $Bar/Margin/VBox/Row1/WaveLabel
@onready var _corrupt_bar: ProgressBar = $Bar/Margin/VBox/Row2/CorruptWrap/CorruptBar
@onready var _tier_label: Label = $Bar/Margin/VBox/Row2/TierLabel

var _hp_tween: Tween = null
var _hp_max := 100.0
var _corrupt_tween: Tween = null
var _pulse_tween: Tween = null
var _wave_tween: Tween = null


func _ready() -> void:
	UiStyle.style_progress(_hp_bar, UiStyle.HP_FILL)
	UiStyle.style_progress(_corrupt_bar, UiStyle.CORRUPT_FILL)
	_corrupt_bar.max_value = float(Data.tuning.corruption.max)
	UiStyle.style_label(_hp_label, 12)
	UiStyle.style_label(_ichor_label, 15, UiStyle.GOLD)
	UiStyle.style_label(_wave_label, 14)
	UiStyle.style_label(_tier_label, 13, UiStyle.DIM)
	# 生命/Ichor 标识前 16×16 图标（scale2）；缺失时占位 0 不显示
	var row: HBoxContainer = $Bar/Margin/VBox/Row1
	var hp_icon := Icons.make_icon("hp")
	row.add_child(hp_icon)
	row.move_child(hp_icon, 0)
	var ichor_icon := Icons.make_icon("ichor")
	row.add_child(ichor_icon)
	row.move_child(ichor_icon, _ichor_label.get_index())
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.ichor_changed.connect(_on_ichor_changed)
	EventBus.corruption_changed.connect(_on_corruption_changed)
	EventBus.corruption_tier_changed.connect(_on_tier_pulse)
	refresh()


func set_wave(text: String) -> void:
	_wave_label.text = text
	_wave_label.pivot_offset = _wave_label.size * 0.5
	if _wave_tween != null and _wave_tween.is_valid():
		_wave_tween.kill()
	_wave_label.scale = Vector2(1.2, 1.2)
	_wave_tween = create_tween()
	_wave_tween.tween_property(_wave_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func refresh() -> void:
	if GameState.run.is_empty():
		return
	_on_hp_changed(float(GameState.run.hp), float(GameState.final_stats().hp))
	_on_ichor_changed(int(GameState.run.ichor))
	_on_corruption_changed(float(GameState.run.corruption))


func _on_hp_changed(hp: float, max_hp: float) -> void:
	_hp_bar.max_value = maxf(max_hp, 1.0)
	_hp_max = max_hp
	var target := maxf(hp, 0.0)
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = create_tween().set_parallel(true)
	_hp_tween.tween_property(_hp_bar, "value", target, 0.25)
	_hp_tween.tween_method(_update_hp_text, _hp_bar.value, target, 0.25)


func _update_hp_text(value: float) -> void:
	_hp_label.text = "%d / %d" % [ceili(maxf(value, 0.0)), ceili(_hp_max)]


func _on_ichor_changed(total: int) -> void:
	_ichor_label.text = "Ichor %d" % total


func _on_corruption_changed(value: float) -> void:
	if _corrupt_tween != null and _corrupt_tween.is_valid():
		_corrupt_tween.kill()
	_corrupt_tween = create_tween()
	_corrupt_tween.tween_property(_corrupt_bar, "value", value, 0.25)
	var tier: int = clampi(GameState.corruption_tier(), 0, Data.tuning.corruption.tier_names.size() - 1)
	_tier_label.text = "污秽 %d · %s" % [int(value), str(Data.tuning.corruption.tier_names[tier])]


func _on_tier_pulse(tier: int) -> void:
	if tier < 1:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_corrupt_bar.modulate = Color.WHITE
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_corrupt_bar, "modulate", Color(1.8, 1.3, 2.2, 1.0), 0.08)
	_pulse_tween.tween_property(_corrupt_bar, "modulate", Color.WHITE, 0.35)