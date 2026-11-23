extends Control
## 结算商店：打开时自动合成神器（金色提示），新武器抽 1、已拥有武器升级、属性点。
## 「继续」发 closed。每次操作后刷新全部按钮状态。

signal closed

const UiStyle := preload("res://ui/panels/UiStyle.gd")
const Icons := preload("res://ui/panels/Icons.gd")

const KIND_NAMES := { "ranged": "远程", "melee": "近战", "shield": "护盾" }
const EFFECT_NAMES := {
	"burn": "灼烧", "pierce": "穿透", "chain": "连锁闪电",
	"knockback_px": "击退", "reflect_enemy_bullets": "反弹敌弹",
	"bounce_radius_mult": "扩大弹球判定", "cleanse_on_ball": "弹球净秽",
	"lifesteal": "吸血", "speed_variance": "变速弹道", "split": "分裂",
}

var _offer_id: String = ""
var _shards_label: Label = null
var _offer_icon: Control = null

@onready var _settle: Label = $Center/Panel/Margin/VBox/Settle
@onready var _forge: Label = $Center/Panel/Margin/VBox/Forge
@onready var _balance: Label = $Center/Panel/Margin/VBox/Balance
@onready var _offer_name: Label = $Center/Panel/Margin/VBox/Scroll/List/OfferName
@onready var _offer_desc: Label = $Center/Panel/Margin/VBox/Scroll/List/OfferDesc
@onready var _buy_btn: Button = $Center/Panel/Margin/VBox/Scroll/List/BuyBtn
@onready var _weapons: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/List/Weapons
@onready var _power_btn: Button = $Center/Panel/Margin/VBox/Scroll/List/Stats/PowerBtn
@onready var _hp_btn: Button = $Center/Panel/Margin/VBox/Scroll/List/Stats/HpBtn
@onready var _speed_btn: Button = $Center/Panel/Margin/VBox/Scroll/List/Stats/SpeedBtn
@onready var _continue_btn: Button = $Center/Panel/Margin/VBox/ContinueBtn


func _ready() -> void:
	UiStyle.style_panel($Center/Panel)
	UiStyle.style_label($Center/Panel/Margin/VBox/Title, 22)
	UiStyle.style_label(_settle, 13, UiStyle.DIM)
	UiStyle.style_label(_forge, 15, UiStyle.GOLD)
	UiStyle.style_label(_balance, 15, UiStyle.GOLD)
	for title in ["NewWeaponTitle", "WeaponsTitle", "StatsTitle"]:
		UiStyle.style_label(get_node("Center/Panel/Margin/VBox/Scroll/List/" + title) as Label, 14, UiStyle.DIM)
	UiStyle.style_label(_offer_name, 17)
	UiStyle.style_label(_offer_desc, 13, UiStyle.DIM)
	for btn in [_buy_btn, _power_btn, _hp_btn, _speed_btn, _continue_btn]:
		UiStyle.style_button(btn, 14)
	_buy_btn.pressed.connect(_on_buy_weapon)
	_power_btn.pressed.connect(_on_buy_stat.bind("power"))
	_hp_btn.pressed.connect(_on_buy_stat.bind("hp"))
	_speed_btn.pressed.connect(_on_buy_stat.bind("speed"))
	_continue_btn.pressed.connect(func() -> void:
		closed.emit()
		hide())
	_setup_icon_rows()
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible:
		UiStyle.enter_anim(self, [_buy_btn, _power_btn, _hp_btn, _speed_btn, _continue_btn])
	else:
		UiStyle.exit_anim(self)


## Ichor/残片余额行与_new weapon offer 行前置 16×16 图标（scale2）；缺失不显示不报错。
func _setup_icon_rows() -> void:
	var vbox := _balance.get_parent() as VBoxContainer
	var bidx := _balance.get_index()
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 6)
	vbox.add_child(brow)
	vbox.move_child(brow, bidx)
	brow.add_child(Icons.make_icon("ichor"))
	_balance.reparent(brow, false)
	brow.add_child(Icons.make_icon("shards"))
	_shards_label = UiStyle.make_label("", 15, UiStyle.GOLD)
	brow.add_child(_shards_label)

	var list := _offer_name.get_parent() as VBoxContainer
	var oidx := _offer_name.get_index()
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 8)
	list.add_child(orow)
	list.move_child(orow, oidx)
	_offer_icon = Icons.make_icon("")
	orow.add_child(_offer_icon)
	_offer_name.reparent(orow, false)
	_offer_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func open(settlement: Dictionary) -> void:
	var forged: Array = GameState.forge_artifacts()
	if forged.is_empty():
		_forge.hide()
	else:
		var names := PackedStringArray()
		for card_name in forged:
			names.append(str(card_name))
		_forge.text = "神器合成：" + "、".join(names)
		_forge.show()
	var gained: int = int(settlement.get("ichor", 0))
	var suffix := "（含首通 +50）" if settlement.get("first_clear", false) else ""
	_settle.text = "本关结算 +%d Ichor%s" % [gained, suffix]
	_pick_offer()
	_refresh()
	show()


func _pick_offer() -> void:
	var candidates: Array = []
	for card_id in Data.cards:
		if not (card_id in GameState.meta.weapons):
			candidates.append(card_id)
	if candidates.is_empty():
		_offer_id = ""
		_offer_name.text = "武器已集齐"
		_offer_desc.text = ""
	else:
		_offer_id = candidates[randi() % candidates.size()]
		var card: Dictionary = Data.cards[_offer_id]
		_offer_name.text = str(card.name)
		_offer_desc.text = _card_desc(card)
	Icons.set_icon(_offer_icon, _offer_id)


func _card_desc(card: Dictionary) -> String:
	var faction := "秩序" if card.get("faction", "") == "order" else "混沌"
	var kind: String = KIND_NAMES.get(card.get("kind", ""), str(card.get("kind", "")))
	var text := "%s · %s ｜ 伤害 %d ｜ 攻速 %.1f" % [
		faction, kind, int(card.get("base_damage", 0)), float(card.get("attack_speed", 0.0))]
	var effects: Array = []
	for key in card.get("effects", {}):
		if EFFECT_NAMES.has(key):
			effects.append(EFFECT_NAMES[key])
	if not effects.is_empty():
		text += " ｜ " + "、".join(PackedStringArray(effects))
	var corruption: int = int(card.get("corruption_per_hit", 0))
	if corruption > 0:
		text += " ｜ 命中污秽 +%d" % corruption
	return text


func _on_buy_weapon() -> void:
	if _offer_id.is_empty():
		return
	var bought_id := _offer_id
	if GameState.buy_weapon(bought_id):
		_offer_id = ""
		_offer_name.text = "已购入 · %s" % str(Data.cards[bought_id].name)
		_offer_desc.text = ""
	_refresh()


func _on_buy_stat(stat: String) -> void:
	GameState.buy_stat_point(stat)
	_refresh()


func _on_upgrade(card_id: String) -> void:
	GameState.upgrade_weapon(card_id)
	_refresh()


func _refresh() -> void:
	var ichor: int = int(GameState.run.get("ichor", 0))
	_balance.text = "Ichor：%d" % ichor
	_shards_label.text = "残片：%d" % int(GameState.meta.shards)
	_buy_btn.disabled = _offer_id.is_empty() or ichor < int(Data.economy.shop.new_weapon)
	var stat_cost: int = int(Data.economy.shop.stat_point)
	_power_btn.disabled = ichor < stat_cost
	_hp_btn.disabled = ichor < stat_cost
	_speed_btn.disabled = ichor < stat_cost
	_rebuild_weapons(ichor)


func _rebuild_weapons(ichor: int) -> void:
	for child in _weapons.get_children():
		_weapons.remove_child(child)
		child.queue_free()
	for card_id in GameState.meta.weapons:
		_weapons.add_child(_make_weapon_row(card_id, ichor))


func _make_weapon_row(card_id: String, ichor: int) -> HBoxContainer:
	var card: Dictionary = Data.cards[card_id]
	var rarity: String = str(GameState.meta.weapons[card_id])
	var color: Color = UiStyle.RARITY_COLORS.get(rarity, UiStyle.TEXT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	row.add_child(Icons.make_icon(card_id))

	var name_label := UiStyle.make_label(str(card.name), 15, color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var rarity_label := UiStyle.make_label(
		"[%s]" % str(UiStyle.RARITY_NAMES.get(rarity, rarity)), 14, color)
	rarity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(rarity_label)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(118, 38)
	UiStyle.style_button(btn, 13)
	match rarity:
		"common":
			var cost: int = int(Data.economy.shop.upgrade_common_to_rare)
			btn.text = "升灵 · %d" % cost
			btn.disabled = ichor < cost
			btn.pressed.connect(_on_upgrade.bind(card_id))
		"rare":
			var cost: int = int(Data.economy.shop.upgrade_rare_to_divine)
			btn.text = "升神 · %d" % cost
			btn.disabled = ichor < cost
			btn.pressed.connect(_on_upgrade.bind(card_id))
		"divine":
			if card.get("faction", "") == "order":
				btn.text = "待残片合成"
			else:
				btn.text = "已满级"
			btn.disabled = true
		_:
			btn.text = "已满级"
			btn.disabled = true
	row.add_child(btn)
	return row