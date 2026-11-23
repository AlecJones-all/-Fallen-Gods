extends RefCounted

# AGENT: TaStyle's drawing half (core seam). One target: its boxes, its own text colours,
# and the text Theme for what it holds. TaStyle decides what to paint; this paints it.
# INVARIANT: Boxes come from TaChrome by the look box's recipe (TaChrome.SPEC_META), with
# the look box's padding. A box the item hid (StyleBoxEmpty) or keeps as its own colour
# (TaStyle.KEEP_META) is left alone. Text a style does not colour reads at 4.5:1 on the face
# it sits on; semantic labels (danger, success, warning) keep their tone, picked to read.
# DO NOT: Read TaLook (the look is passed in). Touch a node TaStyle did not hand over.

enum Mode {
	## A styled surface: its boxes, its own text, and the text of what it holds.
	ITEM,
	## A gauge inside an item (a TaBar's bar): track and fill.
	BAR,
	## A title bar inside an item: the item's fill under an accent stripe, and its title.
	HEADER,
	## A row, grid, strip, feed, or host: no box; its labels take the style's text if set.
	ROW,
}

const STYLE_META := &"ta_style"
const OWNER_META := &"ta_style_owner"
const BOXES_META := &"ta_style_boxes"
const INKS_META := &"ta_style_inks"
const THEME_META := &"ta_style_theme"
const TEXT_META := &"ta_style_text"
const RESTORE_META := &"ta_style_restore"
const CLEAR := Color(0, 0, 0, 0)
## Title bars inside windows, header panels, dialogs, and modals.
const HEADERS: Array[StringName] = [&"TaWindowTitleBar", &"TaHeaderBar", &"TaDialogHeader"]
## How far an unset hover face moves toward its text, and how much an unset pressed face
## darkens. Muted text sits this far from the ink toward the fill, where it still reads.
const _HOVER_MIX := 0.12
const _PRESS_DARKEN := 0.18
const _QUIET_MIX := 0.35
const _ACCENT_ITEMS: Array[StringName] = [&"fill", &"grabber_area", &"grabber_area_highlight"]
const _TRACK_ITEMS: Array[StringName] = [&"background", &"slider"]
const _HOVER_ITEMS: Array[StringName] = [&"hover", &"tab_hovered", &"hovered"]
const _PRESS_ITEMS: Array[StringName] = [&"pressed", &"hover_pressed", &"tab_unselected"]
const _SELECT_ITEMS: Array[StringName] = [&"selected", &"selected_focus"]
## Boxes whose line is the hot one: hovered, pressed, or selected.
const _HOT_ITEMS: Array[StringName] = [
	&"hover", &"pressed", &"hover_pressed", &"tab_hovered", &"tab_selected", &"hovered",
	&"selected", &"selected_focus",
]
## Label types inside a styled item that take its text colour (body), or its quiet one.
const _BODY_TYPES: Array[StringName] = [&"Label", &"TaCardText", &"TaTitle", &"TaBold", &"TaItalic"]
const _QUIET_TYPES: Array[StringName] = [&"TaCardCaption", &"TaCaption"]
## Semantic labels keep their meaning on a styled fill: the look's tone, picked to read there.
const _TONE_TYPES := {
	&"TaDangerLabel": &"color_danger", &"TaSuccessLabel": &"color_success",
	&"TaWarningLabel": &"color_warning",
}


## Controls (and popups) that draw their own boxes; anything else is a row or a label.
static func is_surface(node: Node) -> bool:
	return (
			node is Button or node is PanelContainer or node is Panel or node is ProgressBar
			or node is Slider or node is LineEdit or node is TextEdit or node is TabContainer
			or node is TabBar or node is ItemList or node is Tree or node is PopupPanel
	)


## Draw `style` on one target. True when a box was made for another look family than
## `look` (the look around the item is not known yet): that box keeps what it had.
static func paint(target: Node, mode: Mode, style: TaStyle, look: TaTokens) -> bool:
	var old: Dictionary = target.get_meta(BOXES_META, {})
	var boxes := {}
	var faces := {}
	var stale := false
	var drawn := items(target, mode)
	target.begin_bulk_theme_override()
	for item in drawn:
		var src := theme_box(target, item)
		if src == null:
			continue
		var current := _override(target, item)
		var hidden := current is StyleBoxEmpty or (
				current != null and current.has_meta(TaStyle.KEEP_META)
		)
		if hidden and current != old.get(item):
			continue
		var f := _face(item, target, mode, style, look, src)
		faces[item] = f
		var l := _line(item, mode, style, look, src)
		var w := -1 if _ACCENT_ITEMS.has(item) or mode == Mode.HEADER else style.line_width
		if f.a <= 0.0 and l.a <= 0.0 and w < 0:
			continue
		var spec: Dictionary = src.get_meta(TaChrome.SPEC_META, {})
		if not spec.is_empty() and bool(spec["pixel"]) != look.is_pixel():
			stale = true
			if old.has(item):
				boxes[item] = old[item]
			continue
		var box := redraw(src, f, l, w, look)
		if box != null:
			target.add_theme_stylebox_override(item, box)
			boxes[item] = box
	for item in old:
		if not boxes.has(item) and _override(target, item) == old[item]:
			target.remove_theme_stylebox_override(item)
	target.set_meta(BOXES_META, boxes)
	_paint_inks(target, mode, style, look, faces)
	target.end_bulk_theme_override()
	if mode != Mode.BAR:
		var main: Color = faces.get(drawn[0], CLEAR) if not drawn.is_empty() else CLEAR
		_paint_text(target, mode, style, look, main)
	return stale


## Remove everything paint() put on `target`.
static func unpaint(target: Node) -> void:
	# A selected slot holds the style's face under its pressed one; let it go first.
	var reselect: bool = "selected" in target and target.get("selected") == true
	if reselect:
		target.set("selected", false)
	var boxes: Dictionary = target.get_meta(BOXES_META, {})
	target.begin_bulk_theme_override()
	for item in boxes:
		if _override(target, item) == boxes[item]:
			target.remove_theme_stylebox_override(item)
	for item: StringName in target.get_meta(INKS_META, []):
		target.remove_theme_color_override(item)
	target.end_bulk_theme_override()
	_unrestore(target)
	var ours := own_theme(target)
	if ours != null and target.get("theme") == ours:
		target.set("theme", null)
	for meta in [BOXES_META, INKS_META, THEME_META, TEXT_META, OWNER_META]:
		target.remove_meta(meta)
	if reselect:
		target.set("selected", true)


## The boxes a style paints on `target`, the main one first.
static func items(target: Node, mode: Mode) -> Array[StringName]:
	match mode:
		Mode.BAR:
			return [&"background", &"fill"]
		Mode.HEADER:
			return [&"panel"]
		Mode.ROW:
			return []
	if target is Button:
		return [&"normal", &"hover", &"pressed", &"hover_pressed"]
	if target is ProgressBar:
		return [&"background", &"fill"]
	if target is Slider:
		return [&"slider", &"grabber_area", &"grabber_area_highlight"]
	if target is LineEdit or target is TextEdit:
		return [&"normal", &"read_only"]
	if target is TabContainer:
		return [&"panel", &"tab_selected", &"tab_unselected", &"tab_hovered"]
	if target is TabBar:
		return [&"tab_selected", &"tab_unselected", &"tab_hovered"]
	if target is ItemList or target is Tree:
		return [&"panel", &"selected", &"selected_focus", &"hovered"]
	if target is PanelContainer or target is Panel or target is PopupPanel:
		return [&"panel"]
	return []


## The face one box shows; alpha 0 keeps the look's. Tracks take `track` (a bar or slider
## styled on its own falls back to `fill`); a box the look fills with its accent (a
## selected card, row, or tab) takes the style's accent.
static func _face(
		item: StringName, target: Node, mode: Mode, style: TaStyle, look: TaTokens,
		src: StyleBox
	) -> Color:
	if _ACCENT_ITEMS.has(item):
		return style.accent
	if _TRACK_ITEMS.has(item):
		if style.track.a <= 0.0 and mode == Mode.ITEM:
			return style.fill
		return style.track
	var f := style.fill
	if _HOVER_ITEMS.has(item):
		f = hover_of(style, look)
	elif _PRESS_ITEMS.has(item):
		f = pressed_of(style)
	elif _SELECT_ITEMS.has(item):
		f = style.fill_pressed
	# A card the kit marks on (TaShopCardOn, TaHighlightCellOn) stays marked: the style's
	# accent, else its pressed face, else the look's mark.
	var marked := item == &"panel" and String(target.get("theme_type_variation")).ends_with("On")
	if marked or _was_accent(src, look):
		if style.accent.a > 0.0:
			return style.accent
		if marked and style.fill_pressed.a > 0.0:
			return style.fill_pressed
		return f if target is Button else CLEAR
	return f


static func _line(
		item: StringName, mode: Mode, style: TaStyle, look: TaTokens, src: StyleBox
	) -> Color:
	if _ACCENT_ITEMS.has(item) or mode == Mode.HEADER:
		return style.accent
	if _HOT_ITEMS.has(item):
		if style.accent.a > 0.0:
			return style.accent
		# Without an accent, a line that was the look's accent (a slot's hot line) stays.
		var spec: Dictionary = src.get_meta(TaChrome.SPEC_META, {})
		var was: Color = spec.get("line", CLEAR)
		if was.is_equal_approx(look.color_accent):
			return CLEAR
	return style.line


static func _was_accent(src: StyleBox, look: TaTokens) -> bool:
	var spec: Dictionary = src.get_meta(TaChrome.SPEC_META, {})
	if not spec.is_empty():
		return (spec["fill"] as Color).is_equal_approx(look.color_accent)
	return src is StyleBoxFlat and (src as StyleBoxFlat).bg_color.is_equal_approx(look.color_accent)


static func hover_of(style: TaStyle, look: TaTokens) -> Color:
	if style.fill_hover.a > 0.0:
		return style.fill_hover
	if style.fill.a <= 0.0:
		return CLEAR
	var toward := TaContrast.ink_on(look, style.fill)
	return Color(style.fill.lerp(toward, _HOVER_MIX), style.fill.a)


static func pressed_of(style: TaStyle) -> Color:
	if style.fill_pressed.a > 0.0:
		return style.fill_pressed
	if style.fill.a <= 0.0:
		return CLEAR
	return Color(style.fill.darkened(_PRESS_DARKEN), style.fill.a)


## Muted text: `body` moved toward `face` while it still reads at 4.5:1, else `body`.
static func quiet_of(body: Color, face: Color) -> Color:
	if face.a <= 0.0:
		return body
	var soft := body.lerp(Color(face, 1.0), _QUIET_MIX)
	if TaContrast.worst(soft, face) >= TaDefaults.MIN_TEXT_CONTRAST:
		return soft
	return body


## `src` drawn again with `fill` and `line` (alpha 0 keeps its own) and `width` (-1 keeps
## it): the same TaChrome role and state, on `look` at the box's own fit, with the box's
## padding. A box the kit did not make, or one made for another fit, is recoloured as it
## is (StyleBoxFlat) or left alone (null).
static func redraw(
		src: StyleBox, fill: Color, line: Color, width: int, look: TaTokens
	) -> StyleBox:
	var spec: Dictionary = src.get_meta(TaChrome.SPEC_META, {})
	if not spec.is_empty() and bool(spec["pixel"]) == look.is_pixel():
		var on_screen := TaThemeBuilder.screen(look, int(spec["art"]))
		if look.is_pixel() or is_equal_approx(on_screen.display_px, float(spec["px"])):
			var f: Color = fill if fill.a > 0.0 else spec["fill"]
			var l: Color = line if line.a > 0.0 else spec["line"]
			if width >= 0:
				on_screen.border_width = width_on(on_screen, width)
				on_screen.control_border = on_screen.border_width
			# A margin lets TaChrome clear a pixel frame (D62); the box keeps the look's padding.
			var role: TaChrome.Role = spec["role"]
			var bars := role == TaChrome.Role.TRACK or role == TaChrome.Role.FILL
			var clear := 1 if look.is_pixel() and not bars else 0
			var box := TaChrome.box(on_screen, role, f, l, clear, spec["state"])
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				var keep := maxf(src.get_content_margin(side), box.get_content_margin(side))
				box.set_content_margin(side, keep)
			return box
	if src is StyleBoxFlat:
		var flat := src.duplicate() as StyleBoxFlat
		if fill.a > 0.0:
			flat.bg_color = fill
		if line.a > 0.0:
			flat.border_color = line
		if width >= 0:
			flat.set_border_width_all(width_on(TaThemeBuilder.screen(look), width))
		return flat
	return null


## `width` in the look's units as on-screen px: art pixels times the art scale, or px at
## 1080 times the display scale (a line stays at least 1 px).
static func width_on(on_screen: TaTokens, width: int) -> int:
	if width <= 0:
		return 0
	if on_screen.is_pixel():
		return width * on_screen.art_scale()
	return maxi(1, roundi(width * on_screen.display_px))


## A target's own text colours ([colour item, face it sits on, quiet]). A label styled
## on its own takes only a text colour you set.
static func _ink_slots(target: Node) -> Array:
	if target is Button:
		return [
			[&"font_color", &"normal", false], [&"font_focus_color", &"normal", false],
			[&"font_hover_color", &"hover", false], [&"font_pressed_color", &"pressed", false],
			[&"font_hover_pressed_color", &"pressed", false],
		]
	if target is LineEdit or target is TextEdit:
		return [
			[&"font_color", &"normal", false], [&"font_placeholder_color", &"normal", true],
			[&"caret_color", &"normal", false],
		]
	if target is TabContainer or target is TabBar:
		return [
			[&"font_selected_color", &"tab_selected", false],
			[&"font_unselected_color", &"tab_unselected", true],
			[&"font_hovered_color", &"tab_hovered", false],
		]
	if target is ItemList:
		return [
			[&"font_color", &"panel", false], [&"font_selected_color", &"selected", false],
			[&"font_hovered_color", &"hovered", false],
		]
	if target is Tree:
		return [[&"font_color", &"panel", false], [&"font_selected_color", &"selected", false]]
	if target is Label:
		return [[&"font_color", &"", false]]
	if target is RichTextLabel:
		return [[&"default_color", &"", false]]
	return []


static func _paint_inks(
		target: Node, mode: Mode, style: TaStyle, look: TaTokens, faces: Dictionary
	) -> void:
	var old: Array = target.get_meta(INKS_META, [])
	var inks: Array[StringName] = []
	if mode == Mode.ITEM:
		for slot in _ink_slots(target):
			var face: Color = faces.get(slot[1], CLEAR)
			var c := style.ink
			if c.a <= 0.0 and face.a > 0.0:
				c = TaContrast.ink_on(look, face)
			if bool(slot[2]) and c.a > 0.0:
				c = quiet_of(c, face)
			if c.a > 0.0:
				target.add_theme_color_override(slot[0], c)
				inks.append(slot[0])
	if target is ProgressBar and not _value_hidden(target, old):
		# A stock bar's own value text (a TaBar or TaVBar draws its value itself).
		var v := style.value_ink
		if v.a <= 0.0 and style.accent.a > 0.0:
			v = TaContrast.ink_on(look, style.accent)
		if v.a > 0.0:
			target.add_theme_color_override(&"font_color", v)
			inks.append(&"font_color")
	for item: StringName in old:
		if not inks.has(item):
			target.remove_theme_color_override(item)
	target.set_meta(INKS_META, inks)


## A bar whose own text a TaBar or TaVBar hid (clear ink) draws its value itself.
static func _value_hidden(bar: Node, ours: Array) -> bool:
	if ours.has(&"font_color"):
		return false
	var c: Variant = bar.get("theme_override_colors/font_color")
	return c is Color and (c as Color).a <= 0.0


## What the item holds reads on its fill: a small Theme on the item with its text colours
## (labels added later take them too). A surface inside it with a fill of its own keeps the
## look's text colours. An item that already holds a Theme of its own keeps it.
static func _paint_text(
		target: Node, mode: Mode, style: TaStyle, look: TaTokens, face: Color
	) -> void:
	_unrestore(target)
	var ours := own_theme(target)
	var held: Theme = target.get("theme")
	if held != null and held != ours and not held.has_meta(RESTORE_META):
		return
	var body := style.ink
	if body.a <= 0.0 and face.a > 0.0 and mode != Mode.ROW:
		body = TaContrast.ink_on(look, face)
	if body.a <= 0.0:
		if ours != null and held == ours:
			target.set("theme", null)
		target.remove_meta(THEME_META)
		target.remove_meta(TEXT_META)
		return
	var quiet := quiet_of(body, face)
	var looks := themes(target)
	var text := Theme.new()
	var own := StringName(target.get("theme_type_variation"))
	var body_types: Array[StringName] = _BODY_TYPES.duplicate()
	if not own.is_empty():
		# Chips, tags, and toasts paint their label from their own type's ink.
		body_types.append(own)
	for type_name in body_types:
		_set_ink(text, type_name, body, look)
	for type_name in _QUIET_TYPES:
		_set_ink(text, type_name, quiet, look)
	for type_name in _label_types(looks):
		if body_types.has(type_name) or _QUIET_TYPES.has(type_name):
			continue
		if _TONE_TYPES.has(type_name) and face.a > 0.0:
			var tone: Color = look.get(_TONE_TYPES[type_name])
			_set_ink(text, type_name, TaContrast.tone_ink(tone, face), look)
		else:
			_copy_ink(text, looks, type_name)
	text.set_color(&"default_color", &"RichTextLabel", body)
	target.set_meta(THEME_META, text)
	target.set_meta(TEXT_META, [body, quiet])
	target.set("theme", text)
	if mode == Mode.ITEM:
		_restore_nested(target, looks)


static func _set_ink(text: Theme, type_name: StringName, ink: Color, look: TaTokens) -> void:
	text.set_color(&"font_color", type_name, ink)
	text.set_color(&"font_shadow_color", type_name, TaThemeBuilder.shadow_for(look, ink))


## The look's own text colours for `type_name`, so a recoloured Label does not hide them.
static func _copy_ink(text: Theme, looks: Array[Theme], type_name: StringName) -> void:
	for item in [&"font_color", &"font_shadow_color"]:
		for theme in looks:
			if theme.has_color(item, type_name):
				text.set_color(item, type_name, theme.get_color(item, type_name))
				break


## Every Label type the looks define (variations of variations included).
static func _label_types(looks: Array[Theme]) -> Array[StringName]:
	var out: Array[StringName] = []
	for theme in looks:
		for type_name in theme.get_type_variation_list(&"Label"):
			if not out.has(StringName(type_name)):
				out.append(StringName(type_name))
	return out


## Nested surfaces that draw a fill of their own get the look's text colours back. Nested
## styled items and their parts, and Themes of their own, are left be.
static func _restore_nested(target: Node, looks: Array[Theme]) -> void:
	var restored: Array = []
	var stack: Array[Node] = target.get_children()
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not node is Control:
			continue
		var nested := node as Control
		if nested.has_meta(STYLE_META) or nested.has_meta(OWNER_META) or nested.theme != null:
			continue
		var panel := nested is PanelContainer or nested is Panel
		if panel and _draws_fill(theme_box(nested, &"panel")):
			var inks := Theme.new()
			inks.set_meta(RESTORE_META, true)
			for type_name in [&"Label"] + _label_types(looks):
				_copy_ink(inks, looks, type_name)
			for theme in looks:
				if theme.has_color(&"default_color", &"RichTextLabel"):
					var rich := theme.get_color(&"default_color", &"RichTextLabel")
					inks.set_color(&"default_color", &"RichTextLabel", rich)
					break
			nested.theme = inks
			restored.append([nested, inks])
			continue
		stack.append_array(nested.get_children())
	target.set_meta(RESTORE_META, restored)


static func _unrestore(target: Node) -> void:
	for entry in target.get_meta(RESTORE_META, []):
		var nested := entry[0] as Control
		if is_instance_valid(nested) and nested.theme == entry[1]:
			nested.theme = null
	target.remove_meta(RESTORE_META)


static func _draws_fill(box: StyleBox) -> bool:
	if box is StyleBoxFlat:
		return (box as StyleBoxFlat).draw_center and (box as StyleBoxFlat).bg_color.a > 0.05
	return box is StyleBoxTexture and (box as StyleBoxTexture).texture != null


## The look's box for `item` on `target`, ignoring overrides (a style's own, a selected
## slot's): the nearest Theme up the tree that has it for the target's types, then the
## project theme, then Godot's default.
static func theme_box(target: Node, item: StringName) -> StyleBox:
	var looks := themes(target)
	var types := _types(target, looks)
	for theme in looks:
		for type_name in types:
			if theme.has_stylebox(item, type_name):
				return theme.get_stylebox(item, type_name)
	return null


## The Themes a target's look comes from, nearest first; its own style Theme left out.
static func themes(target: Node) -> Array[Theme]:
	var out: Array[Theme] = []
	var ours := own_theme(target)
	var node: Node = target
	while node != null:
		var theme: Theme = null
		if node is Control or node is Window:
			theme = node.get("theme")
		if theme != null and theme != ours and not out.has(theme):
			out.append(theme)
		node = node.get_parent()
	for theme in [ThemeDB.get_project_theme(), ThemeDB.get_default_theme()]:
		if theme != null and not out.has(theme):
			out.append(theme)
	return out


## The target's theme types, as Godot looks them up: its variation and the variation's
## bases, then its class and the classes it extends.
static func _types(target: Node, looks: Array[Theme]) -> Array[StringName]:
	var out: Array[StringName] = []
	var variation := StringName(target.get("theme_type_variation"))
	while not variation.is_empty() and not out.has(variation):
		out.append(variation)
		var base := &""
		for theme in looks:
			base = theme.get_type_variation_base(variation)
			if not base.is_empty():
				break
		variation = base
	var native := StringName(target.get_class())
	while not native.is_empty():
		out.append(native)
		native = ClassDB.get_parent_class(native)
	return out


static func _override(target: Node, item: StringName) -> StyleBox:
	return target.get("theme_override_styles/" + item) as StyleBox


## The text Theme a style put on `target`, or null.
static func own_theme(target: Node) -> Theme:
	return target.get_meta(THEME_META) as Theme if target.has_meta(THEME_META) else null
