extends RefCounted
## UI 面板共享几何风格：深色底 #14141c 系、白字、细边框按钮，无贴图无音频。

const BG := Color("#14141c")
const PANEL := Color("#1b1b26")
const CARD := Color("#20202e")
const CARD_HOVER := Color("#2a2a3c")
const CARD_PRESSED := Color("#32324a")
const CARD_DISABLED := Color("#191922")
const BORDER := Color("#4a4a60")
const BORDER_DIM := Color("#33333f")
const TEXT := Color("#f2f2f7")
const DIM := Color("#9a9ab2")
const DISABLED_TEXT := Color("#5a5a70")
const RED := Color("#e05555")
const GOLD := Color("#e8c05a")
const HP_FILL := Color("#6fcf7f")
const CORRUPT_FILL := Color("#a05be0")

const RARITY_NAMES := {
	"common": "凡", "rare": "灵", "divine": "神", "artifact": "神器",
}
const RARITY_COLORS := {
	"common": Color("#f2f2f7"),
	"rare": Color("#5b8dd9"),
	"divine": Color("#a06be0"),
	"artifact": Color("#e8c05a"),
}


static func flat_box(bg: Color, border: Color = BORDER, radius: int = 4,
		border_w: int = 1, margin_h: int = 0, margin_v: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


static func style_button(btn: Button, font_size: int = 15) -> void:
	var lk := TaLook.current()
	btn.add_theme_stylebox_override("normal", flat_box(lk.color_card, lk.color_border, lk.radius, 1, 12, 8))
	btn.add_theme_stylebox_override("hover", flat_box(lk.color_surface_hover, lk.color_accent, lk.radius, 1, 12, 8))
	btn.add_theme_stylebox_override("pressed", flat_box(lk.color_surface_pressed, lk.color_accent, lk.radius, 1, 12, 8))
	btn.add_theme_stylebox_override("disabled", flat_box(lk.color_disabled_bg, BORDER_DIM, lk.radius, 1, 12, 8))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", lk.color_text)
	btn.add_theme_color_override("font_hover_color", lk.color_text)
	btn.add_theme_color_override("font_pressed_color", lk.color_text)
	btn.add_theme_color_override("font_disabled_color", lk.color_disabled_text)
	btn.add_theme_font_size_override("font_size", font_size)
	if not btn.has_meta("_ui_press"):
		btn.set_meta("_ui_press", true)
		btn.pivot_offset = btn.size * 0.5
		btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
		btn.button_down.connect(func() -> void:
			press_bounce(btn)
			AudioManager.play_sfx("ui_click"))


static func press_bounce(btn: Button) -> void:
	if btn.has_meta("_ui_press_tween"):
		var old := btn.get_meta("_ui_press_tween") as Tween
		if old != null and old.is_valid():
			old.kill()
	btn.pivot_offset = btn.size * 0.5
	btn.scale = Vector2(0.96, 0.96)
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	btn.set_meta("_ui_press_tween", tw)


static func enter_anim(control: Control, items: Array = []) -> void:
	exit_anim(control)
	var base: Vector2 = control.position
	control.set_meta("_ui_base_pos", base)
	control.set_meta("_ui_items", items)
	control.modulate.a = 0.0
	control.position = base + Vector2(0.0, 16.0)
	var tw := control.create_tween()
	tw.set_parallel(true)
	tw.tween_property(control, "modulate:a", 1.0, 0.18)
	tw.tween_property(control, "position:y", base.y, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i in items.size():
		if not is_instance_valid(items[i]) or not items[i] is Control:
			continue
		var item := items[i] as Control
		item.modulate.a = 0.0
		tw.tween_property(item, "modulate:a", 1.0, 0.12).set_delay(0.05 * float(i))
	control.set_meta("_ui_tween", tw)


static func exit_anim(control: Control) -> void:
	if control.has_meta("_ui_tween"):
		var tw := control.get_meta("_ui_tween") as Tween
		if tw != null and tw.is_valid():
			tw.kill()
		control.remove_meta("_ui_tween")
	if control.has_meta("_ui_base_pos"):
		control.position = control.get_meta("_ui_base_pos") as Vector2
		control.remove_meta("_ui_base_pos")
	control.modulate = Color.WHITE
	if control.has_meta("_ui_items"):
		var items: Array = control.get_meta("_ui_items") as Array
		for item in items:
			if is_instance_valid(item) and item is Control:
				var c := item as Control
				c.modulate = Color.WHITE
				c.scale = Vector2.ONE
		control.remove_meta("_ui_items")


static func style_panel(panel: PanelContainer) -> void:
	var lk := TaLook.current()
	panel.add_theme_stylebox_override("panel", flat_box(lk.color_panel, lk.color_border, lk.radius, 1))


static func style_label(label: Label, font_size: int = 15, color: Color = TEXT) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func style_progress(bar: ProgressBar, fill: Color) -> void:
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", flat_box(Color("#26263a"), BORDER_DIM, 3, 1))
	bar.add_theme_stylebox_override("fill", flat_box(fill, fill, 3, 0))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func make_label(text: String, font_size: int = 15, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	style_label(label, font_size, color)
	return label