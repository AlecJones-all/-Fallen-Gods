class_name TaStyle
extends Resource

# AGENT: One item's own colours over the look. Core layer, opt-in: the expert path beside
# the Playground; the project look stays what Save wrote. apply() redraws an item (a panel,
# card, chip, tag, badge, toast, window, dialog, button, slot, field, slider, tab set, list,
# bar, dial, or label) in the look's own chrome with these colours. On a row, grid, strip,
# hotbar, feed, host, or overlay it styles each piece inside, pieces added later included.
# Widgets that draw their own colours (a dial's ring, a compass needle, a bar's value) read
# them with pick() and repaint in _ta_style_changed(). Drawing is in ta_style_paint.gd.
# INVARIANT: Unset colours (alpha 0; line_width -1) keep the look's. A styled box comes
# from the same TaChrome role and state as the look's box it replaces, with that box's
# padding, so the item keeps its shape and frame in every preset. Text the style does not
# colour is picked to read on the fill (4.5:1). An item is drawn again when its look, its
# fit, or its own theme type changes. clear() removes only what apply() added. A control
# nobody styles is never touched.
# DO NOT: Change the project theme, TaLook, or the look's tokens. Grow past colours into a
# Theme DSL (D13). Add children to the item (kit rows count their children).

## One item's own colours: a rarity card, a team colour, a red health dial. Everything you
## leave unset (alpha 0) keeps the look you saved, and the item keeps the look's shape,
## frame, and padding in every preset.
## [codeblock]
## var epic := TaStyle.make(Color("#3b2350"), Color("#b46cff"))
## TaStyle.apply(card, epic)
## [/codeblock]

const _Paint := preload("res://addons/theme_assist/src/core/ta_style_paint.gd")
## Meta on a box a widget keeps as its own colour (TaIconGrid's tiles): a style leaves it.
const KEEP_META := &"ta_keep"
const _KEY_META := &"ta_style_key"
const _BUSY_META := &"ta_style_busy"
const _HOOK_META := &"ta_style_hook"
const _PARTS_META := &"ta_style_parts"
const _WATCH_META := &"ta_style_watch"
const _PENDING_META := &"ta_style_pending"
const _RETRY_META := &"ta_style_retry"
## What a widget that draws its own colours implements: it repaints, reading pick().
const _HOOK := &"_ta_style_changed"
const _CLEAR := Color(0, 0, 0, 0)

## Background: a panel's or card's fill, a button's or slot's face, a field's well.
@export var fill: Color = Color(0, 0, 0, 0)
## Face of a hovered button, slot, tab, or row. Unset: fill, moved a little toward its text.
@export var fill_hover: Color = Color(0, 0, 0, 0)
## Face of a pressed button, a selected slot, a selected row, an idle tab. Unset: fill,
## darkened.
@export var fill_pressed: Color = Color(0, 0, 0, 0)
## Border and frame line.
@export var line: Color = Color(0, 0, 0, 0)
## Border width, in the look's units: px at 1080 on Flat and Modern, art pixels on Framed
## and Pixel. -1 keeps the look's; 0 is none. Flat, Modern, and Pixel cards have no border
## of their own, so a rarity line needs one. Pixel-look buttons and tags keep their edge.
@export_range(-1, 8) var line_width: int = -1
## The value: a bar's or dial's fill, a slider's filled part, a compass needle, a
## vignette's colour, a hit marker; the line of a hovered, pressed, or selected piece; a
## selected card's, row's, or tab's face where the look fills it with its accent.
@export var accent: Color = Color(0, 0, 0, 0)
## The empty part of a bar, dial, or slider. Unset: the look's (on a bar or slider styled on
## its own, the fill).
@export var track: Color = Color(0, 0, 0, 0)
## Text on the item. Unset: the look's text or page colour, whichever reads on fill.
@export var ink: Color = Color(0, 0, 0, 0)
## Text on a bar or dial: a TaBar's "72/100", a TaRadial's centre. Unset: picked to read
## on the fill and on the track.
@export var value_ink: Color = Color(0, 0, 0, 0)


## A style from colours; leave any of them out to keep the look's.
static func make(
		fill_color: Color,
		line_color: Color = _CLEAR,
		accent_color: Color = _CLEAR,
		ink_color: Color = _CLEAR
	) -> TaStyle:
	var style := TaStyle.new()
	style.fill = fill_color
	style.line = line_color
	style.accent = accent_color
	style.ink = ink_color
	return style


## Wear `style` on `item` (a Control, or a popup such as TaDialog). Text inside takes the
## style's text colour. Call again to switch styles; null clears. Off-tree it waits, and
## draws when the item enters the tree. After you edit a style, call refresh() or apply().
static func apply(item: Node, style: TaStyle) -> void:
	if not _styleable(item):
		return
	if style == null:
		clear(item)
		return
	item.set_meta(_Paint.STYLE_META, style)
	if not item.has_meta(_HOOK_META):
		var hook := func() -> void: _refresh(item, false)
		item.connect(&"theme_changed", hook)
		item.set_meta(_HOOK_META, hook)
	_refresh(item, true)


## The style `item` wears itself, or null (a piece styled through its row has none).
static func of(item: Node) -> TaStyle:
	if not is_instance_valid(item) or not item.has_meta(_Paint.STYLE_META):
		return null
	return item.get_meta(_Paint.STYLE_META) as TaStyle


## Draw again: after you edit a style, or rebuild what a styled item holds. A piece styled
## through its row redraws the row.
static func refresh(node: Node) -> void:
	var owner := _owner_of(node)
	if owner != null:
		_refresh(owner, true)


## The colour `field` of the style `node` wears, itself or through the item it belongs to,
## or `fallback` (the look's) when it sets none. For widgets that draw their own colours.
## Besides the fields: &"body_ink" and &"quiet_ink", the text colours a style picked for
## the node's fill.
static func pick(node: Node, field: StringName, fallback: Color) -> Color:
	var owner := _owner_of(node)
	if owner == null:
		return fallback
	if field == &"body_ink" or field == &"quiet_ink":
		for at in [node, owner]:
			if is_instance_valid(at) and at.has_meta(_Paint.TEXT_META):
				var text: Array = at.get_meta(_Paint.TEXT_META)
				return text[0] if field == &"body_ink" else text[1]
		return fallback
	var value: Variant = of(owner).get(field)
	if value is Color and (value as Color).a > 0.0:
		return value
	return fallback


## Back to the look: remove everything apply() added to `item` and the pieces it styled.
static func clear(item: Node) -> void:
	if not is_instance_valid(item):
		return
	var parts: Array = item.get_meta(_PARTS_META, [])
	for target in parts:
		if is_instance_valid(target):
			_Paint.unpaint(target)
	_unwatch(item)
	if item.has_meta(_HOOK_META):
		var hook: Callable = item.get_meta(_HOOK_META)
		if item.is_connected(&"theme_changed", hook):
			item.disconnect(&"theme_changed", hook)
	for meta in [
		_Paint.STYLE_META, _KEY_META, _BUSY_META, _HOOK_META, _PARTS_META, _RETRY_META,
		_PENDING_META,
	]:
		item.remove_meta(meta)
	_notify(item, parts)


## Text colours you set that fall under 4.5:1, one line each; empty means they read. Text
## you leave unset is always picked to read. `look` defaults to the bound look.
func check(look: TaTokens = null) -> PackedStringArray:
	var out := PackedStringArray()
	var bound := look if look != null else TaLook.current()
	var pairs: Array = []
	if ink.a > 0.0:
		for face_name in ["fill", "fill_hover", "fill_pressed"]:
			var face := fill
			if face_name == "fill_hover":
				face = _Paint.hover_of(self, bound)
			elif face_name == "fill_pressed":
				face = _Paint.pressed_of(self)
			pairs.append(["ink", ink, face_name, face])
	if value_ink.a > 0.0:
		pairs.append(["value_ink", value_ink, "accent", accent])
		pairs.append(["value_ink", value_ink, "track", track])
	for pair in pairs:
		var face: Color = pair[3]
		if face.a <= 0.0:
			continue
		var ratio := TaContrast.worst(pair[1], face)
		if ratio < TaDefaults.MIN_TEXT_CONTRAST:
			out.append("%s on %s: %.2f < %.1f" % [
				pair[0], pair[2], ratio, TaDefaults.MIN_TEXT_CONTRAST])
	return out


static func _styleable(item: Node) -> bool:
	return is_instance_valid(item) and (item is Control or item is Window)


static func _refresh(item: Node, force: bool) -> void:
	if not is_instance_valid(item) or bool(item.get_meta(_BUSY_META, false)):
		return
	var style := of(item)
	if style == null or not item.is_inside_tree():
		return
	var key := _key_of(item)
	if not force and key == String(item.get_meta(_KEY_META, "")):
		return
	item.set_meta(_BUSY_META, true)
	var look := TaContrast.settle_glass(TaLook.look_around(item))
	var found := _collect(item)
	var targets: Array = []
	for entry in found["targets"]:
		targets.append(entry[0])
	for old in item.get_meta(_PARTS_META, []):
		if is_instance_valid(old) and not targets.has(old):
			_Paint.unpaint(old)
	# Pieces are marked before any is drawn, so an item does not hand its own title bar
	# the look's text back.
	for target in targets:
		if target != item:
			target.set_meta(_Paint.OWNER_META, item)
	var stale := false
	for entry in found["targets"]:
		stale = _Paint.paint(entry[0], entry[1], style, look) or stale
	item.set_meta(_PARTS_META, targets)
	_watch(item, found["watch"])
	_notify(item, targets)
	item.set_meta(_BUSY_META, false)
	if not stale:
		item.set_meta(_KEY_META, _key_of(item))
		item.remove_meta(_RETRY_META)
		return
	# The look around the item is not the one its boxes were made for yet: apply_to sets
	# the Theme before it records the look. Keep the old boxes and try once more next frame.
	item.set_meta(_KEY_META, "")
	if not bool(item.get_meta(_RETRY_META, false)):
		item.set_meta(_RETRY_META, true)
		_refresh_later(item, false)


## What a style paints on `item`: {targets: [[node, mode]], watch: [rows to watch]}. A
## surface is painted with the title bars, gauges, and tab sets inside it; a row, grid, or
## overlay paints each surface it holds; a label takes its text colour.
static func _collect(item: Node) -> Dictionary:
	var targets: Array = []
	var watch: Array = [item]
	if _Paint.is_surface(item):
		_collect_surface(item, targets, watch)
	elif item is Label or item is RichTextLabel:
		targets.append([item, _Paint.Mode.ITEM])
	else:
		targets.append([item, _Paint.Mode.ROW])
		var stack: Array[Node] = item.get_children()
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node.has_meta(_Paint.STYLE_META) or node is Window:
				continue
			if _Paint.is_surface(node):
				_collect_surface(node, targets, watch)
			elif not (node is Label or node is RichTextLabel):
				watch.append(node)
				stack.append_array(node.get_children())
	return {"targets": targets, "watch": watch}


static func _collect_surface(surface: Node, targets: Array, watch: Array) -> void:
	targets.append([surface, _Paint.Mode.ITEM])
	var stack: Array[Node] = surface.get_children()
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta(_Paint.STYLE_META) or node is Window:
			continue
		var header := node is PanelContainer and _Paint.HEADERS.has(
				StringName((node as PanelContainer).theme_type_variation)
		)
		if node is ProgressBar:
			targets.append([node, _Paint.Mode.BAR])
		elif header:
			targets.append([node, _Paint.Mode.HEADER])
		elif node is TabContainer:
			targets.append([node, _Paint.Mode.ITEM])
		elif not _Paint.is_surface(node):
			if not (node is Label or node is RichTextLabel):
				watch.append(node)
			stack.append_array(node.get_children())


## Pieces added to a styled row later (a hotbar rebuilt, a feed line, a toast) are styled
## on the next frame.
static func _watch(item: Node, nodes: Array) -> void:
	_unwatch(item)
	var hook := func(_node: Node) -> void: _schedule(item)
	var watched: Array = []
	for node in nodes:
		if is_instance_valid(node) and not node.child_entered_tree.is_connected(hook):
			node.child_entered_tree.connect(hook)
			watched.append(node)
	item.set_meta(_WATCH_META, [hook, watched])


static func _unwatch(item: Node) -> void:
	if not item.has_meta(_WATCH_META):
		return
	var entry: Array = item.get_meta(_WATCH_META)
	for node in entry[1]:
		if is_instance_valid(node) and node.child_entered_tree.is_connected(entry[0]):
			node.child_entered_tree.disconnect(entry[0])
	item.remove_meta(_WATCH_META)


static func _schedule(item: Node) -> void:
	if not is_instance_valid(item) or bool(item.get_meta(_PENDING_META, false)):
		return
	item.set_meta(_PENDING_META, true)
	_refresh_later(item, true)


## Next frame, if the node is still alive. The id is a number, so a free before
## that frame does not log "Lambda capture was freed".
static func _refresh_later(item: Node, clear_pending: bool) -> void:
	var id := item.get_instance_id()
	(func() -> void:
		var node := instance_from_id(id) as Node
		if node == null:
			return
		if clear_pending:
			node.remove_meta(_PENDING_META)
		_refresh(node, true)
	).call_deferred()


## Widgets that draw their own colours repaint (they read pick()).
static func _notify(item: Node, targets: Array) -> void:
	var told: Array = []
	for node in [item] + targets:
		if is_instance_valid(node) and node.has_method(_HOOK) and not told.has(node):
			told.append(node)
			node.call(_HOOK)


## The item that styles `node`: itself, or the item it was styled through. Null if none.
static func _owner_of(node: Node) -> Node:
	if not is_instance_valid(node):
		return null
	if node.has_meta(_Paint.STYLE_META):
		return node
	if node.has_meta(_Paint.OWNER_META):
		var owner: Variant = node.get_meta(_Paint.OWNER_META)
		if is_instance_valid(owner) and (owner as Node).has_meta(_Paint.STYLE_META):
			return owner
	return null


## Which look, fit, and theme type the item was last drawn for: the Themes above it (its
## own counts unless the style set it), its theme type, and the bound look.
static func _key_of(item: Node) -> String:
	var parts := PackedStringArray([String(item.get("theme_type_variation"))])
	var ours := _Paint.own_theme(item)
	var node: Node = item
	while node != null:
		var theme: Theme = null
		if node is Control or node is Window:
			theme = node.get("theme")
		if theme != null and theme != ours:
			parts.append("%d %s" % [theme.get_instance_id(), _fit(theme)])
		node = node.get_parent()
	var project := ThemeDB.get_project_theme()
	if project != null:
		parts.append("p%d %s" % [project.get_instance_id(), _fit(project)])
	parts.append("l%d" % (TaLook.active.get_instance_id() if TaLook.active != null else 0))
	return ",".join(parts)


## The display fit a kit Theme was made for ("" for any other Theme).
static func _fit(theme: Theme) -> String:
	return String(theme.get_meta(TaThemeBuilder.FIT_META, ""))
