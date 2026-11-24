class_name MenuShell
extends RefCounted

## Shared look for menu-like pages (main menu, pause, game over, victory):
## theme preset lookup, centered modal frame, titles, stat rows and hints.

const FALLBACK_PRESET := &"medieval_dark"
const PANEL_PAD_X := 40.0
const PANEL_PAD_Y := 32.0


static func apply_preset() -> void:
	if GoUi.preset() != null:
		return
	var id := FALLBACK_PRESET
	var tree := Engine.get_main_loop() as SceneTree
	var tuning := tree.root.get_node_or_null(^"Tuning") if tree != null else null
	if tuning != null and tuning.has_method(&"value"):
		var chosen: Variant = tuning.call(&"value", "ui", "theme_preset", String(FALLBACK_PRESET))
		if chosen is String or chosen is StringName:
			var text := String(chosen)
			if not text.is_empty():
				id = StringName(text)
	GoUi.use_preset(id)


## Full-screen scrim + centered panel. Returns the column to fill with content.
static func modal_frame(owner: CanvasLayer, scrim_color: Color, width: float) -> VBoxContainer:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	owner.add_child(root)

	if scrim_color.a > 0.0:
		var scrim := GoStyle.scrim(-1.0, scrim_color)
		scrim.name = "Scrim"
		scrim.mouse_filter = Control.MOUSE_FILTER_STOP
		root.add_child(scrim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := GoStyle.hud_panel(Color.TRANSPARENT, PANEL_PAD_X, PANEL_PAD_Y, GoTheme.BOX_PANEL)
	panel.name = "Panel"
	center.add_child(panel)

	return menu_column(panel, width)


static func menu_column(parent: Node, width: float) -> VBoxContainer:
	var column := GoStyle.column(GoUi.metric(GoTheme.GAP))
	column.name = "Menu"
	column.custom_minimum_size.x = width
	parent.add_child(column)
	return column


static func title(column: VBoxContainer, text: String, ink := GoTheme.TEXT, font_scale := 1.0) -> Label:
	var label := GoStyle.label(text, GoTheme.ROLE_BODY, GoUi.color(ink))
	label.name = "Title"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", roundi(GoUi.font_size(GoTheme.ROLE_TITLE) * font_scale))
	column.add_child(label)
	return label


static func subtitle(column: VBoxContainer, text: String, ink := GoTheme.SECONDARY) -> Label:
	var label := GoStyle.label(text, GoTheme.ROLE_MICRO, GoUi.color(ink))
	label.name = "Subtitle"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	return label


static func gap(column: VBoxContainer, token: StringName = GoTheme.GAP_SMALL) -> void:
	column.add_child(GoStyle.spacer(GoUi.metric(token)))


static func stat_row(column: VBoxContainer, label_text: String, value_text: String) -> HBoxContainer:
	var row := GoStyle.row(GoUi.metric(GoTheme.GAP_SMALL))
	row.name = "Stat"
	var key := GoStyle.label(label_text, GoTheme.ROLE_BODY, GoUi.color(GoTheme.MUTED))
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	var value := GoStyle.label(value_text, GoTheme.ROLE_BODY, GoUi.color(GoTheme.TEXT))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	column.add_child(row)
	return row


static func hint(column: VBoxContainer, text: String) -> Label:
	var label := GoStyle.label(text, GoTheme.ROLE_MICRO, GoUi.color(GoTheme.MUTED))
	label.name = "Hint"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	return label
