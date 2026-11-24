extends Node

const TUNING_PATH := "res://data/tuning.json"

const KEY_BINDINGS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"sprint": KEY_SHIFT,
	"dash": KEY_SPACE,
	"pause": KEY_ESCAPE,
	"weapon_1": KEY_1,
	"weapon_2": KEY_2,
}

const MOUSE_BINDINGS := {
	"attack": MOUSE_BUTTON_LEFT,
	"weapon_next": MOUSE_BUTTON_WHEEL_DOWN,
	"weapon_prev": MOUSE_BUTTON_WHEEL_UP,
}

var data: Dictionary = {}


func _ready() -> void:
	_register_inputs()
	_load_tuning()


func value(section_name: String, key: String, fallback: Variant = null) -> Variant:
	var block: Dictionary = data.get(section_name, {})
	return block.get(key, fallback)


func section(section_name: String) -> Dictionary:
	return data.get(section_name, {})


func _load_tuning() -> void:
	var text := FileAccess.get_file_as_string(TUNING_PATH)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if parsed is Dictionary:
		data = parsed
	else:
		push_error("Tuning: 无法解析 %s" % TUNING_PATH)


func _register_inputs() -> void:
	for action: String in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_BINDINGS[action]
		InputMap.action_add_event(action, event)

	for action: String in MOUSE_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BINDINGS[action]
		InputMap.action_add_event(action, event)
