class_name LevelSelect
extends Control

## The campaign board: five acts on five rows, three stops each. A card carries the stop's number,
## its name and — only when a stop is held back — a lock. Built in code so it stays inside the menu
## look: a flat face, one hairline of gold, a filled tint on the chosen card.
##
## Emits [signal entered] with the scene to open and the stop's index; [signal closed] on Esc or the
## back button, and the menu takes the focus back.

signal entered(scene_path: String, level_index: int)
signal closed

const BOARD_WIDTH := 1040.0
const GUTTER_WIDTH := 26.0
const CARD_WIDTH := 312.0
const CARD_HEIGHT := 56.0
const COLUMN_GAP := 10.0
const ROW_GAP := 10.0
## How far a held-back stop is dimmed — under this it stops reading as a name, above it stops reading as closed.
const LOCKED_ALPHA := 0.70
const ROMAN := ["I", "II", "III", "IV", "V"]

var _cards: Array[Button] = []
var _enter_button: Button
var _back_button: Button
var _selected := 0

## Cursor to open on. Set it before the node enters the tree; -1 means the first open stop.
var initial_index := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_wire_focus()
	var start := initial_index if initial_index >= 0 else LevelBook.first_open()
	_select(start)
	_cards[start].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		accept_event()
		_close()


# ── Build ──────────────────────────────────────────────────────────────

func _build() -> void:
	var background := GoStyle.scrim(1.0, Color("#0B0C10"))
	background.name = "Background"
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var column := GoStyle.column(0)
	column.name = "Board"
	column.custom_minimum_size.x = BOARD_WIDTH
	center.add_child(column)

	MenuShell.title(column, "Fallen Gods", GoTheme.TEXT, 1.0)
	MenuShell.gap(column, GoTheme.GAP_LARGE)

	var grid := GoStyle.column(ROW_GAP)
	grid.name = "Acts"
	column.add_child(grid)
	for act in LevelBook.ACT_COUNT:
		grid.add_child(_build_row(act))

	MenuShell.gap(column, GoTheme.GAP_LARGE)
	column.add_child(GoStyle.divider(false))
	MenuShell.gap(column, GoTheme.GAP)
	column.add_child(_build_footer())


func _build_row(act: int) -> HBoxContainer:
	var row := GoStyle.row(COLUMN_GAP)
	row.name = "Act%d" % (act + 1)

	var mark := GoStyle.label(ROMAN[act], GoTheme.ROLE_CAPTION, Color(GoUi.color(GoTheme.ACCENT), 0.7))
	mark.name = "Mark"
	mark.custom_minimum_size.x = GUTTER_WIDTH
	mark.size_flags_horizontal = Control.SIZE_FILL
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(mark)

	row.add_child(GoStyle.divider(true))

	for slot in LevelBook.PER_ACT:
		row.add_child(_build_card(act * LevelBook.PER_ACT + slot))

	# Mirrors the act gutter so the three columns of cards sit optically centred on the page.
	var tail := GoStyle.spacer(0.0)
	tail.name = "Tail"
	tail.custom_minimum_size.x = GUTTER_WIDTH
	tail.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(tail)
	return row


func _build_card(index: int) -> Button:
	var card := Button.new()
	card.name = "L%02d" % (index + 1)
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	GoStyle.style_choice_card(card, GoUi.color(GoTheme.ACCENT), false, false, false)

	var body := GoStyle.card_body(card, 14, 0)

	var line := GoStyle.row(12)
	line.name = "Line"

	var number := GoStyle.label("%02d" % (index + 1), GoTheme.ROLE_CAPTION, GoUi.color(GoTheme.ACCENT))
	number.name = "Number"
	number.size_flags_horizontal = Control.SIZE_FILL
	number.custom_minimum_size.x = 24
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(number)

	var title := GoStyle.line(LevelBook.name_of(index), GoTheme.ROLE_BODY, GoUi.color(GoTheme.TEXT))
	title.name = "Name"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(title)

	line.add_child(GoStyle.spacer(8.0))

	var lock := GoUi.icons().node(GoIconSet.LOCK, 16, GoUi.color(GoTheme.MUTED))
	lock.name = "Lock"
	lock.size_flags_horizontal = Control.SIZE_SHRINK_END
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock.visible = LevelBook.locked(index)
	line.add_child(lock)

	body.add_child(line)
	GoStyle.let_input_through(body)
	if LevelBook.locked(index):
		card.modulate = Color(1.0, 1.0, 1.0, LOCKED_ALPHA)
	card.pressed.connect(_enter.bind(index))
	card.focus_entered.connect(_select.bind(index))
	_cards.append(card)
	return card


func _build_footer() -> HBoxContainer:
	var row := GoStyle.row(GoUi.metric(GoTheme.GAP))
	row.name = "Footer"

	row.add_child(GoStyle.spacer())

	_back_button = GoStyle.button("返回", _close, GoStyle.Tone.OUTLINED)
	_back_button.name = "Back"
	_back_button.custom_minimum_size.x = 88.0
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_back_button)

	_enter_button = GoStyle.button("进入关卡", _enter_selected, GoStyle.Tone.PRIMARY)
	_enter_button.name = "Enter"
	_enter_button.custom_minimum_size.x = 132.0
	_enter_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_enter_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_enter_button)
	return row


func _wire_focus() -> void:
	var last_act := LevelBook.ACT_COUNT - 1
	for index in _cards.size():
		var act := LevelBook.act_of(index)
		var slot := index % LevelBook.PER_ACT
		if act > 0:
			_cards[index].focus_neighbor_top = _card_path(index, index - LevelBook.PER_ACT)
		if act < last_act:
			_cards[index].focus_neighbor_bottom = _card_path(index, index + LevelBook.PER_ACT)
		if slot > 0:
			_cards[index].focus_neighbor_left = _card_path(index, index - 1)
		if slot < LevelBook.PER_ACT - 1:
			_cards[index].focus_neighbor_right = _card_path(index, index + 1)


func _card_path(from: int, to: int) -> NodePath:
	return _cards[from].get_path_to(_cards[to])


# ── State ──────────────────────────────────────────────────────────────

func _select(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	_selected = index
	for other in _cards.size():
		GoStyle.style_choice_card(_cards[other], GoUi.color(GoTheme.ACCENT), other == index, false, false)


func _enter_selected() -> void:
	_enter(_selected)


func _enter(index: int) -> void:
	_select(index)
	if LevelBook.locked(index):
		return
	entered.emit(LevelBook.scene_of(index), index)


func _close() -> void:
	closed.emit()
