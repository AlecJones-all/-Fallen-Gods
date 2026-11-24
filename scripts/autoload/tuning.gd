extends Node

const TUNING_PATH := "res://data/tuning.json"

const BINDINGS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"sprint": KEY_SHIFT,
	"dash": KEY_SPACE,
	"pause": KEY_ESCAPE,
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
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = BINDINGS[action]
		InputMap.action_add_event(action, event)
